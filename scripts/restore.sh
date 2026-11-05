#!/usr/bin/env bash
# Odtworzenie instancji Silo z backupu scripts/backup.sh (stos docker compose).
#
# Uzycie: scripts/restore.sh metadata FILE.json [--merge]
#         scripts/restore.sh full FILE.dump [BLOBS.tar.gz] [--yes]
#   metadata  na uruchomionym stosie z PUSTA baza (bez uzytkownikow; --merge: do istniejacych):
#             `migrate up`, potem `silo-server import-metadata`. Konta startuja initial sync;
#             etykiety uzytkownika i snooze wracaja w miare synchronizacji (job metadata_restore).
#   full      zatrzymuje silo-server, pg_restore --clean --if-exists calej bazy, opcjonalnie
#             zastepuje zawartosc wolumenu blobow archiwum, uruchamia silo-server.
#             Nadpisuje dane: pyta o potwierdzenie (--yes pomija pytanie; wymagane bez terminala).
# Srodowisko: SILO_COMPOSE_FILE (domyslnie docker-compose.yml), COMPOSE_PROJECT_NAME (jak w compose),
#   SILO_TAR_IMAGE (domyslnie alpine:3.22), SILO_BLOBS_VOLUME (nazwa wolumenu, gdy nie da sie jej ustalic).
# Wymaga tego samego SILO_SECRET_KEY co instancja, z ktorej pochodzi backup (hasla skrzynek i TOTP
# sa nim zaszyfrowane). Gdy obok pliku lezy FILE.sha256, suma jest sprawdzana.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export MSYS_NO_PATHCONV=1 # Git Bash na Windows nie moze "poprawiac" sciezek w argumentach docker

COMPOSE=(docker compose -f "${SILO_COMPOSE_FILE:-docker-compose.yml}")
TAR_IMAGE="${SILO_TAR_IMAGE:-alpine:3.22}"
MODE=""
FILES=()
MERGE=0
YES=0

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; }
die() { echo "restore: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help) usage; exit 0 ;;
    --merge) MERGE=1 ;;
    --yes) YES=1 ;;
    -*) echo "Nieznana opcja: $1" >&2; usage >&2; exit 2 ;;
    *)
      if [ -z "$MODE" ]; then MODE="$1"; else FILES+=("$1"); fi
      ;;
  esac
  shift
done

case "$MODE" in
  metadata) [ ${#FILES[@]} -eq 1 ] || { usage >&2; exit 2; } ;;
  full)
    [ ${#FILES[@]} -ge 1 ] && [ ${#FILES[@]} -le 2 ] || { usage >&2; exit 2; }
    [ "$MERGE" = 0 ] || die "--merge dziala tylko w trybie metadata"
    ;;
  *) usage >&2; exit 2 ;;
esac
for f in "${FILES[@]}"; do
  [ -f "$f" ] || die "brak pliku $f"
done

verify_checksum() {
  local f="$1" dir base
  [ -f "$f.sha256" ] || return 0
  dir="$(dirname "$f")"
  base="$(basename "$f")"
  if command -v sha256sum > /dev/null 2>&1; then
    (cd "$dir" && sha256sum -c --status "$base.sha256") || die "suma kontrolna $f nie zgadza sie z $f.sha256"
  else
    (cd "$dir" && shasum -a 256 -c -s "$base.sha256") || die "suma kontrolna $f nie zgadza sie z $f.sha256"
  fi
  echo "suma kontrolna $f: OK"
}

running() { [ -n "$("${COMPOSE[@]}" ps --status running -q "$1")" ]; }

psql_q() {
  # shellcheck disable=SC2016 # zmienne rozwija powloka kontenera postgres
  "${COMPOSE[@]}" exec -T postgres sh -c 'psql -X -q -tA -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "$1"' sh "$1"
}

# Obraz prod jest distroless (bez powloki): exec bezposrednio na binarce.
silo_cli() { "${COMPOSE[@]}" exec -T silo-server /silo-server "$@"; }

blobs_volume() {
  local cid vol="" project
  if [ -n "${SILO_BLOBS_VOLUME:-}" ]; then echo "$SILO_BLOBS_VOLUME"; return; fi
  cid="$("${COMPOSE[@]}" ps -aq silo-server 2> /dev/null | head -n1 || true)"
  if [ -n "$cid" ]; then
    vol="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/data/blobs"}}{{.Name}}{{end}}{{end}}' "$cid")"
  fi
  if [ -z "$vol" ]; then
    project="${COMPOSE_PROJECT_NAME:-$("${COMPOSE[@]}" config --format json | sed -n 's/^  "name": "\(.*\)",$/\1/p' | head -n1)}"
    vol="$(docker volume ls -q --filter "label=com.docker.compose.project=$project" --filter label=com.docker.compose.volume=blobs | head -n1)"
  fi
  echo "$vol"
}

running postgres || die "postgres nie dziala (${COMPOSE[*]} up -d postgres)"
for f in "${FILES[@]}"; do verify_checksum "$f"; done

if [ "$MODE" = metadata ]; then
  running silo-server || die "silo-server nie dziala (${COMPOSE[*]} up -d)"
  # serve stosuje migracje przy starcie; `migrate up` jest idempotentne i gwarantuje schemat.
  silo_cli migrate up > /dev/null || die "migrate up nie powiodlo sie"
  echo "schemat: $(silo_cli migrate version | tr -d '\r')"
  users="$(psql_q 'SELECT count(*) FROM users' | tr -d '\r ')"
  if [ "$users" != 0 ] && [ "$MERGE" = 0 ]; then
    die "baza ma juz $users uzytkownikow: odtwarzaj na pusta baze albo dodaj --merge"
  fi
  imp=(import-metadata --in -)
  [ "$MERGE" = 0 ] || imp+=(--merge)
  silo_cli "${imp[@]}" < "${FILES[0]}" ||
    die "import-metadata nie powiodl sie (ten sam SILO_SECRET_KEY co przy eksporcie?)"
  echo "Gotowe. Konta synchronizuja sie od nowa; etykiety uzytkownika i snooze wroca po zakonczeniu"
  echo "initial sync (job metadata_restore). Wiadomosci zaplanowane wrocily do kolejki na swoj czas."
  exit 0
fi

# full
if [ "$YES" = 0 ]; then
  [ -t 0 ] || die "tryb full nadpisuje baze (i bloby): potwierdz flaga --yes"
  printf 'Nadpisac baze%s danymi z backupu? [y/N] ' "$([ ${#FILES[@]} -eq 2 ] && echo ' i bloby')"
  read -r answer
  case "$answer" in y | Y | t | T) ;; *) die "przerwano" ;; esac
fi

if running silo-server; then
  echo "zatrzymuje silo-server..."
  "${COMPOSE[@]}" stop silo-server > /dev/null
fi
echo "pg_restore ${FILES[0]}..."
# shellcheck disable=SC2016 # zmienne rozwija powloka kontenera postgres
"${COMPOSE[@]}" exec -T postgres sh -c 'pg_restore --clean --if-exists --no-owner -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < "${FILES[0]}" ||
  die "pg_restore nie powiodl sie (silo-server pozostaje zatrzymany)"

if [ ${#FILES[@]} -eq 2 ]; then
  # Kontener (i wolumen) moze jeszcze nie istniec: utworz bez uruchamiania.
  [ -n "$("${COMPOSE[@]}" ps -aq silo-server)" ] || "${COMPOSE[@]}" up --no-start silo-server > /dev/null
  vol="$(blobs_volume)"
  [ -n "$vol" ] || die "nie znaleziono wolumenu blobow; ustaw SILO_BLOBS_VOLUME"
  echo "bloby ${FILES[1]} -> wolumen $vol..."
  docker run --rm -i -v "$vol:/data" "$TAR_IMAGE" sh -c 'find /data -mindepth 1 -delete && tar xzf - -C /data' < "${FILES[1]}" ||
    die "rozpakowanie blobow nie powiodlo sie (silo-server pozostaje zatrzymany)"
fi

"${COMPOSE[@]}" up -d silo-server > /dev/null
echo "Gotowe: baza odtworzona, silo-server uruchomiony."

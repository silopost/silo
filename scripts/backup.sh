#!/usr/bin/env bash
# Backup instancji Silo uruchomionej przez docker compose (plan 2.1, 3.16, 4.1).
#
# Uzycie: scripts/backup.sh [metadata|full] [--out DIR] [--user EMAIL] [-h|--help]
#   metadata (domyslnie)  `silo-server export-metadata`: JSON z metadanymi, ktorych nie ma na
#                         serwerze IMAP (uzytkownicy, konta, etykiety i ich przypisania, snooze,
#                         filtry, kontakty, drafty i wiadomosci zaplanowane z zalacznikami).
#                         Cache poczty odtworzy synchronizacja. Plik: DIR/silo-metadata-<ts>.json.
#   full                  pg_dump -Fc calej bazy (DIR/silo-db-<ts>.dump) + tar.gz katalogu blobow
#                         (DIR/silo-blobs-<ts>.tar.gz; mirror to cache, ale pelny backup go
#                         zachowuje i oszczedza resync). Przy SILO_BLOB_BACKEND=s3 bucket
#                         archiwizuje sie osobno.
# Opcje: --out DIR (domyslnie backups/), --user EMAIL (tylko metadata: jeden uzytkownik).
# Srodowisko: SILO_COMPOSE_FILE (domyslnie docker-compose.yml), COMPOSE_PROJECT_NAME (jak w compose),
#   SILO_BACKUP_WAIT (s, domyslnie 60: czekanie na pusta kolejke imap_op przed eksportem),
#   SILO_TAR_IMAGE (domyslnie alpine:3.22, obraz do archiwizacji wolumenu blobow).
# Do kazdego pliku powstaje plik .sha256. SILO_SECRET_KEY NIE jest w backupie: przechowuj go
# osobno; odtworzenie wymaga tego samego klucza.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export MSYS_NO_PATHCONV=1 # Git Bash na Windows nie moze "poprawiac" sciezek w argumentach docker

COMPOSE=(docker compose -f "${SILO_COMPOSE_FILE:-docker-compose.yml}")
MODE=metadata
OUT_DIR=backups
USER_EMAIL=""
WAIT_S="${SILO_BACKUP_WAIT:-60}"
TAR_IMAGE="${SILO_TAR_IMAGE:-alpine:3.22}"

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; }
die() { echo "backup: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    metadata | full) MODE="$1" ;;
    --out)
      [ $# -ge 2 ] || die "--out wymaga katalogu"
      OUT_DIR="$2"
      shift
      ;;
    --user)
      [ $# -ge 2 ] || die "--user wymaga adresu"
      USER_EMAIL="$2"
      shift
      ;;
    -h | --help) usage; exit 0 ;;
    *) echo "Nieznana opcja: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
[ "$MODE" = metadata ] || [ -z "$USER_EMAIL" ] || die "--user dziala tylko w trybie metadata"

# psql w kontenerze postgres (uzytkownik i baza z jego srodowiska).
psql_q() {
  # shellcheck disable=SC2016 # zmienne rozwija powloka kontenera postgres
  "${COMPOSE[@]}" exec -T postgres sh -c 'psql -X -q -tA -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "$1"' sh "$1"
}

size_of() { wc -c < "$1" | tr -d ' '; }

checksum() {
  local f="$1" dir base
  dir="$(dirname "$f")"
  base="$(basename "$f")"
  if command -v sha256sum > /dev/null 2>&1; then
    (cd "$dir" && sha256sum "$base" > "$base.sha256")
  else
    (cd "$dir" && shasum -a 256 "$base" > "$base.sha256")
  fi
}

# Wolumen z katalogiem blobow: z montowan kontenera silo-server, inaczej po etykietach compose.
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

[ -n "$("${COMPOSE[@]}" ps --status running -q postgres)" ] || die "postgres nie dziala (${COMPOSE[*]} up -d)"
mkdir -p "$OUT_DIR"
TS="$(date -u +%Y%m%dT%H%M%SZ)"

if [ "$MODE" = metadata ]; then
  [ -n "$("${COMPOSE[@]}" ps --status running -q silo-server)" ] || die "silo-server nie dziala (${COMPOSE[*]} up -d)"
  # Oczekujace operacje write-back (imap_op, np. archiwizacja w oknie undo) nie trafiaja do backupu.
  q="SELECT count(*) FROM jobs WHERE kind = 'imap_op' AND status IN ('pending', 'running')"
  waited=0
  while :; do
    pending="$(psql_q "$q" | tr -d '\r ')"
    [ "$pending" = 0 ] && break
    if [ "$waited" -ge "$WAIT_S" ]; then
      echo "UWAGA: po ${WAIT_S} s w kolejce nadal $pending operacji imap_op; nie beda w backupie." >&2
      break
    fi
    [ "$waited" -eq 0 ] && echo "Czekam na zapis $pending operacji imap_op na serwer IMAP (do ${WAIT_S} s)..."
    sleep 2
    waited=$((waited + 2))
  done

  file="$OUT_DIR/silo-metadata-$TS.json"
  args=(export-metadata --out -)
  [ -n "$USER_EMAIL" ] && args+=(--user "$USER_EMAIL")
  # Obraz prod jest distroless (bez powloki): exec bezposrednio na binarce.
  if ! "${COMPOSE[@]}" exec -T silo-server /silo-server "${args[@]}" > "$file.part"; then
    rm -f "$file.part"
    die "export-metadata nie powiodl sie"
  fi
  mv "$file.part" "$file"
  checksum "$file"
  echo "metadata: $file ($(size_of "$file") B)"
else
  db="$OUT_DIR/silo-db-$TS.dump"
  # shellcheck disable=SC2016 # zmienne rozwija powloka kontenera postgres
  if ! "${COMPOSE[@]}" exec -T postgres sh -c 'pg_dump -Fc -U "$POSTGRES_USER" -d "$POSTGRES_DB"' > "$db.part"; then
    rm -f "$db.part"
    die "pg_dump nie powiodl sie"
  fi
  mv "$db.part" "$db"
  checksum "$db"
  echo "baza:  $db ($(size_of "$db") B)"

  vol="$(blobs_volume)"
  if [ -z "$vol" ]; then
    echo "UWAGA: nie znaleziono wolumenu blobow (/data/blobs); przy SILO_BLOB_BACKEND=s3 archiwizuj bucket osobno." >&2
  else
    blobs="$OUT_DIR/silo-blobs-$TS.tar.gz"
    if ! docker run --rm -v "$vol:/data:ro" "$TAR_IMAGE" tar czf - -C /data . > "$blobs.part"; then
      rm -f "$blobs.part"
      die "archiwizacja wolumenu $vol nie powiodla sie"
    fi
    mv "$blobs.part" "$blobs"
    checksum "$blobs"
    echo "bloby: $blobs ($(size_of "$blobs") B, wolumen $vol)"
  fi
fi

echo "Pamietaj: SILO_SECRET_KEY nie jest w backupie; przechowuj go osobno, odtworzenie wymaga tego samego klucza."

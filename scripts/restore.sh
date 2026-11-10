#!/usr/bin/env bash
# Restores a Silo instance from a scripts/backup.sh backup (docker compose stack).
#
# Usage: scripts/restore.sh metadata FILE.json [--merge]
#        scripts/restore.sh full FILE.dump [BLOBS.tar.gz] [--yes]
#   metadata  on a running stack with an EMPTY database (no users; --merge: into existing ones):
#             `migrate up`, then `silo-server import-metadata`. Accounts start an initial sync;
#             user labels and snoozes come back as synchronization progresses (job metadata_restore).
#   full      stops silo-server, pg_restore --clean --if-exists of the whole database, optionally
#             replaces the contents of the blob volume with the archive, starts silo-server.
#             Overwrites data: asks for confirmation (--yes skips the question; required without a terminal).
# Environment: SILO_COMPOSE_FILE (default: COMPOSE_FILE from .env, else docker-compose.yml), COMPOSE_PROJECT_NAME (as in compose),
#   SILO_TAR_IMAGE (default alpine:3.22), SILO_BLOBS_VOLUME (the volume name, when it cannot be determined).
# Requires the same SILO_SECRET_KEY as the instance the backup comes from (mailbox passwords and TOTP
# are encrypted with it). When FILE.sha256 lies next to the file, the checksum is verified.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export MSYS_NO_PATHCONV=1 # Git Bash on Windows must not "fix" paths in docker arguments

# SILO_COMPOSE_FILE: one file or a ":"-separated list (e.g. docker-compose.yml:deploy/http/docker-compose.yml).
# Unset: plain `docker compose`, which takes COMPOSE_FILE from the environment or .env (the production
# variant), otherwise docker-compose.yml. Recreating silo-server (restore) needs the variant files.
COMPOSE=(docker compose)
if [ -n "${SILO_COMPOSE_FILE:-}" ]; then
  IFS=: read -ra compose_files <<< "$SILO_COMPOSE_FILE"
  for compose_file in "${compose_files[@]}"; do COMPOSE+=(-f "$compose_file"); done
fi
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

# A command without compose progress noise; output shown only on error.
quiet() {
  local out
  out="$("$@" 2>&1)" || { printf "%s
" "$out" >&2; return 1; }
}

running() { [ -n "$("${COMPOSE[@]}" ps --status running -q "$1")" ]; }

psql_q() {
  # shellcheck disable=SC2016 # the postgres container's shell expands the variables
  "${COMPOSE[@]}" exec -T postgres sh -c 'psql -X -q -tA -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "$1"' sh "$1"
}

# The prod image is distroless (no shell): exec the binary directly.
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
  # serve applies migrations at start-up; `migrate up` is idempotent and guarantees the schema.
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
  quiet "${COMPOSE[@]}" stop silo-server
fi
echo "pg_restore ${FILES[0]}..."
# shellcheck disable=SC2016 # the postgres container's shell expands the variables
"${COMPOSE[@]}" exec -T postgres sh -c 'pg_restore --clean --if-exists --no-owner -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < "${FILES[0]}" ||
  die "pg_restore nie powiodl sie (silo-server pozostaje zatrzymany)"

if [ ${#FILES[@]} -eq 2 ]; then
  # The container (and the volume) may not exist yet: create it without starting.
  [ -n "$("${COMPOSE[@]}" ps -aq silo-server)" ] || quiet "${COMPOSE[@]}" up --no-start silo-server
  vol="$(blobs_volume)"
  [ -n "$vol" ] || die "nie znaleziono wolumenu blobow; ustaw SILO_BLOBS_VOLUME"
  echo "bloby ${FILES[1]} -> wolumen $vol..."
  docker run --rm -i -v "$vol:/data" "$TAR_IMAGE" sh -c 'find /data -mindepth 1 -delete && tar xzf - -C /data' < "${FILES[1]}" ||
    die "rozpakowanie blobow nie powiodlo sie (silo-server pozostaje zatrzymany)"
fi

quiet "${COMPOSE[@]}" up -d silo-server || die "start silo-server nie powiodl sie"
echo "Gotowe: baza odtworzona, silo-server uruchomiony."

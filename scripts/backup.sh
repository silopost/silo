#!/usr/bin/env bash
# Backup of a Silo instance run with docker compose.
#
# Usage: scripts/backup.sh [metadata|full] [--out DIR] [--user EMAIL] [-h|--help]
#   metadata (default)    `silo-server export-metadata`: JSON with the metadata that is not on
#                         the IMAP server (users, accounts, labels and their assignments, snoozes,
#                         filters, contacts, drafts and scheduled messages with attachments).
#                         Synchronization restores the mail cache. File: DIR/silo-metadata-<ts>.json.
#   full                  pg_dump -Fc of the whole database (DIR/silo-db-<ts>.dump) + tar.gz of the
#                         blob directory (DIR/silo-blobs-<ts>.tar.gz; the mirror is a cache, but a
#                         full backup keeps it and saves a resync). With SILO_BLOB_BACKEND=s3 the
#                         bucket is archived separately.
# Options: --out DIR (default backups/), --user EMAIL (metadata only: a single user).
# Environment: SILO_COMPOSE_FILE (default docker-compose.yml), COMPOSE_PROJECT_NAME (as in compose),
#   SILO_BACKUP_WAIT (s, default 60: waiting for an empty imap_op queue before the export),
#   SILO_TAR_IMAGE (default alpine:3.22, the image used to archive the blob volume).
# Every file gets a .sha256 file. SILO_SECRET_KEY is NOT in the backup: keep it
# separately; a restore requires the same key.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export MSYS_NO_PATHCONV=1 # Git Bash on Windows must not "fix" paths in docker arguments

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

# psql in the postgres container (user and database from its environment).
psql_q() {
  # shellcheck disable=SC2016 # the postgres container's shell expands the variables
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

# The volume with the blob directory: from the silo-server container's mounts, otherwise by compose labels.
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
  # Pending write-back operations (imap_op, e.g. an archive within the undo window) do not go into the backup.
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
  # The prod image is distroless (no shell): exec the binary directly.
  if ! "${COMPOSE[@]}" exec -T silo-server /silo-server "${args[@]}" > "$file.part"; then
    rm -f "$file.part"
    die "export-metadata nie powiodl sie"
  fi
  mv "$file.part" "$file"
  checksum "$file"
  echo "metadata: $file ($(size_of "$file") B)"
else
  db="$OUT_DIR/silo-db-$TS.dump"
  # shellcheck disable=SC2016 # the postgres container's shell expands the variables
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

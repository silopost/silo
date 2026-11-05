#!/usr/bin/env bash
# Uruchamia stos dev (docker-compose.dev.yml) i zaklada konta testowe w docker-mailserver.
# Uzycie: scripts/dev-up.sh [usluga ...]   (domyslnie wszystkie; np. `dev-up.sh postgres mailserver`)
# Idempotentny: kolejne uruchomienia nic nie psuja.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

COMPOSE=(docker compose -f docker-compose.dev.yml)
ACCOUNTS=("dev1@silo.test:devpass1" "dev2@silo.test:devpass2" "dev3@silo.test:devpass3")

services=("$@")
needs_siblings=1
if [ ${#services[@]} -gt 0 ]; then
  needs_siblings=0
  for s in "${services[@]}"; do
    case "$s" in silo-server | silo-web) needs_siblings=1 ;; *) ;; esac
  done
fi

if [ "$needs_siblings" = 1 ]; then
  for d in ../silo-server ../silo-web; do
    if [ ! -d "$d" ]; then
      echo "Brak katalogu $d - repozytoria silo, silo-server i silo-web musza byc rodzenstwem." >&2
      echo "Mozesz uruchomic sam serwer poczty: $0 postgres mailserver" >&2
      exit 1
    fi
  done
fi

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Utworzono .env z .env.example (zmien SILO_DEV_*_PORT, gdy porty sa zajete)."
fi

# Zmienne z .env tylko do wypisania adresow (compose czyta .env sam).
set -a
# shellcheck disable=SC1091
. ./.env
set +a

"${COMPOSE[@]}" up -d --build "${services[@]}"

# Czekamy na mailserver tylko, gdy jest wsrod uruchamianych uslug.
want_mail=1
if [ ${#services[@]} -gt 0 ]; then
  want_mail=0
  for s in "${services[@]}"; do [ "$s" = mailserver ] && want_mail=1; done
fi

if [ "$want_mail" = 1 ]; then
  echo -n "Czekam na IMAP w mailserverze"
  ready=0
  for _ in $(seq 1 90); do
    if "${COMPOSE[@]}" exec -T mailserver ss -lnt 2>/dev/null | grep -q ':143 '; then
      ready=1
      break
    fi
    echo -n "."
    sleep 2
  done
  echo
  if [ "$ready" != 1 ]; then
    echo "Mailserver nie wystartowal w 180 s: ${COMPOSE[*]} logs mailserver" >&2
    exit 1
  fi

  existing="$("${COMPOSE[@]}" exec -T mailserver setup email list 2>/dev/null || true)"
  for acc in "${ACCOUNTS[@]}"; do
    addr="${acc%%:*}"
    pass="${acc#*:}"
    if printf '%s' "$existing" | grep -q "$addr"; then
      echo "Konto $addr istnieje."
    else
      "${COMPOSE[@]}" exec -T mailserver setup email add "$addr" "$pass"
      echo "Zalozono konto $addr."
    fi
  done
fi

cat <<INFO

Stos dev gotowy:
  IMAP (bez TLS)        localhost:${SILO_DEV_IMAP_PORT:-1143}
  SMTP (przyjmowanie)   localhost:${SILO_DEV_SMTP_PORT:-2525}
  Submission (bez TLS)  localhost:${SILO_DEV_SUBMISSION_PORT:-1587}
  Postgres              localhost:${SILO_DEV_PG_PORT:-5432}
  silo-server           http://localhost:${SILO_DEV_SERVER_PORT:-8080}
  silo-web              http://localhost:${SILO_DEV_WEB_PORT:-5173}
Konta: dev1@silo.test / devpass1, dev2@silo.test / devpass2, dev3@silo.test / devpass3
Seed poczty: scripts/seed-mail.sh
INFO

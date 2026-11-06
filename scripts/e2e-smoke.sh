#!/usr/bin/env bash
# Smoke e2e na dzialajacym stosie dev (docker-compose.dev.yml), DoD fazy 2:
#   1. logowanie -> niepusta lista INBOX przez API   < SILO_E2E_LIST_MAX_MS  (domyslnie 10000)
#   2. swaks -> dev1@ -> `event: message.new` w SSE  < SILO_E2E_EVENT_MAX_MS (domyslnie 2000)
# Wymaga: stos (scripts/dev-up.sh), curl, docker compose; swaks jest w kontenerze mailserver.
# Pelny pomiar initial sync: swiezy stos z wyslanym seedem (scripts/seed-mail.sh) PRZED pierwszym
# logowaniem (konto Silo powstaje przy pierwszym logowaniu); na kolejnych przebiegach lista jest od razu.
# Opcje srodowiskowe: SILO_E2E_BASE (domyslnie http://localhost:$SILO_DEV_SERVER_PORT z .env),
# SILO_E2E_USER/SILO_E2E_PASSWORD (dev1@silo.test / devpass1), SILO_E2E_MIN_INBOX (domyslnie 0).
# Kod wyjscia: 0 = progi dotrzymane, 1 = przekroczony prog lub blad, 2 = stos niedostepny.
# DoD Fazy 3 (UI, wysylka, undo, drafty, offline, a11y) sprawdza Playwright w silo-web: `npm run e2e`
# (README silo-web, sekcja "End-to-end tests"); ten skrypt pozostaje szybkim smoke API z Fazy 2.
# DoD Fazy 4 (wyszukiwanie, snooze, schedule send, filtry, etykiety jako keywords, ustawienia, skroty)
# sprawdzaja pliki Playwright silo-web: e2e/{search,snooze,filters,schedule-send,labels-keywords,
# settings,shortcuts}.e2e.ts (`npm run e2e -- --grep-invert @slow` bez testow czekajacych 2-4 min).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi
BASE="${SILO_E2E_BASE:-http://localhost:${SILO_DEV_SERVER_PORT:-8080}}"
USER_EMAIL="${SILO_E2E_USER:-dev1@silo.test}"
PASSWORD="${SILO_E2E_PASSWORD:-devpass1}"
LIST_MAX_MS="${SILO_E2E_LIST_MAX_MS:-10000}"
EVENT_MAX_MS="${SILO_E2E_EVENT_MAX_MS:-2000}"
COMPOSE=(docker compose -f docker-compose.dev.yml)

tmp="$(mktemp -d)"
sse_pid=""
cleanup() {
  [ -n "$sse_pid" ] && kill "$sse_pid" 2> /dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

now_ms() { echo $(($(date +%s%N) / 1000000)); }
fail() { echo "FAIL: $*" >&2; exit 1; }

curl -fsS --max-time 5 "$BASE/healthz" > /dev/null 2>&1 || { echo "silo-server niedostepny pod $BASE (scripts/dev-up.sh?)" >&2; exit 2; }

# 1. Logowanie i initial sync.
t0=$(now_ms)
curl -fsS --max-time 30 -c "$tmp/cookies" -X POST "$BASE/api/v1/session" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$USER_EMAIL\",\"password\":\"$PASSWORD\"}" > "$tmp/login.json" || fail "logowanie $USER_EMAIL"
t_login=$(($(now_ms) - t0))

list_ms=-1
min_inbox="${SILO_E2E_MIN_INBOX:-0}"
while :; do
  elapsed=$(($(now_ms) - t0))
  body="$(curl -fsS --max-time 10 -b "$tmp/cookies" "$BASE/api/v1/threads?labelId=INBOX" 2> /dev/null || true)"
  n_threads="$(printf '%s' "$body" | { grep -o '"messageCount"' || true; } | wc -l | tr -d ' ')"
  if [ "$n_threads" -gt "$min_inbox" ]; then
    list_ms=$(($(now_ms) - t0))
    break
  fi
  [ "$elapsed" -gt $((LIST_MAX_MS + 20000)) ] && break
  sleep 0.2
done
[ "$list_ms" -ge 0 ] || fail "lista INBOX pusta po $((($(now_ms) - t0) / 1000)) s (czy seed zostal wyslany? scripts/seed-mail.sh)"
echo "login: ${t_login} ms; login -> niepusta lista INBOX ($n_threads watkow): ${list_ms} ms (prog ${LIST_MAX_MS} ms)"

# 2. SSE: otwieramy strumien, wysylamy swaks, mierzymy czas do message.new.
(curl -sN -b "$tmp/cookies" "$BASE/api/v1/events" |
  while IFS= read -r line; do
    case "$line" in event:*) echo "$(now_ms) $line" >> "$tmp/sse.log" ;; esac
  done) 2> /dev/null &
sse_pid=$!
sleep 1
: > "$tmp/sse.log"
base_events="$(grep -c 'message.new' "$tmp/sse.log" || true)"

subject="silo e2e smoke $(date +%s)"
# Czas startu kontenerowego `docker compose exec` (~1-2 s na Windows) nie jest czescia dostarczania:
# liczymy od momentu, w ktorym swaks zglosil przyjecie wiadomosci przez Postfix (koniec exec),
# a ponadto raportujemy czas od startu polecenia.
t_send0=$(now_ms)
"${COMPOSE[@]}" exec -T mailserver swaks --server localhost --port 25 \
  --from smoke@example.com --to "$USER_EMAIL" \
  --header "Subject: $subject" --body "e2e smoke" --suppress-data --silent 1 || fail "swaks"
t_sent=$(now_ms)

arrival=""
for _ in $(seq 1 100); do
  if [ "$(grep -c 'message.new' "$tmp/sse.log" || true)" -gt "$base_events" ]; then
    arrival="$(grep 'message.new' "$tmp/sse.log" | sed -n "$((base_events + 1))p" | cut -d' ' -f1)"
    break
  fi
  sleep 0.1
done
[ -n "$arrival" ] || fail "brak message.new w SSE w 10 s od wyslania"
from_start=$((arrival - t_send0))
from_sent=$((arrival - t_sent))
[ "$from_sent" -lt 0 ] && from_sent=0
echo "swaks -> message.new: ${from_sent} ms od zakonczenia swaks (${from_start} ms od startu polecenia, prog ${EVENT_MAX_MS} ms)"

rc=0
[ "$list_ms" -le "$LIST_MAX_MS" ] || { echo "FAIL: lista INBOX ${list_ms} ms > ${LIST_MAX_MS} ms" >&2; rc=1; }
[ "$from_sent" -le "$EVENT_MAX_MS" ] || { echo "FAIL: message.new ${from_sent} ms > ${EVENT_MAX_MS} ms" >&2; rc=1; }
[ "$rc" -eq 0 ] && echo "OK"
exit "$rc"

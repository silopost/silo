#!/usr/bin/env bash
# E2E smoke test on a running dev stack (docker-compose.dev.yml), phase 2 definition of done:
#   1. sign-in -> non-empty INBOX list through the API   < SILO_E2E_LIST_MAX_MS  (default 10000)
#   2. swaks -> dev1@ -> `event: message.new` over SSE   < SILO_E2E_EVENT_MAX_MS (default 2000)
# Requires: the stack (scripts/dev-up.sh), curl, docker compose; swaks is in the mailserver container.
# Full initial sync measurement: a fresh stack with the seed sent (scripts/seed-mail.sh) BEFORE the first
# sign-in (the Silo account is created at the first sign-in); on later runs the list is there immediately.
# Environment options: SILO_E2E_BASE (default http://localhost:$SILO_DEV_SERVER_PORT from .env),
# SILO_E2E_USER/SILO_E2E_PASSWORD (dev1@silo.test / devpass1), SILO_E2E_MIN_INBOX (default 0).
# Exit code: 0 = thresholds met, 1 = threshold exceeded or error, 2 = stack unavailable.
# The phase 3 definition of done (UI, sending, undo, drafts, offline, a11y) is checked by Playwright in
# silo-web: `npm run e2e` (silo-web README, section "End-to-end tests"); this script stays a quick API smoke test.
# The phase 4 definition of done (search, snooze, schedule send, filters, labels as keywords, settings,
# shortcuts) is checked by the silo-web Playwright files e2e/{search,snooze,filters,schedule-send,labels-keywords,
# settings,shortcuts}.e2e.ts (`npm run e2e -- --grep-invert @slow` without the tests that wait 2-4 min).
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
# shellcheck disable=SC2329 # called by trap
cleanup() {
  [ -n "$sse_pid" ] && kill "$sse_pid" 2> /dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

now_ms() { echo $(($(date +%s%N) / 1000000)); }
fail() { echo "FAIL: $*" >&2; exit 1; }

curl -fsS --max-time 5 "$BASE/healthz" > /dev/null 2>&1 || { echo "silo-server niedostepny pod $BASE (scripts/dev-up.sh?)" >&2; exit 2; }

# 1. Sign-in and initial sync.
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

# 2. SSE: open the stream, send with swaks, measure the time to message.new.
(curl -sN -b "$tmp/cookies" "$BASE/api/v1/events" |
  while IFS= read -r line; do
    case "$line" in event:*) echo "$(now_ms) $line" >> "$tmp/sse.log" ;; esac
  done) 2> /dev/null &
sse_pid=$!
sleep 1
: > "$tmp/sse.log"
base_events="$(grep -c 'message.new' "$tmp/sse.log" || true)"

subject="silo e2e smoke $(date +%s)"
# The start-up time of `docker compose exec` (~1-2 s on Windows) is not part of delivery:
# we count from the moment swaks reported that Postfix accepted the message (end of exec),
# and additionally report the time from the start of the command.
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

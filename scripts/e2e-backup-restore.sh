#!/usr/bin/env bash
# Przebieg DoD Fazy 5 (backup metadanych -> utrata danych Silo -> restore + sync) na osobnym
# stosie docker-compose.backup-test.yml (projekt silo-bt; stos dev nie jest dotykany):
#   a. swiezy stos (down -v, up -d --build), czekanie na healthz i serwer poczty;
#   b. seed (scripts/seed-mail.sh) do dev1@silo.test;
#   c. logowanie, czekanie na sync-status `live` (czas initial sync);
#   d. metadane: etykieta uzytkownika Backup-Test na 2 watkach INBOX, archiwizacja 1 watku,
#      draft z zalacznikiem (zsynchronizowany do Drafts), draft zaplanowany na +1 h (SCHEDULED);
#      migawka A: INBOX (bez id i pendingSync, etykiety po nazwach), liczba watkow Backup-Test;
#   e. scripts/backup.sh metadata;
#   f. usuniecie kontenerow i wolumenow Silo (pgdata, blobs). DoD mowi `down -v`; tu chodzi
#      o wolumeny Silo: serwer poczty (dms-mail) gra role zewnetrznego IMAP, jak w produkcji;
#   g. up silo-server (pusta baza, migracje), scripts/restore.sh metadata;
#   h. logowanie, czekanie na `live` i na 2 watki z Backup-Test (job metadata_restore);
#   i. porownanie migawek A i B, draft (temat, tresc, zalacznik z rozmiarem), SCHEDULED;
#   j. PASS/FAIL i czasy.
# Pominiete: snooze i filtry (API Fazy 4 nie ma na tej galezi); sprawdza je test serwera.
# Opcje: --keep (zostaw stos silo-bt; domyslnie down -v projektu silo-bt), -h/--help.
# Srodowisko: SILO_BT_PG_PORT (15432), SILO_BT_SERVER_PORT (18080), SILO_BT_IMAP_PORT (11143),
#   SILO_BT_SMTP_PORT (12525), SILO_BT_SUBMISSION_PORT (11587), SILO_BT_TIMEOUT (s, domyslnie 180).
# Wymaga: docker compose, curl, repo-rodzenstwa ../silo-server. Kod wyjscia: 0 = PASS, 1 = FAIL.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export SILO_COMPOSE_FILE=docker-compose.backup-test.yml
export COMPOSE_PROJECT_NAME=silo-bt
export SILO_BT_PG_PORT="${SILO_BT_PG_PORT:-15432}"
export SILO_BT_SERVER_PORT="${SILO_BT_SERVER_PORT:-18080}"
export SILO_BT_IMAP_PORT="${SILO_BT_IMAP_PORT:-11143}"
export SILO_BT_SMTP_PORT="${SILO_BT_SMTP_PORT:-12525}"
export SILO_BT_SUBMISSION_PORT="${SILO_BT_SUBMISSION_PORT:-11587}"
TIMEOUT="${SILO_BT_TIMEOUT:-180}"
BASE="http://localhost:$SILO_BT_SERVER_PORT"
USER_EMAIL=dev1@silo.test
PASSWORD=devpass1
LABEL=Backup-Test
COMPOSE=(docker compose -f "$SILO_COMPOSE_FILE")
KEEP=0

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --keep) KEEP=1 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "Nieznana opcja: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

tmp="$(mktemp -d)"
# shellcheck disable=SC2329 # wywolywana przez trap
cleanup() {
  rm -rf "$tmp"
  if [ "$KEEP" = 1 ]; then
    echo "Stos silo-bt pozostawiony (${COMPOSE[*]} down -v sprzata)."
  else
    "${COMPOSE[@]}" down -v --remove-orphans > /dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

now_ms() { echo $(($(date +%s%N) / 1000000)); }
secs() { awk -v ms="$1" 'BEGIN { printf "%.1f s", ms / 1000 }'; }
step() { echo "== $*"; }
die() { echo "FAIL: $*" >&2; exit 1; }
FAILS=0
check() { # opis polecenie...
  local what="$1"
  shift
  if "$@"; then echo "  ok: $what"; else echo "  BLAD: $what" >&2; FAILS=$((FAILS + 1)); fi
}

# Wywolanie API (sesja z cookie, X-Silo-CSRF); body na stdout, blad HTTP na stderr.
CSRF=""
ACC=""
api() { # METODA SCIEZKA [JSON]
  local m="$1" p="$2" code
  shift 2
  local args=(-sS --max-time 60 -b "$tmp/cookies" -c "$tmp/cookies" -X "$m" -o "$tmp/resp" -w '%{http_code}')
  [ -z "$CSRF" ] || args+=(-H "X-Silo-CSRF: $CSRF")
  [ $# -eq 0 ] || args+=(-H 'Content-Type: application/json' --data-binary "$1")
  code="$(curl "${args[@]}" "$BASE/api/v1$p")" || { echo "curl $m $p: blad polaczenia" >&2; return 1; }
  case "$code" in
    2*) cat "$tmp/resp" ;;
    *) echo "HTTP $code $m $p: $(cat "$tmp/resp")" >&2; return 1 ;;
  esac
}

# Proste pola JSON bez jq: pierwsze "klucz":"wartosc" / "klucz":liczba.
json_str() { { grep -o "\"$1\":\"[^\"]*\"" || true; } | head -n1 | sed 's/.*:"\(.*\)"$/\1/'; }
json_num() { { grep -o "\"$1\":[0-9]*" || true; } | head -n1 | sed 's/.*://'; }
count_threads() { { grep -o '"messageCount"' || true; } | wc -l | tr -d ' '; }

# Zlozone operacje na JSON: Postgres ze stosu (jsonb). JSON ze stdin jako `j` w CTE `s`.
pg_json() { # SQL (SELECT ... FROM s ...)
  local json
  json="$(cat)"
  # shellcheck disable=SC2016 # $siloj$ to cytowanie dolarowe Postgresa, $POSTGRES_* rozwija kontener
  {
    printf 'WITH s AS (SELECT $siloj$%s$siloj$::jsonb AS j) ' "$json"
    printf '%s;\n' "$1"
  } | "${COMPOSE[@]}" exec -T postgres sh -c 'psql -X -q -tA -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' | tr -d '\r'
}

wait_healthz() {
  local t0
  t0=$(now_ms)
  until curl -fsS --max-time 3 "$BASE/healthz" > /dev/null 2>&1; do
    [ $(($(now_ms) - t0)) -lt $((TIMEOUT * 1000)) ] || die "silo-server niedostepny pod $BASE po ${TIMEOUT} s"
    sleep 1
  done
}

login() {
  local body
  CSRF=""
  rm -f "$tmp/cookies"
  body="$(api POST /session "{\"email\":\"$USER_EMAIL\",\"password\":\"$PASSWORD\"}")" || die "logowanie $USER_EMAIL"
  CSRF="$(printf '%s' "$body" | json_str csrfToken)"
  ACC="$(printf '%s' "$body" | { grep -o '"id":"acc_[^"]*"' || true; } | head -n1 | sed 's/.*:"\(.*\)"$/\1/')"
  [ -n "$CSRF" ] && [ -n "$ACC" ] || die "brak csrfToken lub konta w odpowiedzi logowania: $body"
}

wait_live() { # t0 -> czas w ms od t0 do stanu live
  local t0="$1" st state
  while :; do
    st="$(api GET "/accounts/$ACC/sync-status" 2> /dev/null || true)"
    state="$(printf '%s' "$st" | json_str state)"
    [ "$state" = live ] && break
    case "$state" in auth_failed | disabled) die "konto w stanie $state: $st" ;; *) ;; esac
    [ $(($(now_ms) - t0)) -lt $((TIMEOUT * 1000)) ] || die "konto nie osiagnelo live w ${TIMEOUT} s (stan: ${state:-?})"
    sleep 1
  done
  echo $(($(now_ms) - t0))
}

wait_no_pending_ops() {
  local t0 n
  t0=$(now_ms)
  while :; do
    n="$(api GET "/accounts/$ACC/sync-status" | json_num pendingOps)"
    [ "${n:-0}" = 0 ] && return 0
    [ $(($(now_ms) - t0)) -lt 60000 ] || { echo "  uwaga: pendingOps=$n po 60 s" >&2; return 0; }
    sleep 1
  done
}

label_id() { # nazwa -> l_ id (pusty, gdy brak)
  api GET /labels | pg_json "SELECT e->>'id' FROM s, jsonb_array_elements(j->'labels') e WHERE e->>'name' = '$1' LIMIT 1"
}

# Migawka listy INBOX: wiersz na watek, bez id i pendingSync, etykiety po nazwach (posortowane).
snapshot() {
  local threads labels
  threads="$(api GET '/threads?labelId=INBOX&limit=100')"
  labels="$(api GET /labels)"
  printf '{"t":%s,"l":%s}' "$threads" "$labels" | pg_json "
SELECT concat_ws(' | ', t.e->>'subject', t.e->>'lastMessageAt', t.e->>'messageCount', t.e->>'unreadCount',
  t.e->>'hasAttachments', coalesce(t.e->>'snoozedUntil', '-'), (t.e->>'draftId' IS NOT NULL)::text,
  (SELECT coalesce(string_agg(coalesce(l.e->>'name', x.v), ',' ORDER BY coalesce(l.e->>'name', x.v)), '')
     FROM jsonb_array_elements_text(coalesce(nullif(t.e->'labelIds', 'null'), '[]')) x(v)
     LEFT JOIN jsonb_array_elements(s.j->'l'->'labels') l(e) ON l.e->>'id' = x.v),
  (SELECT coalesce(string_agg(concat(p->>'name', '<', p->>'email', '>', p->>'unread'), ','), '')
     FROM jsonb_array_elements(coalesce(nullif(t.e->'participants', 'null'), '[]')) p),
  replace(t.e->>'snippet', E'\n', ' '))
FROM s, jsonb_array_elements(s.j->'t'->'threads') WITH ORDINALITY t(e, n) ORDER BY t.n"
}

# Watki o danym temacie pod etykieta (DRAFT, SCHEDULED): "draftId|temat" na wiersz.
threads_with_subject() { # etykieta temat
  api GET "/threads?labelId=$1&limit=100" | pg_json "
SELECT concat(coalesce(e->>'draftId', ''), '|', e->>'subject') FROM s, jsonb_array_elements(j->'threads') e
WHERE e->>'subject' = '$2'"
}

# Stan draftu: temat|tresc|nazwa zalacznika|rozmiar|id zalacznika.
draft_state() {
  api GET "/drafts/$1" | pg_json "
SELECT concat_ws('|', j->>'subject', j->>'bodyHtml', j->'attachments'->0->>'filename',
  j->'attachments'->0->>'size', j->'attachments'->0->>'id') FROM s"
}

# Bajty zalacznika draftu: upload u_X to wiersz attachments o tym samym id (GET /attachments/a_X).
attachment_size() {
  curl -sS --max-time 60 -f -b "$tmp/cookies" -o "$tmp/att.bin" "$BASE/api/v1/attachments/a_${1#u_}" || return 1
  wc -c < "$tmp/att.bin" | tr -d ' '
}

t_all=$(now_ms)

# a. Swiezy stos.
step "a. stos silo-bt (down -v, up -d --build)"
"${COMPOSE[@]}" down -v --remove-orphans > /dev/null 2>&1 || true
"${COMPOSE[@]}" up -d --build > "$tmp/up.log" 2>&1 || { cat "$tmp/up.log" >&2; die "docker compose up"; }
wait_healthz
t0=$(now_ms)
until "${COMPOSE[@]}" exec -T mailserver bash -c 'echo > /dev/tcp/127.0.0.1/25 && echo > /dev/tcp/127.0.0.1/143 && doveadm user dev1@silo.test' > /dev/null 2>&1; do
  [ $(($(now_ms) - t0)) -lt $((TIMEOUT * 1000)) ] || die "serwer poczty nie wystartowal w ${TIMEOUT} s"
  sleep 2
done
echo "  stos gotowy po $(secs $(($(now_ms) - t_all)))"

# b. Seed.
step "b. seed do $USER_EMAIL"
bash scripts/seed-mail.sh --to "$USER_EMAIL" > "$tmp/seed.log" 2>&1 || { cat "$tmp/seed.log" >&2; die "seed-mail.sh"; }
expected="$(sed -n 's/^Gotowe: dostarczono \([0-9]*\).*/\1/p' "$tmp/seed.log")"
t0=$(now_ms)
while :; do
  n="$("${COMPOSE[@]}" exec -T mailserver doveadm -f flow mailbox status -u "$USER_EMAIL" messages INBOX 2> /dev/null | sed -n 's/.*messages=\([0-9]*\).*/\1/p' | tr -d '\r' || true)"
  [ "${n:-0}" -ge "${expected:-1}" ] && break
  [ $(($(now_ms) - t0)) -lt 60000 ] || die "w INBOX ${n:-0} z $expected wiadomosci po 60 s"
  sleep 1
done
echo "  INBOX na serwerze IMAP: $n wiadomosci"

# c. Logowanie i initial sync.
step "c. logowanie i initial sync"
t0=$(now_ms)
login
sync_ms="$(wait_live "$t0")"
echo "  konto $ACC: login -> live $(secs "$sync_ms")"

# d. Metadane i migawka A.
step "d. metadane: etykieta, archiwizacja, drafty"
inbox="$(api GET '/threads?labelId=INBOX&limit=100')"
mapfile -t tids < <(printf '%s' "$inbox" | { grep -o '"id":"t_[^"]*"' || true; } | sed 's/.*:"\(.*\)"$/\1/' | head -n3)
[ "${#tids[@]}" -eq 3 ] || die "za malo watkow w INBOX (${#tids[@]})"
lbl="$(api POST /labels "{\"name\":\"$LABEL\",\"type\":\"user\"}" | json_str id)"
[ -n "$lbl" ] || die "nie utworzono etykiety $LABEL"
api POST /threads/modify "{\"ids\":[\"${tids[0]}\",\"${tids[1]}\"],\"addLabelIds\":[\"$lbl\"]}" > /dev/null || die "przypisanie $LABEL"
api POST /threads/modify "{\"ids\":[\"${tids[2]}\"],\"removeLabelIds\":[\"INBOX\"]}" > /dev/null || die "archiwizacja"
echo "  $LABEL ($lbl) na ${tids[0]}, ${tids[1]}; zarchiwizowany ${tids[2]}"

stamp="$(date -u +%Y%m%d%H%M%S)"
draft_subject="Backup draft $stamp"
draft_body="<p>Tresc draftu $stamp</p>"
head -c 3000 /dev/zero | tr '\0' 'x' > "$tmp/zalacznik.txt"
att_size="$(wc -c < "$tmp/zalacznik.txt" | tr -d ' ')"
# Wzgledna sciezka pliku: curl z Git Bash na Windows nie zna sciezek /tmp/...
upload="$(cd "$tmp" && curl -sS --fail-with-body --max-time 60 -b cookies -H "X-Silo-CSRF: $CSRF" -F 'file=@zalacznik.txt;type=text/plain' "$BASE/api/v1/uploads")" || die "upload: $upload"
upload_id="$(printf '%s' "$upload" | json_str id)"
d1="$(api POST /drafts '{}')" || die "POST /drafts"
d1_id="$(printf '%s' "$d1" | json_str id)"
d1_ver="$(printf '%s' "$d1" | json_num version)"
api PUT "/drafts/$d1_id" "{\"version\":$d1_ver,\"to\":[{\"email\":\"dev2@silo.test\"}],\"subject\":\"$draft_subject\",\"bodyHtml\":\"$draft_body\",\"attachmentIds\":[\"$upload_id\"],\"syncNow\":true}" > /dev/null || die "PUT /drafts/$d1_id"
echo "  draft $d1_id z zalacznikiem $upload_id ($att_size B)"

sched_subject="Backup scheduled $stamp"
send_at="$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)"
d2="$(api POST /drafts '{}')" || die "POST /drafts"
d2_id="$(printf '%s' "$d2" | json_str id)"
d2_ver="$(printf '%s' "$d2" | json_num version)"
api PUT "/drafts/$d2_id" "{\"version\":$d2_ver,\"to\":[{\"email\":\"dev2@silo.test\"}],\"subject\":\"$sched_subject\",\"bodyHtml\":\"<p>Zaplanowana $stamp</p>\"}" > /dev/null || die "PUT /drafts/$d2_id"
api POST "/drafts/$d2_id/send" "{\"sendAt\":\"$send_at\"}" > /dev/null || die "zaplanowanie wysylki $d2_id"
echo "  draft $d2_id zaplanowany na $send_at"

sleep 5 # okno undo (1 s) + write-back
wait_no_pending_ops
snapshot > "$tmp/A.txt"
a_label="$(api GET "/threads?labelId=$lbl&limit=100" | count_threads)"
a_draft="$(draft_state "$d1_id")"
a_drafts="$(threads_with_subject DRAFT "$draft_subject" | grep -c . || true)"
a_sched="$(threads_with_subject SCHEDULED "$sched_subject" | grep -c . || true)"
a_att="$(attachment_size "${a_draft##*|}" || echo -)"
echo "  migawka A: INBOX $(wc -l < "$tmp/A.txt" | tr -d ' ') watkow, $LABEL: $a_label, DRAFT z tematem: $a_drafts, SCHEDULED: $a_sched, zalacznik: $a_att B"
[ "$a_label" = 2 ] || die "przed backupem $LABEL ma $a_label watkow zamiast 2"

# e. Backup.
step "e. scripts/backup.sh metadata"
bash scripts/backup.sh metadata --out "$tmp/backup" 2>&1 | sed 's/^/  /'
[ "${PIPESTATUS[0]}" -eq 0 ] || die "backup.sh"
backup_file="$(ls "$tmp"/backup/silo-metadata-*.json)"

# f. Utrata danych Silo: kontenery + wolumeny pgdata i blobs (dms-mail zostaje, patrz naglowek).
step "f. usuniecie silo-server, postgres i wolumenow pgdata, blobs"
"${COMPOSE[@]}" rm -sfv silo-server postgres blobs-init > /dev/null 2>&1
for v in pgdata blobs; do
  vol="$(docker volume ls -q --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME" --filter "label=com.docker.compose.volume=$v")"
  [ -n "$vol" ] || die "nie znaleziono wolumenu $v"
  docker volume rm "$vol" > /dev/null
done

# g. Swieza baza i restore.
step "g. up (pusta baza) i scripts/restore.sh metadata"
"${COMPOSE[@]}" up -d silo-server > "$tmp/up2.log" 2>&1 || { cat "$tmp/up2.log" >&2; die "docker compose up"; }
wait_healthz
t_restore=$(now_ms)
bash scripts/restore.sh metadata "$backup_file" 2>&1 | sed 's/^/  /'
[ "${PIPESTATUS[0]}" -eq 0 ] || die "restore.sh"

# h. Logowanie, sync i odtworzenie etykiet.
step "h. logowanie, sync, metadata_restore"
login
live_ms="$(wait_live "$t_restore")"
echo "  restore -> live $(secs "$live_ms")"
lbl2=""
b_label=0
match_ms=-1
while :; do
  [ -n "$lbl2" ] || lbl2="$(label_id "$LABEL" 2> /dev/null || true)"
  if [ -n "$lbl2" ]; then
    b_label="$(api GET "/threads?labelId=$lbl2&limit=100" 2> /dev/null | count_threads || true)"
    if [ "$b_label" = 2 ]; then
      snapshot > "$tmp/B.txt"
      if cmp -s "$tmp/A.txt" "$tmp/B.txt"; then
        match_ms=$(($(now_ms) - t_restore))
        break
      fi
    fi
  fi
  [ $(($(now_ms) - t_restore)) -lt $((TIMEOUT * 1000)) ] || break
  sleep 3
done
[ -f "$tmp/B.txt" ] || snapshot > "$tmp/B.txt"

# i. Porownanie.
step "i. porownanie"
check "etykieta $LABEL odtworzona (${lbl2:-brak})" test -n "$lbl2"
check "$LABEL na 2 watkach (jest $b_label)" test "$b_label" = 2
if cmp -s "$tmp/A.txt" "$tmp/B.txt"; then
  echo "  ok: GET /threads INBOX identyczne ($(wc -l < "$tmp/A.txt" | tr -d ' ') watkow)"
else
  echo "  BLAD: GET /threads INBOX rozne (< przed backupem, > po restore):" >&2
  diff "$tmp/A.txt" "$tmp/B.txt" | sed 's/^/    /' >&2 || true
  FAILS=$((FAILS + 1))
fi
drafts_b="$(threads_with_subject DRAFT "$draft_subject")"
b_drafts="$(printf '%s' "$drafts_b" | grep -c . || true)"
check "draft bez duplikatu w DRAFT (przed: $a_drafts, po: $b_drafts)" test "$b_drafts" = "$a_drafts"
d1b_id="$(printf '%s\n' "$drafts_b" | head -n1 | cut -d'|' -f1)"
b_draft=""
[ -z "$d1b_id" ] || b_draft="$(draft_state "$d1b_id")"
check "draft: temat, tresc, zalacznik (${b_draft%|*})" test "${b_draft%|*}" = "${a_draft%|*}"
b_att="-"
[ -z "$b_draft" ] || b_att="$(attachment_size "${b_draft##*|}" || echo -)"
check "zalacznik draftu do pobrania: $b_att B (oczekiwane $att_size B)" test "$b_att" = "$att_size"
b_sched="$(threads_with_subject SCHEDULED "$sched_subject" | grep -c . || true)"
check "wiadomosc zaplanowana w SCHEDULED (przed: $a_sched, po: $b_sched)" test "$b_sched" = 1

# j. Wynik.
step "j. wynik"
echo "  initial sync (login -> live): $(secs "$sync_ms")"
if [ "$match_ms" -ge 0 ]; then match_txt="$(secs "$match_ms")"; else match_txt="brak zgodnosci w ${TIMEOUT} s"; fi
echo "  restore -> live: $(secs "$live_ms"); restore -> INBOX zgodny z A i $LABEL na 2 watkach: $match_txt"
echo "  calosc: $(secs $(($(now_ms) - t_all)))"
if [ "$FAILS" -eq 0 ]; then
  echo "PASS"
  exit 0
fi
echo "FAIL ($FAILS)"
exit 1

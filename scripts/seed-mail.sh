#!/usr/bin/env bash
# Wstrzykuje korpus seed/mail/*.eml do docker-mailserver z docker-compose.dev.yml.
#
# Tryby (manifest: seed/mail/manifest.yaml, pole `via`):
#   (domyslnie)  SMTP: wiadomosci `via: smtp` trafiaja przez Postfix -> Dovecot LMTP do INBOX
#                (swaks uruchamiany w kontenerze mailserver, port 25).
#   --append     IMAP APPEND: wiadomosci `via: append` trafiaja do folderu z manifestu
#                (Sent, INBOX) z flagami i INTERNALDATE.
#   --all        oba tryby po kolei.
# Opcje: --shuffle (losowa kolejnosc), --delay <s> (przerwa miedzy wiadomosciami, np. 1 lub 0.5),
#        --to <adres> (adresat/wlasciciel skrzynki, domyslnie dev1@silo.test), -h/--help.
# Uwaga: skrypt nie sprawdza duplikatow - kolejne uruchomienie dodaje wiadomosci ponownie
#        (czysty start: docker compose -f docker-compose.dev.yml down -v).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export MSYS_NO_PATHCONV=1 # Git Bash na Windows nie moze "poprawiac" argumentow dla docker exec

COMPOSE=(docker compose -f docker-compose.dev.yml)
MANIFEST=seed/mail/manifest.yaml
REMOTE_DIR=/tmp/silo-seed
MODE=smtp
SHUFFLE=0
DELAY=0
TO=dev1@silo.test

usage() { sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --append) MODE=append ;;
    --all) MODE=all ;;
    --shuffle) SHUFFLE=1 ;;
    --delay)
      [ $# -ge 2 ] || { echo "--delay wymaga wartosci" >&2; exit 2; }
      DELAY="${2%s}"
      shift
      ;;
    --to)
      [ $# -ge 2 ] || { echo "--to wymaga adresu" >&2; exit 2; }
      TO="$2"
      shift
      ;;
    -h | --help) usage; exit 0 ;;
    *) echo "Nieznana opcja: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

# Haslo skrzynki: devN@silo.test -> devpassN, inaczej z SILO_SEED_PASSWORD (tylko tryb append).
password_for() {
  if [[ "$1" =~ ^dev([0-9]+)@silo\.test$ ]]; then
    echo "devpass${BASH_REMATCH[1]}"
  else
    echo "${SILO_SEED_PASSWORD:?ustaw SILO_SEED_PASSWORD dla konta $1}"
  fi
}

# Manifest -> linie: plik|folder|via|flagi|data
read_manifest() {
  tr -d '\r' < "$MANIFEST" | awk '
    function out() { if (f != "") print f "|" fo "|" v "|" fl "|" d }
    /^  - file:/ { out(); f = $3; fo = ""; v = ""; fl = ""; d = ""; next }
    /^    folder:/ { fo = $2; next }
    /^    via:/ { v = $2; next }
    /^    flags:/ { s = $0; sub(/^    flags: *"/, "", s); sub(/" *$/, "", s); fl = s; next }
    /^    date:/ { s = $0; sub(/^    date: *"/, "", s); sub(/" *$/, "", s); d = s; next }
    END { out() }'
}

# IMAP APPEND przez perl w kontenerze (curl -T nie ustawia flag ani INTERNALDATE).
# argumenty: uzytkownik haslo folder flagi data; tresc wiadomosci na stdin.
# shellcheck disable=SC2016 # kod perla, nie ma byc rozwijany przez shell
PERL_APPEND='
use strict; use IO::Socket::INET;
my ($u, $p, $box, $flags, $date) = @ARGV;
local $/; my $msg = <STDIN>; $msg =~ s/\r?\n/\r\n/g;
my $s = IO::Socket::INET->new(PeerAddr => "127.0.0.1:143", Timeout => 15) or die "connect: $!\n";
$s->autoflush(1); binmode $s;
sub until_tag { my $t = shift; my $r = ""; local $/ = "\n"; while (my $l = <$s>) { $r .= $l; return $r if $l =~ /^$t (OK|NO|BAD)/ } die "polaczenie zamkniete: $r\n" }
{ local $/ = "\n"; my $g = <$s>; die "brak powitania\n" unless $g =~ /^\* OK/; }
print $s "a1 LOGIN \"$u\" \"$p\"\r\n"; my $r = until_tag("a1"); die "LOGIN: $r" unless $r =~ /a1 OK/;
my $cmd = "a2 APPEND \"$box\"";
$cmd .= " ($flags)" if length $flags;
$cmd .= " \"$date\"" if length $date;
print $s $cmd . " {" . length($msg) . "}\r\n";
{ local $/ = "\n"; my $c = <$s>; die "APPEND: $c" unless $c =~ /^\+/; }
print $s $msg . "\r\n"; $r = until_tag("a2"); die "APPEND: $r" unless $r =~ /a2 OK/;
print $s "a3 LOGOUT\r\n"; close $s;
'

# Petla dostarczania wykonywana w kontenerze (jeden docker exec zamiast jednego na wiadomosc:
# na Windows pojedynczy exec trwa ~2 s). Lista wiadomosci przychodzi na stdin.
# shellcheck disable=SC2016 # zmienne maja byc rozwijane dopiero w kontenerze
REMOTE_LOOP='ok=0; fail=0; i=0
while IFS="|" read -r file folder via flags date from; do
  i=$((i + 1))
  if [ "$via" = smtp ]; then
    swaks --server localhost --port 25 --from "$from" --to "$S_TO" --data "@$S_DIR/$file" --suppress-data --silent 1
  else
    perl -e "$PERL_APPEND" -- "$S_TO" "$S_PASS" "$folder" "$flags" "$date" < "$S_DIR/$file"
  fi
  rc=$?
  if [ "$rc" -eq 0 ]; then ok=$((ok + 1)); echo "[$i/$S_TOTAL] $via $file"; else fail=$((fail + 1)); echo "BLAD $via: $file" >&2; fi
  if [ "$S_DELAY" != 0 ] && [ "$i" -lt "$S_TOTAL" ]; then sleep "$S_DELAY"; fi
done
echo "Gotowe: dostarczono $ok, bledy $fail"
[ "$fail" -eq 0 ]'

[ -f "$MANIFEST" ] || { echo "Brak $MANIFEST" >&2; exit 1; }

entries=()
while IFS= read -r line; do
  IFS='|' read -r _ _ via _ _ <<< "$line"
  case "$MODE:$via" in
    smtp:smtp | append:append | all:smtp | all:append) entries+=("$line") ;;
    *) ;;
  esac
done < <(read_manifest)

total=${#entries[@]}
echo "Tryb: $MODE, adresat: $TO, wiadomosci: $total"
[ "$total" -gt 0 ] || { echo "Nic do dostarczenia."; exit 0; }

list=()
for line in "${entries[@]}"; do
  IFS='|' read -r file folder via flags date <<< "$line"
  flags="${flags//\\\\/\\}"
  from="$(tr -d '\r' < "seed/mail/$file" | sed -n 's/^From:.*<\([^>]*\)>.*/\1/p;/^$/q' | head -n1)"
  list+=("$file|$folder|$via|$flags|$date|${from:-seed@example.com}")
done

if [ "$SHUFFLE" = 1 ] && [ "$total" -gt 1 ]; then
  shuffled=()
  while IFS= read -r line; do shuffled+=("$line"); done < <(printf '%s\n' "${list[@]}" | { shuf 2> /dev/null || sort -R; })
  list=("${shuffled[@]}")
fi

# Korpus kopiujemy do kontenera raz.
"${COMPOSE[@]}" exec -T mailserver rm -rf "$REMOTE_DIR"
"${COMPOSE[@]}" cp seed/mail "mailserver:$REMOTE_DIR"

printf '%s\n' "${list[@]}" | "${COMPOSE[@]}" exec -T \
  -e S_TO="$TO" -e S_PASS="$(password_for "$TO")" -e S_DIR="$REMOTE_DIR" -e S_DELAY="$DELAY" \
  -e S_TOTAL="$total" -e PERL_APPEND="$PERL_APPEND" \
  mailserver bash -c "$REMOTE_LOOP"

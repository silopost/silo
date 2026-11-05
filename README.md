# Silo

Self-hosted **klient webowy poczty** (IMAP/SMTP) z UX współczesnego Gmaila: wątki, wiele etykiet, archiwizacja, snooze, undo send, szybkie wyszukiwanie, skróty klawiszowe, real-time.

Silo **nie jest serwerem pocztowym**. Łączy się z istniejącym serwerem (docker-mailserver, Dovecot, Gmail IMAP, Office 365 itd.) przez IMAP i SMTP submission – tak jak Roundcube czy Thunderbird. Serwer IMAP pozostaje źródłem prawdy dla poczty. Szczegóły: [sekcja 1 planu](ARCHITECTURE_AND_PLAN.md#1-cel-i-zasady) i [ADR 0005](docs/adr/0005-imap-source-of-truth.md).

> Status: Faza 3 zamknięta – działa klient webowy z układem Gmaila: czytanie, akcje z „Cofnij”, compose z draftami na serwerze, wysyłka z undo send. Brak wyszukiwania z operatorami, snooze, filtrów i wielu kont w UI (Fazy 4–5); szczegóły w sekcji [Stan: Faza 3](#stan-faza-3).

## Repozytoria

| Repo | Licencja | Zakres | Artefakt |
|---|---|---|---|
| `silo` (to repo) | MIT | Orkiestracja (compose, Caddy, skrypty), dokumentacja, ADR, e2e | tag + compose z przypiętymi obrazami |
| `silo-server` | AGPL-3.0 | Backend Go: API, SSE, sync IMAP, SMTP, workery | `ghcr.io/silopost/silo-server` |
| `silo-web` | AGPL-3.0 | SPA React/TS, konsument OpenAPI | `ghcr.io/silopost/silo-web` |

## Szybki start (dev)

Wymagane: Docker z Compose v2, Git.

```sh
mkdir silopost && cd silopost
git clone https://github.com/silopost/silo.git
git clone https://github.com/silopost/silo-server.git
git clone https://github.com/silopost/silo-web.git

cd silo
scripts/dev-up.sh
```

`scripts/dev-up.sh` sprawdza repozytoria rodzeństwa, tworzy `.env` z `.env.example` (gdy go brak), uruchamia `docker compose -f docker-compose.dev.yml up -d --build`, czeka na serwer pocztowy, zakłada brakujące konta testowe i wypisuje adresy usług. Jest idempotentny. Można podać listę usług, np. `scripts/dev-up.sh postgres mailserver` (sam serwer poczty, bez budowania `silo-server`/`silo-web`).

Repozytoria muszą być rodzeństwem (`silopost/{silo,silo-server,silo-web}`) – compose buduje z `../silo-server` i `../silo-web`.

Weryfikacja:

```sh
curl localhost:8080/healthz     # silo-server -> 200
# http://localhost:5173         # silo-web (Vite)
```

### Serwer pocztowy, konta i seed (dev)

Do testów działa [docker-mailserver](https://github.com/docker-mailserver/docker-mailserver) 16 (Dovecot 2.4) bez TLS i bez filtrów antyspamowych – wyłącznie do developmentu. Konfiguracja: `dev/dms/config/` (`dovecot.cf` dopuszcza hasło jawne bez TLS).

Konta testowe (hasła wyłącznie deweloperskie, hashe są w repo w `dev/dms/config/postfix-accounts.cf`, dzięki czemu start jest deterministyczny; `dev-up.sh` dodatkowo zakłada brakujące konta):

| Konto | Hasło |
|---|---|
| `dev1@silo.test` | `devpass1` |
| `dev2@silo.test` | `devpass2` |
| `dev3@silo.test` | `devpass3` |

Seed poczty (`seed/mail/`, ponad 60 fikcyjnych wiadomości: wątki, Sent, out-of-order, HTML, Base64/QP, ISO-8859-2, Windows-1250, załączniki, inline obraz, brak Message-ID):

```sh
scripts/seed-mail.sh              # SMTP: 54 wiadomości do INBOX dev1@silo.test
scripts/seed-mail.sh --append     # IMAP APPEND: Sent (11) i 3 wiadomości do INBOX z flagami i datą
scripts/seed-mail.sh --all --shuffle --delay 1   # oba tryby, losowa kolejność, 1 s przerwy
scripts/seed-mail.sh --to dev2@silo.test         # inny adresat
```

Po `--all` `dev1@silo.test` ma 57 wiadomości w INBOX i 11 w Sent. Skrypt nie wykrywa duplikatów; czysty start: `docker compose -f docker-compose.dev.yml down -v`. Korpus jest generowany przez `node scripts/gen-seed.mjs` (wynik jest w repo).

Thunderbird (lub inny klient): serwer przychodzący IMAP `localhost`, port `1143` (z `SILO_DEV_IMAP_PORT`), zabezpieczenie połączenia: brak, uwierzytelnianie: hasło zwykłe; wychodzący SMTP `localhost`, port `1587`, bez szyfrowania, to samo hasło. Użytkownik: pełny adres, np. `dev1@silo.test`.

### Smoke e2e

DoD Fazy 3 (UI, wysyłka, undo, drafty, offline, a11y) sprawdzają testy Playwright w `silo-web` (`npm run e2e`, opis w README `silo-web`); poniższy skrypt to szybki smoke API z Fazy 2.

Skrypt `scripts/e2e-smoke.sh` sprawdza na działającym stosie dev dwa punkty Definition of done Fazy 2:

- logowanie `dev1@silo.test` (`POST /api/v1/session`) do niepustej listy INBOX (`GET /api/v1/threads?labelId=INBOX`): **< 10 s** (initial sync),
- wiadomość wysłana `swaks` (w kontenerze `mailserver`) do `dev1@silo.test` pojawia się w strumieniu SSE (`GET /api/v1/events`) jako `message.new`: **< 2 s** (liczone od zakończenia `swaks`; skrypt podaje też czas od startu polecenia, który na Windows zawiera ~1 s narzutu `docker compose exec`).

```sh
scripts/dev-up.sh postgres mailserver silo-server
scripts/seed-mail.sh              # przed pierwszym logowaniem: konto Silo powstaje przy logowaniu
scripts/e2e-smoke.sh              # kod wyjścia 0 = progi dotrzymane, 1 = przekroczone lub błąd, 2 = brak serwera
```

Bez `jq` (parsowanie `grep`/`sed`), potrzebny tylko `curl` i `docker compose`. Adres bierze z `SILO_DEV_SERVER_PORT` w `.env` (nadpisanie: `SILO_E2E_BASE`), progi: `SILO_E2E_LIST_MAX_MS`, `SILO_E2E_EVENT_MAX_MS`. Pełny pomiar initial sync wymaga świeżej bazy (`docker compose -f docker-compose.dev.yml rm -sf silo-server postgres && docker volume rm silo_pgdata`); na kolejnych przebiegach lista jest dostępna od razu. Pomiar z 5.11.2026 (Windows, Docker Desktop): lista po 2,0 s od logowania (świeża baza, 54 wiadomości), `message.new` po ok. 0,5 s.

### Porty

Domyślnie: Postgres `5432`, silo-server `8080`, silo-web `5173`, IMAP `1143`, SMTP `2525`, submission `1587`. Gdy któryś jest zajęty, zmień w `.env` (kopia `.env.example`) odpowiednio `SILO_DEV_PG_PORT`, `SILO_DEV_SERVER_PORT`, `SILO_DEV_WEB_PORT`, `SILO_DEV_IMAP_PORT`, `SILO_DEV_SMTP_PORT`, `SILO_DEV_SUBMISSION_PORT` i uruchom `scripts/dev-up.sh` ponownie. Skrypty działają w Git Bash (Windows) i bash (Linux/macOS).

## Stan: Faza 3

Działa (UI `silo-web` 0.2.0 na API `silo-server` 0.3.0): logowanie danymi skrzynki, układ Gmaila (LeftNav z licznikami i folderami, wyszukiwanie pełnotekstowe bez operatorów, banery synchronizacji i offline), lista wątków (wirtualizacja, zaznaczanie, akcje na hover, ikona „oczekuje”), widok wątku (HTML w piaskownicy bez skryptów, obrazy zdalne blokowane, załączniki, treść na żądanie), akcje z natychmiastową zmianą w UI i „Cofnij” (`/operations/{id}/undo` w oknie `SILO_UNDO_WINDOW`), compose w wielu oknach (TipTap, podpowiedzi adresów, załączniki z postępem, autosave na serwer i jedna kopia w folderze Drafts), odpowiedz / odpowiedz wszystkim / przekaż, wysyłka przez SMTP submission z „Cofnij” (undo send), kopią w Sent i `\Answered` na oryginale, skróty `j k o u e # s x z c r a f ?`, logowanie bearer dla klientów natywnych (ADR 0007). Spełnienie Definition of done sprawdzają testy Playwright w `silo-web` (`npm run e2e`, README `silo-web`, sekcja „End-to-end tests”), z weryfikacją stanu serwera przez IMAP.

Pomiary e2e z 5.11.2026 (Windows 11, Docker Desktop, build produkcyjny przez `vite preview`): `e` → wiersz znika z DOM po 15–16 ms (następna klatka 18–20 ms); wiadomość w Archive po 10,0–10,4 s przy oknie 10 s; „Cofnij” → ten sam UID w INBOX, nic w Archive; undo send → po 12 s nic u `dev2@`, bez cofnięcia dostarczenie 0,6 s po oknie; draft w Drafts po 32 s od ostatniego znaku, po zamknięciu okna (`syncNow`) w < 1 s; mailserver zatrzymany → archiwizacja 3 wątków i ikony „oczekuje”, po starcie ikony znikają po ok. 17 s bez odświeżenia; lista 5000 wątków przewinięta do końca w ok. 12 s bez long tasks (0 w końcowym przebiegu; w pojedynczych przebiegach jeden task 50–63 ms przy doładowaniu strony listy); axe (WCAG 2.2 AA) bez naruszeń na logowaniu, liście, wątku i compose; Lighthouse a11y 100 (logowanie i lista, uruchomiony raz ręcznie).

Nie działa jeszcze: operatory wyszukiwania, snooze, filtry, schedule send w UI, edycja etykiet użytkownika, ekran „Dodaj konto” (konto powstaje przy logowaniu), ustawienia (`PATCH /settings`), obrazy inline (`cid:`) w compose, załączniki oryginału przy przekazaniu, obsługa odbić (bounce/DSN), wiele kont w UI – Fazy 4–5.

Jak uruchomić UI:

```sh
scripts/dev-up.sh                 # cały stos, w tym silo-web (Vite) na :5173
scripts/seed-mail.sh --all        # przed pierwszym logowaniem
# http://localhost:5173 -> dev1@silo.test / devpass1
```

Albo backend w compose i Vite lokalnie: `scripts/dev-up.sh postgres mailserver silo-server`, potem w `silo-web` `VITE_API_PROXY=http://localhost:8090 npm run dev` (port serwera z `SILO_DEV_SERVER_PORT`). Druga skrzynka do odpowiedzi: `dev2@silo.test` / `devpass2` (Thunderbird lub drugie logowanie w innej przeglądarce).

## Stan: Faza 2

Działa (API, bez UI): sesje i konta (`/session`, `/accounts`), initial sync i synchronizacja przyrostowa IMAP (CONDSTORE, IDLE, fallbacki bez CONDSTORE i bez MOVE/UIDPLUS), lustro wiadomości w Postgresie, etykiety i wątki (`/labels`, `/threads`, `/messages`), write-back operacji (archiwizacja, kosz, flagi, etykiety użytkownika, foldery) z kolejką `imap_op`, treść wiadomości (sanitised HTML, raw, załączniki), strumień zdarzeń SSE `/events` z replay, subkomendy `serve`, `migrate`, `rotate-secrets`, `reconcile`.

Nie działa jeszcze: interfejs użytkownika (`silo-web` ma tylko szkielet i klienta API), wysyłka (SMTP submission, drafty, undo send), endpoint cofania operacji (okno `SILO_UNDO_WINDOW` działa w silniku, ale bez API), snooze, filtry, wyszukiwanie ponad proste `q`, QRESYNC (wyłączony – go-imap/v2 beta.8 go nie wystawia, [ADR 0006](docs/adr/0006-go-imap-v2-spike.md); używany jest CONDSTORE). Kontrakt API przed 1.0 może się łamać – [macierz kompatybilności](docs/compat-matrix.md).

## Dokumentacja

- [ARCHITECTURE_AND_PLAN.md](ARCHITECTURE_AND_PLAN.md) – architektura i plan wdrożenia
- [docs/adr/](docs/adr/README.md) – rekordy decyzji architektonicznych
- [docs/compat-matrix.md](docs/compat-matrix.md) – macierz kompatybilności
- [CONTRIBUTING.md](CONTRIBUTING.md) – konwencje i workflow dla wszystkich trzech repo

## Licencja

MIT (to repo) – zob. [LICENSE](LICENSE). `silo-server` i `silo-web` są na AGPL-3.0.

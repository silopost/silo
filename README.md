# Silo

Self-hosted **klient webowy poczty** (IMAP/SMTP) z UX współczesnego Gmaila: wątki, wiele etykiet, archiwizacja, snooze, undo send, szybkie wyszukiwanie, skróty klawiszowe, real-time.

Silo **nie jest serwerem pocztowym**. Łączy się z istniejącym serwerem (docker-mailserver, Dovecot, Gmail IMAP, Office 365 itd.) przez IMAP i SMTP submission – tak jak Roundcube czy Thunderbird. Serwer IMAP pozostaje źródłem prawdy dla poczty. Szczegóły: [sekcja 1 planu](ARCHITECTURE_AND_PLAN.md#1-cel-i-zasady) i [ADR 0005](docs/adr/0005-imap-source-of-truth.md).

> Status: Faza 5 (zakres 1.0) zamknięta – wiele kont z „Dodaj konto” i autokonfiguracją, OAuth2 dla Gmaila i Microsoft 365, tryb `local` z TOTP i panelem admina, backup i odtwarzanie, S3Store, hardening, PWA, stos produkcyjny z Caddy i dokumentacja administratora. Do 1.1 odłożone: tryb `provider=gmail` (X-GM), ManageSieve, OAuth2 dla klientów natywnych, `GET /changes`/`ETag`; Gmail i Microsoft 365 nieprzetestowane na żywych kontach. Szczegóły w sekcji [Stan: Faza 5](#stan-faza-5).
>
> Aplikacja mobilna `silo-mobile` 0.1.0 (Android, React Native/Expo – [ADR 0010](docs/adr/0010-react-native-for-silo-mobile.md)): parytet poczty z `silo-web` 0.3.0, niewydana i **niesprawdzona na urządzeniu** (tylko testy, bundel i smoke-test API); szczegóły w sekcji [Stan: silo-mobile 0.1.0](#stan-silo-mobile-010).

## Repozytoria

| Repo | Licencja | Zakres | Artefakt |
|---|---|---|---|
| `silo` (to repo) | MIT | Orkiestracja (compose, Caddy, skrypty), dokumentacja, ADR, e2e | tag + compose z przypiętymi obrazami |
| `silo-server` | AGPL-3.0 | Backend Go: API, SSE, sync IMAP, SMTP, workery | `ghcr.io/silopost/silo-server` |
| `silo-web` | AGPL-3.0 | SPA React/TS, konsument OpenAPI | `ghcr.io/silopost/silo-web` |
| `silo-mobile` | AGPL-3.0 | Aplikacja mobilna React Native/Expo (Android, iOS docelowo) – cienki klient tego samego OpenAPI z logowaniem bearer; [README](https://github.com/silopost/silo-mobile#readme) | bundel `expo export` w CI; APK przez `expo prebuild` + Gradle (dystrybucja – Faza 6) |

## Szybki start (prod)

Wymagane: host Linux z Dockerem i Compose v2 (≥ 2.24), domena wskazująca na host, porty 80/443. Stos [`docker-compose.yml`](docker-compose.yml): Caddy (TLS ACME, [`Caddyfile`](Caddyfile)), Postgres 17, `silo-server` i `silo-web` z `ghcr.io/silopost/*` (tagi `SILO_SERVER_TAG`/`SILO_WEB_TAG`); serwer poczty jest zewnętrzny.

```sh
git clone --branch v0.5.0 https://github.com/silopost/silo.git && cd silo
cp .env.example .env    # sekcja "Produkcja": SILO_DOMAIN, SILO_SECRET_KEY (openssl rand -base64 32),
                        # SILO_POSTGRES_PASSWORD (openssl rand -hex 24), SILO_DEFAULT_IMAP_HOST
docker compose up -d
curl -fsS https://poczta.example.com/healthz
```

Pełna instrukcja (serwer domyślny z docker-mailserver, tryb `local` i pierwszy admin, hasła aplikacji, upgrade, backup, S3, fail2ban, OAuth2): [docs/admin](docs/admin/README.md). Kopię `SILO_SECRET_KEY` trzymaj osobno od backupów bazy.

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

`silo-mobile` nie jest częścią compose; do pracy nad aplikacją mobilną sklonuj je obok (`git clone https://github.com/silopost/silo-mobile.git`) – patrz [Stan: silo-mobile 0.1.0](#stan-silo-mobile-010).

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

DoD Fazy 3 (UI, wysyłka, undo, drafty, offline, a11y) i Fazy 4 (wyszukiwanie, snooze, schedule send, filtry, etykiety jako keywords, ustawienia, skróty) sprawdzają testy Playwright w `silo-web` (`npm run e2e`, opis w README `silo-web`; `npm run e2e -- --grep-invert @slow` pomija testy czekające 2–4 min); poniższy skrypt to szybki smoke API z Fazy 2.

Skrypt `scripts/e2e-smoke.sh` sprawdza na działającym stosie dev dwa punkty Definition of done Fazy 2:

- logowanie `dev1@silo.test` (`POST /api/v1/session`) do niepustej listy INBOX (`GET /api/v1/threads?labelId=INBOX`): **< 10 s** (initial sync),
- wiadomość wysłana `swaks` (w kontenerze `mailserver`) do `dev1@silo.test` pojawia się w strumieniu SSE (`GET /api/v1/events`) jako `message.new`: **< 2 s** (liczone od zakończenia `swaks`; skrypt podaje też czas od startu polecenia, który na Windows zawiera ~1 s narzutu `docker compose exec`).

```sh
scripts/dev-up.sh postgres mailserver silo-server
scripts/seed-mail.sh              # przed pierwszym logowaniem: konto Silo powstaje przy logowaniu
scripts/e2e-smoke.sh              # kod wyjścia 0 = progi dotrzymane, 1 = przekroczone lub błąd, 2 = brak serwera
```

Bez `jq` (parsowanie `grep`/`sed`), potrzebny tylko `curl` i `docker compose`. Adres bierze z `SILO_DEV_SERVER_PORT` w `.env` (nadpisanie: `SILO_E2E_BASE`), progi: `SILO_E2E_LIST_MAX_MS`, `SILO_E2E_EVENT_MAX_MS`. Pełny pomiar initial sync wymaga świeżej bazy (`docker compose -f docker-compose.dev.yml rm -sf silo-server postgres && docker volume rm silo_pgdata`); na kolejnych przebiegach lista jest dostępna od razu. Pomiar z 5.11.2026 (Windows, Docker Desktop): lista po 2,0 s od logowania (świeża baza, 54 wiadomości), `message.new` po ok. 0,5 s.

### Test backupu i odtwarzania (DoD Fazy 5)

`scripts/e2e-backup-restore.sh` przechodzi Definition of done Fazy 5 na osobnym stosie `docker-compose.backup-test.yml` (projekt `silo-bt`, obraz produkcyjny `silo-server`, porty `SILO_BT_*`: Postgres `15432`, serwer `18080`, IMAP `11143`, SMTP `12525`, submission `11587`; stos dev nie jest dotykany): seed, initial sync, etykieta użytkownika `Backup-Test` na 2 wątkach, archiwizacja, draft z załącznikiem, wiadomość zaplanowana na +1 h, snooze wątku na +1 h, filtr z etykietą `Backup-Test`, migawka listy INBOX, `scripts/backup.sh metadata`, usunięcie kontenerów oraz wolumenów `pgdata` i `blobs` (wolumen serwera poczty zostaje: to „zewnętrzny” IMAP, jak w produkcji), `scripts/restore.sh metadata` na pustą bazę, ponowne logowanie i porównanie: identyczne `GET /threads` dla INBOX, etykieta na 2 wątkach, draft (temat, treść, załącznik do pobrania) bez duplikatu, wiadomość w `SCHEDULED`, wątek w `SNOOZED` z tym samym czasem wybudzenia, filtr z etykietą wskazaną po nazwie. Procedura dla administratora: [docs/admin/backup.md](docs/admin/backup.md).

```sh
scripts/e2e-backup-restore.sh          # kod wyjścia 0 = PASS, 1 = FAIL; na końcu down -v projektu silo-bt
scripts/e2e-backup-restore.sh --keep   # zostawia stos silo-bt do oględzin
```

Pomiar z 6.11.2026 (Windows 11, Docker Desktop, 54 wiadomości, `silo-server` 0.5.0): initial sync 1,9 s od logowania; po restore konto `live` po 5,7 s, lista INBOX identyczna z migawką sprzed backupu, etykieta na 2 wątkach i snooze odtworzone po 70,7 s (snooze odtwarza job `metadata_restore`, który ponawia co minutę; bez snooze – 25,4 s, 5.11.2026); cały przebieg 156 s (z budową obrazu).

### Porty

Domyślnie: Postgres `5432`, silo-server `8080`, silo-web `5173`, IMAP `1143`, SMTP `2525`, submission `1587`. Gdy któryś jest zajęty, zmień w `.env` (kopia `.env.example`) odpowiednio `SILO_DEV_PG_PORT`, `SILO_DEV_SERVER_PORT`, `SILO_DEV_WEB_PORT`, `SILO_DEV_IMAP_PORT`, `SILO_DEV_SMTP_PORT`, `SILO_DEV_SUBMISSION_PORT` i uruchom `scripts/dev-up.sh` ponownie. Skrypty działają w Git Bash (Windows) i bash (Linux/macOS).

## Stan: Faza 5

Działa (UI `silo-web` 0.4.0 na API `silo-server` 0.5.0, dystrybucja `silo` 0.5.0), ponad Fazę 4:

- **Wiele kont** u jednego użytkownika: przełącznik kont z licznikami, `/u/<n>`, `g 1..9`, pole „Od” (draft przenosi się na wybrane konto), „Dodaj konto” z autokonfiguracją (ISPDB, autoconfig, SRV, zgadywanie z weryfikacją TLS) i testem połączenia; **izolacja użytkowników** sprawdzona testem każdego endpointu i SSE w obu kierunkach (cudze ID → `404`).
- **Tryb `local`** ([ADR 0011](docs/adr/0011-local-auth-mode-and-totp.md)): użytkownicy Silo z hasłem argon2id zakładani przez admina (`silo-server user`), **TOTP** z kodami zapasowymi, Ustawienia → Bezpieczeństwo (hasło, TOTP, sesje, „wyloguj wszędzie indziej”), **panel admina** (użytkownicy, stany kont, zadania `dead`).
- **OAuth2/XOAUTH2** dla Gmaila i Microsoft 365 ([ADR 0013](docs/adr/0013-oauth2-xoauth2.md), [docs/admin/oauth.md](docs/admin/oauth.md)); Gmail w trybie generycznym (`\All` z deduplikacją, archiwizacja bez duplikatów).
- **Backup i odtwarzanie** (`scripts/backup.sh`/`restore.sh`, tryby `metadata` i `full`, format `silo-metadata` v1 – [ADR 0014](docs/adr/0014-metadata-backup-format.md), [docs/admin/backup.md](docs/admin/backup.md)); **S3Store** ([ADR 0012](docs/adr/0012-s3-blobstore.md)).
- **Hardening:** limity per IP (`429 rate_limited`), maks. 8 strumieni SSE na użytkownika, nagłówki bezpieczeństwa i CSP, `SILO_TRUSTED_PROXIES`, log zdarzeń bezpieczeństwa dla fail2ban, anty-SSRF przy każdym połączeniu (`internal/netx`), `session.expired` zamyka strumień po wylogowaniu; model zagrożeń: [docs/threat-model.md](docs/threat-model.md).
- **PWA:** manifest, service worker z cache listy i treści, odczyt offline, baner nowej wersji; baner niezgodnej wersji z `minWebVersion`.
- **Produkcja:** `docker-compose.yml` z Caddy ([Szybki start (prod)](#szybki-start-prod)), test upgrade z poprzedniego tagu w CI `silo-server`.

Pomiary z 5–6.11.2026 (Windows 11, Docker Desktop): backup/odtwarzanie (`scripts/e2e-backup-restore.sh`, 54 wiadomości) – **PASS**: identyczne `GET /threads` INBOX (38 wątków), etykieta na 2 wątkach, draft z załącznikiem bez duplikatu, wiadomość zaplanowana, wątek odłożony z tym samym czasem wybudzenia i filtr z etykietą po nazwie; initial sync 1,9 s, restore → konto `live` 5,7 s, restore → pełna zgodność ze snooze 70,7 s (job `metadata_restore` ponawia co minutę). Skrzynka 200 000 wiadomości (`TestInitialSync`): initial sync 99 min 10 s bez błędów, RSS procesu maks. 77 MiB (próg 512 MB). Upgrade 0.4.0 → 0.5.0 na danych z filtrem i snooze (`scripts/upgrade-test.sh`): PASS (57 s, schemat 9 → 52, `reconcile` bez rozbieżności). e2e `silo-web`: wiele kont (liczniki obu kont, wysyłka z konta 2), tryb `local` z TOTP, PWA (lista offline po przeładowaniu po 281 ms), regresja archiwizacji/odpowiedzi/a11y – PASS. Stos produkcyjny zbudowany z kodu (`docker-compose.build.yml`): `/healthz`, `/api/v1/meta` i SPA przez Caddy z TLS, nagłówki i CSP SPA bez naruszeń (strona logowania w Chromium).

Po scaleniu (6.11.2026, dev compose, migracje 9 → 52): Playwright `silo-web` 25 testów bez `offline.e2e.ts` – przebieg zbiorczy 20/25, po dwóch poprawkach w `silo-web` 0.4.0 (liczniki świeżo dodanego konta w przełączniku, `g 1` na bieżącym koncie) i oczekiwaniu e2e na throttling logowania: `multi-account`, `reply`, `shortcuts` – PASS, `drafts` – PASS (33,6 s; dwa wcześniejsze przebiegi 35,6–35,9 s przy progu 35 s – do 5 s odpytywania kolejki jobów), `labels-keywords` – FAIL środowiskowy (INBOX `dev1@` wyczerpał limit 26 słów kluczowych maildir resztkami poprzednich przebiegów); `local-auth` na `silo-bt` – PASS. Szczegóły: plan, Faza 5.

Odłożone do 1.1: tryb `provider=gmail` (`X-GM-LABELS`/`X-GM-MSGID`/`X-GM-THRID` – etykiety Gmaila jako etykiety Silo, wątki Gmaila; brak konta testowego i symulatora X-GM), ManageSieve (filtry działają w Silo, nie na serwerze), OAuth2 dla klientów natywnych (wiązanie stanu ciasteczkiem – wariant z `redirectUri` w Fazie 6), API dla klientów offline (`GET /changes`, `ETag`/`If-None-Match` dla obiektów list – dziś `ETag` mają tylko niezmienne treści; `silo-web` tego nie wymaga, potrzebuje go `silo-mobile` w Fazie 6). Brak w UI: mapowanie ról folderów (API `PUT /accounts/{id}/folders` jest; role wykrywane z SPECIAL-USE i nazw). Niesprawdzone: Gmail i Microsoft 365 na żywych kontach (kroki ręczne w [macierzy](docs/compat-matrix.md#oauth2-i-xoauth2-faza-5)), migracja blobów `fs` → `s3`, fail2ban na żywym hoście.

## Stan: silo-mobile 0.1.0

Działa (aplikacja `silo-mobile` 0.1.0, niewydana, na API `silo-server` 0.4.0; [ADR 0010](docs/adr/0010-react-native-for-silo-mobile.md), plan – Faza 4m): parytet funkcji pocztowych z `silo-web` 0.3.0 i aplikacją Gmail na Androida – logowanie bearer z tokenem w Keystore ([ADR 0007](docs/adr/0007-bearer-tokens-for-native-clients.md)), szuflada z etykietami, wiele kont z przełącznikiem, lista wątków ze swipe i zaznaczaniem, akcje z „Cofnij”, widok wątku (HTML w WebView, obrazy `cid:`, załączniki, miniatury), compose (TipTap – drafty przechodzą między telefonem a przeglądarką, załączniki, obrazy w treści, undo send, zaplanowana wysyłka), wyszukiwanie z podpowiedziami i chipami, snooze, ustawienia (urządzenie + `/settings`), filtry, zarządzanie etykietami, sesje, zdarzenia na żywo (SSE przez strumieniowy `fetch`, fallback na polling, tylko na pierwszym planie). Z `silo-server` 0.3.0 działa zakres Fazy 3 – funkcje 0.4.0 są ukryte po `serverVersion` ([macierz kompatybilności](docs/compat-matrix.md#silo-mobile)).

Sprawdzone 6.11.2026 bez urządzenia: typecheck, lint, format, 405 testów (jest-expo + msw), bundel Hermes Androida (`expo export`, 8,4 MB), schemat zgodny z `v0.4.0`, smoke-test tylko-odczyt warstwy klienta na dev compose 14/14 (`npm run smoke:api`).

Nie działa jeszcze / niesprawdzone: aplikacja **nie była uruchamiana na urządzeniu ani emulatorze** (gesty, klawiatura edytora, WebView, pickery), iOS w ogóle, e2e z mutacjami i SSE na żywym API; brak powiadomień push, offline cache, podpisanego APK/AAB i F-Droid – Faza 6. Odstępstwa od parytetu: README `silo-mobile`, sekcja „Odstępstwa od parytetu”; luki kontraktu serwera: plan, Faza 6, i [docs/history/SILO-MOBILE-NOTES.md](docs/history/SILO-MOBILE-NOTES.md).

Jak uruchomić (szczegóły w README `silo-mobile`, sekcja „Uruchomienie”):

```sh
scripts/dev-up.sh postgres mailserver silo-server   # API dev; port z SILO_DEV_SERVER_PORT
scripts/seed-mail.sh --all                           # przed pierwszym logowaniem
cd ../silo-mobile && npm ci
npx expo start          # Expo Go na telefonie: zeskanuj kod QR (bez Android SDK)
npx expo run:android    # development build na emulatorze/urządzeniu (wymaga Android SDK)
```

Adres instancji na ekranie logowania: w emulatorze `http://10.0.2.2:<port>`, na telefonie adres LAN komputera (`localhost` to sam telefon); cleartext HTTP działa tylko w Expo Go i buildzie debug. Konto testowe np. `dev1@silo.test` / `devpass1`.

## Stan: Faza 4

Działa (UI `silo-web` 0.3.0 na API `silo-server` 0.4.0), ponad Fazę 3: wyszukiwanie ze składnią Gmaila parsowane na serwerze (`from:`, `to:`, `subject:`, `has:attachment`, `is:`, `label:`, `in:`, daty, rozmiary, `OR`, `-`, nawiasy; tokenizer w aplikacji – [ADR 0008](docs/adr/0008-search-tokenizer-in-app.md)) z podpowiedziami (historia, kontakty, etykiety, operatory), chipami, wyszukiwaniem zaawansowanym i banerem indeksowania; snooze (folder `Snoozed` na serwerze, presety w strefie użytkownika, wybudzanie co 30 s, nowa wiadomość budzi wątek, lista Odłożone); zaplanowana wysyłka (lista Zaplanowane, wiadomość nie istnieje na serwerze przed czasem); filtry (CRUD, „Utwórz filtr z wyszukiwania”, nowe wiadomości przy ingest, „Zastosuj do istniejących”, przekazywanie); etykiety użytkownika jako IMAP keywords (drzewo, kolory, zagnieżdżanie, stan per folder `mirrored`/`local_only`/`partial`, limit 26 słów kluczowych maildir liczony przez Silo – [ADR 0009](docs/adr/0009-keyword-state-per-folder.md)); odbudowa cache konta (`resync rebuild`, `silo-server rebuild-cache`); ustawienia (`GET/PATCH /settings`: gęstość, okres undo send, strefa, podpis, skróty, powiadomienia desktop); obrazy inline (`cid:`) w compose, miniatury obrazów, przekazanie z załącznikami oryginału; komplet skrótów z planu 6.6 (`g l`, `g 1..9`, `n p l v b`, `Ctrl+Enter`). Notatki administratora (limit keywordów, `rebuild-cache`, folder `Snoozed`, reindeks po upgrade): [docs/admin](docs/admin/README.md).

Pomiary e2e z 6.11.2026 (Windows 11, Docker Desktop, build produkcyjny przez `vite preview`, docker-mailserver 16): tag ustawiony drugim klientem IMAP (`UID STORE +FLAGS`) → etykieta na wierszu listy po 961–968 ms; etykieta z Silo jako keyword na serwerze w < 3 s; snooze „za minutę” → wiadomość w `Snoozed` na serwerze, poza INBOX, po czasie wybudzenia z powrotem w INBOX bez `\Seen` i na górze listy po 14,1–14,5 s (tick 30 s, próg 90 s); wiadomość zaplanowana ok. 2 min naprzód – przed czasem w żadnym folderze nadawcy ani w INBOX odbiorcy, dostarczona 4,4 s po czasie wysyłki (próg ±30 s); filtr `from:x → pomiń Odebrane + etykieta Y` – nowa wiadomość w Archive z keywordem Y, starsza po „Zastosuj”; wyszukiwanie z operatorami, podpowiedziami, chipami, wyszukiwaniem zaawansowanym i `422`; ustawienia po przeładowaniu, skróty wyłączone blokują `e`; komplet skrótów 6.6 (dwa scenariusze). Regresja Fazy 3 w tym samym przebiegu: `e` → wiersz poza DOM po 22,7 ms, Archive po 10,2 s (okno 10 s), draft w Drafts po 34,0 s, `syncNow` 78 ms, undo send – dostarczenie 0,5 s po oknie, 5000 wątków w 12,5 s z jednym long taskiem 54 ms, axe bez naruszeń.

Nie działa jeszcze: ekran „Dodaj konto” i mapowanie folderów w UI (konto powstaje przy logowaniu; API serwera jest), wiele kont w UI, OAuth2, tryb Gmail – Faza 5; obsługa odbić (bounce/DSN), miniatury i przeglądarka PDF (PDF otwiera się/pobiera w nowej karcie), preset „Jutro po południu” w zaplanowanej wysyłce – później. Do ręcznego sprawdzenia w Thunderbirdzie: lista w [docs/history/FAZA4-NOTES.md](docs/history/FAZA4-NOTES.md) (sekcja „Do sprawdzenia ręcznie”).

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
- [docs/admin/](docs/admin/README.md) – przewodnik administratora: instalacja produkcyjna, tryb `local`, hasła aplikacji, upgrade, [backup](docs/admin/backup.md), S3, hardening, [OAuth2](docs/admin/oauth.md)
- [docs/threat-model.md](docs/threat-model.md) – model zagrożeń
- [docs/history/](docs/history/FAZA4-NOTES.md) – archiwum notatek koordynatora faz ([Faza 4](docs/history/FAZA4-NOTES.md), [silo-mobile](docs/history/SILO-MOBILE-NOTES.md))
- [CONTRIBUTING.md](CONTRIBUTING.md) – konwencje i workflow dla wszystkich czterech repo

## Licencja

MIT (to repo) – zob. [LICENSE](LICENSE). `silo-server`, `silo-web` i `silo-mobile` są na AGPL-3.0.

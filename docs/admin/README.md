# Administracja instancją Silo

Przewodnik administratora instancji Silo (stan po Fazie 5: `silo` 0.5.0, `silo-server` 0.5.0, `silo-web` 0.4.0). Pełna lista zmiennych środowiskowych: README `silo-server` (sekcja „Configuration”) i [plan 2.5](../../ARCHITECTURE_AND_PLAN.md#25-konfiguracja-instancji-env); model zagrożeń: [threat-model.md](../threat-model.md).

Osobne strony: [backup i odtwarzanie](backup.md), [OAuth2 dla Gmaila i Microsoft 365](oauth.md).

## Instalacja produkcyjna

**Wymagania:** host Linux z Docker Engine i Compose v2 (≥ 2.24), rekord DNS (A/AAAA) domeny instancji wskazujący na host, otwarte porty 80 i 443 (Caddy pobiera certyfikat ACME), ruch wychodzący do serwerów poczty (IMAP 993/143, SMTP 587/465) i HTTPS (ISPDB, dostawcy OAuth2). Pamięć: `silo-server` mieści się w kilkuset MB (test 200k wiadomości: maks. 77 MiB RSS); dysk Postgresa i blobów rośnie jak rozmiar mirrorowanych skrzynek (limity `SILO_MIRROR_*`).

Stos [`docker-compose.yml`](../../docker-compose.yml) (projekt `silo-prod`): `caddy` (TLS, 80/443, [`Caddyfile`](../../Caddyfile): `/api/v1/events` bez buforowania, `/api/*` → `silo-server`, reszta → `silo-web`, nagłówki bezpieczeństwa i HSTS dla SPA), `postgres:17` (wolumen `pgdata`), `silo-server` (obraz `ghcr.io/silopost/silo-server:${SILO_SERVER_TAG}`, distroless nonroot, wolumen `blobs` przygotowywany przez `blobs-init`, bez portów na hoście) i `silo-web` (`ghcr.io/silopost/silo-web:${SILO_WEB_TAG}`, statyczny build serwowany przez nginx w obrazie). Serwer poczty jest zewnętrzny.

```sh
git clone --branch v0.5.0 https://github.com/silopost/silo.git && cd silo
cp .env.example .env
openssl rand -base64 32     # -> SILO_SECRET_KEY
openssl rand -hex 24        # -> SILO_POSTGRES_PASSWORD
$EDITOR .env                # sekcja "Produkcja": SILO_DOMAIN, klucze, SILO_DEFAULT_*
docker compose up -d
docker compose logs -f silo-server       # migracje przy starcie, potem nasłuch :8080
curl -fsS https://poczta.example.com/healthz && curl -fsS https://poczta.example.com/api/v1/meta
```

- **`.env`:** `docker-compose.yml` przekazuje do `silo-server` wszystkie zmienne `SILO_*` z `.env` (`env_file`; inny plik: `SILO_ENV_FILE`). Wymagane: `SILO_DOMAIN`, `SILO_SECRET_KEY`, `SILO_POSTGRES_PASSWORD` i w trybie `imap` `SILO_DEFAULT_IMAP_HOST`. `SILO_PUBLIC_URL` domyślnie `https://$SILO_DOMAIN` (musi zgadzać się z adresem w przeglądarce: sprawdzanie `Origin`, ciasteczko `Secure`, adres powrotu OAuth2).
- **`SILO_SECRET_KEY`** szyfruje hasła skrzynek, tokeny OAuth2 i sekrety TOTP. Zapisz kopię **osobno** od backupów bazy (menedżer haseł, sejf). Bez klucza backup nie odtworzy dostępu do skrzynek; rotacja: README `silo-server` (`rotate-secrets`).
- **`SILO_TRUSTED_PROXIES`:** sieć compose ma stałą podsieć `SILO_NETWORK_SUBNET` (domyślnie `172.29.250.0/24`, zmień przy kolizji); z niej przychodzi Caddy, więc tylko jej `X-Forwarded-For` jest honorowany. Caddy nie przekazuje dalej `X-Forwarded-For` od klientów (tylko od swoich zaufanych proxy), więc nagłówka nie da się podrobić z zewnątrz. Za dodatkowym balancerem dopisz jego adres w `SILO_TRUSTED_PROXIES` i w opcji `trusted_proxies` Caddy. Sprawdź w logu `security event`, że `ip=` to adresy klientów, a nie bramka dockera (Docker zachowuje adres źródłowy przy publikacji portów przez iptables; `userland-proxy` go gubi).
- **Serwer domyślny – docker-mailserver w innym compose na tym samym hoście:** dołącz kontener poczty do sieci Silo z aliasem równym nazwie z certyfikatu, żeby TLS się weryfikował, i ustaw tę nazwę jako `SILO_DEFAULT_IMAP_HOST`/`SILO_DEFAULT_SMTP_HOST`. W compose docker-mailservera (sieć `silo-prod_default` powstaje przy pierwszym `docker compose up` Silo):

  ```yaml
  services:
    mailserver:
      networks:
        default: {}
        silo:
          aliases: [mail.example.com]
  networks:
    silo:
      external: true
      name: silo-prod_default
  ```

  Host domyślny jest zaufany (nie przechodzi filtra anty-SSRF), więc adres prywatny jest w porządku. Serwer zewnętrzny: publiczna nazwa hosta, porty 993/`implicit` i 587/`starttls` (lub 465/`implicit`).
- **Pierwsze uruchomienie:** `silo-server` czeka na zdrowy Postgres, wykonuje migracje (pod `pg_advisory_lock`) i startuje. Tryb `imap`: pierwsze logowanie danymi skrzynki zakłada użytkownika i jego konto; admina nadaje `docker compose exec silo-server /silo-server user admin --email X --set=true`. Tryb `local` – niżej.
- **Budowa z kodu** (przed wydaniem obrazów lub do testów): `docker compose -f docker-compose.yml -f docker-compose.build.yml up -d --build` z repozytoriami `silo-server` i `silo-web` obok.
- Logi `silo-server`: sterownik `json-file` z rotacją (10 MB × 5); format `SILO_LOG_FORMAT` (`text` w `.env.example`, wygodny dla fail2ban).

## Tryb `local` i pierwszy admin

`SILO_AUTH_MODE=local` – użytkownicy Silo z własnym hasłem, zakładani przez admina; skrzynki (dowolne serwery, autokonfiguracja, OAuth2) dodają sami w UI ([ADR 0011](../adr/0011-local-auth-mode-and-totp.md)). `SILO_DEFAULT_IMAP_HOST` jest wtedy opcjonalny.

```sh
docker compose exec silo-server /silo-server user add --email admin@example.com --admin   # hasło wypisane raz
echo 'dlugie haslo' | docker compose exec -T silo-server /silo-server user add --email ala@example.com --password-stdin
docker compose exec -T silo-server /silo-server user passwd --email ala@example.com   # nowe hasło ze stdin
docker compose exec silo-server /silo-server user list
```

- **TOTP:** każdy użytkownik włącza go w `silo-web` (Ustawienia → Bezpieczeństwo: kod QR, 10 kodów zapasowych pokazywanych raz). Admin powinien mieć TOTP włączony. Zgubione urządzenie bez kodów: Administracja → Użytkownicy → reset TOTP (`POST /admin/users/{id}/totp/reset`).
- **Panel admina** (`silo-web` → Administracja, dla `isAdmin`): użytkownicy (zakładanie z hasłem tymczasowym, reset hasła, blokada – natychmiastowe wylogowanie i zatrzymanie synchronizacji kont, usunięcie z danymi Silo), konta (stan, błąd, `pendingOps`, `deadOps`), zadania `dead` (ponów / usuń). Admin nie może zablokować, zdegradować ani usunąć siebie.
- Zmiana trybu działającej instancji z `imap` na `local` nie była testowana; wybierz tryb przy instalacji (w razie zmiany nadaj użytkownikom hasła przez `user passwd`).

## Hasła aplikacji

Silo loguje się do skrzynek w tle, więc przechowuje poświadczenie odwracalnie (zaszyfrowane `SILO_SECRET_KEY`). Wyciek bazy **razem z kluczem** daje dostęp do wszystkich skrzynek ([threat-model.md](../threat-model.md)). Dlatego zamiast hasła głównego używaj poświadczeń odwoływalnych i przypisanych tylko do Silo:

- **Gmail / Google Workspace:** najlepiej OAuth2 („Zaloguj przez Google”, [oauth.md](oauth.md)); alternatywnie hasło aplikacji (wymaga weryfikacji dwuetapowej; konto Google → Bezpieczeństwo → Hasła do aplikacji) przy koncie z hasłem (`imap.gmail.com:993`, `smtp.gmail.com:465`).
- **Microsoft 365 (Exchange Online):** tylko OAuth2 – uwierzytelnianie hasłem dla IMAP/SMTP jest wyłączone. Outlook.com: OAuth2 (eksperymentalnie).
- **Dovecot / docker-mailserver:** natywnych haseł aplikacji nie ma; można dodać drugi `passdb` (np. `passwd-file` z osobnymi hasłami dla Silo) przed głównym, w docker-mailserverze przez nadpisanie konfiguracji Dovecota – SMTP AUTH Postfixa idzie przez Dovecot SASL, więc to samo hasło działa dla wysyłki. Takie hasło można odwołać bez zmiany hasła skrzynki (przykład konfiguracji nie jest testowany przez Silo).
- Hosting współdzielony: jeśli panel oferuje osobne hasła/konta IMAP dla aplikacji, użyj ich.

## Upgrade

1. Przeczytaj notatki wydania i [macierz kompatybilności](../compat-matrix.md) (wymagane pary `silo-server`/`silo-web`, migracje, reindeksy).
2. **Backup:** `scripts/backup.sh full` (i `metadata`) – [backup.md](backup.md).
3. Podbij tagi obrazów: nowy tag repo `silo` (`git pull && git checkout vX.Y.Z` – domyślne `SILO_SERVER_TAG`/`SILO_WEB_TAG` w `docker-compose.yml`) albo zmienne w `.env`.
4. `docker compose pull && docker compose up -d`. `silo-server` przy starcie wykonuje migracje pod `pg_advisory_lock` (`serve --migrate`, domyślnie włączone); stan: `docker compose exec silo-server /silo-server migrate version`. Migracje są addytywne w obrębie wydania (plan 2.4); migracje tylko tabel cache mogą wymagać `rebuild-cache` – zaznacza to changelog.
5. Zgodność klienta: `GET /api/v1/meta` zwraca `minWebVersion` (dla 0.5.0: `0.3.0`). Starszy `silo-web` w otwartej karcie pokazuje baner „Dostępna nowa wersja · Odśwież”; PWA – „Nowa wersja aplikacji gotowa”. Aktualizuj serwer i web razem (ten sam `docker compose up -d`).
6. Ścieżkę upgrade sprawdza CI `silo-server` (`scripts/upgrade-test.sh`, workflow `upgrade.yml`): obraz poprzedniego tagu z danymi (logowanie, wiadomości, etykieta, filtr, snooze) → bieżący obraz na tej samej bazie → ta sama skrzynka, `reconcile` bez rozbieżności. Lokalnie: 0.3.0 → 0.4.0+Faza 5 (schemat 5 → 51) i 0.4.0 → 0.5.0 (9 → 52) PASS.
7. Wycofanie: migracje nie mają automatycznego `down` między wydaniami – wróć do poprzednich tagów i `scripts/restore.sh full` z kroku 2.

## Backup i odtwarzanie

Szczegóły, harmonogram i procedura odtworzenia: [backup.md](backup.md). W skrócie: `scripts/backup.sh metadata` (mały JSON z danymi istniejącymi tylko w Silo, [ADR 0014](../adr/0014-metadata-backup-format.md)) codziennie, `scripts/backup.sh full` (`pg_dump` + wolumen blobów) rzadziej; `SILO_SECRET_KEY` osobno.

## S3Store

Bloby (surowe wiadomości, załączniki, uploady, miniatury) mogą leżeć w buckecie S3 zamiast wolumenu `blobs` ([ADR 0012](../adr/0012-s3-blobstore.md)). Zmienne (README `silo-server`, sekcja „S3Store”): `SILO_BLOB_BACKEND=s3`, `SILO_BLOB_S3_ENDPOINT`, `_BUCKET`, `_ACCESS_KEY`, `_SECRET_KEY`, `_REGION`, `_PREFIX`, `_USE_SSL`, `_PATH_STYLE`.

- **Bucket musi istnieć** – `serve` sprawdza go przy starcie i nie tworzy. MinIO: `mc mb silo/silo-blobs`; AWS: bucket prywatny (Block Public Access), użytkownik IAM z `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` na `arn:aws:s3:::BUCKET/*` i `s3:ListBucket` na bucket; `SILO_BLOB_S3_PATH_STYLE=false`, endpoint `s3.<region>.amazonaws.com`.
- MinIO na tym samym hoście: osobny kontener w sieci `silo-prod_default` (`SILO_BLOB_S3_ENDPOINT=minio:9000`, `SILO_BLOB_S3_USE_SSL=false` tylko w sieci wewnętrznej).
- `Put` buforuje blob w pliku tymczasowym kontenera (`/tmp`), żeby policzyć `sha256` – potrzeba miejsca na największy blob.
- Backup `full` nie obejmuje bucketu – użyj wersjonowania/replikacji dostawcy lub `mc mirror`.
- **Migracja z `fs` na `s3` (ręczna, nieprzetestowana end-to-end):** układ kluczy jest ten sam (`ab/cd/<sha256>`, w S3 z prefiksem), więc wystarczy skopiować wolumen do bucketu: zatrzymaj `silo-server` (`docker compose stop silo-server`), skopiuj zawartość wolumenu `silo-prod_blobs` z pominięciem plików `.tmp-*` (np. `mc mirror --exclude ".tmp-*" /var/lib/docker/volumes/silo-prod_blobs/_data silo/silo-blobs/<prefiks>`), ustaw `SILO_BLOB_BACKEND=s3` i `SILO_BLOB_S3_*`, `docker compose up -d`. Skrót: bloby mirrora (`kind=mirror`) to cache – brakujące zostaną pobrane z IMAP przy odczycie lub przez `rebuild-cache --all`; **bloby `local` (uploady, drafty, wiadomości zaplanowane) nie mają kopii na serwerze poczty i trzeba je skopiować** – bez kopiowania wysłanie zaplanowanych wiadomości i otwarcie załączników draftów się nie uda.

## Hardening

Mechanizmy po stronie serwera opisuje README `silo-server` (sekcja „Hardening”); tu – co ustawić na instancji.

- **Proxy i adres klienta:** `SILO_TRUSTED_PROXIES` (instalacja wyżej). Bez niego limity i logi widzą adres Caddy.
- **Limity:** `SILO_RATE_LIMIT_API` (domyślnie `600/m` na IP), `SILO_RATE_LIMIT_AUTH` (`20/m` na IP dla logowania, zmiany hasła, TOTP; dodatkowo limit na login); przekroczenie → `429 rate_limited` z `Retry-After`. Najwyżej 8 strumieni SSE na użytkownika. Limity są w pamięci procesu (jedna instancja).
- **Nagłówki:** API – `silo-server` (CSP `default-src 'none'`, `nosniff`, `DENY`, `no-referrer`, HSTS przy `https`; `SILO_HSTS=false`, gdy proxy wysyła HSTS samo lub subdomeny nie mają HTTPS). SPA – `Caddyfile` (CSP `script-src 'self'`, `style-src 'self' 'unsafe-inline'`, `img-src` z `https:`/`http:` dla obrazów zdalnych odblokowanych przez użytkownika w ramce wiadomości, HSTS `max-age=31536000; includeSubDomains`). Przy własnym proxy przenieś te nagłówki.
- **fail2ban:** `silo-server` loguje nieudane logowania, kody TOTP, odrzucenia CSRF, `403` i `429` jako `msg="security event" event=… ip=… path=… login=<zamaskowany>`. W pliku logu dockera (`json-file`) cudzysłowy są poprzedzone `\`, stąd filtr dla `SILO_LOG_FORMAT=text`:

  ```ini
  # /etc/fail2ban/filter.d/silo.conf
  [Definition]
  failregex = msg=\\"security event\\" event=(?:auth_failed|totp_failed|csrf_rejected) ip=<ADDR>
  ```

  ```ini
  # /etc/fail2ban/jail.d/silo.local
  [silo]
  enabled   = true
  filter    = silo
  logpath   = /var/lib/docker/containers/*/*-json.log
  port      = http,https
  # porty opublikowane przez Dockera omijają łańcuch INPUT
  chain     = DOCKER-USER
  banaction = iptables-multiport
  maxretry  = 10
  findtime  = 10m
  bantime   = 1h
  ```

  Przy sterowniku `journald` (`backend = systemd`, `journalmatch = CONTAINER_NAME=silo-prod-silo-server-1`) użyj filtrów z README `silo-server` (bez `\`). `rate_limited` w alternatywie daje ostrzejszy jail (uwaga na klientów za wspólnym NAT).
- **Pozostałe:** `SILO_ALLOW_CUSTOM_SERVERS=false` w trybie `imap`, jeśli użytkownicy nie potrzebują innych serwerów; nigdy `SILO_ALLOW_INSECURE_TRANSPORT` w produkcji; Postgres bez portu na hoście (jak w `docker-compose.yml`); szyfrowanie dysku i backupów.

## Autokonfiguracja kont

„Dodaj konto” w `silo-web` wywołuje `POST /api/v1/accounts/discover`, który podpowiada serwery IMAP/SMTP po adresie e-mail: ISPDB Thunderbirda, plik `autoconfig.<domena>` / `.well-known`, rekordy SRV (RFC 6186), na końcu zgadywanie `imap.`/`mail.`/`smtp.` z weryfikacją certyfikatu (README `silo-server`, sekcja „Account autoconfiguration”). Wynik i tak przechodzi test połączenia przed zapisaniem konta.

- `SILO_AUTOCONFIG_ISPDB_URL` – domyślnie `https://autoconfig.thunderbird.net/v1.1/`; własny mirror ISPDB lub `off` (bez zapytań do Mozilli; zostają autoconfig domeny, SRV i zgadywanie).
- Tryb `imap` bez `SILO_ALLOW_CUSTOM_SERVERS`: odpowiedź to serwer domyślny, bez ruchu sieciowego.
- Wszystkie połączenia autokonfiguracji idą przez filtr anty-SSRF: adresy prywatne są odrzucane, chyba że są na `SILO_CUSTOM_SERVER_ALLOWLIST` (nazwy hostów, IP lub CIDR – np. serwer poczty w sieci firmowej w trybie `local`). Limit 10 wywołań na minutę na użytkownika.
- Instancja potrzebuje wychodzącego HTTPS (443) i DNS (SRV).

## OAuth2 (Gmail, Microsoft 365)

Rejestracja aplikacji u Google i w Microsoft Entra, zmienne `SILO_OAUTH_*`, adresy przekierowania i diagnostyka: [oauth.md](oauth.md) ([ADR 0013](../adr/0013-oauth2-xoauth2.md)).

## Limit 26 słów kluczowych w folderze (Dovecot maildir)

Etykiety użytkownika Silo są zapisywane na wiadomościach jako IMAP keywords – Thunderbird pokazuje je jako tagi, a odbudowa cache je odczytuje ([plan 3.7](../../ARCHITECTURE_AND_PLAN.md#37-etykiety-użytkownika-jako-imap-keywords), [ADR 0009](../adr/0009-keyword-state-per-folder.md)).

- Dovecot z formatem **maildir** koduje słowa kluczowe literami `a`–`z` w nazwach plików, więc jeden folder ma najwyżej **26 różnych słów kluczowych** (łącznie z tagami Thunderbirda i innych klientów). Formaty **sdbox/mdbox** nie mają tego limitu.
- Dovecot 2.4 **nie odrzuca** 27. słowa kluczowego: `STORE` kończy się `OK`, ale słowo trafia tylko do indeksu Dovecota i ginie przy jego odbudowie. Dlatego Silo liczy słowa z `PERMANENTFLAGS` folderu i ponad limit nie zapisuje keywordu – etykieta zostaje tylko w Silo dla tego folderu (`keywordState: partial`, `localOnlyFolders`; w `silo-web` ostrzeżenie przy etykiecie). Odmowa `NO` serwera na `STORE` daje ten sam skutek.
- Limit ustawia `SILO_SYNC_KEYWORD_FOLDER_LIMIT` (domyślnie `26`). Dla sdbox/mdbox lub serwera bez limitu ustaw `0`.
- Dovecot nie usuwa słowa z listy folderu, gdy znikają wiadomości, które je miały. Folder, w którym wiele etykiet powstawało i znikało (np. skrzynka testowa e2e), może dojść do limitu mimo niewielu etykiet. Wyjścia: przenieść starą pocztę do innego folderu, odtworzyć folder (lub wolumen poczty w dev) albo przejść na sdbox/mdbox.
- Etykiety `partial` i `local_only` istnieją tylko w bazie Silo – obejmuje je backup Postgresa (plan 3.3).

## Odbudowa cache konta (`rebuild-cache`)

Silo przechowuje lustro poczty (wiadomości, położenia, wątki, bloby) jako cache odtwarzalny z serwera IMAP. Odbudowa usuwa cache konta i robi initial sync od zera.

```sh
silo-server rebuild-cache --account 1        # w kontenerze/środowisku instancji (SILO_DATABASE_URL)
silo-server rebuild-cache --account 1 --yes  # bez pytania o potwierdzenie
```

`--account` to numer konta (`acc_1` w API → `1`).

- To samo robi `POST /api/v1/accounts/{id}/resync` z `{"mode": "rebuild"}` (UI: Ustawienia → Konta → „Odbuduj cache”). Komenda tylko **kolejkuje** odbudowę (wiersz `account_rebuilds`); wykonuje ją działający `silo-server serve` (lub najbliższy start). Można jej użyć także po ręcznym `TRUNCATE` tabel cache.
- Odmowa `409 rebuild_blocked`, gdy wiadomość czeka na wysyłkę lub jest wysyłana (`outbound`) albo operacje czekają na zapis na serwerze (`imap_op`); ponów, gdy `sync-status.pendingOps` = 0.
- **Zostają:** etykiety (nazwy, kolory, drzewo, keywords), filtry, ustawienia, kontakty, historia wyszukiwań, lokalne wiadomości draftów i wysyłek.
- **Przenoszone po `dedupe_key`** (Message-ID + rozmiar) i przypinane, gdy wiadomości wracają: snooze, przypisania etykiet lokalnych (`local_only`, foldery `localOnlyFolders`), wiadomość, na którą odpowiada draft. Etykiety z keywordami wracają z serwera (także bez metadanych w tabeli `labels` – są tworzone ponownie z nazw keywordów).
- **Giną:** możliwość cofnięcia (undo) operacji sprzed odbudowy.
- Czas: initial sync całego konta (na dev ~2 s dla kilkudziesięciu wiadomości; duże skrzynki – minuty do godzin, wg `SILO_SYNC_BACKFILL_RATE`).

## Folder `Snoozed`

- Odłożenie wątku (snooze) przenosi jego wiadomości z INBOX do folderu roli `snoozed` – domyślnie `Snoozed`, tworzonego przez Silo przy pierwszym użyciu (jak Archive) – i dodaje keyword `$SiloSnoozed`. Inne programy pocztowe nie pokazują ich więc w Odebranych ([plan 3.10](../../ARCHITECTURE_AND_PLAN.md#310-snooze)).
- Inną nazwę folderu można zmapować przez `PUT /accounts/{id}/folders` (rola `snoozed`); istniejący folder o nazwie `Snoozed` jest wykrywany automatycznie.
- Wybudza job `snooze_wake` (co 30 s i przy nowej wiadomości w odłożonym wątku): wiadomości wracają do INBOX, najnowsza nieprzeczytana, bez `$SiloSnoozed`. **Wymaga działającego Silo** – gdy instancja stoi, poczta czeka bezpiecznie w `Snoozed` i wraca po starcie.
- Przeniesienie wiadomości z `Snoozed` w innym kliencie kasuje snooze w Silo (≤ 30 s). Usunięcie lub odtworzenie folderu z tymi samymi wiadomościami (nowe `UIDVALIDITY`) nie gubi snooze.
- Nie usuwaj folderu `Snoozed` z wiadomościami, jeśli instancja ma aktywne snooze – wiadomości wrócą do INBOX dopiero po ich ponownym znalezieniu przez sync.

## Reindeks wyszukiwania po upgrade

- Indeks pełnotekstowy (`messages.search_tsv`) buduje tokenizer aplikacji ([ADR 0008](../adr/0008-search-tokenizer-in-app.md)); każdy wiersz ma wersję tokenizera (`messages.search_ver`).
- Po upgrade do wersji z nowym tokenizerem (pierwszy raz: 0.3.0 → 0.4.0, migracja `000006_search_index`) `silo-server` przy starcie przeindeksowuje w tle wiersze ze starszą wersją, paczkami po 500 (log `search index rebuilt messages=… took=…`; na dev 5158 wiadomości w < 1 s). Do końca reindeksu wyniki po starszych wiadomościach mogą być niepełne; odpowiedź wyszukiwania niesie wtedy `indexing`, a UI pokazuje „Indeksowanie treści”.
- Migracje 0.4.0 (`000006`–`000009`) są addytywne (nowe kolumny, tabele, indeksy) i wykonują się automatycznie przy starcie (`serve`, chyba że `--migrate=false`). Przed upgrade zrób backup Postgresa.

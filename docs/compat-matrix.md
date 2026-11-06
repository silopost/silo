# Macierz kompatybilności

Szkielet; wypełniany przed każdym release. Kontekst: [plan 2.1](../ARCHITECTURE_AND_PLAN.md#21-struktura-silo) i [2.4](../ARCHITECTURE_AND_PLAN.md#24-wersjonowanie-i-kontrakt).

## 1. Wersje `silo-server` / `silo-web` / `silo-mobile`

Przed 1.0 zmiany łamiące kontrakt API są opisywane tutaj. `silo-mobile` nie jest częścią dystrybucji `silo` (aplikacja na telefon, nie obraz) – kolumna mówi, która wersja aplikacji jest zbudowana na kontrakcie danego wydania serwera; zgodność z innymi wersjami serwera – [niżej](#silo-mobile).

| silo | silo-server | silo-web | silo-mobile | Uwagi |
|---|---|---|---|---|
| 0.5.0 | 0.5.0 | 0.4.0 | 0.1.0 (bez zmian) | kontrakt API Fazy 5 (addytywny wobec 0.4.0): `/settings` bez zmian (`activeAccountId` wybiera konto); `PUT /drafts/{id}` z `accountId` przenosi nową wiadomość na inne konto jako nowy draft (nowe `id`/`messageId`/`threadId`, `draft.updated.previousDraftId`; odpowiedź/przekazanie → `409 draft_account_locked`); tryb `local`: `POST /session/password`, `/totp/setup`, `/totp/enable`, `DELETE /totp`, `/totp/backup-codes`, `totpCode` w `POST /session` (`401 totp_required`), `user.totpEnabled`; `/admin/users`, `/admin/accounts` (z `authType`), `/admin/jobs` (`403` dla nie-admina); `POST /accounts/discover`; OAuth2: `POST /oauth/{provider}/start`, `GET /oauth/{provider}/callback`, `meta.oauthProviders`, `Account.authType` (`password`/`xoauth2`); `DELETE /sessions?others=true`; SSE `session.expired` i `stream.limit` (maks. 8 strumieni na użytkownika), `label.counts` po `account.status` `live`; `429 rate_limited` z `Retry-After`; `POST /accounts/{id}/resync {mode: rebuild}` bez zmian; `minWebVersion` = `0.3.0`. Migracje `000050`–`000052` addytywne (upgrade 0.4.0 → 0.5.0 sprawdzony testem upgrade). `silo-web` 0.3.0 działa z `silo-server` 0.5.0; `silo-web` 0.4.0 wymaga `silo-server` ≥ 0.5.0 |
| 0.4.0 | 0.4.0 | 0.3.0 | 0.1.0 | kontrakt API Fazy 4 (addytywny wobec 0.3.0): wyszukiwanie ze składnią Gmaila (`GET /threads?q=` z `indexing`/`approximate`/`resultSizeEstimate`, `422 invalid_query`, `GET /search/suggest`, `DELETE /search/history`), snooze (`POST`/`DELETE /threads/{id}/snooze`, `GET /snooze/presets`, rola folderu `snoozed`), schedule send (`Thread.scheduledAt`/`outboundId`), filtry (`/filters` CRUD, `POST /filters/{id}/apply`, `filter.applied`), `GET/PATCH /settings` (`desktopNotifications`, `updatedAt`, `settings.updated`; `SessionInfo.settings` zyskało te pola), uploady `inline` z `cid` i miniatury (`GET /attachments/{id}/thumbnail`, `thumbnail`/`cid`/`inline` przy załącznikach, `415 thumbnail_unsupported`), `Draft.warnings` (forward z załącznikami oryginału), `Thread.snoozedUntil`, etykiety `keywordState` `mirrored`/`local_only`/`partial` z `localOnlyFolders`, `PATCH /labels/{id}` z `parentId` (`422 invalid_parent`), `POST /accounts/{id}/resync {mode: rebuild}` (`409 rebuild_blocked`). Migracje `000006`–`000009` addytywne; reindeks wyszukiwania w tle po upgrade (`docs/admin`). `silo-web` 0.2.0 działa z `silo-server` 0.4.0; `silo-web` 0.3.0 wymaga `silo-server` ≥ 0.4.0 |
| 0.3.0 | 0.3.0 | 0.2.0 | 0.1.0 (zakres Fazy 3) | kontrakt API Fazy 3 (addytywny wobec 0.2.0, poza poprawkami schematu na końcu wiersza): logowanie bearer dla klientów natywnych (`POST /session` z `client`, `Authorization: Bearer`, ADR 0007), `/operations/{id}/undo`, `/uploads`, drafty (`/drafts`, `PUT` z `version` i `syncNow`, jedna kopia w Drafts), wysyłka (`/drafts/{id}/send`, `/outbound/{id}/cancel` – undo send, `SCHEDULED`/`SENT`, APPEND do Sent, `\Answered`), `/contacts/autocomplete`, `Account.position`, `Message.draftId`/`Thread.draftId`, `Draft.lastSend`, `meta.maxAttachmentBytes`, pola problemów (`limit`/`size`, `currentVersion`/`current`, `address`/`field`), `operation.failed.kind`, `outbound.status` z `draftId`. Schemat: `Draft.lastSend` i `Message.folder` mogą być `null`, `Message.replyTo` jest pomijane bez nagłówka Reply-To (wcześniej błędnie wymagane). `silo-web` 0.2.0 wymaga `silo-server` ≥ 0.3.0 |
| 0.2.0 | 0.2.0 | 0.1.0 | – | kontrakt API Fazy 2: session, accounts, labels, threads, messages, events; przed 1.0 breaking changes dopuszczalne |
| edge | edge | edge | `main` | obrazy `:edge`, bez gwarancji kompatybilności |

### `silo-mobile`

| silo-mobile | silo-server | Uwagi |
|---|---|---|
| 0.1.0 (niewydane) | 0.5.0 | oczekiwany zakres jak przy 0.4.0 (kontrakt 0.5.0 jest addytywny; niesprawdzone). Nowości 0.5.0 nieobsługiwane: logowanie z TOTP (`401 totp_required` – brak pola kodu), dodawanie kont OAuth2 (wymaga wariantu dla klienta natywnego, Faza 6), panel admina, zmiana „Od” w drafcie, `DELETE /sessions?others=true`; konta OAuth2 dodane w `silo-web` synchronizują się normalnie |
| 0.1.0 (niewydane) | 0.4.0 | pełny zakres: schemat wygenerowany z OpenAPI `v0.4.0` (`silo.serverRef`), parytet poczty z `silo-web` 0.3.0 (Fazy 3–4), [ADR 0010](adr/0010-react-native-for-silo-mobile.md). Funkcje kontraktu 0.4.0 (wyszukiwanie z operatorami i podpowiedziami, snooze, zaplanowana wysyłka, `/settings`, filtry, zarządzanie etykietami, miniatury, obrazy w treści) bramkowane po `Meta.serverVersion` (`src/lib/features.ts`), bo `/meta` nie ma flag funkcji; wersja nieparsowalna (`dev`) = najnowsza. Sprawdzone testami (405), bundlem Androida i smoke-testem tylko-odczyt na dev compose (14/14), nie na urządzeniu |
| 0.1.0 (niewydane) | 0.3.0 | zakres Fazy 3: logowanie bearer, lista, wątek, akcje i „Cofnij”, compose i undo send, załączniki, konta, sesje, zdarzenia; ustawienia tylko na urządzeniu, wyszukiwanie tylko tekstu; funkcje 0.4.0 ukryte |
| – | ≤ 0.2.0 | nieobsługiwane (brak logowania bearer, ADR 0007) |

## 2. Serwery pocztowe IMAP/SMTP

Oczekiwania wyjściowe – **do potwierdzenia testem**. Scenariusz ręczny: dodaj konto, initial sync, archiwizuj, etykieta, snooze, wyślij, odpowiedź z innego klienta.

| Serwer | IDLE | CONDSTORE/QRESYNC | MOVE/UIDPLUS | SPECIAL-USE | Keywords (`PERMANENTFLAGS \*`) | Uwagi | Status |
|---|---|---|---|---|---|---|---|
| Dovecot 2.3/2.4 (docker-mailserver) | tak | tak (CONDSTORE używany; QRESYNC nieużywany – brak w go-imap/v2 beta.8, ADR 0006) | tak | tak | tak (maildir: max 26 słów kluczowych na folder; 2.4 nie odrzuca 27. – Silo liczy limit sam, ADR 0009) | serwer referencyjny; `CREATE-SPECIAL-USE` jest ignorowany przez Dovecota (rola folderu wynika z konfiguracji serwera) | potwierdzono (Faza 2, wysyłka/Drafts/Sent: Faza 3, snooze/keywords/rebuild: Faza 4) |
| Dovecot 2.4 z `passdb oauth2` (XOAUTH2) | tak | tak | tak | tak | tak | `AUTHENTICATE XOAUTH2` (IMAP) i `AUTH XOAUTH2` (SMTP), token sprawdzany introspekcją RFC 7662 u atrapy dostawcy | potwierdzono testcontainers (Faza 5: profil `oauth2`, `TestOAuthAccount`) |
| Gmail IMAP | tak | CONDSTORE tak, QRESYNC nie | tak | tak (`\All`) | nie (etykiety = foldery) | **tryb generyczny z OAuth2** (lub hasłem aplikacji): `\All` z deduplikacją, archiwizacja = usunięcie kopii z INBOX, `sentAppend` wyłączone (Sent zapisuje sam); etykiety Gmaila niewidoczne, wątki JWZ Silo – tryb `provider=gmail` (X-GM) odłożony do 1.1 ([ADR 0013](adr/0013-oauth2-xoauth2.md)) | tryb generyczny z OAuth2: potwierdzono testami (profil `gmail-like`, Dovecot `oauth2`); na żywo do potwierdzenia ręcznie ([kroki](#oauth2-i-xoauth2-faza-5)) |
| Office 365 / Outlook.com | tak | nie | tak | tak | nie / niepewne | tylko OAuth2 (basic auth wyłączony): `outlook.office365.com:993`, `smtp.office365.com:587` STARTTLS (SMTP AUTH musi być włączony dla skrzynki), `sentAppend` wyłączone; Outlook.com eksperymentalnie | OAuth2/XOAUTH2 potwierdzono testami (atrapa dostawcy, Dovecot `oauth2`, `scope` przy odświeżaniu); na żywo do potwierdzenia ręcznie ([kroki](#oauth2-i-xoauth2-faza-5)) |
| Courier IMAP | tak (zależnie od konfiguracji) | nie | zależnie od wersji | częściowo | tak przy `IMAP_KEYWORDS=1` | popularny na hostingach współdzielonych | do potwierdzenia |

### Potwierdzenie Dovecota (Faza 2)

Sprawdzone testami integracyjnymi `silo-server` na `dovecot/dovecot:2.4.5` (testcontainers) oraz e2e na docker-mailserver 16 (`scripts/e2e-smoke.sh`): `IDLE` (`message.new` w SSE po ok. 0,5 s od dostarczenia), `CONDSTORE` (przyrostowy sync po `HIGHESTMODSEQ`/`CHANGEDSINCE`), `MOVE`/`UIDPLUS` (`COPYUID`), `SPECIAL-USE`, keywords (`PERMANENTFLAGS \*`, etykiety użytkownika). `QRESYNC` jest reklamowany, ale nieużywany do czasu łatki lub forka `imapx`.

Profile testowe, zweryfikowane jako fallbacki (ten sam zestaw testów sync przechodzi):

| Profil | Reklamuje | Ścieżka |
|---|---|---|
| `full` | domyślne Dovecota (`CONDSTORE QRESYNC MOVE UIDPLUS IDLE SPECIAL-USE ...`) | główna |
| `no-condstore` | bez `CONDSTORE QRESYNC` | pełne porównanie UID + flagi |
| `no-move` | bez `MOVE UIDPLUS` | kopia + `\Deleted` (bez `EXPUNGE` poza Trash/Drafts) |

### Potwierdzenie Dovecota i Postfixa: wysyłka, Drafts, Sent (Faza 3)

Sprawdzone testami Playwright `silo-web` (`npm run e2e`) na docker-mailserver 16 (Dovecot 2.4, Postfix submission na 587 bez TLS w dev), stan serwera odczytany drugim klientem IMAP (`imapflow`), 5.11.2026:

- **Wysyłka (SMTP submission, AUTH PLAIN):** odpowiedź z Silo dociera do `dev2@` z `In-Reply-To` = `Message-ID` oryginału i `References` zawierającym go; undo send w oknie – nic nie dociera (sprawdzone po 12 s); bez cofnięcia dostarczenie ok. 0,6 s po końcu okna.
- **Sent:** dokładnie jedna kopia (APPEND z `\Seen`, ten sam `Message-ID`), w Silo bez duplikatu (Matcher przypina kopię do lokalnej wiadomości); oryginał dostaje `\Answered`.
- **Drafts:** draft w folderze Drafts po ok. 32 s od ostatniej zmiany (opóźnienie 30 s), po każdej edycji nadal jedna wiadomość (APPEND nowej wersji, usunięcie starej), `syncNow` przy zamknięciu okna – nowa wersja w < 1 s.
- **Archive i undo:** `MOVE` do Archive po 10,3–10,4 s (okno 10 s); „Cofnij” w oknie – wiadomość zostaje w INBOX z tym samym UID (brak `MOVE`; serwer dev nie loguje komend IMAP, UID jest dowodem), Archive pusty.
- **Serwer pocztowy niedostępny:** `docker compose stop mailserver` → konto w `backoff`, operacje czekają (`pendingSync`); po `start` wykonane bez odświeżenia UI po ok. 17 s (backoff 5 s / 15 s).

### Potwierdzenie Dovecota: snooze, keywords per folder, odbudowa cache (Faza 4)

Sprawdzone testami integracyjnymi `silo-server` na `dovecot/dovecot:2.4.5` (testcontainers, profile `full` i `no-move`) oraz Playwright `silo-web` na docker-mailserver 16 (Dovecot 2.4), stan serwera odczytany drugim klientem IMAP, 6.11.2026:

- **Snooze:** wiadomości wątku w folderze `Snoozed` (tworzonym przez Silo, z keywordem `$SiloSnoozed`) i nie w INBOX; po czasie wracają do INBOX bez `Seen` na najnowszej wiadomości; przeniesienie z `Snoozed` do INBOX drugim klientem kasuje snooze; snooze przetrwa `DELETE` + `CREATE` folderu `Snoozed` z tymi samymi wiadomościami (nowe `UIDVALIDITY`). Na profilu `no-move` – kopia + `Deleted`, bez utraty snooze.
- **Keywords:** etykieta Silo jako keyword na serwerze; keyword ustawiony drugim klientem (`UID STORE +FLAGS`, jak tag Thunderbirda) jako etykieta w Silo – INBOX przez IDLE w ok. 0,6 s (testy serwera) i ok. 1 s na wierszu listy w UI (e2e); inne foldery w interwale pollingu.
- **Limit 26 (maildir):** Dovecot 2.4.5 **nie odrzuca** 27. słowa kluczowego (`STORE` → `OK`, słowo tylko w indeksie, ginie przy jego odbudowie). Silo liczy słowa z `PERMANENTFLAGS` folderu (`SILO_SYNC_KEYWORD_FOLDER_LIMIT`, domyślnie 26) i ponad limit oznacza etykietę jako `partial` dla folderu (ADR 0009); ścieżka „serwer odpowiada `NO`” sprawdzona wstrzykniętą odpowiedzią. Słowa nie znikają z listy folderu po usunięciu wiadomości – patrz `docs/admin`.
- **Odbudowa cache** (`resync rebuild` / `rebuild-cache`): etykiety użytkownika odtworzone z keywordów (porównanie zbiorów `(Message-ID, etykieta)` przed i po, także bez wierszy `labels`), ten sam podział na wątki, snooze i etykiety lokalne przeniesione; 33 wiadomości w ok. 2 s.
- **Schedule send:** wiadomość zaplanowana nie istnieje na serwerze (żaden folder nadawcy, INBOX odbiorcy) przed czasem; dostarczenie po czasie wysyłki (testy serwera: ok. 0,1 s po `sendAt`).
- **Filtry:** nowa wiadomość pasująca do `from:x` → `MOVE` do Archive + keyword etykiety; „Zastosuj” przenosi starsze.

### OAuth2 i XOAUTH2 (Faza 5)

Sprawdzone testami `silo-server` (testcontainers, 6.11.2026): XOAUTH2 dla IMAP i SMTP na Dovecocie 2.4.5 z `passdb oauth2` (profil `oauth2`; token weryfikowany introspekcją RFC 7662 u atrapy dostawcy `testutil/oauthtest`) i `smtptest` z `AUTH XOAUTH2`; pełny przepływ `start` → callback → test IMAP/SMTP → konto → initial sync (`TestOAuthAccount`); odświeżanie tokenu (Microsoft z `scope`), `invalid_grant` → `auth_failed` i ponowna autoryzacja. Tryb generyczny Gmaila na profilu `gmail-like` (`[Gmail]/All Mail` = `\All`): jedna wiadomość dla kopii w INBOX i All Mail, archiwizacja usuwa tylko kopię z INBOX, bez folderu Archive (`TestGmailGenericMode`).

**Na żywo nieprzetestowane** (brak kont testowych Google i Microsoft 365). Test ręczny przed wpisaniem „potwierdzono” (konfiguracja: [docs/admin/oauth.md](admin/oauth.md)):

1. „Zaloguj przez Google” (lub Microsoft) dodaje konto i wraca do `silo-web` z `oauth=ok`.
2. Initial sync kończy się stanem `live`; INBOX zgodny z webmailem.
3. Archiwizacja wątku: znika z Odebranych w webmailu, zostaje we „Wszystkich” (Gmail) / w Archiwum (Microsoft); w Silo bez duplikatu.
4. Etykieta użytkownika Silo zapisana na serwerze (keyword; Gmail keywordów nie pokazuje jako etykiet).
5. Wysyłka: wiadomość dostarczona, dokładnie jedna kopia w Wysłanych.
6. Odpowiedź z innego klienta dołącza do wątku w Silo.
7. Odwołanie dostępu aplikacji u dostawcy: konto przechodzi w `auth_failed` przy następnym połączeniu; „Zaloguj ponownie” przywraca synchronizację.

Dla Microsoft 365 skrzynka musi mieć włączone IMAP i Authenticated SMTP.

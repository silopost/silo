# Macierz kompatybilności

Szkielet; wypełniany przed każdym release. Kontekst: [plan 2.1](../ARCHITECTURE_AND_PLAN.md#21-struktura-silo) i [2.4](../ARCHITECTURE_AND_PLAN.md#24-wersjonowanie-i-kontrakt).

## 1. Wersje `silo-server` / `silo-web`

Przed 1.0 zmiany łamiące kontrakt API są opisywane tutaj.

| silo | silo-server | silo-web | Uwagi |
|---|---|---|---|
| 0.3.0 | 0.3.0 | 0.2.0 | kontrakt API Fazy 3 (addytywny wobec 0.2.0, poza poprawkami schematu na końcu wiersza): logowanie bearer dla klientów natywnych (`POST /session` z `client`, `Authorization: Bearer`, ADR 0007), `/operations/{id}/undo`, `/uploads`, drafty (`/drafts`, `PUT` z `version` i `syncNow`, jedna kopia w Drafts), wysyłka (`/drafts/{id}/send`, `/outbound/{id}/cancel` – undo send, `SCHEDULED`/`SENT`, APPEND do Sent, `\Answered`), `/contacts/autocomplete`, `Account.position`, `Message.draftId`/`Thread.draftId`, `Draft.lastSend`, `meta.maxAttachmentBytes`, pola problemów (`limit`/`size`, `currentVersion`/`current`, `address`/`field`), `operation.failed.kind`, `outbound.status` z `draftId`. Schemat: `Draft.lastSend` i `Message.folder` mogą być `null`, `Message.replyTo` jest pomijane bez nagłówka Reply-To (wcześniej błędnie wymagane). `silo-web` 0.2.0 wymaga `silo-server` ≥ 0.3.0 |
| 0.2.0 | 0.2.0 | 0.1.0 | kontrakt API Fazy 2: session, accounts, labels, threads, messages, events; przed 1.0 breaking changes dopuszczalne |
| edge | edge | edge | obrazy `:edge`, bez gwarancji kompatybilności |

## 2. Serwery pocztowe IMAP/SMTP

Oczekiwania wyjściowe – **do potwierdzenia testem**. Scenariusz ręczny: dodaj konto, initial sync, archiwizuj, etykieta, snooze, wyślij, odpowiedź z innego klienta.

| Serwer | IDLE | CONDSTORE/QRESYNC | MOVE/UIDPLUS | SPECIAL-USE | Keywords (`PERMANENTFLAGS \*`) | Uwagi | Status |
|---|---|---|---|---|---|---|---|
| Dovecot 2.3/2.4 (docker-mailserver) | tak | tak (CONDSTORE używany; QRESYNC nieużywany – brak w go-imap/v2 beta.8, ADR 0006) | tak | tak | tak (maildir: max 26 słów kluczowych na folder) | serwer referencyjny; `CREATE-SPECIAL-USE` jest ignorowany przez Dovecota (rola folderu wynika z konfiguracji serwera) | potwierdzono (Faza 2, wysyłka/Drafts/Sent: Faza 3) |
| Gmail IMAP | tak | CONDSTORE tak, QRESYNC nie | tak | tak (`\All`) | nie (etykiety = foldery) | tryb `provider=gmail` w fazie 5; Sent zapisuje sam | do potwierdzenia |
| Office 365 / Outlook.com | tak | nie | tak | tak | nie / niepewne | wymaga OAuth2 (basic auth wyłączony) – faza 5 | do potwierdzenia |
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

# Macierz kompatybilności

Szkielet; wypełniany przed każdym release. Kontekst: [plan 2.1](../ARCHITECTURE_AND_PLAN.md#21-struktura-silo) i [2.4](../ARCHITECTURE_AND_PLAN.md#24-wersjonowanie-i-kontrakt).

## 1. Wersje `silo-server` / `silo-web`

Przed 1.0 zmiany łamiące kontrakt API są opisywane tutaj.

| silo | silo-server | silo-web | Uwagi |
|---|---|---|---|
| 0.2.0 | 0.2.0 | 0.1.0 | kontrakt API Fazy 2: session, accounts, labels, threads, messages, events; przed 1.0 breaking changes dopuszczalne |
| edge | edge | edge | obrazy `:edge`, bez gwarancji kompatybilności |

## 2. Serwery pocztowe IMAP/SMTP

Oczekiwania wyjściowe – **do potwierdzenia testem**. Scenariusz ręczny: dodaj konto, initial sync, archiwizuj, etykieta, snooze, wyślij, odpowiedź z innego klienta.

| Serwer | IDLE | CONDSTORE/QRESYNC | MOVE/UIDPLUS | SPECIAL-USE | Keywords (`PERMANENTFLAGS \*`) | Uwagi | Status |
|---|---|---|---|---|---|---|---|
| Dovecot 2.3/2.4 (docker-mailserver) | tak | tak (CONDSTORE używany; QRESYNC nieużywany – brak w go-imap/v2 beta.8, ADR 0006) | tak | tak | tak (maildir: max 26 słów kluczowych na folder) | serwer referencyjny; `CREATE-SPECIAL-USE` jest ignorowany przez Dovecota (rola folderu wynika z konfiguracji serwera) | potwierdzono (Faza 2) |
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

# Macierz kompatybilności

Szkielet; wypełniany przed każdym release. Kontekst: [plan 2.1](../ARCHITECTURE_AND_PLAN.md#21-struktura-silo) i [2.4](../ARCHITECTURE_AND_PLAN.md#24-wersjonowanie-i-kontrakt).

## 1. Wersje `silo-server` / `silo-web`

Przed 1.0 zmiany łamiące kontrakt API są opisywane tutaj.

| silo | silo-server | silo-web | Uwagi |
|---|---|---|---|
| edge | edge | edge | obrazy `:edge`, bez gwarancji kompatybilności |

## 2. Serwery pocztowe IMAP/SMTP

Oczekiwania wyjściowe – **do potwierdzenia testem**. Scenariusz ręczny: dodaj konto, initial sync, archiwizuj, etykieta, snooze, wyślij, odpowiedź z innego klienta.

| Serwer | IDLE | CONDSTORE/QRESYNC | MOVE/UIDPLUS | SPECIAL-USE | Keywords (`PERMANENTFLAGS \*`) | Uwagi | Status |
|---|---|---|---|---|---|---|---|
| Dovecot 2.3/2.4 (docker-mailserver) | tak | tak | tak | tak | tak (maildir: max 26 słów kluczowych na folder) | serwer referencyjny | do potwierdzenia |
| Gmail IMAP | tak | CONDSTORE tak, QRESYNC nie | tak | tak (`\All`) | nie (etykiety = foldery) | tryb `provider=gmail` w fazie 5; Sent zapisuje sam | do potwierdzenia |
| Office 365 / Outlook.com | tak | nie | tak | tak | nie / niepewne | wymaga OAuth2 (basic auth wyłączony) – faza 5 | do potwierdzenia |
| Courier IMAP | tak (zależnie od konfiguracji) | nie | zależnie od wersji | częściowo | tak przy `IMAP_KEYWORDS=1` | popularny na hostingach współdzielonych | do potwierdzenia |

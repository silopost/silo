# 0005. IMAP jako źródło prawdy; Silo jest klientem, nie serwerem

- **Status:** Przyjęty
- **Data:** 2026-11-05
- **Dotyczy:** silo, silo-server, silo-web

## Kontekst

Silo ma dawać funkcje Gmaila (wątki, etykiety, snooze, undo send) na istniejącym serwerze poczty, a użytkownik może równolegle używać Thunderbirda lub telefonu ([plan 1](../../ARCHITECTURE_AND_PLAN.md#1-cel-i-zasady)). Odczyty muszą być szybkie, więc Silo trzyma lokalny mirror w Postgresie. Trzeba rozstrzygnąć, kto ma rację przy rozbieżnościach, i jaki jest zakres odpowiedzialności produktu.

## Decyzja

1. **Serwer IMAP jest źródłem prawdy dla poczty:** istnienie wiadomości, treść, folder i standardowe flagi. Postgres to cache/mirror ([plan 3.3](../../ARCHITECTURE_AND_PLAN.md#33-źródło-prawdy-serwer-imap-vs-postgres)); utrata cache oznacza odbudowę z serwera.
2. Wszystko, co da się wyrazić w IMAP (foldery, flagi, słowa kluczowe, drafty, Sent), zapisujemy na serwerze. Tylko to, czego IMAP nie wyraża (wątki, snooze, harmonogramy, filtry, ustawienia, definicje etykiet), żyje wyłącznie w Postgresie i podlega backupowi.
3. Odczyty zawsze z lokalnego mirrora; zapisy optymistycznie lokalnie, a write-back do IMAP asynchronicznie (kolejka, [ADR 0003](0003-job-queue-in-postgres.md)). Silo nie „wie lepiej” niż serwer po wykonaniu własnej operacji.
4. **Silo nie jest serwerem pocztowym** ([plan 1.1](../../ARCHITECTURE_AND_PLAN.md#11-czego-silo-nie-robi)): nie przyjmuje poczty z internetu, nie dostarcza do odbiorców, nie robi DKIM/SPF/DMARC, nie filtruje spamu, nie wystawia IMAP/POP3, nie importuje `.mbox`. Wysyłka idzie przez SMTP submission zewnętrznego serwera.
5. Gdy Gmail-parity koliduje z tą zasadą, wygrywa IMAP, a UI uczciwie pokazuje ograniczenie.

## Konsekwencje

- Interoperacyjność z innymi klientami i brak vendor lock-in; Silo można usunąć bez utraty poczty.
- Wymagana kompatybilność z różnymi serwerami (macierz w `docs/compat-matrix.md`) oraz ścieżki fallback (brak CONDSTORE, MOVE, keywords).
- Część funkcji ma uczciwe ograniczenia (np. etykiety lokalne bez wsparcia keywords).
- Dostarczalność, DNS i antyspam to odpowiedzialność serwera, nie Silo.

## Alternatywy

- **Własny serwer pocztowy z modelem Gmaila:** pełna kontrola, ale wymaga MTA, antyspamu i dostarczalności; wykracza poza cel.
- **Postgres jako źródło prawdy (import i własny magazyn):** szybkie, lecz rozjeżdża się z innymi klientami i zamyka dane w Silo.
- **JMAP zamiast IMAP:** możliwe przyszłe źródło, decyzja odłożona; dziś brak powszechnego wsparcia.

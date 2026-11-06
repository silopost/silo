# 0008. Tokenizer wyszukiwania w aplikacji zamiast `to_tsvector(unaccent)`

- **Status:** Przyjęty
- **Data:** 2026-11-06
- **Dotyczy:** silo-server

## Kontekst

Wyszukiwarka Fazy 4 ([plan 3.12](../../ARCHITECTURE_AND_PLAN.md#312-wyszukiwanie)) ma dwa wykonawcze odbicia tego samego zapytania w składni Gmaila: SQL po `messages.search_tsv` (lista wyników, „Zastosuj do istniejących” filtra) i matcher w pamięci (`search.Matcher`, filtry przy ingest – [plan 3.11](../../ARCHITECTURE_AND_PLAN.md#311-filtry)). DoD wymaga, żeby oba dawały ten sam zbiór (property test). Plan zakładał `to_tsvector('simple', unaccent(...))` po stronie Postgresa i `to_tsquery('simple', unaccent($n) || ':*')` w zapytaniu. Wtedy podział na słowa i zwijanie diakrytyków robi Postgres, a matcher w Go musiałby to odtworzyć bit w bit (parser `simple` traktuje inaczej adresy e-mail, URL-e, liczby z kropką i łączniki). Rozbieżności wychodziłyby jako filtr, który „nie działa” na nowej wiadomości, a działa po „Zastosuj”. Do tego `unaccent` jest rozszerzeniem z własnym słownikiem, zależnym od wersji obrazu Postgresa.

## Decyzja

`search_tsv` i literały zapytań buduje **jeden tokenizer w Go** (`internal/search`), a Postgres dostaje gotowe leksemy.

- **Tokenizacja:** ciągi liter i cyfr (Unicode), małe litery, zwijanie diakrytyków w Go (`ą` → `a`, `ł` → `l`), bez stemmingu. Adresy e-mail i domeny dzielą się na słowa (`firma` trafia `jan@firma.pl`).
- **Indeks:** wiersz `messages.search_tsv` to literał `tsvector` z jawnymi pozycjami i wagami (temat A; nazwy i adresy from/to/cc oraz nazwy załączników B; `body_text` do 512 KB C), zapisywany przez aplikację (`mail.ReindexSearch`).
- **Zapytanie:** literał `::tsquery` – słowo = prefiks (`:*`), kilka tokenów jednego słowa lub fraza = `<->`, `subject:` = waga A po `search_tsv`. Bez `to_tsvector`/`unaccent` w SQL.
- **Wersja tokenizera:** `messages.search_ver` (migracja `000006_search_index`) i stała `mail.SearchVersion`; wiersze ze starszą wersją są przeindeksowywane w tle przy starcie (paczki po 500).

## Konsekwencje

- SQL i matcher dzielą tekst identycznie – property test (240 wiadomości, ~120 zapytań) porównuje oba zbiory.
- Zmiana tokenizera = podbicie `SearchVersion` i reindeks w tle po upgrade; do jego końca wyszukiwanie po starszych wiadomościach jest niepełne (odpowiedź niesie `indexing`). Opisane w `docs/admin`.
- Nie potrzebujemy rozszerzenia `unaccent` ani indeksów wyrażeniowych po `subject` (temat to waga A tego samego `tsvector`).
- Zwijanie diakrytyków i reguły podziału są nasze: każda poprawka (np. inne pismo, apostrofy) wymaga testu w `internal/search` i reindeksu.
- Stemming per język (decyzja odłożona nr 7) można dodać tylko w Go, z kolejną wersją tokenizera.

## Alternatywy

- **`to_tsvector('simple', unaccent(...))` w Postgresie (plan pierwotny):** jeden tokenizer w bazie, ale matcher filtrów musiałby go emulować albo każdą nową wiadomość sprawdzać zapytaniem SQL (koszt przy ingest, filtr przed zapisem wiadomości niemożliwy). Odrzucone z powodu rozbieżności SQL ↔ matcher.
- **Matcher filtrów przez SQL po zapisie wiadomości:** jedna implementacja, ale zapytanie na każdą nową wiadomość i każdy filtr oraz brak ewaluacji na samych nagłówkach przed pobraniem treści. Odrzucone.
- **Zewnętrzny silnik (Meilisearch, Tantivy):** nowa usługa w compose i synchronizacja indeksu – sprzeczne z zasadą „Postgres + jeden binarny serwer”. Odrzucone.

# 0008. Search tokenizer in the application instead of `to_tsvector(unaccent)`

- **Status:** Accepted
- **Date:** 2026-11-06
- **Applies to:** silo-server

## Context

The phase 4 search has two executable forms of the same query in Gmail syntax: SQL over `messages.search_tsv` (the result list, a filter's "Apply to existing") and an in-memory matcher (`search.Matcher`, filters at ingest). The definition of done requires both to produce the same set (property test). The design assumed `to_tsvector('simple', unaccent(...))` on the Postgres side and `to_tsquery('simple', unaccent($n) || ':*')` in the query. Then Postgres does word splitting and diacritic folding, and the Go matcher would have to reproduce it bit for bit (the `simple` parser treats email addresses, URLs, numbers with dots and hyphens differently). Discrepancies would show up as a filter that "does not work" on a new message but works after "Apply". On top of that, `unaccent` is an extension with its own dictionary, dependent on the version of the Postgres image.

## Decision

`search_tsv` and the query literals are built by **one tokenizer in Go** (`internal/search`), and Postgres receives ready-made lexemes.

- **Tokenization:** runs of letters and digits (Unicode), lowercase, diacritic folding in Go (`ą` → `a`, `ł` → `l`), no stemming. Email addresses and domains are split into words (`firma` matches `jan@firma.pl`).
- **Index:** the `messages.search_tsv` value is a `tsvector` literal with explicit positions and weights (subject A; names and addresses in from/to/cc and attachment names B; `body_text` up to 512 KB C), written by the application (`mail.ReindexSearch`).
- **Query:** a `::tsquery` literal – a word = a prefix (`:*`), several tokens of one word or a phrase = `<->`, `subject:` = weight A over `search_tsv`. No `to_tsvector`/`unaccent` in SQL.
- **Tokenizer version:** `messages.search_ver` (migration `000006_search_index`) and the constant `mail.SearchVersion`; rows with an older version are reindexed in the background at start-up (batches of 500).

## Consequences

- SQL and the matcher split text identically – a property test (240 messages, ~120 queries) compares both sets.
- Changing the tokenizer = bumping `SearchVersion` and a background reindex after upgrade; until it finishes, search over older messages is incomplete (the response carries `indexing`). Described in `docs/admin`.
- We need neither the `unaccent` extension nor expression indexes on `subject` (the subject is weight A of the same `tsvector`).
- Diacritic folding and splitting rules are ours: every fix (e.g. another script, apostrophes) requires a test in `internal/search` and a reindex.
- Per-language stemming (a postponed decision) can only be added in Go, with a new tokenizer version.

## Alternatives

- **`to_tsvector('simple', unaccent(...))` in Postgres (the original design):** one tokenizer in the database, but the filter matcher would have to emulate it, or check every new message with an SQL query (a cost at ingest, and filtering before the message is stored is impossible). Rejected because of the SQL ↔ matcher discrepancy.
- **Filter matching through SQL after the message is stored:** one implementation, but a query for every new message and every filter, and no evaluation on headers alone before the body is fetched. Rejected.
- **An external engine (Meilisearch, Tantivy):** a new service in compose and index synchronization – contrary to the "Postgres + a single server binary" principle. Rejected.

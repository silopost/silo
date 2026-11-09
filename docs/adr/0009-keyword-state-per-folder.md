# 0009. Per-folder label keyword state and a limit counted from `PERMANENTFLAGS`

- **Status:** Accepted
- **Date:** 2026-11-06
- **Applies to:** silo-server, silo-web

## Context

User labels are stored on the server as IMAP keywords, so that they are visible in Thunderbird and come back after a cache rebuild. The design assumed two states at the account level (`accounts.keywords_supported`) and that when the maildir limit is exceeded (26 keywords per folder – the letters `a`–`z` in file names) "the server rejects new ones". A test on Dovecot 2.4.5 (maildir, phase 4) showed that **the server does not reject the 27th keyword**: `STORE` ends with `OK`, the keyword only lands in Dovecot's index and is lost when the index is rebuilt. The label would look saved, and after an index failure or a `rebuild-cache` it would disappear from the message. The limit is per folder, so one label may be a keyword in INBOX and be unable to be one in Archive.

## Decision

Silo **counts the limit itself** and stores the **label's keyword state per folder**.

- **Limit:** before storing a new keyword, Silo counts the keywords in the folder's `PERMANENTFLAGS` (refreshed on every `SELECT`) and compares them with `SILO_SYNC_KEYWORD_FOLDER_LIMIT` (default 26; `0` = no limit, e.g. sdbox/mdbox). Beyond the limit the keyword is not stored. A `NO` to `STORE` in a folder that announces `\*` has the same effect.
- **State:** the table `label_folder_state(label_id, folder_id)` (migration `000009_label_folders_rebuild`) – the folders in which the label lives only in Silo. API: `GET /labels` → `keywordState` ∈ `mirrored | local_only | partial`, with `partial` also `localOnlyFolders: [f_…]`; adding a folder to the list → `label.changed`.
- **Account level unchanged:** no `\*` in INBOX's `PERMANENTFLAGS` → `local_only` for all labels and `account.error keywords_unsupported` (only in this global case).
- **Collisions:** a new keyword does not take a word that the server already knows from the folder's `PERMANENTFLAGS` (a tag of another client) – it gets `_2`, `_3`, and the mapping is explicit in `labels.imap_keyword`.
- **Cache rebuild:** label assignments in `localOnlyFolders` folders (and of `local_only` labels) are carried over by `account_rebuilds.restore` by `dedupe_key`, because they cannot be read from the server.

## Consequences

- A label never "pretends" to be saved on the server: what is a keyword survives a rebuild of Dovecot's index and `rebuild-cache`; the rest is explicitly marked in the UI (a warning on the label, `silo-web` shows the folders).
- Counting from `PERMANENTFLAGS` depends on the server announcing all keywords of the folder in it (Dovecot: yes). Dovecot does not remove a word from the list after its messages are gone, so a test folder with many e2e runs can reach the limit (advice in `docs/admin`).
- `partial` labels require a backup of Silo metadata, just like `local_only` ones, because they exist only in Silo's database.
- A new env variable `SILO_SYNC_KEYWORD_FOLDER_LIMIT` – an administrator of a server without the limit sets `0`.

## Alternatives

- **Relying on the server's refusal (the original design):** Dovecot 2.4 maildir does not refuse – silent label loss. Rejected.
- **State only at the account level (`keywords_supported=false` after the first overflow):** one full folder would disable keywords everywhere, including where they work. Rejected.
- **A prefix or encoding several labels in one keyword:** works around the limit, but tags stop being readable in Thunderbird (contrary to the goal of showing labels as tags). Rejected.

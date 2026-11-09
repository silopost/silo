# 0014. Metadata backup format `silo-metadata` v1

- **Status:** Accepted
- **Date:** 2026-11-06
- **Applies to:** silo-server, silo

## Context

Silo's Postgres holds a **cache** of mail, which sync rebuilds from the IMAP server ([ADR 0005](0005-imap-source-of-truth.md)), and **metadata** that exists only in Silo. A `pg_dump` of the whole database is large and ties the backup to a schema version and to row identifiers. Phase 5 definition of done: metadata backup → loss of Silo data → restore + sync → an identical Inbox list; labels, snoozes, filters and scheduled messages preserved.

## Decision

`silo-server export-metadata` writes a single JSON document `silo-metadata` in version 1; `import-metadata` loads it into a migrated database (`scripts/backup.sh metadata` / `scripts/restore.sh metadata`).

- **Sections** (a map name → array; unknown ones are skipped with a warning, missing ones = empty): `users` (password hash, settings, TOTP), `accounts` (server configuration and the encrypted secret, no sync state), `labels` (user labels: name, keyword, color, nesting), `labelAssignments`, `snoozes`, `drafts` with `local` blobs (base64 inline; `--no-local-blobs` keeps only the `sha256`), `outbound` (`queued`/`sending`), `filters` (action labels by **name**: `actions.addLabels`), `searchHistory`, `contacts` (manual).
- **Stable identities instead of IDs:** user = email, account = user + IMAP host + login, label = account + name, message = the `Message-ID` header (`message_id_hdr`). Secrets are re-encrypted with an AAD built from the stable keys – import requires the same `SILO_SECRET_KEY` (or it as `SILO_SECRET_KEY_PREVIOUS`).
- **Restoring the assignments** of labels and snoozes waits for sync: rows go to the staging table `metadata_restores`; the `metadata_restore` job applies them as ingest progresses (`mirrored` labels store the keyword through the operation queue), retries every minute for up to 24 h, then it is `dead` in the admin panel. Scheduled messages go back to the queue for their time.
- **Not in the backup:** sessions, events, jobs, write-back operations (`imap_op` – `backup.sh` waits for an empty queue), the cache (messages, threads, folders, mirror blobs), the `SILO_SECRET_KEY` key.
- Import into a database that has users refuses; `--merge` adds idempotently.

## Consequences

- The backup is small and independent of the schema and IDs; it can be restored on a new instance of the same or a newer version.
- Restoring the assignments takes as long as the initial sync (e2e: a few dozen seconds for a small mailbox; large mailboxes – hours).
- Messages without a `Message-ID` (or with a duplicated one) do not get their local labels back; a draft taken over from another client's copy (without `X-Silo-Draft-Id`) comes back as a duplicate.
- The format is extended additively; a breaking change = `v2` with an import of `v1`.

## Alternatives

- **Only `pg_dump`:** keeps everything, but only on the same schema version, with the cache (size) and without merging into another instance. It remains as mode `full`.
- **Exporting the metadata tables through `COPY` with IDs:** simpler, but cache IDs (messages, threads) differ after a rebuild – the assignments would be unrestorable. Rejected.
- **All metadata on the IMAP server** (keywords, folders): works for `mirrored` labels and snoozes, but not for filters, settings, local drafts and `local_only` labels. A complement, not a replacement.

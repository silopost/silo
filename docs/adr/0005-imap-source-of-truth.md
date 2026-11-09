# 0005. IMAP as the source of truth; Silo is a client, not a server

- **Status:** Accepted
- **Date:** 2026-11-05
- **Applies to:** silo, silo-server, silo-web

## Context

Silo is meant to provide Gmail features (threads, labels, snooze, undo send) on top of an existing mail server, while the user may use Thunderbird or a phone at the same time. Reads must be fast, so Silo keeps a local mirror in Postgres. We need to decide who is right when the two disagree, and what the product is responsible for.

## Decision

1. **The IMAP server is the source of truth for mail:** the existence of messages, their content, folder and standard flags. Postgres is a cache/mirror; losing the cache means rebuilding it from the server.
2. Everything that can be expressed in IMAP (folders, flags, keywords, drafts, Sent) is written to the server. Only what IMAP cannot express (threads, snooze, schedules, filters, settings, label definitions) lives solely in Postgres and is covered by backups.
3. Reads always come from the local mirror; writes are applied optimistically locally, and the write-back to IMAP is asynchronous (queue, [ADR 0003](0003-job-queue-in-postgres.md)). Silo does not "know better" than the server after performing its own operation.
4. **Silo is not a mail server:** it does not accept mail from the internet, does not deliver to recipients, does not do DKIM/SPF/DMARC, does not filter spam, does not expose IMAP/POP3 and does not import `.mbox`. Sending goes through the SMTP submission service of an external server.
5. When Gmail parity conflicts with this principle, IMAP wins and the UI honestly shows the limitation.

## Consequences

- Interoperability with other clients and no vendor lock-in; Silo can be removed without losing mail.
- Compatibility with various servers is required (the matrix in `docs/compat-matrix.md`), along with fallback paths (no CONDSTORE, MOVE, keywords).
- Some features have honest limitations (e.g. local-only labels without keyword support).
- Deliverability, DNS and anti-spam are the server's responsibility, not Silo's.

## Alternatives

- **Our own mail server with Gmail's model:** full control, but requires an MTA, anti-spam and deliverability; beyond the goal.
- **Postgres as the source of truth (import into our own store):** fast, but drifts apart from other clients and locks the data into Silo.
- **JMAP instead of IMAP:** a possible future source, decision postponed; today it lacks widespread support.

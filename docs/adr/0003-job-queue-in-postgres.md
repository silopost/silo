# 0003. Job queue in Postgres (SKIP LOCKED), no Redis

- **Status:** Accepted
- **Date:** 2026-11-05
- **Applies to:** silo-server

## Context

Silo needs a queue for IMAP write-back (`imap_op`), sending (`send`), snooze, GC, reindexing and more. One of the project principles is self-hosting with minimal dependencies: the MVP is Postgres, a single backend binary, a static frontend and Caddy. Operations on one IMAP account must be serialized. The volume ranges from a few to a few hundred operations per minute.

## Decision

The queue is the `jobs` table in Postgres:

- Jobs are claimed with `UPDATE ... WHERE id = (SELECT ... FOR UPDATE SKIP LOCKED LIMIT 1) RETURNING *`, with `locked_until` as a lease.
- A general pool (4 goroutines by default) handles jobs without an `account_id`; an `AccountWorker` claims the jobs of its account (`ORDER BY run_at, id`), which serializes operations per account.
- Success = `DELETE`; failure = `run_at = now() + backoff(attempts)`; after `max_attempts` the status is `dead` (visible in the admin panel).
- Wake-up through `LISTEN silo_jobs` + `pg_notify`, with polling every 5 s as a fallback.
- A job is created in **the same transaction** as the local change; undo is a `DELETE` in a transaction.
- Kinds include `imap_op`, `send`, `snooze_wake`, `orphan_gc`, `blob_gc`, `reindex`, `filter_apply`, `keyword_rename` and `events_prune`.

## Consequences

- No additional service; the Postgres backup covers the queue.
- Atomicity: there is no "archive visible, but nobody will send it" state.
- A custom queue implementation to maintain; once it grows beyond ~300 lines we will consider `riverqueue/river` (also Postgres) while keeping per-account serialization.
- Scaling is limited to a single Postgres instance, which fits the goal (up to ~50 users).

## Alternatives

- **Redis (asynq, BullMQ etc.):** an additional dependency, and no transactionality with the data in Postgres.
- **A broker (RabbitMQ, NATS):** excessive for self-hosted volumes.
- **An in-process queue:** loses operations on restart and does not allow undo through a transaction.
- **River from the start:** a reasonable candidate for later; at the start our own query is simpler and gives full control over per-account serialization.

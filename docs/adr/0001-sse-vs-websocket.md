# 0001. SSE instead of WebSocket for real time

- **Status:** Accepted
- **Date:** 2026-11-05
- **Applies to:** silo-server, silo-web

## Context

The browser must see new mail and state changes (from IMAP sync and from other tabs) in under 5 s, without a reload. Real-time communication is one-way: the server notifies the client. User actions go over REST with validation, idempotency and error codes. Everything has to work behind Caddy with a single backend binary.

## Decision

Real time is implemented with **Server-Sent Events**: `GET /api/v1/events` (`text/event-stream`).

- An in-memory hub per user, a channel per client with a buffer of 64; overflow closes the connection (reconnect + replay).
- Events are stored in the `events` table with `seq` as the SSE `id:` and a 24 h retention; a reconnect with `Last-Event-ID` replays events, and a `seq` that is too old yields `resync`.
- A `: ping` heartbeat every 25 s; Caddy with `flush_interval -1`.
- Fallback: after 3 failed `EventSource` connections the client switches to `GET /api/v1/events/poll?after=<seq>` every 15 s and periodically tries to return to SSE.
- Events from sync and from the API/ops are published through `tx.AfterCommit`, so the client does not distinguish the source of a change.

## Consequences

- Simple: plain HTTP/2, the session cookie works automatically, the browser provides reconnects and `Last-Event-ID`, and the implementation is on the order of 100 lines of Go.
- No client → server channel; none is needed, because actions are REST.
- Requires a correct proxy configuration (no buffering).
- We maintain the `events` table and the `events_prune` job.
- The polling fallback is additional code on both the client and the server.

## Alternatives

- **WebSocket:** bidirectional, but not needed; requires our own reconnect, replay and upgrade authentication, and we want actions in REST anyway.
- **Long polling:** works everywhere, but has more overhead and latency; kept only as the fallback.
- **Plain polling:** does not meet the < 5 s budget without excessive load.

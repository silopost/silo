# 0002. UNREAD as an `is_unread` flag, not a label

- **Status:** Accepted
- **Date:** 2026-11-05
- **Applies to:** silo-server, silo-web

## Context

Gmail treats `UNREAD` as a label, and its API lets clients add and remove it through `addLabelIds`/`removeLabelIds`. In IMAP the read state is the standard `\Seen` flag (no flag = unread), and it belongs to the server, which is the source of truth for mail ([ADR 0005](0005-imap-source-of-truth.md)). Silo must keep Gmail parity in the API and UI while not drifting apart from other clients (Thunderbird, phone). Counters and lists are a hot path (budget < 50 ms).

## Decision

`UNREAD` is a **derived flag**, not a row in `message_labels` (rows there are user labels; system states are derived from IMAP flags and folders):

- `messages.is_unread bool NOT NULL` with a partial index `WHERE is_unread`.
- Value = no `\Seen` on the server, with pending operations applied on top; computed by `mail.DeriveSystemLabels`.
- The API keeps the pseudo-label `UNREAD` in `labelIds` and in `addLabelIds`/`removeLabelIds`; `mail.ModifyLabels` translates `±UNREAD` into `UID STORE ∓FLAGS (\Seen)`.
- Search: `is:unread` is `m.is_unread`, `is:read` is `NOT m.is_unread`.
- Counters count threads with at least one unread message.

## Consequences

- One source of truth (the server flag); a change in another client immediately changes `is_unread`.
- Fast counters and filters without joins to the label table.
- API clients see `UNREAD` as in Gmail, so the UI needs no special cases.
- The pseudo-label requires translation in the API layer (an exception to the "label = row" rule).
- Opening a thread does not automatically mark it as read; the frontend sends `removeLabelIds: ["UNREAD"]` (controlled by a setting).

## Alternatives

- **`UNREAD` as a regular label in `message_labels`:** consistent with Gmail, but duplicates the `\Seen` state and risks drift; every flag change would have to update two places.
- **The IMAP keyword `$Unread`:** non-standard, the inverse of `\Seen` semantics, and not understood by other clients.

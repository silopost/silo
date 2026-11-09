# 0006. go-imap/v2 as the IMAP client: spike results and the scope of `imapx`

- **Status:** Accepted
- **Date:** 2026-11-05
- **Applies to:** silo-server

## Context

The sync engine relies on `QRESYNC`/`CONDSTORE`, `MOVE`/`COPYUID`, `IDLE`, `SPECIAL-USE` and keywords. The design assumed `github.com/emersion/go-imap/v2` (`imapclient`) with a thin `internal/imapx` layer, and required a spike **before** phase 2, because the library is in beta and the `QRESYNC` parameters of `SELECT` might not be exposed.

Spike: `silo-server/internal/imapx/spike_test.go`, run with `-v`, against a real Dovecot `dovecot/dovecot:2.4.5` in testcontainers (`internal/testutil/imaptest`, profiles `full`, `no-condstore`, `no-move`). The tests pin the findings with assertions, so a library update that changes something breaks a test and forces a revision of this ADR. Version: **`go-imap/v2 v2.0.0-beta.8`** (the newest on the day of the spike; dependencies `go-message v0.18.2`, `go-sasl`).

## Results

| Feature | Status | API / notes |
|---|---|---|
| Connection: implicit TLS, STARTTLS, no TLS | native | `imapclient.New`, `NewStartTLS`, `DialTLS`... Our own `Dial` in `imapx` adds `context`, timeouts (connection + handshake + greeting) and modes; the library itself has no command timeouts |
| LOGIN, wrong password | native + mapping | `Client.Login(u, p).Wait()` returns `*imap.Error{Type: NO, Code: ...}`; `imapx` maps it to `ErrAuthFailed` (NO) or `ErrUnavailable` (network, BYE, `[UNAVAILABLE]`, `[INUSE]`, `[LIMIT]`, `[OVERQUOTA]`) |
| CAPABILITY | native | `Client.Caps()` / `Capability().Wait()` -> `imap.CapSet`; `Has()` accounts for implications (QRESYNC => CONDSTORE, IMAP4rev2 => MOVE, UIDPLUS, IDLE). `imapx.Capabilities` is a type with methods `HasQRESYNC()`, `HasMove()` etc. |
| `ENABLE QRESYNC` / `ENABLE CONDSTORE` | **missing** | `Client.Enable` rejects everything except `IMAP4rev2`, `UTF8=ACCEPT`, `METADATA` (`cannot enable "QRESYNC": not supported`). CONDSTORE is enabled implicitly through `SELECT (CONDSTORE)` or `FETCH ... MODSEQ` |
| `SELECT` with `(QRESYNC (uidvalidity modseq [known-uids]))` | **missing** | `imap.SelectOptions` has only `ReadOnly` and `CondStore`; there is also no public way to send a raw command (`beginCommand` is private) |
| `VANISHED` / `VANISHED (EARLIER)` | **missing, kills the connection** | an unknown `*` response ends the read loop: `unsupported response type "VANISHED"`, `Client.Closed()` closed (`TestSpikeVanishedKillsClient`). On Dovecot this does not happen until we send `ENABLE QRESYNC`, but adding QRESYNC requires patching the library, not just `imapx` |
| SELECT parameters: `UIDVALIDITY`, `UIDNEXT`, `HIGHESTMODSEQ`, `PERMANENTFLAGS` | native | `imap.SelectData{UIDValidity, UIDNext, HighestModSeq, PermanentFlags, NumMessages}`; Dovecot returns `\*` in `PERMANENTFLAGS` (`imap.FlagWildcard`) |
| `UID FETCH ... (CHANGEDSINCE n)` + `MODSEQ` in the response | native | `imap.FetchOptions{UID, Flags, ModSeq: true, ChangedSince: n}`; `FetchMessageBuffer.ModSeq`. Returns only the changed UIDs with their new modseq |
| `UNCHANGEDSINCE` on `STORE` | native | `imap.StoreOptions{UnchangedSince}` (useful for write-back) |
| `UID SEARCH` / `ESEARCH` | native | `UIDSearch(criteria, &imap.SearchOptions{ReturnAll, ReturnCount, ReturnMin, ReturnMax})`; `SearchData.All` is an `imap.UIDSet` (ranges), `.Nums()` expands it. The `Since` criterion works |
| Detecting deletions without QRESYNC | native (CONDSTORE path) | `UID SEARCH ALL` + difference with the local set; verified with a scenario of 2 deleted, 1 flag change, 1 added; `CHANGEDSINCE` returns `[1 5]`, `SEARCH ALL` `[1 4 5]` |
| `EXPUNGE` from another client | native | `UnilateralDataHandler.Expunge(seqNum)` (sequence number, not UID) |
| `UID EXPUNGE` | native | `Client.UIDExpunge(imap.UIDSet)`, requires UIDPLUS; returns sequence numbers |
| `APPEND` with flags and `INTERNALDATE` | native | `Append(mailbox, size, &imap.AppendOptions{Flags, Time})`, `Write`, `Close`, `Wait()` -> `AppendData{UID, UIDValidity}` (APPENDUID). `INTERNALDATE` preserved to the second |
| `MOVE` with `COPYUID` | native | `Move(uidSet, dst).Wait()` -> `MoveData{UIDValidity, SourceUIDs, DestUIDs}`. `Copy()` -> `CopyData` with the same |
| Fallback without `MOVE` | **native, but dangerous** | `Client.Move` itself does `COPY` + `STORE +FLAGS.SILENT \Deleted` + `UID EXPUNGE`. **Without UIDPLUS** it uses a plain `EXPUNGE`, which also deletes unrelated messages flagged `\Deleted` in the folder (reproduced in `TestSpikeNoMoveProfile`). The sync design forbids this |
| `IDLE` | native, with caveats | `Idle()` blocks until acknowledged, `IdleCommand.Close()` + `Wait()` end it; the connection keeps working after IDLE. The library restarts IDLE every **28 min** on its own (a constant; the design assumed 25 min) |
| Unilateral data during IDLE | native | `Options.UnilateralDataHandler{Mailbox (NumMessages = EXISTS), Fetch, Expunge}`. EXISTS about 0.5 s after an APPEND from another connection, FETCH with a flag change after about 0.5 s. **Note:** the unilateral `FETCH` from Dovecot contains `FLAGS` and `MODSEQ`, but **no `UID`** (only the sequence number). The handler blocks the client's reader |
| `LIST` with `RETURN (SPECIAL-USE)` | native | `ListOptions{ReturnSpecialUse, ReturnChildren, SelectSpecialUse}`, roles in `ListData.Attrs` (`imap.MailboxAttrSent` etc.) |
| `CREATE ... USE (\Archive)` | supported by the library, **ignored by Dovecot** | `CreateOptions{SpecialUse}` sends a correct command and the server answers OK, but the role is not created (`LIST` without `\Archive`); Dovecot does not advertise `CREATE-SPECIAL-USE`. The role has to be assigned in the server configuration or stored in Silo |
| `STATUS (MESSAGES UIDNEXT UIDVALIDITY HIGHESTMODSEQ)` | native | `Status(mbox, &imap.StatusOptions{...}).Wait()` |
| `LIST-STATUS` (`RETURN (STATUS (...))`) | native | `ListOptions.ReturnStatus`; `ListData.Status` filled in for all folders with one command |
| Keywords | native | `Store(set, &imap.StoreFlags{Op: StoreFlagsAdd, Flags: {"$SiloSnoozed", "Praca"}})`; visible in `SelectedMailbox.Flags` after the store; `PERMANENTFLAGS \*` confirmed. The FETCH response also contains `\Recent` (IMAP4rev1), to be filtered out during ingest |
| `OBJECTID` (`EMAILID`) | missing on the server side | Dovecot 2.4.5 does not advertise OBJECTID in this configuration (it is treated as optional; the matcher falls back to `dedupe_key`). The library only knows the `CapObjectID` constant: `FetchOptions` has no `EMAILID`/`THREADID` (to be added when a server advertises them) |
| Profiles `no-condstore`, `no-move` | OK | `imap_capability` in Dovecot 2.4 **replaces** the whole list (it is not additive), so the profiles list it explicitly. It only changes the advertisement; `IMAP4rev2` has to be hidden in `no-move`, because it implies MOVE and UIDPLUS. Dovecot still returns APPENDUID/COPYUID even without advertising UIDPLUS |

Not checked: `NOTIFY` (RFC 5465; the library only has the `CapNotify` constant, no command), `COMPRESS=DEFLATE`, `BINARY`, XOAUTH2/SASL, STARTTLS and implicit TLS against a real server (the tests run without TLS; the TLS paths go through the standard library and are to be checked in phase 2 on docker-mailserver), behavior with large folders, and `known-uids` in QRESYNC.

## Decision

**We stay with `go-imap/v2 v2.0.0-beta.8` (pinned) with a thin `internal/imapx`.** Everything except QRESYNC works natively. In `imapx` we add only what is durable and small (done in phase 1): `Dial` with `context`, timeouts and TLS modes, `Login` with error mapping (`ErrAuthFailed` vs `ErrUnavailable`), `Capabilities` with typed methods, and `Await(ctx, ...)` for commands with a deadline (when exceeded it closes the connection, because the library has no cancellation).

**QRESYNC (plan B).** The library does not support it, and `imapx` cannot add it from the outside (no raw commands, the response parser is private). The missing pieces in the library are an estimated 50-80 lines: allowing `ENABLE QRESYNC`, `QResync` fields in `SelectOptions` with encoding, a parser for `VANISHED [(EARLIER)] uid-set` and its delivery (to `SelectData` and `UnilateralDataHandler`). Resolution:

1. **Phase 2 starts on the `CONDSTORE` path** (`SELECT (CONDSTORE)`, `FETCH CHANGEDSINCE`, deletions through `UID SEARCH ALL` in ESEARCH + set difference). It works natively, it is required for Gmail and other servers without QRESYNC, and the spike confirmed it on Dovecot. The path without CONDSTORE (STATUS + full comparison) is also native.
2. **QRESYNC is added as an optimization** through a fork of `emersion/go-imap` (`replace` in `go.mod`, a patch limited to `imapclient`, a PR upstream), after measuring the cost of `UID SEARCH ALL` on large folders (>50k) in phase 2. Until the patch exists, `imapx.Capabilities.HasQRESYNC()` is informational only, and the engine **does not send** `ENABLE QRESYNC`.
3. Rejected for now: our own IMAP parser in `imapx` (duplicating the library) and a raw socket for a single command (SELECT with QRESYNC changes the session state, so the whole session would have to understand `VANISHED` anyway).

**Workarounds that `imapx` must have in phase 2 (not implemented in this spike):**

- **Our own message move** instead of `Client.Move` when MOVE is missing: `UID COPY` + `UID STORE \Deleted` + `UID EXPUNGE`. Without UIDPLUS: **do not** call `EXPUNGE` outside `Trash`/`Drafts`; in other folders copy + `\Deleted`, and leave the physical removal to the server or the user (for Silo a message with `\Deleted` is already "deleted"). Moving on such servers is therefore best effort.
- **Unilateral FETCH without UID** (IDLE): do not trust UIDs from the handler; treat FETCH/EXISTS/EXPUNGE as an "INBOX changed" signal and run an incremental sync (`CHANGEDSINCE`).
- **IDLE timer**: the library restarts IDLE every 28 min, in line with RFC 2177 (< 29 min), which is acceptable; the design value of 25 min is to be corrected to "≤ 28 min", or we use our own `Close()`+`Idle()` loop.
- **Command timeouts**: all commands go through `Client.Await(ctx, ...)`.
- **Folder roles**: do not rely on `CREATE ... USE`; for a newly created Archive keep the role in Silo (mapping by name) or require an existing folder.
- **Unilateral handlers** must be fast (they block the reader): a buffered channel + a separate goroutine.

## Consequences

- Phase 2 is not blocked: the full CONDSTORE path and the fallbacks are verified against a real server, in CI (testcontainers, ~1 s per container after pulling the image in about 6 s).
- We keep a dependency on a beta version; the spike tests act as a characterization test on every update (`go get` the new beta, `go test ./internal/imapx`).
- QRESYNC is extra work (fork/patch) and a risk, but postponed until there is data on the cost. The design assumptions about the IMAP client, the IDLE interval (25 min) and the MOVE fallback without UIDPLUS need a small correction in line with this ADR.
- The Dovecot profiles are adequate for testing fallbacks, but only as CAPABILITY advertisements: the server still actually supports the hidden extensions (e.g. it returns COPYUID), so a test of a "real" lack of UIDPLUS (no APPENDUID/COPYUID) will require a fake server in phase 2.

## Alternatives

- **Our own IMAP client in `imapx`**: full control (QRESYNC, VANISHED, NOTIFY), but several thousand lines of parser and literal handling, with no benefit beyond QRESYNC. Rejected.
- **`github.com/emersion/go-imap` v1** (stable): no CONDSTORE/QRESYNC/MOVE in a convenient form and no further development. Rejected.
- **Other libraries**: no mature alternative with CONDSTORE and IDLE of go-imap/v2's quality (not prototyped). Rejected.
- **Fork right away**: maintenance cost before we have measured the need for QRESYNC. Postponed (point 2 of the decision).

# Compatibility matrix

A skeleton, filled in before every release. `silo` is the distribution (a set of pinned image tags); `silo-server`, `silo-web` and `silo-mobile` have independent SemVer, and the contract between them is the OpenAPI specification generated from the backend.

## 1. Versions of `silo-server` / `silo-web` / `silo-mobile`

Before 1.0, breaking changes to the API contract are recorded here. `silo-mobile` is not part of the `silo` distribution (a phone app, not an image) – the column says which app version is built on the contract of a given server release; compatibility with other server versions – [below](#silo-mobile).

| silo | silo-server | silo-web | silo-mobile | Notes |
|---|---|---|---|---|
| 0.5.0 | 0.5.0 | 0.4.0 | 0.1.0 (unchanged) | phase 5 API contract (additive relative to 0.4.0): `/settings` unchanged (`activeAccountId` selects the account); `PUT /drafts/{id}` with `accountId` moves a new message to another account as a new draft (new `id`/`messageId`/`threadId`, `draft.updated.previousDraftId`; reply/forward → `409 draft_account_locked`); mode `local`: `POST /session/password`, `/totp/setup`, `/totp/enable`, `DELETE /totp`, `/totp/backup-codes`, `totpCode` in `POST /session` (`401 totp_required`), `user.totpEnabled`; `/admin/users`, `/admin/accounts` (with `authType`), `/admin/jobs` (`403` for non-admins); `POST /accounts/discover`; OAuth2: `POST /oauth/{provider}/start`, `GET /oauth/{provider}/callback`, `meta.oauthProviders`, `Account.authType` (`password`/`xoauth2`); `DELETE /sessions?others=true`; SSE `session.expired` and `stream.limit` (max. 8 streams per user), `label.counts` after `account.status` `live`; `429 rate_limited` with `Retry-After`; `POST /accounts/{id}/resync {mode: rebuild}` unchanged; `minWebVersion` = `0.3.0`. Migrations `000050`–`000052` additive (upgrade 0.4.0 → 0.5.0 verified by the upgrade test). `silo-web` 0.3.0 works with `silo-server` 0.5.0; `silo-web` 0.4.0 requires `silo-server` ≥ 0.5.0 |
| 0.4.0 | 0.4.0 | 0.3.0 | 0.1.0 | phase 4 API contract (additive relative to 0.3.0): search with Gmail syntax (`GET /threads?q=` with `indexing`/`approximate`/`resultSizeEstimate`, `422 invalid_query`, `GET /search/suggest`, `DELETE /search/history`), snooze (`POST`/`DELETE /threads/{id}/snooze`, `GET /snooze/presets`, folder role `snoozed`), schedule send (`Thread.scheduledAt`/`outboundId`), filters (`/filters` CRUD, `POST /filters/{id}/apply`, `filter.applied`), `GET/PATCH /settings` (`desktopNotifications`, `updatedAt`, `settings.updated`; `SessionInfo.settings` gained these fields), `inline` uploads with `cid` and thumbnails (`GET /attachments/{id}/thumbnail`, `thumbnail`/`cid`/`inline` on attachments, `415 thumbnail_unsupported`), `Draft.warnings` (forward with the original's attachments), `Thread.snoozedUntil`, labels `keywordState` `mirrored`/`local_only`/`partial` with `localOnlyFolders`, `PATCH /labels/{id}` with `parentId` (`422 invalid_parent`), `POST /accounts/{id}/resync {mode: rebuild}` (`409 rebuild_blocked`). Migrations `000006`–`000009` additive; background search reindex after upgrade (`docs/admin`). `silo-web` 0.2.0 works with `silo-server` 0.4.0; `silo-web` 0.3.0 requires `silo-server` ≥ 0.4.0 |
| 0.3.0 | 0.3.0 | 0.2.0 | 0.1.0 (phase 3 scope) | phase 3 API contract (additive relative to 0.2.0, except for the schema fixes at the end of the row): bearer sign-in for native clients (`POST /session` with `client`, `Authorization: Bearer`, ADR 0007), `/operations/{id}/undo`, `/uploads`, drafts (`/drafts`, `PUT` with `version` and `syncNow`, a single copy in Drafts), sending (`/drafts/{id}/send`, `/outbound/{id}/cancel` – undo send, `SCHEDULED`/`SENT`, APPEND to Sent, `\Answered`), `/contacts/autocomplete`, `Account.position`, `Message.draftId`/`Thread.draftId`, `Draft.lastSend`, `meta.maxAttachmentBytes`, problem fields (`limit`/`size`, `currentVersion`/`current`, `address`/`field`), `operation.failed.kind`, `outbound.status` with `draftId`. Schema: `Draft.lastSend` and `Message.folder` may be `null`, `Message.replyTo` is omitted without a Reply-To header (previously wrongly required). `silo-web` 0.2.0 requires `silo-server` ≥ 0.3.0 |
| 0.2.0 | 0.2.0 | 0.1.0 | – | phase 2 API contract: session, accounts, labels, threads, messages, events; breaking changes allowed before 1.0 |
| edge | edge | edge | `main` | `:edge` images, no compatibility guarantee |

### `silo-mobile`

| silo-mobile | silo-server | Notes |
|---|---|---|
| 0.1.0 (unreleased) | 0.5.0 | expected scope as with 0.4.0 (the 0.5.0 contract is additive; not checked). 0.5.0 features not supported: sign-in with TOTP (`401 totp_required` – no code field), adding OAuth2 accounts (requires a variant for native clients, phase 6), the admin panel, changing "From" in a draft, `DELETE /sessions?others=true`; OAuth2 accounts added in `silo-web` sync normally |
| 0.1.0 (unreleased) | 0.4.0 | full scope: schema generated from the `v0.4.0` OpenAPI (`silo.serverRef`), mail parity with `silo-web` 0.3.0 (phases 3–4), [ADR 0010](adr/0010-react-native-for-silo-mobile.md). The 0.4.0 contract features (search with operators and suggestions, snooze, scheduled send, `/settings`, filters, label management, thumbnails, inline images) are gated on `Meta.serverVersion` (`src/lib/features.ts`), because `/meta` has no feature flags; an unparsable version (`dev`) = the newest. Verified by tests (405), the Android bundle and a read-only smoke test on the dev compose stack (14/14), not on a device |
| 0.1.0 (unreleased) | 0.3.0 | phase 3 scope: bearer sign-in, list, thread, actions and "Undo", compose and undo send, attachments, accounts, sessions, events; settings only on the device, text-only search; 0.4.0 features hidden |
| – | ≤ 0.2.0 | not supported (no bearer sign-in, ADR 0007) |

## 2. IMAP/SMTP mail servers

Initial expectations – **to be confirmed by testing**. Manual scenario: add an account, initial sync, archive, label, snooze, send, reply from another client.

| Server | IDLE | CONDSTORE/QRESYNC | MOVE/UIDPLUS | SPECIAL-USE | Keywords (`PERMANENTFLAGS \*`) | Notes | Status |
|---|---|---|---|---|---|---|---|
| Dovecot 2.3/2.4 (docker-mailserver) | yes | yes (CONDSTORE used; QRESYNC unused – missing in go-imap/v2 beta.8, ADR 0006) | yes | yes | yes (maildir: max 26 keywords per folder; 2.4 does not reject the 27th – Silo counts the limit itself, ADR 0009) | reference server; `CREATE-SPECIAL-USE` is ignored by Dovecot (the folder role comes from the server configuration) | confirmed (phase 2; sending/Drafts/Sent: phase 3; snooze/keywords/rebuild: phase 4) |
| Dovecot 2.4 with `passdb oauth2` (XOAUTH2) | yes | yes | yes | yes | yes | `AUTHENTICATE XOAUTH2` (IMAP) and `AUTH XOAUTH2` (SMTP), token checked through RFC 7662 introspection at a fake provider | confirmed with testcontainers (phase 5: profile `oauth2`, `TestOAuthAccount`) |
| Gmail IMAP | yes | CONDSTORE yes, QRESYNC no | yes | yes (`\All`) | no (labels = folders) | **generic mode with OAuth2** (or an app password): `\All` with deduplication, archive = removing the copy from INBOX, `sentAppend` disabled (Gmail stores Sent itself); Gmail labels invisible, Silo's JWZ threads – mode `provider=gmail` (X-GM) postponed to 1.1 ([ADR 0013](adr/0013-oauth2-xoauth2.md)) | generic mode with OAuth2: confirmed by tests (profile `gmail-like`, Dovecot `oauth2`); live to be confirmed manually ([steps](#oauth2-and-xoauth2-phase-5)) |
| Office 365 / Outlook.com | yes | no | yes | yes | no / uncertain | OAuth2 only (basic auth disabled): `outlook.office365.com:993`, `smtp.office365.com:587` STARTTLS (SMTP AUTH must be enabled for the mailbox), `sentAppend` disabled; Outlook.com experimental | OAuth2/XOAUTH2 confirmed by tests (fake provider, Dovecot `oauth2`, `scope` on refresh); live to be confirmed manually ([steps](#oauth2-and-xoauth2-phase-5)) |
| Courier IMAP | yes (depending on configuration) | no | depending on version | partially | yes with `IMAP_KEYWORDS=1` | popular on shared hosting | to be confirmed |

### Dovecot confirmation (phase 2)

Verified by `silo-server` integration tests on `dovecot/dovecot:2.4.5` (testcontainers) and e2e on docker-mailserver 16 (`scripts/e2e-smoke.sh`): `IDLE` (`message.new` over SSE about 0.5 s after delivery), `CONDSTORE` (incremental sync by `HIGHESTMODSEQ`/`CHANGEDSINCE`), `MOVE`/`UIDPLUS` (`COPYUID`), `SPECIAL-USE`, keywords (`PERMANENTFLAGS \*`, user labels). `QRESYNC` is advertised, but unused until `imapx` is patched or forked.

Test profiles, verified as fallbacks (the same set of sync tests passes):

| Profile | Advertises | Path |
|---|---|---|
| `full` | Dovecot defaults (`CONDSTORE QRESYNC MOVE UIDPLUS IDLE SPECIAL-USE ...`) | main |
| `no-condstore` | without `CONDSTORE QRESYNC` | full comparison of UIDs + flags |
| `no-move` | without `MOVE UIDPLUS` | copy + `\Deleted` (no `EXPUNGE` outside Trash/Drafts) |

### Dovecot and Postfix confirmation: sending, Drafts, Sent (phase 3)

Verified by `silo-web` Playwright tests (`npm run e2e`) on docker-mailserver 16 (Dovecot 2.4, Postfix submission on 587 without TLS in dev), with the server state read by a second IMAP client (`imapflow`), 2026-11-05:

- **Sending (SMTP submission, AUTH PLAIN):** a reply from Silo reaches `dev2@` with `In-Reply-To` = the original's `Message-ID` and `References` containing it; undo send within the window – nothing arrives (checked after 12 s); without undo, delivery about 0.6 s after the end of the window.
- **Sent:** exactly one copy (APPEND with `\Seen`, the same `Message-ID`), no duplicate in Silo (the Matcher attaches the copy to the local message); the original gets `\Answered`.
- **Drafts:** the draft is in the Drafts folder about 32 s after the last change (30 s delay); after each edit there is still one message (APPEND of the new version, deletion of the old one); `syncNow` when the window closes – the new version in < 1 s.
- **Archive and undo:** `MOVE` to Archive after 10.3–10.4 s (10 s window); "Undo" within the window – the message stays in INBOX with the same UID (no `MOVE`; the dev server does not log IMAP commands, the UID is the evidence), Archive empty.
- **Mail server unavailable:** `docker compose stop mailserver` → the account is in `backoff`, operations wait (`pendingSync`); after `start` they are executed without a UI refresh after about 17 s (backoff 5 s / 15 s).

### Dovecot confirmation: snooze, per-folder keywords, cache rebuild (phase 4)

Verified by `silo-server` integration tests on `dovecot/dovecot:2.4.5` (testcontainers, profiles `full` and `no-move`) and `silo-web` Playwright tests on docker-mailserver 16 (Dovecot 2.4), with the server state read by a second IMAP client, 2026-11-06:

- **Snooze:** the thread's messages are in the `Snoozed` folder (created by Silo, with the `$SiloSnoozed` keyword) and not in INBOX; after the time they return to INBOX without `Seen` on the newest message; moving from `Snoozed` to INBOX with a second client cancels the snooze; the snooze survives a `DELETE` + `CREATE` of the `Snoozed` folder with the same messages (a new `UIDVALIDITY`). On the `no-move` profile – copy + `Deleted`, without losing the snooze.
- **Keywords:** a Silo label as a keyword on the server; a keyword set by a second client (`UID STORE +FLAGS`, like a Thunderbird tag) as a label in Silo – INBOX through IDLE in about 0.6 s (server tests) and about 1 s on the list row in the UI (e2e); other folders within the polling interval.
- **Limit of 26 (maildir):** Dovecot 2.4.5 **does not reject** the 27th keyword (`STORE` → `OK`, the word only in the index, lost when it is rebuilt). Silo counts the words from the folder's `PERMANENTFLAGS` (`SILO_SYNC_KEYWORD_FOLDER_LIMIT`, default 26) and beyond the limit marks the label as `partial` for the folder (ADR 0009); the "server answers `NO`" path checked with an injected response. Words do not disappear from the folder's list after messages are deleted – see `docs/admin`.
- **Cache rebuild** (`resync rebuild` / `rebuild-cache`): user labels restored from keywords (comparison of the `(Message-ID, label)` sets before and after, also without `labels` rows), the same thread split, snoozes and local labels carried over; 33 messages in about 2 s.
- **Schedule send:** a scheduled message does not exist on the server (no sender folder, no recipient INBOX) before its time; delivery after the send time (server tests: about 0.1 s after `sendAt`).
- **Filters:** a new message matching `from:x` → `MOVE` to Archive + the label's keyword; "Apply" moves older ones.

### OAuth2 and XOAUTH2 (phase 5)

Verified by `silo-server` tests (testcontainers, 2026-11-06): XOAUTH2 for IMAP and SMTP on Dovecot 2.4.5 with `passdb oauth2` (profile `oauth2`; token verified through RFC 7662 introspection at the fake provider `testutil/oauthtest`) and `smtptest` with `AUTH XOAUTH2`; the full flow `start` → callback → IMAP/SMTP test → account → initial sync (`TestOAuthAccount`); token refresh (Microsoft with `scope`), `invalid_grant` → `auth_failed` and re-authorization. Gmail generic mode on the `gmail-like` profile (`[Gmail]/All Mail` = `\All`): one message for the copies in INBOX and All Mail, archiving removes only the INBOX copy, no Archive folder (`TestGmailGenericMode`).

**Not tested live** (no Google or Microsoft 365 test accounts). Manual test before marking "confirmed" (configuration: [docs/admin/oauth.md](admin/oauth.md)):

1. "Sign in with Google" (or Microsoft) adds the account and returns to `silo-web` with `oauth=ok`.
2. The initial sync ends in the `live` state; INBOX matches the webmail.
3. Archiving a thread: it disappears from the Inbox in the webmail and stays in All Mail (Gmail) / in Archive (Microsoft); no duplicate in Silo.
4. A Silo user label is stored on the server (a keyword; Gmail does not show keywords as labels).
5. Sending: the message is delivered, exactly one copy in Sent.
6. A reply from another client joins the thread in Silo.
7. Revoking the app's access at the provider: the account goes to `auth_failed` on the next connection; "Sign in again" restores synchronization.

For Microsoft 365 the mailbox must have IMAP and Authenticated SMTP enabled.

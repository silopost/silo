# Architecture decision records (ADRs)

Format: [0000-template.md](0000-template.md). Rules for adding ADRs: [CONTRIBUTING.md](../../CONTRIBUTING.md#adr).

| No. | Title | Status |
|---|---|---|
| [0001](0001-sse-vs-websocket.md) | SSE instead of WebSocket for real time | Accepted |
| [0002](0002-unread-as-flag.md) | UNREAD as an `is_unread` flag, not a label | Accepted |
| [0003](0003-job-queue-in-postgres.md) | Job queue in Postgres (SKIP LOCKED), no Redis | Accepted |
| [0004](0004-huma-openapi-contract.md) | huma + chi and OpenAPI generated from code | Accepted |
| [0005](0005-imap-source-of-truth.md) | IMAP as the source of truth; Silo is a client, not a server | Accepted |
| [0006](0006-go-imap-v2-spike.md) | go-imap/v2 as the IMAP client: spike results and the scope of `imapx` | Accepted |
| [0007](0007-bearer-tokens-for-native-clients.md) | Opaque bearer tokens for native clients | Accepted |
| [0008](0008-search-tokenizer-in-app.md) | Search tokenizer in the application instead of `to_tsvector(unaccent)` | Accepted |
| [0009](0009-keyword-state-per-folder.md) | Per-folder label keyword state and a limit counted from `PERMANENTFLAGS` | Accepted |
| [0010](0010-react-native-for-silo-mobile.md) | React Native (Expo) for `silo-mobile` | Accepted |
| [0011](0011-local-auth-mode-and-totp.md) | Mode `local` with a Silo password and built-in TOTP | Accepted |
| [0012](0012-s3-blobstore.md) | `S3Store` on minio-go | Accepted |
| [0013](0013-oauth2-xoauth2.md) | OAuth2 (authorization code + PKCE) and XOAUTH2 for Gmail and Microsoft 365 | Accepted |
| [0014](0014-metadata-backup-format.md) | Metadata backup format `silo-metadata` v1 | Accepted |
| [0015](0015-i18n-typed-dictionaries.md) | Multilingual UI: English as the source language, typed dictionaries, `settings.language` | Accepted |

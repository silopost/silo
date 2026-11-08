# Rekordy decyzji architektonicznych (ADR)

Format: [0000-template.md](0000-template.md). Zasady dodawania ADR: [CONTRIBUTING.md](../../CONTRIBUTING.md#adr). Kontekst: [ARCHITECTURE_AND_PLAN.md](../../ARCHITECTURE_AND_PLAN.md).

| Nr | Tytuł | Status |
|---|---|---|
| [0001](0001-sse-vs-websocket.md) | SSE zamiast WebSocket dla real-time | Przyjęty |
| [0002](0002-unread-as-flag.md) | UNREAD jako flaga `is_unread`, nie etykieta | Przyjęty |
| [0003](0003-job-queue-in-postgres.md) | Kolejka zadań w Postgresie (SKIP LOCKED), bez Redis | Przyjęty |
| [0004](0004-huma-openapi-contract.md) | huma + chi i OpenAPI generowany z kodu | Przyjęty |
| [0005](0005-imap-source-of-truth.md) | IMAP jako źródło prawdy; Silo jest klientem, nie serwerem | Przyjęty |
| [0006](0006-go-imap-v2-spike.md) | go-imap/v2 jako klient IMAP: wyniki spike'a i zakres `imapx` | Przyjęty |
| [0007](0007-bearer-tokens-for-native-clients.md) | Opaque bearer tokens dla klientów natywnych | Przyjęty |
| [0008](0008-search-tokenizer-in-app.md) | Tokenizer wyszukiwania w aplikacji zamiast `to_tsvector(unaccent)` | Przyjęty |
| [0009](0009-keyword-state-per-folder.md) | Stan keywordu etykiety per folder i limit liczony z `PERMANENTFLAGS` | Przyjęty |
| [0010](0010-react-native-for-silo-mobile.md) | React Native (Expo) dla `silo-mobile` | Przyjęty |
| [0011](0011-local-auth-mode-and-totp.md) | Tryb `local` z hasłem Silo i własnym TOTP | Przyjęty |
| [0012](0012-s3-blobstore.md) | `S3Store` na minio-go | Przyjęty |
| [0013](0013-oauth2-xoauth2.md) | OAuth2 (authorization code + PKCE) i XOAUTH2 dla Gmaila i Microsoft 365 | Przyjęty |
| [0014](0014-metadata-backup-format.md) | Format backupu metadanych `silo-metadata` v1 | Przyjęty |
| [0015](0015-i18n-typed-dictionaries.md) | Wielojęzyczny UI: angielski źródłowy, typowane słowniki, `settings.language` | Przyjęty |

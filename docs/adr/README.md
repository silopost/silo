# Rekordy decyzji architektonicznych (ADR)

Format: [0000-template.md](0000-template.md). Zasady dodawania ADR: [CONTRIBUTING.md](../../CONTRIBUTING.md#adr). Kontekst: [ARCHITECTURE_AND_PLAN.md](../../ARCHITECTURE_AND_PLAN.md).

| Nr | Tytuł | Status |
|---|---|---|
| [0001](0001-sse-vs-websocket.md) | SSE zamiast WebSocket dla real-time | Przyjęty |
| [0002](0002-unread-as-flag.md) | UNREAD jako flaga `is_unread`, nie etykieta | Przyjęty |
| [0003](0003-job-queue-in-postgres.md) | Kolejka zadań w Postgresie (SKIP LOCKED), bez Redis | Przyjęty |
| [0004](0004-huma-openapi-contract.md) | huma + chi i OpenAPI generowany z kodu | Przyjęty |
| [0005](0005-imap-source-of-truth.md) | IMAP jako źródło prawdy; Silo jest klientem, nie serwerem | Przyjęty |

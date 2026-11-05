# 0003. Kolejka zadań w Postgresie (SKIP LOCKED), bez Redis

- **Status:** Przyjęty
- **Data:** 2026-11-05
- **Dotyczy:** silo-server

## Kontekst

Silo potrzebuje kolejki dla write-back do IMAP (`imap_op`), wysyłki (`send`), snooze, GC, reindeksacji i innych ([plan 3.13](../../ARCHITECTURE_AND_PLAN.md#313-kolejka-i-workery-bez-redis)). Zasada 5: self-hosted, minimum zależności – MVP to Postgres, jeden binarny backend, statyczny frontend i Caddy. Operacje na jednym koncie IMAP muszą być serializowane. Wolumen to jednostki–setki operacji na minutę.

## Decyzja

Kolejka to tabela `jobs` w Postgresie:

- Pobieranie przez `UPDATE ... WHERE id = (SELECT ... FOR UPDATE SKIP LOCKED LIMIT 1) RETURNING *` z `locked_until` jako dzierżawą.
- Pula ogólna (domyślnie 4 gorutyny) obsługuje joby bez `account_id`; `AccountWorker` pobiera joby swojego konta (`ORDER BY run_at, id`), co serializuje operacje per konto.
- Sukces = `DELETE`; błąd = `run_at = now() + backoff(attempts)`; po `max_attempts` status `dead` (widoczny w panelu).
- Budzenie przez `LISTEN silo_jobs` + `pg_notify`, polling co 5 s jako fallback.
- Job powstaje w **tej samej transakcji** co lokalna zmiana; undo to `DELETE` w transakcji.
- Rodzaje m.in.: `imap_op`, `send`, `snooze_wake`, `orphan_gc`, `blob_gc`, `reindex`, `filter_apply`, `keyword_rename`, `events_prune`.

## Konsekwencje

- Brak dodatkowej usługi, backup Postgresa obejmuje kolejkę.
- Atomowość: nie ma stanu „archiwizacja widoczna, ale nikt jej nie wyśle”.
- Własna implementacja kolejki do utrzymania; gdy urośnie ponad ~300 linii, rozważamy `riverqueue/river` (też Postgres) z zachowaniem serializacji per konto.
- Skalowanie ograniczone do jednej instancji Postgresa, co mieści się w celu (do ~50 użytkowników).

## Alternatywy

- **Redis (asynq, BullMQ itp.):** dodatkowa zależność i brak transakcyjności z danymi w Postgresie.
- **Broker (RabbitMQ, NATS):** nadmiarowe dla wolumenu self-hosted.
- **Kolejka w pamięci procesu:** gubi operacje przy restarcie, nie pozwala na undo przez transakcję.
- **River od początku:** rozsądny kandydat na później; na starcie własne zapytanie jest prostsze i daje pełną kontrolę nad serializacją per konto.

# 0001. SSE zamiast WebSocket dla real-time

- **Status:** Przyjęty
- **Data:** 2026-11-05
- **Dotyczy:** silo-server, silo-web

## Kontekst

Przeglądarka musi widzieć nową pocztę i zmiany stanu (z sync IMAP oraz z innych kart) w mniej niż 5 s, bez odświeżania ([plan 1, zasada 3](../../ARCHITECTURE_AND_PLAN.md#1-cel-i-zasady)). Komunikacja real-time jest jednokierunkowa: serwer powiadamia klienta. Akcje użytkownika idą REST-em z walidacją, idempotencją i kodami błędów. Całość ma działać za Caddy w pojedynczym binarnym backendzie.

## Decyzja

Real-time realizujemy przez **Server-Sent Events**: `GET /api/v1/events` (`text/event-stream`), opisane w [planie 3.14](../../ARCHITECTURE_AND_PLAN.md#314-real-time-sse).

- Hub w pamięci per użytkownik, kanał per klient z buforem 64; przepełnienie zamyka połączenie (reconnect + replay).
- Zdarzenia w tabeli `events` z `seq` jako `id:` SSE i retencją 24 h; reconnect z `Last-Event-ID` odtwarza zdarzenia, zbyt stary `seq` daje `resync`.
- Heartbeat `: ping` co 25 s; Caddy z `flush_interval -1`.
- Fallback: po 3 nieudanych połączeniach `EventSource` klient przechodzi na `GET /api/v1/events/poll?after=<seq>` co 15 s i okresowo próbuje wrócić do SSE.
- Zdarzenia z sync i z API/ops publikowane przez `tx.AfterCommit`, więc klient nie rozróżnia źródła zmiany.

## Konsekwencje

- Proste: zwykłe HTTP/2, cookie sesyjne działa automatycznie, reconnect i `Last-Event-ID` zapewnia przeglądarka, implementacja to rzędu 100 linii Go.
- Brak kanału klient → serwer; nie jest potrzebny, bo akcje to REST.
- Wymaga poprawnej konfiguracji proxy (brak buforowania).
- Utrzymujemy tabelę `events` i job `events_prune`.
- Pollingowy fallback to dodatkowy kod po stronie klienta i serwera.

## Alternatywy

- **WebSocket:** dwukierunkowy, ale niepotrzebny; wymaga własnego reconnectu, replay i uwierzytelniania upgrade'u, a akcje i tak chcemy mieć w REST.
- **Long polling:** działa wszędzie, lecz większy narzut i opóźnienia; zostaje tylko jako fallback.
- **Sam polling:** nie spełnia budżetu < 5 s bez nadmiernego obciążenia.

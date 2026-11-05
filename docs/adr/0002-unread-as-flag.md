# 0002. UNREAD jako flaga `is_unread`, nie etykieta

- **Status:** Przyjęty
- **Data:** 2026-11-05
- **Dotyczy:** silo-server, silo-web

## Kontekst

Gmail traktuje `UNREAD` jako etykietę, a jego API pozwala dodawać i zdejmować ją przez `addLabelIds`/`removeLabelIds`. W IMAP stan przeczytania to standardowa flaga `\Seen` (brak flagi = nieprzeczytana), należąca do serwera ([plan 3.3](../../ARCHITECTURE_AND_PLAN.md#33-źródło-prawdy-serwer-imap-vs-postgres)). Silo ma zachować Gmail-parity w API i UI, a jednocześnie nie rozjechać się z innymi klientami (Thunderbird, telefon). Liczniki i listy są gorącą ścieżką (budżet < 50 ms).

## Decyzja

`UNREAD` jest **flagą pochodną**, nie wierszem w `message_labels` ([plan 4.4](../../ARCHITECTURE_AND_PLAN.md#44-etykiety-na-dwóch-poziomach)):

- `messages.is_unread bool NOT NULL` z indeksem częściowym `WHERE is_unread`.
- Wartość = brak `\Seen` na serwerze, z nałożonymi oczekującymi operacjami; wylicza `mail.DeriveSystemLabels`.
- W API zachowujemy pseudo-etykietę `UNREAD` w `labelIds` oraz w `addLabelIds`/`removeLabelIds`; `mail.ModifyLabels` tłumaczy `±UNREAD` na `UID STORE ∓FLAGS (\Seen)`.
- Wyszukiwanie: `is:unread` to `m.is_unread`, `is:read` to `NOT m.is_unread`.
- Liczniki zliczają wątki z co najmniej jedną nieprzeczytaną wiadomością.

## Konsekwencje

- Jedno źródło prawdy (flaga serwera); zmiana w innym kliencie natychmiast zmienia `is_unread`.
- Szybkie liczniki i filtry bez joinów do tabeli etykiet.
- Klient API widzi `UNREAD` jak w Gmailu, więc UI nie wymaga specjalnych przypadków.
- Pseudo-etykieta wymaga tłumaczenia w warstwie API (wyjątek od zasady „etykieta = wiersz”).
- Otwarcie wątku nie oznacza go automatycznie jako przeczytanego; frontend wysyła `removeLabelIds: ["UNREAD"]` (sterowalne ustawieniem).

## Alternatywy

- **`UNREAD` jako zwykła etykieta w `message_labels`:** spójne z Gmailem, ale duplikuje stan `\Seen` i grozi rozjazdem; każda zmiana flagi musiałaby aktualizować dwa miejsca.
- **Keyword IMAP `$Unread`:** niestandardowe, odwrotne do semantyki `\Seen`, niezrozumiałe dla innych klientów.

# 0006. go-imap/v2 jako klient IMAP: wyniki spike'a i zakres `imapx`

- **Status:** Przyjęty
- **Data:** 2026-11-05
- **Dotyczy:** silo-server

## Kontekst

Silnik synchronizacji ([3.5](../../ARCHITECTURE_AND_PLAN.md)) opiera się na `QRESYNC`/`CONDSTORE`, `MOVE`/`COPYUID`, `IDLE`, `SPECIAL-USE` i keywords. Plan (3.1, Faza 1) zakłada `github.com/emersion/go-imap/v2` (`imapclient`) z cienką warstwą `internal/imapx` i wymaga spike'a **przed** Fazą 2, bo biblioteka jest w wersji beta, a parametry `QRESYNC` w `SELECT` mogły nie być wystawione.

Spike: `silo-server/internal/imapx/spike_test.go`, uruchamiany z `-v`, na prawdziwym Dovecocie `dovecot/dovecot:2.4.5` w testcontainers (`internal/testutil/imaptest`, profile `full`, `no-condstore`, `no-move`). Testy przypinają ustalenia asercjami, więc aktualizacja biblioteki, która coś zmieni, wywali test i zmusi do rewizji tego ADR. Wersja: **`go-imap/v2 v2.0.0-beta.8`** (najnowsza w dniu spike'a; zależności `go-message v0.18.2`, `go-sasl`).

## Wyniki

| Funkcja | Status | API / uwagi |
|---|---|---|
| Połączenie: implicit TLS, STARTTLS, bez TLS | natywnie | `imapclient.New`, `NewStartTLS`, `DialTLS`... Własny `Dial` w `imapx` dodaje `context`, timeouty (połączenie + handshake + greeting) i tryby; sama biblioteka nie ma timeoutów komend |
| LOGIN, błąd hasła | natywnie + mapowanie | `Client.Login(u, p).Wait()` zwraca `*imap.Error{Type: NO, Code: ...}`; `imapx` mapuje na `ErrAuthFailed` (NO) lub `ErrUnavailable` (sieć, BYE, `[UNAVAILABLE]`, `[INUSE]`, `[LIMIT]`, `[OVERQUOTA]`) |
| CAPABILITY | natywnie | `Client.Caps()` / `Capability().Wait()` -> `imap.CapSet`, `Has()` uwzględnia implikacje (QRESYNC => CONDSTORE, IMAP4rev2 => MOVE, UIDPLUS, IDLE). `imapx.Capabilities` to typ z metodami `HasQRESYNC()`, `HasMove()` itd. |
| `ENABLE QRESYNC` / `ENABLE CONDSTORE` | **brak** | `Client.Enable` odrzuca wszystko poza `IMAP4rev2`, `UTF8=ACCEPT`, `METADATA` (`cannot enable "QRESYNC": not supported`). CONDSTORE włącza się niejawnie przez `SELECT (CONDSTORE)` lub `FETCH ... MODSEQ` |
| `SELECT` z `(QRESYNC (uidvalidity modseq [known-uids]))` | **brak** | `imap.SelectOptions` ma tylko `ReadOnly` i `CondStore`; polecenie nie ma też publicznego sposobu na wysłanie surowej komendy (`beginCommand` jest prywatne) |
| `VANISHED` / `VANISHED (EARLIER)` | **brak, ubija połączenie** | nieznana odpowiedź `*` kończy pętlę czytającą: `unsupported response type "VANISHED"`, `Client.Closed()` zamknięte (`TestSpikeVanishedKillsClient`). Na Dovecocie nie zdarzy się to, dopóki nie wyślemy `ENABLE QRESYNC`, ale dopisanie QRESYNC wymaga łatki biblioteki, nie samego `imapx` |
| Parametry SELECT: `UIDVALIDITY`, `UIDNEXT`, `HIGHESTMODSEQ`, `PERMANENTFLAGS` | natywnie | `imap.SelectData{UIDValidity, UIDNext, HighestModSeq, PermanentFlags, NumMessages}`; Dovecot zwraca `\*` w `PERMANENTFLAGS` (`imap.FlagWildcard`) |
| `UID FETCH ... (CHANGEDSINCE n)` + `MODSEQ` w odpowiedzi | natywnie | `imap.FetchOptions{UID, Flags, ModSeq: true, ChangedSince: n}`; `FetchMessageBuffer.ModSeq`. Zwraca tylko zmienione UID z nowym modseq |
| `UNCHANGEDSINCE` przy `STORE` | natywnie | `imap.StoreOptions{UnchangedSince}` (przydatne w write-back) |
| `UID SEARCH` / `ESEARCH` | natywnie | `UIDSearch(criteria, &imap.SearchOptions{ReturnAll, ReturnCount, ReturnMin, ReturnMax})`; `SearchData.All` to `imap.UIDSet` (zakresy), `.Nums()` rozwija. Kryterium `Since` działa |
| Wykrywanie usunięć bez QRESYNC | natywnie (ścieżka CONDSTORE) | `UID SEARCH ALL` + różnica ze zbiorem lokalnym; zweryfikowane scenariuszem: 2 usunięte, 1 zmiana flagi, 1 dodana; `CHANGEDSINCE` zwraca `[1 5]`, `SEARCH ALL` `[1 4 5]` |
| `EXPUNGE` od innego klienta | natywnie | `UnilateralDataHandler.Expunge(seqNum)` (numer sekwencyjny, nie UID) |
| `UID EXPUNGE` | natywnie | `Client.UIDExpunge(imap.UIDSet)`, wymaga UIDPLUS; zwraca numery sekwencyjne |
| `APPEND` z flagami i `INTERNALDATE` | natywnie | `Append(mailbox, size, &imap.AppendOptions{Flags, Time})`, `Write`, `Close`, `Wait()` -> `AppendData{UID, UIDValidity}` (APPENDUID). `INTERNALDATE` zachowane co do sekundy |
| `MOVE` z `COPYUID` | natywnie | `Move(uidSet, dst).Wait()` -> `MoveData{UIDValidity, SourceUIDs, DestUIDs}`. `Copy()` -> `CopyData` z tym samym |
| Fallback bez `MOVE` | **natywny, ale niebezpieczny** | `Client.Move` sam robi `COPY` + `STORE +FLAGS.SILENT \Deleted` + `UID EXPUNGE`. **Bez UIDPLUS** użyje zwykłego `EXPUNGE`, który kasuje też niezwiązane wiadomości oznaczone `\Deleted` w folderze (odtworzone w `TestSpikeNoMoveProfile`). Plan 3.5.1 tego zabrania |
| `IDLE` | natywnie, z zastrzeżeniami | `Idle()` blokuje do potwierdzenia, `IdleCommand.Close()` + `Wait()` kończą; po IDLE połączenie działa dalej. Biblioteka sama restartuje IDLE co **28 min** (stała, plan mówi 25 min) |
| Unilateral data w IDLE | natywnie | `Options.UnilateralDataHandler{Mailbox (NumMessages = EXISTS), Fetch, Expunge}`. EXISTS po ok. 0,5 s od APPENDa z innego połączenia, FETCH ze zmianą flagi po ok. 0,5 s. **Uwaga:** unilateral `FETCH` z Dovecota zawiera `FLAGS` i `MODSEQ`, ale **bez `UID`** (tylko numer sekwencyjny). Handler blokuje czytnik klienta |
| `LIST` z `RETURN (SPECIAL-USE)` | natywnie | `ListOptions{ReturnSpecialUse, ReturnChildren, SelectSpecialUse}`, role w `ListData.Attrs` (`imap.MailboxAttrSent` itd.) |
| `CREATE ... USE (\Archive)` | wspierane przez bibliotekę, **Dovecot ignoruje** | `CreateOptions{SpecialUse}` wysyła poprawną komendę, serwer odpowiada OK, ale rola nie powstaje (`LIST` bez `\Archive`); Dovecot nie reklamuje `CREATE-SPECIAL-USE`. Rolę trzeba nadać konfiguracją serwera albo zapisać w Silo |
| `STATUS (MESSAGES UIDNEXT UIDVALIDITY HIGHESTMODSEQ)` | natywnie | `Status(mbox, &imap.StatusOptions{...}).Wait()` |
| `LIST-STATUS` (`RETURN (STATUS (...))`) | natywnie | `ListOptions.ReturnStatus`; `ListData.Status` wypełnione dla wszystkich folderów jedną komendą |
| Keywords | natywnie | `Store(set, &imap.StoreFlags{Op: StoreFlagsAdd, Flags: {"$SiloSnoozed", "Praca"}})`; po zapisie widoczne w `SelectedMailbox.Flags`; `PERMANENTFLAGS \*` potwierdzone. Odpowiedź FETCH zawiera też `\Recent` (IMAP4rev1), do odfiltrowania w ingeście |
| `OBJECTID` (`EMAILID`) | brak po stronie serwera | Dovecot 2.4.5 nie reklamuje OBJECTID w tej konfiguracji (plan zakłada go jako opcjonalny; matcher spada na `dedupe_key`). Biblioteka zna tylko stałą `CapObjectID`: `FetchOptions` nie ma `EMAILID`/`THREADID` (do dopisania, gdy serwer je reklamuje) |
| Profile `no-condstore`, `no-move` | OK | `imap_capability` w Dovecot 2.4 **zastępuje** całą listę (nie jest addytywne), profile wypisują ją jawnie. Zmienia tylko reklamę; `IMAP4rev2` trzeba ukryć w `no-move`, bo implikuje MOVE i UIDPLUS. Dovecot nadal zwraca APPENDUID/COPYUID mimo braku reklamy UIDPLUS |

Nie sprawdzono: `NOTIFY` (RFC 5465; w bibliotece jest tylko stała `CapNotify`, brak komendy), `COMPRESS=DEFLATE`, `BINARY`, XOAUTH2/SASL, STARTTLS i implicit TLS na prawdziwym serwerze (testy bez TLS; ścieżki TLS idą przez stdlib i są do sprawdzenia w Fazie 2 na docker-mailserver), zachowanie przy dużych folderach i `known-uids` w QRESYNC.

## Decyzja

**Zostajemy przy `go-imap/v2 v2.0.0-beta.8` (przypiętym) z cienkim `internal/imapx`.** Wszystko poza QRESYNC działa natywnie. Dopisujemy w `imapx` tylko to, co trwałe i małe (zrobione w Fazie 1): `Dial` z `context`, timeoutami i trybami TLS, `Login` z mapowaniem błędów (`ErrAuthFailed` vs `ErrUnavailable`), `Capabilities` z typowanymi metodami oraz `Await(ctx, ...)` do komend z deadline'em (po przekroczeniu zamyka połączenie, bo biblioteka nie ma anulowania).

**QRESYNC (plan B).** Biblioteka go nie wspiera, a `imapx` nie może go dodać z zewnątrz (brak surowych komend, parser odpowiedzi jest prywatny). Brakujące kawałki w bibliotece to szacunkowo 50-80 linii: zezwolenie na `ENABLE QRESYNC`, pola `QResync` w `SelectOptions` z kodowaniem, parser `VANISHED [(EARLIER)] uid-set` i jego dostarczenie (do `SelectData` i `UnilateralDataHandler`). Ustalenie:

1. **Faza 2 startuje na ścieżce `CONDSTORE`** z planu 3.5.4 (`SELECT (CONDSTORE)`, `FETCH CHANGEDSINCE`, usunięcia przez `UID SEARCH ALL` w ESEARCH + różnica zbiorów). Działa natywnie, jest wymagana dla Gmaila i innych serwerów bez QRESYNC, a spike potwierdził ją na Dovecocie. Ścieżka bez CONDSTORE (STATUS + pełne porównanie) też jest natywna.
2. **QRESYNC dodajemy jako optymalizację** przez fork `emersion/go-imap` (`replace` w `go.mod`, łatka ograniczona do `imapclient`, PR do upstreamu), po pomiarze kosztu `UID SEARCH ALL` na dużych folderach (>50k) w Fazie 2. Do czasu łatki `imapx.Capabilities.HasQRESYNC()` pozostaje informacją, a silnik **nie wysyła** `ENABLE QRESYNC`.
3. Odrzucone na teraz: własny parser IMAP w `imapx` (duplikacja biblioteki) i surowe gniazdo do jednej komendy (SELECT z QRESYNC zmienia stan sesji, więc cała sesja i tak musiałaby rozumieć `VANISHED`).

**Obejścia, które `imapx` musi mieć w Fazie 2 (nie implementowane w tym spike'u):**

- **Własne przeniesienie wiadomości** zamiast `Client.Move`, gdy brak MOVE: `UID COPY` + `UID STORE \Deleted` + `UID EXPUNGE`. Gdy brak UIDPLUS: **nie** wołać `EXPUNGE` poza `Trash`/`Drafts` (plan 3.5.1), w innych folderach kopia + `\Deleted`, a fizyczne usunięcie zostawić serwerowi lub użytkownikowi (dla Silo wiadomość z `\Deleted` jest już „usunięta”). Przenoszenie na takich serwerach jest więc best effort.
- **Unilateral FETCH bez UID** (IDLE): nie ufać UID z handlera; traktować FETCH/EXISTS/EXPUNGE jako sygnał „INBOX zmieniony” (plan 3.5.5 tak robi) i uruchamiać sync przyrostowy (`CHANGEDSINCE`).
- **Timer IDLE**: biblioteka restartuje IDLE co 28 min, zgodnie z RFC 2177 (< 29 min), co jest akceptowalne; plan z 25 min do korekty na „≤ 28 min” albo własna pętla `Close()`+`Idle()`.
- **Timeouty komend**: wszystkie komendy przez `Client.Await(ctx, ...)`.
- **Role folderów**: nie polegać na `CREATE ... USE`; dla nowo tworzonego Archive trzymać rolę w Silo (mapowanie po nazwie) lub wymagać istniejącego folderu.
- **Handlery unilateral** muszą być szybkie (blokują czytnik): kanał buforowany + osobna gorutyna.

## Konsekwencje

- Faza 2 nie jest blokowana: pełna ścieżka CONDSTORE i fallbacki są zweryfikowane na prawdziwym serwerze, w CI (testcontainers, ~1 s na kontener po pobraniu obrazu ok. 6 s).
- Utrzymujemy zależność od wersji beta; testy spike'a działają jak test charakteryzacyjny przy każdej aktualizacji (`go get` nowej bety, `go test ./internal/imapx`).
- QRESYNC to dodatkowa praca (fork/łatka) i ryzyko, ale odłożona do czasu, gdy będą dane o kosztach. Plan 3.1 (wiersz o kliencie) i 3.5.1 (IDLE 25 min, fallback MOVE bez UIDPLUS) wymagają drobnej korekty zgodnie z tym ADR; zmiana planu poza zakresem tego commita.
- Profile Dovecota są adekwatne do testów fallbacków, ale tylko jako reklama CAPABILITY: serwer faktycznie nadal obsługuje ukryte rozszerzenia (np. zwraca COPYUID), więc test „prawdziwego” braku UIDPLUS (brak APPENDUID/COPYUID) będzie wymagał fałszywego serwera w Fazie 2.

## Alternatywy

- **Własny klient IMAP w `imapx`**: pełna kontrola (QRESYNC, VANISHED, NOTIFY), ale kilka tysięcy linii parsera i literałów, bez korzyści poza QRESYNC. Odrzucone.
- **`github.com/emersion/go-imap` v1** (stabilny): bez CONDSTORE/QRESYNC/MOVE w wygodnej formie i bez dalszego rozwoju. Odrzucone.
- **Inne biblioteki**: brak dojrzałej alternatywy z CONDSTORE i IDLE o jakości go-imap/v2 (nie prototypowano). Odrzucone.
- **Fork od razu**: koszt utrzymania zanim zmierzymy potrzebę QRESYNC. Odroczone (punkt 2 decyzji).

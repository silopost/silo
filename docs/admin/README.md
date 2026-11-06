# Administracja instancją Silo

Notatki dla administratora instancji `silo-server` (stan po Fazie 4, `silo-server` 0.4.0). Pełny przewodnik (instalacja z docker-mailserver, hasła aplikacji, backup, upgrade) powstaje w Fazie 5 ([plan 7](../../ARCHITECTURE_AND_PLAN.md#7-roadmapa)). Konfiguracja env: [plan 2.5](../../ARCHITECTURE_AND_PLAN.md#25-konfiguracja-instancji-env) i README `silo-server` (sekcja „Configuration”).

## Limit 26 słów kluczowych w folderze (Dovecot maildir)

Etykiety użytkownika Silo są zapisywane na wiadomościach jako IMAP keywords – Thunderbird pokazuje je jako tagi, a odbudowa cache je odczytuje ([plan 3.7](../../ARCHITECTURE_AND_PLAN.md#37-etykiety-użytkownika-jako-imap-keywords), [ADR 0009](../adr/0009-keyword-state-per-folder.md)).

- Dovecot z formatem **maildir** koduje słowa kluczowe literami `a`–`z` w nazwach plików, więc jeden folder ma najwyżej **26 różnych słów kluczowych** (łącznie z tagami Thunderbirda i innych klientów). Formaty **sdbox/mdbox** nie mają tego limitu.
- Dovecot 2.4 **nie odrzuca** 27. słowa kluczowego: `STORE` kończy się `OK`, ale słowo trafia tylko do indeksu Dovecota i ginie przy jego odbudowie. Dlatego Silo liczy słowa z `PERMANENTFLAGS` folderu i ponad limit nie zapisuje keywordu – etykieta zostaje tylko w Silo dla tego folderu (`keywordState: partial`, `localOnlyFolders`; w `silo-web` ostrzeżenie przy etykiecie). Odmowa `NO` serwera na `STORE` daje ten sam skutek.
- Limit ustawia `SILO_SYNC_KEYWORD_FOLDER_LIMIT` (domyślnie `26`). Dla sdbox/mdbox lub serwera bez limitu ustaw `0`.
- Dovecot nie usuwa słowa z listy folderu, gdy znikają wiadomości, które je miały. Folder, w którym wiele etykiet powstawało i znikało (np. skrzynka testowa e2e), może dojść do limitu mimo niewielu etykiet. Wyjścia: przenieść starą pocztę do innego folderu, odtworzyć folder (lub wolumen poczty w dev) albo przejść na sdbox/mdbox.
- Etykiety `partial` i `local_only` istnieją tylko w bazie Silo – obejmuje je backup Postgresa (plan 3.3).

## Odbudowa cache konta (`rebuild-cache`)

Silo przechowuje lustro poczty (wiadomości, położenia, wątki, bloby) jako cache odtwarzalny z serwera IMAP. Odbudowa usuwa cache konta i robi initial sync od zera.

```sh
silo-server rebuild-cache --account 1        # w kontenerze/środowisku instancji (SILO_DATABASE_URL)
silo-server rebuild-cache --account 1 --yes  # bez pytania o potwierdzenie
```

`--account` to numer konta (`acc_1` w API → `1`).

- To samo robi `POST /api/v1/accounts/{id}/resync` z `{"mode": "rebuild"}` (UI: Ustawienia → Konta → „Odbuduj cache”). Komenda tylko **kolejkuje** odbudowę (wiersz `account_rebuilds`); wykonuje ją działający `silo-server serve` (lub najbliższy start). Można jej użyć także po ręcznym `TRUNCATE` tabel cache.
- Odmowa `409 rebuild_blocked`, gdy wiadomość czeka na wysyłkę lub jest wysyłana (`outbound`) albo operacje czekają na zapis na serwerze (`imap_op`); ponów, gdy `sync-status.pendingOps` = 0.
- **Zostają:** etykiety (nazwy, kolory, drzewo, keywords), filtry, ustawienia, kontakty, historia wyszukiwań, lokalne wiadomości draftów i wysyłek.
- **Przenoszone po `dedupe_key`** (Message-ID + rozmiar) i przypinane, gdy wiadomości wracają: snooze, przypisania etykiet lokalnych (`local_only`, foldery `localOnlyFolders`), wiadomość, na którą odpowiada draft. Etykiety z keywordami wracają z serwera (także bez metadanych w tabeli `labels` – są tworzone ponownie z nazw keywordów).
- **Giną:** możliwość cofnięcia (undo) operacji sprzed odbudowy.
- Czas: initial sync całego konta (na dev ~2 s dla kilkudziesięciu wiadomości; duże skrzynki – minuty do godzin, wg `SILO_SYNC_BACKFILL_RATE`).

## Folder `Snoozed`

- Odłożenie wątku (snooze) przenosi jego wiadomości z INBOX do folderu roli `snoozed` – domyślnie `Snoozed`, tworzonego przez Silo przy pierwszym użyciu (jak Archive) – i dodaje keyword `$SiloSnoozed`. Inne programy pocztowe nie pokazują ich więc w Odebranych ([plan 3.10](../../ARCHITECTURE_AND_PLAN.md#310-snooze)).
- Inną nazwę folderu można zmapować przez `PUT /accounts/{id}/folders` (rola `snoozed`); istniejący folder o nazwie `Snoozed` jest wykrywany automatycznie.
- Wybudza job `snooze_wake` (co 30 s i przy nowej wiadomości w odłożonym wątku): wiadomości wracają do INBOX, najnowsza nieprzeczytana, bez `$SiloSnoozed`. **Wymaga działającego Silo** – gdy instancja stoi, poczta czeka bezpiecznie w `Snoozed` i wraca po starcie.
- Przeniesienie wiadomości z `Snoozed` w innym kliencie kasuje snooze w Silo (≤ 30 s). Usunięcie lub odtworzenie folderu z tymi samymi wiadomościami (nowe `UIDVALIDITY`) nie gubi snooze.
- Nie usuwaj folderu `Snoozed` z wiadomościami, jeśli instancja ma aktywne snooze – wiadomości wrócą do INBOX dopiero po ich ponownym znalezieniu przez sync.

## Reindeks wyszukiwania po upgrade

- Indeks pełnotekstowy (`messages.search_tsv`) buduje tokenizer aplikacji ([ADR 0008](../adr/0008-search-tokenizer-in-app.md)); każdy wiersz ma wersję tokenizera (`messages.search_ver`).
- Po upgrade do wersji z nowym tokenizerem (pierwszy raz: 0.3.0 → 0.4.0, migracja `000006_search_index`) `silo-server` przy starcie przeindeksowuje w tle wiersze ze starszą wersją, paczkami po 500 (log `search index rebuilt messages=… took=…`; na dev 5158 wiadomości w < 1 s). Do końca reindeksu wyniki po starszych wiadomościach mogą być niepełne; odpowiedź wyszukiwania niesie wtedy `indexing`, a UI pokazuje „Indeksowanie treści”.
- Migracje 0.4.0 (`000006`–`000009`) są addytywne (nowe kolumny, tabele, indeksy) i wykonują się automatycznie przy starcie (`serve`, chyba że `--migrate=false`). Przed upgrade zrób backup Postgresa.

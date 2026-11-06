# 0009. Stan keywordu etykiety per folder i limit liczony z `PERMANENTFLAGS`

- **Status:** Przyjęty
- **Data:** 2026-11-06
- **Dotyczy:** silo-server, silo-web

## Kontekst

Etykiety użytkownika są zapisywane na serwerze jako IMAP keywords ([plan 3.7](../../ARCHITECTURE_AND_PLAN.md#37-etykiety-użytkownika-jako-imap-keywords)), żeby były widoczne w Thunderbirdzie i wracały po odbudowie cache. Plan zakładał dwa stany na poziomie konta (`accounts.keywords_supported`) i przy przekroczeniu limitu maildir (26 słów kluczowych na folder – litery `a`–`z` w nazwach plików) „serwer odrzuca nowe”. Test na Dovecocie 2.4.5 (maildir, Faza 4) pokazał, że **serwer nie odrzuca 27. keywordu**: `STORE` kończy się `OK`, keyword trafia tylko do indeksu Dovecota i ginie przy jego odbudowie. Etykieta wyglądałaby na zapisaną, a po awarii indeksu lub `rebuild-cache` znikałaby z wiadomości. Limit jest per folder, więc jedna etykieta może być keywordem w INBOX i nie móc nim być w Archive.

## Decyzja

Silo **liczy limit samo** i przechowuje **stan keywordu etykiety per folder**.

- **Limit:** przed zapisem nowego keywordu Silo liczy słowa kluczowe w `PERMANENTFLAGS` folderu (odświeżanym przy każdym `SELECT`) i porównuje z `SILO_SYNC_KEYWORD_FOLDER_LIMIT` (domyślnie 26; `0` = bez limitu, np. sdbox/mdbox). Ponad limit keyword nie jest zapisywany. `NO` na `STORE` w folderze, który ogłasza `\*`, ma ten sam skutek.
- **Stan:** tabela `label_folder_state(label_id, folder_id)` (migracja `000009_label_folders_rebuild`) – foldery, w których etykieta żyje tylko w Silo. API: `GET /labels` → `keywordState` ∈ `mirrored | local_only | partial`, przy `partial` `localOnlyFolders: [f_…]`; dodanie folderu do listy → `label.changed`.
- **Poziom konta bez zmian:** brak `\*` w `PERMANENTFLAGS` INBOX → `local_only` dla wszystkich etykiet i `account.error keywords_unsupported` (tylko w tym, globalnym przypadku).
- **Kolizje:** nowy keyword nie zajmuje słowa, które serwer już zna z `PERMANENTFLAGS` folderu (tag innego klienta) – dostaje `_2`, `_3`, mapowanie jest jawne w `labels.imap_keyword`.
- **Odbudowa cache:** przypisania etykiet w folderach `localOnlyFolders` (i etykiet `local_only`) są przenoszone przez `account_rebuilds.restore` po `dedupe_key`, bo nie da się ich odczytać z serwera.

## Konsekwencje

- Etykieta nigdy nie „udaje” zapisu na serwerze: to, co jest keywordem, przetrwa odbudowę indeksu Dovecota i `rebuild-cache`; reszta jest jawnie oznaczona w UI (ostrzeżenie przy etykiecie, `silo-web` pokazuje foldery).
- Liczenie z `PERMANENTFLAGS` zależy od tego, że serwer ogłasza w nim wszystkie słowa kluczowe folderu (Dovecot: tak). Dovecot nie usuwa słowa z listy po zniknięciu wiadomości, więc folder testowy z wieloma przebiegami e2e może dojść do limitu (porada w `docs/admin`).
- Etykiety `partial` wymagają backupu metadanych Silo tak jak `local_only` (plan 3.3).
- Nowy env `SILO_SYNC_KEYWORD_FOLDER_LIMIT` (plan 2.5) – administrator serwera bez limitu ustawia `0`.

## Alternatywy

- **Poleganie na odmowie serwera (plan pierwotny):** Dovecot 2.4 maildir nie odmawia – ciche utraty etykiet. Odrzucone.
- **Stan tylko na poziomie konta (`keywords_supported=false` po pierwszym przekroczeniu):** jeden pełny folder wyłączałby keywords wszędzie, także tam, gdzie działają. Odrzucone.
- **Prefiks lub kodowanie wielu etykiet w jednym keywordzie:** obchodzi limit, ale tagi przestają być czytelne w Thunderbirdzie (sprzeczne z celem 3.7). Odrzucone.

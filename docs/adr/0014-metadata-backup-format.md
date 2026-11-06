# 0014. Format backupu metadanych `silo-metadata` v1

- **Status:** Przyjęty
- **Data:** 2026-11-06
- **Dotyczy:** silo-server, silo

## Kontekst

Postgres Silo trzyma **cache** poczty, który sync odtwarza z serwera IMAP, oraz **metadane** istniejące tylko w Silo ([plan 3.3](../../ARCHITECTURE_AND_PLAN.md#33-źródło-prawdy-serwer-imap-vs-postgres)). `pg_dump` całej bazy jest duży i wiąże backup z wersją schematu oraz identyfikatorami wierszy. DoD Fazy 5: backup metadanych → utrata danych Silo → restore + sync → identyczna lista Inbox; etykiety, snooze, filtry i wiadomości zaplanowane zachowane.

## Decyzja

`silo-server export-metadata` zapisuje jeden dokument JSON `silo-metadata` w wersji 1; `import-metadata` wczytuje go do zmigrowanej bazy (`scripts/backup.sh metadata` / `scripts/restore.sh metadata`).

- **Sekcje** (mapa nazwa → tablica; nieznane pomijane z ostrzeżeniem, brakujące = puste): `users` (hash hasła, ustawienia, TOTP), `accounts` (konfiguracja serwerów i zaszyfrowany sekret, bez stanu sync), `labels` (użytkownika: nazwa, keyword, kolor, zagnieżdżenie), `labelAssignments`, `snoozes`, `drafts` z blobami `local` (base64 inline; `--no-local-blobs` zostawia sam `sha256`), `outbound` (`queued`/`sending`), `filters` (etykiety akcji po **nazwie**: `actions.addLabels`), `searchHistory`, `contacts` (ręczne).
- **Stabilne tożsamości zamiast ID:** użytkownik = e-mail, konto = użytkownik + host IMAP + login, etykieta = konto + nazwa, wiadomość = nagłówek `Message-ID` (`message_id_hdr`). Sekrety przeszyfrowane z AAD ze stabilnych kluczy – import wymaga tego samego `SILO_SECRET_KEY` (lub jako `SILO_SECRET_KEY_PREVIOUS`).
- **Odtwarzanie przypisań** etykiet i snooze czeka na sync: wiersze w tabeli staging `metadata_restores`; job `metadata_restore` stosuje je w miarę ingestu (etykiety `mirrored` zapisują keyword przez kolejkę operacji), ponawia co minutę do 24 h, potem jest `dead` w panelu admina. Wiadomości zaplanowane wracają do kolejki na swój czas.
- **Poza backupem:** sesje, zdarzenia, joby, operacje write-back (`imap_op` – `backup.sh` czeka na pustą kolejkę), cache (wiadomości, wątki, foldery, bloby mirrora), klucz `SILO_SECRET_KEY`.
- Import do bazy z użytkownikami odmawia; `--merge` dopisuje idempotentnie.

## Konsekwencje

- Backup jest mały, niezależny od schematu i ID; odtworzenie na nowej instancji tej samej lub nowszej wersji.
- Odtworzenie przypisań trwa tyle, co initial sync (e2e: kilkadziesiąt sekund dla małej skrzynki; duże skrzynki – godziny).
- Wiadomości bez `Message-ID` (lub z powtórzonym) nie odzyskają etykiet lokalnych; draft przejęty z kopii innego klienta (bez `X-Silo-Draft-Id`) wraca jako duplikat.
- Format rozszerzany addytywnie; zmiana łamiąca = `v2` z importem `v1`.

## Alternatywy

- **Tylko `pg_dump`:** zachowuje wszystko, ale tylko na tej samej wersji schematu, z cache (rozmiar) i bez scalania z inną instancją. Zostaje jako tryb `full`.
- **Eksport tabel metadanych przez `COPY` z ID:** prostszy, ale ID cache (wiadomości, wątki) po odbudowie są inne – przypisania byłyby nieodtwarzalne. Odrzucone.
- **Wszystkie metadane na serwerze IMAP** (keywords, foldery): działa dla etykiet `mirrored` i snooze, ale nie dla filtrów, ustawień, draftów lokalnych i etykiet `local_only`. Uzupełnienie, nie zastępstwo.

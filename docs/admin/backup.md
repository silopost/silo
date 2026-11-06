# Backup i odtwarzanie

Postgres Silo trzyma dwa rodzaje danych ([plan 3.3](../../ARCHITECTURE_AND_PLAN.md#33-źródło-prawdy-serwer-imap-vs-postgres)): **cache** poczty (wiadomości, foldery, wątki, etykiety systemowe, bloby mirrora), który synchronizacja odbudowuje z serwera IMAP, oraz **metadane** istniejące tylko w Silo. Poczta jest na serwerze IMAP – jego backup to zadanie administratora serwera poczty.

Skrypty `scripts/backup.sh` i `scripts/restore.sh` działają na stosie `docker compose` (plik z `SILO_COMPOSE_FILE`, domyślnie produkcyjny `docker-compose.yml`; w dev `SILO_COMPOSE_FILE=docker-compose.dev.yml`), także z obrazem distroless. Format metadanych: [ADR 0014](../adr/0014-metadata-backup-format.md); szczegóły eksportu i importu: README `silo-server`, sekcja „Backup and restore”.

```sh
scripts/backup.sh metadata --out backups/        # domyślny tryb; --user EMAIL: jeden użytkownik
scripts/backup.sh full --out backups/            # pg_dump -Fc całej bazy + tar.gz wolumenu blobów
scripts/restore.sh metadata backups/silo-metadata-<ts>.json [--merge]
scripts/restore.sh full backups/silo-db-<ts>.dump [backups/silo-blobs-<ts>.tar.gz] [--yes]
```

| Tryb | Zawiera | Odtworzenie |
|---|---|---|
| `metadata` | JSON z `silo-server export-metadata`: użytkownicy (hash hasła, ustawienia, TOTP), konta (konfiguracja i zaszyfrowany sekret skrzynki), etykiety użytkownika z przypisaniami i snooze (po Message-ID), filtry (etykiety po nazwie), kontakty ręczne, historia wyszukiwań, drafty i wiadomości zaplanowane z załącznikami | na pustą, zmigrowaną bazę: `import-metadata`; konta robią initial sync, etykiety i snooze wracają w miarę synchronizacji (job `metadata_restore`), wiadomości zaplanowane wracają do kolejki na swój czas |
| `full` | `pg_dump -Fc` całej bazy (cache i metadane) oraz archiwum wolumenu blobów | zatrzymanie `silo-server`, `pg_restore --clean --if-exists`, podmiana zawartości wolumenu blobów, start; nadpisuje dane, więc pyta o potwierdzenie (`--yes`) |

Każdy plik dostaje `.sha256`; `restore.sh` sprawdza sumę, gdy plik leży obok.

## Czego nie ma w backupie

- **`SILO_SECRET_KEY`** – hasła skrzynek, tokeny OAuth2 i sekrety TOTP są nim zaszyfrowane. Przechowuj klucz **osobno** od backupów (menedżer haseł, sejf, inny nośnik); odtwarzaj z tym samym kluczem (albo z nim jako `SILO_SECRET_KEY_PREVIOUS`). Bez klucza użytkownicy muszą ponownie podać hasła skrzynek i zalogować się przez OAuth2.
- `metadata`: sesje (użytkownicy logują się ponownie), zdarzenia, joby, cache poczty (odtwarza sync), operacje write-back jeszcze niezapisane na serwerze (`imap_op`, np. archiwizacja w oknie undo) – `backup.sh` czeka do 60 s (`SILO_BACKUP_WAIT`) na pustą kolejkę, potem ostrzega i eksportuje.
- Bucket S3 przy `SILO_BLOB_BACKEND=s3` – `full` archiwizuje tylko wolumen; bucket zabezpiecz narzędziami dostawcy (wersjonowanie, replikacja, `mc mirror`).
- Pliki `.env` i `Caddyfile` – trzymaj w repozytorium konfiguracji lub kopii hosta (`.env` zawiera klucz, więc osobno od backupów bazy).

## Harmonogram

`metadata` jest mały (kilka–kilkaset kB na użytkownika plus załączniki draftów) – codziennie; `full` (rozmiar skrzynek) – tygodniowo albo przed upgrade. Przykład `/etc/cron.d/silo-backup` (instalacja w `/opt/silo`):

```text
15 3 * * *  root  cd /opt/silo && scripts/backup.sh metadata --out /var/backups/silo >> /var/log/silo-backup.log 2>&1
45 3 * * 0  root  cd /opt/silo && scripts/backup.sh full --out /var/backups/silo >> /var/log/silo-backup.log 2>&1
30 4 * * *  root  find /var/backups/silo -name 'silo-*' -mtime +30 -delete
```

Backup zawiera hashe haseł, zaszyfrowane sekrety i treść draftów: katalog z prawami `0700`, kopia poza hostem zaszyfrowana (np. `age`, `gpg`, `restic`).

## Odtworzenie krok po kroku

**Z backupu `metadata`** (nowy host lub utracona baza):

1. Instalacja jak w [README](README.md#instalacja-produkcyjna), z **tym samym** `SILO_SECRET_KEY` w `.env`.
2. `docker compose up -d` – `silo-server` tworzy pustą bazę i wykonuje migracje. W trybie `imap` **nie loguj się przed importem** (logowanie zakłada użytkownika).
3. `scripts/restore.sh metadata /var/backups/silo/silo-metadata-<ts>.json` (sprawdza sumę, schemat i pustą bazę; `--merge` importuje do istniejących użytkowników bez duplikatów).
4. Konta startują initial sync przy najbliższym przeglądzie managera (do ok. 20 s). Etykiety i snooze wracają w miarę synchronizacji; job `metadata_restore` ponawia co minutę do 24 h, potem jest `dead` w panelu admina (niedopasowane wiersze zostają z `last_error`).
5. Użytkownicy logują się ponownie (sesje nie są w backupie).

**Z backupu `full`:** `scripts/restore.sh full silo-db-<ts>.dump silo-blobs-<ts>.tar.gz` na działającym stosie tej samej wersji (zatrzymuje `silo-server`, odtwarza bazę i bloby, uruchamia go). Po restore starszej wersji niż obrazy – najpierw wróć do tagów z czasu backupu.

**Uszkodzony cache jednego konta** (rozjazd z serwerem, utracone bloby): bez restore – `silo-server rebuild-cache --account N` ([README, sekcja „Odbudowa cache konta”](README.md#odbudowa-cache-konta-rebuild-cache)). Brakujące bloby mirrora są też pobierane ponownie z IMAP przy pierwszym odczycie.

## Ograniczenia

- Draft otwarty z kopii w Drafts zapisanej przez inny klient (bez `X-Silo-Draft-Id`) wraca jako lokalny draft obok tej kopii (duplikat do usunięcia ręcznie).
- Wiadomości bez nagłówka `Message-ID` nie odzyskają etykiet tylko-lokalnych (`local_only`/`partial`); etykiety zapisane jako keywords wracają z serwera.
- Snooze, którego czas minął w trakcie przerwy, budzi się zaraz po odtworzeniu.

## Test end-to-end

`scripts/e2e-backup-restore.sh` przechodzi DoD Fazy 5 na osobnym stosie `docker-compose.backup-test.yml` (projekt `silo-bt`): seed, etykieta, archiwizacja, draft z załącznikiem, wiadomość zaplanowana, snooze, filtr → `backup.sh metadata` → usunięcie wolumenów Silo → `restore.sh metadata` → porównanie (README repozytorium, sekcja „Test backupu i odtwarzania”).

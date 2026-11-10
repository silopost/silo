# Backup and restore

Silo's Postgres holds two kinds of data: a **cache** of mail (messages, folders, threads, system labels, mirror blobs), which synchronization rebuilds from the IMAP server, and **metadata** that exists only in Silo (the IMAP server is the source of truth for mail, [ADR 0005](../adr/0005-imap-source-of-truth.md)). The mail itself is on the IMAP server – backing it up is the job of the mail server's administrator.

The scripts `scripts/backup.sh` and `scripts/restore.sh` work on the `docker compose` stack (the files from `SILO_COMPOSE_FILE`, one file or a `:`-separated list; unset: `COMPOSE_FILE` from `.env` with the production variant, otherwise the base `docker-compose.yml`; in dev `SILO_COMPOSE_FILE=docker-compose.dev.yml`). `restore.sh full` recreates `silo-server`, so it needs the variant files (`COMPOSE_FILE` or `SILO_COMPOSE_FILE`), otherwise `silo-server` comes back without the settings of the variant, also with the distroless image. Metadata format: [ADR 0014](../adr/0014-metadata-backup-format.md); details of export and import: the `silo-server` README, section "Backup and restore".

```sh
scripts/backup.sh metadata --out backups/        # default mode; --user EMAIL: a single user
scripts/backup.sh full --out backups/            # pg_dump -Fc of the whole database + tar.gz of the blob volume
scripts/restore.sh metadata backups/silo-metadata-<ts>.json [--merge]
scripts/restore.sh full backups/silo-db-<ts>.dump [backups/silo-blobs-<ts>.tar.gz] [--yes]
```

| Mode | Contains | Restore |
|---|---|---|
| `metadata` | JSON from `silo-server export-metadata`: users (password hash, settings, TOTP), accounts (configuration and the encrypted mailbox secret), user labels with assignments and snoozes (by Message-ID), filters (labels by name), manual contacts, search history, drafts and scheduled messages with attachments | into an empty, migrated database: `import-metadata`; accounts run an initial sync, labels and snoozes come back as synchronization progresses (job `metadata_restore`), scheduled messages go back to the queue for their time |
| `full` | `pg_dump -Fc` of the whole database (cache and metadata) and an archive of the blob volume | stop `silo-server`, `pg_restore --clean --if-exists`, replace the contents of the blob volume, start; it overwrites data, so it asks for confirmation (`--yes`) |

Every file gets a `.sha256`; `restore.sh` verifies the checksum when the file is next to it.

## What is not in the backup

- **`SILO_SECRET_KEY`** – mailbox passwords, OAuth2 tokens and TOTP secrets are encrypted with it. Keep the key **separately** from the backups (password manager, safe, another medium); restore with the same key (or with it as `SILO_SECRET_KEY_PREVIOUS`). Without the key, users have to enter their mailbox passwords again and sign in through OAuth2 again.
- `metadata`: sessions (users sign in again), events, jobs, the mail cache (restored by sync), write-back operations not yet written to the server (`imap_op`, e.g. an archive within the undo window) – `backup.sh` waits up to 60 s (`SILO_BACKUP_WAIT`) for an empty queue, then warns and exports.
- The S3 bucket with `SILO_BLOB_BACKEND=s3` – `full` archives only the volume; protect the bucket with the provider's tools (versioning, replication, `mc mirror`).
- The `.env` file and any changed proxy configuration (`deploy/caddy/Caddyfile`, nginx `silo.conf`) – keep them in a configuration repository or a host copy (`.env` contains the key, so separately from the database backups).

## Schedule

`metadata` is small (a few to a few hundred kB per user plus draft attachments) – daily; `full` (the size of the mailboxes) – weekly or before an upgrade. Example `/etc/cron.d/silo-backup` (installation in `/opt/silo`):

```text
15 3 * * *  root  cd /opt/silo && scripts/backup.sh metadata --out /var/backups/silo >> /var/log/silo-backup.log 2>&1
45 3 * * 0  root  cd /opt/silo && scripts/backup.sh full --out /var/backups/silo >> /var/log/silo-backup.log 2>&1
30 4 * * *  root  find /var/backups/silo -name 'silo-*' -mtime +30 -delete
```

A backup contains password hashes, encrypted secrets and draft content: a directory with `0700` permissions, an encrypted off-host copy (e.g. `age`, `gpg`, `restic`).

## Step-by-step restore

**From a `metadata` backup** (a new host or a lost database):

1. Install as in the [README](README.md#production-installation), with **the same** `SILO_SECRET_KEY` in `.env`.
2. `docker compose up -d` – `silo-server` creates an empty database and runs the migrations. In mode `imap` **do not sign in before the import** (signing in creates the user).
3. `scripts/restore.sh metadata /var/backups/silo/silo-metadata-<ts>.json` (checks the checksum, the schema and that the database is empty; `--merge` imports into existing users without duplicates).
4. Accounts start an initial sync at the manager's next pass (up to about 20 s). Labels and snoozes come back as synchronization progresses; the `metadata_restore` job retries every minute for up to 24 h, then it is `dead` in the admin panel (unmatched rows remain with `last_error`).
5. Users sign in again (sessions are not in the backup).

**From a `full` backup:** `scripts/restore.sh full silo-db-<ts>.dump silo-blobs-<ts>.tar.gz` on a running stack of the same version (it stops `silo-server`, restores the database and the blobs, and starts it). When restoring a version older than the images – first go back to the tags from the time of the backup.

**A damaged cache of a single account** (drift from the server, lost blobs): no restore needed – `silo-server rebuild-cache --account N` ([README, section "Account cache rebuild"](README.md#account-cache-rebuild-rebuild-cache)). Missing mirror blobs are also fetched again from IMAP on first read.

## Limitations

- A draft opened from a copy in Drafts saved by another client (without `X-Silo-Draft-Id`) comes back as a local draft next to that copy (a duplicate to delete by hand).
- Messages without a `Message-ID` header do not get local-only labels (`local_only`/`partial`) back; labels stored as keywords come back from the server.
- A snooze whose time passed during the outage wakes up right after the restore.

## End-to-end test

`scripts/e2e-backup-restore.sh` runs the phase 5 definition of done on a separate stack `docker-compose.backup-test.yml` (project `silo-bt`): seed, a label, an archive, a draft with an attachment, a scheduled message, a snooze, a filter → `backup.sh metadata` → removal of the Silo volumes → `restore.sh metadata` → comparison (the repository README, section ["Backup and restore test"](../../README.md#backup-and-restore-test)).

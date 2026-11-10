# Administering a Silo instance

A guide for administrators of a Silo instance (state after phase 5: `silo` 0.5.0, `silo-server` 0.5.0, `silo-web` 0.4.0). Full list of environment variables: the `silo-server` README (section "Configuration") and the [Configuration section of the main README](../../README.md#configuration); threat model: [threat-model.md](../threat-model.md).

Separate pages: [backup and restore](backup.md), [OAuth2 for Gmail and Microsoft 365](oauth.md).

## Production installation

**Requirements:** a Linux host with Docker Engine and Compose v2 (≥ 2.24), for the `caddy` variant a DNS record (A/AAAA) for the instance's domain pointing at the host and open ports 80 and 443 (Caddy obtains an ACME certificate), outbound traffic to mail servers (IMAP 993/143, SMTP 587/465) and HTTPS (ISPDB, OAuth2 providers). Memory: `silo-server` fits in a few hundred MB (200k-message test: max. 77 MiB RSS); the Postgres and blob disk grows with the size of the mirrored mailboxes (limits `SILO_MIRROR_*`).

The stack (project `silo-prod`) is the base [`docker-compose.yml`](../../docker-compose.yml) plus one variant overlay from `deploy/` that adds the reverse proxy; the variants, when to use which and their commands: [the main README](../../README.md#choose-a-variant). The base: `postgres:17` (volume `pgdata`), `silo-server` (image `ghcr.io/silopost/silo-server:${SILO_SERVER_TAG}`, distroless nonroot, volume `blobs` prepared by `blobs-init`, no host ports) and `silo-web` (`ghcr.io/silopost/silo-web:${SILO_WEB_TAG}`, a static build served by nginx inside the image, without an `/api` proxy). The mail server is external. The variants:

- **`caddy`** ([`deploy/caddy/docker-compose.yml`](../../deploy/caddy/docker-compose.yml), recommended): Caddy with TLS via ACME on 80/443, [`Caddyfile`](../../deploy/caddy/Caddyfile): `/api/v1/events` without buffering, `/api/*` and `/healthz` → `silo-server`, everything else → `silo-web`, security headers and HSTS for the SPA. Requires `SILO_DOMAIN`.
- **`http`** ([`deploy/http/docker-compose.yml`](../../deploy/http/docker-compose.yml)): the same Caddy and `Caddyfile` with the site address `http://:8080` – plain HTTP on `SILO_HTTP_PORT` (default 8080), no TLS and no HSTS. Requires `SILO_PUBLIC_URL=http://<host>:8080`. Mailbox passwords cross the network in cleartext: only for a trusted network or behind your own TLS terminator.
- **`nginx`** ([`deploy/nginx/`](../../deploy/nginx/README.md)): behind an existing nginx with certbot (e.g. a Portainer stack): `silo-server` and `silo-web` join the nginx network, an nginx server block and the deployment steps.

Installation with the `caddy` variant (`COMPOSE_FILE` in `.env` saves repeating `-f docker-compose.yml -f deploy/caddy/docker-compose.yml` in every `docker compose` command):

```sh
git clone --branch v0.8.0 https://github.com/silopost/silo.git && cd silo
cp .env.example .env
openssl rand -base64 32     # -> SILO_SECRET_KEY
openssl rand -hex 24        # -> SILO_POSTGRES_PASSWORD
$EDITOR .env                # production section: SILO_DOMAIN, keys, SILO_DEFAULT_*
docker compose -f docker-compose.yml -f deploy/caddy/docker-compose.yml up -d
docker compose logs -f silo-server       # migrations at start-up, then listening on :8080
curl -fsS https://mail.example.com/healthz && curl -fsS https://mail.example.com/api/v1/meta
```

The commands below write plain `docker compose …` and assume `COMPOSE_FILE` or the `-f` files of the variant (`docker compose exec` works with the base alone).

- **`.env`:** `docker-compose.yml` passes all `SILO_*` variables from `.env` to `silo-server` (`env_file`; another file: `SILO_ENV_FILE`). Required: `SILO_SECRET_KEY`, `SILO_POSTGRES_PASSWORD`, in mode `imap` `SILO_DEFAULT_IMAP_HOST`, and per variant `SILO_DOMAIN` (`caddy`), `SILO_PUBLIC_URL` (`http`, `nginx`), `SILO_PROXY_NETWORK` and `SILO_TRUSTED_PROXIES` (`nginx`). With `caddy`, `SILO_PUBLIC_URL` defaults to `https://$SILO_DOMAIN` (it must match the address in the browser: `Origin` checks, the `Secure` cookie, the OAuth2 return address).
- **`SILO_SECRET_KEY`** encrypts mailbox passwords, OAuth2 tokens and TOTP secrets. Keep a copy **separately** from the database backups (password manager, safe). Without the key a backup cannot restore access to the mailboxes; rotation: the `silo-server` README (`rotate-secrets`).
- **`SILO_TRUSTED_PROXIES`** (variants `caddy` and `http`; for `nginx` see [deploy/nginx](../../deploy/nginx/README.md)): the compose network has a fixed subnet `SILO_NETWORK_SUBNET` (default `172.29.250.0/24`, change it on a collision); Caddy comes from it, so only its `X-Forwarded-For` is honored. Caddy does not pass on `X-Forwarded-For` from clients (only from its own trusted proxies), so the header cannot be forged from the outside. Behind an additional load balancer, add its address to `SILO_TRUSTED_PROXIES` and to Caddy's `trusted_proxies` option. Check in the `security event` log that `ip=` shows client addresses and not the Docker gateway (Docker keeps the source address when publishing ports through iptables; `userland-proxy` loses it).
- **Default server – docker-mailserver in another compose project on the same host:** attach the mail container to Silo's network with an alias equal to the name in its certificate, so that TLS verifies, and set that name as `SILO_DEFAULT_IMAP_HOST`/`SILO_DEFAULT_SMTP_HOST`. In the docker-mailserver compose file (the `silo-prod_default` network is created by Silo's first `docker compose up`):

  ```yaml
  services:
    mailserver:
      networks:
        default: {}
        silo:
          aliases: [mail.example.com]
  networks:
    silo:
      external: true
      name: silo-prod_default
  ```

  The default host is trusted (it does not go through the anti-SSRF filter), so a private address is fine. An external server: a public host name, ports 993/`implicit` and 587/`starttls` (or 465/`implicit`).
- **First start:** `silo-server` waits for a healthy Postgres, runs the migrations (under `pg_advisory_lock`) and starts. Mode `imap`: the first sign-in with mailbox credentials creates the user and their account; admin rights are granted with `docker compose exec silo-server /silo-server user admin --email X --set=true`. Mode `local` – see below.
- **Building from source** (before images are published, or for testing): `docker-compose.build.yml` after the variant file, e.g. `docker compose -f docker-compose.yml -f deploy/caddy/docker-compose.yml -f docker-compose.build.yml up -d --build` with the `silo-server` and `silo-web` repositories next to this one.
- `silo-server` logs: the `json-file` driver with rotation (10 MB × 5); format `SILO_LOG_FORMAT` (`text` in `.env.example`, convenient for fail2ban).

## Mode `local` and the first admin

`SILO_AUTH_MODE=local` – Silo users with their own password, created by an admin; they add mailboxes (any servers, autoconfiguration, OAuth2) themselves in the UI ([ADR 0011](../adr/0011-local-auth-mode-and-totp.md)). `SILO_DEFAULT_IMAP_HOST` is optional then.

```sh
docker compose exec silo-server /silo-server user add --email admin@example.com --admin   # password printed once
echo 'a long password' | docker compose exec -T silo-server /silo-server user add --email alice@example.com --password-stdin
docker compose exec -T silo-server /silo-server user passwd --email alice@example.com   # new password from stdin
docker compose exec silo-server /silo-server user list
```

- **TOTP:** every user enables it in `silo-web` (Settings → Security: a QR code and 10 backup codes shown once). Admins should have TOTP enabled. A lost device without codes: Administration → Users → reset TOTP (`POST /admin/users/{id}/totp/reset`).
- **Admin panel** (`silo-web` → Administration, for `isAdmin`): users (creation with a temporary password, password reset, blocking – immediate sign-out and a stop of account sync, deletion with the user's Silo data), accounts (state, error, `pendingOps`, `deadOps`), `dead` jobs (retry / delete). An admin cannot block, demote or delete themselves.
- Switching a running instance from mode `imap` to `local` has not been tested; choose the mode at installation (if you switch, give users passwords with `user passwd`).

## App passwords

Silo signs in to mailboxes in the background, so it stores the credential reversibly (encrypted with `SILO_SECRET_KEY`). A database leak **together with the key** gives access to all mailboxes ([threat-model.md](../threat-model.md)). That is why, instead of the main password, use credentials that are revocable and assigned only to Silo:

- **Gmail / Google Workspace:** preferably OAuth2 ("Sign in with Google", [oauth.md](oauth.md)); alternatively an app password (requires 2-Step Verification; Google Account → Security → App passwords) on an account with a password (`imap.gmail.com:993`, `smtp.gmail.com:465`).
- **Microsoft 365 (Exchange Online):** OAuth2 only – password authentication for IMAP/SMTP is turned off. Outlook.com: OAuth2 (experimental).
- **Dovecot / docker-mailserver:** there are no native app passwords; you can add a second `passdb` (e.g. a `passwd-file` with separate passwords for Silo) before the main one, in docker-mailserver by overriding the Dovecot configuration – Postfix SMTP AUTH goes through Dovecot SASL, so the same password works for sending. Such a password can be revoked without changing the mailbox password (the configuration example is not tested by Silo).
- Shared hosting: if the control panel offers separate IMAP passwords/accounts for applications, use them.

## Upgrade

1. Read the release notes and the [compatibility matrix](../compat-matrix.md) (required `silo-server`/`silo-web` pairs, migrations, reindexes).
2. **Backup:** `scripts/backup.sh full` (and `metadata`) – [backup.md](backup.md).
3. Bump the image tags: a new tag of the `silo` repository (`git pull && git checkout vX.Y.Z` – the defaults of `SILO_SERVER_TAG`/`SILO_WEB_TAG` in `docker-compose.yml`) or the variables in `.env`.
4. `docker compose pull && docker compose up -d` (with `COMPOSE_FILE` or the `-f` files of the variant; coming from a version with Caddy inside `docker-compose.yml`, use the `caddy` variant – its volumes keep their names and the certificates stay). At start-up `silo-server` runs the migrations under `pg_advisory_lock` (`serve --migrate`, enabled by default); state: `docker compose exec silo-server /silo-server migrate version`. Migrations are additive within a release; migrations of cache tables only may require `rebuild-cache` – the changelog says so.
5. Client compatibility: `GET /api/v1/meta` returns `minWebVersion` (for 0.8.0: `0.3.0`). An older `silo-web` in an open tab shows a "New version available · Reload" banner; the PWA shows "New app version ready". Upgrade server and web together (the same `docker compose up -d`).
6. The upgrade path is checked by the `silo-server` CI (`scripts/upgrade-test.sh`, workflow `upgrade.yml`): the image of the previous tag with data (sign-in, messages, a label, a filter, a snooze) → the current image on the same database → the same mailbox, `reconcile` without drift. Locally: 0.3.0 → 0.4.0 + phase 5 (schema 5 → 51) and 0.4.0 → 0.5.0 (9 → 52) PASS.
7. Rollback: migrations have no automatic `down` between releases – go back to the previous tags and run `scripts/restore.sh full` with the backup from step 2.

**Where the images come from:** pushing a `vX.Y.Z` tag in the `silo-server` or `silo-web` repository runs the GitHub Actions workflow `release.yml`, which publishes `ghcr.io/silopost/<repo>:X.Y.Z`, `:X.Y` and `:latest` (multi-arch amd64/arm64); a push to `main` publishes `:edge`. After the first publication, a GHCR package has to be made public once in its settings on GitHub (Package settings → Change visibility); otherwise `docker pull` without signing in to `ghcr.io` does not work.

## Backup and restore

Details, schedule and the restore procedure: [backup.md](backup.md). In short: `scripts/backup.sh metadata` (a small JSON with the data that exists only in Silo, [ADR 0014](../adr/0014-metadata-backup-format.md)) daily, `scripts/backup.sh full` (`pg_dump` + the blob volume) less often; `SILO_SECRET_KEY` separately.

## S3Store

Blobs (raw messages, attachments, uploads, thumbnails) can live in an S3 bucket instead of the `blobs` volume ([ADR 0012](../adr/0012-s3-blobstore.md)). Variables (the `silo-server` README, section "S3Store"): `SILO_BLOB_BACKEND=s3`, `SILO_BLOB_S3_ENDPOINT`, `_BUCKET`, `_ACCESS_KEY`, `_SECRET_KEY`, `_REGION`, `_PREFIX`, `_USE_SSL`, `_PATH_STYLE`.

- **The bucket must exist** – `serve` checks it at start-up and does not create it. MinIO: `mc mb silo/silo-blobs`; AWS: a private bucket (Block Public Access), an IAM user with `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` on `arn:aws:s3:::BUCKET/*` and `s3:ListBucket` on the bucket; `SILO_BLOB_S3_PATH_STYLE=false`, endpoint `s3.<region>.amazonaws.com`.
- MinIO on the same host: a separate container in the `silo-prod_default` network (`SILO_BLOB_S3_ENDPOINT=minio:9000`, `SILO_BLOB_S3_USE_SSL=false` only on the internal network).
- `Put` buffers the blob in a temporary file of the container (`/tmp`) to compute the `sha256` – space for the largest blob is needed.
- The `full` backup does not cover the bucket – use the provider's versioning/replication or `mc mirror`.
- **Migrating from `fs` to `s3` (manual, not tested end-to-end):** the key layout is the same (`ab/cd/<sha256>`, in S3 with a prefix), so copying the volume to the bucket is enough: stop `silo-server` (`docker compose stop silo-server`), copy the contents of the `silo-prod_blobs` volume, skipping `.tmp-*` files (e.g. `mc mirror --exclude ".tmp-*" /var/lib/docker/volumes/silo-prod_blobs/_data silo/silo-blobs/<prefix>`), set `SILO_BLOB_BACKEND=s3` and `SILO_BLOB_S3_*`, `docker compose up -d`. Shortcut: mirror blobs (`kind=mirror`) are a cache – missing ones are fetched from IMAP on read or through `rebuild-cache --all`; **`local` blobs (uploads, drafts, scheduled messages) have no copy on the mail server and must be copied** – without copying, sending scheduled messages and opening draft attachments will fail.

## Hardening

The server-side mechanisms are described in the `silo-server` README (section "Hardening"); here – what to set on the instance.

- **Proxy and client address:** `SILO_TRUSTED_PROXIES` (installation above). Without it, limits and logs see Caddy's address.
- **Limits:** `SILO_RATE_LIMIT_API` (default `600/m` per IP), `SILO_RATE_LIMIT_AUTH` (`20/m` per IP for sign-in, password change, TOTP; plus a per-login limit); exceeding them → `429 rate_limited` with `Retry-After`. At most 8 SSE streams per user. Limits are kept in process memory (a single instance).
- **Headers:** API – `silo-server` (CSP `default-src 'none'`, `nosniff`, `DENY`, `no-referrer`, HSTS with `https`; `SILO_HSTS=false` when the proxy sends HSTS itself or subdomains have no HTTPS). SPA – [`deploy/caddy/Caddyfile`](../../deploy/caddy/Caddyfile) or `deploy/nginx/silo.conf` (CSP `script-src 'self'`, `style-src 'self' 'unsafe-inline'`, `img-src` with `https:`/`http:` for remote images unblocked by the user in the message frame, HSTS `max-age=31536000; includeSubDomains`). With your own proxy, carry these headers over.
- **fail2ban:** `silo-server` logs failed sign-ins, TOTP codes, CSRF rejections, `403` and `429` as `msg="security event" event=… ip=… path=… login=<masked>`. In the Docker log file (`json-file`) the quotes are preceded by `\`, hence the filter for `SILO_LOG_FORMAT=text`:

  ```ini
  # /etc/fail2ban/filter.d/silo.conf
  [Definition]
  failregex = msg=\\"security event\\" event=(?:auth_failed|totp_failed|csrf_rejected) ip=<ADDR>
  ```

  ```ini
  # /etc/fail2ban/jail.d/silo.local
  [silo]
  enabled   = true
  filter    = silo
  logpath   = /var/lib/docker/containers/*/*-json.log
  port      = http,https
  # ports published by Docker bypass the INPUT chain
  chain     = DOCKER-USER
  banaction = iptables-multiport
  maxretry  = 10
  findtime  = 10m
  bantime   = 1h
  ```

  With the `journald` driver (`backend = systemd`, `journalmatch = CONTAINER_NAME=silo-prod-silo-server-1`) use the filters from the `silo-server` README (without `\`). Adding `rate_limited` to the alternation gives a stricter jail (beware of clients behind a shared NAT).
- **Other:** `SILO_ALLOW_CUSTOM_SERVERS=false` in mode `imap` if users do not need other servers; never `SILO_ALLOW_INSECURE_TRANSPORT` in production; Postgres without a host port (as in `docker-compose.yml`); disk and backup encryption.

## Account autoconfiguration

"Add account" in `silo-web` calls `POST /api/v1/accounts/discover`, which suggests IMAP/SMTP servers from the email address: Thunderbird's ISPDB, the `autoconfig.<domain>` / `.well-known` file, SRV records (RFC 6186), and finally guessing `imap.`/`mail.`/`smtp.` with certificate verification (the `silo-server` README, section "Account autoconfiguration"). The result still goes through a connection test before the account is saved.

- `SILO_AUTOCONFIG_ISPDB_URL` – default `https://autoconfig.thunderbird.net/v1.1/`; your own ISPDB mirror or `off` (no queries to Mozilla; domain autoconfig, SRV and guessing remain).
- Mode `imap` without `SILO_ALLOW_CUSTOM_SERVERS`: the answer is the default server, with no network traffic.
- All autoconfiguration connections go through the anti-SSRF filter: private addresses are rejected unless they are on `SILO_CUSTOM_SERVER_ALLOWLIST` (host names, IPs or CIDRs – e.g. a mail server on the company network in mode `local`). Limit of 10 calls per minute per user.
- The instance needs outbound HTTPS (443) and DNS (SRV).

## OAuth2 (Gmail, Microsoft 365)

Registering the application with Google and in Microsoft Entra, the `SILO_OAUTH_*` variables, redirect addresses and diagnostics: [oauth.md](oauth.md) ([ADR 0013](../adr/0013-oauth2-xoauth2.md)).

## The 26-keyword limit per folder (Dovecot maildir)

Silo user labels are stored on messages as IMAP keywords – Thunderbird shows them as tags, and a cache rebuild reads them back ([ADR 0009](../adr/0009-keyword-state-per-folder.md)).

- Dovecot with the **maildir** format encodes keywords as the letters `a`–`z` in file names, so one folder has at most **26 different keywords** (including tags of Thunderbird and other clients). The **sdbox/mdbox** formats do not have this limit.
- Dovecot 2.4 **does not reject** the 27th keyword: `STORE` ends with `OK`, but the word only lands in Dovecot's index and is lost when it is rebuilt. That is why Silo counts the words from the folder's `PERMANENTFLAGS` and does not store a keyword beyond the limit – the label stays only in Silo for that folder (`keywordState: partial`, `localOnlyFolders`; a warning on the label in `silo-web`). A `NO` from the server on `STORE` has the same effect.
- The limit is set by `SILO_SYNC_KEYWORD_FOLDER_LIMIT` (default `26`). For sdbox/mdbox or a server without the limit, set `0`.
- Dovecot does not remove a word from the folder's list when the messages that had it are gone. A folder in which many labels were created and removed (e.g. an e2e test mailbox) can reach the limit despite having few labels. Ways out: move old mail to another folder, recreate the folder (or the mail volume in dev), or switch to sdbox/mdbox.
- `partial` and `local_only` labels exist only in Silo's database – the Postgres backup covers them.

## Account cache rebuild (`rebuild-cache`)

Silo keeps a mirror of mail (messages, locations, threads, blobs) as a cache that can be restored from the IMAP server. A rebuild deletes the account's cache and runs an initial sync from scratch.

```sh
silo-server rebuild-cache --account 1        # in the instance's container/environment (SILO_DATABASE_URL)
silo-server rebuild-cache --account 1 --yes  # without asking for confirmation
```

`--account` is the account number (`acc_1` in the API → `1`).

- `POST /api/v1/accounts/{id}/resync` with `{"mode": "rebuild"}` does the same (UI: Settings → Accounts → "Rebuild cache"). The command only **queues** the rebuild (an `account_rebuilds` row); a running `silo-server serve` executes it (or the next start does). It can also be used after a manual `TRUNCATE` of the cache tables.
- Refused with `409 rebuild_blocked` when a message is waiting to be sent or is being sent (`outbound`), or operations are waiting to be written to the server (`imap_op`); retry when `sync-status.pendingOps` = 0.
- **Kept:** labels (names, colors, tree, keywords), filters, settings, contacts, search history, local draft and outgoing messages.
- **Carried over by `dedupe_key`** (Message-ID + size) and reattached when the messages come back: snoozes, assignments of local labels (`local_only`, `localOnlyFolders` folders), the message a draft replies to. Labels with keywords come back from the server (even without metadata in the `labels` table – they are recreated from the keyword names).
- **Lost:** the ability to undo operations from before the rebuild.
- Time: an initial sync of the whole account (in dev ~2 s for a few dozen messages; large mailboxes – minutes to hours, depending on `SILO_SYNC_BACKFILL_RATE`).

## The `Snoozed` folder

- Snoozing a thread moves its messages from INBOX to the folder with the `snoozed` role – by default `Snoozed`, created by Silo on first use (like Archive) – and adds the `$SiloSnoozed` keyword. Other mail programs therefore do not show them in the Inbox.
- Another folder name can be mapped through `PUT /accounts/{id}/folders` (role `snoozed`); an existing folder named `Snoozed` is detected automatically.
- The `snooze_wake` job wakes them up (every 30 s and on a new message in a snoozed thread): the messages return to INBOX, the newest one unread, without `$SiloSnoozed`. **It requires a running Silo** – while the instance is down, the mail waits safely in `Snoozed` and comes back after the start.
- Moving messages out of `Snoozed` in another client cancels the snooze in Silo (≤ 30 s). Deleting or recreating the folder with the same messages (a new `UIDVALIDITY`) does not lose the snooze.
- Do not delete the `Snoozed` folder with messages in it if the instance has active snoozes – the messages return to INBOX only once sync finds them again.

## Search reindex after upgrade

- The full-text index (`messages.search_tsv`) is built by the application's tokenizer ([ADR 0008](../adr/0008-search-tokenizer-in-app.md)); every row has a tokenizer version (`messages.search_ver`).
- After an upgrade to a version with a new tokenizer (the first time: 0.3.0 → 0.4.0, migration `000006_search_index`), `silo-server` reindexes rows with an older version in the background at start-up, in batches of 500 (log `search index rebuilt messages=… took=…`; in dev 5158 messages in < 1 s). Until the reindex finishes, results for older messages may be incomplete; the search response then carries `indexing`, and the UI shows "Indexing content".
- The 0.4.0 migrations (`000006`–`000009`) are additive (new columns, tables, indexes) and run automatically at start-up (`serve`, unless `--migrate=false`). Back up Postgres before upgrading.

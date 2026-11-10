# Silopost

**The open-source, self-hosted Gmail alternative without Gmail's limits.** A modern webmail and
Android client with the Gmail experience (threads, labels, snooze, undo send, fast search,
keyboard shortcuts, real-time updates) that runs on your server against any IMAP/SMTP mailbox.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Release](https://img.shields.io/badge/release-v0.7.0-informational.svg)](https://github.com/silopost/silo/releases)
[![CI](https://github.com/silopost/silo/actions/workflows/ci.yml/badge.svg)](https://github.com/silopost/silo/actions/workflows/ci.yml)

This repository (`silo`) is the entry point of the project: the Docker Compose stacks for
production (Caddy with TLS, plain HTTP, or behind nginx) and development, the proxy
configurations, operational scripts (backup, restore, mail seed, smoke tests) and the project
documentation. The application code lives in
[`silo-server`](https://github.com/silopost/silo-server), [`silo-web`](https://github.com/silopost/silo-web)
and [`silo-mobile`](https://github.com/silopost/silo-mobile).

## Contents

- [What is Silopost?](#what-is-silopost)
- [Why: Gmail without its limits](#why-gmail-without-its-limits)
- [Features](#features)
- [Repositories](#repositories)
- [Requirements](#requirements)
- [Quick start: production](#quick-start-production)
- [Quick start: development](#quick-start-development)
- [Configuration](#configuration)
- [Running in production](#running-in-production)
- [Development](#development)
- [Testing](#testing)
- [Project structure](#project-structure)
- [Status and roadmap](#status-and-roadmap)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

## What is Silopost?

Silopost (Silo for short) gives you what people like about Gmail – conversation threads, several
labels per message, archive instead of folders, snooze, scheduled send, undo send, Gmail-style
search operators, filters, keyboard shortcuts and a UI that updates live – on infrastructure you
control.

Silopost is a **mail client, not a mail server.** Like Roundcube or Thunderbird, it connects to an
existing mailbox over IMAP and sends through SMTP submission: your own
[docker-mailserver](https://github.com/docker-mailserver/docker-mailserver) or Dovecot/Postfix,
a hosting provider, or even Gmail and Microsoft 365. The IMAP server stays the source of truth for
your mail ([ADR 0005](docs/adr/0005-imap-source-of-truth.md)); Silo keeps a fast local mirror in
Postgres plus the data that only Silo has (labels, snoozes, filters, drafts, settings).

## Why: Gmail without its limits

Gmail is a great product with limits you cannot negotiate. Silopost keeps the experience and
removes the limits that come from someone else owning the service:

| | Gmail (free tier) | Silopost |
|---|---|---|
| Storage | 15 GB, shared with Google Drive and Google Photos | No Silopost quota: limited only by the disk of your IMAP server (for example docker-mailserver/Dovecot) and of the Silo host |
| Mailboxes | Google mailboxes; other providers only through limited import/forwarding | Any IMAP/SMTP provider; several mailboxes per user side by side (the admin sets the cap, default 5) and as many users as your host can serve |
| Ads and content processing | Ads in the free tier; mail is stored and processed by Google | No ads, no tracking; mail travels only between your browser, your Silo host and your mail servers |
| Data ownership | Google's data centres, Google's terms | Your server, your Postgres, your backups (`scripts/backup.sh`) |
| Account lockout | A suspended Google account takes the mailbox (and every other Google service) with it | Nobody else can lock you out of your own instance |
| Multiple providers | One provider | Your own domain, a hosting mailbox and a Gmail or Microsoft 365 account in one UI |
| Self-hosting and offline | SaaS only | Docker Compose on your hardware; installable PWA with offline reading of cached lists and messages |
| Source code | Proprietary | Open source (MIT orchestration, AGPL-3.0 server and clients) |

The fine print:

- Silopost does not receive mail for your domain. To get rid of the 15 GB limit you need an IMAP
  server whose storage you control (docker-mailserver, Dovecot or a provider with the quota you
  want). A Gmail mailbox connected to Silo still has Gmail's quota.
- Silo mirrors messages into Postgres and a blob store on its own host, so that host needs disk too
  (`SILO_MIRROR_MAX_MESSAGE_BYTES` and `SILO_MIRROR_QUOTA_PER_ACCOUNT` cap the mirror).
- By default "Add account" asks Mozilla's Thunderbird ISPDB for server settings
  (`SILO_AUTOCONFIG_ISPDB_URL=off` disables it), and OAuth2 sign-in talks to Google or Microsoft
  once you enable it.

## Features

- **Gmail-style UI** (silo-web): conversation threads, multiple labels, archive, star, important,
  spam, trash, hover actions, virtualised lists (5000 threads scroll without long tasks), undo for
  every action, sync and offline banners.
- **Compose**: several compose windows, TipTap editor, address suggestions, attachments with
  progress, inline images (`cid:`), server-side autosave with exactly one copy in the Drafts
  folder, reply / reply all / forward with the original attachments, **undo send** and
  **scheduled send**.
- **Search** with Gmail syntax parsed on the server (`from:`, `to:`, `subject:`,
  `has:attachment`, `is:`, `label:`, `in:`, dates, sizes, `OR`, `-`, brackets), suggestions
  (history, contacts, labels, operators), chips and an advanced search form.
- **Snooze** (a real `Snoozed` folder on the IMAP server, so other clients do not show snoozed mail
  in their inbox), **filters** (create from a search, apply to existing mail, forwarding),
  **user labels stored as IMAP keywords** (Thunderbird shows them as tags), nested and coloured
  labels.
- **Multiple accounts** per user with an account switcher, unread counters, `g 1`…`g 9`, a
  "From" picker and **Add account** with autoconfiguration (ISPDB, autoconfig, DNS SRV, verified
  guesses) and a connection test.
- **OAuth2 / XOAUTH2** for Gmail and Microsoft 365 ([ADR 0013](docs/adr/0013-oauth2-xoauth2.md)).
- **Two authentication modes**: `imap` (sign in with mailbox credentials) and `local` (Silo users
  with argon2id passwords, **TOTP** with backup codes, an **admin panel**)
  ([ADR 0011](docs/adr/0011-local-auth-mode-and-totp.md)).
- **Real-time updates** over Server-Sent Events with a polling fallback; changes made in other
  IMAP clients show up within seconds (IDLE).
- **PWA**: installable, offline reading of cached lists and messages, update banner.
- **Backup and restore** of the Silo-only metadata or of the whole database
  ([ADR 0014](docs/adr/0014-metadata-backup-format.md)); blobs on the filesystem or in **S3**
  ([ADR 0012](docs/adr/0012-s3-blobstore.md)).
- **Hardening**: per-IP rate limits, security headers and CSP, trusted proxies, a security log
  for fail2ban, anti-SSRF checks on every outbound connection ([threat model](docs/threat-model.md)).
- **Android app** (silo-mobile, unreleased): Gmail-for-Android look and mail feature parity with
  silo-web 0.3.0 – see [Status and roadmap](#status-and-roadmap).
- silo-web UI in **English** by default, **Polish** selectable in Settings.

## Repositories

| Repository | License | Contents | Artefact |
|---|---|---|---|
| [`silo`](https://github.com/silopost/silo) (this one) | MIT | Orchestration (Compose, Caddy, scripts), documentation, ADRs, smoke and backup tests | release tag + Compose file with pinned images |
| [`silo-server`](https://github.com/silopost/silo-server) | AGPL-3.0 | Go backend: REST API (OpenAPI), SSE, IMAP sync, SMTP sending, background workers | `ghcr.io/silopost/silo-server` |
| [`silo-web`](https://github.com/silopost/silo-web) | AGPL-3.0 | React/TypeScript single-page app and PWA, consumer of the OpenAPI contract | `ghcr.io/silopost/silo-web` |
| [`silo-mobile`](https://github.com/silopost/silo-mobile) | AGPL-3.0 | React Native/Expo app (Android; iOS later), thin client of the same API with bearer sign-in | `expo export` bundle in CI; APK via `expo prebuild` + Gradle (distribution not set up yet) |

Current versions: `silo` 0.7.0, `silo-server` 0.7.0, `silo-web` 0.6.0, `silo-mobile` 0.1.0
(unreleased). Which versions work together: [compatibility matrix](docs/compat-matrix.md).

## Requirements

Production:

- Linux host with Docker Engine and Docker Compose v2 (2.24 or newer).
- Depending on the [variant](#choose-a-variant): for `caddy`, a DNS record (A/AAAA) for the
  instance domain pointing to the host and ports 80 and 443 open (Caddy obtains the certificate via
  ACME); for `http`, a free port 8080 and a trusted network; for `nginx`, your nginx with a
  certificate for the domain.
- Outbound access to your mail servers (IMAP 993/143, SMTP 587/465) and to HTTPS (ISPDB, OAuth2
  providers).
- An IMAP/SMTP server to connect to. It is not part of this stack.
- Memory: `silo-server` stays within a few hundred MB (200,000-message test: 77 MiB peak RSS). Disk
  for Postgres and blobs grows with the mirrored mailboxes.

Development:

- Docker with Compose v2, and Git.
- Bash: Linux/macOS, or Git Bash on Windows (all scripts run there).
- Optional: Go 1.26+ and Node.js 22+ to run `silo-server` or `silo-web` outside containers.

## Quick start: production

The production stack is a base file, [`docker-compose.yml`](docker-compose.yml) (Postgres,
`silo-server`, `silo-web`, no proxy and no host ports), plus **one variant overlay** that puts a
reverse proxy in front of it. The proxy is required: `silo-web` serves only the SPA, and the proxy
routes `/api` and `/healthz` to `silo-server`.

### Choose a variant

| Variant | When to use | Exposes | Requires |
|---|---|---|---|
| **`caddy`** (recommended) | A public instance on its own host | 80 and 443 (+ UDP 443, HTTP/3) | `SILO_DOMAIN` with a DNS record pointing at the host; ports 80/443 reachable for ACME |
| **`http`** | A trusted LAN, a test, or behind a TLS terminator you already run | 8080 (`SILO_HTTP_PORT`), plain HTTP | `SILO_PUBLIC_URL=http://<host>:8080`; a trusted network |
| **`nginx`** | A host that already runs nginx with certbot (e.g. Portainer) | nothing; nginx reaches the stack over its Docker network | `SILO_PUBLIC_URL`, `SILO_PROXY_NETWORK`, `SILO_TRUSTED_PROXIES`, a certificate in nginx |

The commands, from the repository root:

```sh
docker compose -f docker-compose.yml -f deploy/caddy/docker-compose.yml up -d   # caddy
docker compose -f docker-compose.yml -f deploy/http/docker-compose.yml up -d    # http
docker compose -f docker-compose.yml -f deploy/nginx/docker-compose.yml up -d   # nginx
```

The same `-f` files go into every later `docker compose` command that creates or changes containers
(`up`, `pull`, `down`, `logs`). To avoid repeating them, set them once in `.env`, then a plain
`docker compose up -d` uses them (the separator is `;` on Windows):

```sh
COMPOSE_FILE=docker-compose.yml:deploy/caddy/docker-compose.yml
```

The rest of this README writes plain `docker compose …` and assumes `COMPOSE_FILE` or the `-f`
files. `docker compose exec silo-server …` also works without them (the base file defines the
service). All variants use the Compose project `silo-prod` and the same volumes, so switching
variants keeps the data: `down` with the old files, `up -d` with the new ones.

### Install (variant `caddy`)

```sh
git clone --branch v0.7.0 https://github.com/silopost/silo.git && cd silo
cp .env.example .env
openssl rand -base64 32     # -> SILO_SECRET_KEY
openssl rand -hex 24        # -> SILO_POSTGRES_PASSWORD
$EDITOR .env                # production section: SILO_DOMAIN, the two secrets, SILO_DEFAULT_*, COMPOSE_FILE
docker compose up -d
docker compose logs -f silo-server        # migrations run at start-up, then it listens on :8080
curl -fsS https://mail.example.com/healthz && curl -fsS https://mail.example.com/api/v1/meta
```

Open `https://<SILO_DOMAIN>` and sign in with a mailbox of the default server (mode `imap`). The
first sign-in creates the Silo user and its account. Keep a copy of `SILO_SECRET_KEY` **separately
from database backups**: without it, stored mailbox passwords, OAuth2 tokens and TOTP secrets
cannot be decrypted. `SILO_DOMAIN=localhost` gets a certificate from Caddy's internal CA, for a
local test.

### Variant `http` (port 8080, no TLS)

The same Caddy and [`Caddyfile`](deploy/caddy/Caddyfile) as `caddy`, with the site address
`http://:8080`: no certificates, no redirect to HTTPS, no HSTS. In `.env`, instead of `SILO_DOMAIN`:

```sh
SILO_PUBLIC_URL=http://192.168.1.10:8080   # exactly the address in the browser
COMPOSE_FILE=docker-compose.yml:deploy/http/docker-compose.yml
# SILO_HTTP_PORT=8081                      # another host port; 127.0.0.1:8080 = loopback only
```

> **Warning:** without TLS, mailbox passwords, session cookies and mail cross the network in
> cleartext. Use this variant only on a network you trust, or publish it on loopback
> (`SILO_HTTP_PORT=127.0.0.1:8080`) behind a TLS terminator on the same host.

`SILO_PUBLIC_URL` is required here. `silo-server` derives from it the session cookie (`Secure` only
for `https://`) and HSTS (only for `https://`), and accepts state-changing requests only with an
`Origin` equal to it or to the served host, so it must match what users type, including the port.
Behind your own TLS terminator set `SILO_PUBLIC_URL=https://<domain>`; the terminator's address is
then the client address that `silo-server` logs and rate-limits, unless you configure Caddy's
`trusted_proxies` and `SILO_TRUSTED_PROXIES` for it.

### Variant `nginx` (an existing nginx, Portainer)

[`deploy/nginx/`](deploy/nginx/README.md): an overlay that attaches `silo-server` and `silo-web`
to the network of your nginx container, an nginx server block ([`silo.conf`](deploy/nginx/silo.conf),
the equivalent of the `Caddyfile`), the variables
([`deploy/nginx/.env.example`](deploy/nginx/.env.example)) and the steps for the certificate
(certbot webroot) and for a Portainer stack from this git repository.

Details (docker-mailserver on the same host, mode `local` and the first admin, upgrades, backups,
S3, fail2ban, OAuth2): [Running in production](#running-in-production).

## Quick start: development

```sh
mkdir silopost && cd silopost
git clone https://github.com/silopost/silo.git
git clone https://github.com/silopost/silo-server.git
git clone https://github.com/silopost/silo-web.git

cd silo
scripts/dev-up.sh
scripts/seed-mail.sh --all     # sample mail; run it before the first sign-in
```

The repositories must be siblings (`silopost/{silo,silo-server,silo-web}`): the dev Compose file
builds from `../silo-server` and `../silo-web`.

`scripts/dev-up.sh` checks the sibling repositories, creates `.env` from `.env.example` when it is
missing, runs `docker compose -f docker-compose.dev.yml up -d --build`, waits for the mail server,
creates the missing test mailboxes and prints the service addresses. It is idempotent. Pass a list
of services to start only some of them, for example `scripts/dev-up.sh postgres mailserver` (mail
server only, no build of `silo-server`/`silo-web`) or
`scripts/dev-up.sh postgres mailserver silo-server` (backend only).

```sh
curl localhost:8080/healthz     # silo-server -> {"status":"ok"}
# http://localhost:5173         # silo-web (Vite dev server with HMR)
```

Sign in at <http://localhost:5173> as `dev1@silo.test` / `devpass1`.

### Dev mail server and test mailboxes

The dev stack runs [docker-mailserver](https://github.com/docker-mailserver/docker-mailserver) 16
(Dovecot 2.4) **without TLS and without spam filters – for development only**. Its configuration is
in `dev/dms/config/` (`dovecot.cf` allows plaintext authentication without TLS).

| Mailbox | Password |
|---|---|
| `dev1@silo.test` | `devpass1` |
| `dev2@silo.test` | `devpass2` |
| `dev3@silo.test` | `devpass3` |

The password hashes are committed in `dev/dms/config/postfix-accounts.cf`, so start-up is
deterministic; `dev-up.sh` also creates missing mailboxes. These passwords are for development
only.

### Sample mail

`seed/mail/` holds over 60 fictional messages: threads, Sent items, out-of-order replies, HTML,
Base64/quoted-printable, ISO-8859-2 and Windows-1250 charsets, attachments, an inline image and a
message without `Message-ID`.

```sh
scripts/seed-mail.sh                              # SMTP: 54 messages to dev1@silo.test's INBOX
scripts/seed-mail.sh --append                     # IMAP APPEND: Sent (11) and 3 INBOX messages with flags and dates
scripts/seed-mail.sh --all --shuffle --delay 1    # both modes, random order, 1 s apart
scripts/seed-mail.sh --to dev2@silo.test          # another recipient
```

After `--all`, `dev1@silo.test` has 57 messages in INBOX and 11 in Sent. The script does not
detect duplicates; for a clean start run `docker compose -f docker-compose.dev.yml down -v`. The
corpus is generated by `node scripts/gen-seed.mjs` (the output is committed). `--append` to a
mailbox other than `devN@silo.test` needs `SILO_SEED_PASSWORD`; `SILO_COMPOSE_FILE` selects another
Compose stack.

### Connecting Thunderbird to the dev mail server

- Incoming: IMAP, host `localhost`, port `1143` (`SILO_DEV_IMAP_PORT`), no connection security,
  normal password.
- Outgoing: SMTP, host `localhost`, port `1587` (`SILO_DEV_SUBMISSION_PORT`), no encryption, the
  same password.
- Username: the full address, for example `dev1@silo.test`.

A second client is handy to watch Silo's changes on the server (tags, folders, Snoozed).

### Dev ports

| Service | Default host port | Variable in `.env` |
|---|---|---|
| Postgres | `5432` | `SILO_DEV_PG_PORT` |
| silo-server | `8080` | `SILO_DEV_SERVER_PORT` |
| silo-web (Vite) | `5173` | `SILO_DEV_WEB_PORT` |
| IMAP | `1143` | `SILO_DEV_IMAP_PORT` |
| SMTP (port 25 in the container) | `2525` | `SILO_DEV_SMTP_PORT` |
| SMTP submission | `1587` | `SILO_DEV_SUBMISSION_PORT` |

If a port is taken, change it in `.env` and run `scripts/dev-up.sh` again.

### Running silo-web or silo-mobile outside Compose

Backend in Compose, Vite on the host (faster HMR, especially on Windows):

```sh
scripts/dev-up.sh postgres mailserver silo-server
cd ../silo-web && npm ci
VITE_API_PROXY=http://localhost:8080 npm run dev     # the port is your SILO_DEV_SERVER_PORT
```

`silo-mobile` is not part of the Compose stack. Clone it next to the others and point the app at
the dev API:

```sh
git clone https://github.com/silopost/silo-mobile.git ../silo-mobile
scripts/dev-up.sh postgres mailserver silo-server
scripts/seed-mail.sh --all
cd ../silo-mobile && npm ci
npx expo start          # Expo Go on the phone: scan the QR code (no Android SDK needed)
npx expo run:android    # development build on an emulator/device (needs the Android SDK)
```

On the sign-in screen use `http://10.0.2.2:<SILO_DEV_SERVER_PORT>` in the Android emulator, or
your computer's LAN address on a phone (`localhost` is the phone itself). Cleartext HTTP works only
in Expo Go and debug builds. See the [silo-mobile README](https://github.com/silopost/silo-mobile#readme).

## Configuration

All configuration is environment variables. [`.env.example`](.env.example) is the template for
both stacks; copy it to `.env` (git ignores `.env`; `dev-up.sh` makes the copy for you).

- The **production** stack (`docker-compose.yml` with a variant) passes **every `SILO_*` variable from `.env`** to
  `silo-server` (`env_file`; another file: `SILO_ENV_FILE`), so any `silo-server` setting can be set
  in `.env`.
- The **dev** stack (`docker-compose.dev.yml`) does not read the instance variables from `.env`:
  the dev values are written in the Compose file. It reads only the dev ports and the sync engine
  variables below.

The complete list of `silo-server` variables, with defaults and validation rules, is in the
[silo-server README](https://github.com/silopost/silo-server#configuration).

### Production (`docker-compose.yml` and the variants)

| Variable | Default | Description |
|---|---|---|
| `COMPOSE_FILE` | – | Optional: the base and variant files (`docker-compose.yml:deploy/<variant>/docker-compose.yml`), so that plain `docker compose` commands use them. |
| `SILO_DOMAIN` | – (required by `caddy`) | Domain of the instance. Caddy obtains an ACME certificate for it (`localhost` gets an internal certificate). |
| `SILO_PUBLIC_URL` | `caddy`: `https://$SILO_DOMAIN`; `http`, `nginx`: – (required) | Public URL. Must match the address in the browser (Origin check, `Secure` cookie, OAuth2 redirect). With `caddy`, change it only for another port or path. |
| `SILO_SECRET_KEY` | – (required) | 32 random bytes, base64 (`openssl rand -base64 32`). Encrypts mailbox passwords, OAuth2 tokens and TOTP secrets. Keep a copy separate from backups. Empty stops start-up. |
| `SILO_POSTGRES_PASSWORD` | – (required) | Postgres password inside the Compose network, without characters that need URL encoding (`openssl rand -hex 24`). Empty stops start-up. |
| `SILO_SERVER_TAG` | `0.7.0` | Image tag of `ghcr.io/silopost/silo-server`. |
| `SILO_WEB_TAG` | `0.6.0` | Image tag of `ghcr.io/silopost/silo-web`. |
| `SILO_SERVER_IMAGE` / `SILO_WEB_IMAGE` | `ghcr.io/silopost/silo-server` / `ghcr.io/silopost/silo-web` | Image repositories, e.g. your own registry. |
| `SILO_HTTP_PORT` / `SILO_HTTPS_PORT` | `caddy`: `80` / `443`; `http`: `8080` / – | Host ports of Caddy (HTTPS also on UDP for HTTP/3). `127.0.0.1:8080` publishes on loopback only. |
| `SILO_NETWORK_SUBNET` | `172.29.250.0/24` | Fixed subnet of the Compose network (Caddy connects from it); change it on collision. |
| `SILO_TRUSTED_PROXIES` | `$SILO_NETWORK_SUBNET`; `nginx`: – (required) | Proxies whose `X-Forwarded-For` is trusted. Add a load balancer in front of Caddy here; with `nginx`, the subnet of `SILO_PROXY_NETWORK`. |
| `SILO_PROXY_NETWORK` | – (required by `nginx`) | Existing Docker network of the nginx container; `silo-server` and `silo-web` join it. |
| `SILO_ENV_FILE` | `.env` | File passed to `silo-server` as `env_file`. |
| `SILO_AUTH_MODE` | `imap` | `imap`: sign in with mailbox credentials of the default server. `local`: Silo users created by an admin. |
| `SILO_DEFAULT_IMAP_HOST` | – | Default IMAP server (required in mode `imap`). For docker-mailserver on the same host see [Running in production](#docker-mailserver-on-the-same-host). |
| `SILO_DEFAULT_IMAP_PORT` / `SILO_DEFAULT_IMAP_TLS` | `993` / `implicit` | Port and TLS mode (`implicit` or `starttls`). |
| `SILO_DEFAULT_SMTP_HOST` | `SILO_DEFAULT_IMAP_HOST` | Default SMTP submission server. |
| `SILO_DEFAULT_SMTP_PORT` / `SILO_DEFAULT_SMTP_TLS` | `587` / `starttls` | Port and TLS mode. |
| `SILO_DEFAULT_LOGIN_FORMAT` | `email` | `email` or `localpart` (then `SILO_DEFAULT_DOMAIN` is required). |
| `SILO_ALLOW_CUSTOM_SERVERS` | `false` | Mode `imap`: let users add mailboxes on other servers. Always allowed in mode `local`. |
| `SILO_CUSTOM_SERVER_ALLOWLIST` | empty | Private hosts, IPs or CIDRs that custom servers may resolve to (anti-SSRF exceptions). |
| `SILO_MAX_ACCOUNTS_PER_USER` | `5` | Mail accounts per Silo user. |
| `SILO_LOG_FORMAT` | `text` in `.env.example` (`json` in the server) | `text` is convenient for fail2ban on Docker logs. |
| `SILO_RATE_LIMIT_API` / `SILO_RATE_LIMIT_AUTH` | `600/m` / `20/m` | Per-IP rate limits for the API and for sign-in, password change and TOTP. |
| `SILO_HSTS` | `true` | HSTS on API responses over HTTPS. |
| `SILO_AUTOCONFIG_ISPDB_URL` | `https://autoconfig.thunderbird.net/v1.1/` | ISPDB for account autoconfiguration; `off` disables it. |
| `SILO_OAUTH_GOOGLE_CLIENT_ID` / `SILO_OAUTH_GOOGLE_CLIENT_SECRET` | empty | Enables "Sign in with Google" (set both). See the [OAuth2 guide](docs/admin/oauth.md). |
| `SILO_OAUTH_MICROSOFT_CLIENT_ID` / `SILO_OAUTH_MICROSOFT_CLIENT_SECRET` | empty | Enables "Sign in with Microsoft" (set both). |
| `SILO_OAUTH_MICROSOFT_TENANT` | `common` | `common`, `organizations`, `consumers` or a tenant id/domain. |

### Sync engine and limits

`docker-compose.dev.yml` passes these to the dev `silo-server`; in production set them in `.env`.
The values shown are the defaults.

| Variable | Default | Description |
|---|---|---|
| `SILO_SYNC_MAX_CONNECTIONS_PER_ACCOUNT` | `3` | IMAP connections per account (minimum 2: sync + IDLE; the third is for write-back). |
| `SILO_SYNC_INITIAL_CONCURRENCY` | `2` | Accounts doing their initial sync at the same time. |
| `SILO_SYNC_POLL_INTERVAL` | `5m` | Poll/STATUS sweep of folders. |
| `SILO_SYNC_BACKFILL_RATE` | `5MB/s` | Pace of the body backfill per account. |
| `SILO_MIRROR_MAX_MESSAGE_BYTES` | `50MB` | Larger messages keep headers only; bodies are fetched on demand. |
| `SILO_MIRROR_QUOTA_PER_ACCOUNT` | `0` | Stop the body backfill of an account at this many bytes (`0` = no limit). |
| `SILO_UNDO_WINDOW` | `10s` | Undo window of folder moves before they are written to the server. |
| `SILO_MAX_ATTACHMENT_BYTES` | `25MB` | Largest upload and outgoing message. |
| `SILO_SYNC_KEYWORD_FOLDER_LIMIT` | `26` | IMAP keywords per folder (Dovecot maildir: 26; `0` = no limit, for example sdbox/mdbox). |

### Blob storage

| Variable | Default | Description |
|---|---|---|
| `SILO_BLOB_BACKEND` | `fs` | `fs`: directory `SILO_BLOB_FS_DIR` (`/data/blobs`, volume `blobs`). `s3`: an S3/MinIO bucket that must already exist. |
| `SILO_BLOB_S3_ENDPOINT`, `SILO_BLOB_S3_BUCKET`, `SILO_BLOB_S3_ACCESS_KEY`, `SILO_BLOB_S3_SECRET_KEY` | – | Required with `s3`. |
| `SILO_BLOB_S3_REGION` / `SILO_BLOB_S3_PREFIX` | `us-east-1` / empty | Region and key prefix. |
| `SILO_BLOB_S3_USE_SSL` / `SILO_BLOB_S3_PATH_STYLE` | `true` / `true` | Path-style addressing suits MinIO; use `false` for AWS virtual-hosted style. |

### Dev stack, test stacks and scripts

| Variable | Default | Used by |
|---|---|---|
| `SILO_DEV_PG_PORT`, `SILO_DEV_SERVER_PORT`, `SILO_DEV_WEB_PORT`, `SILO_DEV_IMAP_PORT`, `SILO_DEV_SMTP_PORT`, `SILO_DEV_SUBMISSION_PORT` | see [Dev ports](#dev-ports) | `docker-compose.dev.yml`, scripts, silo-web e2e |
| `SILO_BT_PG_PORT`, `SILO_BT_SERVER_PORT`, `SILO_BT_IMAP_PORT`, `SILO_BT_SMTP_PORT`, `SILO_BT_SUBMISSION_PORT` | `15432`, `18080`, `11143`, `12525`, `11587` | `docker-compose.backup-test.yml` |
| `SILO_COMPOSE_FILE` | `COMPOSE_FILE` from `.env`, else `docker-compose.yml` (`seed-mail.sh`: `docker-compose.dev.yml`) | Compose file(s) used by `backup.sh`, `restore.sh` and `seed-mail.sh`; `backup.sh`/`restore.sh` take a `:`-separated list. `restore.sh full` recreates `silo-server` and needs the variant files. |
| `SILO_BACKUP_WAIT` | `60` | Seconds `backup.sh metadata` waits for pending write-back |
| `SILO_BLOBS_VOLUME` | detected | Blob volume for `backup.sh full` / `restore.sh full` |
| `SILO_TAR_IMAGE` | `alpine:3.22` | Image used to archive the blob volume |
| `SILO_SEED_PASSWORD` | – | Mailbox password for `seed-mail.sh --append` to a non-dev mailbox |
| `SILO_E2E_BASE`, `SILO_E2E_USER`, `SILO_E2E_PASSWORD` | `http://localhost:$SILO_DEV_SERVER_PORT`, `dev1@silo.test`, `devpass1` | `scripts/e2e-smoke.sh` |
| `SILO_E2E_LIST_MAX_MS`, `SILO_E2E_EVENT_MAX_MS`, `SILO_E2E_MIN_INBOX` | `10000`, `2000`, `0` | `scripts/e2e-smoke.sh` thresholds |
| `SILO_BT_TIMEOUT` | `180` | Wait timeout (seconds) of `scripts/e2e-backup-restore.sh` |

Test-only variables of `silo-server` (`SILO_REQUIRE_DOCKER`, `SILO_BENCH_*`, `SILO_SYNC_TEST_*`) are
described in the [silo-server README](https://github.com/silopost/silo-server#testing).

## Running in production

The [administrator guide](docs/admin/README.md) is the full reference. The essentials follow.

### The stack

The base [`docker-compose.yml`](docker-compose.yml) uses the Compose project `silo-prod`, so it never
shares volumes with the dev project `silo`. It defines the services every variant shares; each
variant overlay in `deploy/` adds only the proxy (see [Choose a variant](#choose-a-variant)):

| Service | Image | Notes |
|---|---|---|
| `postgres` | `postgres:17` | Volume `pgdata`, no host port. |
| `blobs-init` | `alpine:3.22` | One-shot `chown` of the `blobs` volume for the nonroot (65532) server image. |
| `silo-server` | `ghcr.io/silopost/silo-server:${SILO_SERVER_TAG}` | Distroless, nonroot, no host port; migrations at start-up under a Postgres advisory lock; `json-file` logs rotated at 10 MB × 5. |
| `silo-web` | `ghcr.io/silopost/silo-web:${SILO_WEB_TAG}` | Static build served by nginx inside the image; no `/api` proxy, no host port. |

| Variant file | Adds | Notes |
|---|---|---|
| [`deploy/caddy/docker-compose.yml`](deploy/caddy/docker-compose.yml) | `caddy` (`caddy:2.10`) on 80/443 (+ UDP 443 for HTTP/3), volumes `caddy-data`, `caddy-config` | TLS via ACME for `SILO_DOMAIN`. [`Caddyfile`](deploy/caddy/Caddyfile): `/api/v1/events` without buffering, `/api/*` and `/healthz` to `silo-server`, everything else to `silo-web`; security headers, CSP and HSTS for the SPA. |
| [`deploy/http/docker-compose.yml`](deploy/http/docker-compose.yml) | `caddy` on 8080 | The same `Caddyfile` with the site address `http://:8080`: no TLS and no HSTS. Requires `SILO_PUBLIC_URL`. |
| [`deploy/nginx/docker-compose.yml`](deploy/nginx/docker-compose.yml) | the external network `SILO_PROXY_NETWORK` for `silo-server` and `silo-web` | Your nginx proxies with [`silo.conf`](deploy/nginx/silo.conf). Requires `SILO_PUBLIC_URL` and `SILO_TRUSTED_PROXIES`. |

The images are published by the `release.yml` GitHub Actions workflow of `silo-server` and
`silo-web`: a `vX.Y.Z` tag publishes `:X.Y.Z`, `:X.Y` and `:latest` (amd64/arm64), and a push to
`main` publishes `:edge`. A new GHCR package has to be made public once (Package settings → Change
visibility), otherwise `docker pull` without signing in to `ghcr.io` fails.

To build the images from the sibling repositories instead of pulling them (before images are
published, or to test the production stack), add the build overlay after the variant file:

```sh
docker compose -f docker-compose.yml -f deploy/caddy/docker-compose.yml -f docker-compose.build.yml up -d --build
```

### docker-mailserver on the same host

Attach the mail server container to Silo's network with an alias equal to the name in its
certificate (so that TLS verifies) and use that name as `SILO_DEFAULT_IMAP_HOST` and
`SILO_DEFAULT_SMTP_HOST`. The network `silo-prod_default` is created by the first
`docker compose up` of Silo. In docker-mailserver's Compose file:

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

The default host is trusted (it bypasses the anti-SSRF filter), so a private address is fine. For
an external server use its public host name with 993/`implicit` and 587/`starttls` (or
465/`implicit`).

### Users and admins

- Mode `imap`: the first sign-in with mailbox credentials creates the user. Make someone an admin
  with `docker compose exec silo-server /silo-server user admin --email X --set=true`.
- Mode `local` (`SILO_AUTH_MODE=local`): an admin creates users; users add their mailboxes (any
  server, autoconfiguration, OAuth2) in the UI. `SILO_DEFAULT_IMAP_HOST` is optional.

```sh
docker compose exec silo-server /silo-server user add --email admin@example.com --admin   # prints a generated password once
echo 'a long password' | docker compose exec -T silo-server /silo-server user add --email ala@example.com --password-stdin
docker compose exec -T silo-server /silo-server user passwd --email ala@example.com       # new password from stdin
docker compose exec silo-server /silo-server user list
```

Users turn on TOTP in Settings → Security, and admins should. A lost device without backup codes:
Administration → Users → reset TOTP. Switching a running instance from `imap` to `local` has not
been tested; choose the mode at installation.

Prefer revocable credentials over main passwords: OAuth2 or an app password for Gmail, OAuth2 for
Microsoft 365 (Exchange Online has password authentication for IMAP/SMTP turned off), a separate
Dovecot `passdb` for your own server. Silo stores mailbox credentials reversibly (encrypted with
`SILO_SECRET_KEY`), see the [threat model](docs/threat-model.md).

### Upgrades

1. Read the release notes and the [compatibility matrix](docs/compat-matrix.md).
2. Back up: `scripts/backup.sh full` (and `metadata`).
3. Move to the new tag of this repository (`git pull && git checkout vX.Y.Z`; the defaults of
   `SILO_SERVER_TAG`/`SILO_WEB_TAG` follow it) or set the tags in `.env`.
4. `docker compose pull && docker compose up -d` (with `COMPOSE_FILE` or the `-f` files of your
   variant). Migrations run at start-up; check them with
   `docker compose exec silo-server /silo-server migrate version`. Coming from a version where
   Caddy was part of `docker-compose.yml` (the `Caddyfile` in the repository root): use the
   `caddy` variant (`COMPOSE_FILE=docker-compose.yml:deploy/caddy/docker-compose.yml`); its
   volumes keep their names, so the certificates stay.
5. `GET /api/v1/meta` reports `minWebVersion` (`0.3.0` for server 0.7.0); open tabs of an older
   silo-web ask the user to reload. Upgrade server and web together.
6. There is no automatic downgrade between releases: go back to the previous tags and run
   `scripts/restore.sh full` with the backup from step 2.

The upgrade path is tested in the `silo-server` CI (`scripts/upgrade-test.sh`); 0.4.0 → 0.5.0 passed
locally (schema 9 → 52, `reconcile` without drift).

### Backup and restore

Postgres holds a **cache** of the mail (rebuilt from IMAP by the sync) and **metadata** that exists
only in Silo. The mail itself lives on the IMAP server and is backed up there.

```sh
scripts/backup.sh metadata --out backups/        # default mode; --user EMAIL for one user
scripts/backup.sh full --out backups/            # pg_dump -Fc of the database + tar.gz of the blob volume
scripts/restore.sh metadata backups/silo-metadata-<ts>.json [--merge]
scripts/restore.sh full backups/silo-db-<ts>.dump [backups/silo-blobs-<ts>.tar.gz] [--yes]
```

Run `metadata` daily and `full` weekly or before upgrades; every file gets a `.sha256`. Restore
with the **same** `SILO_SECRET_KEY`. In mode `imap`, do not sign in before importing a metadata
backup. The S3 bucket, `.env` and a changed `deploy/caddy/Caddyfile` or nginx `silo.conf` are not part of the backup. Full procedure, a cron
example and the limits: [docs/admin/backup.md](docs/admin/backup.md).

### S3, hardening, OAuth2

- **S3Store**: set `SILO_BLOB_BACKEND=s3` and `SILO_BLOB_S3_*`; the bucket must exist. A `full`
  backup does not include the bucket. Moving existing blobs from `fs` to `s3` is a manual copy
  ([admin guide](docs/admin/README.md#s3store)).
- **Hardening**: set `SILO_TRUSTED_PROXIES` correctly (check that `ip=` in the `security event`
  log lines shows client addresses), never enable `SILO_ALLOW_INSECURE_TRANSPORT`, consider
  `SILO_ALLOW_CUSTOM_SERVERS=false` in mode `imap`, keep Postgres without a host port, and encrypt
  disks and backups. A fail2ban filter and jail for the Docker `json-file` log are in the
  [admin guide](docs/admin/README.md#hardening).
- **OAuth2** for Gmail and Microsoft 365: register an application with Google and in Microsoft
  Entra, set `SILO_OAUTH_*`, and register the redirect URI
  `SILO_PUBLIC_URL/api/v1/oauth/{google|microsoft}/callback`. Step by step:
  [docs/admin/oauth.md](docs/admin/oauth.md).

## Development

### Compose files

| File | Purpose |
|---|---|
| [`docker-compose.yml`](docker-compose.yml) | Production base (project `silo-prod`): Postgres 17, `silo-server` and `silo-web` from published images; no proxy, no host ports. |
| [`deploy/caddy/docker-compose.yml`](deploy/caddy/docker-compose.yml) | Production variant `caddy`: Caddy with TLS (ACME) on 80/443, [`deploy/caddy/Caddyfile`](deploy/caddy/Caddyfile). |
| [`deploy/http/docker-compose.yml`](deploy/http/docker-compose.yml) | Production variant `http`: the same Caddy on 8080 without TLS. |
| [`deploy/nginx/docker-compose.yml`](deploy/nginx/docker-compose.yml) | Production variant `nginx`: joins an existing nginx network ([`deploy/nginx/README.md`](deploy/nginx/README.md)). |
| [`docker-compose.build.yml`](docker-compose.build.yml) | Overlay for the production stack (after any variant file): builds `silo-server` (target `prod`) and `silo-web` from the sibling repositories. |
| [`docker-compose.dev.yml`](docker-compose.dev.yml) | Dev stack (project `silo`): Postgres, docker-mailserver, `silo-server` with hot reload (air), `silo-web` on Vite with polling file watching. |
| [`docker-compose.backup-test.yml`](docker-compose.backup-test.yml) | Separate stack (project `silo-bt`, ports `SILO_BT_*`) with the production `silo-server` image and its own mail server, for the backup/restore test and some silo-web e2e runs. |
| [`docker-compose.local-auth.yml`](docker-compose.local-auth.yml) | Overlay for the `silo-bt` stack: `silo-server` in mode `local` (silo-web `local-auth` e2e). |

The dev `silo-server` uses a fixed, development-only `SILO_SECRET_KEY`, plaintext IMAP/SMTP to the
dev mail server (`SILO_ALLOW_INSECURE_TRANSPORT=true`) and `SILO_PUBLIC_URL=http://localhost:5173`.
Never reuse these settings in production.

### Working on the applications

Each application repository documents its own workflow:

- [silo-server](https://github.com/silopost/silo-server#development): Go, `make run`, sqlc,
  OpenAPI generation, integration tests with testcontainers.
- [silo-web](https://github.com/silopost/silo-web#development): `npm run dev`, vitest, Playwright.
- [silo-mobile](https://github.com/silopost/silo-mobile#development): Expo, jest, `expo export`.

## Testing

### API smoke test

`scripts/e2e-smoke.sh` checks two latency targets on a running dev stack:

- sign-in of `dev1@silo.test` (`POST /api/v1/session`) to a non-empty INBOX list
  (`GET /api/v1/threads?labelId=INBOX`) in **under 10 s** (initial sync);
- a message sent with `swaks` (inside the `mailserver` container) to `dev1@silo.test` appears in the
  SSE stream (`GET /api/v1/events`) as `message.new` in **under 2 s** (measured from the end of
  `swaks`; the script also prints the time from the start of the command, which includes about 1 s
  of `docker compose exec` overhead on Windows).

```sh
scripts/dev-up.sh postgres mailserver silo-server
scripts/seed-mail.sh              # before the first sign-in: the Silo account is created at sign-in
scripts/e2e-smoke.sh              # exit 0 = targets met, 1 = exceeded or error, 2 = server not running
```

It needs only `curl` and `docker compose` (no `jq`). The address comes from `SILO_DEV_SERVER_PORT`
in `.env` (override: `SILO_E2E_BASE`), the targets from `SILO_E2E_LIST_MAX_MS` and
`SILO_E2E_EVENT_MAX_MS`. Measuring the initial sync needs a fresh database:
`docker compose -f docker-compose.dev.yml rm -sf silo-server postgres && docker volume rm silo_pgdata`.

### Backup and restore test

`scripts/e2e-backup-restore.sh` runs end to end on the separate `silo-bt` stack (the dev stack is
not touched): seed mail, initial sync, a user label on 2 threads, archive, a draft with an
attachment, a message scheduled an hour ahead, a snoozed thread, a filter with a label, an INBOX
snapshot, `backup.sh metadata`, removal of the containers and of the `pgdata` and `blobs` volumes
(the mail server volume stays, like an external IMAP server), `restore.sh metadata` into an empty
database, a new sign-in and a comparison of everything above.

```sh
scripts/e2e-backup-restore.sh          # exit 0 = PASS, 1 = FAIL; ends with down -v of silo-bt
scripts/e2e-backup-restore.sh --keep   # keeps the silo-bt stack for inspection
```

### Web end-to-end tests

The user-facing behaviour (UI, sending, undo, drafts, offline, accessibility, search, snooze,
scheduled send, filters, labels as keywords, settings, shortcuts, multiple accounts, mode `local`,
PWA) is covered by the Playwright suite of silo-web (`npm run e2e`;
`npm run e2e -- --grep-invert @slow` skips the tests that wait 2–4 minutes). See the
[silo-web README](https://github.com/silopost/silo-web#end-to-end-tests).

### CI of this repository

`.github/workflows/ci.yml` validates the Compose files (`docker compose config`, the production
base with each variant) and the `Caddyfile` for both site addresses (`caddy validate`), lints YAML and Markdown (`.markdownlint.yaml`) and runs shellcheck
on `scripts/`.

## Project structure

```text
silo/
├── docker-compose*.yml           # production base, build overlay, dev, backup-test, local-auth
├── deploy/                       # production variants (overlays for docker-compose.yml)
│   ├── caddy/                    # Caddy with TLS on 80/443; Caddyfile shared with http/
│   ├── http/                     # the same Caddy, plain HTTP on 8080
│   └── nginx/                    # behind an existing nginx (silo.conf, Portainer)
├── .env.example                  # configuration template (copy to .env)
├── dev/dms/config/               # dev docker-mailserver configuration and test mailboxes
├── seed/mail/                    # sample messages (.eml) for the dev mail server
├── scripts/
│   ├── dev-up.sh                 # start the dev stack
│   ├── seed-mail.sh              # load sample mail (SMTP and IMAP APPEND)
│   ├── gen-seed.mjs              # generate seed/mail/
│   ├── backup.sh, restore.sh     # metadata and full backup/restore
│   ├── e2e-smoke.sh              # API latency smoke test
│   └── e2e-backup-restore.sh     # backup/restore end-to-end test
└── docs/
    ├── adr/                      # architecture decision records
    ├── admin/                    # administrator guide, backup, OAuth2
    ├── compat-matrix.md          # version and mail server compatibility
    └── threat-model.md
```

## Status and roadmap

Silopost is pre-1.0. The scope planned for 1.0 is implemented (`silo` 0.5.0 with `silo-server`
0.5.0 and `silo-web` 0.4.0). The API may still change before 1.0; every change is recorded in the
[compatibility matrix](docs/compat-matrix.md).

**Verified** (Windows 11 + Docker Desktop, docker-mailserver 16, November 2026):

- Sign-in to a listed INBOX in 2.0 s on a fresh database (54 messages); `message.new` over SSE in
  about 0.5 s.
- Initial sync of a 200,000-message mailbox in 99 min without errors, peak RSS 77 MiB (target
  512 MB).
- Backup/restore test: PASS (identical INBOX of 38 threads, labels, a draft with an attachment, a
  scheduled message, a snooze with the same wake time, a filter).
- Upgrade 0.4.0 → 0.5.0 with filters and snoozes: PASS.
- silo-web e2e: archive and undo (row gone from the DOM in about 20 ms), undo send, drafts in the
  server's Drafts folder, mail server going offline, a 5000-thread list, axe (WCAG 2.2 AA) without
  violations, search, snooze, scheduled send (delivered within ±30 s), filters, keywords, settings,
  shortcuts, multiple accounts, mode `local` with TOTP, PWA offline reload.
- The production stack built from source (`docker-compose.build.yml`): `/healthz`, `/api/v1/meta`
  and the SPA through Caddy with TLS, headers and CSP without violations.
- The production variants with the published images (server 0.7.0, web 0.6.0): `caddy` with
  `SILO_DOMAIN=localhost` (HTTPS, HSTS on the SPA) and `http` (`/healthz`, `/api/v1/meta`, the SPA
  without HSTS, sign-in with a session cookie without `Secure`, a foreign `Origin` rejected with
  403); `nginx`: both services reachable by name from the proxy network, Postgres not.

**Known limitations and unverified areas**:

- **Gmail and Microsoft 365 (OAuth2/XOAUTH2) have not been tested against live accounts** – only
  against a fake provider and Dovecot with `AUTH=XOAUTH2`. The manual test steps are in the
  [compatibility matrix](docs/compat-matrix.md#oauth2-and-xoauth2-phase-5).
- Gmail accounts sync in generic IMAP mode: Gmail labels other than the special folders are not
  mapped to Silo labels, and threads are built by Silo, not by Gmail.
- Not verified: migrating blobs from `fs` to `s3`, fail2ban on a live host.
- Filters run in Silo (on new INBOX mail while Silo runs); they are not exported as Sieve scripts.
- No folder role mapping in the UI yet (the API `PUT /accounts/{id}/folders` exists; roles are
  detected from SPECIAL-USE and folder names). No bounce/DSN handling, no PDF thumbnails or viewer.
- **silo-mobile 0.1.0 is unreleased and has never been run on a device or an emulator.** It is
  verified by typecheck, lint, 405 tests (jest-expo + msw), an Android Hermes bundle
  (`expo export`, 8.4 MB) and a read-only API smoke test (14/14). Gestures, the editor keyboard,
  WebView and pickers still need checking on a device; iOS is not checked at all. Its UI is in
  Polish only for now.

**Next (1.1)**: Gmail mode with `X-GM-LABELS`/`X-GM-MSGID`/`X-GM-THRID`, ManageSieve, OAuth2 for
native clients, a delta API for offline clients (`GET /changes`, `ETag` on lists), and for
silo-mobile push notifications, an offline cache and signed APK/AAB builds (F-Droid).

## Documentation

- [docs/admin/](docs/admin/README.md) – administrator guide: production installation, mode `local`,
  app passwords, upgrades, [backup](docs/admin/backup.md), S3, hardening, [OAuth2](docs/admin/oauth.md)
- [docs/adr/](docs/adr/README.md) – architecture decision records
- [docs/compat-matrix.md](docs/compat-matrix.md) – compatibility of versions and mail servers
- [docs/threat-model.md](docs/threat-model.md) – threat model

## Contributing

Contributions are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) describes the conventions and the
workflow shared by all four repositories: Conventional Commits, focused pull requests with green
CI, versioning rules and ADRs for architectural decisions. Before opening a pull request, run the
tests and linters of the repository you changed (each README lists them).

## License

This repository is licensed under the [MIT License](LICENSE). `silo-server`, `silo-web` and
`silo-mobile` are licensed under the GNU Affero General Public License v3.0.

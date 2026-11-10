# Silo threat model

State: `silo-server` 0.5.0, `silo-web` 0.4.0 (phase 5). Details of the mechanisms: the `silo-server` README (sections "Hardening", "OAuth2", "Users, mode `local`", "Backup and restore"); operational recommendations: [docs/admin](admin/README.md).

## Scope and assumptions

Silo is a mail client running on a server: it signs in to IMAP/SMTP mailboxes **in the background** (IDLE, sync, scheduled sending), keeps a mirror of the mail in Postgres and exposes it to the browser (`silo-web`) and the `silo-mobile` app through `/api/v1`. We assume:

- a single `silo-server` instance behind a reverse proxy with TLS (the `caddy` or `nginx` production variant; the plain-HTTP `http` variant only on a trusted network); Postgres and the blobs are not reachable from the internet;
- the mail server is external and trusted with respect to its user's mailbox content, but **message content is hostile** (anyone can send arbitrary HTML);
- the instance administrator is trusted (has access to the database and the key); users of the instance do not trust each other.

## Assets

| Asset | Where | Protection |
|---|---|---|
| IMAP/SMTP passwords and OAuth2 refresh tokens | `accounts.secret_enc` | AES-256-GCM with the `SILO_SECRET_KEY` key, format `v1:<key_id>:<nonce>:<ciphertext>`, AAD = account id (a ciphertext cannot be moved to another row); rotation with `rotate-secrets` |
| TOTP secrets and backup codes | `users.totp_secret_enc`, `users.totp_backup_codes` | the secret as above (AAD = user id); backup codes only as `sha256`, single-use |
| Silo passwords (mode `local`) and the offline verifier (mode `imap`) | `users.password_hash` | argon2id |
| The mail mirror | `messages`, `body_text`, blobs (`fs`/`s3`) | **plaintext** in the database and the blob store – disk/backup encryption is up to the admin |
| Sessions | `sessions` | a random 256-bit token; only its `sha256` in the database; cookie `HttpOnly; Secure; SameSite=Lax`, or a bearer token in Keychain/Keystore |
| The `SILO_SECRET_KEY` key | env / secret file | never in the database, in logs or in backups |
| Metadata (labels, filters, drafts, settings) | Postgres | `metadata` backup ([ADR 0014](adr/0014-metadata-backup-format.md)) |

## Actors

- **An anonymous attacker on the internet** – guesses passwords, sends crafted requests, links and pages (CSRF), scans.
- **The sender of a malicious message** – controls HTML, attachments, headers, remote images.
- **A signed-in user of the instance** – tries to read another user's data or to use Silo to attack the internal network (SSRF).
- **An attacker with access to a copy of the database or a backup** (a leaked dump, disk, bucket).
- **An attacker with a compromised host** (database + env with the key).
- **An attacker on the network** between Silo and the mail server or the OAuth provider (MITM).

## Threats and mitigations

| Threat | Impact | Mitigation (mechanism) |
|---|---|---|
| Leak of a DB dump or backup without the key | no secrets in plaintext; **mail content in plaintext** | secrets with AES-GCM and AAD; the key outside the database and backups (`backup.sh` does not store it); disk and backup encryption – the admin's job; at-rest encryption of the mirror out of scope (below) |
| Leak of the DB + `SILO_SECRET_KEY` (host compromise) | access to all mailboxes | **app passwords** instead of main passwords, OAuth2 ([ADR 0013](adr/0013-oauth2-xoauth2.md)) – tokens revocable at the provider, no main password; key rotation (`SILO_SECRET_KEY_PREVIOUS` + `rotate-secrets`) after an incident, change of mailbox passwords |
| Sign-in brute force; Silo as an oracle for guessing mail server passwords | account takeover | token bucket per IP (`SILO_RATE_LIMIT_AUTH`, default `20/m`) and per login, a constant minimum response time, always `401 invalid_credentials`; in mode `local` an unknown/disabled user is verified against a dummy argon2id hash ([ADR 0011](adr/0011-local-auth-mode-and-totp.md)); seclog `event=auth_failed` → fail2ban |
| An intercepted or guessed TOTP code | bypassing the second factor | anti-replay (`totp_last_step`), a ±1-step window, the `SILO_RATE_LIMIT_AUTH` limit, seclog `totp_failed`; `401 totp_required` only after a correct password; re-authentication (password change, disabling TOTP, new codes) requires the password and a code (`403`) |
| Session theft | access to the user's mail | cookie `HttpOnly; Secure; SameSite=Lax`, the token's `sha256` in the database; expiry 30/90 days (bearer 90/365); session list, `DELETE /sessions/{id}` and `DELETE /sessions?others=true`; a password change and disabling the user end sessions; an open SSE stream receives `session.expired` and is closed (checked on every heartbeat) |
| CSRF against the API | actions on the user's behalf | `SameSite=Lax` + the `X-Silo-CSRF` header for mutations + `Origin` equal to `SILO_PUBLIC_URL`; the browser does not attach a bearer token; seclog `csrf_rejected` |
| OAuth login CSRF (the victim completes an authorization started by the attacker, or vice versa) | someone else's mailbox attached to the attacker's account | single-use state in `oauth_states` (10 min) **and** the `silo_oauth_state` cookie binding start and callback to the same browser; PKCE S256; re-authorization requires the same address (`oauth_account_mismatch`) |
| XSS through message content | session theft, actions in Silo | an HTML sanitizer on the server + DOMPurify in the client; a `sandbox` iframe without `allow-scripts`, content through `srcdoc` with its own CSP (`script-src 'none'`); the application CSP from the Caddyfile (`script-src 'self'`); `GET /messages/{id}/html` with CSP `default-src 'none'` and `frame-ancestors` limited to the Silo origin; attachments with `CSP: sandbox` and `nosniff` |
| Tracking through remote images | disclosure of the IP and the read time | remote images blocked by default in `silo-web` (a "Show images" button); `Referrer-Policy: no-referrer`; an image proxy is out of scope (below) |
| Clickjacking | forced clicks | `X-Frame-Options: DENY`, `frame-ancestors 'none'` (API and SPA) |
| SSRF through an account on an arbitrary host, autoconfiguration or DNS rebinding | scanning and attacks on the internal network | `SILO_ALLOW_CUSTOM_SERVERS=false` by default in mode `imap`; `internal/netx`: the host is resolved by Silo, and the connection goes **to the filtered address** (IMAP, SMTP, account test, autoconfiguration, ISPDB) – private/loopback/link-local addresses rejected, exceptions only from `SILO_CUSTOM_SERVER_ALLOWLIST`; autoconfiguration: redirects only `https` to the same host (≤ 3), response ≤ 256 kB, limit of 10/min per user |
| Reading another user's data (IDOR) | mail leak | every query scoped to the session's user; someone else's ID in the path → `404` like a non-existent one, in the body → `400`/`422` like an unknown one; SSE events and polling only for own data; the `TestUserIsolation` test (every endpoint in both directions, SSE, `Last-Event-ID`) |
| Escalation to admin | instance takeover | `/admin/*` → `403` for non-admins (seclog `forbidden`); an admin cannot demote or disable themselves; rights granted only by an admin or the CLI on the host |
| TLS downgrade / MITM towards the mail server or the OAuth provider | interception of passwords and tokens | TLS with certificate verification by default; `TLS=none` and unverified certificates only with `SILO_ALLOW_INSECURE_TRANSPORT` (dev); OAuth providers only over `https`; HSTS for the browser |
| Spoofing the client IP (`X-Forwarded-For`) | bypassing limits, fake logs | headers honored only from the addresses in `SILO_TRUSTED_PROXIES`; client = the rightmost address outside the trusted ones |
| DoS: request floods, many SSE streams, large uploads | unavailability | `SILO_RATE_LIMIT_API` (`600/m` per IP, `429 rate_limited` + `Retry-After`), max. 8 SSE streams per user (`stream.limit`), `SILO_MAX_ATTACHMENT_BYTES`, mirror size limits (`SILO_MIRROR_*`) and limits on the number of accounts |
| Secrets leaking into logs | account takeover | passwords and tokens are never logged; the login in the seclog is masked (`j***@example.com`); jobs in the admin panel without `payload` |
| Loss of the `SILO_SECRET_KEY` key | no access to mailboxes after a failure | the key stored separately from the database backup (two different places); without it a metadata import is useless – users must enter their mailbox passwords again |
| Revoked OAuth access / changed mailbox password | sync stops | the `auth_failed` state + `account.error`, no retries (does not lock the account at the provider), re-authorization by the user |

## Deliberately out of scope

- **At-rest encryption of the mail mirror** (blobs, `body_text`) – a postponed decision: a key derived from the user's password would make background sync impossible. Disk and backup encryption is recommended.
- **A remote image proxy** – a postponed decision (a server-side SSRF risk); today images are blocked in the client.
- Protection against a malicious instance administrator or host (they have the database and the key).
- Multiple `silo-server` instances (limits are kept in process memory – a postponed decision).
- Anti-spam, anti-virus, SPF/DKIM/DMARC – tasks of the mail server.
- WebAuthn and an external IdP (OIDC) – [ADR 0011](adr/0011-local-auth-mode-and-totp.md), postponed.
- OAuth2 for native clients – phase 6 ([ADR 0013](adr/0013-oauth2-xoauth2.md)).

## Recommendations for the administrator

- **App passwords** for mailboxes (a separate, revocable IMAP/SMTP password for Silo); Gmail and Microsoft 365 – OAuth2 ([admin/oauth.md](admin/oauth.md)) instead of the main password.
- **TLS everywhere:** Silo only behind HTTPS (`SILO_PUBLIC_URL=https://…`, HSTS); to the mail server `implicit`/`starttls` with a valid certificate; never `SILO_ALLOW_INSECURE_TRANSPORT` in production.
- **The key separately from the database:** `SILO_SECRET_KEY` in a secrets manager or in a separate copy; the database backup and the key in different places; after a leak – rotate the key and change the mailbox passwords.
- `SILO_TRUSTED_PROXIES` set to the proxy network, fail2ban on the seclog, `SILO_ALLOW_CUSTOM_SERVERS=false` if users do not need other servers.
- Encryption of the host disk, the volumes and the backups; Postgres and the S3 bucket not reachable from the internet.
- TOTP for administrator accounts in mode `local`.

Instructions: [docs/admin/README.md](admin/README.md) (sections ["Production installation"](admin/README.md#production-installation), ["App passwords"](admin/README.md#app-passwords), ["Hardening"](admin/README.md#hardening)).

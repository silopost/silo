# 0011. Mode `local` with a Silo password and built-in TOTP

- **Status:** Accepted
- **Date:** 2026-11-06
- **Applies to:** silo-server, silo-web

## Context

Mode `imap` signs users in with their mailbox credentials on the default server – convenient for a "one mail server" instance, but useless when users have mailboxes with different providers (Gmail through OAuth2, Microsoft 365, hosting). Phase 5 needs Silo users independent of mailboxes, created by an administrator, with a second factor and an admin panel. At the same time Silo must not become an oracle for guessing which accounts exist, nor accept a replayed one-time code.

## Decision

`SILO_AUTH_MODE=local`: Silo users with their own password (argon2id), created by an administrator (`silo-server user add`, `POST /admin/users`); no self-registration. The second factor is **TOTP (RFC 6238) implemented in Silo** (`internal/totp`, SHA1, 30 s, 6 digits, ±1 step).

- **Constant sign-in time:** an unknown user, a disabled user and a wrong password are verified against a constant dummy argon2id hash, with the same minimum response time; always `401 invalid_credentials`.
- **Factor order:** `401 totp_required` only after a correct password (without a code); a wrong code → `401 invalid_credentials`. The client sends `POST /session` again with `totpCode`.
- **The TOTP secret** is encrypted with AES-256-GCM using `SILO_SECRET_KEY` (AAD = `users.id`) and is covered by `rotate-secrets`. **Anti-replay:** `users.totp_last_step` – a code from an already used time step is rejected. **Backup codes:** 10 one-time codes, only their `sha256` in the database.
- **Re-authentication** of a signed-in user (password change, disabling TOTP, new backup codes) with a wrong password or code → `403 invalid_credentials` (the client treats 401 as "signed out").
- **Disabling a user by an admin:** sessions stop working immediately (including the SSE stream – `session.expired`), accounts switch to `sync_state='disabled'` (sync stops), and re-enabling resumes connections. An admin cannot disable, demote or delete themselves (`409 admin_self_change`).
- In mode `local` users add mailboxes themselves (`POST /accounts`, autoconfiguration, OAuth2); a host other than the default one always goes through the anti-SSRF validation (`internal/netx`).

## Consequences

- An instance serves mailboxes with many providers; the admin panel (users, account states, `dead` jobs) works in both modes.
- No dependency on an external TOTP library or an external IdP; the cost is our own cryptographic code (checked against the RFC 6238 test vectors).
- A lost device without backup codes requires an admin (`POST /admin/users/{id}/totp/reset`).
- A code intercepted within the same time step is useless after its first use; online attacks are limited by the rate limit (`SILO_RATE_LIMIT_AUTH`, seclog `totp_failed` for fail2ban).
- In mode `imap` the `/totp/*` and `/session/password` endpoints answer `409 not_available`.

## Alternatives

- **OIDC / an external IdP (Keycloak, Authentik):** natural for organizations, but requires an additional service that a small instance does not have; postponed (possible as a third mode).
- **WebAuthn / passkeys:** stronger than TOTP, but requires device registration, a separate flow for `silo-mobile` and HTTPS on every test instance; postponed to 1.x.
- **The `pquerna/otp` library:** ready-made, but does not solve anti-replay or backup codes (state on the application side) – little gain compared to ~100 lines of code with test vectors.
- **TOTP in mode `imap` too:** the password is verified by the mail server anyway; a Silo second factor does not protect the mailbox from other IMAP clients. Rejected.

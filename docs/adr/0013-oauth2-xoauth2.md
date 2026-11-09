# 0013. OAuth2 (authorization code + PKCE) and XOAUTH2 for Gmail and Microsoft 365

- **Status:** Accepted
- **Date:** 2026-11-06
- **Applies to:** silo-server, silo-web, silo-mobile

## Context

Exchange Online has password authentication for IMAP/SMTP turned off, and Gmail requires an app password (available only with 2FA). Silo signs in to mailboxes in the background (IDLE, scheduled sending), so it needs a revocable credential that it can refresh without the user; mailbox secrets are stored encrypted with `SILO_SECRET_KEY`. Silo is a web application with a client secret on the server side; every instance registers its own OAuth application with the provider.

## Decision

- **The authorization code flow with PKCE (S256)**, `golang.org/x/oauth2`: `POST /oauth/{provider}/start` (signed in) → the provider's page → `GET /oauth/{provider}/callback` → `303` to `SILO_PUBLIC_URL + returnTo?oauth=ok|error&code=…`. The state (32 random bytes, the PKCE verifier, the user, `returnTo`) is kept in the `oauth_states` table for 10 minutes and is single-use.
- **The `silo_oauth_state` cookie** (HttpOnly, SameSite=Lax, path `/api/v1/oauth/`) binds start and callback to the same browser – protection against OAuth login CSRF (a consent page link sent by an attacker will not attach someone else's mailbox to the attacker's user).
- **The refresh token** is encrypted like a mailbox password (`accounts.secret_enc`, AES-256-GCM, AAD = account id, `rotate-secrets`). The access token is kept in memory and refreshed before connecting when it expires within 60 s; a rotated refresh token is stored again. `invalid_grant` → account `auth_failed` + `account.error`; re-authorization through `start` with `accountId` (a `login_hint`, and the address must match).
- **XOAUTH2** for IMAP (`AUTHENTICATE XOAUTH2`) and SMTP (`AUTH XOAUTH2`); `Account.authType` = `password | xoauth2`; an OAuth account has no password (`PATCH` of the password → `409 not_available`).
- **Microsoft:** the refresh request includes `scope` (our own request, because `x/oauth2` omits it); IMAP `outlook.office365.com:993`, SMTP `smtp.office365.com:587` STARTTLS. **Google:** `access_type=offline`, `prompt=consent`; IMAP 993, SMTP 465 implicit TLS.
- `sent_append=false` for Google and Microsoft – both store sent mail in Sent themselves, so Silo does not APPEND its own copy.
- **Gmail works in generic mode** (folders, `\All` with deduplication, archive = removing the copy from INBOX). **Mode `provider=gmail`** (`X-GM-LABELS`, `X-GM-MSGID`, `X-GM-THRID`, syncing only All Mail/Trash/Spam) is **postponed to 1.1**: there is no test account and no X-GM simulator (Dovecot does not emulate `X-GM-EXT-1`), and generic mode covers reading, archiving and sending.

## Consequences

- Gmail and Microsoft 365 accounts without passwords, revocable on the provider's side; Silo does not store the main password.
- The administrator must register an application and (for Google, the restricted scope `https://mail.google.com/`) go through verification; Google's *Testing* mode expires refresh tokens after 7 days. Instructions: [docs/admin/oauth.md](../admin/oauth.md).
- **A native client** (bearer, external browser) has no `silo_oauth_state` cookie and gets `oauth_state_invalid`. `silo-mobile` needs a variant with the app's `redirectUri` (deep link) and a different state binding – phase 6.
- Without mode `provider=gmail`, Gmail labels (other than the special folders) are not Silo labels, and threads are built by Silo's JWZ (they may differ from Gmail's); part of the phase 5 definition of done for Gmail moves to 1.1.
- Live providers are not tested in CI: XOAUTH2 is checked with Dovecot using `passdb oauth2` (RFC 7662 introspection at a fake provider) and the `gmail-like` profile; the manual test steps are in the [compatibility matrix](../compat-matrix.md#2-imapsmtp-mail-servers).

## Alternatives

- **App passwords instead of OAuth2:** still supported (an account with a password), but unavailable in Exchange Online and increasingly rare in Google Workspace. Not sufficient.
- **Binding the state only to the Silo session (no cookie):** lets native clients use the same flow, but leaves login CSRF open (the callback does not require a session – it comes from the victim's browser). Rejected for 1.0.
- **Implicit flow / a public client without a secret:** tokens in the browser, no refresh token for background work. Rejected.
- **The Gmail API (REST) instead of IMAP:** native labels and threads, but a second sync engine next to IMAP (contrary to [ADR 0005](0005-imap-source-of-truth.md)). Rejected.

# 0007. Opaque bearer tokens for native clients

- **Status:** Accepted
- **Date:** 2026-11-05
- **Applies to:** silo-server, silo, future silo-mobile

## Context

A dedicated native mobile app (a separate repository, e.g. `silo-mobile`) will connect to `silo-server`, with parity of mail operations with silo-web and the Gmail phone app; it is one more client of the same `/api/v1`. Until now the only authentication was the browser session: the `silo_session` cookie (HttpOnly, SameSite=Lax) + the `X-Silo-CSRF` header + an `Origin` check. A native client has no browser cookie jar and no `Origin`, and a 30/90-day lifetime means signing in again too often on a phone. JWT was excluded from the start; the security rules (only a hash of the token in the database, session revocation, "sign out everywhere") must apply to mobile too.

## Decision

A second, equivalent authentication channel: an **opaque bearer token** in the `Authorization: Bearer <token>` header, in the same `sessions` table as cookie sessions.

- **Token:** the same random 256-bit token as for the cookie; only its `sha256` is stored in the database (`sessions.token_hash`). No JWT, no signatures, no refresh tokens.
- **Session kind:** the column `sessions.kind` (`cookie` | `bearer`, default `cookie`) and `sessions.client_name` (device name). A token is accepted **only in the channel it was issued for**: a cookie token in the `Authorization` header → 401, and vice versa.
- **Sign-in:** the same `POST /api/v1/session` with an optional `client` field:
  `{"email","password","client":{"kind":"bearer","name":"Pixel 8"}}`. For `bearer` the response (`SessionBody`) contains `token` (shown once), without `Set-Cookie`. Without the `client` field (or with `kind: "cookie"`) the behavior is unchanged. We chose one endpoint instead of a separate one, because all the sign-in logic (IMAP LOGIN, offline verifier, limits, constant response time, account creation) is shared, and only the way the token is handed over differs.
- **CSRF:** requests authenticated with a bearer token do not require `X-Silo-CSRF` or an `Origin` check: a browser never attaches the `Authorization` header on its own (a CSRF attack rides on ambient credentials, i.e. cookies). When an `Authorization: Bearer` header is present, it **alone** authenticates (the cookie is ignored), so CSRF cannot be bypassed for cookie sessions. Other schemes (`Basic` from a reverse proxy) are ignored.
- **Lifetime:** bearer: sliding 90 days, absolute 365 days (cookie unchanged: 30/90). Constants in code (`internal/auth`), no new env variables – as for cookies; we will add env variables when there is a real need.
- **Management:** `GET /sessions` returns `kind` and `clientName`; `DELETE /sessions/{id}` and `DELETE /session` work for both kinds ("sign out everywhere" covers mobile devices).
- **Streams and files:** `GET /events`, `/events/poll`, message content and attachments are regular operations protected by the same middleware, so they work with a bearer token. A token in the query string is **not** allowed (logs, history, the `Referer` header); a native client sets headers itself, and the browser uses the cookie.
- **OpenAPI:** a second security scheme `bearerAuth` (`type: http, scheme: bearer`) as an alternative to `cookieAuth` (+ `csrfHeader` on mutations) in every protected operation.

## Consequences

- One session model and one place for revocation for web and mobile; no signing keys to rotate.
- Every bearer request reads the session from the database (as for cookies) – acceptable at Silo's scale, and it gives immediate revocation.
- A bearer token is equivalent to the Silo password for 90/365 days: the client must keep it in the system's secure storage (Keychain / Android Keystore). Token theft is limited by "sign out everywhere" and the session list with device names.
- No refresh tokens: after a session expires the user signs in again (rare with 90 days of inactivity).
- Future features (push, delta sync) tie a device to a bearer session, not to a separate authentication entity.

## Alternatives

- **JWT (access + refresh):** stateless verification is unnecessary with one server and Postgres; revocation requires a list in the database anyway, plus key rotation and the risk of configuration mistakes (`alg`, lifetime). The design excluded JWT from the start.
- **OAuth2 (authorization code + PKCE / device flow) with our own authorization server:** the right pattern for third-party apps, but Silo has no third-party clients; our own authorization server is a large surface (client registration, consent, refresh) with no benefit for a single first-party app.
- **A separate API token table:** duplicates the lifetime, listing and revocation logic; "sign out everywhere" would have to cover two tables. The `kind` column gives the same with a single code path.
- **A token in the query string for SSE:** unnecessary for a native client (it sets headers), and it leaks into logs and history; rejected.

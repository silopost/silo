# Signing in to mail accounts with OAuth2 (Gmail, Microsoft 365)

Silo can add Gmail and Microsoft 365 accounts with a "Sign in with Google" /
"Sign in with Microsoft" button instead of a password. For Microsoft 365 this
is the only way: Exchange Online has basic (password) authentication for IMAP
turned off. For Gmail it is a more convenient and more secure alternative to
app passwords: the user gives Silo no password at all, and access can be
revoked at any time on Google's side.

How it works in short:

- Silo uses the *authorization code* flow with PKCE (S256). The user signs in
  on the Google/Microsoft page and consents to access to their mail.
- Silo stores the **refresh token**, encrypted with `SILO_SECRET_KEY` in the
  same way as account passwords (the `rotate-secrets` command re-encrypts it
  together with the passwords). Before every IMAP/SMTP connection Silo obtains
  a short-lived *access token* and signs in with the `XOAUTH2` mechanism.
- Every Silo instance needs **its own OAuth application**, registered by the
  administrator with the provider. Silo does not ship a shared client ID.

The decision and its consequences: [ADR 0013](../adr/0013-oauth2-xoauth2.md);
protocol details (error codes, tokens): the `silo-server` README, section
"OAuth2"; other administration: [README](README.md). OAuth2 sign-in currently
works only in `silo-web` (the browser) – `silo-mobile` will get its own variant
in phase 6.

## 1. Redirect URI

For each provider you register exactly one address:

```text
<SILO_PUBLIC_URL>/api/v1/oauth/google/callback
<SILO_PUBLIC_URL>/api/v1/oauth/microsoft/callback
```

Example for `SILO_PUBLIC_URL=https://mail.example.com`:
`https://mail.example.com/api/v1/oauth/google/callback`.

With the `caddy` variant, `SILO_PUBLIC_URL` defaults to `https://$SILO_DOMAIN`; the `http` and `nginx` variants set it explicitly.
The address must match character for character (the `https` scheme, the host,
no trailing slash). Both providers require `https` (the exception is
`http://localhost` for local tests). If you change `SILO_PUBLIC_URL`, change
the address at the provider too.

## 2. Google (Gmail, Google Workspace)

Everything happens in the [Google Cloud Console](https://console.cloud.google.com/),
on the instance administrator's account (for Workspace preferably on an
organization account).

1. **Project.** Create a new project (e.g. "Silo mail") or select an existing one.
2. **Consent screen** (*Google Auth Platform* → *Branding* / formerly *OAuth
   consent screen*):
   - the application name (e.g. "Silo – mail"), a support email address, an
     optional logo, the home page domain and the privacy policy (required when
     publishing for external users);
   - *Audience* / user type:
     - **Internal** – only accounts of your Google Workspace organization; no
       Google verification, no user limit. The simplest option for a company
       on Workspace.
     - **External** – any Google accounts (including private @gmail.com).
3. **Scopes** (*Data Access* → *Add or remove scopes*): add
   `https://mail.google.com/` (full IMAP/SMTP access – the only scope that
   allows IMAP and SMTP) as well as `openid` and `.../auth/userinfo.email`
   (`email`). Google marks `https://mail.google.com/` as a **restricted**
   scope.
4. **Publishing status** (applies to the External type):
   - **Testing** – works right away, but only for accounts added as *Test
     users* (up to 100), and **refresh tokens expire after 7 days**: the
     account in Silo then goes to the `auth_failed` state ("OAuth
     authorization expired; sign in again") and the user has to sign in
     again. Good for trials, not for daily work.
   - **In production** – for a restricted scope Google requires verification
     of the application, and for an application shared more widely also an
     external security assessment (CASA). Without verification users will see
     the "Google hasn't verified this app" screen (and a limit of 100 users
     applies). For a small, private instance a deliberate click on
     "Advanced → Go to … (unsafe)" is usually enough; for organizations we
     recommend the Internal type.
5. **OAuth client** (*Clients* / *Credentials* → *Create credentials* → *OAuth
   client ID*):
   - application type: **Web application**;
   - *Authorized redirect URIs*: the address from step 1 for Google;
   - *Authorized JavaScript origins* are not needed.
   Save the *Client ID* and the *Client secret*.
6. (Optional) *APIs & Services* → *Library* → enable the **Gmail API** – it is
   not required for IMAP/SMTP, but makes later changes and viewing quotas
   easier.
7. For users: IMAP in Gmail is always enabled today; in Google Workspace an
   administrator can turn it off (*Admin console* → *Apps* → *Google
   Workspace* → *Gmail* → *End user access* → *POP and IMAP access*) – it must
   be allowed. If Workspace restricts third-party app access (*API
   controls*), mark the Silo application as trusted.

Silo configuration:

```env
SILO_OAUTH_GOOGLE_CLIENT_ID=1234567890-abc.apps.googleusercontent.com
SILO_OAUTH_GOOGLE_CLIENT_SECRET=GOCSPX-...
```

## 3. Microsoft 365 (Exchange Online) and Outlook.com

Everything happens in the [Microsoft Entra admin center](https://entra.microsoft.com/)
(formerly Azure AD), on an account with at least the *Application Developer*
role (admin consent: *Cloud Application Administrator* or *Global
Administrator*).

1. **Application registration:** *Identity* → *Applications* → *App
   registrations* → *New registration*:
   - a name (e.g. "Silo mail");
   - *Supported account types* – `SILO_OAUTH_MICROSOFT_TENANT` depends on it:

     | Choice in the portal | `SILO_OAUTH_MICROSOFT_TENANT` |
     |---|---|
     | Accounts in this organizational directory only (single tenant) | the directory ID (*Directory (tenant) ID*) or the domain, e.g. `example.onmicrosoft.com` |
     | Accounts in any organizational directory (multitenant) | `organizations` |
     | … and personal Microsoft accounts | `common` (default) |

   - *Redirect URI*: platform **Web**, the address from step 1 for Microsoft.
2. **Secret:** *Certificates & secrets* → *New client secret*. Copy the
   **Value** (not the *Secret ID*) – it is shown only once. The secret has an
   expiry date (max. 24 months): put its replacement in your calendar; after
   it expires nobody can add or renew an account, and existing accounts stop
   connecting.
3. **Permissions:** *API permissions* → *Add a permission* → *Microsoft Graph*
   → *Delegated permissions*, select:
   - `IMAP.AccessAsUser.All`
   - `SMTP.Send`
   - `offline_access` (without it there is no refresh token)
   - `openid`, `email`
   If the directory policy does not let users consent on their own, click
   **Grant admin consent for <organization>**.
4. *Overview*: copy the **Application (client) ID** (and the *Directory
   (tenant) ID* for a single-directory application).
5. **Exchange Online – SMTP AUTH.** In new tenants, authenticated SMTP sending
   (SMTP AUTH) is disabled by default. Enable it for the mailboxes used in
   Silo (PowerShell, the ExchangeOnlineManagement module):

   ```powershell
   Connect-ExchangeOnline
   # for a single mailbox:
   Set-CASMailbox -Identity jan@example.com -SmtpClientAuthenticationDisabled $false
   # or for the whole organization:
   Set-TransportConfig -SmtpClientAuthenticationDisabled $false
   ```

   The same in the *Microsoft 365 admin center*: *Users* → the user → *Mail* →
   *Manage email apps* → **Authenticated SMTP** and **IMAP** checked.
   IMAP must be enabled (`Set-CASMailbox -ImapEnabled $true`).
   Disabling *Security defaults* is not needed: XOAUTH2 is modern
   authentication.
6. Private Outlook.com accounts (`TENANT=common` or `consumers`) have not yet
   been checked with Silo (servers `outlook.office365.com` /
   `smtp.office365.com`); treat them as experimental.

Silo configuration:

```env
SILO_OAUTH_MICROSOFT_CLIENT_ID=00000000-0000-0000-0000-000000000000
SILO_OAUTH_MICROSOFT_CLIENT_SECRET=abc~...
SILO_OAUTH_MICROSOFT_TENANT=organizations
```

## 4. Starting and checking

- A provider's client ID and secret are set **together**; only one of them is
  a configuration error (Silo will not start and prints what is missing).
- Add the variables to `.env` and run `docker compose up -d` (the
  `silo-server` container is recreated with the new configuration). Then
  `GET /api/v1/meta` returns `"oauthProviders": ["google", "microsoft"]`
  (only the configured ones) – silo-web then shows the sign-in buttons when
  adding an account.
- The variables `SILO_OAUTH_*_AUTH_URL`, `*_TOKEN_URL`, `*_USERINFO_URL` are
  for tests only (a fake provider) – do not set them in production.
- Silo connects to the providers' servers (`imap.gmail.com:993`,
  `smtp.gmail.com:465`, `outlook.office365.com:993`, `smtp.office365.com:587`)
  and to their token servers (`oauth2.googleapis.com`,
  `login.microsoftonline.com`) – the firewall must allow this.

## 5. What the user sees and what happens later

- Adding an account: "Sign in with Google/Microsoft" → the provider's page →
  consent → back to Silo. Silo immediately checks IMAP and SMTP; if the test
  fails, the account is not created (code `account_test_failed`, e.g. SMTP
  AUTH disabled in Exchange).
- Expired or revoked access (a Google account password change, revoking the
  app in the account's security settings, *Testing* mode after 7 days, an
  expired client secret on the Microsoft side): the account goes to the
  `auth_failed` state with the message "OAuth authorization expired; sign in
  again". Synchronization stops, sending fails; the user clicks "Sign in
  again" on the account and signs in with **the same** address.
- Revoking Silo's access to a mailbox: Google Account → *Security* →
  *Third-party apps & services*; Microsoft: *myapps.microsoft.com* /
  *account.live.com/consent/Manage*, or an administrator in Entra
  (*Enterprise applications* → the application → *Users and groups* / remove
  consent). Deleting the account in Silo does not revoke the consent at the
  provider – do it there.
- Copies of sent messages: Gmail and Exchange Online store sent mail in the
  Sent folder themselves, so by default Silo does not add its own copy
  (`sentAppend` disabled).

## 6. Gmail without mode `provider=gmail`

The full Gmail mode (Gmail labels as Silo labels, Gmail threads) is planned
for 1.1. Until then a Gmail account works in generic mode: Silo sees the
inbox and the special folders (`[Gmail]/All Mail`, Sent, Drafts, Trash,
Spam); the same message in the Inbox and in All Mail is a single message in
Silo; archiving removes the "Inbox" label (the copy in All Mail remains).
Labels created in Gmail are not visible in Silo, and Silo builds threads on
its own, so they may differ slightly from the threads in Gmail.

## 7. Manual test after configuration

Neither Gmail nor Microsoft 365 has been checked live yet (CI uses a fake
provider and Dovecot with `passdb oauth2`). After the first configuration,
go through the scenario from the [compatibility matrix](../compat-matrix.md#oauth2-and-xoauth2-phase-5)
(adding an account, initial sync, archive, a label, sending, a reply from
another client, revoking access) and report the result, so that the matrix
can be completed.

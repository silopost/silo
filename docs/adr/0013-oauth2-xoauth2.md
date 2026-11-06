# 0013. OAuth2 (authorization code + PKCE) i XOAUTH2 dla Gmaila i Microsoft 365

- **Status:** Przyjęty
- **Data:** 2026-11-06
- **Dotyczy:** silo-server, silo-web, silo-mobile

## Kontekst

Exchange Online ma wyłączone uwierzytelnianie hasłem dla IMAP/SMTP, a Gmail wymaga hasła aplikacji (dostępnego tylko przy 2FA). Silo loguje się do skrzynek w tle (IDLE, wysyłka zaplanowana), więc potrzebuje odwoływalnego poświadczenia, które może odświeżać bez użytkownika ([plan 3.15](../../ARCHITECTURE_AND_PLAN.md#315-konta-uwierzytelnianie-i-sekrety)). Silo jest aplikacją webową z sekretem klienta po stronie serwera; każda instancja rejestruje własną aplikację OAuth u dostawcy.

## Decyzja

- **Przepływ authorization code z PKCE (S256)**, `golang.org/x/oauth2`: `POST /oauth/{provider}/start` (zalogowany) → strona dostawcy → `GET /oauth/{provider}/callback` → `303` na `SILO_PUBLIC_URL + returnTo?oauth=ok|error&code=…`. Stan (32 losowe bajty, weryfikator PKCE, użytkownik, `returnTo`) w tabeli `oauth_states` na 10 minut, jednorazowy.
- **Ciasteczko `silo_oauth_state`** (HttpOnly, SameSite=Lax, ścieżka `/api/v1/oauth/`) wiąże start i callback z tą samą przeglądarką – ochrona przed OAuth login CSRF (link do strony zgody wysłany przez napastnika nie dopisze cudzej skrzynki do jego użytkownika).
- **Refresh token** zaszyfrowany jak hasło skrzynki (`accounts.secret_enc`, AES-256-GCM, AAD = id konta, `rotate-secrets`). Access token w pamięci, odświeżany przed połączeniem, gdy wygasa w ciągu 60 s; rotowany refresh token zapisywany ponownie. `invalid_grant` → konto `auth_failed` + `account.error`; ponowna autoryzacja przez `start` z `accountId` (podpowiedź `login_hint`, adres musi się zgadzać).
- **XOAUTH2** dla IMAP (`AUTHENTICATE XOAUTH2`) i SMTP (`AUTH XOAUTH2`); `Account.authType` = `password | xoauth2`; konto OAuth nie ma hasła (`PATCH` hasła → `409 not_available`).
- **Microsoft:** żądanie odświeżenia zawiera `scope` (własne żądanie, bo `x/oauth2` go pomija); IMAP `outlook.office365.com:993`, SMTP `smtp.office365.com:587` STARTTLS. **Google:** `access_type=offline`, `prompt=consent`; IMAP 993, SMTP 465 implicit TLS.
- `sent_append=false` dla Google i Microsoft – oba zapisują wysłaną pocztę w Sent same ([plan 3.9](../../ARCHITECTURE_AND_PLAN.md#39-wysyłka-smtp-submission)).
- **Gmail działa w trybie generycznym** (foldery, `\All` z deduplikacją, archiwizacja = usunięcie kopii z INBOX). **Tryb `provider=gmail`** (`X-GM-LABELS`, `X-GM-MSGID`, `X-GM-THRID`, sync tylko All Mail/Trash/Spam) **odłożony do 1.1**: brak konta testowego i symulatora X-GM (Dovecot nie udaje `X-GM-EXT-1`), a tryb generyczny pokrywa odczyt, archiwizację i wysyłkę.

## Konsekwencje

- Konta Gmail i Microsoft 365 bez haseł, odwoływalne po stronie dostawcy; Silo nie przechowuje hasła głównego.
- Administrator musi zarejestrować aplikację i (Google, zakres zastrzeżony `https://mail.google.com/`) przejść weryfikację; tryb *Testing* Google wygasza refresh tokeny po 7 dniach. Instrukcja: [docs/admin/oauth.md](../admin/oauth.md).
- **Klient natywny** (bearer, zewnętrzna przeglądarka) nie ma ciasteczka `silo_oauth_state` i dostaje `oauth_state_invalid`. `silo-mobile` potrzebuje wariantu z `redirectUri` aplikacji (deep link) i innym wiązaniem stanu – Faza 6.
- Bez trybu `provider=gmail` etykiety Gmaila (poza folderami specjalnymi) nie są etykietami Silo, a wątki buduje JWZ Silo (mogą różnić się od Gmaila); część DoD Fazy 5 dla Gmaila przechodzi do 1.1.
- Dostawcy na żywo nieprzetestowani w CI: XOAUTH2 sprawdzony Dovecotem z `passdb oauth2` (introspekcja RFC 7662 u atrapy dostawcy) i profilem `gmail-like`; kroki testu ręcznego w [macierzy kompatybilności](../compat-matrix.md#2-serwery-pocztowe-imapsmtp).

## Alternatywy

- **Hasła aplikacji zamiast OAuth2:** nadal wspierane (konto z hasłem), ale niedostępne w Exchange Online i coraz rzadziej w Google Workspace. Nie wystarcza.
- **Wiązanie stanu tylko sesją Silo (bez ciasteczka):** pozwala klientom natywnym na ten sam przepływ, ale zostawia login CSRF (callback nie wymaga sesji – przychodzi z przeglądarki ofiary). Odrzucone na 1.0.
- **Implicit flow / klient publiczny bez sekretu:** tokeny w przeglądarce, brak refresh tokenu do pracy w tle. Odrzucone.
- **Gmail API (REST) zamiast IMAP:** natywne etykiety i wątki, ale drugi silnik synchronizacji obok IMAP (sprzeczne z [ADR 0005](0005-imap-source-of-truth.md)). Odrzucone.

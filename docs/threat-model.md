# Model zagrożeń Silo

Stan: `silo-server` 0.5.0, `silo-web` 0.4.0 (Faza 5). Rozwija tabelę z [planu 3.15](../ARCHITECTURE_AND_PLAN.md#315-konta-uwierzytelnianie-i-sekrety). Szczegóły mechanizmów: README `silo-server` (sekcje „Hardening”, „OAuth2”, „Users, mode `local`”, „Backup and restore”), zalecenia operacyjne: [docs/admin](admin/README.md).

## Zakres i założenia

Silo to klient poczty działający na serwerze: loguje się do skrzynek IMAP/SMTP **w tle** (IDLE, sync, wysyłka zaplanowana), trzyma lustro poczty w Postgresie i udostępnia je przeglądarce (`silo-web`) i aplikacji `silo-mobile` przez `/api/v1`. Zakładamy:

- jedną instancję `silo-server` za reverse proxy z TLS (Caddy z `docker-compose.yml`); Postgres i bloby niedostępne z internetu;
- serwer poczty jest zewnętrzny i zaufany co do treści skrzynki swojego użytkownika, ale **treść wiadomości jest wroga** (każdy może wysłać dowolny HTML);
- administrator instancji jest zaufany (ma dostęp do bazy i klucza); użytkownicy instancji nie ufają sobie nawzajem.

## Aktywa

| Aktywo | Gdzie | Ochrona |
|---|---|---|
| Hasła IMAP/SMTP i refresh tokeny OAuth2 | `accounts.secret_enc` | AES-256-GCM kluczem `SILO_SECRET_KEY`, format `v1:<key_id>:<nonce>:<ciphertext>`, AAD = id konta (szyfrogramu nie da się przenieść do innego wiersza); rotacja `rotate-secrets` |
| Sekrety TOTP i kody zapasowe | `users.totp_secret_enc`, `users.totp_backup_codes` | sekret jak wyżej (AAD = id użytkownika); kody zapasowe tylko jako `sha256`, jednorazowe |
| Hasła Silo (tryb `local`) i weryfikator offline (tryb `imap`) | `users.password_hash` | argon2id |
| Lustro poczty | `messages`, `body_text`, bloby (`fs`/`s3`) | **jawne** w bazie i magazynie blobów – szyfrowanie dysku/backupów po stronie admina |
| Sesje | `sessions` | losowy 256-bitowy token; w bazie tylko `sha256`; cookie `HttpOnly; Secure; SameSite=Lax` lub bearer w Keychain/Keystore |
| Klucz `SILO_SECRET_KEY` | env / plik sekretu | nigdy w bazie, w logach ani w backupie |
| Metadane (etykiety, filtry, drafty, ustawienia) | Postgres | backup `metadata` ([ADR 0014](adr/0014-metadata-backup-format.md)) |

## Aktorzy

- **Anonimowy napastnik w internecie** – zgaduje hasła, wysyła spreparowane żądania, linki i strony (CSRF), skanuje.
- **Nadawca złośliwej wiadomości** – kontroluje HTML, załączniki, nagłówki, obrazy zdalne.
- **Zalogowany użytkownik instancji** – próbuje odczytać dane innego użytkownika albo użyć Silo do ataku na sieć wewnętrzną (SSRF).
- **Napastnik z dostępem do kopii bazy lub backupu** (wyciek dumpu, dysku, bucketu).
- **Napastnik z przejętym hostem** (baza + env z kluczem).
- **Napastnik w sieci** między Silo a serwerem poczty lub dostawcą OAuth (MITM).

## Zagrożenia i mitygacje

| Zagrożenie | Skutek | Mitygacja (mechanizm) |
|---|---|---|
| Wyciek dumpu DB lub backupu bez klucza | brak sekretów w jawnej postaci; **treść poczty jawna** | sekrety AES-GCM z AAD; klucz poza bazą i backupem (`backup.sh` go nie zapisuje); szyfrowanie dysku i backupów – zadanie admina; at-rest mirrora poza zakresem (niżej) |
| Wyciek DB + `SILO_SECRET_KEY` (przejęcie hosta) | dostęp do wszystkich skrzynek | **hasła aplikacji** zamiast haseł głównych, OAuth2 ([ADR 0013](adr/0013-oauth2-xoauth2.md)) – tokeny odwoływalne u dostawcy, bez hasła głównego; rotacja klucza (`SILO_SECRET_KEY_PREVIOUS` + `rotate-secrets`) po incydencie, zmiana haseł skrzynek |
| Brute-force logowania; Silo jako wyrocznia do zgadywania haseł serwera poczty | przejęcie konta | token bucket per IP (`SILO_RATE_LIMIT_AUTH`, domyślnie `20/m`) i per login, stała minimalna długość odpowiedzi, zawsze `401 invalid_credentials`; w trybie `local` nieznany/wyłączony użytkownik weryfikowany wobec fikcyjnego hasha argon2id ([ADR 0011](adr/0011-local-auth-mode-and-totp.md)); seclog `event=auth_failed` → fail2ban |
| Przechwycony lub zgadywany kod TOTP | obejście drugiego składnika | anty-replay (`totp_last_step`), okno ±1 krok, limit `SILO_RATE_LIMIT_AUTH`, seclog `totp_failed`; `401 totp_required` dopiero po poprawnym haśle; ponowne uwierzytelnienie (zmiana hasła, wyłączenie TOTP, nowe kody) wymaga hasła i kodu (`403`) |
| Kradzież sesji | dostęp do poczty użytkownika | cookie `HttpOnly; Secure; SameSite=Lax`, w bazie `sha256` tokenu; wygasanie 30/90 dni (bearer 90/365); lista sesji, `DELETE /sessions/{id}` i `DELETE /sessions?others=true`; zmiana hasła i wyłączenie użytkownika kończą sesje; otwarty strumień SSE dostaje `session.expired` i jest zamykany (sprawdzane co heartbeat) |
| CSRF na API | akcje w imieniu użytkownika | `SameSite=Lax` + nagłówek `X-Silo-CSRF` dla mutacji + `Origin` równe `SILO_PUBLIC_URL`; bearer nie jest dołączany przez przeglądarkę; seclog `csrf_rejected` |
| OAuth login CSRF (ofiara kończy autoryzację rozpoczętą przez napastnika lub odwrotnie) | cudza skrzynka podpięta do konta napastnika | stan jednorazowy w `oauth_states` (10 min) **i** ciasteczko `silo_oauth_state` wiążące start i callback z tą samą przeglądarką; PKCE S256; re-autoryzacja wymaga tego samego adresu (`oauth_account_mismatch`) |
| XSS przez treść wiadomości | kradzież sesji, akcje w Silo | sanitizer HTML na serwerze + DOMPurify w kliencie; iframe `sandbox` bez `allow-scripts`, treść przez `srcdoc` z własnym CSP (`script-src 'none'`); CSP aplikacji z Caddyfile (`script-src 'self'`); `GET /messages/{id}/html` z CSP `default-src 'none'` i `frame-ancestors` ograniczonym do origin Silo; załączniki z `CSP: sandbox` i `nosniff` |
| Śledzenie przez obrazy zdalne | ujawnienie IP i czasu odczytu | obrazy zdalne blokowane domyślnie w `silo-web` (przycisk „Pokaż obrazy”); `Referrer-Policy: no-referrer`; proxy obrazów poza zakresem (niżej) |
| Clickjacking | wymuszone kliknięcia | `X-Frame-Options: DENY`, `frame-ancestors 'none'` (API i SPA) |
| SSRF przez konto na dowolnym hoście, autokonfigurację lub DNS rebinding | skan i ataki na sieć wewnętrzną | `SILO_ALLOW_CUSTOM_SERVERS=false` domyślnie w trybie `imap`; `internal/netx`: host rozwiązywany przez Silo, połączenie **z przefiltrowanym adresem** (IMAP, SMTP, test konta, autokonfiguracja, ISPDB) – adresy prywatne/loopback/link-local odrzucane, wyjątki tylko z `SILO_CUSTOM_SERVER_ALLOWLIST`; autokonfiguracja: przekierowania tylko `https` na ten sam host (≤ 3), odpowiedź ≤ 256 kB, limit 10/min na użytkownika |
| Odczyt danych innego użytkownika (IDOR) | wyciek poczty | każde zapytanie zawężone do użytkownika sesji; cudze ID w ścieżce → `404` jak nieistniejące, w ciele → `400`/`422` jak nieznane; zdarzenia SSE i polling tylko własne; test `TestUserIsolation` (każdy endpoint w obu kierunkach, SSE, `Last-Event-ID`) |
| Eskalacja do admina | przejęcie instancji | `/admin/*` → `403` dla nie-admina (seclog `forbidden`); admin nie może zdegradować ani wyłączyć siebie; nadanie uprawnień tylko przez admina lub CLI na hoście |
| Downgrade TLS / MITM do serwera poczty lub dostawcy OAuth | przechwycenie haseł i tokenów | TLS z weryfikacją certyfikatu domyślnie; `TLS=none` i niezweryfikowane certyfikaty tylko z `SILO_ALLOW_INSECURE_TRANSPORT` (dev); dostawcy OAuth wyłącznie przez `https`; HSTS dla przeglądarki |
| Fałszowanie IP klienta (`X-Forwarded-For`) | obejście limitów, fałszywe logi | nagłówki honorowane tylko od adresów z `SILO_TRUSTED_PROXIES`; klient = skrajnie prawy adres spoza zaufanych |
| DoS: zalew żądań, wiele strumieni SSE, duże uploady | niedostępność | `SILO_RATE_LIMIT_API` (`600/m` per IP, `429 rate_limited` + `Retry-After`), maks. 8 strumieni SSE na użytkownika (`stream.limit`), `SILO_MAX_ATTACHMENT_BYTES`, limity rozmiaru mirrora (`SILO_MIRROR_*`) i liczby kont |
| Wyciek sekretów w logach | przejęcie kont | hasła i tokeny nigdy nie są logowane; login w seclogu maskowany (`j***@example.com`); joby w panelu admina bez `payload` |
| Utrata klucza `SILO_SECRET_KEY` | brak dostępu do skrzynek po awarii | klucz przechowywany osobno od backupu bazy (dwa różne miejsca); bez niego import metadanych jest bezużyteczny – użytkownicy muszą podać hasła skrzynek ponownie |
| Odwołany dostęp OAuth / zmienione hasło skrzynki | sync stoi | stan `auth_failed` + `account.error`, brak ponowień (nie blokuje konta u dostawcy), re-autoryzacja przez użytkownika |

## Świadomie poza zakresem

- **Szyfrowanie at-rest lustra poczty** (bloby, `body_text`) – [decyzja odłożona 8](../ARCHITECTURE_AND_PLAN.md#decyzje-odłożone--otwarte-pytania): klucz pochodny z hasła użytkownika uniemożliwiłby sync w tle. Zalecane szyfrowanie dysku i backupów.
- **Proxy obrazów zdalnych** – decyzja odłożona 4 (ryzyko SSRF po stronie serwera); dziś blokada w kliencie.
- Ochrona przed złośliwym administratorem instancji lub hostem (ma bazę i klucz).
- Wiele instancji `silo-server` (limity w pamięci procesu – decyzja odłożona 14).
- Antyspam, antywirus, SPF/DKIM/DMARC – zadania serwera poczty.
- WebAuthn i zewnętrzny IdP (OIDC) – [ADR 0011](adr/0011-local-auth-mode-and-totp.md), odłożone.
- OAuth2 dla klientów natywnych – Faza 6 ([ADR 0013](adr/0013-oauth2-xoauth2.md)).

## Zalecenia dla administratora

- **Hasła aplikacji** dla skrzynek (osobne, odwoływalne hasło IMAP/SMTP dla Silo); Gmail i Microsoft 365 – OAuth2 ([admin/oauth.md](admin/oauth.md)) zamiast hasła głównego.
- **TLS wszędzie:** Silo tylko za HTTPS (`SILO_PUBLIC_URL=https://…`, HSTS); do serwera poczty `implicit`/`starttls` z ważnym certyfikatem; nigdy `SILO_ALLOW_INSECURE_TRANSPORT` w produkcji.
- **Klucz osobno od bazy:** `SILO_SECRET_KEY` w menedżerze sekretów lub w osobnej kopii; backup bazy i klucz w różnych miejscach; po wycieku – rotacja klucza i zmiana haseł skrzynek.
- `SILO_TRUSTED_PROXIES` ustawione na sieć proxy, fail2ban na seclogu, `SILO_ALLOW_CUSTOM_SERVERS=false`, jeśli użytkownicy nie potrzebują innych serwerów.
- Szyfrowanie dysku hosta, wolumenów i backupów; Postgres i bucket S3 niedostępne z internetu.
- TOTP dla kont administratorów w trybie `local`.

Instrukcje: [docs/admin/README.md](admin/README.md) (sekcje „Instalacja produkcyjna”, „Hasła aplikacji”, „Hardening”).

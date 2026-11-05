# 0007. Opaque bearer tokens dla klientów natywnych

- **Status:** Przyjęty
- **Data:** 2026-11-05
- **Dotyczy:** silo-server, silo (plan), przyszłe silo-mobile

## Kontekst

Do `silo-server` będzie łączyć się dedykowana natywna aplikacja mobilna (osobne repo, np. `silo-mobile`; [plan 1](../../ARCHITECTURE_AND_PLAN.md#1-cel-i-zasady), [2.6](../../ARCHITECTURE_AND_PLAN.md#26-klienci-api)) z parytetem operacji pocztowych względem silo-web i aplikacji Gmail na telefon. Dotąd jedynym uwierzytelnieniem była sesja przeglądarkowa: cookie `silo_session` (HttpOnly, SameSite=Lax) + nagłówek `X-Silo-CSRF` + sprawdzenie `Origin` ([plan 3.15](../../ARCHITECTURE_AND_PLAN.md#315-konta-uwierzytelnianie-i-sekrety)). Klient natywny nie ma słoika cookie przeglądarki, nie ma `Origin`, a 30/90 dni ważności oznacza zbyt częste ponowne logowanie na telefonie. Plan wykluczał JWT; zasady bezpieczeństwa (tylko hash tokenu w bazie, unieważnianie sesji, „wyloguj wszędzie”) mają obowiązywać także mobile.

## Decyzja

Drugi, równorzędny kanał uwierzytelnienia: **opaque bearer token** w nagłówku `Authorization: Bearer <token>`, w tej samej tabeli `sessions` co sesje cookie.

- **Token:** ten sam losowy 256-bitowy token co dla cookie; w bazie tylko `sha256` (`sessions.token_hash`). Bez JWT, bez podpisów, bez refresh tokenów.
- **Rodzaj sesji:** kolumna `sessions.kind` (`cookie` | `bearer`, domyślnie `cookie`) i `sessions.client_name` (nazwa urządzenia). Token jest akceptowany **tylko w kanale, dla którego go wydano**: token cookie w nagłówku `Authorization` → 401 i odwrotnie.
- **Logowanie:** ten sam `POST /api/v1/session` z opcjonalnym polem `client`:
  `{"email","password","client":{"kind":"bearer","name":"Pixel 8"}}`. Dla `bearer` odpowiedź (`SessionBody`) zawiera `token` (pokazywany raz), bez `Set-Cookie`. Bez pola `client` (lub z `kind: "cookie"`) zachowanie bez zmian. Wybraliśmy jeden endpoint zamiast osobnego, bo cała logika logowania (IMAP LOGIN, weryfikator offline, limity, stały czas odpowiedzi, tworzenie konta) jest wspólna, a różni się tylko sposób przekazania tokenu.
- **CSRF:** dla żądań uwierzytelnionych bearerem nie ma wymogu `X-Silo-CSRF` ani weryfikacji `Origin`: przeglądarka nigdy nie dołącza nagłówka `Authorization` sama (atak CSRF jeździ na ambient credentials, czyli cookie). Gdy nagłówek `Authorization: Bearer` jest obecny, uwierzytelnia **wyłącznie** on (cookie jest ignorowane), więc nie da się ominąć CSRF dla sesji cookie. Inne schematy (`Basic` z reverse proxy) są ignorowane.
- **Ważność:** bearer: sliding 90 dni, absolutnie 365 dni (cookie bez zmian: 30/90). Stałe w kodzie (`internal/auth`), bez nowych zmiennych env – jak dla cookie; env dodamy, gdy pojawi się realna potrzeba.
- **Zarządzanie:** `GET /sessions` zwraca `kind` i `clientName`; `DELETE /sessions/{id}` i `DELETE /session` działają dla obu rodzajów („wyloguj wszędzie” obejmuje urządzenia mobilne).
- **Strumienie i pliki:** `GET /events`, `/events/poll`, treści i załączniki są zwykłymi operacjami chronionymi tym samym middleware, więc działają z bearerem. Tokenu w query string **nie** dopuszczamy (logi, historia, nagłówek `Referer`); klient natywny ustawia nagłówki sam, a przeglądarka używa cookie.
- **OpenAPI:** drugi security scheme `bearerAuth` (`type: http, scheme: bearer`) jako alternatywa dla `cookieAuth` (+ `csrfHeader` przy mutacjach) w każdej chronionej operacji.

## Konsekwencje

- Jeden model sesji i jedno miejsce unieważniania dla web i mobile; brak kluczy podpisujących do rotacji.
- Każde żądanie bearer to odczyt sesji z bazy (jak dla cookie) – akceptowalne przy skali Silo, a daje natychmiastowe unieważnienie.
- Token bearer jest równoważny hasłu do Silo przez 90/365 dni: klient musi go trzymać w bezpiecznym magazynie systemu (Keychain / Android Keystore). Kradzież tokenu ogranicza „wyloguj wszędzie” i lista sesji z nazwą urządzenia.
- Brak refresh tokenów: po wygaśnięciu sesji użytkownik loguje się ponownie (przy 90 dniach bezczynności to rzadkie).
- Przyszłe funkcje (push, delta sync) wiążą urządzenie z sesją bearer, a nie z osobnym bytem uwierzytelniającym.

## Alternatywy

- **JWT (access + refresh):** bezstanowa weryfikacja jest zbędna przy jednym serwerze z Postgresem; unieważnianie wymaga i tak listy w bazie, dochodzi rotacja kluczy i ryzyko błędów konfiguracji (`alg`, czas życia). Plan od początku wyklucza JWT.
- **OAuth2 (authorization code + PKCE / device flow) na własnym serwerze:** poprawny wzorzec dla aplikacji zewnętrznych, ale Silo nie ma klientów firm trzecich; własny serwer autoryzacji to duża powierzchnia (rejestracja klientów, zgody, refresh) bez korzyści dla jednej własnej aplikacji.
- **Osobna tabela tokenów API:** dubluje logikę ważności, listowania i unieważniania; „wyloguj wszędzie” musiałby obejmować dwie tabele. Kolumna `kind` daje to samo przy jednej ścieżce kodu.
- **Token w query string dla SSE:** niepotrzebny dla klienta natywnego (ustawia nagłówki), a wycieka do logów i historii; odrzucony.

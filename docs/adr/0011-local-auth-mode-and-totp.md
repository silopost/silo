# 0011. Tryb `local` z hasłem Silo i własnym TOTP

- **Status:** Przyjęty
- **Data:** 2026-11-06
- **Dotyczy:** silo-server, silo-web

## Kontekst

Tryb `imap` ([plan 3.15](../../ARCHITECTURE_AND_PLAN.md#315-konta-uwierzytelnianie-i-sekrety)) loguje danymi skrzynki na serwerze domyślnym – wygodny dla instancji „jeden serwer poczty”, ale bezużyteczny, gdy użytkownicy mają skrzynki u różnych dostawców (Gmail przez OAuth2, Microsoft 365, hosting). Faza 5 potrzebuje użytkowników Silo niezależnych od skrzynek, zakładanych przez administratora, z drugim składnikiem i panelem administracyjnym. Silo nie powinno przy tym stać się wyrocznią do odgadywania, które konta istnieją, ani przyjmować ponownie przechwyconego kodu jednorazowego.

## Decyzja

`SILO_AUTH_MODE=local`: użytkownicy Silo z własnym hasłem (argon2id), zakładani przez administratora (`silo-server user add`, `POST /admin/users`); bez samodzielnej rejestracji. Drugi składnik to **TOTP RFC 6238 zaimplementowany w Silo** (`internal/totp`, SHA1, 30 s, 6 cyfr, ±1 krok).

- **Stały czas logowania:** nieznany, wyłączony użytkownik i złe hasło weryfikowane są wobec stałego fikcyjnego hasha argon2id, z tą samą minimalną długością odpowiedzi; zawsze `401 invalid_credentials`.
- **Kolejność czynników:** `401 totp_required` dopiero po poprawnym haśle (bez kodu); zły kod → `401 invalid_credentials`. Klient wysyła ponownie `POST /session` z `totpCode`.
- **Sekret TOTP** zaszyfrowany AES-256-GCM kluczem `SILO_SECRET_KEY` (AAD = `users.id`), obejmuje go `rotate-secrets`. **Anty-replay:** `users.totp_last_step` – kod z kroku czasowego już użytego jest odrzucany. **Kody zapasowe:** 10 jednorazowych, w bazie tylko `sha256`.
- **Ponowne uwierzytelnienie** zalogowanego (zmiana hasła, wyłączenie TOTP, nowe kody zapasowe) przy złym haśle lub kodzie → `403 invalid_credentials` (401 klient traktuje jako „wylogowany”).
- **Wyłączenie użytkownika przez admina:** sesje przestają działać od razu (także strumień SSE – `session.expired`), konta przechodzą w `sync_state='disabled'` (sync staje), odblokowanie wznawia połączenia. Admin nie może wyłączyć, odebrać sobie uprawnień ani usunąć siebie (`409 admin_self_change`).
- W trybie `local` użytkownik dodaje skrzynki sam (`POST /accounts`, autokonfiguracja, OAuth2); host inny niż domyślny zawsze przechodzi walidację anty-SSRF (`internal/netx`).

## Konsekwencje

- Instancja obsługuje skrzynki u wielu dostawców; panel admina (użytkownicy, stany kont, joby `dead`) działa w obu trybach.
- Brak zależności od zewnętrznej biblioteki TOTP i od zewnętrznego IdP; koszt: własny kod kryptograficzny (sprawdzony wektorami RFC 6238).
- Zgubione urządzenie bez kodów zapasowych wymaga admina (`POST /admin/users/{id}/totp/reset`).
- Kod przechwycony w tym samym kroku czasowym jest bezużyteczny po pierwszym użyciu; atak online ogranicza rate limit (`SILO_RATE_LIMIT_AUTH`, seclog `totp_failed` dla fail2ban).
- W trybie `imap` endpointy `/totp/*` i `/session/password` odpowiadają `409 not_available`.

## Alternatywy

- **OIDC / zewnętrzny IdP (Keycloak, Authentik):** naturalne dla organizacji, ale wymaga dodatkowej usługi, której mała instancja nie ma; odłożone (możliwe jako trzeci tryb).
- **WebAuthn / passkeys:** silniejsze od TOTP, ale wymaga rejestracji urządzeń, osobnego przepływu dla `silo-mobile` i HTTPS na każdej instancji testowej; odłożone do 1.x.
- **Biblioteka `pquerna/otp`:** gotowa, ale nie rozwiązuje anty-replay ani kodów zapasowych (stan po stronie aplikacji) – zysk niewielki wobec ~100 linii kodu z wektorami testowymi.
- **TOTP także w trybie `imap`:** hasło i tak weryfikuje serwer poczty; drugi składnik Silo nie chroni skrzynki przed innymi klientami IMAP. Odrzucone.

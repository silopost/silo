
# Logowanie kont pocztowych przez OAuth2 (Gmail, Microsoft 365)

Silo może dodawać konta Gmail i Microsoft 365 przyciskiem „Zaloguj przez
Google” / „Zaloguj przez Microsoft” zamiast hasła. Dla Microsoft 365 to jedyna
droga: w Exchange Online uwierzytelnianie podstawowe (hasło) dla IMAP jest
wyłączone. Dla Gmaila to wygodniejsza i bezpieczniejsza alternatywa dla haseł
aplikacji: użytkownik nie podaje Silo żadnego hasła, a dostęp można w każdej
chwili odwołać po stronie Google.

Jak to działa w skrócie:

- Silo używa przepływu *authorization code* z PKCE (S256). Użytkownik loguje
  się na stronie Google/Microsoft i zgadza się na dostęp do poczty.
- Silo zapisuje **refresh token**, zaszyfrowany kluczem `SILO_SECRET_KEY` tak
  samo jak hasła kont (polecenie `rotate-secrets` przeszyfrowuje go razem z
  hasłami). Przed każdym połączeniem IMAP/SMTP Silo pobiera krótkotrwały
  *access token* i loguje się mechanizmem `XOAUTH2`.
- Każda instancja Silo potrzebuje **własnej aplikacji OAuth** zarejestrowanej
  przez administratora u dostawcy. Silo nie dostarcza wspólnego identyfikatora
  klienta.

Decyzja i jej konsekwencje: [ADR 0013](../adr/0013-oauth2-xoauth2.md);
szczegóły protokołu (kody błędów, tokeny): README `silo-server`, sekcja
„OAuth2”; pozostała administracja: [README](README.md). Logowanie OAuth2 działa
dziś tylko w `silo-web` (przeglądarka) – `silo-mobile` dostanie własny wariant
w Fazie 6.

## 1. Adres przekierowania (redirect URI)

Dla każdego dostawcy rejestrujesz dokładnie jeden adres:

```text
<SILO_PUBLIC_URL>/api/v1/oauth/google/callback
<SILO_PUBLIC_URL>/api/v1/oauth/microsoft/callback
```

Przykład dla `SILO_PUBLIC_URL=https://poczta.example.com`:
`https://poczta.example.com/api/v1/oauth/google/callback`.

W `docker-compose.yml` `SILO_PUBLIC_URL` to domyślnie `https://$SILO_DOMAIN`.
Adres musi zgadzać się co do znaku (schemat `https`, host, brak końcowego
ukośnika). Obaj dostawcy wymagają `https` (wyjątkiem jest `http://localhost`
do testów lokalnych). Jeśli zmieniasz `SILO_PUBLIC_URL`, zmień też adres u
dostawcy.

## 2. Google (Gmail, Google Workspace)

Wszystko w [Google Cloud Console](https://console.cloud.google.com/), na koncie
administratora instancji (dla Workspace najlepiej na koncie organizacji).

1. **Projekt.** Utwórz nowy projekt (np. „Silo poczta”) albo wybierz istniejący.
2. **Ekran zgody** (*Google Auth Platform* → *Branding* / dawniej *OAuth consent
   screen*):
   - nazwa aplikacji (np. „Silo – poczta”), adres e-mail wsparcia, logo
     opcjonalnie, domena strony głównej i polityki prywatności (wymagane przy
     publikacji dla użytkowników zewnętrznych);
   - *Audience* / typ użytkowników:
     - **Internal** – tylko konta Twojej organizacji Google Workspace; brak
       weryfikacji Google, brak limitu użytkowników. Najprostsza opcja dla
       firmy na Workspace.
     - **External** – dowolne konta Google (także prywatne @gmail.com).
3. **Zakresy** (*Data Access* → *Add or remove scopes*): dodaj
   `https://mail.google.com/` (pełny dostęp IMAP/SMTP – jedyny zakres, który
   pozwala na IMAP i SMTP) oraz `openid` i `.../auth/userinfo.email`
   (`email`). Google oznacza `https://mail.google.com/` jako zakres
   **zastrzeżony** (*restricted*).
4. **Status publikacji** (dotyczy typu External):
   - **Testing** – działa od razu, ale tylko dla kont dopisanych jako *Test
     users* (do 100), a **refresh tokeny wygasają po 7 dniach**: konto w Silo
     przechodzi wtedy w stan `auth_failed` („OAuth authorization expired; sign
     in again”) i użytkownik musi zalogować się ponownie. Dobre do prób, nie do
     codziennej pracy.
   - **In production** – dla zakresu zastrzeżonego Google wymaga weryfikacji
     aplikacji, a dla aplikacji udostępnianej szerzej także zewnętrznej oceny
     bezpieczeństwa (CASA). Bez weryfikacji użytkownicy zobaczą ekran
     „Google hasn't verified this app” (i obowiązuje limit 100 użytkowników).
     Dla małej, prywatnej instancji zwykle wystarcza świadome kliknięcie
     „Advanced → Go to … (unsafe)”; dla organizacji polecamy typ Internal.
5. **Klient OAuth** (*Clients* / *Credentials* → *Create credentials* → *OAuth
   client ID*):
   - typ aplikacji: **Web application**;
   - *Authorized redirect URIs*: adres z punktu 1 dla Google;
   - *Authorized JavaScript origins* nie są potrzebne.
   Zapisz *Client ID* i *Client secret*.
6. (Opcjonalnie) *APIs & Services* → *Library* → włącz **Gmail API** – nie jest
   wymagane dla IMAP/SMTP, ale ułatwia późniejsze zmiany i podgląd limitów.
7. U użytkowników: IMAP w Gmailu jest dziś zawsze włączony; w Google Workspace
   administrator może go wyłączyć (*Admin console* → *Apps* → *Google
   Workspace* → *Gmail* → *End user access* → *POP and IMAP access*) – musi być
   dozwolony. Jeśli Workspace ogranicza dostęp aplikacji firm trzecich (*API
   controls*), oznacz aplikację Silo jako zaufaną.

Konfiguracja Silo:

```env
SILO_OAUTH_GOOGLE_CLIENT_ID=1234567890-abc.apps.googleusercontent.com
SILO_OAUTH_GOOGLE_CLIENT_SECRET=GOCSPX-...
```

## 3. Microsoft 365 (Exchange Online) i Outlook.com

Wszystko w [Microsoft Entra admin center](https://entra.microsoft.com/)
(dawniej Azure AD) na koncie z rolą co najmniej *Application Developer*
(zgoda administratora: *Cloud Application Administrator* lub *Global
Administrator*).

1. **Rejestracja aplikacji:** *Identity* → *Applications* → *App
   registrations* → *New registration*:
   - nazwa (np. „Silo poczta”);
   - *Supported account types* – od tego zależy `SILO_OAUTH_MICROSOFT_TENANT`:

     | Wybór w portalu | `SILO_OAUTH_MICROSOFT_TENANT` |
     |---|---|
     | Accounts in this organizational directory only (single tenant) | identyfikator katalogu (*Directory (tenant) ID*) lub domena, np. `example.onmicrosoft.com` |
     | Accounts in any organizational directory (multitenant) | `organizations` |
     | … and personal Microsoft accounts | `common` (domyślnie) |

   - *Redirect URI*: platforma **Web**, adres z punktu 1 dla Microsoft.
2. **Sekret:** *Certificates & secrets* → *New client secret*. Skopiuj
   **Value** (nie *Secret ID*) – widać ją tylko raz. Sekret ma datę ważności
   (maks. 24 miesiące): zapisz w kalendarzu jego wymianę; po wygaśnięciu nikt
   nie doda ani nie odnowi konta, a istniejące konta przestaną się łączyć.
3. **Uprawnienia:** *API permissions* → *Add a permission* → *Microsoft Graph*
   → *Delegated permissions*, zaznacz:
   - `IMAP.AccessAsUser.All`
   - `SMTP.Send`
   - `offline_access` (bez niego nie ma refresh tokenu)
   - `openid`, `email`
   Jeśli zasady katalogu nie pozwalają użytkownikom samodzielnie wyrażać zgody,
   kliknij **Grant admin consent for <organizacja>**.
4. *Overview*: skopiuj **Application (client) ID** (oraz *Directory (tenant)
   ID* dla aplikacji jednego katalogu).
5. **Exchange Online – SMTP AUTH.** W nowych dzierżawach uwierzytelnione
   wysyłanie SMTP (SMTP AUTH) jest domyślnie wyłączone. Włącz je dla skrzynek
   używanych w Silo (PowerShell, moduł ExchangeOnlineManagement):

   ```powershell
   Connect-ExchangeOnline
   # dla jednej skrzynki:
   Set-CASMailbox -Identity jan@example.com -SmtpClientAuthenticationDisabled $false
   # lub dla całej organizacji:
   Set-TransportConfig -SmtpClientAuthenticationDisabled $false
   ```

   W *Microsoft 365 admin center* to samo: *Users* → użytkownik → *Mail* →
   *Manage email apps* → **Authenticated SMTP** oraz **IMAP** zaznaczone.
   IMAP musi być włączony (`Set-CASMailbox -ImapEnabled $true`).
   Wyłączone *Security defaults* nie są potrzebne: XOAUTH2 to nowoczesne
   uwierzytelnianie.
6. Konta prywatne Outlook.com (`TENANT=common` lub `consumers`) nie były
   jeszcze sprawdzone z Silo (serwery `outlook.office365.com` /
   `smtp.office365.com`); traktuj je jako eksperymentalne.

Konfiguracja Silo:

```env
SILO_OAUTH_MICROSOFT_CLIENT_ID=00000000-0000-0000-0000-000000000000
SILO_OAUTH_MICROSOFT_CLIENT_SECRET=abc~...
SILO_OAUTH_MICROSOFT_TENANT=organizations
```

## 4. Uruchomienie i sprawdzenie

- Identyfikator i sekret dostawcy podaje się **razem**; tylko jeden z nich to
  błąd konfiguracji (Silo nie wystartuje i wypisze, czego brakuje).
- Zmienne dopisz do `.env` i uruchom `docker compose up -d` (kontener
  `silo-server` zostanie odtworzony z nową konfiguracją). Potem
  `GET /api/v1/meta` zwraca `"oauthProviders": ["google", "microsoft"]`
  (tylko skonfigurowanych) – silo-web pokazuje wtedy przyciski logowania przy
  dodawaniu konta.
- Zmienne `SILO_OAUTH_*_AUTH_URL`, `*_TOKEN_URL`, `*_USERINFO_URL` służą
  wyłącznie testom (atrapa dostawcy) – w produkcji ich nie ustawiaj.
- Silo łączy się z serwerami dostawców (`imap.gmail.com:993`,
  `smtp.gmail.com:465`, `outlook.office365.com:993`, `smtp.office365.com:587`)
  oraz z ich serwerami tokenów (`oauth2.googleapis.com`,
  `login.microsoftonline.com`) – zapora musi na to pozwalać.

## 5. Co widzi użytkownik i co się dzieje później

- Dodanie konta: „Zaloguj przez Google/Microsoft” → strona dostawcy → zgoda →
  powrót do Silo. Silo od razu sprawdza IMAP i SMTP; jeśli test się nie uda,
  konto nie powstaje (kod `account_test_failed`, np. wyłączony SMTP AUTH w
  Exchange).
- Wygaśnięcie lub odwołanie dostępu (zmiana hasła konta Google, odwołanie
  aplikacji w ustawieniach bezpieczeństwa konta, tryb *Testing* po 7 dniach,
  wygasły sekret klienta po stronie Microsoft): konto przechodzi w stan
  `auth_failed` z komunikatem „OAuth authorization expired; sign in again”.
  Synchronizacja stoi, wysyłka kończy się błędem; użytkownik klika „Zaloguj
  ponownie” przy koncie i loguje się **tym samym** adresem.
- Odwołanie dostępu Silo do skrzynki: konto Google → *Bezpieczeństwo* →
  *Połączenia z aplikacjami innych firm*; Microsoft: *myapps.microsoft.com* /
  *account.live.com/consent/Manage* albo administrator w Entra (*Enterprise
  applications* → aplikacja → *Users and groups* / usunięcie zgody).
  Usunięcie konta w Silo nie odwołuje zgody u dostawcy – zrób to tam.
- Kopie wysłanych wiadomości: Gmail i Exchange Online same zapisują wysłaną
  pocztę w folderze Wysłane, dlatego Silo domyślnie nie dokłada własnej kopii
  (`sentAppend` wyłączone).

## 6. Gmail bez trybu `provider=gmail`

Pełny tryb Gmaila (etykiety Gmaila jako etykiety Silo, wątki Gmaila) jest
planowany na 1.1. Do tego czasu konto Gmail działa w trybie ogólnym: Silo
widzi skrzynkę odbiorczą i foldery specjalne (`[Gmail]/Wszystkie`, Wysłane,
Wersje robocze, Kosz, Spam); ta sama wiadomość w Odebranych i we Wszystkich
jest w Silo jedną wiadomością; archiwizacja zdejmuje etykietę „Odebrane”
(kopia we „Wszystkich” zostaje). Etykiety założone w Gmailu nie są widoczne
w Silo, a wątki Silo buduje sam i mogą nieznacznie różnić się od wątków w
Gmailu.

## 7. Test ręczny po konfiguracji

Ani Gmail, ani Microsoft 365 nie były jeszcze sprawdzone na żywo (CI używa
atrapy dostawcy i Dovecota z `passdb oauth2`). Po pierwszej konfiguracji
przejdź scenariusz z [macierzy kompatybilności](../compat-matrix.md#2-serwery-pocztowe-imapsmtp)
(dodanie konta, initial sync, archiwizacja, etykieta, wysyłka, odpowiedź z
innego klienta, odwołanie dostępu) i zgłoś wynik, żeby uzupełnić macierz.

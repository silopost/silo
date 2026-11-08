# 0015. Wielojęzyczny UI: angielski jako język źródłowy, typowane słowniki, `settings.language`

- **Status:** Przyjęty
- **Data:** 2026-11-08
- **Dotyczy:** silo-server, silo-web, silo (dotyczy też przyszłego silo-mobile)

## Kontekst

`silo-web` miał jeden słownik `src/lib/i18n.ts` – typowany obiekt `t` z napisami i funkcjami (liczba mnoga przez własne `plural()` dla polskiego), wyłącznie po polsku, importowany w ~70 plikach; daty i liczby formatowane na sztywno w `pl-PL`, kilka napisów poza słownikiem (nazwy widoków systemowych, opisy skrótów, `index.html`, manifest PWA). Silo ma być wielojęzyczne: **domyślnie angielski**, inne języki wybierane w ustawieniach użytkownika, na start angielski i polski z kompletnym tłumaczeniem.

Ograniczenia z [planu](../../ARCHITECTURE_AND_PLAN.md): logika domenowa i stan użytkownika po stronie serwera, wspólne dla klientów (2.6); kontrakt OpenAPI przed UI ([ADR 0004](0004-huma-openapi-contract.md)); klient web ma działać bez przeładowania strony; `silo-mobile` ([ADR 0010](0010-react-native-for-silo-mobile.md)) ma własny `src/lib/i18n.ts` i powinien pokazać ten sam język co web.

## Decyzja

**Język jest ustawieniem użytkownika na serwerze, słowniki są w klientach.**

- **`silo-server`:** pole `language` w `Settings` (wymagane w odpowiedzi) i `SettingsPatch`, w JSONB `users.settings` bez migracji. Wartość to kod BCP 47 z zamkniętej listy obsługiwanych języków (`en`, `pl`; enum w OpenAPI); brak lub nieobsługiwana wartość w bazie czyta się jako `en`; nieznany kod w `PATCH /settings` → `422 invalid_setting`. Zmiana idzie zwykłą ścieżką `settings.updated`, więc inne sesje (web, mobile) przełączają się same. Serwer **nie tłumaczy** komunikatów: problem details zostają po angielsku, klient pokazuje własny tekst dla `code` (detail serwera tylko jako szczegół diagnostyczny, np. odpowiedź SMTP/IMAP).
- **`silo-web`, słowniki:** `src/lib/messages/en.ts` jest źródłem (`export type Messages = typeof en`), `messages/pl.ts` ma typ `Messages` – brak lub nadmiarowy klucz to błąd `tsc`; test porównuje drzewa kluczy także w mapach `Record<string, string>`, których typ nie sprawdza. Oba słowniki są bundlowane statycznie (dwa języki, kilkadziesiąt KB). Napisy z parametrami są funkcjami, liczba mnoga przez `Intl.PluralRules` (`lib/plural.ts`: `plural(locale, n, {one, few, many, other})`), wzorce dat date-fns są w słowniku (`dateFormats`), liczby i rozmiary przez `toLocaleString` bieżącego języka, porównania i `toLocaleLowerCase` z tym samym locale.
- **`silo-web`, runtime (`src/lib/i18n.ts`):** bieżący język w module (`getLocale`/`setLocale`, `useLocale()` przez `useSyncExternalStore`, `useT()`, `getT()` dla kodu poza Reactem). Istniejący import `t` zostaje: to `Proxy`, który każdy odczyt kieruje do słownika bieżącego języka, więc toasty, powiadomienia desktop i `format.ts` zawsze mówią aktualnym językiem bez zmian w ~70 plikach. Zasada: `t.*` czytamy w funkcjach, nigdy w stałych modułu (stałe z napisami są funkcjami albo getterami). Zmiana języka przemontowuje `RouterProvider` pod kluczem języka – wszystkie trasy renderują się od nowa bez przeładowania strony; cache TanStack Query i store'y zustand zostają.
- **Źródło języka w web:** przed zalogowaniem (ekran logowania, błędy sieci) ostatni język tej przeglądarki z `localStorage` (`silo.language`), a bez niego `en` – nie `navigator.language`, żeby nowy użytkownik zawsze widział domyślny angielski. Po zalogowaniu wygrywa `settings.language` (sesja, `GET /settings`, `settings.updated`, snapshot offline) i jest zapisywany w `localStorage`. Wybór w Ustawienia → Ogólne przełącza od razu (optymistycznie) i wysyła `PATCH {language}`; odrzucony PATCH przywraca poprzedni język. `document.documentElement.lang` i `document.title` idą za językiem.
- **Statyczne zasoby:** `index.html` (`lang="en"`) i manifest PWA są jednym plikiem dla wszystkich użytkowników, więc są po angielsku; service worker nie pokazuje tekstów.
- **`silo-mobile`:** czyta i zapisuje to samo `settings.language` (bez osobnej preferencji urządzenia), z tym samym domyślnym `en` i tą samą listą kodów; jego słowniki zostają w jego repo, z własnym typowaniem.

## Konsekwencje

- Jeden język użytkownika na wszystkich urządzeniach; nowy język = słownik w każdym kliencie + kod w enumie serwera (zmiana addytywna kontraktu, starsze klienty ignorują nieznane wartości dzięki fallbackowi do `en`).
- Brak nowej zależności; kompilator pilnuje kompletności tłumaczeń, a słowniki można przeglądać jak zwykły kod.
- Przemontowanie przy zmianie języka gubi stan lokalny komponentów (np. niezapisany podpis w edytorze, przewinięcie listy); drafty są bezpieczne (autosave serwera, stan okien w zustand). Zmiana języka jest rzadka, więc to akceptujemy.
- `Proxy` wymaga dyscypliny: napis odczytany w stałej modułu zamrozi się w języku z chwili importu – takie miejsca przerobiono na funkcje/gettery i opisano zasadę w `i18n.ts`.
- Tłumaczy się przez edycję plików TypeScript (bez platformy tłumaczeń, bez ICU MessageFormat); przy wielu językach może to wymagać ekstrakcji do JSON.

## Alternatywy

- **i18next / react-i18next (lub FormatJS):** dojrzałe, z ICU, ładowaniem leniwym i narzędziami dla tłumaczy, ale klucze jako napisy (typowanie przez generowane deklaracje), druga warstwa formatowania obok date-fns i przepisanie ~1000 wywołań `t.xxx`. Dla dwóch statycznych języków przewaga nie uzasadnia zależności; do rozważenia przy wielu językach i zewnętrznych tłumaczach.
- **Język tylko w `localStorage` klienta:** prostsze, ale każde urządzenie i klient (mobile) wybierałby osobno, wbrew zasadzie wspólnego stanu użytkownika na serwerze.
- **`Accept-Language` / `navigator.language`:** dobre jako podpowiedź, ale nie jako ustawienie – wymaganie to domyślny angielski i świadomy wybór w ustawieniach.
- **Tłumaczenie problem details na serwerze:** rozszerzyłoby kontrakt o negocjację języka; klienci i tak mapują stabilne `code` na własne teksty.
- **`useT()` w każdym komponencie zamiast `Proxy` + remount:** re-render bez remountu, ale zmiana ~70 plików i ryzyko pominięcia kodu poza Reactem (toasty, powiadomienia), który i tak potrzebuje `getT()`.

> Archiwum: notatki koordynatora `silo-mobile` skopiowane bez zmian z `silo-mobile/docs/NOTES-FOR-SILO.md` przy scaleniu do repo `silo` (2026-11-06; `silo-mobile` 0.1.0, 98 commitów na `main`, kontrakt `silo-server` `v0.4.0`). Naniesione: [ADR 0010](../adr/0010-react-native-for-silo-mobile.md) (pod nazwą `0010-react-native-for-silo-mobile.md`, status „Przyjęty”), plan (1, 2, 2.4, 2.6, 3.14, 5.1, 5.3, Faza 4m, Faza 6 z lukami kontraktu, decyzja odłożona 19), [macierz kompatybilności](../compat-matrix.md#silo-mobile) i README, sekcja „Stan: silo-mobile 0.1.0”. Odnośniki względne poniżej (`../README.md`) wskazują na repo `silo-mobile`.

# Notatki dla repozytorium silo

Propozycje i ustalenia z silo-mobile przeznaczone dla repozytorium `silo` (plan
`ARCHITECTURE_AND_PLAN.md`, `docs/adr/`). Koordynator scala je tam; po scaleniu ten plik może
zostać skrócony do odnośników. Stan na 2026-11-06: silo-mobile `0.1.0` (niewydane), kontrakt
silo-server `v0.4.0`.

Spis:

1. [Propozycja ADR 0010: React Native (Expo) dla silo-mobile](#propozycja-adr-0010-react-native-expo-dla-silo-mobile)
2. [Propozycje zmian w planie](#propozycje-zmian-w-planie)
3. [Luki kontraktu odkryte przez mobile](#luki-kontraktu-odkryte-przez-mobile)
4. [Decyzje stacku](#decyzje-stacku)
5. [Odstępstwa od parytetu](#odstępstwa-od-parytetu)

## Propozycja ADR 0010: React Native (Expo) dla silo-mobile

Do wpisania jako `docs/adr/0010-react-native-expo-for-silo-mobile.md` (numery 0008 i 0009 są
zajęte; wcześniejsza wersja tej notatki nosiła roboczy numer 0008). Rozstrzyga decyzję odłożoną
nr 19.

```markdown
# 0010. React Native (Expo) dla silo-mobile

- **Status:** Zaproponowany
- **Data:** 2026-11-06
- **Dotyczy:** silo-mobile, silo (plan)

## Kontekst

Plan (1, 2.6, Faza 6) przewiduje natywną aplikację mobilną `silo-mobile` z parytetem
operacji pocztowych względem silo-web i aplikacji Gmail na telefon, jako cienkiego klienta
tego samego `/api/v1` z uwierzytelnieniem bearer (ADR 0007). Technologia była decyzją
odłożoną nr 19 z kryteriami: koszt utrzymania dwóch platform, jakość generowania klienta z
OpenAPI, push w tle, offline storage, licencja i dystrybucja (F-Droid). Ograniczenia
projektu: mały zespół piszący już silo-web w TypeScript (React, TanStack Query,
openapi-typescript + openapi-fetch, TipTap), Android jako pierwszy cel, brak kluczy wydawcy i
projektu w sklepach, maszyny deweloperskie bez Android SDK.

## Decyzja

silo-mobile jest napisane w **React Native z Expo** (SDK 58, React Native 0.88, nowa
architektura, Hermes, expo-router), w TypeScript `strict`, z tym samym łańcuchem kontraktu co
silo-web.

- Typy z OpenAPI silo-server przez `openapi-typescript` (`npm run gen:api`, ref serwera w
  `package.json` `silo.serverRef`), żądania przez `openapi-fetch`, błędy jako `ApiError` nad
  RFC 9457, stan serwera w TanStack Query; job CI `api-contract` jak w silo-web. Bez ręcznie
  pisanych DTO (plan 2.6).
- Token bearer w `expo-secure-store` (Android Keystore / iOS Keychain).
- Zdarzenia: SSE przez strumieniowy `expo/fetch` z nagłówkami (bez tokenu w URL-u),
  fallback na `/events/poll`, tylko na pierwszym planie.
- Treść poczty w `react-native-webview` z sanityzowanego `GET /messages/{id}/html`; edytor
  compose to TipTap w WebView (`@10play/tentap-editor`), więc `bodyJson` jest zgodny z
  silo-web.
- Bez EAS: `expo prebuild` generuje zwykły projekt Gradle (continuous native generation), z
  którego APK buduje się lokalnie albo na serwerze F-Droid.
- Push (Faza 6) przez `expo-notifications` (FCM/APNs) lub UnifiedPush, powiązany z sesją
  bearer (`POST /devices`); offline cache przez `expo-sqlite` dla cache TanStack Query i delty
  `/changes` (Faza 5).

## Konsekwencje

Zyskujemy:

- Jedną bazę kodu dla Androida i iOS; parytet z aplikacją Gmail to długa lista ekranów, a
  dwie aplikacje natywne podwoiłyby koszt każdej funkcji.
- Te same narzędzia kontraktu co silo-web: zmiana kontraktu psuje oba klienty tak samo, a
  recenzenci silo-web mogą recenzować silo-mobile; pomocniki (mapowanie błędów, i18n, daty,
  adresy, `DraftSession`, `applyEvent`) są portowane, nie przepisywane.
- Testy bez SDK: Expo Go uruchamia aplikację na telefonie z `npx expo start`; CI dowodzi
  buildu przez `expo export --platform android` (bundel JavaScript) plus typecheck, lint i
  jest z msw. Wycinek mobilny powstał w całości na maszynie bez Android SDK (405 testów,
  bundel Hermes ~8 MB).
- Bezpieczne przechowywanie tokenu i swobodną dystrybucję (brak zależności od EAS).

Tracimy / ryzyka:

- Rozmiar aplikacji: Hermes + runtime React Native, APK release ~20–30 MB przed zasobami,
  więcej niż aplikacja natywna.
- HTML poczty i edytor żyją w WebView: przewijanie długiej wiadomości w natywnym widoku
  wątku, klawiatura i kursor w edytorze wymagają testów na urządzeniu (niesprawdzone).
- Coroczne aktualizacje SDK Expo są obowiązkowe (zmiany łamiące co wydanie); biblioteki UI
  (react-native-paper) potrafią nie nadążać za React Native (np. typ ref `TextInput`).
- Moduły spoza Expo Go wymagają development buildu (Android SDK).
- Zobowiązanie: aktualizować `silo.serverRef` i schemat przy każdym wydaniu serwera, które
  mobile ma wspierać.

## Alternatywy

- **Kotlin Multiplatform (Compose Multiplatform):** wspólna logika w Kotlinie, UI w Compose
  (na iOS mniej dojrzałe) albo osobno w SwiftUI. Odrzucone: drugi język i drugi łańcuch
  generowania z OpenAPI obok TypeScriptu silo-web, brak współdzielenia pomocników i
  edytora TipTap z web, wyższy koszt dla zespołu TS; zalety (wydajność, natywne UI) nie
  ważą wiele w kliencie, którego najcięższe widoki i tak są WebView (HTML poczty).
- **Flutter:** jedna baza kodu, dobre UI Material. Odrzucone: Dart i generator OpenAPI dla
  Darta poza łańcuchem web, edytor zgodny z `bodyJson` TipTap trzeba by i tak osadzić w
  WebView albo napisać od nowa, zero współdzielenia z silo-web, mniejsza zbieżność z
  wiedzą zespołu.
- **Natywne (Kotlin + Swift):** najlepsza integracja z platformą i najmniejszy rozmiar.
  Odrzucone: dwie bazy kodu i dwa klienty API do utrzymania przy długiej liście parytetu,
  podwójny koszt każdej funkcji; Android jest pierwszym celem, a iOS ma dojść bez
  przepisywania.
- **React Native bez Expo (bare):** pełna kontrola nad projektem natywnym. Odrzucone: wymaga
  Android SDK od pierwszego dnia i ręcznych aktualizacji projektów natywnych; Expo z
  `prebuild` daje to samo wyjście (projekt Gradle) na życzenie.
```

## Propozycje zmian w planie

Konkretne punkty per sekcja `ARCHITECTURE_AND_PLAN.md`.

### 1. Cel i zasady

- Akapit **Klienci**: zastąpić „technologia nieustalona, faza 6” przez: „`silo-mobile` (osobne
  repo, React Native/Expo – ADR 0010) ma od 2026-11-06 parytet funkcji pocztowych z silo-web 0.3.0
  (Fazy 3 i 4) i aplikacją Gmail w zakresie czytania, wyszukiwania, akcji, snooze, compose,
  załączników, draftów, wielu kont i ustawień; brakuje powiadomień push i offline cache (Faza 6),
  sprawdzone testami, nie na urządzeniu”.
- Zdanie o PWA bez zmian (PWA zostaje ścieżką pośrednią dla iOS i przeglądarki).

### 1.1 Czego Silo nie robi

Bez zmian (czat, Meet, Spaces poza zakresem także w mobile).

### 2. Rola repozytoriów (tabela)

Wiersz `silo-mobile` zamiast „(przyszłe, faza 6) | do ustalenia | …”:

| Repo          | Licencja | Zakres                                                                                                                                                        | Artefakt                                                                                                                   |
| ------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `silo-mobile` | AGPL-3.0 | aplikacja mobilna React Native/Expo (Android, iOS docelowo), konsumuje OpenAPI (`gen:api`), uwierzytelnienie bearer (ADR 0007); CI `.github/workflows/ci.yml` | APK/AAB przez `expo prebuild` + Gradle (lokalnie/CI) lub EAS; F-Droid – do ustalenia; dziś tylko bundel `expo export` w CI |

W 2.1 (struktura `silo`) dopisać do `docs/compat-matrix.md` kolumnę `silo-mobile` (dziś
`0.1.0` wymaga serwera ≥ 0.3.0, pełny zakres przy 0.4.0).

### 2.4 Wersjonowanie i kontrakt

- „SemVer niezależny dla `silo-server`, `silo-web` **i `silo-mobile`**”.
- Dodać punkt **Konsumpcja w `silo-mobile`**: jak w web – `openapi-typescript` →
  `src/api/schema.d.ts` z `api/openapi.yaml` tagu z `package.json` `silo.serverRef`
  (`npm run gen:api`, `-- --server-ref <ref>`, `-- --local <plik>`), klient `openapi-fetch`; job CI
  `api-contract` regeneruje schemat z silo-server na `serverRef` i failuje przy różnicy.
- Przy `GET /meta`: klient natywny nie może się „odświeżyć” jak SPA – patrz luka
  [minimalna wersja klienta mobilnego](#meta-i-flagi-funkcji).

### 2.6 Klienci API

- Potwierdzenie: reguła działa także w mobile – silo-mobile nie ma logiki domenowej (undo z
  `undoUntil`, autosave przez `PUT /drafts/{id}` z `version`, parser i historia wyszukiwania,
  presety snooze, wybudzanie i wysyłka zaplanowana, filtry – wszystko serwera).
- Dopisać, co klient mobilny robi lokalnie: prezentacja (motyw, gęstość do czasu `/settings`),
  gesty (swipe, zaznaczanie), preferencje urządzenia (akcje swipe, potwierdzenia, oznaczanie
  jako przeczytane po otwarciu, obrazy zdalne), bufor edytowanego draftu w pamięci, wyliczanie
  propozycji czasu zaplanowanej wysyłki (do czasu presetów serwera – luka w
  [Drafty i wysyłka](#drafty-i-wysyłka)).
- Dopisać wymaganie: **feature flags w `GET /meta`** (`Meta.features`) – klient, który musi
  działać ze starszym serwerem, nie powinien zgadywać funkcji z `serverVersion` (dziś mobile
  robi to w `src/lib/features.ts`).

### 3.14 Real-time: SSE

- Akapit **Klient natywny**: dopisać, że React Native nie ma `EventSource`; silo-mobile czyta
  strumień przez `fetch` ze strumieniowym ciałem (`expo/fetch`), z nagłówkami `Authorization`,
  `X-Silo-Client` i `Last-Event-ID` w nagłówku; polling co 15 s (jak w planie; silo-web 5 s);
  tylko na pierwszym planie (`AppState`).
- Heartbeat `: ping` co 25 s podnieść do **kontraktu** (opis operacji `/events`): mobile uznaje
  strumień cichy przez 60 s za martwy (sieci komórkowe zrywają bezczynne TCP bez FIN).
- Zaznaczyć, że do Fazy 5 nie ma `/changes`: po > 24 h offline klient dostaje `resync` i
  odświeża wszystkie zapytania.

### 5.1 / 5.3 Kontrakt API

Zbiorczo: [Luki kontraktu odkryte przez mobile](#luki-kontraktu-odkryte-przez-mobile). Najważniejsze
do wpisania w 5.1: `Meta.features`, `Meta.minMobileVersion` (lub `minClientVersions`),
`DELETE /sessions` (wszystkie poza bieżącą), schematy payloadów zdarzeń (`oneOf` po `type`),
podpisane krótkotrwałe URL-e miniatur i obrazów `cid:`, `POST /threads/snooze` zbiorczo; w 5.3:
`enum` kodów błędów w OpenAPI i nagłówek `Retry-After` w odpowiedziach 429/503.

### Roadmapa: nowa sekcja „Faza 4m: silo-mobile” (przed Fazą 5)

Proponowany tytuł: **„Faza 4m: `silo-mobile` – parytet poczty z web (Fazy 3–4) – wykonana
2026-11-06”** (alternatywnie oznaczenie „Faza 3.5/4.5” przy Fazach 3 i 4).

**Zakres wykonany:** repo `silo-mobile` (React Native/Expo, ADR 0010), klient wygenerowany z
`openapi.yaml` `v0.4.0`, logowanie bearer z tokenem w Keystore/Keychain, powłoka Gmaila
(szuflada, pasek wyszukiwania, przełącznik kont, FAB), lista wątków (FlashList, swipe,
zaznaczanie, banery synchronizacji), akcje z optimistic update i „Cofnij”, zdarzenia SSE z
pollingiem i cyklem `AppState`, widok wątku (HTML w WebView z CSP, obrazy `cid:`, załączniki,
odpowiedź), compose (TipTap, autosave z `version`, konflikty, załączniki z postępem, undo send),
ustawienia (urządzenie + `/settings`), konta i sesje, wyszukiwanie z podpowiedziami i chipami,
snooze, zaplanowana wysyłka, filtry, zarządzanie etykietami, miniatury, obrazy w treści;
bramkowanie funkcji wersją serwera (0.3.0 minimum, 0.4.0 pełny zakres).

**Definition of done – sprawdzone:**

- `npm run typecheck`, `npm run lint`, `npm run format:check` – czyste;
- `npm test` – 405 testów (jest-expo + msw, w tym testy tras na prawdziwym drzewie `app/`);
- `CI=1 npm run export:android` – bundel Hermes Androida się buduje;
- schemat zgodny z `silo-server` `v0.4.0` (`gen:api --local` bez różnic);
- smoke-test tylko-odczyt warstwy klienta na żywym API dev compose (`npm run smoke:api`, wynik w
  README silo-mobile).

**Definition of done – NIE sprawdzone:** uruchomienie na urządzeniu lub emulatorze (brak Android
SDK na maszynie deweloperskiej), gesty, klawiatura edytora, WebView i pickery na urządzeniu, iOS
w ogóle, e2e na żywym API poza smoke-testem (w szczególności widoczność operacji z mobile w web
bez odświeżenia – DoD Fazy 6 pkt 1 – nie była testowana automatycznie).

### Faza 6: 1.1 – zawęzić do tego, co zostało

- Zakres: usunąć z Fazy 6 to, co wykonała Faza 4m (repo, klient z OpenAPI, logowanie bearer,
  parytet operacji pocztowych, miniatury, drafty, wiele kont, ustawienia). Zostaje: **push**
  (`push_devices`, `POST/DELETE /devices`, job `push.notify`, bramka APNs/FCM lub UnifiedPush,
  `expo-notifications`, aktywna pozycja „Powiadomienia”), **offline cache** (`expo-sqlite`, ostatnie
  N wątków per etykieta + treść, kolejka akcji offline, wznowienie przez `/changes`),
  **dystrybucja** (podpisywanie, AAB/APK, F-Droid, sklepy), testy na urządzeniach (Android, iOS).
- DoD pkt 1 (widoczność w web bez odświeżenia) przenieść jako test e2e do wykonania na
  urządzeniu/emulatorze.

### Decyzje odłożone

- **19** – rozstrzygnięta: React Native/Expo, ADR 0010.
- **20** (bramka push) – nadal otwarta; wybór wpływa na `expo-notifications` (FCM/APNs) vs
  UnifiedPush w mobile.

## Luki kontraktu odkryte przez mobile

Priorytet: **blokuje** (funkcji nie da się zrobić bez zmiany API), **utrudnia** (obejście w
kliencie, ryzyko rozjazdu klientów), **kosmetyka** (dokumentacja, wygoda). Status: **otwarta**,
**otwarta, obejście w mobile**, **zamknięta** (przez kontrakt 0.4.0 lub przez mobile).

### Meta i flagi funkcji

- **Brak flag funkcji w `GET /meta`** (utrudnia; otwarta, obejście w mobile). Plan 5.1 je
  wymienia, `Meta` ma tylko wersje i limity; mobile decyduje po `serverVersion`
  (`hasServerFeature` względem 0.4.0, `dev` = najnowsza). Propozycja:
  `Meta.features: ["search", "snooze", "schedule", "settings", "filters", …]`.
- **Brak minimalnej wersji klienta mobilnego** (utrudnia; otwarta). `Meta.minWebVersion` istnieje,
  dla natywnych nic; stara aplikacja na telefonie nie wie, że serwer już jej nie wspiera.
  Propozycja: `minClientVersions: {web, mobile}` albo `minMobileVersion`.
- **Brak nazwy instancji** (kosmetyka; otwarta). Logowanie pokazuje tylko „Silo · serwer 0.3.0”;
  nazwa (np. `SILO_INSTANCE_NAME`) pozwoliłaby potwierdzić adres przed wpisaniem hasła przy kilku
  instancjach.
- **Brak domyślnego serwera poczty w `Meta`** (kosmetyka; otwarta). Plan 5.1 wymienia „domyślny
  serwer (host do wyświetlenia)”, kontrakt nie: bez `allowCustomServers` formularz „Dodaj konto”
  mówi tylko „domyślny serwer tej instancji”. Propozycja: `Meta.defaultImapHost`/`defaultSmtpHost`;
  przy okazji walidacja domeny adresu przed testem połączenia.
- **Limit kont nie jest w `Meta`** (kosmetyka; otwarta). `SILO_MAX_ACCOUNTS_PER_USER` widać dopiero
  jako 409 `account_limit_reached` po teście połączenia; `Meta.maxAccountsPerUser` pozwoliłby
  ukryć „Dodaj konto” przy limicie.
- **Limit całej wiadomości znany dopiero przy wysyłce** (utrudnia; otwarta).
  `Meta.maxAttachmentBytes` ogranicza jeden plik; suma wraca jako 413 `message_too_large` z
  `limit` po „Wyślij”. Propozycja: `Meta.maxMessageBytes`.
- **Brak palety kolorów etykiet** (kosmetyka; otwarta). `CreateLabelBody`/`UpdateLabelBody` mają
  `colorBg`/`colorText`, ale dozwolone pary są zaszyte w obu klientach (20 par Gmaila, silo-web
  `lib/labelColors.ts`, mobile `src/lib/labelColors.ts`); serwer przyjmuje każdą parę. Propozycja:
  `Meta.labelColors` albo `enum`, żeby serwer odrzucał nieczytelne pary.
- **Kolejność widoków systemowych po stronie klienta** (kosmetyka; otwarta). `Label.position`
  porządkuje etykiety użytkownika, a kolejność Gmaila (Odebrane, Oznaczone gwiazdką, Odłożone,
  Ważne, Wysłane, Zaplanowane, Wersje robocze, Wszystkie, Spam, Kosz) jest zaszyta w obu klientach
  (`SYSTEM_VIEWS`); mógłby ją podać plan 5.5.

### Ogólne cechy kontraktu

- **Kody błędów bez `enum`** (utrudnia; otwarta). `Problem.code` to wolny napis; kody, po których
  klienci się rozgałęziają (`invalid_credentials`, `rate_limited`, `upstream_imap_error`,
  `draft_version_conflict`, `send_in_progress`, `invalid_query`, `invalid_snooze`, `not_in_inbox`,
  `not_snoozed`, `invalid_setting`, `invalid_timezone`, `invalid_filter`, `invalid_label`, …) są
  tylko w planie 5.3 i kodzie serwera. Także: `PATCH /labels/{id}` deklaruje 409 bez kodu (mobile
  czyta to jako „nazwa zajęta”), `invalid_parent` tylko w prozie, `PATCH /accounts/{id}` nie
  deklaruje 502 (`upstream_imap_error`/`upstream_smtp_error`), `DELETE /accounts/{id}` deklaruje
  422 bez opisu kiedy. Propozycja: `enum` (lub przynajmniej `examples`) na `Problem.code` per
  operacja.
- **`Retry-After` niezadeklarowany** (kosmetyka; otwarta). Plan 5.3 obiecuje go na 429 i 503, ale
  żadna odpowiedź w `openapi.yaml` go nie deklaruje; klienci czytają go z konwencji.
- **`X-Silo-Client` deklarowany per operacja** (kosmetyka; otwarta). Jest tylko przy niektórych
  mutacjach; klienci natywni wysyłają go zawsze (identyfikuje instalację w `origin` zdarzeń).
  Propozycja: wspólny parametr albo notka w `securitySchemes`/`info`.
- **Brak ETag/304** (kosmetyka; otwarta – Faza 5 planuje `ETag`/`If-None-Match`).
  `/messages/{id}/html` i `/attachments/{id}` wysyłają `ETag` i `Cache-Control: immutable`, ale
  OpenAPI tego nie deklaruje, a serwer nie odpowiada 304 na `If-None-Match`; mobile polega na
  `staleTime: Infinity`.

### Uwierzytelnienie i sesje

- **Brak `DELETE /sessions` (wszystkie poza bieżącą)** (utrudnia; otwarta, obejście w mobile).
  „Wyloguj wszędzie” listuje `GET /sessions` i wysyła `DELETE /sessions/{id}` per sesja, potem
  `DELETE /session`; nieatomowe – sesja utworzona w międzyczasie przetrwa. Propozycja:
  `DELETE /sessions?except=current` lub `POST /sessions/revoke-all` (plan 3.15).
- **401 na strumieniu jest nieodróżnialny** (kosmetyka; otwarta). Mobile traktuje 401 z `/events`
  jako koniec sesji (jak REST); gdyby serwer odmawiał strumienia z innego powodu (limit połączeń),
  powinien to być osobny kod (429 z `Retry-After`), żeby klienci się nie wylogowywali.
- `SessionInfo` (`lastSeenAt`, `kind`, `clientName`) wystarcza liście sesji – brak luki.

### Zdarzenia

- **Payloady bez schematu** (utrudnia; otwarta). `/events` deklaruje `text/event-stream` jako napis,
  `PolledEvent.data` jako wolny obiekt; pola typów (`threadId`, `labelIds`, `unreadCount`, `intoId`,
  `labels[]`, `operationId`, `kind`, `threadIds`, `draftId`, `version`, `status`, `error`,
  `failedRecipients`, `state`, pola `SyncProgress`, `origin`) są tylko w planie 5.4 i serwerze; oba
  klienty czytają `Record<string, unknown>` ze strażnikami. Propozycja: schemat per typ (np.
  `ThreadUpdatedEvent`) w `oneOf` na `PolledEvent` z dyskryminatorem `type`.
- **Niepełna lista typów** (utrudnia; otwarta). Opis `/events` wymienia message.new … resync, ale
  nie `draft.updated` i `outbound.status`, których używają plan 5.4 i oba klienty. Propozycja:
  `enum` na `PolledEvent.type`.
- **Brak `label.created`** (kosmetyka; otwarta). `POST /labels` zwraca etykietę, autor odświeża
  `GET /labels`; inne urządzenia widzą nową etykietę dopiero przy odświeżeniu po `label.counts`.
- **`thread.updated` bez `scheduledAt`/`outboundId`** (kosmetyka; otwarta). Niesie `snoozedUntil`,
  ale zmiana zaplanowanej wysyłki z innego miejsca dociera do listy tylko przez `outbound.status` i
  odświeżenie.
- **`settings.updated` niesie tylko `{updatedAt, origin}`** (kosmetyka; otwarta). Każda inna sesja
  pobiera cały obiekt; nazwy zmienionych pól pozwoliłyby pominąć żądanie.
- **Heartbeat tylko w prozie** (utrudnia; otwarta). `: ping` co 25 s – mobile na nim polega (60 s
  ciszy = martwy strumień); interwał powinien być częścią kontraktu.
- **Brak wskazówki ponowienia** (kosmetyka; otwarta). Serwer mógłby wysyłać `retry:` w strumieniu
  (mobile i tak ma własny backoff) albo `Retry-After` na 503 z `/events` pod obciążeniem.
- **Brak delty po długim offline** (blokuje offline cache; otwarta – Faza 5 `GET /changes`). Po
  > 24 h retencji serwer odpowiada `resync`, a aplikacja unieważnia wszystkie zapytania; dziś
  > akceptowalne, kosztowne przy `expo-sqlite`.
- **Brak zbiorczych liczników nieprzeczytanych dla kont** (utrudnia; otwarta). Przełącznik kont
  pokazuje liczniki Odebranych każdego konta; jedyne źródło to `GET /labels?accountId=` per konto
  (N żądań przy otwarciu dialogu, cache 30 s). Propozycja: `Account.inboxUnread` w `GET /session` /
  `GET /accounts` albo `GET /labels/summary`; `label.counts` mogłoby wtedy odświeżać wszystkie
  konta, nie tylko otwarte.

### Treści i załączniki

- **Obrazy zdalne zostawione przez serwer** (utrudnia; otwarta, obejście w mobile).
  `/messages/{id}/html` zostawia zdalne obrazy, a jego CSP dopuszcza `https:`/`http:`; aplikacja
  ładuje HTML jako napis do WebView, więc nagłówek CSP nie działa – mobile blokuje obrazy własnym
  CSP w dokumencie do „Pokaż obrazy”. Propozycja (decyzja odłożona 4): `?blockRemote=1`
  przepisujące `src` po stronie serwera albo proxy obrazów ukrywające IP czytelnika.
- **Obrazy `cid:` wymagają nagłówka bearer** (utrudnia; otwarta, obejście w mobile). Wskazują na
  `/api/v1/attachments/{id}?inline=1`; WebView nie wysyła `Authorization` z podżądaniami, a token w
  URL-u jest zabroniony (ADR 0007), więc mobile pobiera je klientem API i wstawia jako data URI (do
  5 MB na wiadomość; większe zostają zepsute). Propozycja: podpisane krótkotrwałe URL-e albo
  wariant `inline=data` w `/messages/{id}/html`.
- **Miniatury wymagają nagłówka** (utrudnia; otwarta, obejście w mobile).
  `GET /attachments/{id}/thumbnail` nie da się podać jako URL `Image` bez nagłówka; mobile używa
  `Image` z `source.headers`, a natywny cache obrazów może trzymać miniatury po wylogowaniu.
  Propozycja: `thumbnailUrl` z wygasającym podpisem (bez tokenu sesji) – dowolny komponent i cache
  obrazów, tańszy podgląd.
- **Miniatury w 0.3.0** (zamknięta – kontrakt 0.4.0 `/attachments/{id}/thumbnail`).
- **Pobieranie: 503 bez opóźnienia** (kosmetyka; otwarta). Natywny downloader zwraca tylko status,
  więc mobile mówi „spróbuj za chwilę” bez wartości `Retry-After`.
- **Brak zdjęć nadawców** (kosmetyka; otwarta). Kontrakt nie ma URL-a awatara uczestnika ani
  endpointu (Gravatar/BIMI, zdjęcia kontaktów); oba klienty rysują inicjał. Propozycja:
  `Participant.avatarUrl` (serwowany przez Silo, cache, z ochroną prywatności) lub
  `GET /avatars/{email}`.
- **Kolejność i rola `Thread.participants` nieopisane** (kosmetyka; otwarta). Awatar wiersza to
  „ostatni nadawca, który nie jest użytkownikiem”; mobile zakłada kolejność wiadomości i że
  ostatni wpis nie-`me` wysłał najnowszą wiadomość; uczestnika tylko-odbiorcę nie da się odróżnić.
  Propozycja: opisać kolejność i dodać `Thread.lastSender` lub `Participant.role: from|to`.
- **Użytkownik to `"me"` w `Participant.email`** (kosmetyka; otwarta). Konwencja (klienci pokazują
  „ja”) wynika tylko z danych; schemat powinien ją opisać.
- **STARRED/UNREAD wątku są pochodne** (kosmetyka; otwarta). Po `POST /messages/modify` otwarty
  wątek ma gwiazdkę/nieprzeczytane, gdy ma je którakolwiek wiadomość – praktyka silo-web, nie
  kontrakt.

### Operacje na wątkach

- **Brak zbiorczego snooze** (utrudnia; otwarta, obejście w mobile). `POST/DELETE
/threads/{id}/snooze` biorą jeden wątek; zaznaczenie N wątków = N żądań, N operacji, N cofnięć,
  częściową porażkę skleja klient. Propozycja: `POST /threads/snooze {ids, until}` z jednym
  `OperationResult`, jak `/threads/modify`.
- **Brak operacji na wszystkich wątkach widoku** (utrudnia; otwarta). „Zaznacz wszystko” zaznacza
  tylko wczytane wiersze: `POST /threads/modify|trash|untrash|delete` biorą jawne id (a
  `IDsBody.ids` jest nullable bez opisu znaczenia null); oferowanie „przeczytane/nieprzeczytane”
  wymaga stanów wątków spoza wczytanych stron. Propozycja: selektor `{accountId, labelId, q}` w tych
  ciałach (po stronie serwera, jedna operacja, jedno cofnięcie).
- **Archiwizacja w widoku folderu lub etykiety nieokreślona** (utrudnia; otwarta). Plan 4.4 mówi,
  że `-<folder>` archiwizuje; klienci sami wybierają etykietę do zdjęcia: mobile wysyła `-INBOX` w
  widokach systemowych, `-<folder>` w widoku folderu i `-INBOX -<label>` w widoku etykiety (jak
  aplikacja Gmail), silo-web zawsze `-INBOX`. Propozycja: jedna reguła w planie albo operacja
  archiwizacji przyjmująca widok.
- **Przeniesienia zdejmują starą lokalizację niejawnie** (kosmetyka; otwarta). Przy
  `+<folder>`/`+INBOX`/`+SPAM` serwer zdejmuje poprzednią lokalizację (plan 4.4); opis `ModifyBody`
  tego nie mówi, a klienci odwzorowują to optymistycznie sami.
- **`undoUntil` null dla zmian samych flag** (kosmetyka; otwarta). Mają `operationId`, a
  `/operations/{id}/undo` je przyjmuje (plan 5.2); oba klienty pokazują „Cofnij” przy każdym
  `operationId` (4 s, gdy `undoUntil` null). Kontrakt mógłby podać, jak długo takie cofnięcie ma
  sens.
- **409 dwuznaczne** (kosmetyka; otwarta). Na undo `operation_not_undoable` i `undo_expired` to oba
  409 (klienci pokazują to samo „Tej operacji nie można już cofnąć.”); `PUT /drafts/{id}` i
  `POST /outbound/{id}/cancel` odpowiadają 409 `draft_version_conflict` / `send_in_progress`. Trzeba
  rozgałęziać po `code`, który nie ma `enum`.
- **`DELETE /threads/{id}/snooze` zwraca `SnoozeResult` z `operationId: null`** (kosmetyka;
  otwarta). Działa, ale osobny typ odpowiedzi (bez pól cofania) oszczędziłby klientom nulli.
- **Brak agregatu oczekujących operacji** (kosmetyka; otwarta). `Thread.pendingSync` jest per wątek,
  `SyncStatus.pendingOps` per konto; brak sumy (np. w `GET /session`) dla „N zmian oczekuje” i
  sposobu na listę oczekujących wątków. Propozycja: `pendingOps` na `Account` w `GET /session` i
  filtr `pending=true` w `GET /threads`.
- **`Indexing.done` to ułamek, a `ThreadList.approximate`/`indexing` są opcjonalne** (kosmetyka;
  otwarta). Klienci pokazują notki tylko, gdy są (`done < 1`).

### Drafty i wysyłka

- **`bodyJson` czy `bodyHtml` – co jest źródłem prawdy** (utrudnia; otwarta). `Draft.bodyJson` to
  dokument TipTap „zapisany jak podano”, `bodyHtml` idzie obok; kontrakt nie mówi, co wygrywa, gdy
  klient edytuje bez TipTap albo serwer wypełnia treść (prefill odpowiedzi przychodzi jako
  `bodyHtml` z `bodyJson: null`). Oba klienty wysyłają oba z TipTap, więc w praktyce się zgadzają.
  Propozycja: „zapis z `bodyJson: null` czyni `bodyHtml` autorytatywnym, a edytor web odbudowuje
  dokument z HTML”. Tu też: forma obrazu w treści w `bodyJson` (`src` = URL uploadu, atrybut `cid`)
  to konwencja silo-web, którą mobile powtarza – kontrakt powinien ją opisać lub orzec, że wygrywa
  `bodyHtml` z `cid:`.
- **Serwer nie wstawia podpisu** (utrudnia; otwarta). `POST /drafts` wypełnia odbiorców, temat i
  cytat, ale nie `Settings.signature`; silo-web wstawia go w kliencie (`withSignature`,
  `div.silo-signature`), mobile nie (plan 2.6). Nowy draft z telefonu nie ma podpisu, z przeglądarki
  ma. Propozycja: `POST /drafts` wstawia podpis do `bodyHtml` (nad cytatem, w tym samym
  `div.silo-signature`) albo udokumentowana reguła, że robią to klienci.
- **Podpis tylko jako HTML** (kosmetyka; otwarta). Telefon edytuje tekst; brak `signatureText` lub
  opisanego minimalnego podzbioru HTML, więc zapis z telefonu traci formatowanie silo-web.
- **Brak presetów czasu wysyłki** (kosmetyka; otwarta, obejście w mobile). Plan 3.9 wymienia „Jutro
  rano 8:00 / Jutro po południu 13:00 / Poniedziałek rano 8:00”; kontrakt nie ma endpointu (silo-web
  używa presetów snooze, bez popołudniowego). Mobile liczy je na urządzeniu jako propozycje.
  Propozycja: `GET /snooze/presets?scope=send` (lub `/send/presets`) w `settings.timezone`.
- **`SendResult.undoUntil` zaplanowanej wysyłki to czas wysyłki** (kosmetyka; otwarta, obejście w
  mobile). Snackbar do `undoUntil` wisiałby dniami; mobile pokazuje „Zaplanowano na … · Cofnij”
  najwyżej 10 s. Propozycja: osobne `scheduledAt` w `SendResult`.
- **Brak cofnięcia odrzucenia draftu** (kosmetyka; otwarta). `DELETE /drafts/{id}` jest
  ostateczne; Gmail ma „Cofnij” po „Odrzuć”, mobile pyta o potwierdzenie. Propozycja: miękkie
  usunięcie z `undoUntil` albo `POST /drafts/{id}/restore`.
- **„Od” niezmienne w istniejącym drafcie** (utrudnia; otwarta). `Draft.accountId` ustala
  `POST /drafts`, `UpdateDraftBody` nie ma konta; Gmail pozwala zmienić nadawcę w każdej chwili.
  Propozycja: opcjonalne `accountId` w `UpdateDraftBody` (serwer przenosi draft między kontami).
- **`/contacts/autocomplete` bez `accountId`** (kosmetyka; otwarta). Podpowiedzi mieszają adresy
  wszystkich kont użytkownika; warto dodać opcjonalne `accountId`.
- **Zaplanowana wysyłka w 0.3.0** (zamknięta – kontrakt 0.4.0 `SendDraftBody.sendAt`).
- Uwaga kliencka: pickery Androida nie zawsze podają rozmiar pliku; takie pliki pomijają kontrolę
  przed wysłaniem i polegają na 413 `upload_too_large`.

### Konta i ustawienia

- **`desktopNotifications` bez odpowiednika mobilnego** (blokuje powiadomienia; otwarta – Faza 6).
  To ustawienie przeglądarki; telefon potrzebuje push (`push_devices`, `POST/DELETE /devices` –
  plan 5.1 jeszcze bez implementacji). Propozycja: `Settings.pushNotifications` (per użytkownik) i
  stan per urządzenie w `POST/DELETE /devices`; mobile pokazuje `desktopNotifications` jako
  nieaktywną pozycję.
- **Nieudane operacje tylko jako licznik** (utrudnia; otwarta). `SyncStatus.deadOps` mówi ile, ale
  nie ma endpointu do listy (rodzaj, wątki, błąd) ani ponowienia/odrzucenia (plan 5.7 „Nieudane
  operacje”); ekran konta pokazuje „Nieudane operacje: N”.
- **`PATCH /accounts/{id}` nie zmienia `email`, `username` ani hostów; hasło nietestowane**
  (utrudnia; otwarta). Zmiana hosta IMAP u dostawcy = usunięcie i ponowne dodanie konta (utrata
  cache); nowe hasło jest zapisywane bez testu, błąd wychodzi przy `auth_failed`. Propozycja: test
  logowania IMAP przy zmianie hasła i 422 `account_test_failed` jak w `POST /accounts`.
- **`rebuild` odpowiada 501** (kosmetyka; otwarta). `Resync.mode` wymienia `rebuild`; mobile oferuje
  tylko `incremental` i `full`.
- **`Account.position` po usunięciu** (kosmetyka; otwarta). Pozycje nie są przenumerowywane
  (`/u/<n>` pozostałych kont działają, powstaje luka 0, 2); warto to zapisać w kontrakcie, bo oba
  klienty mapują `/u/<n>` na `position`.
- **`SyncStatus` bez hosta serwera poczty** (kosmetyka; otwarta). Baner backoffu nazywa serwer,
  klienci biorą `Account.imapHost` z sesji; pole `host` uczyniłoby baner samowystarczalnym.
- **`settings.activeAccountId` nie był zapisywany przez klientów** (zamknięta przez mobile).
  silo-mobile wysyła `PATCH /settings {activeAccountId}` przy zmianie konta (serwer 0.4.0); kontrakt
  mógłby powiedzieć, że klienci powinni.
- **Brak `/settings` w 0.3.0** (zamknięta – kontrakt 0.4.0). Gęstość, czas cofania wysyłki i podpis
  przeszły na `PATCH /settings`; `comfortable` mobile oferuje od 0.4.0.
- **Strefa urządzenia vs `settings.timezone`** (utrudnia; otwarta). Presety snooze liczone w
  `settings.timezone` (UTC, gdy brak), `SnoozePresets.timezone` mówi w której; mobile pokazuje czasy
  presetów w tej strefie, a wiersze, snackbary i wątek w strefie urządzenia, pickery używają zegara
  urządzenia. Przy różnych strefach użytkownik widzi dwa zegary; sesja nie sygnalizuje różnicy.
- **`conversationView` nieobsługiwany w mobile** (kosmetyka; otwarta). Aplikacja zawsze pokazuje
  wątki (API listuje wątki); albo API dostanie listę wiadomości (decyzja odłożona 15), albo pole
  należy opisać jako tylko-web.

### Etykiety, filtry, wyszukiwanie, snooze

- **Lista filtrów bez liczników** (kosmetyka; otwarta). `Filter` nie ma „ostatnio zastosowany” ani
  „dopasowano N” (tylko `matchedEstimate` przy apply).
- **`FilterActionsInput.forwardTo` to `string`, a `FilterActions.forwardTo` – `string | null`**
  (kosmetyka; otwarta). Wyczyszczenie przekazania = pominięcie pola w PUT (pełna zamiana) – działa,
  ale tylko implicite.
- **`showInList` ma trzy wartości, aplikacja Gmail – przełącznik** (kosmetyka; otwarta). Mobile
  przełącza `show`/`hide`; `show_if_unread` (z silo-web) pokazuje jako włączone z „Gdy są
  nieprzeczytane”.
- **`SnoozePreset.label` po angielsku** (kosmetyka; otwarta). Klienci tłumaczą po `key`
  (`later_today|tomorrow|this_weekend|next_week`); etykieta mogłaby iść za językiem użytkownika
  albo zniknąć z kontraktu.
- **`/search/suggest` z pustym `q`** (kosmetyka; otwarta). Zwraca 5 ostatnich zapytań (`kind:
history`), opisane tylko w opisie operacji; limit (5 z 50 przechowywanych) nie jest parametrem.
  Mobile nie trzyma lokalnej historii.

## Decyzje stacku

- **Expo SDK 58** (React Native 0.88, React 19.3, nowa architektura) z szablonu
  `blank-typescript`; trasy w `app/` (przewodnik szablonu sugeruje `src/app/`; kod nie-trasowy w
  `src/`). React Compiler (włączony w SDK 58) odrzuca ręczne `useMemo`, których nie potrafi
  zachować – ekrany polegają na kompilatorze, `useCallback` zostaje tylko tam, gdzie jest zachowany
  (callbacki wierszy).
- **Stan**: TanStack Query dla stanu serwera, zustand dla auth (status, adres serwera, token w
  pamięci), jak w silo-web; poświadczenia (token, adres, id instalacji) w `expo-secure-store`,
  preferencje urządzenia (nie tajne, nie serwerowe) w AsyncStorage przez `persist`.
- **react-native-paper 5** – komponenty Material 3 z minimalnym motywem; primary = niebieski Google,
  czerwień Gmaila jako `brand` (logotyp, akcenty), żeby kontrolki Paper nie robiły się czerwone.
  Typ ref `TextInput` Paper 5 nie pasuje do React Native 0.88 (`TextInputHandles` vs nowy typ
  instancji), więc łańcuch fokusu między polami pominięto; jeśli Paper znów nie nadąży za React
  Native, rozważyć własne komponenty na prymitywach. Quirk `Menu`: zamontowane z
  `visible={false}` po animacji ukrywania odmontowuje portal menu otwartego w międzyczasie – pasek
  zaznaczenia montuje `Menu` tylko, gdy jest otwarte. FAB: `AnimatedFAB` zwijany propem `extended`
  wg kierunku przewijania (8 dp).
- **Szuflada**: `Drawer` expo-router (dołączony fork szuflady react-navigation na
  `react-native-drawer-layout`, gesture-handler i reanimated 4), nie własny `Modal`: swipe od
  krawędzi, obsługa wstecz i stan szuflady z routera. Koszt w jest: mock reanimated nie ładuje się
  pod presetem Androida (zamiennik w `jest.config.js`), a fake timers `renderRouter` ograniczone do
  zegara, żeby msw działał.
- **Lista**: `@shopify/flash-list` 2.3.2 (pin SDK 58; v2 mierzy elementy sam, bez
  `estimatedItemSize`); w jest działa naprawdę z `jestSetup` biblioteki, nie przez atrapę
  `FlatList`.
- **Swipe**: własny pan (gesture-handler 3 `usePanGesture` + reanimated 4) zamiast
  `ReanimatedSwipeable`: swipe Gmaila wysuwa cały wiersz i działa po puszczeniu za progiem, a
  Swipeable biblioteki odsłania przyciski. Aktywacja po 16 dp w poziomie, porażka po 12 dp w pionie,
  ujemny hit slop 32 dp krawędzi szuflady (`swipeEdgeWidth`). Nietestowany w jest; do sprawdzenia
  na urządzeniu.
- **SSE**: własny parser nad strumieniowym `fetch`, bez `react-native-sse`. `expo/fetch` (globalny
  `fetch` SDK 58, o ile nie ustawiono `EXPO_PUBLIC_USE_RN_FETCH`) ma `Response.body` jako
  `ReadableStream` zasilany natywnie (OkHttp / URLSession); wszystkie nagłówki pod kontrolą
  aplikacji, brak ryzyka modułu natywnego, jest testuje prawdziwy czytnik na strumieniu msw.
  `react-native-sse` (XHR, też z nagłówkami) byłby fallbackiem; z fetchem React Native (bez
  strumienia) próba się nie udaje i aplikacja przechodzi na polling. Ponowienia decyduje aplikacja,
  nie transport.
- **Arkusze**: Paper `Modal` (`src/components/BottomSheet.tsx`), bez przeciągania – `@gorhom/bottom-sheet`
  dodałby zależność od natywnych gestów, której jest-expo nie uruchomi, dla rzadko używanego gestu.
- **Edytor compose**: `@10play/tentap-editor` 1.1.0 (TipTap 3 w istniejącym `react-native-webview`);
  plan B (`TextInput`) niepotrzebny. Dlaczego: compose silo-web to TipTap, drafty trzymają `bodyJson`
  jako TipTap JSON, więc draft przechodzi między telefonem i przeglądarką z formatowaniem, cytatem i
  linkami, a `PUT /drafts/{id}` jest tym samym żądaniem. Koszt: `npx expo install` dodał 60 pakietów
  (TipTap 3, ProseMirror, lodash); gotowa strona edytora (`editorHtml`) to ok. 600 KB JavaScriptu w
  bundlu (bundel Hermes Androida 8,2 MB z nim); bez config pluginu i zmian Babel/Metro; mały moduł
  natywny `TenTapKeyboard` (tylko własne klawiatury) jest autolinkowany i opcjonalny. Integracja
  zajęła znacznie mniej niż szacowane 3–5 dni, ale klawiatura, kursor i pasek na urządzeniu są
  niesprawdzone. W jest – fałszywy mostek trzymający HTML. Typ `theme` `useEditorBridge` przekracza
  głębokość instancjacji TS z `darkEditorTheme`, więc jest rzutowany. Ryzyko schematu: starter kit
  ma więcej rozszerzeń niż edytor web (lista zadań, wyróżnienie, kolor, kod); pasek mobile
  udostępnia tylko to, co web (B, I, U, listy, link, cytat), ale wklejony tekst sformatowany może
  wnieść znaczniki, które web odrzuci.
- **WebView treści**: JavaScript włączony tylko dla skryptu wysokości (react-native-webview na
  Androidzie nie ma natywnej automatycznej wysokości), CSP dokumentu zostawia `script-src
'unsafe-inline'`; `evaluateJavascript` Androida prawdopodobnie nie podlega CSP strony, więc
  `script-src 'none'` może zadziałać – do sprawdzenia na urządzeniu.
- **Miniatury**: React Native `Image` z `source.headers` (Authorization, X-Silo-Client), bez nowego
  modułu natywnego (`expo-image` niepotrzebne); token nigdy w URL-u.
- **Picker daty**: `@react-native-community/datetimepicker` (w Expo Go) przez
  `DateTimePickerAndroid.open` – dialog daty, potem godziny, jak w Gmailu; iOS wymaga komponentu
  inline.
- **ESLint**: `eslint-config-expo` 58 (flat config) na ESLint 9 zamiast ręcznego zestawu
  typescript-eslint + react-hooks z silo-web – preset łączy te reguły i rozwiązuje rozszerzenia
  platform; jego wtyczki (`eslint-plugin-react`, `eslint-plugin-import`) akceptują ESLint do 9, więc
  mobile zostaje na 9, a silo-web używa 10.
- **Testy**: `jest-expo` (preset Androida), `@testing-library/react-native` 14 (asynchroniczne
  `render` i `fireEvent`), msw 3. jest-expo podmienia `fetch` na natywny Expo, który nie przenosi
  ciał msw; własne środowisko zapisuje klasy fetch Node i je przywraca (`jest.environment.js`,
  `jest.polyfills.js`). `undici` odrzucone: jego ciała wiszą na polyfillu web-streams jest-expo.

## Odstępstwa od parytetu

Pełna lista (względem aplikacji Gmail i silo-web): [README – „Odstępstwa od
parytetu”](../README.md#odstępstwa-od-parytetu). Przyczyny po stronie kontraktu są w lukach
powyżej.

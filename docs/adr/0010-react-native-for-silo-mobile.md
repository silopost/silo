# 0010. React Native (Expo) dla silo-mobile

- **Status:** Przyjęty
- **Data:** 2026-11-06
- **Dotyczy:** silo-mobile, silo

## Kontekst

Użytkownik zdecydował, że Silo dostaje **natywną aplikację mobilną** `silo-mobile` z parytetem operacji pocztowych względem `silo-web` i aplikacji Gmail na telefon, jako cienkiego klienta tego samego `/api/v1` z uwierzytelnieniem bearer ([plan 1, 2.6, Faza 6](../../ARCHITECTURE_AND_PLAN.md#26-klienci-api), [ADR 0007](0007-bearer-tokens-for-native-clients.md)). Technologia była decyzją odłożoną nr 19 z kryteriami: koszt utrzymania dwóch platform, jakość generowania klienta z OpenAPI, push w tle, offline storage, licencja i dystrybucja (F-Droid).

Ograniczenia projektu: mały zespół piszący już `silo-web` w TypeScript (React, TanStack Query, `openapi-typescript` + `openapi-fetch`, TipTap), Android jako pierwszy cel, brak kluczy wydawcy i projektu w sklepach, maszyny deweloperskie bez Android SDK.

## Decyzja

`silo-mobile` jest napisane w **React Native z Expo** (SDK 58, React Native 0.88, nowa architektura, Hermes, expo-router), w TypeScript `strict`, z UI w **react-native-paper** (Material 3) i tym samym łańcuchem kontraktu co `silo-web`.

- Typy z OpenAPI `silo-server` przez `openapi-typescript` (`npm run gen:api`, ref serwera w `package.json` `silo.serverRef`), żądania przez `openapi-fetch` z **tym samym schematem co web**, błędy jako `ApiError` nad RFC 9457, stan serwera w **TanStack Query**; job CI `api-contract` jak w `silo-web`. Bez ręcznie pisanych DTO ([plan 2.6](../../ARCHITECTURE_AND_PLAN.md#26-klienci-api)).
- Token bearer w `expo-secure-store` (Android Keystore / iOS Keychain); tokenu nigdy w URL-u.
- Zdarzenia: **SSE przez strumieniowy `fetch`** (`expo/fetch`, `Response.body` jako `ReadableStream`) z nagłówkami `Authorization`, `X-Silo-Client` i `Last-Event-ID`, własny parser; fallback na `/events/poll`; tylko na pierwszym planie (`AppState`).
- Treść poczty w `react-native-webview` z sanityzowanego `GET /messages/{id}/html`; edytor compose to TipTap w WebView (`@10play/tentap-editor`), więc `bodyJson` jest zgodny z `silo-web`.
- Bez EAS: `expo prebuild` generuje zwykły projekt Gradle (continuous native generation), z którego APK buduje się lokalnie albo na serwerze F-Droid.
- Push (Faza 6) przez `expo-notifications` (FCM/APNs) lub UnifiedPush, powiązany z sesją bearer (`POST /devices`); offline cache przez `expo-sqlite` dla cache TanStack Query i delty `/changes` (Faza 5).

## Konsekwencje

Zyskujemy:

- Jedną bazę kodu dla Androida i iOS; parytet z aplikacją Gmail to długa lista ekranów, a dwie aplikacje natywne podwoiłyby koszt każdej funkcji.
- Te same narzędzia kontraktu co `silo-web`: zmiana kontraktu psuje oba klienty tak samo, a recenzenci `silo-web` mogą recenzować `silo-mobile`; pomocniki (mapowanie błędów, i18n, daty, adresy, `DraftSession`, `applyEvent`) są portowane, nie przepisywane.
- Testy bez SDK: Expo Go uruchamia aplikację na telefonie z `npx expo start`; CI dowodzi buildu przez `expo export --platform android` (bundel JavaScript) plus typecheck, lint i jest z msw. Wersja 0.1.0 powstała w całości na maszynie bez Android SDK (405 testów, bundel Hermes ok. 8 MB).
- Bezpieczne przechowywanie tokenu i swobodną dystrybucję (brak zależności od EAS).

Tracimy / ryzyka:

- Rozmiar aplikacji: Hermes + runtime React Native, APK release ok. 20–30 MB przed zasobami, więcej niż aplikacja natywna.
- HTML poczty i edytor żyją w WebView: przewijanie długiej wiadomości w natywnym widoku wątku, klawiatura i kursor w edytorze wymagają testów na urządzeniu (niesprawdzone w 0.1.0).
- Coroczne aktualizacje SDK Expo są obowiązkowe (zmiany łamiące co wydanie); biblioteki UI (react-native-paper) potrafią nie nadążać za React Native (np. typ ref `TextInput` w Paper 5 vs React Native 0.88).
- Moduły spoza Expo Go wymagają development buildu (Android SDK).
- Zobowiązanie: aktualizować `silo.serverRef` i schemat przy każdym wydaniu serwera, które mobile ma wspierać; wpis w [macierzy kompatybilności](../compat-matrix.md).

## Alternatywy

- **Kotlin Multiplatform (Compose Multiplatform):** wspólna logika w Kotlinie, UI w Compose (na iOS mniej dojrzałe) albo osobno w SwiftUI. Odrzucone: drugi język i drugi łańcuch generowania z OpenAPI obok TypeScriptu `silo-web`, brak współdzielenia pomocników i edytora TipTap z web, wyższy koszt dla zespołu TS; zalety (wydajność, natywne UI) nie ważą wiele w kliencie, którego najcięższe widoki i tak są WebView (HTML poczty).
- **Flutter:** jedna baza kodu, dobre UI Material. Odrzucone: Dart i generator OpenAPI dla Darta poza łańcuchem web, edytor zgodny z `bodyJson` TipTap trzeba by i tak osadzić w WebView albo napisać od nowa, zero współdzielenia z `silo-web`, mniejsza zbieżność z wiedzą zespołu.
- **Natywne (Kotlin + Swift):** najlepsza integracja z platformą i najmniejszy rozmiar. Odrzucone: dwie bazy kodu i dwa klienty API do utrzymania przy długiej liście parytetu, podwójny koszt każdej funkcji; Android jest pierwszym celem, a iOS ma dojść bez przepisywania.
- **React Native bez Expo (bare):** pełna kontrola nad projektem natywnym. Odrzucone: wymaga Android SDK od pierwszego dnia i ręcznych aktualizacji projektów natywnych; Expo z `prebuild` daje to samo wyjście (projekt Gradle) na życzenie.

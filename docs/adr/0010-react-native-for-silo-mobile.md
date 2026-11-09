# 0010. React Native (Expo) for silo-mobile

- **Status:** Accepted
- **Date:** 2026-11-06
- **Applies to:** silo-mobile, silo

## Context

The user decided that Silo gets a **native mobile app** `silo-mobile` with parity of mail operations with `silo-web` and the Gmail phone app, as a thin client of the same `/api/v1` with bearer authentication ([ADR 0007](0007-bearer-tokens-for-native-clients.md)); like every API client, it keeps no domain logic of its own and uses types generated from the OpenAPI contract. The technology was a postponed decision with these criteria: the cost of maintaining two platforms, the quality of client generation from OpenAPI, background push, offline storage, licensing and distribution (F-Droid).

Project constraints: a small team already writing `silo-web` in TypeScript (React, TanStack Query, `openapi-typescript` + `openapi-fetch`, TipTap), Android as the first target, no publisher keys or store projects, development machines without the Android SDK.

## Decision

`silo-mobile` is written in **React Native with Expo** (SDK 58, React Native 0.88, the new architecture, Hermes, expo-router), in `strict` TypeScript, with the UI in **react-native-paper** (Material 3) and the same contract chain as `silo-web`.

- Types from the `silo-server` OpenAPI through `openapi-typescript` (`npm run gen:api`, the server ref in `package.json` `silo.serverRef`), requests through `openapi-fetch` with **the same schema as the web client**, errors as `ApiError` on top of RFC 9457, server state in **TanStack Query**; an `api-contract` CI job as in `silo-web`. No hand-written DTOs.
- The bearer token in `expo-secure-store` (Android Keystore / iOS Keychain); never a token in a URL.
- Events: **SSE over a streaming `fetch`** (`expo/fetch`, `Response.body` as a `ReadableStream`) with the `Authorization`, `X-Silo-Client` and `Last-Event-ID` headers and our own parser; fallback to `/events/poll`; only in the foreground (`AppState`).
- Mail content in `react-native-webview` from the sanitized `GET /messages/{id}/html`; the compose editor is TipTap in a WebView (`@10play/tentap-editor`), so `bodyJson` is compatible with `silo-web`.
- No EAS: `expo prebuild` generates a regular Gradle project (continuous native generation), from which the APK is built locally or on the F-Droid server.
- Push (phase 6) through `expo-notifications` (FCM/APNs) or UnifiedPush, tied to the bearer session (`POST /devices`); an offline cache through `expo-sqlite` for the TanStack Query cache and the `/changes` delta (phase 5).

## Consequences

We gain:

- One code base for Android and iOS; parity with the Gmail app is a long list of screens, and two native apps would double the cost of every feature.
- The same contract tooling as `silo-web`: a contract change breaks both clients in the same way, and `silo-web` reviewers can review `silo-mobile`; helpers (error mapping, i18n, dates, addresses, `DraftSession`, `applyEvent`) are ported, not rewritten.
- Tests without the SDK: Expo Go runs the app on a phone with `npx expo start`; CI proves the build with `expo export --platform android` (the JavaScript bundle) plus typecheck, lint and jest with msw. Version 0.1.0 was written entirely on a machine without the Android SDK (405 tests, a Hermes bundle of about 8 MB).
- Secure token storage and free distribution (no dependency on EAS).

We lose / risks:

- App size: Hermes + the React Native runtime, a release APK of about 20–30 MB before assets, more than a native app.
- Mail HTML and the editor live in a WebView: scrolling a long message in the native thread view, and the keyboard and cursor in the editor, need testing on a device (not checked in 0.1.0).
- Yearly Expo SDK upgrades are mandatory (breaking changes in every release); UI libraries (react-native-paper) can lag behind React Native (e.g. the `TextInput` ref type in Paper 5 vs React Native 0.88).
- Modules outside Expo Go require a development build (Android SDK).
- Commitment: update `silo.serverRef` and the schema with every server release that mobile is to support; an entry in the [compatibility matrix](../compat-matrix.md).

## Alternatives

- **Kotlin Multiplatform (Compose Multiplatform):** shared logic in Kotlin, UI in Compose (less mature on iOS) or separately in SwiftUI. Rejected: a second language and a second OpenAPI generation chain next to the TypeScript of `silo-web`, no sharing of helpers or the TipTap editor with the web client, a higher cost for a TS team; the advantages (performance, native UI) carry little weight in a client whose heaviest views are WebViews anyway (mail HTML).
- **Flutter:** one code base, good Material UI. Rejected: Dart and an OpenAPI generator for Dart outside the web chain; an editor compatible with TipTap's `bodyJson` would have to be embedded in a WebView anyway or written from scratch; zero sharing with `silo-web`, and less overlap with the team's knowledge.
- **Native (Kotlin + Swift):** the best platform integration and the smallest size. Rejected: two code bases and two API clients to maintain for a long parity list, a double cost for every feature; Android is the first target, and iOS should follow without a rewrite.
- **React Native without Expo (bare):** full control over the native project. Rejected: requires the Android SDK from day one and manual upgrades of the native projects; Expo with `prebuild` gives the same output (a Gradle project) on demand.

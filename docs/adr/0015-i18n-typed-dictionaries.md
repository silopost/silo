# 0015. Multilingual UI: English as the source language, typed dictionaries, `settings.language`

- **Status:** Accepted
- **Date:** 2026-11-08
- **Applies to:** silo-server, silo-web, silo (also applies to the future silo-mobile)

## Context

`silo-web` had a single dictionary `src/lib/i18n.ts` – a typed object `t` with strings and functions (plurals through a custom `plural()` for Polish), Polish only, imported in ~70 files; dates and numbers were hard-coded to `pl-PL`, and a few strings lived outside the dictionary (names of system views, shortcut descriptions, `index.html`, the PWA manifest). Silo is to be multilingual: **English by default**, other languages selectable in the user's settings, starting with English and Polish with a complete translation.

Constraints: domain logic and user state live on the server and are shared by the clients; the OpenAPI contract comes before the UI ([ADR 0004](0004-huma-openapi-contract.md)); the web client must work without a page reload; `silo-mobile` ([ADR 0010](0010-react-native-for-silo-mobile.md)) has its own `src/lib/i18n.ts` and should show the same language as the web client.

## Decision

**The language is a user setting on the server; the dictionaries live in the clients.**

- **`silo-server`:** a `language` field in `Settings` (required in the response) and `SettingsPatch`, in the `users.settings` JSONB, without a migration. The value is a BCP 47 code from a closed list of supported languages (`en`, `pl`; an enum in OpenAPI); a missing or unsupported value in the database reads as `en`; an unknown code in `PATCH /settings` → `422 invalid_setting`. The change goes through the regular `settings.updated` path, so other sessions (web, mobile) switch on their own. The server **does not translate** messages: problem details stay in English, and the client shows its own text for the `code` (the server's detail only as a diagnostic detail, e.g. an SMTP/IMAP response).
- **`silo-web`, dictionaries:** `src/lib/messages/en.ts` is the source (`export type Messages = typeof en`), `messages/pl.ts` has the type `Messages` – a missing or extra key is a `tsc` error; a test compares the key trees, also in `Record<string, string>` maps that the type does not check. Both dictionaries are bundled statically (two languages, a few dozen KB). Strings with parameters are functions, plurals go through `Intl.PluralRules` (`lib/plural.ts`: `plural(locale, n, {one, few, many, other})`), date-fns date patterns are in the dictionary (`dateFormats`), numbers and sizes go through `toLocaleString` of the current language, and comparisons and `toLocaleLowerCase` use the same locale.
- **`silo-web`, runtime (`src/lib/i18n.ts`):** the current language lives in the module (`getLocale`/`setLocale`, `useLocale()` through `useSyncExternalStore`, `useT()`, `getT()` for code outside React). The existing `t` import stays: it is a `Proxy` that routes every read to the dictionary of the current language, so toasts, desktop notifications and `format.ts` always speak the current language without changes in ~70 files. Rule: `t.*` is read inside functions, never in module constants (constants with strings are functions or getters). A language change remounts `RouterProvider` under a language key – all routes render again without a page reload; the TanStack Query cache and the zustand stores remain.
- **Source of the language in the web client:** before sign-in (the sign-in screen, network errors) the last language of this browser from `localStorage` (`silo.language`), and without it `en` – not `navigator.language`, so that a new user always sees the default English. After sign-in `settings.language` wins (session, `GET /settings`, `settings.updated`, offline snapshot) and is saved to `localStorage`. Choosing it in Settings → General switches immediately (optimistically) and sends `PATCH {language}`; a rejected PATCH restores the previous language. `document.documentElement.lang` and `document.title` follow the language.
- **Static assets:** `index.html` (`lang="en"`) and the PWA manifest are a single file for all users, so they are in English; the service worker shows no text.
- **`silo-mobile`:** reads and writes the same `settings.language` (no separate device preference), with the same default `en` and the same list of codes; its dictionaries stay in its repository, with their own typing.

## Consequences

- One user language on all devices; a new language = a dictionary in every client + a code in the server's enum (an additive contract change; older clients ignore unknown values thanks to the fallback to `en`).
- No new dependency; the compiler enforces complete translations, and the dictionaries can be reviewed like regular code.
- Remounting on a language change loses local component state (e.g. an unsaved signature in the editor, the list scroll position); drafts are safe (server autosave, window state in zustand). Language changes are rare, so we accept this.
- The `Proxy` requires discipline: a string read in a module constant freezes in the language at import time – such places were turned into functions/getters, and the rule is documented in `i18n.ts`.
- Translation is done by editing TypeScript files (no translation platform, no ICU MessageFormat); with many languages this may require extraction to JSON.

## Alternatives

- **i18next / react-i18next (or FormatJS):** mature, with ICU, lazy loading and tools for translators, but keys as strings (typing through generated declarations), a second formatting layer next to date-fns and a rewrite of ~1000 `t.xxx` calls. For two static languages the advantage does not justify the dependency; to be reconsidered with many languages and external translators.
- **The language only in the client's `localStorage`:** simpler, but every device and client (mobile) would choose separately, contrary to the principle of shared user state on the server.
- **`Accept-Language` / `navigator.language`:** good as a hint, but not as a setting – the requirement is English by default and a deliberate choice in the settings.
- **Translating problem details on the server:** would extend the contract with language negotiation; clients map the stable `code` to their own texts anyway.
- **`useT()` in every component instead of `Proxy` + remount:** re-renders without a remount, but a change in ~70 files and a risk of missing code outside React (toasts, notifications), which needs `getT()` anyway.

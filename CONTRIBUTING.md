# Współtworzenie Silo

Ten dokument jest **głównym źródłem konwencji** dla wszystkich trzech repozytoriów: `silo`, `silo-server`, `silo-web`. Pozostałe repo odsyłają tutaj.

## Język

- Kod, komentarze, nazwy, komunikaty commitów, tytuły i opisy PR: **angielski**.
- Dokumentacja (README, ADR, docs, plan): **polski**.

## Conventional Commits

Format: `<type>(<scope>): <opis w trybie rozkazującym, małe litery, bez kropki>`

Typy: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
Scope (opcjonalny) to obszar kodu, np. `sync`, `api`, `ops`, `search`, `ui`, `compose`.
Zmiana łamiąca: `!` po typie/scope lub stopka `BREAKING CHANGE:`.

Przykłady:

```
feat(sync): add QRESYNC incremental folder sync
fix(api): return 409 on stale thread modification
docs: add ADR for job queue in postgres
build(compose): pin postgres image to 17
feat(ui)!: replace label picker with command palette
```

## Workflow PR

1. Gałąź z `main` (`feat/...`, `fix/...`); commity zgodne z Conventional Commits.
2. Pull request do `main`; opis: co i dlaczego, jak przetestowano.
3. Zielone CI jest warunkiem merge. `main` ma branch protection: wymagany PR + zielone CI, brak force-push.
4. Preferowany squash merge z tytułem w formacie Conventional Commits (z niego powstaje changelog).

## `.editorconfig`

Wspólny plik jest w repo `silo`; kopiujemy go bez zmian do `silo-server` i `silo-web`. Zasady: UTF-8, LF, końcowy newline, tab dla Go, 2 spacje dla yaml/json/md/ts/tsx.

## Wersjonowanie

SemVer **niezależny per repo** ([plan 2.4](ARCHITECTURE_AND_PLAN.md#24-wersjonowanie-i-kontrakt)): `silo-server` i `silo-web` mają własne wersje, `silo` ma wersję dystrybucji (zestaw przypiętych tagów obrazów). Kontrakt między nimi to OpenAPI generowany z backendu; przed 1.0 zmiany łamiące opisujemy w [docs/compat-matrix.md](docs/compat-matrix.md).

## ADR

Zmiana decyzji architektonicznej (lub odstępstwo od Gmail-parity) wymaga ADR w `docs/adr/` w repo `silo`:

1. Skopiuj [`docs/adr/0000-template.md`](docs/adr/0000-template.md) do `NNNN-krotki-tytul.md` (kolejny numer).
2. Wypełnij Status, Kontekst, Decyzja, Konsekwencje, Alternatywy.
3. Dodaj wpis do [`docs/adr/README.md`](docs/adr/README.md).
4. Zmiana wcześniejszej decyzji = nowy ADR ze statusem „Zastępuje NNNN”; stary dostaje „Zastąpiony przez NNNN”.

## Dev

Szybki start w [README](README.md). Przed PR uruchom lokalne testy/lint danego repo (opisane w jego README).

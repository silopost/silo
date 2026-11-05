# 0004. huma + chi i OpenAPI generowany z kodu

- **Status:** Przyjęty
- **Data:** 2026-11-05
- **Dotyczy:** silo-server, silo-web

## Kontekst

`silo-server` i `silo-web` są w osobnych repozytoriach z niezależnym SemVer ([plan 2.4](../../ARCHITECTURE_AND_PLAN.md#24-wersjonowanie-i-kontrakt)). Potrzebny jest jeden, wiarygodny kontrakt API. Ręcznie utrzymywana specyfikacja obok kodu zawsze się rozjeżdża.

## Decyzja

- Backend: `github.com/danielgtaylor/huma/v2` z adapterem `humachi` nad routerem `chi`. chi zostaje routerem i miejscem middleware (auth, CSRF, logowanie, recover).
- **OpenAPI 3.1 jest generowany ze structów Go**; huma waliduje też requesty. `cmd/silo-openapi` zapisuje `api/openapi.yaml` (bez DB), plik jest commitowany, a CI failuje, gdy wygenerowany plik różni się od zacommitowanego.
- Frontend: `openapi-typescript` generuje `src/api/schema.d.ts` z `openapi.yaml` pobranego z tagu serwera (`npm run gen:api -- --server-ref vX.Y.Z`); klient HTTP to `openapi-fetch`. CI frontendu sprawdza zgodność z zadeklarowanym `server-ref`.
- `/api/v1` jest addytywne w ramach 1.x; przed 1.0 dopuszczamy zmiany łamiące, opisane w `docs/compat-matrix.md`. `GET /api/v1/meta` zwraca m.in. `serverVersion`, `apiVersion`, `minWebVersion`.

## Konsekwencje

- Kontrakt zawsze zgodny z kodem; typy TypeScript wynikają z tego samego źródła.
- Zmiana API w serwerze wymusza świadomą aktualizację `server-ref` w web.
- Zależność od huma i jego konwencji definiowania operacji.
- Za stary frontend wykrywany przez `minWebVersion`; UI pokazuje baner „Dostępna nowa wersja”.

## Alternatywy

- **Spec-first (ręczny YAML + oapi-codegen):** dobra kontrola, ale ryzyko rozjazdu spec/implementacja i więcej pracy ręcznej.
- **swaggo (komentarze w kodzie):** słabsza walidacja, OpenAPI 2/3.0, komentarze łatwo się rozjeżdżają.
- **gRPC/Connect:** gorzej pasuje do SSE, cookie sesyjnych i prostego klienta przeglądarkowego.

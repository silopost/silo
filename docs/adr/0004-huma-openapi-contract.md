# 0004. huma + chi and OpenAPI generated from code

- **Status:** Accepted
- **Date:** 2026-11-05
- **Applies to:** silo-server, silo-web

## Context

`silo-server` and `silo-web` live in separate repositories with independent SemVer. A single, trustworthy API contract is needed. A specification maintained by hand next to the code always drifts.

## Decision

- Backend: `github.com/danielgtaylor/huma/v2` with the `humachi` adapter on top of the `chi` router. chi remains the router and the place for middleware (auth, CSRF, logging, recover).
- **OpenAPI 3.1 is generated from Go structs**; huma also validates requests. `cmd/silo-openapi` writes `api/openapi.yaml` (no database needed), the file is committed, and CI fails when the generated file differs from the committed one.
- Frontend: `openapi-typescript` generates `src/api/schema.d.ts` from the `openapi.yaml` of a server tag (`npm run gen:api -- --server-ref vX.Y.Z`); the HTTP client is `openapi-fetch`. The frontend CI checks consistency with the declared `server-ref`.
- `/api/v1` is additive within 1.x; before 1.0 breaking changes are allowed and recorded in `docs/compat-matrix.md`. `GET /api/v1/meta` returns, among others, `serverVersion`, `apiVersion` and `minWebVersion`.

## Consequences

- The contract always matches the code; the TypeScript types come from the same source.
- An API change in the server forces a deliberate update of `server-ref` in the web client.
- A dependency on huma and its conventions for defining operations.
- A frontend that is too old is detected through `minWebVersion`; the UI shows a "New version available" banner.

## Alternatives

- **Spec-first (hand-written YAML + oapi-codegen):** good control, but a risk of spec/implementation drift and more manual work.
- **swaggo (comments in code):** weaker validation, OpenAPI 2/3.0, and comments drift easily.
- **gRPC/Connect:** fits SSE, session cookies and a simple browser client poorly.

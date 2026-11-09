# Contributing to Silo

This document is the **primary source of conventions** for all four repositories: `silo`, `silo-server`, `silo-web` and `silo-mobile`. The other repositories link here.

## Language

- Code, comments, names, commit messages, pull request titles and descriptions: **English**.
- Documentation (README, ADRs, docs): **English**.

## Conventional Commits

Format: `<type>(<scope>): <description in the imperative mood, lowercase, no trailing period>`

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
The scope (optional) is the area of the code, e.g. `sync`, `api`, `ops`, `search`, `ui`, `compose`.
Breaking change: `!` after the type/scope or a `BREAKING CHANGE:` footer.

Examples:

```text
feat(sync): add QRESYNC incremental folder sync
fix(api): return 409 on stale thread modification
docs: add ADR for job queue in postgres
build(compose): pin postgres image to 17
feat(ui)!: replace label picker with command palette
```

## Pull request workflow

1. Branch off `main` (`feat/...`, `fix/...`); commits follow Conventional Commits.
2. Open a pull request against `main`; the description says what and why, and how it was tested.
3. Green CI is required to merge. `main` has branch protection: a pull request and green CI are required, force-push is disabled.
4. Squash merge is preferred, with a title in Conventional Commits format (the changelog is built from it).

## `.editorconfig`

The shared file lives in the `silo` repository; it is copied unchanged to `silo-server`, `silo-web` and `silo-mobile`. Rules: UTF-8, LF, final newline, tabs for Go, 2 spaces for yaml/json/md/ts/tsx.

## Versioning

SemVer is **independent per repository**: `silo-server`, `silo-web` and `silo-mobile` have their own versions, and `silo` has a distribution version (a set of pinned image tags). The contract between them is the OpenAPI specification generated from the backend; before 1.0, breaking changes are recorded in [docs/compat-matrix.md](docs/compat-matrix.md).

## ADR

Changing an architectural decision (or deviating from Gmail parity) requires an ADR in `docs/adr/` in the `silo` repository:

1. Copy [`docs/adr/0000-template.md`](docs/adr/0000-template.md) to `NNNN-short-title.md` (next number).
2. Fill in Status, Context, Decision, Consequences, Alternatives.
3. Add an entry to [`docs/adr/README.md`](docs/adr/README.md).
4. Changing an earlier decision = a new ADR with the status "Supersedes NNNN"; the old one gets "Superseded by NNNN".
5. A security-related decision (authentication, secrets, network traffic, message content) also updates [docs/threat-model.md](docs/threat-model.md).

## Dev

Quick start in the [README](README.md). Before opening a pull request, run the local tests/linters of the repository you changed (described in its README).

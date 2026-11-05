# Silo

Self-hosted **klient webowy poczty** (IMAP/SMTP) z UX współczesnego Gmaila: wątki, wiele etykiet, archiwizacja, snooze, undo send, szybkie wyszukiwanie, skróty klawiszowe, real-time.

Silo **nie jest serwerem pocztowym**. Łączy się z istniejącym serwerem (docker-mailserver, Dovecot, Gmail IMAP, Office 365 itd.) przez IMAP i SMTP submission – tak jak Roundcube czy Thunderbird. Serwer IMAP pozostaje źródłem prawdy dla poczty. Szczegóły: [sekcja 1 planu](ARCHITECTURE_AND_PLAN.md#1-cel-i-zasady) i [ADR 0005](docs/adr/0005-imap-source-of-truth.md).

> Status: Faza 0 (scaffolding). Projekt nie jest jeszcze użyteczny.

## Repozytoria

| Repo | Licencja | Zakres | Artefakt |
|---|---|---|---|
| `silo` (to repo) | MIT | Orkiestracja (compose, Caddy, skrypty), dokumentacja, ADR, e2e | tag + compose z przypiętymi obrazami |
| `silo-server` | AGPL-3.0 | Backend Go: API, SSE, sync IMAP, SMTP, workery | `ghcr.io/silopost/silo-server` |
| `silo-web` | AGPL-3.0 | SPA React/TS, konsument OpenAPI | `ghcr.io/silopost/silo-web` |

## Szybki start (dev)

Wymagane: Docker z Compose v2, Git.

```sh
mkdir silopost && cd silopost
git clone https://github.com/silopost/silo.git
git clone https://github.com/silopost/silo-server.git
git clone https://github.com/silopost/silo-web.git

cd silo
docker compose -f docker-compose.dev.yml up
```

Repozytoria muszą być rodzeństwem (`silopost/{silo,silo-server,silo-web}`) – compose buduje z `../silo-server` i `../silo-web`.

Weryfikacja:

```sh
curl localhost:8080/healthz     # silo-server -> 200
# http://localhost:5173         # silo-web (Vite)
```

Serwer pocztowy do testów (docker-mailserver, konta testowe, seed) dojdzie w Fazie 1.

## Dokumentacja

- [ARCHITECTURE_AND_PLAN.md](ARCHITECTURE_AND_PLAN.md) – architektura i plan wdrożenia
- [docs/adr/](docs/adr/README.md) – rekordy decyzji architektonicznych
- [docs/compat-matrix.md](docs/compat-matrix.md) – macierz kompatybilności
- [CONTRIBUTING.md](CONTRIBUTING.md) – konwencje i workflow dla wszystkich trzech repo

## Licencja

MIT (to repo) – zob. [LICENSE](LICENSE). `silo-server` i `silo-web` są na AGPL-3.0.

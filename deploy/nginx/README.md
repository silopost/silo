# Silo behind an existing nginx (Portainer)

The `nginx` variant of the production stack (the variants: [README.md](../../README.md#quick-start-production)), for a host that already runs nginx with certbot (both in containers) and, optionally, docker-mailserver: no Caddy, `silo-server` and `silo-web` without host ports, reached by nginx over its Docker network. The configuration reference: [docs/admin/README.md](../../docs/admin/README.md).

| File | Purpose |
| --- | --- |
| [`../../docker-compose.yml`](../../docker-compose.yml) | The base shared by every variant: `postgres`, `blobs-init`, `silo-server`, `silo-web`. |
| [`docker-compose.yml`](docker-compose.yml) | Overlay for the base: attaches `silo-server` and `silo-web` to the nginx network, requires `SILO_PUBLIC_URL` and `SILO_TRUSTED_PROXIES`. |
| [`.env.example`](.env.example) | Stack variables (Portainer: "Environment variables"; CLI: `.env` in the repository root). |
| [`silo.conf`](silo.conf) | nginx server block, the equivalent of the [`Caddyfile`](../caddy/Caddyfile). |

The service definitions live only in the base file; this directory adds no copy of them. The stack is always the two files together:

```sh
docker compose -f docker-compose.yml -f deploy/nginx/docker-compose.yml up -d
```

## How the pieces connect

- `silo-server` and `silo-web` join the existing network of the nginx container (`SILO_PROXY_NETWORK`, `external: true`); compose registers the service names as DNS aliases there, so nginx proxies to `silo-server:8080` and `silo-web:80`. Postgres stays on the stack's own network (`silo-prod_default`, subnet `SILO_NETWORK_SUBNET`).
- nginx resolves the names per request (`resolver 127.0.0.11`, upstreams in variables): it starts and reloads while the stack is down and answers `502` until it is up.
- `SILO_TRUSTED_PROXIES` is the subnet of that network. nginx sends `X-Forwarded-For $remote_addr`, replacing any client value; `silo-server` honors the header only from a trusted peer and takes the right-most untrusted entry, so the client address cannot be forged. Every container on the proxy network counts as a trusted proxy.
- `client_max_body_size 32m` covers one upload of `SILO_MAX_ATTACHMENT_BYTES` (25 MB) plus form fields; larger files get nginx's `413` instead of Silo's own error. Raise both together.
- SPA security headers (CSP, HSTS, `nosniff`, `DENY`, `Referrer-Policy`, `Permissions-Policy`) are set in `location /`; `silo-server` sets its own for `/api` and `/healthz`.
- Variables: the overlay passes `SILO_SECRET_KEY`, `SILO_PUBLIC_URL`, `SILO_TRUSTED_PROXIES`, `SILO_AUTH_MODE`, `SILO_DEFAULT_*` and `SILO_LOG_FORMAT` to `silo-server` explicitly, so the stack's variables reach it even without an env file. Further `SILO_*` come from the env files: `.env` (`SILO_ENV_FILE`) and Portainer's `stack.env`, both optional.

## Deployment

The commands assume an nginx container `nginx-app` with `/etc/nginx/conf.d`, `/etc/letsencrypt` and `/var/www/certbot` bind-mounted, and a certbot container `nginx-certbot` sharing the last two (webroot renewal). Adjust the names to your host.

1. **Find the proxy network and its subnet:**

   ```sh
   docker inspect -f '{{range $n, $_ := .NetworkSettings.Networks}}{{$n}} {{end}}' nginx-app
   docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' nginx_default
   ```

2. **DNS:** an A/AAAA record of the Silo domain pointing at the nginx host (as for the other virtual hosts).
3. **Certificate (webroot):** while there is no certificate, `silo.conf` cannot be loaded (nginx refuses missing `ssl_certificate` files). Put a temporary HTTP-only server block in the nginx `conf.d` directory, e.g. `silo.example.com.conf`:

   ```nginx
   server {
       server_name silo.example.com;
       listen 80;
       location /.well-known/acme-challenge/ {
           root /var/www/certbot;
       }
   }
   ```

   ```sh
   docker exec nginx-app nginx -t && docker exec nginx-app nginx -s reload
   docker exec nginx-certbot certbot certonly --webroot -w /var/www/certbot -d silo.example.com
   ```

   Certbot then renews it like the other certificates. `certbot renew` alone does not reload nginx: the usual nginx+certbot setup reloads nginx periodically (an `nginx -s reload` loop in the nginx container).
4. **The stack** – either way, with a filled-in copy of `.env.example`: `SILO_PUBLIC_URL`, `SILO_SECRET_KEY` (`openssl rand -base64 32`, keep a copy separately from backups), `SILO_POSTGRES_PASSWORD` (`openssl rand -hex 24`), `SILO_PROXY_NETWORK`, `SILO_TRUSTED_PROXIES`, `SILO_DEFAULT_IMAP_HOST`.
   - **Portainer, from the git repository (recommended):** Stacks → Add stack → name `silo-prod` (Portainer uses the stack name as the project name: volumes `silo-prod_pgdata`, `silo-prod_blobs`, as in [backup.md](../../docs/admin/backup.md)) → build method "Repository": the URL of this repository (`https://github.com/silopost/silo`), reference `refs/tags/vX.Y.Z` (or `refs/heads/main`), Compose path `docker-compose.yml`, "Additional paths": `deploy/nginx/docker-compose.yml` → Environment variables: "Load variables from .env file" with the filled-in copy → Deploy the stack. Portainer writes the variables to `stack.env`, which `silo-server` also reads, so further `SILO_*` can be added there. A Portainer version without the "Additional paths" field cannot combine the files: use the CLI then.
   - **Portainer web editor (no git access):** the editor takes one file. Generate it from a checkout instead of keeping a copy, so that the base stays the only definition: `docker compose -f docker-compose.yml -f deploy/nginx/docker-compose.yml config --no-interpolate > silo-nginx-stack.yml`, then in the output replace the `env_file` list of `silo-server` (two absolute paths of the checkout) with one entry `path: stack.env`, `required: false`, and paste it. Regenerate it after every upgrade of this repository.
   - **CLI:** in a checkout of this repository, `cp deploy/nginx/.env.example .env`, fill it in, then `docker compose -f docker-compose.yml -f deploy/nginx/docker-compose.yml up -d`. With `COMPOSE_FILE=docker-compose.yml:deploy/nginx/docker-compose.yml` in `.env` a plain `docker compose up -d` (and `pull`, `logs`, …) uses both files.
5. **Server block:** copy `silo.conf` to the nginx `conf.d` directory in place of the temporary file, replace `silo.example.com` (4 places), then:

   ```sh
   docker exec nginx-app nginx -t && docker exec nginx-app nginx -s reload
   curl -fsS https://silo.example.com/healthz && curl -fsS https://silo.example.com/api/v1/meta
   ```

6. **Check the client address:** after a failed sign-in, `docker logs silo-prod-silo-server-1 | grep 'security event'` must show the client's address in `ip=`, not one from the proxy subnet.

## Default mail server

- **Public host name (default):** `SILO_DEFAULT_IMAP_HOST` = the name in the mail server's certificate (e.g. its `HOSTNAME`/`OVERRIDE_HOSTNAME` in docker-mailserver), ports 993/`implicit` and 587/`starttls` published on the host. TLS verifies by name; from a container on the same host this needs the name to resolve to an address reachable from Docker (public DNS with NAT loopback on the router, or split DNS).
- **Network alias:** attach the mail container to `silo-prod_default` with an alias equal to that name, as described in [docs/admin/README.md](../../docs/admin/README.md) ("Default server – docker-mailserver in another compose project on the same host"). Traffic then stays on the host and does not depend on NAT loopback.

## Upgrade and operations

- Upgrade: change `SILO_SERVER_TAG`/`SILO_WEB_TAG` in the stack's variables (or move the git reference), then "Update the stack" with "Re-pull image" (git stacks: "Pull and redeploy"). The rest of [docs/admin/README.md](../../docs/admin/README.md) ("Upgrade") applies.
- Images from another registry (e.g. when a `ghcr.io` package is not public): `SILO_SERVER_IMAGE`, `SILO_WEB_IMAGE`.
- Admin commands: `docker exec silo-prod-silo-server-1 /silo-server …` in place of `docker compose exec silo-server /silo-server …`.
- Backup scripts need a checkout of this repository on the host with a `.env` holding at least `SILO_POSTGRES_PASSWORD` (for interpolation): `COMPOSE_PROJECT_NAME=silo-prod scripts/backup.sh full`. The scripts use the base `docker-compose.yml`, which defines `postgres` and `silo-server` for every variant.

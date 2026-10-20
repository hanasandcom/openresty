# Hanasand OpenResty

OpenResty is Hanasand's reverse proxy for `hanasand.com` and related domains. It routes web traffic to configured backends and shares TCP port 443 with Minecraft routing and Name Pending signaling.

## How it works

The `openresty` service in `docker-compose.yml` uses host networking. It listens directly on host ports 80 and 443; Docker port mappings are not used. Loopback upstreams such as `localhost:3000` and `127.0.0.1:8080` therefore refer to services on the host. All upstreams in `nginx/conf.d/` must be reachable at their configured addresses and ports.

`nginx/conf/nginx.conf` contains the shared TCP 443 listener and HTTP settings. Virtual hosts and upstreams are in `nginx/conf.d/`; reusable proxy settings and error pages are in `nginx/snippets/`; Lua handlers are in `nginx/lua/`.

The shared listener also carries Minecraft traffic. See [minecraft/README.md](minecraft/README.md) for its routes, DNS, deployment, checks, and rollback steps.

## Requirements

- Docker Engine with the Compose plugin (`docker compose`).
- Host networking. Docker Engine supports it on Linux; Docker Desktop requires version 4.34 or later and host networking enabled in settings. See [Docker's host networking documentation](https://docs.docker.com/engine/network/drivers/host/).
- Host ports 80 and 443 available for this service.
- The upstream services referenced by `proxy_pass` in `nginx/conf.d/` reachable at their configured addresses and ports.
- TLS certificates and Certbot credential files available at the paths described below.

## Runtime files and certificates

Run Compose commands from the repository root. The Compose file mounts these repository-relative paths into the container:

| Host path | Container path | Purpose |
| --- | --- | --- |
| `letsencrypt/` | `/etc/letsencrypt` | TLS certificates and Certbot state |
| `certbot-credentials/` | `/etc/certbot-credentials` (read-only) | DNS provider credentials |
| `scripts/` | `/usr/local/openresty/certbot-scripts` (read-only) | This repository has no tracked files in this directory |

The Nginx configuration references certificates for `hanasand.com` and `pengeflyt.com`, plus `options-ssl-nginx.conf` and `ssl-dhparams.pem`. Put the files at the matching paths under `letsencrypt/` before starting OpenResty. Keep private keys and DNS credentials out of Git. The repository's `.gitignore` excludes untracked files by default; check `git status` before committing runtime files.

## Deploy or update the container

Run these commands from the repository root on the host that serves public traffic. They build and validate the candidate image, then recreate the running service with it.

```sh
docker compose config -q
docker compose build openresty
docker compose run --rm --no-deps \
  --name openresty-config-check \
  --entrypoint /usr/local/openresty/bin/openresty \
  openresty -t
docker compose up -d --no-build openresty
docker compose ps
```

Check the public HTTPS endpoint after the service is healthy:

```sh
curl -I https://hanasand.com/
```

For a change only to files mounted from `nginx/`, validate and reload the running service without rebuilding the image:

```sh
docker compose exec -T openresty /usr/local/openresty/bin/openresty -t && \
  docker compose exec -T openresty /usr/local/openresty/bin/openresty -s reload
```

## Check status and logs

```sh
docker compose ps
docker compose logs --tail=100 openresty
```

The Compose health check runs OpenResty's configuration test every 30 seconds. It does not verify that upstream applications respond; use the public HTTPS check above and the relevant service's own health check for that.

## Renew certificates

`renew-hanasand-certbot.sh` runs `certbot renew` inside the `openresty` container. It renews existing certificates; first-time certificate issuance is not documented in this repository. When a certificate renews, its deploy hook tests the Nginx configuration and reloads OpenResty.

```sh
./renew-hanasand-certbot.sh
```

To request Certbot's dry run:

```sh
CERTBOT_RENEW_MODE=dry-run ./renew-hanasand-certbot.sh
```

The script enables the deploy hook during dry runs, so it can still test and reload the running OpenResty service.

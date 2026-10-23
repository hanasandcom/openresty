# Hanasand OpenResty

Dockerized OpenResty reverse proxy for `hanasand.com` and related services.

`identity.hanasand.com` serves Identity Next.js pages from the Identity web workers (`hanasand_identity_web`). Its `/api/*` and `/ready` paths route directly to the Fastify Identity workers (`hanasand_auth`); browser sign-in and app selection use this host and do not go through the Hanasand application API.

The Sandbox page at `/sandbox` is part of Hanasand's existing Next.js frontend and uses the normal site shell. OpenResty sends the main host to that frontend through its standard route. Browser data, streams, and WebSockets use the Browser API at `https://browsers.hanasand.com/api`, sign-in calls Identity directly at `identity.hanasand.com`, and Browser records stay in the Browser-owned database. The Browser subdomain serves only the API and redirects other website paths to the standard Hanasand UI.

Shared HTTP error responses use the template in `nginx/errors/` and its Lua renderer in `nginx/lua/`.

The service uses host networking so the existing upstreams such as `localhost:3000`, `localhost:8080`, and `localhost:8501` keep the same meaning they had in the host-level OpenResty service. Its shared port 443 listener routes TLS by SNI, `SSH-` greetings to the VM SSH gateway, HTTP signaling to Name Pending, and Minecraft Java by the hostname in its handshake. VM services route to the selected guest port on the VM's private address. The API feed supplies VM identities and published service metadata; OpenResty keeps route maps in shared memory and updates mc-router through its loopback API. The VM guest does not need access to the route token, Docker networks, LXD socket, or Minecraft seed route file. The internal SSH relay consumes the PROXY header before forwarding the SSH stream to the gateway on port 22.

VM names provide their public hostname (`<vm-name>.hanasand.com`). Owners can
also publish a typed service hostname (`<service-name>.hanasand.com`) in the
Hanasand VM details page. HTTP routes terminate TLS at the wildcard HTTPS
listener and proxy to the selected guest port; TLS routes use SNI to pass the
encrypted stream through; Minecraft Java routes use the handshake hostname.
The gateway checks each hostname against its route type before connecting to
the VM's private address. Existing numeric aliases such as
`8080-test3.hanasand.com` remain supported for legacy routes. Set the same
private `VM_PORT_ROUTE_TOKEN` in the Hanasand API and this repository's `.env`;
the gateway reads the route list from `127.0.0.1:8080` every five seconds.
Arbitrary plain TCP and UDP services cannot be selected by hostname alone.

The route dictionaries are sized for the previously observed 71-VM inventory
at the product limit of 1,000 published services per VM. With 40-character
service names, the stream map is budgeted at about 256 bytes per route
(17.4 MiB for 71,000 routes); the HTTP map stores two entries per HTTP route
and is budgeted at about 512 bytes per route (34.7 MiB). The configured 32 MiB
stream and 64 MiB HTTP dictionaries leave room for slab metadata and growth.
These are host-wide upper planning figures, not a claim that 71,000 services
are currently configured. Route refreshes use non-evicting writes. If a write
fails, OpenResty logs the failure, attempts to roll back keys changed by that
snapshot, and skips stale-key cleanup. Rollback is best-effort and can also
fail, so the active map may be partially updated until a later successful
five-second refresh.

## Deploy

```sh
docker compose up -d --build
docker exec openresty openresty -t
curl -I https://hanasand.com
curl -fsS https://identity.hanasand.com/ready
```

TLS certificates are read from `/etc/letsencrypt` on the host.

Requests sent directly to `128.39.142.218` redirect to the canonical Hanasand URL
while preserving the path and query. HTTPS uses a separate Let's Encrypt IP
certificate because the domain certificate does not identify the numeric address.
IP certificates use the `shortlived` profile and expire after six days. Certbot
must renew them automatically; the Inspur renewal job runs twice daily and reloads
OpenResty after a successful renewal. The HTTP-01 challenge path remains available
on port 80 for renewal.

To issue or replace the IP certificate from the OpenResty container, use:

```sh
docker exec openresty certbot certonly --preferred-profile shortlived \
  --webroot --webroot-path /etc/letsencrypt \
  --ip-address 128.39.142.218
```

The renewal configuration created by Certbot is picked up by
`renew-hanasand-certbot.sh`; verify that the scheduled renewal job remains enabled.

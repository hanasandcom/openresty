# Hanasand OpenResty

Dockerized OpenResty reverse proxy for `hanasand.com` and related services.

`identity.hanasand.com` routes `/api/*` and `/ready` directly to the Identity workers (`hanasand_auth`). Browser sign-in uses this host and does not go through the Hanasand application API.

`hanasand.com/sandbox` serves the Browser UI, with `/api/browser/*` and `/api/ws/browser/*` routed to the Browser API. Browser sign-in calls Identity directly at `identity.hanasand.com`; Browser records stay in the Browser-owned database. Requests to `browsers.hanasand.com` redirect into the Hanasand site, and its `/login` path uses the canonical Hanasand login. The retired `/sandbox/login` path and trailing-slash variant reach Hanasand's not-found handler instead of the Browser service.

Shared HTTP error responses use the template in `nginx/errors/` and its Lua renderer in `nginx/lua/`.

The service uses host networking so the existing upstreams such as `localhost:3000`, `localhost:8080`, and `localhost:8501` keep the same meaning they had in the host-level OpenResty service. Its shared port 443 listener routes TLS to web sites, named VM services, or `turn.hanasand.com` (TURN over TLS via the local HAProxy bridge), `SSH-` greetings to the VM SSH gateway, HTTP signaling to Name Pending, and remaining game traffic to mc-router. Minecraft service routes are refreshed through mc-router's watched config. The internal SSH relay consumes the PROXY header before forwarding the SSH stream to the gateway on port 22.

VM service routes are created in Hanasand's VM details page. HTTP website routes
terminate TLS at this gateway with the Hanasand wildcard certificate and proxy
HTTP to the guest port. TLS routes pass through end to end, and Minecraft Java
routes use the hostname in the game handshake. Set the same private
`VM_PORT_ROUTE_TOKEN` in the Hanasand API and this repository's `.env`; the gateway
uses it to read the route list from `127.0.0.1:8080` every five seconds. The wildcard
DNS record sends `port-*.hanasand.com` to this host. TLS services must send SNI and
keep their own certificate. Plain TCP and UDP services need another routing method.

## Deploy

```sh
docker compose up -d --build
docker exec openresty openresty -t
curl -I https://hanasand.com
curl -fsS https://identity.hanasand.com/ready
```

TLS certificates are read from `/etc/letsencrypt` on the host.

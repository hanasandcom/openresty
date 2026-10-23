# Hanasand OpenResty

Dockerized OpenResty reverse proxy for `hanasand.com` and related services.

`identity.hanasand.com` routes `/api/*` and `/ready` directly to the Identity workers (`hanasand_auth`). Browser sign-in uses this host and does not go through the Hanasand application API.

The Browser UI runs inside Hanasand's standard app shell at `/sandbox`. OpenResty leaves that exact route on the Hanasand frontend and sends `/sandbox/ui` plus Browser page assets and child routes directly to the Browser web service at `127.0.0.1:8186`. Browser data, streams, and WebSockets route directly to the separate Browser API at `127.0.0.1:8185`; sign-in calls Identity directly at `identity.hanasand.com`, and Browser records stay in the Browser-owned database. Requests to `browsers.hanasand.com` redirect to the standard `/sandbox` path; its legacy `/login` path uses the canonical Hanasand login. The retired `/sandbox/login` path and trailing-slash variant return the OpenResty 404 instead of reaching the Browser service.

Shared HTTP error responses use the template in `nginx/errors/` and its Lua renderer in `nginx/lua/`.

The service uses host networking so the existing upstreams such as `localhost:3000`, `localhost:8080`, and `localhost:8501` keep the same meaning they had in the host-level OpenResty service. Its shared port 443 listener routes TLS by SNI, `SSH-` greetings to the VM SSH gateway, HTTP signaling to Name Pending, and Minecraft Java by the hostname in its handshake. VM services route to the selected guest port on the VM's private address. The VM route feed contains VM identities and private addresses only; OpenResty does not mount or write the Minecraft router's watched route file. The internal SSH relay consumes the PROXY header before forwarding the SSH stream to the gateway on port 22.

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

## Deploy

```sh
docker compose up -d --build
docker exec openresty openresty -t
curl -I https://hanasand.com
curl -fsS https://identity.hanasand.com/ready
```

TLS certificates are read from `/etc/letsencrypt` on the host.

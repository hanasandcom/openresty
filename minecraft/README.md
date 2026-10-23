# Minecraft on HTTPS port 443

Players use `name-pending.hanasand.com`, `67.hanasand.com`, or
`cobbleverse.hanasand.com`. The `_minecraft._tcp` SRV records select TCP 443;
explicit `:443` also works. `np.hanasand.com` is an additional alias for Name Pending. These are Java Edition server addresses, not URLs.
Each modded server still requires its own matching client version and mods.

OpenResty's stream listener owns IPv4/IPv6 port 443. SSH greetings go to the VM
gateway on port 22. TLS SNI routes pass through to the matching guest port.
Minecraft Java handshakes identify the VM and guest port; OpenResty registers
that exact hostname with mc-router's loopback-only route API. The watched
`minecraft/runtime/minecraft.json` file contains only the fixed first-party seed
routes. NetherNet HTTP signaling for np.hanasand.com goes through loopback
8444; TLS for first-party sites goes to `127.0.0.1:8443`; other game traffic
goes to mc-router on `127.0.0.1:25566`. PROXY protocol preserves the original IP
for the router. mc-router retains its existing server networks and does not
mount the Docker socket. Customer VMs do not join those Docker networks and
receive traffic only at the selected guest IP and port.

The route feed contains VM identity routes and named service routes. A service
entry has a hostname, route type, private VM IP and guest port. When a VM
publishes Minecraft Java on guest port 25565, the gateway also registers
`<vm-name>.hanasand.com` to that VM's port 25565. Published Minecraft service
hostnames use their configured guest ports. The gateway reconciles these routes
through mc-router's loopback API every five seconds; the guest needs only a
listener on its port. It does not need the route token, Docker networks, LXD
socket or access to the seed route file. Existing
`<port>-<vm-name>.hanasand.com` numeric aliases remain available. TLS services
must provide their own certificate and send SNI. Website services terminate
wildcard HTTPS at the gateway and proxy HTTP to the configured guest port.

## Tracked configuration

- This repository: `minecraft/docker-compose.yml`, DNS setup/check scripts,
  `nginx/conf/nginx.conf`, and HTTPS virtual-host listeners in `nginx/conf.d/`.
- Create server: `eirikhanasand/67`, deployed at `/home/hanasand/67`.
  Its existing NeoForge/mod versions are pinned and its network alias is
  `create-server` (the numeric container name is unsuitable as a DNS target).
- Name Pending: `eirikhanasand/name-pending-server` on GitHub. The clean source
  checkout is `/home/hanasand/name-pending-server-source`; the live Compose
  project and world remain `/home/hanasand/name_pending_server`. The legacy
  live-directory Git history contains runtime data and must not be pushed.
- Cobbleverse: `minecraft/cobbleverse.compose.yml` is the source; copy it to
  `/home/hanasand/cobbleverse/docker-compose.yml`. It keeps modpack 1.7.42 and
  Java 21, adds missing Configurable, and replaces the Java-25-only C2ME build
  with the pinned 0.3 build whose native optimization is optional on Java 21.

Worlds, `.env` files, RCON passwords, and DNS credentials remain on the server
and must never be committed. Old game ports 5000, 5001, and 25565 bind only to
loopback; they no longer need public firewall rules. Website ports are separate.
The firewall must pass ordinary TCP on 443, rather than enforce HTTPS-only traffic.

## Deploy on Inspur

Apply the server Compose files in their existing project directories to preserve
volumes and network names. Copy the Name Pending source Compose file to its live
directory; copy the Cobbleverse manifest as described above. Check player counts
with `docker exec CONTAINER rcon-cli list` before planned server restarts.
Run `docker compose up -d` in each changed server directory and wait for healthy
status before changing the shared listener.

From `/home/hanasand/openresty`:

```sh
mkdir -p minecraft/runtime
cp minecraft/routes-seed.json minecraft/runtime/minecraft.json
docker compose -p minecraft-routing -f minecraft/docker-compose.yml up -d
docker exec openresty nginx -t
docker exec openresty nginx -s reload
python3 minecraft/check_routes.py --connect 127.0.0.1 --forge
python3 minecraft/setup_dns.py --apply
```

Set `VM_PORT_ROUTES_API_URL` and `VM_PORT_ROUTE_TOKEN` in the private OpenResty
`.env`. Set the same route token in the Hanasand API environment. The VM and
service route list is read from the API on `127.0.0.1:8080` every five seconds.
The mc-router route API is exposed only on host loopback port `25567` for
OpenResty to reconcile Minecraft routes from that list.

`setup_dns.py` defaults to a dry run. It reads the existing Domeneshop Certbot
credentials from `letsencrypt/domeneshop.ini`, updates only the four A and four
SRV records, and reads them back to verify. It never prints or stores credentials.

Run `python3 minecraft/check_routes.py --forge` from outside the server to test
DNS, port 443, routing, Minecraft status, and ping/pong. This verifies the network
path, not an authenticated player joining and playing. Also check HTTPS sites and
a fresh `ssh cashflow` connection; both use the same public port.

## Rollback

The initial migration backup is `/home/hanasand/backups/minecraft-443-20260921`.
Restore its `nginx.conf`, `default.conf`, and `cashflow.conf` to their corresponding
Nginx paths, validate and reload. Restore any server Compose file requiring its
old public port and recreate only that server. Restore the previous DNS routing
if reverting the client addresses. Never replace or delete the world directories.

## Name Pending on iPad

Bedrock address: `np.hanasand.com`, port `443`. Geyser NetherNet handles UDP
19132 directly (UDP 443 is blocked upstream). `nginx/conf.d/bedrock.conf` routes HTTP/HTTPS signaling at
`/v1/join` to loopback TCP 19132. The Name Pending source repository owns
Geyser, Floodgate, and deployment settings. Player authentication and the
whitelist remain enabled.

# Minecraft on HTTPS port 443

Players use `name-pending.hanasand.com`, `67.hanasand.com`, or
`cobbleverse.hanasand.com`. The `_minecraft._tcp` SRV records select TCP 443;
explicit `:443` also works. `np.hanasand.com` is an additional alias for Name Pending. These are Java Edition server addresses, not URLs.
Each modded server still requires its own matching client version and mods.

OpenResty's stream listener owns IPv4/IPv6 port 443. SSH greetings go to the VM
gateway on port 22. NetherNet HTTP signaling for np.hanasand.com goes through loopback
8444; TLS goes to the existing HTTP virtual hosts on `127.0.0.1:8443`; other
connections go to mc-router on `127.0.0.1:25566`. PROXY protocol preserves the
original IP for HTTPS and router logs. mc-router routes only the configured
hostnames across the existing Docker networks. It needs no Docker socket or
administrative API. Minecraft backends retain their own authentication; their
socket peer is the router.

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
docker compose -p minecraft-routing -f minecraft/docker-compose.yml up -d
docker exec openresty nginx -t
docker exec openresty nginx -s reload
python3 minecraft/check_routes.py --connect 127.0.0.1 --forge
python3 minecraft/setup_dns.py --apply
```

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

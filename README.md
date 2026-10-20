# Hanasand OpenResty

Dockerized OpenResty reverse proxy for `hanasand.com` and related services.

The service uses host networking so the existing upstreams such as `localhost:3000`, `localhost:8080`, and `localhost:8501` keep the same meaning they had in the host-level OpenResty service. Its shared port 443 listener routes TLS to web sites, `SSH-` greetings to the VM SSH gateway, HTTP signaling to Name Pending, and remaining game traffic to mc-router. The internal SSH relay consumes the PROXY header before forwarding the SSH stream to the gateway on port 22.

## Deploy

```sh
docker compose up -d --build
docker exec openresty openresty -t
curl -I https://hanasand.com
```

TLS certificates are read from `/etc/letsencrypt` on the host.

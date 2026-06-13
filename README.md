# erp-proxy

Minimal nginx reverse-proxy used to work around outbound network restrictions
on specific Coolify hosts. Deploy this on a Coolify server that **can** reach
the ERP, and point Cleanshelf (or any other admin backend that cannot reach
the ERP directly) at this proxy's public URL. Traffic originates from the
proxy host's IP, so the Cleanshelf server never has to talk to the ERP
directly.

## What it does

- Forwards every request to `${ERP_UPSTREAM}` verbatim — same path, same
  query string, same headers (including `Authorization` / `X-API-Key`).
- Exposes `/healthz` for Coolify/Docker health probes — always returns `ok`
  without hitting the upstream.
- Optional IP allow-list via the `ALLOW_CIDRS` env var.
- Coolify's Traefik in front terminates HTTPS for you (Let's Encrypt) so
  Cleanshelf talks to the proxy over HTTPS even though the ERP is plain HTTP.

## Environment variables

| Name | Required | Default | Purpose |
|---|---|---|---|
| `ERP_UPSTREAM` | **Yes** | `http://example.com:8080` | Base URL of the real ERP (scheme + host + port, no trailing slash). Example: `http://erp-host.internal:PORT`. The real host/IP goes in Coolify env only — never commit it. |
| `PROXY_SERVER_NAME` | No | `_` | `server_name` for the nginx vhost. Leave as `_` and let Coolify's Traefik route by Host header. |
| `PROXY_CLIENT_MAX_BODY_SIZE` | No | `10m` | Max request body. ERP product sync payloads fit easily. |
| `PROXY_CONNECT_TIMEOUT` | No | `10s` | Upstream connect timeout. |
| `PROXY_READ_TIMEOUT` | No | `60s` | Upstream read timeout. |
| `PROXY_SEND_TIMEOUT` | No | `60s` | Upstream send timeout. |
| `ALLOW_CIDRS` | **Recommended** | *(empty)* | Comma-separated CIDRs that are allowed to hit the proxy. When set, all other sources get `403 Forbidden`. **Fails closed:** if left empty/unset the proxy denies every source IP, so you must set this to deploy a usable proxy. |

## Deploy on Coolify

1. **New Application** → type: **Public Repository** (or Private; doesn't matter) → URL: this repo → Branch: `main`.
2. **Build Pack**: Dockerfile. Dockerfile path: `/Dockerfile`. Port: `80`.
3. **Domain**: give it a Coolify subdomain, e.g. `erp-proxy.yourdomain.com`. Coolify will provision a Let's Encrypt cert.
4. **Environment Variables** (at minimum — real host/IP goes here, never in git):
   ```
   ERP_UPSTREAM=http://erp-host.internal:PORT
   ```
   Required to make the proxy reachable — lock it to Cleanshelf's egress IP
   (the allow-list fails closed, so an unset `ALLOW_CIDRS` denies everything):
   ```
   ALLOW_CIDRS=1.2.3.4/32
   ```
5. **Deploy**.
6. Verify:
   ```
   curl -sS https://erp-proxy.yourdomain.com/healthz
   # -> ok
   curl -sS -H "Authorization: Bearer $ERP_TOKEN" \
        https://erp-proxy.yourdomain.com/api/PRODUCTS | head -c 400
   ```

## Point Cleanshelf at the proxy

In admin → **Settings** → **ERP Integration**, change the **Branch stock API base URL** from the direct ERP URL to the proxy URL:

```
https://erp-proxy.yourdomain.com
```

Leave the auth mode, bearer token / header name, and paths (`/api/PRODUCTS`, etc.) unchanged — nginx forwards the full request verbatim. Save, then trigger a manual sync from the admin UI to confirm it works.

## Rollback

If something goes wrong, put the old direct URL back in the Cleanshelf admin Setting and the proxy is bypassed — no backend redeploy needed. The proxy service can stay running idle.

## Security notes

- The proxy is reachable by anyone who finds the public hostname. If the ERP itself is unauthenticated, **set `ALLOW_CIDRS`** to Cleanshelf's egress IP or an internal Tailscale/Wireguard range. Otherwise you're republishing the ERP to the internet.
- Bearer tokens and API keys are forwarded in the `Authorization` / custom header. The Cleanshelf → proxy leg is HTTPS (Let's Encrypt via Coolify) so the tokens are encrypted in transit for the public portion of the hop. The proxy → ERP leg is plain HTTP inside whatever network segment the proxy server sits in — make sure that segment is trusted.
- Do **not** bake the ERP URL or tokens into the image. Use Coolify env vars so rotations don't require rebuilds.

## Local test

```sh
docker build -t erp-proxy .
docker run --rm -p 8080:80 \
  -e ERP_UPSTREAM=https://httpbin.org \
  erp-proxy
# In another terminal:
curl -sS http://localhost:8080/healthz            # -> ok
curl -sS http://localhost:8080/get                # -> proxied response from httpbin
```

## Files

- `Dockerfile` — `nginx:1.27-alpine`, copies the template, sets sane defaults for env vars, adds a healthcheck.
- `nginx/default.conf.template` — the vhost. Env vars interpolated by `envsubst` at container start (standard `nginx:alpine` behaviour for `/etc/nginx/templates/*.template`).
- `nginx/40-allow-list.sh` — entrypoint hook that materialises `ALLOW_CIDRS` into an `include`-able allow-list before nginx starts. No-op when unset.

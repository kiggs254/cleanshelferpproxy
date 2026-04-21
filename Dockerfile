FROM nginx:1.27-alpine

# nginx:alpine runs `envsubst` over files ending in `.template` inside
# /etc/nginx/templates/ on startup. This lets us bake the config but keep
# the upstream URL + allow-list overrideable at deploy time via env vars.
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template

# Entrypoint hook — runs before nginx starts. Translates ALLOW_CIDRS env var
# into /etc/nginx/conf.d/allow-list.conf so the server block's `include`
# always resolves (empty file when ALLOW_CIDRS is unset = no restriction).
COPY nginx/40-allow-list.sh /docker-entrypoint.d/40-allow-list.sh
RUN chmod +x /docker-entrypoint.d/40-allow-list.sh \
 && touch /etc/nginx/conf.d/allow-list.conf

# Defaults are intentionally generic. Coolify → Environment Variables overrides.
ENV ERP_UPSTREAM="http://example.com:8080" \
    PROXY_SERVER_NAME="_" \
    PROXY_CLIENT_MAX_BODY_SIZE="10m" \
    PROXY_CONNECT_TIMEOUT="10s" \
    PROXY_READ_TIMEOUT="60s" \
    PROXY_SEND_TIMEOUT="60s" \
    ALLOW_CIDRS=""

EXPOSE 80

# nginx:alpine entrypoint already handles envsubst + starting nginx.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1/healthz || exit 1

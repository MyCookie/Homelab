# Public Relay

This is a relay server that is accessible from a public IP. The only ports required are `80` and `443`.

## Debian

Install `tailscale` and `caddy`.

Documentation for Tailscale: https://tailscale.com/kb/1031/install-linux.

Documentation for Caddy: https://caddyserver.com/docs/install.

### Caddy

Replace `DOMAIN_NAME` and `TAILNET_NAME` from `../.env` in the `Caddyfile`. Copy the `Caddyfile` to `/etc/caddy`.

Copy Cloudflare's Origin CA certificates to `/etc/caddy/ssl/$DOMAIN_URL`.

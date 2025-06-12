# Public Relay

This is a relay server that is accessible from a public IP. The only ports required are `80` and `443`.

## Debian

Install `tailscale` and `caddy`.

Documentation for Tailscale: https://tailscale.com/kb/1031/install-linux.

Documentation for Caddy: https://caddyserver.com/docs/install.

### Caddy

Replace `DOMAIN_NAME` and `TAILNET_NAME` from `../.env` in the `Caddyfile`. Copy the `Caddyfile` to `/etc/caddy`.

Copy Cloudflare's Origin CA certificates to `/etc/caddy/ssl/$DOMAIN_URL`.

#### `reverse_proxy` directive

When proxying to HTTPS, set the `Host` header to the domain name of the HTTPS server. See [here](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#https).

## Cloudflare

When proxying behind Cloudflare, make sure to strip all non-Cloudflare IPs form the `X-Forwarded-For` header.

Using Cloudflare's API:

```bash
curl --request PUT \
  --url https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/rulesets/phases/http_request_late_transform/entrypoint \
  --header 'Content-Type: application/json' \
  --header 'X-Auth-Key: $CLOUDFLARE_API_KEY' \
  --data '{
  "description": "Remove X-Forwarded-For Header",
  "rules": [
    {
      "action": "execute",
      "action_parameters": {
        "headers": {
          "x-forwarded-for": {
            "operation": "remove"
          }
        }
      },
      "description": "Remove all non-Cloudflare IPs in the X-Forwarded-For Header",
      "enabled": true,
      "expression": "not ip.src in {103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 104.16.0.0/13 104.24.0.0/14 108.162.192.0/18 131.0.72.0/22 141.101.64.0/18 162.158.0.0/15 172.64.0.0/13 173.245.48.0/20 188.114.96.0/20 190.93.240.0/20 197.234.240.0/22 198.41.128.0/17 2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32 2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32}",
      "logging": {
        "enabled": true
      }
    }
  ]
}'
```

More reading:
https://www.authelia.com/integration/proxies/forwarded-headers/
https://www.cloudflare.com/ips/

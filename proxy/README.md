# Public Relay

This is a relay server that is accessible from a public IP. An additonal reverse proxy, in front of the Caddy instance running in Docker. This is to abstract away the internal tailnet for traffic coming from the wider internet. Which will also allow us to deny access to parts of services we don't want publicly accessible, while allowing anyone on the tailnet unfettered access. The only ports required are `22`, `80` and `443`.

Any major flavour of Linux distribution will work, as long as it can fulfill the prerequisite requirements below.

## Prerequisites

Install `tailscale` and `caddy`.

Documentation for Tailscale: https://tailscale.com/kb/1031/install-linux.

Documentation for Caddy: https://caddyserver.com/docs/install.

## Caddy

Bog-standard Caddy install. Use the binary from the distribution's repository. Since this instance only handles TLS termination for internet-wide traffic, no special install or setup is necessary.

Replace `DOMAIN_NAME` and `TAILNET_NAME` from `../.env` in the `Caddyfile`. Copy the `Caddyfile` to `/etc/caddy`.

Copy Cloudflare's Origin CA certificates to `/etc/caddy/ssl/$DOMAIN_URL`.

#### `reverse_proxy` directive

When proxying to HTTPS, set the `Host` header to the domain name of the HTTPS server. See [here](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#https).

### TLS Host Header

When reverse proxying to a server using HTTPS with a differnt domain, if we do not change the headers, the browser will refuse to connect, as will any other proxies. When running a site served over HTTPS on a tailnet, this is the case. In order to solve this, we will need to manage the Host header when passing traffic through the proxy. An example is provided below.

```Caddyfile
matrix.$DOMAIN_URL {
	tls /etc/ssl/$DOMAIN_URL/$DOMAIN_URL.cert.pem /etc/ssl/$DOMAIN_URL/$DOMAIN_URL.key.pem

	reverse_proxy /_matrix/* https://matrix.$TAILNET.ts.net:8008 {
        # https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#https
		# when proxying to https on a different domain, switch the header for SNI
		header_up Host matrix.$TAILNET.ts.net
		header_down Host matrix.$DOMAIN_URL
    }
	reverse_proxy /_synapse/client/* https://matrix.$TAILNET.ts.net:8008 {
        # https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#https
		# when proxying to https on a different domain, switch the header for SNI
		header_up Host matrix.$TAILNET.ts.net
		header_down Host matrix.$DOMAIN_URL
    }

	log {
		output file /var/log/caddy/$DOMAIN_URL/matrix/caddy.log
	}
}
```

See https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#https for more details.

### Logging

Add the `log` directive to each proxied site. The location is arbitrary, as long as Caddy can write to it.

```Caddyfile
log {
	output file /var/log/caddy/$DOMAIN_URL/caddy.log
}
```

Add the subdomain after the parent domain in the above example to separate the logs by site.

### Matrix

For domain delegation, see ../docker/README.md#Docker#Synapse#Delegation. An example is provided below:

```Caddyfile
header /.well-known/matrix/* Content-Type application/json
header /.well-known/matrix/* Access-Control-Allow-Origin *
respond /.well-known/matrix/server `{"m.server": "matrix.$DOMAIN_URL:443"}`
respond /.well-known/matrix/client `{"m.homeserver":{"base_url":"https://matrix.$DOMAIN_URL"}}`
```

## Troubleshooting

### Tailscale DNS issues

There are multiple services fighting over `/etc/resolve.conf` in a Linux machine. Until all services adopt a single DNS resolver, this mess will continue.

This issue will appear as an inability to access sites even if the proxy is connected to Tailscale.

You have this issue when:

- You CAN:
  - See a successful `tailscale status`.
  - Successfully `tailscale ping` a node.
  - Successfully `ping $TAILNET_NODE_IP` a node.
  - Successfully get a `NOERROR` on `dig ts.net` or resolve an IP with `nslookup ts.net`.
- You CAN NOT:
  - Successfully `curl $TAILNET_NODE_HOSTNAME`.
  - Successfully get a `NOERROR` on `dig $TAILNET_NODE_HOSTNAME.$TAILNET.ts.net`

For machines with `systemd-resolved`, use `resolvectl` to see the available networks and their attached DNS servers. A failed config will return:

```bash
user@host$ resolvectl
Link 3 (tailscale0)
    Current Scopes: none
         Protocols: -DefaultRoute -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
```

To attempt to resolve this issue with `resolvectl`, run:

```bash
# resolvectl dns tailscale0 100.100.100.100
# resolvectl domain tailscale0 ts.net
# systemctl restart systemd-resolved
```

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

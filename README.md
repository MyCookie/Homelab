# Homelab

Config for a self-hosted homelab: Docker Compose stacks for Nextcloud, Jellyfin, Synapse, Forgejo, and other services, a Caddy reverse-proxy setup, and operational docs for running it all on Debian + ZFS.

Evolved from [docker_cloud](https://github.com/MyCookie/docker_cloud) (2019–2021), which ran the same idea on **Docker Swarm (per-service stacks) behind nginx** before this repo moved to a split, `include:`-based Compose layout, Caddy, ZFS, and a GPU LLM-inference layer.

## What this is

A personal, living stack, not a production deployment — it's where I run my own services and experiment with whatever has my attention at the moment (currently: local LLM inference). That trade-off shows up a few ways:

- Liberal use of `:latest` tags, with Watchtower pulling new images as they ship rather than pinning and reviewing each bump.
- No monitoring/alerting stack yet — a full Grafana setup doesn't fit the memory budget alongside everything else running here.
- No test suite or upgrade-failure notifications yet either. Both are on the list, waiting on more headroom.

## Layout

```
compose/    the core homelab stack (Nextcloud, Jellyfin, Synapse, MinIO, Forgejo, ...)
spark/      LLM inference stack (llama.cpp router or a single vLLM model server)
proxy/      public relay box: Caddy + Tailscale, terminates public TLS
mac/        native macOS services (llama-server, whisper-server, MCP) + upgrade tooling
docs/       ZFS and Debian host runbooks
```

Compose files are split one-service-per-file and assembled with Compose's `include:` directive rather than one large YAML. Each directory below has its own README with the real operational how-tos — Watchtower, Caddy reload, database upgrades, hardware transcoding, and more — so start there for anything specific; this file is just the map.

| Path | Covers |
| --- | --- |
| [compose/README.md](compose/README.md) | The main stack: Nextcloud, Jellyfin, Synapse, MinIO, Forgejo, and friends |
| [spark/README.md](spark/README.md) | llama.cpp / vLLM inference stack, model swapping, troubleshooting |
| [proxy/README.md](proxy/README.md) | The public-facing relay box |
| [mac/README.md](mac/README.md) | Native macOS services and the `mac/upgrade` update tool |
| [docs/ZFS.md](docs/ZFS.md) | Pool layout |
| [docs/debian.md](docs/debian.md) | Archival Debian + ZFS + Nvidia + libvirt setup notes (superseded, kept for reference) |

## License

[GNU GPLv3](LICENSE).

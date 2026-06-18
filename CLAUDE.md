# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This is an infrastructure-as-config repo for a self-hosted homelab — not an application codebase. It's a collection of Docker Compose stacks, a Caddy reverse-proxy config, and operational docs for running services on Debian + ZFS (formerly TrueNAS SCALE) plus a couple of Mac-specific setups. There is no build, lint, or test tooling; "correctness" means `docker compose config` parses and the resulting containers start cleanly.

## Repo layout

- `compose/` — the main homelab stack (`name: nextcloud` in `docker-compose.yaml`). Uses Compose's `include:` directive to assemble the stack from smaller files rather than one monolithic file:
  - `docker-compose.yaml` — entrypoint; `include:`s configs, networks, and services in dependency order (configs → networks → core deps like database/minio → primary apps → remaining services), then defines `watchtower` inline.
  - `configs.yaml` — shared Compose `configs:` blocks (e.g. `tailscale_serve` JSON, referenced via `${TAILNET_FQDN}`).
  - `networks/*.yaml` — one file per named external network (`homelab`, `nextcloud`, `servarr`).
  - `services/*.yaml` — one file per service/app (jellyfin, nextcloud, synapse, minio, forgejo, audiobookshelf, etc.), each a self-contained `services:` map merged in by `include:`.
  - `env/*.env` — per-service env files (e.g. `nextcloud.env`, `tailscale.env`); `.env` at `compose/` root holds shared vars like `$VOLUMES_PATH`.
  - `volumes/` — bind-mounted config trees for `caddy` and `tailscale` that get mounted into containers.
- `spark/` — a separate Compose project (`name: spark`) for LLM inference, also assembled via `include:`. Runs either an `llamacpp-router` (llama.cpp server with a `models.ini` preset config covering multiple GGUF models/quantizations) or one of several single-model `vllm-*.yaml` services (gpt-oss-120b, Qwen3.6-27b, Gemma4, Nemotron, etc.), each pinned to a specific image tag and GPU reservation. Only one model service is typically included at a time — swap which file is included/uncommented in `compose.yaml` rather than running them concurrently (they all bind port 8000 and reserve all GPUs).
- `proxy/` — config for a separate "public relay" box: a minimal Caddy instance + Tailscale that terminates public TLS and reverse-proxies into the tailnet, decoupling internet-facing exposure from the internal stack. `Caddyfile` is the template (placeholders `DOMAIN_NAME`/`TAILNET_NAME`); `compose.yaml` runs it in Docker.
- `mac/` — LaunchAgents (plists) and an `update.sh` script for running `llama-server`/`whisper-server`/MCP servers natively on macOS (via Apple's `container` tool, not Docker).
- `docs/` — operational runbooks: `ZFS.md` (pool layout/hierarchy under the `Homelab` pool: `Archive`, `Downloads`, `Library/{Audiobooks,Games,Music,Podcasts}`, `Services/{Docker,libvirt}`), `debian.md` (deprecated/archival Debian+ZFS+Nvidia+libvirt setup notes).
- Per-directory `README.md` files (`compose/README.md`, `proxy/README.md`, `mac/README.md`) contain the actual operational how-tos (Watchtower, Caddy reload, Nextcloud OCC/cron, MariaDB/Postgres upgrades, Synapse delegation, Jellyfin hardware transcoding, Tailscale sidecar pattern, Cloudflare header stripping). Read the relevant README before changing a service in that directory — most non-obvious behavior is documented there, not in the YAML.

## Conventions when editing Compose files

- Split new services into their own file under `services/` and wire them into the parent `compose.yaml`'s `include:` list, rather than growing a single file.
- Networks are external/named (`homelab`, `nextcloud`, `servarr`, `spark`) and declared once in `networks/*.yaml`; reference them by name in services rather than redefining.
- GPU access uses the Compose `deploy.resources.reservations.devices` Nvidia pattern (see `spark/services/*.yaml`); Intel QuickSync uses `group_add` + `/dev/dri/renderD128` (see `compose/services/models.yaml` and the Jellyfin section of `compose/README.md`).
- Secrets/host paths are injected via `.env` files (`$VOLUMES_PATH`, `$HF_TOKEN`, `$TAILNET_FQDN`, etc.) — never hardcode a host path or token into a service YAML.
- `restart: unless-stopped` is the norm for long-running services; one-shot/manual services (e.g. `spark`'s `vllm`/`llamacpp`) use `restart: no` since they're swapped manually.

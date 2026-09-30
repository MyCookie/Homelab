# Spark

LLM inference stack. Runs either the `llamacpp-router` (a single llama.cpp server multiplexing several GGUF model/quantization presets) or one of the single-model `vllm-*` services. Only one model service should be included/uncommented in `compose.yaml` at a time, since they all bind port 8000 and reserve all GPUs.

## Prometheus

`services/monitoring.yaml` runs Prometheus, Grafana, and cAdvisor on the `spark` network. Scrape jobs live in `volumes/prometheus/prometheus.yaml`, which is mounted into the container as `/etc/prometheus/prometheus.yaml`.

| Job | Target | Source |
| --- | --- | --- |
| `cadvisor` | `cadvisor:8080` | Per-container CPU, memory, network, and block I/O (read from cgroups) |
| `docker` | `host.docker.internal:9323` | The Docker engine itself |

### Docker

cAdvisor is the `cadvisor` service. The engine endpoint is built into `dockerd` and is off by default. Add it to `/etc/docker/daemon.json` and restart Docker. This host uses the Nvidia runtime, so merge the key into the existing file rather than replacing it:

```json
{
  "metrics-addr": "0.0.0.0:9323"
}
```

```bash
sudo systemctl restart docker
curl -s localhost:9323/metrics | head
```

Older Docker versions also require `"experimental": true`. To keep the endpoint off the LAN, bind to the `docker0` bridge address (usually `172.17.0.1:9323`) and point the `docker` job at that address instead of `host.docker.internal`.

The `prometheus` service sets `extra_hosts: host.docker.internal:host-gateway` so the container can reach a port published on the host.

Restarting `dockerd` stops running containers (including whichever model service is up) unless `"live-restore": true` is set in `daemon.json`.

GPU metrics are not covered by either job. Use [dcgm-exporter](https://github.com/NVIDIA/dcgm-exporter) for those.

### Podman

Podman has no built-in Prometheus endpoint. Use [prometheus-podman-exporter](https://github.com/containers/prometheus-podman-exporter), which reads the Podman API socket and exposes container, pod, image, and volume metrics on port 9882.

Enable the API socket (rootful):

```bash
sudo systemctl enable --now podman.socket
```

Run the exporter:

```bash
sudo podman run -d --name podman-exporter \
  --user root --security-opt label=disable \
  -p 9882:9882 \
  -v /run/podman/podman.sock:/run/podman/podman.sock \
  -e CONTAINER_HOST=unix:///run/podman/podman.sock \
  quay.io/navidys/prometheus-podman-exporter
```

Then add a job to `prometheus.yaml`, using the host address if Prometheus runs elsewhere:

```yaml
  - job_name: podman
    static_configs:
      - targets:
          - <podman-host>:9882
```

cAdvisor also works against rootful Podman because it reads cgroups, but container names and labels are less reliable than with the exporter.

## Troubleshooting

### llamacpp-router fails to load `models.ini` after a Watchtower update

Symptom:

```console
$ docker logs llamacpp
...
E srv  llama_server: failed to initialize router models: preset file does not exist: /root/models.ini
```

and `docker compose up -d --force-recreate` fixes it until the next image update.

Cause: `models.ini` used to be defined as a Compose top-level `configs:` block with inline `content:`. Compose materializes that content to an ephemeral file on the host only when you run `docker compose up`, then bind-mounts it into the container. Watchtower doesn't go through `docker compose up` — it recreates the container directly via the Docker Engine API, cloning the previous container's bind-mount spec. By the time it does, the ephemeral file Compose generated is gone, so Docker silently mounts an empty directory at `/root/models.ini` instead.

Fix: `models.ini` is now bind-mounted from a real, persistent file (`volumes/llamacpp/models.ini`) instead of a Compose-managed `configs:` block, so the mount survives container recreation by any tool. The file must exist on the host at `~/.cache/llamacpp/models.ini` — copy or symlink `volumes/llamacpp/models.ini` there once per host:

```console
mkdir -p ~/.cache/llamacpp
ln -s "$(pwd)/volumes/llamacpp/models.ini" ~/.cache/llamacpp/models.ini
```
### `llama.cpp` fails to load GPT-OSS

Explicitly enable Jinja:

```
[ggml-org/gpt-oss-120b-GGUF:MXFP4]
LLAMA_ARG_ALIAS=gpt-oss,gpt-oss-120b
LLAMA_ARG_HF_REPO=ggml-org/gpt-oss-120b-GGUF:MXFP4
LLAMA_ARG_CTX_SIZE=131072
LLAMA_ARG_JINJA=true
```
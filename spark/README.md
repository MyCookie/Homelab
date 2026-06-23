# Spark

LLM inference stack. Runs either the `llamacpp-router` (a single llama.cpp server multiplexing several GGUF model/quantization presets) or one of the single-model `vllm-*` services. Only one model service should be included/uncommented in `compose.yaml` at a time, since they all bind port 8000 and reserve all GPUs.

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

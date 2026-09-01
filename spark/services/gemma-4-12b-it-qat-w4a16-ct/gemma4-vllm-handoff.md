# Gemma 4 / vLLM 0.26.0 MTP handoff for Codex CLI

## Environment

* Hardware: NVIDIA DGX Spark / GB10, ARM64
* OS/container target: Ubuntu 24.04 ARM64
* vLLM image:

  ```text
  vllm/vllm-openai:v0.26.0-aarch64-ubuntu2404
  ```
* Serving via Docker Compose
* Hugging Face cache mounted from host
* Goal: serve Gemma 4 with MTP speculative decoding and CUDA graphs enabled

## Working configuration: Gemma 4 31B

This configuration works:

```yaml
services:
  gemma4:
    container_name: gemma4
    image: vllm/vllm-openai:v0.26.0-aarch64-ubuntu2404
    ipc: host
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    ports:
      - "8000:8000"
    environment:
      - HF_TOKEN=${HF_TOKEN}
    volumes:
      - ~/.cache/huggingface:/root/.cache/huggingface
    configs:
      - source: vllm_runtime_config
        target: /etc/vllm/config.yaml
    command: --config /etc/vllm/config.yaml

configs:
  vllm_runtime_config:
    content: |
      model: "google/gemma-4-31B-it-qat-w4a16-ct"
      trust_remote_code: true
      gpu_memory_utilization: 0.8
      enable_per_request_metrics: true
      kv_cache_dtype: fp8
      max_model_len: 262144
      async_scheduling: true
      default_chat_template_kwargs: '{"preserve_thinking": true}'
      enable_auto_tool_choice: true
      tool_call_parser: gemma4
      enable_prefix_caching: true

      speculative_config:
        method: "mtp"
        model: "google/gemma-4-31B-it-qat-q4_0-unquantized-assistant"
        num_speculative_tokens: 2
```

## Failing configuration: Gemma 4 12B

Current Compose configuration:

```yaml
services:
  gemma4:
    container_name: gemma4

    build:
      context: .
      dockerfile: vllm-gemma-4-12B-w4a16-ct.Dockerfile

    image: local/vllm-openai:v0.26.0-gemma4-pr48515

    ipc: host
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

    ports:
      - "8000:8000"

    environment:
      - HF_TOKEN=${HF_TOKEN}

    volumes:
      - ~/.cache/huggingface:/root/.cache/huggingface

    configs:
      - source: vllm_runtime_config
        target: /etc/vllm/config.yaml

    command: --config /etc/vllm/config.yaml

configs:
  vllm_runtime_config:
    content: |
      model: "google/gemma-4-12B-it-qat-w4a16-ct"
      trust_remote_code: true
      gpu_memory_utilization: 0.4
      kv_cache_dtype: fp8
      max_model_len: 262144
      async_scheduling: true
      default_chat_template_kwargs: '{"preserve_thinking": true}'
      enable_auto_tool_choice: true
      tool_call_parser: gemma4
      enable_prefix_caching: true

      speculative_config:
        method: "mtp"
        model: "google/gemma-4-12B-it-qat-q4_0-unquantized-assistant"
        num_speculative_tokens: 4
```

## Diagnosis already established

The 12B target model and MTP assistant both load successfully.

The failure happens later during CUDA graph capture for the MTP speculator.

Relevant runtime sequence:

```text
Capturing CUDA graphs (PIECEWISE): 100%
Capturing CUDA graphs (FULL): 100%
Capturing model for speculator...
Capturing prefill CUDA graphs (PIECEWISE): 100%
Capturing prefill CUDA graphs (FULL): 0%
```

The traceback ends at:

```python
File "/usr/local/lib/python3.12/dist-packages/vllm/model_executor/models/gemma4_mtp.py", line 585, in compute_logits
    logits[:, self._suppress_token_ids] = -float("inf")
```

with:

```text
RuntimeError: Cannot copy between CPU and CUDA tensors during CUDA graph capture unless the CPU tensor is pinned.
```

The original logs also showed:

```text
Checkpoint size: 9.56 GiB
```

for the 12B target and:

```text
Checkpoint size: 0.79 GiB
```

for the MTP assistant, so this was not a model-loading failure.

KV cache allocation also succeeded with approximately:

```text
Available KV cache memory: 36.19 GiB
GPU KV cache size: 3,248,113 tokens
Maximum concurrency for 262,144 tokens per request: 12.39x
```

## Root cause

The 12B MTP assistant has `suppress_tokens` in its generation config.

In vLLM 0.26.0, `Gemma4MTP` stores these as a normal Python-side value:

```python
draft_cfg = vllm_config.speculative_config.draft_model_config
gen_cfg = draft_cfg.try_get_generation_config()
self._suppress_token_ids = gen_cfg.get("suppress_tokens") if gen_cfg else None
```

Later:

```python
if logits is not None and self._suppress_token_ids:
    logits[:, self._suppress_token_ids] = -float("inf")
```

During CUDA graph capture, that indexing path causes an implicit CPU-to-CUDA operation.

The 31B assistant does not exercise the same path because its generation config does not contain the same `suppress_tokens` setting.

## Upstream issue / intended fix

Relevant upstream work:

```text
https://github.com/vllm-project/vllm/pull/48515
```

The essential fix is:

1. Convert `suppress_token_ids` into a `torch.long` tensor.
2. Register it as a model buffer so it moves onto the CUDA device.
3. Replace advanced-index assignment with `index_fill_`.

Conceptually:

```python
suppress_token_ids = gen_cfg.get("suppress_tokens") if gen_cfg else None

self.register_buffer(
    "_suppress_token_ids",
    (
        torch.tensor(suppress_token_ids, dtype=torch.long)
        if suppress_token_ids
        else None
    ),
    persistent=False,
)
```

and:

```python
if logits is not None and self._suppress_token_ids is not None:
    logits.index_fill_(1, self._suppress_token_ids, float("-inf"))
```

## Backport approach

Do not rebuild all of vLLM unless necessary.

The chosen approach is to derive from the official ARM64 image and patch:

```text
/usr/local/lib/python3.12/dist-packages/vllm/model_executor/models/gemma4_mtp.py
```

directly during `docker build`.

In vLLM 0.26.0, this is the relevant file containing the problematic suppression logic.

## Current Dockerfile

Use this corrected version:

```dockerfile
# syntax=docker/dockerfile:1

FROM vllm/vllm-openai:v0.26.0-aarch64-ubuntu2404

# Backport vLLM PR #48515.
#
# Fix Gemma 4 MTP suppress_token_ids handling during CUDA graph capture:
#   1. Store suppress_token_ids as a registered torch.long buffer.
#   2. Replace advanced-index assignment with index_fill_.

RUN python3 - <<'PY'
from pathlib import Path

path = Path(
    "/usr/local/lib/python3.12/dist-packages/"
    "vllm/model_executor/models/gemma4_mtp.py"
)

if not path.exists():
    raise RuntimeError(f"Expected vLLM source file not found: {path}")

source = path.read_text()

old_init = '''        draft_cfg = vllm_config.speculative_config.draft_model_config
        gen_cfg = draft_cfg.try_get_generation_config()
        self._suppress_token_ids = gen_cfg.get("suppress_tokens") if gen_cfg else None
'''

new_init = '''        draft_cfg = vllm_config.speculative_config.draft_model_config
        gen_cfg = draft_cfg.try_get_generation_config()
        suppress_token_ids = gen_cfg.get("suppress_tokens") if gen_cfg else None
        self.register_buffer(
            "_suppress_token_ids",
            (
                torch.tensor(suppress_token_ids, dtype=torch.long)
                if suppress_token_ids
                else None
            ),
            persistent=False,
        )
'''

old_logits = '''        if logits is not None and self._suppress_token_ids:
            logits[:, self._suppress_token_ids] = -float("inf")
'''

new_logits = '''        if logits is not None and self._suppress_token_ids is not None:
            logits.index_fill_(1, self._suppress_token_ids, float("-inf"))
'''

if source.count(old_init) != 1:
    raise RuntimeError(
        "PR #48515 init patch target was not found exactly once. "
        "Refusing to build."
    )

if source.count(old_logits) != 1:
    raise RuntimeError(
        "PR #48515 compute_logits patch target was not found exactly once. "
        "Refusing to build."
    )

source = source.replace(old_init, new_init, 1)
source = source.replace(old_logits, new_logits, 1)

path.write_text(source)

patched = path.read_text()

if '"_suppress_token_ids"' not in patched:
    raise RuntimeError("Missing _suppress_token_ids after patch")

if "self.register_buffer(" not in patched:
    raise RuntimeError("register_buffer patch was not applied")

if 'logits.index_fill_(1, self._suppress_token_ids, float("-inf"))' not in patched:
    raise RuntimeError("index_fill_ patch was not applied")

if 'logits[:, self._suppress_token_ids] = -float("inf")' in patched:
    raise RuntimeError("Old CUDA-graph-unsafe logits assignment still present")

print(f"Successfully applied Gemma 4 MTP CUDA-graph fix to {path}")
PY

RUN python3 -m py_compile \
    /usr/local/lib/python3.12/dist-packages/vllm/model_executor/models/gemma4_mtp.py
```

## Previous Docker build failure

The first version of the Dockerfile failed with:

```text
AssertionError
```

after applying the patch.

That was not evidence that the patch failed.

The original post-patch check incorrectly contained:

```python
assert 'self.register_buffer(\\n            "_suppress_token_ids"' in patched
```

The `\\n` tested for a literal backslash followed by `n`, rather than an actual newline.

The patch target validation had already succeeded, both replacements had executed, and the file had been written before this assertion failed.

The corrected Dockerfile above removes that fragile whitespace-sensitive assertion.

## Next actions for Codex

Work directly in the existing Spark repository.

First inspect:

```bash
pwd
git status
cat services/vllm-gemma-4-12B-w4a16-ct.Dockerfile
cat services/vllm-gemma-4-12B-w4a16-ct.yaml
```

Then build the corrected image:

```bash
docker compose build --no-cache gemma4
```

If the build succeeds, start it:

```bash
docker compose up gemma4
```

The primary success criterion is that startup progresses through:

```text
Capturing model for speculator...
Capturing prefill CUDA graphs (PIECEWISE): 100%
Capturing prefill CUDA graphs (FULL): 100%
```

without the previous CPU/CUDA tensor-copy exception.

If a different error occurs, diagnose that error rather than reverting immediately to `enforce_eager`.

## Important constraints

* Preserve:

  ```text
  vllm/vllm-openai:v0.26.0-aarch64-ubuntu2404
  ```

  as the base unless there is a strong technical reason to change it.

* Do not disable CUDA graphs as the final solution.

* Do not add:

  ```yaml
  enforce_eager: true
  ```

  except as a temporary diagnostic.

* Preserve MTP speculative decoding.

* Do not assume `num_speculative_tokens: 4` is optimal.

vLLM already warns:

```text
Enabling num_speculative_tokens > 1 will run multiple times of forward on same MTP layer, which may result in lower acceptance rate
```

Once the model boots correctly, benchmark:

```text
num_speculative_tokens: 1
num_speculative_tokens: 2
num_speculative_tokens: 4
```

using actual throughput and speculative acceptance metrics on the DGX Spark.

## Codex objective

Continue from the current repository state and get this configuration running:

```text
google/gemma-4-12B-it-qat-w4a16-ct
+
google/gemma-4-12B-it-qat-q4_0-unquantized-assistant
+
vLLM 0.26.0
+
CUDA graphs
+
MTP speculative decoding
+
DGX Spark / ARM64
```

Prefer a minimal, auditable backport over broad source-tree changes.


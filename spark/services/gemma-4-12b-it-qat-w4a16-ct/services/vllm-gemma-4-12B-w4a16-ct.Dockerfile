# syntax=docker/dockerfile:1

FROM vllm/vllm-openai:v0.26.0-aarch64-ubuntu2404

# Install the optional dependencies declared by vLLM audio support without
# reinstalling or upgrading the vLLM package from the official ARM64 image.
RUN uv pip install --system --no-cache \
        av \
        scipy \
        soundfile \
        soxr \
        "mistral-common[audio]" \
    && python3 -c \
        "import av, scipy, soundfile, soxr; import mistral_common"

# Backport vLLM PR #48515:
# https://github.com/vllm-project/vllm/pull/48515
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

# Verify we're patching exactly the expected v0.26.0 source.
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

# Post-patch sanity checks. Keep these independent of formatting/whitespace.
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

# Verify that the modified module is syntactically valid.
RUN python3 -m py_compile \
    /usr/local/lib/python3.12/dist-packages/vllm/model_executor/models/gemma4_mtp.py

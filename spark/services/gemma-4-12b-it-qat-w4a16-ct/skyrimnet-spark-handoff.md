# SkyrimNet + DGX Spark Prefill Optimization Handoff

## Goal

Optimize local inference for **SkyrimNet** on a **DGX Spark / GB10**, with an emphasis on:

* low **time-to-first-token**
* high **prefill throughput**
* acceptable multimodal/vision latency
* stable performance under SkyrimNet's bursty concurrent request pattern

This is a casual-use setup, not a pursuit of maximum model quality. The target experience is simply responsive enough for relaxed Skyrim sessions.

The mod's GitHub is: https://github.com/MinLL/SkyrimNet-GamePlugin

## Current Model

Primary model:

```text
Gemma 4 12B
```

The intent is to use the **Gemma 4 12B unified multimodal implementation**, rather than a conventional VLM with a separate vision transformer.

The exact checkpoint/container/YAML should be inspected in the Codex session before making changes.

## Hardware Constraints

Hardware:

```text
NVIDIA DGX Spark
GB10
128 GB unified memory
~273 GB/s memory bandwidth
```

Important architectural constraint:

The Spark has a large unified memory pool but relatively modest memory bandwidth for LLM inference.

The workload should therefore be treated as heavily sensitive to:

* memory traffic
* model working-set size
* KV-cache traffic
* repeated loading/access of separate model weights
* concurrent prefill workloads

Headline FP4 compute is less likely to be the limiting factor than memory behavior for much of this workload.

---

# SkyrimNet Workload Characteristics

SkyrimNet is not a normal chatbot workload.

It can simultaneously perform tasks such as:

```text
NPC dialogue
action selection
gamemaster/world reasoning
memory/event processing
vision/screenshot interpretation
other background agent operations
```

Requests may contain several thousand input tokens, while generated responses are comparatively short.

Therefore the primary optimization target is:

```text
PREFILL / TTFT
```

rather than:

```text
DECODE TOKENS/SECOND
```

A model with faster prompt ingestion but somewhat slower generation may feel substantially better in SkyrimNet.

Representative benchmarks should therefore look like:

```text
5k input / 150 output
10k input / 150 output
20k input / 150 output
```

at concurrency levels such as:

```text
1
4
8
```

Record at least:

```text
TTFT
prompt tokens/sec
output tokens/sec
p50 request latency
p95 request latency
```

---

# Current Architectural Hypothesis

## Prefer one model initially

Earlier consideration was given to using separate models for dialogue and utility/background requests.

Current conclusion:

**Do not start there on DGX Spark.**

Using multiple concurrently active models could cause disproportionately poor performance because:

* both models share the same 273 GB/s unified-memory subsystem
* separate vLLM instances cannot batch requests together
* alternating models reduces cache locality
* both may generate large memory-bandwidth demands during prefill
* excessive unified-memory pressure may introduce reclamation/page-management effects
* SkyrimNet can switch between workloads rapidly

The likely topology to test first is therefore:

```text
              +-- dialogue
              +-- actions
SkyrimNet ----+-- vision
              +-- gamemaster
              +-- misc
                    |
                    v
             Gemma 4 12B
                    |
                    v
             one vLLM engine
```

This gives one scheduler the opportunity to continuously batch SkyrimNet requests.

A second small model should only be tested later if profiling shows that background requests are consistently blocking interactive dialogue.

---

# Vision Is a Major Reason for Choosing Gemma 4 12B

Conventional multimodal models often look roughly like:

```text
image
  |
  v
BF16/FP16 vision transformer
  |
  v
visual embeddings
  |
  v
projector
  |
  v
quantized LLM
```

This is undesirable on Spark because the vision tower is often left in BF16/FP16 even when the LLM itself is aggressively quantized.

That adds:

* additional high-precision weights
* another large working set
* extra memory traffic
* vision-transformer compute before LLM prefill even begins

This has been a particular concern with Qwen 3.x vision models, where the vision subsystem has felt too expensive relative to the resulting quality.

## Gemma 4 12B Unified

The Gemma 4 12B unified architecture is interesting because its multimodal path is **encoder-free**.

Conceptually:

```text
raw image patches
      |
      v
normalization
      |
      v
dense patch projection
      |
      v
2D positional information
      |
      v
multimodal projection
      |
      v
Gemma language model
```

There is no conventional SigLIP/ViT-style vision tower in this path.

That potentially offers two benefits:

1. Much lower image preprocessing/encoding cost.
2. A much smaller vision-related working set competing for Spark memory bandwidth.

This is a major reason to evaluate Gemma 4 12B rather than Gemma 4 31B or Qwen 3.x VLMs.

Do not assume that a 26B MoE model will necessarily beat it for this workload simply because relatively few experts are active. End-to-end image-to-first-token latency includes the multimodal frontend and memory behavior, not merely active LM parameter count.

---

# Important Implementation Check

Verify that the running model actually uses vLLM's **Gemma 4 unified multimodal implementation**.

The relevant implementation should correspond to something equivalent to:

```text
Gemma4UnifiedForConditionalGeneration
```

Do not accidentally benchmark a compatibility/model path that uses a traditional external vision encoder.

Inspect:

* vLLM model registration
* model class selected at startup
* checkpoint configuration
* startup logs
* multimodal processor configuration

This verification is important before drawing conclusions about vision performance.

---

# vLLM Prefill Strategy

The initial tuning direction should emphasize large, efficient prefills.

Candidate baseline:

```yaml
enable_prefix_caching: true
enable_chunked_prefill: true

max_num_batched_tokens: 32768
max_num_seqs: 16

async_scheduling: true
```

Exact field availability/defaults depend on the vLLM version being used.

## Benchmark `max_num_batched_tokens`

Test at least:

```text
8192
16384
32768
65536
```

Hold everything else constant.

For SkyrimNet, `32768` is currently the most promising starting point, but this should be demonstrated empirically.

A larger token budget may allow concurrent SkyrimNet prefills to be combined into efficient GPU work rather than processed as many small chunks.

Do not optimize this configuration around inter-token latency at the expense of TTFT.

---

# Prefix Caching

Prefix caching may be one of the largest available optimizations.

Enable it explicitly:

```yaml
enable_prefix_caching: true
```

However, cache effectiveness depends on SkyrimNet prompt structure.

Ideal structure:

```text
[stable global system prompt]
[stable action/tool instructions]
[stable NPC information]
[mostly stable world information]
[volatile current state]
[current conversation]
[current user action]
```

Poor structure:

```text
[current time]
[current location]
[current random/session data]
[stable global instructions]
[stable NPC information]
...
```

If volatile information occurs near the front of the prompt, the reusable prefix may become very small.

## Codex investigation task

Inspect SkyrimNet's prompt-building implementation/templates and determine:

1. What parts of the prompt are common across requests?
2. What varies every request?
3. In what order are decorators/templates concatenated?
4. Can stable material safely be moved earlier?
5. Does SkyrimNet inject timestamps, location, dynamic state, UUID-like data, or similar material before otherwise reusable content?
6. Do different request classes have independently reusable prefixes?

Do not make semantic prompt changes merely for cache efficiency without verifying that ordering does not affect model behavior.

---

# Context Length

Do not allocate an enormous context window simply because the model supports it.

Determine actual SkyrimNet prompt-length distribution first.

If real workloads are approximately:

```text
typical:       5k-10k
large:         10k-20k
pathological:  20k-30k
```

then something like:

```yaml
max_model_len: 32768
```

or possibly:

```yaml
max_model_len: 49152
```

may be preferable to a 128k/256k configuration.

The goal is not that a smaller configured context magically makes matrix multiplication faster. It is to keep memory allocation and KV-cache planning aligned with the workload instead of reserving for unrealistic contexts.

---

# KV Cache

Current preference is likely:

```yaml
kv_cache_dtype: fp8
```

provided Gemma 4 behaves acceptably with it.

Expected benefit:

* substantially larger effective KV capacity
* lower cache memory traffic
* more headroom for concurrent requests

Do not treat FP8 KV as the primary solution to slow first-prefill compute.

Its main advantages are cache capacity and attention/cache bandwidth.

Evaluate quality separately if needed.

---

# Quantization

Aggressive weight quantization is desirable on Spark because reduced model-weight traffic can directly benefit inference on its bandwidth-constrained UMA design.

Current experiments around Gemma 4 have included QAT/NVFP4-style variants.

For SkyrimNet specifically:

* favor quantization with fast kernels on GB10
* benchmark prefill, not only decode
* avoid assuming the smallest checkpoint on disk is the fastest
* verify whether quantized kernels are actually used for prompt GEMMs
* watch for fallback paths on ARM64 / Blackwell / GB10

---

# Do Not Prioritize MTP / Speculative Decoding Yet

MTP/speculative decoding is primarily useful for accelerating autoregressive generation.

SkyrimNet currently appears to be dominated by:

```text
long input
+
short output
```

Therefore MTP is not the first optimization target.

Only revisit it after:

```text
vision processing
prompt construction
prefix caching
prefill batching
```

have been optimized.

---

# Vision Benchmarking

Do not measure vision performance using aggregate token throughput alone.

Create four test classes.

## A. Text baseline

```text
text only
very short prompt
no image
```

Measure TTFT.

## B. Vision frontend

```text
image
+
tiny text prompt
```

Measure TTFT.

Approximate additional multimodal cost as:

```text
vision overhead ~= TTFT(B) - TTFT(A)
```

## C. Realistic SkyrimNet multimodal request

```text
image
+
normal SkyrimNet prompt/context
```

Measure TTFT.

This identifies the actual user-facing cost.

## D. Repeated request

Repeat the same or closely related:

```text
image
+
prompt prefix
```

and measure whether:

* multimodal preprocessing is cached
* prefix caching hits
* the repeated request materially improves

Also inspect vLLM metrics/logging to distinguish multimodal preprocessing cache hits from LLM prefix-cache hits if possible.

---

# Determine Whether Vision or Text Is Actually the Bottleneck

The working hypothesis is:

Once using Gemma 4 12B Unified, the conventional heavy vision-tower cost may disappear sufficiently that **SkyrimNet's text prompt becomes the dominant latency source**.

This should be demonstrated rather than assumed.

Measure separately:

```text
image processing time
LLM prefill time
queue/scheduler delay
decode time
```

If possible, instrument request timing from both:

```text
SkyrimNet client side
vLLM server side
```

This will distinguish:

```text
SkyrimNet preparation
network/API delay
queueing
multimodal preprocessing
prefill
decode
```

---

# Investigate SkyrimNet Prompt Bloat

Inspect actual request bodies generated during play.

Capture representative examples for:

```text
dialogue
vision
actions
gamemaster
memory/background work
```

For each request, report:

```text
input token count
output token count
system/template token count
NPC bio token count
history/event token count
dynamic world-state token count
vision-token count
```

Look for:

* duplicated lore
* duplicated character descriptions
* excessive historical events
* equipment lists
* appearance descriptions
* full world state where only a small subset is relevant
* repetitive action descriptions
* repeated plugin metadata

Do not immediately remove data.

First quantify where the token budget is going.

---

# Concurrency

SkyrimNet may produce multiple simultaneous or near-simultaneous requests.

Test:

```text
max_num_seqs:
8
16
32
```

Do not assume the vLLM default is optimal.

The goal is enough concurrency to batch SkyrimNet's background requests without allowing so much outstanding work that interactive dialogue is starved or the KV cache becomes excessively fragmented.

Investigate scheduler metrics if exposed.

Potentially useful quantities:

```text
number of waiting requests
number of running requests
prefill tokens scheduled per iteration
KV cache utilization
prefix cache hit rate
TTFT distribution
```

---

# Secondary Experiment: Two Models

Only after obtaining a good one-model baseline, test whether routing trivial/background work to a second small model helps.

Possible topology:

```text
                        +--> Gemma 4 12B
                        |    dialogue
SkyrimNet --> router ---+    vision
                        |    important reasoning
                        |
                        +--> 4B/8B model
                             action/meta/background work
```

The question is not whether the small model is faster in isolation.

Measure whether **total user-facing dialogue latency improves while both models are active**.

Specifically look for:

* worsening Gemma prefill throughput
* increased TTFT
* memory bandwidth contention
* increased GPU scheduling/context-switch overhead
* cache locality loss
* UMA memory pressure/reclamation
* inability to batch requests across engines

If the second model causes nonlinear degradation, abandon this approach.

A single Gemma 4 12B engine is the preferred baseline.

---

# Suggested Experimental Matrix

Keep all tests reproducible.

## Phase 1 — Baseline

Current configuration.

Measure:

```text
text-only prefill
vision TTFT
real SkyrimNet dialogue
real SkyrimNet vision request
```

## Phase 2 — Prefix cache

Enable/verify:

```yaml
enable_prefix_caching: true
```

Measure cold vs warm requests.

Record cache hit statistics.

## Phase 3 — Prefill batching

Test:

```text
max_num_batched_tokens:
8192
16384
32768
65536
```

## Phase 4 — Sequence concurrency

Test best token budget with:

```text
max_num_seqs:
8
16
32
```

## Phase 5 — Context allocation

Compare sensible values such as:

```text
32768
49152
65536
```

if the workload requires them.

## Phase 6 — SkyrimNet prompt analysis

Capture real prompts and quantify token composition.

Then consider cache-friendly reordering or pruning.

## Phase 7 — Optional secondary model

Only if required.

Benchmark under actual simultaneous load rather than isolated synthetic tests.

---

# Success Criteria

The goal is not maximum benchmark throughput.

A successful setup should prioritize:

1. Dialogue starts quickly after the player speaks.
2. Screenshot/vision requests do not create multi-second stalls.
3. Background SkyrimNet jobs do not regularly block dialogue.
4. Once output starts, generation only needs to be comfortably faster than perceived speech/TTS consumption.
5. Performance remains consistent over a long gaming session.
6. No serious UMA/swap/reclamation behavior develops over time.

A modest-quality 12B model with good TTFT is preferable to a smarter model that feels sluggish.

---

# Codex CLI Requested Work

Please inspect the actual local configuration and SkyrimNet installation and then:

1. Identify the precise Gemma 4 12B checkpoint.
2. Identify the vLLM version/container.
3. Confirm whether the model is using the unified encoder-free multimodal implementation.
4. Review the current vLLM YAML.
5. Check whether prefix caching and chunked prefill are enabled/effective.
6. Inspect current `max_num_batched_tokens`, `max_num_seqs`, context length, and KV configuration.
7. Capture representative SkyrimNet API requests if practical.
8. Analyze their token composition.
9. Inspect SkyrimNet prompt/template ordering for prefix-cache friendliness.
10. Design a reproducible benchmark for text-prefill and image-to-first-token latency.
11. Change one variable at a time.
12. Prefer measured improvements over theoretical tuning.
13. Do not optimize speculative decoding until prefill is under control.
14. Avoid introducing a second concurrently active model unless benchmark data demonstrates a net improvement.

When proposing configuration changes, explain the expected effect specifically in terms of:

```text
TTFT
prefill tok/s
memory bandwidth
KV usage
batching
prefix reuse
vision preprocessing
```

rather than generic LLM-performance advice.


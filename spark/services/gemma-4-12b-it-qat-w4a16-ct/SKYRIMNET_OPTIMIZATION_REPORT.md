# SkyrimNet + Gemma 4 12B Optimization Report

Date: 2026-08-25

## Scope and limitations

This report covers the local Gemma/vLLM server and a static audit of SkyrimNet's
public prompt templates. No live SkyrimNet request capture was available, so the
latency workload is synthetic. The benchmark deliberately matches the proposed
5k/10k/20k input lengths and concurrency 1/4/8, but it does not claim to reproduce
the mod's actual request distribution.

The prompt audit uses SkyrimNet commit
`20f634c9ee76fe514d431ef5f2a7964d4226b7d0` (2026-08-23).

## Verified server state

- Checkpoint: `google/gemma-4-12B-it-qat-w4a16-ct`
- vLLM: `0.26.0`
- Architecture: `Gemma4UnifiedForConditionalGeneration`
- Quantization: compressed-tensors W4A16 using `MarlinLinearKernel`
- KV cache: FP8
- Chunked prefill: enabled
- Prefix caching: enabled
- MTP: enabled with four speculative tokens
- GPU memory utilization: 0.25
- Current explicit scheduler settings:
  - `max_num_batched_tokens: 2496`
  - `max_num_seqs: 16`
- Context limit remains 262,144 because no real prompt-length distribution exists
  yet. Reducing it was not shown to improve latency and could reject an unknown
  real request.

## Text-prefill screening results

All screening requests generated eight output tokens to isolate prefill. Each
cell is one simultaneous batch, so percentiles are descriptive rather than a
high-confidence population estimate.

### Selected baseline: MTP, 2,496 batched tokens

| Input | Concurrency | Cold TTFT p50 | Cold TTFT p95 | Warm TTFT p50 |
|---:|---:|---:|---:|---:|
| 5k | 1 | 2.47s | 2.47s | 0.18s |
| 5k | 4 | 8.20s | 9.57s | 0.39s |
| 5k | 8 | 12.90s | 19.01s | 0.60s |
| 10k | 1 | 5.16s | 5.16s | 0.21s |
| 10k | 4 | 14.91s | 19.92s | 0.48s |
| 10k | 8 | 24.96s | 39.50s | 0.73s |
| 20k | 1 | 11.56s | 11.56s | 0.24s |
| 20k | 4 | 30.64s | 44.18s | 0.57s |
| 20k | 8 | 53.36s | 87.83s | 0.95s |

The warm cases prime one exact shared prefix before measuring the batch. They
demonstrate the available upside of prefix stability; they are not a prediction
that SkyrimNet achieves these hit rates.

### Scheduler comparison

| Input / concurrency | 2,496 p50 | 8,192 p50 | 16,384 p50 |
|---|---:|---:|---:|
| 5k / 4 | 8.20s | 9.33s | 9.88s |
| 5k / 8 | 12.90s | 15.48s | 17.88s |
| 10k / 4 | 14.91s | 17.77s | 19.84s |
| 10k / 8 | 24.96s | 28.12s | 33.75s |
| 20k / 4 | 30.64s | 33.52s | 40.32s |
| 20k / 8 | 53.36s | 56.42s | 63.55s |

Larger batches made completion times more uniform and improved aggregate tail
completion by only about 1-2% in some concurrency-8 cases. They consistently
delayed the median first token, which is the wrong trade for interactive dialogue.
The 16,384 setting also reduced reported KV capacity to roughly 623k tokens and
increased graph/activation memory. A 32,768 test was skipped because the trend
was already adverse.

Setting `max_num_seqs: 16` did not materially change performance at measured
concurrency 1/4/8 and did not remove vLLM's MTP scheduler warning. It remains a
reasonable guardrail against an unbounded request flood.

## MTP tradeoff

Disabling MTP reduced model memory from 9.1 GiB to 8.32 GiB, reduced profiled peak
activation from 1.97 GiB to 0.35 GiB, and increased KV cache memory from about
17.8 GiB to 20.2 GiB. Cold long-prefill TTFT improved by roughly 5-6% in several
10k/20k concurrent cases, but the result was mixed at 5k.

Representative 150-token results favored retaining MTP:

| Input / concurrency | MTP TTFT | MTP total | No-MTP TTFT | No-MTP total |
|---|---:|---:|---:|---:|
| 5k / 1 | 2.53s | 5.75s | 2.40s | 8.72s |
| 20k / 1 | 11.89s | 16.15s | 10.97s | 17.64s |
| 5k / 4 | 7.06s p50 | 13.54s p95 | 6.87s p50 | 15.68s p95 |
| 20k / 4 | 30.67s p50 | 50.31s p95 | 29.44s p50 | 50.39s p95 |

MTP slightly increases TTFT but materially improves single-request completion and
therefore how quickly streamed dialogue becomes available to downstream TTS.

## Vision latency

The benchmark uses public-domain fixtures already documented in
`tests/assets/SOURCES.md`. A separate Apollo video frame was extracted to guarantee
an uncached image. Unique text prefixes prevent accidental prefix-cache reuse in
the corrected cold realistic run.

| Scenario | Cold TTFT | Repeated TTFT |
|---|---:|---:|
| Tiny text, 21 tokens | 0.11s | 0.12s |
| Image + tiny text, 287 tokens | 2.64s | 0.17s |
| Image + realistic 5k text, 5,010 tokens | 2.87s | 0.18-0.19s |

The first image adds about 2.53s over the tiny-text baseline. vLLM metrics showed
six multimodal-cache queries and five hits during the original three-pass test,
confirming that the repeated-image improvement is a real multimodal cache effect.
The corrected realistic measurement shows that unified image processing and text
prefill do not behave like two fully serial costs on this model.

## Static SkyrimNet prompt audit

The principal dialogue order is:

1. NPC-specific identity in the system message.
2. `system_head`, in filename order:
   stable task/format rules, full actor bios, live scene context, current
   OmniSight descriptions, and speech style.
3. Event history as alternating user/assistant messages.
4. `user_final_instructions`, including response format, audio tags, eligible
   actions, direct narration, and recent state changes.

Important consequences:

- The first rendered tokens contain NPC identity. Cross-NPC prefix reuse is
  therefore effectively unavailable even though many global rules are identical.
- Full actor profiles and live scene context occur before event history. A changed
  actor, target, scene, linked identity, or OmniSight description invalidates all
  downstream prefix reuse.
- Stable response-format and audio-tag instructions occur after dynamic event
  history, so their tokens cannot be reused when history changes.
- Event-history templates include relative time, game-time strings, locations,
  actors, and formatted event content. They are intentionally volatile.
- `8000_recent_state_changes.prompt` reads health, magicka, stamina, equipment,
  and tracked state. It is late in the prompt but can still add per-request churn.
- The action selector includes a full character profile in its system message and
  location, compact history, last player speech, and nearby actors in its user
  message.
- The gamemaster planner places current location, time, nearby actors, profiles,
  and compact event history in its system message, making exact reuse unlikely.
- No active shipped prompt uses `[ cache ]`; the marker appears only in prompt
  authoring documentation. vLLM automatic prefix caching depends on identical
  leading tokens regardless of that marker.

## Prompt changes worth A/B testing later

Do not apply these without rendered prompts and behavior checks:

1. Put genuinely global, stable dialogue/output rules before NPC identity and
   other dynamic fields so different NPC requests can share an initial prefix.
2. Keep NPC profile and stable speech style ahead of history for same-NPC reuse,
   but move live scene/OmniSight state after the stable actor material.
3. Move stable response-format rules ahead of event history while leaving truly
   dynamic action lists, combat state, and recent-state changes near the end.
4. Quantify event-history tokens before changing event count or relevance rules.
   The upstream templates defer the count to `get_event_history_count`, so static
   source alone cannot reveal the rendered size.
5. Treat dialogue, action selection, gamemaster, memory, and vision as separate
   prefix families. Attempting one global common prefix may harm prompt semantics.

## Recommended current server baseline

Keep the present configuration:

```yaml
gpu_memory_utilization: 0.25
kv_cache_dtype: fp8
max_model_len: 262144
max_num_batched_tokens: 2496
max_num_seqs: 16
async_scheduling: true
enable_prefix_caching: true
speculative_config:
  method: mtp
  model: google/gemma-4-12B-it-qat-q4_0-unquantized-assistant
  num_speculative_tokens: 4
```

The unusually small batched-token budget is intentional: larger values improved
aggregate completion only marginally while worsening first-token latency. Revisit
the context limit only after observing actual rendered prompt lengths.

## Remaining live-data work

A future play-session capture is still needed to determine:

- request class frequency and burst timing;
- actual prompt/output token distributions;
- real prefix-cache hit rate by request class and NPC;
- token contribution from profiles, events, world state, action lists, and vision;
- client-side template rendering, queuing, network, and retry time;
- whether background jobs starve interactive dialogue.

## Reproduction artifacts

- `benchmarks/skyrimnet_prefill_bench.py`
- `benchmarks/skyrimnet_vision_bench.py`
- `benchmarks/results/*.json`
- `benchmarks/assets/apollo-frame-10s.jpg`
- `tests/assets/SOURCES.md`

Upstream sources:

- <https://github.com/MinLL/SkyrimNet-GamePlugin/tree/20f634c9ee76fe514d431ef5f2a7964d4226b7d0/SKSE/Plugins/SkyrimNet/prompts>
- <https://github.com/MinLL/SkyrimNet-GamePlugin/blob/20f634c9ee76fe514d431ef5f2a7964d4226b7d0/docs/modding/WORKFLOW_PROMPTS.md>

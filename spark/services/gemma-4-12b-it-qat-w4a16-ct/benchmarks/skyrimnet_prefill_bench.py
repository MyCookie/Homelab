#!/usr/bin/env python3
"""Synthetic SkyrimNet-shaped TTFT and prefill benchmark for a vLLM server."""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import math
import statistics
import time
import urllib.request
import uuid
from dataclasses import asdict, dataclass
from pathlib import Path


LORE = (
    "The road winds through a cold pine forest near Whiterun while distant guards "
    "watch the valley. Lydia remembers the recent journey, the people involved, "
    "their promises, equipment, relationships, and unresolved plans. "
)


@dataclass
class Result:
    target_tokens: int
    concurrency: int
    cache_mode: str
    request_index: int
    prompt_tokens: int | None
    output_tokens: int | None
    ttft_seconds: float
    total_seconds: float
    prompt_tokens_per_second: float | None
    output_tokens_per_second: float | None
    error: str | None = None


def percentile(values: list[float], quantile: float) -> float:
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * quantile
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def post_json(url: str, payload: dict, timeout: float):
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    return urllib.request.urlopen(request, timeout=timeout)


def token_count(base_url: str, model: str, messages: list[dict], timeout: float) -> int:
    with post_json(
        f"{base_url}/tokenize",
        {"model": model, "messages": messages, "add_generation_prompt": True},
        timeout,
    ) as response:
        payload = json.load(response)
    return int(payload["count"])


def build_messages(
    base_url: str,
    model: str,
    target_tokens: int,
    cache_key: str,
    request_index: int,
    timeout: float,
) -> list[dict]:
    system = (
        f"Synthetic SkyrimNet benchmark profile {cache_key}. You are Lydia, a Nord "
        "housecarl in Skyrim. Remain in character and answer the final instruction.\n"
    )
    final = (
        f"Current event {request_index}: The player asks whether the road is safe. "
        "Reply with exactly 150 short numbered words."
    )
    low, high = 0, max(1, target_tokens // 20)
    while True:
        messages = [
            {"role": "system", "content": system + LORE * high},
            {"role": "user", "content": final},
        ]
        if token_count(base_url, model, messages, timeout) >= target_tokens:
            break
        high *= 2

    while low + 1 < high:
        middle = (low + high) // 2
        messages[0]["content"] = system + LORE * middle
        if token_count(base_url, model, messages, timeout) < target_tokens:
            low = middle
        else:
            high = middle
    messages[0]["content"] = system + LORE * high
    return messages


def run_request(
    base_url: str,
    model: str,
    messages: list[dict],
    target_tokens: int,
    concurrency: int,
    cache_mode: str,
    request_index: int,
    max_tokens: int,
    timeout: float,
) -> Result:
    payload = {
        "model": model,
        "messages": messages,
        "stream": True,
        "stream_options": {"include_usage": True},
        "temperature": 0.0,
        "max_tokens": max_tokens,
        "ignore_eos": True,
    }
    started = time.perf_counter()
    first_token_at = None
    usage = {}
    try:
        with post_json(f"{base_url}/v1/chat/completions", payload, timeout) as response:
            for raw_line in response:
                line = raw_line.decode("utf-8", errors="replace").strip()
                if not line.startswith("data: ") or line == "data: [DONE]":
                    continue
                chunk = json.loads(line[6:])
                if chunk.get("usage"):
                    usage = chunk["usage"]
                for choice in chunk.get("choices", []):
                    delta = choice.get("delta", {})
                    if first_token_at is None and (delta.get("content") or delta.get("reasoning_content")):
                        first_token_at = time.perf_counter()
        finished = time.perf_counter()
        ttft = (first_token_at or finished) - started
        prompt_tokens = usage.get("prompt_tokens")
        output_tokens = usage.get("completion_tokens")
        decode_seconds = max(finished - (first_token_at or finished), 1e-9)
        return Result(
            target_tokens,
            concurrency,
            cache_mode,
            request_index,
            prompt_tokens,
            output_tokens,
            ttft,
            finished - started,
            prompt_tokens / ttft if prompt_tokens else None,
            output_tokens / decode_seconds if output_tokens else None,
        )
    except Exception as exc:
        finished = time.perf_counter()
        return Result(
            target_tokens,
            concurrency,
            cache_mode,
            request_index,
            None,
            None,
            finished - started,
            finished - started,
            None,
            None,
            f"{type(exc).__name__}: {exc}",
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8001")
    parser.add_argument("--model", default="google/gemma-4-12B-it-qat-w4a16-ct")
    parser.add_argument("--tokens", type=int, nargs="+", default=[5000, 10000, 20000])
    parser.add_argument("--concurrency", type=int, nargs="+", default=[1, 4, 8])
    parser.add_argument("--cache-modes", nargs="+", choices=["cold", "warm"], default=["cold", "warm"])
    parser.add_argument("--repetitions", type=int, default=2)
    parser.add_argument("--max-tokens", type=int, default=150)
    parser.add_argument("--timeout", type=float, default=600.0)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    args.base_url = args.base_url.rstrip("/")
    all_results: list[Result] = []
    for target_tokens in args.tokens:
        for cache_mode in args.cache_modes:
            shared_key = f"warm-{target_tokens}-{uuid.uuid4().hex}"
            for concurrency in args.concurrency:
                for repetition in range(args.repetitions):
                    messages_batch = []
                    for index in range(concurrency):
                        cache_key = (
                            shared_key
                            if cache_mode == "warm"
                            else f"cold-{target_tokens}-{concurrency}-{repetition}-{index}-{uuid.uuid4().hex}"
                        )
                        messages_batch.append(
                            build_messages(
                                args.base_url,
                                args.model,
                                target_tokens,
                                cache_key,
                                repetition * concurrency + index,
                                args.timeout,
                            )
                        )

                    # The first request establishes the shared prefix outside the measured batch.
                    if cache_mode == "warm" and repetition == 0 and concurrency == args.concurrency[0]:
                        run_request(
                            args.base_url,
                            args.model,
                            messages_batch[0],
                            target_tokens,
                            1,
                            "prime",
                            -1,
                            1,
                            args.timeout,
                        )

                    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as pool:
                        futures = [
                            pool.submit(
                                run_request,
                                args.base_url,
                                args.model,
                                messages,
                                target_tokens,
                                concurrency,
                                cache_mode,
                                repetition * concurrency + index,
                                args.max_tokens,
                                args.timeout,
                            )
                            for index, messages in enumerate(messages_batch)
                        ]
                        batch_results = [future.result() for future in futures]
                    all_results.extend(batch_results)
                    print(
                        json.dumps(
                            {
                                "tokens": target_tokens,
                                "cache": cache_mode,
                                "concurrency": concurrency,
                                "repetition": repetition,
                                "ttft": [round(item.ttft_seconds, 3) for item in batch_results],
                                "total": [round(item.total_seconds, 3) for item in batch_results],
                            }
                        ),
                        flush=True,
                    )

    groups = []
    for target_tokens in args.tokens:
        for cache_mode in args.cache_modes:
            for concurrency in args.concurrency:
                rows = [
                    item
                    for item in all_results
                    if item.target_tokens == target_tokens
                    and item.cache_mode == cache_mode
                    and item.concurrency == concurrency
                    and item.error is None
                ]
                if not rows:
                    continue
                ttft = [item.ttft_seconds for item in rows]
                total = [item.total_seconds for item in rows]
                groups.append(
                    {
                        "target_tokens": target_tokens,
                        "cache_mode": cache_mode,
                        "concurrency": concurrency,
                        "requests": len(rows),
                        "ttft_p50_seconds": statistics.median(ttft),
                        "ttft_p95_seconds": percentile(ttft, 0.95),
                        "latency_p50_seconds": statistics.median(total),
                        "latency_p95_seconds": percentile(total, 0.95),
                        "mean_prompt_tokens_per_second": statistics.mean(
                            item.prompt_tokens_per_second for item in rows if item.prompt_tokens_per_second
                        ),
                        "mean_output_tokens_per_second": statistics.mean(
                            item.output_tokens_per_second for item in rows if item.output_tokens_per_second
                        ),
                    }
                )

    output = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "arguments": vars(args) | {"output": str(args.output)},
        "summary": groups,
        "requests": [asdict(item) for item in all_results],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

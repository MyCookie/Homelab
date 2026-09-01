#!/usr/bin/env python3
"""Measure text, image-front-end, realistic vision, and repeated-image TTFT."""

from __future__ import annotations

import argparse
import base64
import json
import statistics
import time
import urllib.request
from pathlib import Path


LORE = (
    "The road winds through a cold pine forest near Whiterun while distant guards "
    "watch the valley. Lydia remembers the recent journey, the people involved, "
    "their promises, equipment, relationships, and unresolved plans. "
)


def post_json(url: str, payload: dict, timeout: float):
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    return urllib.request.urlopen(request, timeout=timeout)


def tokenize(base_url: str, model: str, messages: list[dict], timeout: float) -> int:
    with post_json(
        f"{base_url}/tokenize",
        {"model": model, "messages": messages, "add_generation_prompt": True},
        timeout,
    ) as response:
        return int(json.load(response)["count"])


def stream_request(base_url: str, model: str, messages: list[dict], timeout: float) -> dict:
    payload = {
        "model": model,
        "messages": messages,
        "stream": True,
        "stream_options": {"include_usage": True},
        "temperature": 0.0,
        "max_tokens": 8,
        "ignore_eos": True,
    }
    started = time.perf_counter()
    first_token_at = None
    usage = {}
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
    return {
        "ttft_seconds": (first_token_at or finished) - started,
        "total_seconds": finished - started,
        "prompt_tokens": usage.get("prompt_tokens"),
        "output_tokens": usage.get("completion_tokens"),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8001")
    parser.add_argument("--model", default="google/gemma-4-12B-it-qat-w4a16-ct")
    parser.add_argument("--image", type=Path, default=Path("tests/assets/cat_operating_camera.jpg"))
    parser.add_argument("--realistic-tokens", type=int, default=5000)
    parser.add_argument("--realistic-first", action="store_true")
    parser.add_argument("--repetitions", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=600.0)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.base_url = args.base_url.rstrip("/")

    mime = "image/jpeg" if args.image.suffix.lower() in {".jpg", ".jpeg"} else "image/png"
    image_url = f"data:{mime};base64,{base64.b64encode(args.image.read_bytes()).decode()}"
    tiny_text = "Describe the screenshot in one short sentence."
    image_part = {"type": "image_url", "image_url": {"url": image_url}}

    scenarios = {
        "text_tiny": [{"role": "user", "content": tiny_text}],
        "image_tiny": [
            {
                "role": "user",
                "content": [image_part, {"type": "text", "text": tiny_text}],
            }
        ],
    }

    realistic_system = f"Synthetic run {time.time_ns()}. You are an NPC in Skyrim. Use the scene context below.\n"
    low, high = 0, max(1, args.realistic_tokens // 20)
    realistic_messages = [
        {"role": "system", "content": realistic_system},
        {
            "role": "user",
            "content": [image_part, {"type": "text", "text": tiny_text}],
        },
    ]
    while True:
        realistic_messages[0]["content"] = realistic_system + LORE * high
        if tokenize(args.base_url, args.model, realistic_messages, args.timeout) >= args.realistic_tokens:
            break
        high *= 2
    while low + 1 < high:
        middle = (low + high) // 2
        realistic_messages[0]["content"] = realistic_system + LORE * middle
        if tokenize(args.base_url, args.model, realistic_messages, args.timeout) < args.realistic_tokens:
            low = middle
        else:
            high = middle
    realistic_messages[0]["content"] = realistic_system + LORE * high
    scenarios["image_realistic"] = realistic_messages
    if args.realistic_first:
        scenarios = {"image_realistic": scenarios.pop("image_realistic"), **scenarios}

    results = []
    for name, messages in scenarios.items():
        for repetition in range(args.repetitions):
            result = stream_request(args.base_url, args.model, messages, args.timeout)
            result.update({"scenario": name, "repetition": repetition})
            results.append(result)
            print(json.dumps(result), flush=True)

    summary = []
    for name in scenarios:
        rows = [row for row in results if row["scenario"] == name]
        summary.append(
            {
                "scenario": name,
                "first_ttft_seconds": rows[0]["ttft_seconds"],
                "repeat_ttft_median_seconds": (
                    statistics.median(row["ttft_seconds"] for row in rows[1:])
                    if len(rows) > 1
                    else None
                ),
                "prompt_tokens": rows[0]["prompt_tokens"],
            }
        )

    output = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "image": str(args.image),
        "summary": summary,
        "requests": results,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

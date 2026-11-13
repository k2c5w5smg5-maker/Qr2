"""Scores a served label model against held-out examples.

    python3 llm/eval.py --url http://localhost:8080/v1 --model label-maker
    python3 llm/eval.py --url https://your-server/v1 --model label-maker --key "$LABEL_MODEL_KEY"

Sends each eval prompt exactly as the app does and compares the reply with the expected
labels. Use it to compare base vs fine-tuned models, or before shipping a new version.
Standard library only.
"""

import argparse
import json
import time
import urllib.error
import urllib.request
from pathlib import Path

from labelformat import parse_reply

HERE = Path(__file__).resolve().parent


def ask(url: str, model: str, key: str, messages: list[dict]) -> str:
    endpoint = url.rstrip("/")
    if not endpoint.endswith("/chat/completions"):
        endpoint += "/chat/completions"
    body = {"model": model, "messages": messages, "temperature": 0.2, "max_tokens": 1500,
            "response_format": {"type": "json_object"}}
    headers = {"Content-Type": "application/json"}
    if key:
        headers["Authorization"] = f"Bearer {key}"
    request = urllib.request.Request(endpoint, data=json.dumps(body).encode(), headers=headers, method="POST")
    with urllib.request.urlopen(request, timeout=120) as response:
        reply = json.loads(response.read())
    return reply["choices"][0]["message"]["content"] or ""


def norm(text: str) -> str:
    return " ".join(text.lower().split())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", required=True, help="base URL, e.g. http://localhost:8080/v1")
    parser.add_argument("--model", default="label-maker")
    parser.add_argument("--key", default="")
    parser.add_argument("--data", type=Path, default=HERE / "data" / "eval.jsonl")
    parser.add_argument("--show", action="store_true", help="print each mismatch")
    args = parser.parse_args()

    rows = [json.loads(l) for l in args.data.read_text(encoding="utf-8").splitlines() if l.strip()]
    totals = {"valid_json": 0, "label_count": 0, "titles": 0, "prices": 0, "quantities": 0, "qr": 0}
    latency = []
    for index, row in enumerate(rows):
        messages = row["messages"]
        expected = parse_reply(messages[-1]["content"])
        started = time.time()
        try:
            got = parse_reply(ask(args.url, args.model, args.key, messages[:-1]))
        except (ValueError, OSError, KeyError) as error:  # OSError covers URLError and timeouts
            if args.show:
                print(f"[{index}] failed: {error}")
            continue
        latency.append(time.time() - started)
        totals["valid_json"] += 1
        if len(got) == len(expected):
            totals["label_count"] += 1
            pairs = list(zip(expected, got))
            checks = {
                "titles": all(norm(a["title"]) == norm(b["title"]) for a, b in pairs),
                "prices": all(a["price"] == b["price"] for a, b in pairs),
                "quantities": all(a["quantity"] == b["quantity"] for a, b in pairs),
                "qr": all(a["qr"] == b["qr"] for a, b in pairs),
            }
            for name, ok in checks.items():
                totals[name] += ok
            if args.show and not all(checks.values()):
                print(f"[{index}] expected {json.dumps(expected)}\n     got      {json.dumps(got)}")
        elif args.show:
            print(f"[{index}] expected {len(expected)} labels, got {len(got)}")

    count = len(rows) or 1
    print(f"examples: {len(rows)}")
    for name, value in totals.items():
        print(f"  {name:12} {value / count:6.1%}")
    if latency:
        print(f"  median latency {sorted(latency)[len(latency) // 2]:.2f}s")


if __name__ == "__main__":
    main()

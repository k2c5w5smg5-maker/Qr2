"""Merges, checks, de-duplicates and splits training data.

    python3 llm/prepare_data.py data/seed.jsonl ~/Downloads/label-training.jsonl

Writes data/train.jsonl and data/eval.jsonl. Bad records are reported and skipped.
"""

import argparse
import hashlib
import json
import random
from pathlib import Path

from labelformat import validate_record

HERE = Path(__file__).resolve().parent


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("inputs", nargs="+", type=Path, help="JSONL files (seed, exports from the app, ...)")
    parser.add_argument("--eval-fraction", type=float, default=0.1)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--out", type=Path, default=HERE / "data")
    args = parser.parse_args()

    records, seen, skipped = [], set(), 0
    for path in args.inputs:
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError as error:
                print(f"{path}:{number}: invalid JSON ({error})")
                skipped += 1
                continue
            problems = validate_record(record)
            if problems:
                print(f"{path}:{number}: {'; '.join(problems)}")
                skipped += 1
                continue
            # The same prompt twice (e.g. printed twice) keeps only the latest answer.
            key = hashlib.sha256(record["messages"][1]["content"].encode()).hexdigest()
            if key in seen:
                records = [r for r in records if r[0] != key]
            seen.add(key)
            records.append((key, record))

    data = [record for _, record in records]
    random.Random(args.seed).shuffle(data)
    eval_count = max(1, int(len(data) * args.eval_fraction)) if len(data) >= 10 else 0
    splits = {"eval": data[:eval_count], "train": data[eval_count:]}

    args.out.mkdir(parents=True, exist_ok=True)
    for name, rows in splits.items():
        with (args.out / f"{name}.jsonl").open("w", encoding="utf-8") as handle:
            for row in rows:
                handle.write(json.dumps(row, ensure_ascii=False) + "\n")
    print(f"train: {len(splits['train'])}  eval: {len(splits['eval'])}  skipped: {skipped}")
    if len(data) < 200:
        print("Tip: a few hundred real examples (turn on 'Save training examples' in the app) give much better results.")


if __name__ == "__main__":
    main()

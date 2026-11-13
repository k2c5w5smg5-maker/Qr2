"""Fails if the system prompt in the app and in prompt/system.txt have drifted apart.

    python3 llm/check_prompt_sync.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWIFT = ROOT / "LabelKit" / "Model" / "LabelPrompt.swift"
TEXT = ROOT / "llm" / "prompt" / "system.txt"


def swift_prompt() -> str:
    source = SWIFT.read_text(encoding="utf-8")
    match = re.search(r'static let systemPrompt = """\n(.*?)\n( *)"""', source, re.S)
    if not match:
        sys.exit(f"Could not find systemPrompt in {SWIFT}")
    indent = len(match.group(2))
    lines = [line[indent:] if line.startswith(" " * indent) else line.lstrip() for line in match.group(1).split("\n")]
    return "\n".join(lines)


def main() -> None:
    app = swift_prompt()
    training = TEXT.read_text(encoding="utf-8").rstrip("\n")
    if app != training:
        for number, (a, b) in enumerate(zip(app.split("\n"), training.split("\n")), start=1):
            if a != b:
                print(f"line {number} differs:\n  app:      {a}\n  training: {b}")
                break
        sys.exit("System prompts differ. Update one to match the other, then retrain or re-check your model.")
    print("System prompt in sync.")


if __name__ == "__main__":
    main()

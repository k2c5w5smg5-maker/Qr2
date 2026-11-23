"""The label model's chat format, ported from the app (LabelKit/Model/LabelPrompt.swift).

Training data must look exactly like what the app sends at run time, so every script in
this folder builds prompts through these functions. If you change the format in Swift,
change it here too (check_prompt_sync.py guards the system prompt).
"""

from __future__ import annotations

import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
SYSTEM_PROMPT = (HERE / "prompt" / "system.txt").read_text(encoding="utf-8").rstrip("\n")

LABEL_FIELDS = ("title", "subtitle", "details", "price", "code", "qr", "quantity")
CURRENCY_SYMBOLS = {"USD": "$", "CAD": "CA$", "AUD": "A$", "EUR": "€", "GBP": "£", "JPY": "¥"}


def format_price(price: str, currency: str) -> str:
    """Rough port of ProductFacts.formattedPrice for en_US (the app uses NumberFormatter)."""
    price = (price or "").strip()
    if not price:
        return ""
    try:
        value = float(price.replace(",", ""))
    except ValueError:
        return price
    symbol = CURRENCY_SYMBOLS.get((currency or "USD").upper(), (currency or "") + " ")
    return f"{symbol}{value:,.0f}" if currency and currency.upper() == "JPY" else f"{symbol}{value:,.2f}"


def normalize_label(label: dict) -> dict:
    """Fill defaults so every label has every field, in the types the app expects."""
    details = label.get("details") or []
    if isinstance(details, str):
        details = [details]
    return {
        "title": str(label.get("title", "")),
        "subtitle": str(label.get("subtitle", "")),
        "details": [str(d) for d in details][:3],
        "price": str(label.get("price", "")),
        "code": str(label.get("code", "")),
        "qr": str(label.get("qr", "")),
        "quantity": max(1, min(500, int(label.get("quantity", 1) or 1))),
    }


def encode_labels(labels: list[dict]) -> str:
    """Same bytes as Swift's JSONEncoder with [.sortedKeys, .withoutEscapingSlashes]."""
    return json.dumps([normalize_label(l) for l in labels], sort_keys=True,
                      separators=(",", ":"), ensure_ascii=False)


def user_message(product: dict | None = None, instructions: str = "", current: list[dict] | None = None) -> str:
    """Port of LabelPrompt.userMessage(for:)."""
    sections = []
    if product:
        lines = ["PRODUCT PAGE", f"url: {product.get('url', '')}"]
        price = format_price(product.get("price", ""), product.get("currency", ""))
        fields = [
            ("name", product.get("name", "")), ("brand", product.get("brand", "")), ("price", price),
            ("sku", product.get("sku", "")), ("gtin", product.get("gtin", "")), ("color", product.get("color", "")),
            ("size", product.get("size", "")), ("material", product.get("material", "")),
            ("category", product.get("category", "")), ("site", product.get("siteName", "")),
            ("page title", product.get("pageTitle", "")), ("description", product.get("description", "")),
        ]
        for key, value in fields:
            if value and value.strip():
                lines.append(f"{key}: {value.strip()}")
        text = (product.get("pageText") or "").strip()
        if text:
            lines.append(f"page text:\n{text}")
        sections.append("\n".join(lines))
    if current:
        sections.append("LABELS SO FAR\n" + encode_labels(current))
    instructions = (instructions or "").strip()
    sections.append("INSTRUCTIONS\n" + (instructions or "Make labels for this product."))
    return "\n\n".join(sections)


def assistant_message(labels: list[dict]) -> str:
    """Port of LabelPrompt.assistantMessage(for:)."""
    return '{"labels":' + encode_labels(labels) + "}"


def example(labels: list[dict], product: dict | None = None, instructions: str = "",
            current: list[dict] | None = None) -> dict:
    """One training record in chat format."""
    return {"messages": [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": user_message(product, instructions, current)},
        {"role": "assistant", "content": assistant_message(labels)},
    ]}


def parse_reply(reply: str) -> list[dict]:
    """Port of LabelPrompt.parseReply: tolerate code fences and prose around the JSON."""
    start, end = reply.find("{"), reply.rfind("}")
    if 0 <= start < end:
        try:
            data = json.loads(reply[start:end + 1])
            if isinstance(data, dict) and isinstance(data.get("labels"), list):
                return [normalize_label(l) for l in data["labels"] if isinstance(l, dict)]
        except (json.JSONDecodeError, ValueError, TypeError):
            pass
    start, end = reply.find("["), reply.rfind("]")
    if 0 <= start < end:
        try:
            data = json.loads(reply[start:end + 1])
            if isinstance(data, list):
                return [normalize_label(l) for l in data if isinstance(l, dict)]
        except (json.JSONDecodeError, ValueError, TypeError):
            pass
    raise ValueError(f"not label JSON: {reply[:200]!r}")


def validate_record(record: dict) -> list[str]:
    """Problems with one training record (empty list = fine)."""
    problems = []
    messages = record.get("messages")
    if not isinstance(messages, list) or [m.get("role") for m in messages] != ["system", "user", "assistant"]:
        return ["messages must be [system, user, assistant]"]
    if messages[0]["content"].rstrip("\n") != SYSTEM_PROMPT:
        problems.append("system prompt differs from prompt/system.txt")
    try:
        labels = parse_reply(messages[2]["content"])
    except ValueError as error:
        return problems + [str(error)]
    if not labels:
        problems.append("assistant returned no labels")
    for label in labels:
        if not label["title"].strip():
            problems.append("label with empty title")
        if len(label["title"]) > 40:
            problems.append(f"title too long: {label['title']!r}")
        if any(len(d) > 40 for d in label["details"]):
            problems.append(f"detail too long in {label['title']!r}")
        if label["price"] and not re.search(r"\d", label["price"]):
            problems.append(f"price without digits: {label['price']!r}")
    return problems

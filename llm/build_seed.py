"""Writes data/seed.jsonl: hand-written examples that show the model the job.

    python3 llm/build_seed.py

A few dozen examples like these teach the format; a few hundred real ones (from the app's
"Save training examples" switch) teach it your taste. Add your own below.
"""

import json
from pathlib import Path

from labelformat import example, validate_record

OUT = Path(__file__).resolve().parent / "data" / "seed.jsonl"


def L(title, subtitle="", details=(), price="", code="", qr="", quantity=1):
    return {"title": title, "subtitle": subtitle, "details": list(details), "price": price,
            "code": code, "qr": qr, "quantity": quantity}


EXAMPLES = [
    # --- Product pages -------------------------------------------------------------------
    example(
        product={
            "url": "https://shop.example.com/products/ceramic-pour-over-dripper",
            "name": "Ceramic Pour-Over Coffee Dripper, Size 02 – Matte White | Example Coffee Co.",
            "brand": "Example Coffee Co.", "price": "28.00", "currency": "USD", "sku": "DRP-02-WHT",
            "color": "Matte White", "material": "Ceramic", "siteName": "Example Coffee Co.",
            "description": "Our best-selling dripper brews a clean, bright cup. Fits size 02 filters. Dishwasher safe.",
            "pageText": "Free shipping over $50\nCeramic Pour-Over Coffee Dripper\n$28.00\nFits size 02 filters\nDishwasher safe\nAdd to cart",
        },
        labels=[L("Ceramic Pour-Over Dripper", "Example Coffee Co. · Size 02",
                  ["Matte white", "Fits size 02 filters", "Dishwasher safe"], "$28.00", "DRP-02-WHT",
                  "https://shop.example.com/products/ceramic-pour-over-dripper")],
    ),
    example(
        product={
            "url": "https://www.example-outdoor.com/p/trail-runner-socks-3-pack",
            "name": "Trail Runner Merino Wool Socks (3-Pack) - Best Hiking Socks for Men & Women",
            "brand": "Ridgeline", "price": "34.95", "currency": "USD", "gtin": "0812345678901",
            "size": "M (W 7-9.5 / M 6-8.5)", "material": "62% merino wool, 35% nylon, 3% spandex",
            "pageText": "Ridgeline Trail Runner Merino Socks 3-Pack\nCushioned sole\nMachine wash cold\n$34.95",
        },
        labels=[L("Trail Runner Merino Socks", "Ridgeline · 3-pack · Size M",
                  ["62% merino wool", "Cushioned sole", "Machine wash cold"], "$34.95", "0812345678901",
                  "https://www.example-outdoor.com/p/trail-runner-socks-3-pack")],
    ),
    example(
        product={
            "url": "https://example-books.co.uk/books/the-quiet-garden",
            "name": "The Quiet Garden: Planting for Calm Spaces (Hardback)",
            "brand": "Greenleaf Press", "price": "18.99", "currency": "GBP", "sku": "9781234567897",
            "description": "A practical guide to designing restful gardens of any size.",
        },
        instructions="Shelf tags, 2 copies",
        labels=[L("The Quiet Garden", "Greenleaf Press · Hardback", ["Planting for calm spaces"],
                  "£18.99", "9781234567897", "https://example-books.co.uk/books/the-quiet-garden", 2)],
    ),
    example(
        product={
            "url": "https://example-hardware.com/item/48213",
            "pageTitle": "Cordless Drill Driver 20V Kit with 2 Batteries – Example Hardware",
            "pageText": "Home > Tools > Drills\n20V Cordless Drill Driver Kit\nModel CD-2040\nIncludes 2 batteries and charger\n1/2 in. keyless chuck\n2-speed gearbox\nOut of stock online\nCheck store availability",
        },
        instructions="no price, I just want an inventory label",
        labels=[L("20V Cordless Drill Driver", "Model CD-2040",
                  ["2 batteries + charger", '1/2" keyless chuck', "2-speed gearbox"], "", "CD-2040",
                  "https://example-hardware.com/item/48213")],
    ),
    example(
        product={
            "url": "https://example-market.com/olive-oil-500ml",
            "name": "Extra Virgin Olive Oil 500 ml", "brand": "Casa Verde", "price": "12.5", "currency": "EUR",
            "category": "Pantry > Oils", "description": "Cold-pressed from Arbequina olives. Harvest 2025.",
        },
        labels=[L("Extra Virgin Olive Oil", "Casa Verde · 500 ml", ["Cold-pressed Arbequina", "Harvest 2025"],
                  "€12.50", "", "https://example-market.com/olive-oil-500ml")],
    ),

    # --- Spoken or typed instructions ------------------------------------------------------
    example(
        instructions="Make pantry labels for flour, sugar, rice and oats",
        labels=[L("Flour"), L("Sugar"), L("Rice"), L("Oats")],
    ),
    example(
        instructions="I need labels for my moving boxes. Kitchen, two of them. Bedroom, three. And one that says fragile glasses.",
        labels=[L("Kitchen", quantity=2), L("Bedroom", quantity=3), L("Fragile", "Glasses")],
    ),
    example(
        instructions="garage sale stickers. blue lamp five dollars, bike twenty five dollars, box of books two dollars each book",
        labels=[L("Blue Lamp", price="$5"), L("Bike", price="$25"), L("Books", details=["Per book"], price="$2")],
    ),
    example(
        instructions="Ten labels that say homemade strawberry jam, made June 2026, with a QR code to example.com/jam",
        labels=[L("Strawberry Jam", "Homemade", ["Made June 2026"], qr="https://example.com/jam", quantity=10)],
    ),
    example(
        instructions="Return address labels, 30 of them: Sam Rivera, 42 Elm Street, Springfield IL 62704",
        labels=[L("Sam Rivera", "42 Elm Street", ["Springfield, IL 62704"], quantity=30)],
    ),
    example(
        instructions="file folder labels: taxes 2025, insurance, medical, car, receipts",
        labels=[L("Taxes 2025"), L("Insurance"), L("Medical"), L("Car"), L("Receipts")],
    ),
    example(
        instructions="Name labels for my kid's school stuff, Maya Chen, Room 12, make twenty",
        labels=[L("Maya Chen", "Room 12", quantity=20)],
    ),
    example(
        instructions="Freezer labels for chicken soup and beef chili, contains celery, dated November 13 2026",
        labels=[L("Chicken Soup", details=["Contains celery", "Nov 13, 2026"]),
                L("Beef Chili", details=["Contains celery", "Nov 13, 2026"])],
    ),
    example(
        instructions="label for the wifi: network Hearth, password is Blue-Kettle-77, add a QR code people can scan to join",
        labels=[L("Wi-Fi: Hearth", "Password: Blue-Kettle-77", qr="WIFI:T:WPA;S:Hearth;P:Blue-Kettle-77;;")],
    ),

    # --- Edits to labels made so far --------------------------------------------------------
    example(
        current=[L("Flour"), L("Sugar"), L("Rice")],
        instructions="make six of each and add today's date, it's March 3rd 2026",
        labels=[L("Flour", details=["Mar 3, 2026"], quantity=6), L("Sugar", details=["Mar 3, 2026"], quantity=6),
                L("Rice", details=["Mar 3, 2026"], quantity=6)],
    ),
    example(
        current=[L("Blue Lamp", price="$5"), L("Bike", price="$25")],
        instructions="actually the bike is 20 and add a rocking chair for 15",
        labels=[L("Blue Lamp", price="$5"), L("Bike", price="$20"), L("Rocking Chair", price="$15")],
    ),
    example(
        current=[L("Ceramic Pour-Over Dripper", "Example Coffee Co. · Size 02", ["Matte white"], "$28.00", "DRP-02-WHT",
                   "https://shop.example.com/products/ceramic-pour-over-dripper")],
        instructions="remove the QR code and put it on sale for 22 dollars",
        labels=[L("Ceramic Pour-Over Dripper", "Example Coffee Co. · Size 02", ["Matte white", "Sale"], "$22.00",
                  "DRP-02-WHT")],
    ),
    example(
        current=[L("Kitchen", quantity=2), L("Bedroom", quantity=3)],
        instructions="delete bedroom and add bathroom and office",
        labels=[L("Kitchen", quantity=2), L("Bathroom"), L("Office")],
    ),
]


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    bad = 0
    with OUT.open("w", encoding="utf-8") as handle:
        for index, record in enumerate(EXAMPLES):
            problems = validate_record(record)
            if problems:
                bad += 1
                print(f"example {index}: {'; '.join(problems)}")
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
    print(f"Wrote {len(EXAMPLES)} examples to {OUT}" + (f" ({bad} with problems)" if bad else ""))


if __name__ == "__main__":
    main()

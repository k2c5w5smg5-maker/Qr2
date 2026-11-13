import Foundation

/// A rules-only label writer that needs no model and no network (apart from reading the
/// product page). It is the fallback when your model is not set up or can't be reached,
/// so the label maker always works on its own.
struct OnDeviceLabelModel: LabelModel {
    var displayName: String { "On-device" }

    func makeLabels(for request: LabelRequest) async throws -> [LabelContent] {
        var labels: [LabelContent] = []
        if let product = request.product {
            labels = [Self.label(from: product)]
        } else {
            labels = request.current
        }

        let text = request.instructions.trimmed
        if !text.isEmpty {
            labels = labels.isEmpty ? Self.labels(fromInstructions: text) : Self.apply(text, to: labels)
        }
        labels = labels.filter { !$0.isBlank }
        guard !labels.isEmpty else { throw LabelModelError.nothingToLabel }
        return labels
    }

    // MARK: - Product pages

    static func label(from product: ProductFacts) -> LabelContent {
        var label = LabelContent(title: shortTitle(product.displayName, brand: product.brand, site: product.siteName))

        var subtitleParts: [String] = []
        if !product.brand.isEmpty, !label.title.localizedCaseInsensitiveContains(product.brand) {
            subtitleParts.append(product.brand)
        }
        if !product.size.isEmpty { subtitleParts.append(product.size) }
        label.subtitle = clip(subtitleParts.joined(separator: " · "), 40)

        var details: [String] = []
        if !product.color.isEmpty { details.append(clip("Color: \(product.color)", 32)) }
        if !product.material.isEmpty { details.append(clip(product.material, 32)) }
        if details.count < 2, let sentence = firstSentence(product.description), sentence.count <= 48 {
            details.append(clip(sentence, 32))
        }
        label.details = Array(details.prefix(3))
        label.price = product.formattedPrice
        label.code = product.sku.isEmpty ? product.gtin : product.sku
        label.qr = product.url
        return label
    }

    /// Product names on web pages are long ("Brand Thing 2-Pack, Blue | Store Name").
    /// Keep the part before the first separator and drop the store name.
    static func shortTitle(_ raw: String, brand: String, site: String) -> String {
        var title = raw.collapsedWhitespace
        for separator in [" | ", " – ", " — ", " - ", " :: "] {
            if let range = title.range(of: separator) {
                let head = String(title[..<range.lowerBound])
                if head.count >= 3 { title = head }
            }
        }
        if !site.isEmpty, title.lowercased().hasSuffix(site.lowercased()) {
            title = String(title.dropLast(site.count)).trimmed
        }
        if !brand.isEmpty, title.lowercased().hasPrefix(brand.lowercased() + " "), title.count > 32 {
            title = String(title.dropFirst(brand.count)).trimmed
        }
        return clip(title, 32)
    }

    // MARK: - Spoken or typed instructions

    static func labels(fromInstructions text: String) -> [LabelContent] {
        let quantity = Self.quantity(in: text)
        let price = Self.price(in: text)
        let link = Self.link(in: text)
        let wantsDate = text.range(of: #"\b(today'?s date|dated?|with the date)\b"#, options: [.regularExpression, .caseInsensitive]) != nil

        let items = Self.items(in: text)
        // "10 of each" means per item; "6 labels for flour, sugar and rice" is 6 in total.
        let perItem = text.range(of: #"\beach\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        let copies: Int
        if let quantity, items.count > 1, !perItem {
            copies = quantity % items.count == 0 ? quantity / items.count : 1
        } else {
            copies = quantity ?? 1
        }
        return items.map { item -> LabelContent in
            var label = LabelContent(title: clip(titleCase(item.name), 32))
            label.price = item.price ?? (items.count == 1 ? price ?? "" : "")
            label.qr = link ?? ""
            label.quantity = copies.clampedQuantity
            if wantsDate { label.details = [today()] }
            return label
        }
    }

    /// Applies simple edits ("price 4.99", "make 10 of each", "add a QR code to example.com").
    static func apply(_ text: String, to labels: [LabelContent]) -> [LabelContent] {
        let price = Self.price(in: text)
        let quantity = Self.quantity(in: text)
        let link = Self.link(in: text)
        let removeQR = text.range(of: #"\b(no|remove|without)\b.*\b(qr|code|link)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        let addDate = text.range(of: #"\b(add|with|include)\b.*\bdate\b"#, options: [.regularExpression, .caseInsensitive]) != nil

        var changed = false
        let edited = labels.map { original -> LabelContent in
            var label = original
            if let price { label.price = price; changed = true }
            if let quantity { label.quantity = quantity.clampedQuantity; changed = true }
            if let link { label.qr = link; changed = true }
            if removeQR { label.qr = ""; changed = true }
            if addDate, !label.details.contains(today()) {
                label.details = Array((label.details + [today()]).suffix(3)); changed = true
            }
            return label
        }
        // Not an edit we understand: treat it as a request for new labels.
        return changed ? edited : labels + Self.labels(fromInstructions: text)
    }

    struct Item { var name: String; var price: String? }

    /// "Make 6 labels for flour, sugar and rice" → ["flour", "sugar", "rice"].
    static func items(in text: String) -> [Item] {
        var body = text
        if let colon = body.firstIndex(of: ":") {
            body = String(body[body.index(after: colon)...])
        } else {
            let lead = #"^\s*(please\s+)?(can you\s+|could you\s+)?(make|create|print|give me|i need|i want|we need)?\s*(me\s+)?(a|an|some|\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|twenty|a dozen|dozen)?\s*((\w+\s+){0,2}?)(labels?|stickers?|tags?|copies)\s*(for|that says?|saying|reading|of|with)?\s*"#
            body = ProductPageReader.replace(lead, in: body, with: "")
        }
        // Drop links and trailing filler before splitting.
        body = ProductPageReader.replace(#"https?://\S+|www\.\S+"#, in: body, with: "")
        body = ProductPageReader.replace(#"\b(with|and)\s+(a\s+)?(qr( code)?|link)\b.*$"#, in: body, with: "")
        body = ProductPageReader.replace(#"\b(with\s+)?(today'?s date|the date|dated)\b"#, in: body, with: "")
        body = ProductPageReader.replace(#"\beach\b"#, in: body, with: "")

        let pieces = ProductPageReader.replace(#"\s+and\s+|\s*[,;\n]\s*"#, in: body, with: "|")
            .split(separator: "|")
            .map { String($0).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { !$0.isEmpty }

        let parsed = pieces.map { piece -> Item in
            let price = Self.price(in: piece)
            let name = ProductPageReader.replace(#"(at|for)?\s*[$€£¥]\s?\d+([.,]\d{1,2})?|\d+([.,]\d{1,2})?\s?(dollars|euros|pounds)"#, in: piece, with: "")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            return Item(name: name, price: price)
        }.filter { !$0.name.isEmpty }

        if parsed.isEmpty {
            return [Item(name: text.collapsedWhitespace, price: nil)]
        }
        return parsed
    }

    static func quantity(in text: String) -> Int? {
        let words = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
                     "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "twenty": 20, "dozen": 12, "a dozen": 12]
        let pattern = #"\b(\d{1,3}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|twenty|a dozen|dozen)\s+(\w+\s+){0,2}?(labels?|stickers?|tags?|copies|of each|each)\b"#
        guard let match = ProductPageReader.firstMatch(pattern, in: text)?.lowercased() else { return nil }
        return Int(match) ?? words[match]
    }

    static func price(in text: String) -> String? {
        if let symbol = ProductPageReader.allMatches(#"[$€£¥]\s?\d+([.,]\d{1,2})?"#, in: text).first {
            return symbol.replacingOccurrences(of: " ", with: "")
        }
        if let words = ProductPageReader.allMatches(#"\d+([.,]\d{1,2})?\s?(dollars|bucks)"#, in: text).first,
           let number = ProductPageReader.allMatches(#"\d+([.,]\d{1,2})?"#, in: words).first {
            return "$" + number
        }
        if let price = ProductPageReader.firstMatch(#"\bprice\s*(?:is|of|:)?\s*(\d+(?:[.,]\d{1,2})?)\b"#, in: text) {
            return "$" + price
        }
        return nil
    }

    static func link(in text: String) -> String? {
        if let url = ProductPageReader.allMatches(#"https?://\S+"#, in: text).first { return url }
        if let bare = ProductPageReader.allMatches(#"\b[\w-]+(\.[\w-]+)*\.(com|net|org|io|co|shop|store|us|uk|ca|de)(/\S*)?"#, in: text).first {
            return "https://" + bare
        }
        return nil
    }

    // MARK: - Text helpers

    static func titleCase(_ text: String) -> String {
        let small: Set<String> = ["a", "an", "and", "of", "the", "for", "with", "in", "on", "to"]
        return text.split(separator: " ").enumerated().map { index, word -> String in
            let lower = word.lowercased()
            if index > 0, small.contains(lower) { return lower }
            // Leave acronyms and mixed-case words (iPhone, USB) as typed.
            if word.dropFirst().contains(where: \.isUppercase) { return String(word) }
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }.joined(separator: " ")
    }

    static func clip(_ text: String, _ limit: Int) -> String {
        let trimmed = text.trimmed
        guard trimmed.count > limit else { return trimmed }
        let cut = trimmed.prefix(limit - 1)
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > limit / 2 {
            return String(cut[..<space]) + "…"
        }
        return String(cut) + "…"
    }

    static func firstSentence(_ text: String) -> String? {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return nil }
        if let end = trimmed.firstIndex(where: { ".!?".contains($0) }) {
            return String(trimmed[...end]).trimmed
        }
        return trimmed
    }

    static func today() -> String {
        Date().formatted(date: .abbreviated, time: .omitted)
    }
}

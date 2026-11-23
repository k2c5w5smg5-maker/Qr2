import Foundation

/// Everything the model is given for one request. Any mix of fields can be set: a product
/// page alone, spoken instructions alone, or instructions that edit the current labels.
struct LabelRequest: Codable, Equatable {
    var product: ProductFacts?
    var instructions: String = ""
    var current: [LabelContent] = []

    var isEmpty: Bool { product == nil && instructions.trimmed.isEmpty }
}

/// The prompt format shared by the app and the training kit in `llm/`.
///
/// IMPORTANT: `systemPrompt` must stay identical to `llm/prompt/system.txt`. The model is
/// fine-tuned on that exact text, and `llm/check_prompt_sync.py` fails when they drift.
enum LabelPrompt {
    static let systemPrompt = """
    You write the text for printed sticker labels. You are given a product page summary, spoken or typed instructions, the labels made so far, or any mix of these.
    Reply with JSON only, no other text, in exactly this shape:
    {"labels":[{"title":"","subtitle":"","details":[],"price":"","code":"","qr":"","quantity":1}]}
    Rules:
    - title: what the item is, at most 32 characters. Drop store names, marketing words and search filler.
    - subtitle: brand, variant or size, at most 40 characters, or "".
    - details: 0 to 3 short facts a person needs on the label (size, color, material, contents, dates, care, allergens), each at most 32 characters.
    - price: only when the input gives one, with its currency symbol, e.g. "$19.99". Otherwise "".
    - code: SKU, model number or barcode number when the input gives one, otherwise "".
    - qr: for a product page, the page URL. Otherwise a URL or text only when the user asks for a QR code or link, else "".
    - quantity: copies of this label to print, 1 unless the user asks for more.
    - Make one label per distinct item. When the user lists several items, make one label for each.
    - When labels made so far are given, treat the instructions as edits to them and return the full updated list.
    - Never invent prices, codes, dates or facts that are not in the input.
    """

    /// The user turn. Sections are only included when they have content.
    static func userMessage(for request: LabelRequest) -> String {
        var sections: [String] = []

        if let product = request.product {
            var lines = ["PRODUCT PAGE", "url: \(product.url)"]
            let fields: [(String, String)] = [
                ("name", product.name), ("brand", product.brand), ("price", product.formattedPrice),
                ("sku", product.sku), ("gtin", product.gtin), ("color", product.color),
                ("size", product.size), ("material", product.material), ("category", product.category),
                ("site", product.siteName), ("page title", product.pageTitle), ("description", product.description),
            ]
            for (key, value) in fields where !value.trimmed.isEmpty {
                lines.append("\(key): \(value.trimmed)")
            }
            if !product.pageText.trimmed.isEmpty {
                lines.append("page text:\n\(product.pageText.trimmed)")
            }
            sections.append(lines.joined(separator: "\n"))
        }

        if !request.current.isEmpty, let json = encode(request.current) {
            sections.append("LABELS SO FAR\n\(json)")
        }

        let instructions = request.instructions.trimmed
        sections.append("INSTRUCTIONS\n\(instructions.isEmpty ? "Make labels for this product." : instructions)")
        return sections.joined(separator: "\n\n")
    }

    /// The assistant turn for a finished set of labels (used for training examples).
    static func assistantMessage(for labels: [LabelContent]) -> String {
        encode(labels).map { "{\"labels\":\($0)}" } ?? "{\"labels\":[]}"
    }

    private static func encode(_ labels: [LabelContent]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(labels) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Pulls the labels out of a model reply. Tolerates code fences, prose around the JSON,
    /// and a bare array instead of `{"labels": [...]}`.
    static func parseReply(_ reply: String) throws -> [LabelContent] {
        struct Envelope: Decodable { var labels: [LabelContent] }
        let decoder = JSONDecoder()

        if let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
           let data = String(reply[start...end]).data(using: .utf8),
           let envelope = try? decoder.decode(Envelope.self, from: data) {
            return clean(envelope.labels)
        }
        if let start = reply.firstIndex(of: "["), let end = reply.lastIndex(of: "]"), start < end,
           let data = String(reply[start...end]).data(using: .utf8),
           let labels = try? decoder.decode([LabelContent].self, from: data) {
            return clean(labels)
        }
        throw LabelModelError.unreadableReply(String(reply.prefix(200)))
    }

    private static func clean(_ labels: [LabelContent]) -> [LabelContent] {
        labels.filter { !$0.isBlank }
    }
}

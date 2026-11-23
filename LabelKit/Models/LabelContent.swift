import Foundation

/// The words on one label. This mirrors the JSON the label model returns (see `LabelPrompt`),
/// so whatever the model writes can be edited by hand and printed as-is.
struct LabelContent: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    /// What the item is. The biggest text on the label.
    var title: String
    /// Brand, variant or size.
    var subtitle: String = ""
    /// Up to three short facts (size, contents, date, care...).
    var details: [String] = []
    /// Price exactly as printed, e.g. "$19.99". Empty for no price.
    var price: String = ""
    /// SKU, model number or barcode number.
    var code: String = ""
    /// Text or URL to encode as a QR code. Empty for no code.
    var qr: String = ""
    /// Copies of this label to print.
    var quantity: Int = 1

    enum CodingKeys: String, CodingKey {
        case title, subtitle, details, price, code, qr, quantity
    }

    static let maxQuantity = 500

    /// True when there is nothing worth printing.
    var isBlank: Bool {
        [title, subtitle, price, code, qr].allSatisfy { $0.trimmed.isEmpty }
            && details.allSatisfy { $0.trimmed.isEmpty }
    }

    /// Details with empty lines removed.
    var visibleDetails: [String] {
        details.map(\.trimmed).filter { !$0.isEmpty }
    }
}

extension LabelContent {
    init(title: String) {
        self.title = title
    }

    /// Lenient decoding: models (and older saved drafts) may leave fields out, send a single
    /// string for `details`, or send numbers as strings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = c.lenientString(.title)
        subtitle = c.lenientString(.subtitle)
        price = c.lenientString(.price)
        code = c.lenientString(.code)
        qr = c.lenientString(.qr)

        if let list = try? c.decode([String].self, forKey: .details) {
            details = list
        } else if let single = try? c.decode(String.self, forKey: .details), !single.trimmed.isEmpty {
            details = [single]
        }
        details = Array(details.prefix(3))

        if let number = try? c.decode(Int.self, forKey: .quantity) {
            quantity = number
        } else if let text = try? c.decode(String.self, forKey: .quantity), let number = Int(text.trimmed) {
            quantity = number
        }
        quantity = quantity.clampedQuantity
    }
}

private extension KeyedDecodingContainer where K == LabelContent.CodingKeys {
    func lenientString(_ key: K) -> String {
        if let text = try? decode(String.self, forKey: key) { return text }
        if let number = try? decode(Double.self, forKey: key) {
            if let whole = Int(exactly: number) { return String(whole) }
            return number.rounded() == number ? String(format: "%.0f", number) : String(number)
        }
        return ""
    }
}

extension Int {
    var clampedQuantity: Int { Swift.min(Swift.max(self, 1), LabelContent.maxQuantity) }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

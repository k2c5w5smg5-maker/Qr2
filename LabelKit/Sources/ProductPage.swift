import Foundation

/// What we could learn about a product from its web page. Structured data (schema.org
/// JSON-LD and Open Graph tags) is preferred; `pageText` is a trimmed copy of the visible
/// text so the model can still find facts on pages without structured data.
struct ProductFacts: Codable, Equatable {
    var url: String
    var name = ""
    var brand = ""
    var description = ""
    var price = ""
    var currency = ""
    var sku = ""
    var gtin = ""
    var color = ""
    var size = ""
    var material = ""
    var category = ""
    var siteName = ""
    var pageTitle = ""
    var pageText = ""

    /// Best name we have for the product.
    var displayName: String {
        for candidate in [name, pageTitle] where !candidate.trimmed.isEmpty { return candidate.trimmed }
        return URL(string: url)?.host ?? url
    }

    /// Price with its currency symbol, e.g. "$19.99", or "" when the page had none.
    var formattedPrice: String {
        let amount = price.trimmed
        guard !amount.isEmpty else { return "" }
        guard let value = Double(amount.replacingOccurrences(of: ",", with: "")) else { return amount }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.isEmpty ? (Locale.current.currency?.identifier ?? "USD") : currency
        return formatter.string(from: NSNumber(value: value)) ?? amount
    }
}

enum ProductPageError: LocalizedError {
    case badURL
    case http(Int)
    case notHTML

    var errorDescription: String? {
        switch self {
        case .badURL: return "That doesn't look like a web address."
        case .http(let status): return "The site answered with an error (\(status)). Some stores block apps; try describing the product instead."
        case .notHTML: return "That link isn't a web page."
        }
    }
}

/// Downloads a product page and extracts `ProductFacts`. Runs entirely on the device.
enum ProductPageReader {
    static let maxPageBytes = 4_000_000
    static let maxTextCharacters = 4_000

    /// Accepts "example.com/item" or a full URL.
    static func normalizedURL(_ raw: String) -> URL? {
        var text = raw.trimmed
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        guard let url = URL(string: text), let host = url.host, host.contains(".") else { return nil }
        return url
    }

    static func read(_ raw: String) async throws -> ProductFacts {
        guard let url = normalizedURL(raw) else { throw ProductPageError.badURL }
        var request = URLRequest(url: url, timeoutInterval: 20)
        // Many stores serve an empty shell or a block page to unknown clients.
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(Locale.preferredLanguages.first ?? "en", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else { throw ProductPageError.http(http.statusCode) }
            if let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
               !type.contains("html"), !type.contains("text") { throw ProductPageError.notHTML }
        }
        let bytes = data.prefix(maxPageBytes)
        let html = String(data: bytes, encoding: .utf8) ?? String(decoding: bytes, as: UTF8.self)
        let finalURL = response.url ?? url
        return parse(html: html, url: finalURL.absoluteString)
    }

    // MARK: - Parsing

    static func parse(html: String, url: String) -> ProductFacts {
        var facts = ProductFacts(url: url)
        let meta = metaTags(in: html)

        if let product = jsonLDProducts(in: html).first {
            apply(product, to: &facts)
        }

        func fill(_ keyPath: WritableKeyPath<ProductFacts, String>, _ keys: [String]) {
            guard facts[keyPath: keyPath].trimmed.isEmpty else { return }
            for key in keys {
                if let value = meta[key], !value.trimmed.isEmpty {
                    facts[keyPath: keyPath] = value.trimmed
                    return
                }
            }
        }
        fill(\.name, ["og:title", "twitter:title"])
        fill(\.description, ["og:description", "description", "twitter:description"])
        fill(\.price, ["product:price:amount", "og:price:amount"])
        fill(\.currency, ["product:price:currency", "og:price:currency"])
        fill(\.brand, ["product:brand", "og:brand"])
        fill(\.siteName, ["og:site_name", "application-name"])

        if let title = firstMatch(#"<title[^>]*>([\s\S]*?)</title>"#, in: html) {
            facts.pageTitle = decodeEntities(title).collapsedWhitespace
        }
        facts.pageText = String(visibleText(html).prefix(maxTextCharacters))
        facts.description = String(facts.description.collapsedWhitespace.prefix(600))
        return facts
    }

    /// `<meta property|name="..." content="...">` pairs, keys lowercased.
    static func metaTags(in html: String) -> [String: String] {
        var result: [String: String] = [:]
        for tag in allMatches(#"<meta\s[^>]*>"#, in: html) {
            let attributes = self.attributes(in: tag)
            guard let key = (attributes["property"] ?? attributes["name"] ?? attributes["itemprop"])?.lowercased(),
                  let content = attributes["content"], result[key] == nil else { continue }
            result[key] = decodeEntities(content)
        }
        return result
    }

    static func attributes(in tag: String) -> [String: String] {
        var result: [String: String] = [:]
        let pattern = #"([A-Za-z_:\-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let ns = tag as NSString
        for match in regex.matches(in: tag, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1)).lowercased()
            let valueRange = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 3)
            if valueRange.location != NSNotFound { result[name] = ns.substring(with: valueRange) }
        }
        return result
    }

    /// Every schema.org Product (or ProductGroup) object in the page's JSON-LD blocks.
    static func jsonLDProducts(in html: String) -> [[String: Any]] {
        let blocks = allCaptures(#"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#, in: html)
        var products: [[String: Any]] = []
        for block in blocks {
            let cleaned = block
                .replacingOccurrences(of: "<!--", with: "")
                .replacingOccurrences(of: "-->", with: "")
                .replacingOccurrences(of: "<![CDATA[", with: "")
                .replacingOccurrences(of: "]]>", with: "")
            guard let data = cleaned.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { continue }
            collectProducts(json, into: &products)
        }
        return products
    }

    private static func collectProducts(_ node: Any, into products: inout [[String: Any]]) {
        if let list = node as? [Any] {
            list.forEach { collectProducts($0, into: &products) }
        } else if let object = node as? [String: Any] {
            let types: [String]
            if let type = object["@type"] as? String { types = [type] }
            else { types = object["@type"] as? [String] ?? [] }
            if types.contains(where: { $0.hasSuffix("Product") || $0.hasSuffix("ProductGroup") }) {
                products.append(object)
            } else {
                for key in ["@graph", "mainEntity", "itemListElement", "item"] {
                    if let child = object[key] { collectProducts(child, into: &products) }
                }
            }
        }
    }

    private static func apply(_ product: [String: Any], to facts: inout ProductFacts) {
        facts.name = text(product["name"])
        facts.description = decodeEntities(stripTags(text(product["description"])))
        facts.sku = text(product["sku"]).isEmpty ? text(product["mpn"]) : text(product["sku"])
        facts.gtin = ["gtin13", "gtin12", "gtin14", "gtin8", "gtin"].lazy.map { text(product[$0]) }.first { !$0.isEmpty } ?? ""
        facts.color = text(product["color"])
        facts.size = text(product["size"])
        facts.material = text(product["material"])
        facts.category = text(product["category"])

        if let brand = product["brand"] as? [String: Any] { facts.brand = text(brand["name"]) }
        else { facts.brand = text(product["brand"]) }

        var offers: Any? = product["offers"]
        if let list = offers as? [Any] { offers = list.first }
        if let offer = offers as? [String: Any] {
            var price = text(offer["price"])
            if price.isEmpty { price = text(offer["lowPrice"]) }
            if price.isEmpty, let spec = offer["priceSpecification"] as? [String: Any] { price = text(spec["price"]) }
            facts.price = price
            facts.currency = text(offer["priceCurrency"])
        }
        if facts.price.isEmpty, let variants = product["hasVariant"] as? [[String: Any]], let first = variants.first {
            var variant = facts
            apply(first, to: &variant)
            facts.price = variant.price
            facts.currency = variant.currency
        }
    }

    /// Turns a JSON-LD value into display text. Numbers keep two decimals when they have any.
    private static func text(_ value: Any?) -> String {
        guard let value else { return "" }
        switch value {
        case let string as String:
            return decodeEntities(string).collapsedWhitespace
        case let number as NSNumber:
            let double = number.doubleValue
            return double == double.rounded() ? String(Int(double)) : String(format: "%.2f", double)
        case let list as [Any]:
            return list.map { text($0) }.filter { !$0.isEmpty }.joined(separator: ", ")
        case let object as [String: Any]:
            return text(object["name"] ?? object["value"])
        default:
            return ""
        }
    }

    /// Visible text of the page with scripts, styles and markup removed.
    static func visibleText(_ html: String) -> String {
        var text = html
        for pattern in [#"<!--[\s\S]*?-->"#, #"<script[\s\S]*?</script>"#, #"<style[\s\S]*?</style>"#,
                        #"<noscript[\s\S]*?</noscript>"#, #"<svg[\s\S]*?</svg>"#, #"<head[\s\S]*?</head>"#] {
            text = replace(pattern, in: text, with: " ")
        }
        text = replace(#"<(br|/p|/div|/li|/h[1-6]|/tr)[^>]*>"#, in: text, with: "\n")
        return decodeEntities(stripTags(text))
            .components(separatedBy: .newlines)
            .map(\.collapsedWhitespace)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func stripTags(_ html: String) -> String {
        replace(#"<[^>]+>"#, in: html, with: " ")
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        let named = ["&nbsp;": " ", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">",
                     "&ndash;": "–", "&mdash;": "—", "&rsquo;": "’", "&lsquo;": "‘", "&rdquo;": "”",
                     "&ldquo;": "“", "&trade;": "™", "&reg;": "®", "&copy;": "©", "&hellip;": "…"]
        for (entity, replacement) in named { result = result.replacingOccurrences(of: entity, with: replacement) }

        guard let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") else { return result }
        let ns = result as NSString
        var output = ""
        var cursor = 0
        for match in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)) {
            output += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let isHex = match.range(at: 1).length > 0
            let digits = ns.substring(with: match.range(at: 2))
            if let value = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(value) {
                output.unicodeScalars.append(scalar)
            } else {
                output += ns.substring(with: match.range)
            }
            cursor = match.range.location + match.range.length
        }
        output += ns.substring(from: cursor)
        // &amp; last so "&amp;lt;" stays "&lt;".
        return output.replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: - Regex helpers

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    static func allMatches(_ pattern: String, in text: String) -> [String] {
        guard let regex = regex(pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    static func allCaptures(_ pattern: String, in text: String) -> [String] {
        guard let regex = regex(pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
            $0.range(at: 1).location == NSNotFound ? nil : ns.substring(with: $0.range(at: 1))
        }
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        allCaptures(pattern, in: text).first
    }

    static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = regex(pattern) else { return text }
        let ns = text as NSString
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: template)
    }
}

extension String {
    /// Runs of whitespace (including newlines) collapsed to single spaces, trimmed.
    var collapsedWhitespace: String {
        split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

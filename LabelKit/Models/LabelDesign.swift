import Foundation

enum LabelLook: String, CaseIterable, Identifiable, Codable {
    /// Black text on white.
    case clean
    /// White text on a black label, heavier type.
    case bold
    /// Retail shelf tag: large price under a rule.
    case shelf

    var id: String { rawValue }
    var title: String {
        switch self {
        case .clean: return "Clean"
        case .bold: return "Bold"
        case .shelf: return "Shelf tag"
        }
    }
}

enum LabelAlignment: String, CaseIterable, Identifiable, Codable {
    case leading, center
    var id: String { rawValue }
    var title: String { self == .leading ? "Left" : "Center" }
}

/// How every label on the sheet is drawn. The words come from `LabelContent`.
struct LabelDesign: Codable, Equatable {
    var look: LabelLook = .clean
    var alignment: LabelAlignment = .leading
    var showQR = true
    var showPrice = true
    var showCode = true
    /// Print a thin outline around each label (handy for test prints on plain paper).
    var outlines = false
}

extension LabelDesign {
    /// Missing keys keep their defaults, so saved drafts survive new settings.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        look = (try? c.decodeIfPresent(LabelLook.self, forKey: .look)) ?? look
        alignment = (try? c.decodeIfPresent(LabelAlignment.self, forKey: .alignment)) ?? alignment
        showQR = (try? c.decodeIfPresent(Bool.self, forKey: .showQR)) ?? showQR
        showPrice = (try? c.decodeIfPresent(Bool.self, forKey: .showPrice)) ?? showPrice
        showCode = (try? c.decodeIfPresent(Bool.self, forKey: .showCode)) ?? showCode
        outlines = (try? c.decodeIfPresent(Bool.self, forKey: .outlines)) ?? outlines
    }
}

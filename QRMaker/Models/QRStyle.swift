import SwiftUI

/// A color that can be stored on disk.
struct RGBAColor: Codable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let black = RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)
    static let white = RGBAColor(red: 1, green: 1, blue: 1, alpha: 1)

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        if UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) {
            self.init(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
        } else {
            self = .black
        }
    }

    var color: Color { Color(red: red, green: green, blue: blue, opacity: alpha) }
    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: alpha) }

    /// CSS style hex string, e.g. "#1A2B3C".
    var hex: String {
        let r = Int((red * 255).rounded()), g = Int((green * 255).rounded()), b = Int((blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// QR error correction level. Higher levels survive more damage but produce denser codes.
enum ErrorCorrection: String, CaseIterable, Identifiable, Codable {
    case L, M, Q, H
    var id: String { rawValue }
    var title: String {
        switch self {
        case .L: return "Low (7%)"
        case .M: return "Medium (15%)"
        case .Q: return "Quartile (25%)"
        case .H: return "High (30%)"
        }
    }
}

/// Outline of the exported image.
enum CanvasShape: String, CaseIterable, Identifiable, Codable {
    case square
    case rectangle
    var id: String { rawValue }
    var title: String { self == .square ? "Square" : "Rectangle" }
}

/// The shape and size of the exported image. The QR grid itself always stays square
/// (that is required for it to scan), and is centered inside the canvas.
struct CanvasSpec: Codable, Equatable, Hashable {

    static let minSide = 256
    static let maxSide = 4096

    var shape: CanvasShape = .square
    /// Width in pixels. For a square this is also the height.
    var width: Int = 1024
    /// Height in pixels. Ignored for squares.
    var height: Int = 1024

    /// Final pixel size of the exported image.
    var pixelSize: CGSize {
        let w = CGFloat(width.clamped(to: Self.minSide...Self.maxSide))
        let h = CGFloat((shape == .square ? width : height).clamped(to: Self.minSide...Self.maxSide))
        return CGSize(width: w, height: h)
    }

    var aspectRatio: CGFloat {
        let size = pixelSize
        return size.width / size.height
    }

    var summary: String {
        let size = pixelSize
        return "\(Int(size.width)) × \(Int(size.height)) px"
    }
}

/// Everything about how a code looks.
struct QRStyle: Codable, Equatable, Hashable {
    var foreground: RGBAColor = .black
    var background: RGBAColor = .white
    var correction: ErrorCorrection = .M
    var canvas = CanvasSpec()
    /// Quiet zone around the grid, measured in modules. The QR spec recommends 4.
    var quietZone: Int = 4

    static let standard = QRStyle()
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

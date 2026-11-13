import UIKit

/// Draws one label into the current UIKit graphics context (bitmap or PDF). Text shrinks
/// to fit the label, so the same content works on a ½" return-address label and a 4" × 6"
/// shipping label.
enum LabelRenderer {
    /// Smallest QR code we will print, in points (about 0.4"). Smaller codes don't scan reliably.
    static let minQRSide: CGFloat = 28

    static func draw(_ label: LabelContent, design: LabelDesign, in rect: CGRect, cornerRadius: CGFloat) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }

        let shape = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        shape.addClip()

        let colors = Palette(look: design.look)
        if design.look == .bold {
            colors.background.setFill()
            UIRectFill(rect)
        }

        let pad = max(3, min(rect.width, rect.height) * 0.08)
        var content = rect.insetBy(dx: pad, dy: pad)

        let qrText = label.qr.trimmed
        if design.showQR, !qrText.isEmpty, let modules = LabelQR.modules(for: qrText) {
            let side = min(content.height, content.width * 0.45)
            if side >= minQRSide {
                let qrRect = CGRect(x: content.maxX - side, y: content.midY - side / 2, width: side, height: side)
                LabelQR.draw(modules, in: qrRect)
                content.size.width -= side + pad * 0.75
            }
        }

        drawText(label, design: design, colors: colors, in: content)
    }

    /// A bitmap of one label at `scale` × its point size, for on-screen previews.
    static func image(_ label: LabelContent, design: LabelDesign, size: CGSize, cornerRadius: CGFloat, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            draw(label, design: design, in: CGRect(origin: .zero, size: size), cornerRadius: cornerRadius)
        }
    }

    // MARK: - Text

    private struct Palette {
        let background: UIColor
        let primary: UIColor
        let secondary: UIColor

        init(look: LabelLook) {
            if look == .bold {
                background = .black
                primary = .white
                secondary = UIColor(white: 0.82, alpha: 1)
            } else {
                background = .white
                primary = .black
                secondary = UIColor(white: 0.3, alpha: 1)
            }
        }
    }

    private struct Block {
        var text: NSAttributedString
        var maxLines: Int
        var spaceBefore: CGFloat
        var ruleAbove = false
    }

    private static func blocks(for label: LabelContent, design: LabelDesign, colors: Palette, base: CGFloat) -> [Block] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = design.alignment == .center ? .center : .left
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineHeightMultiple = 0.95

        func attributed(_ text: String, size: CGFloat, weight: UIFont.Weight, color: UIColor, mono: Bool = false) -> NSAttributedString {
            let font = mono ? UIFont.monospacedSystemFont(ofSize: size, weight: weight) : UIFont.systemFont(ofSize: size, weight: weight)
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
        }

        let bold = design.look == .bold
        var result: [Block] = []
        let title = label.title.trimmed
        if !title.isEmpty {
            result.append(Block(text: attributed(title, size: base * (bold ? 1.1 : 1.0), weight: bold ? .heavy : .bold, color: colors.primary),
                                maxLines: 2, spaceBefore: 0))
        }
        let subtitle = label.subtitle.trimmed
        if !subtitle.isEmpty {
            result.append(Block(text: attributed(subtitle, size: base * 0.62, weight: .medium, color: colors.secondary),
                                maxLines: 1, spaceBefore: base * 0.12))
        }
        for detail in label.visibleDetails {
            result.append(Block(text: attributed(detail, size: base * 0.52, weight: .regular, color: colors.primary),
                                maxLines: 1, spaceBefore: base * 0.08))
        }

        let price = design.showPrice ? label.price.trimmed : ""
        let code = design.showCode ? label.code.trimmed : ""
        if !price.isEmpty || !code.isEmpty {
            let footer = NSMutableAttributedString()
            if !price.isEmpty {
                let size = base * (design.look == .shelf ? 1.5 : 0.85)
                footer.append(attributed(price, size: size, weight: .heavy, color: colors.primary))
            }
            if !code.isEmpty {
                if footer.length > 0 { footer.append(attributed("   ", size: base * 0.45, weight: .regular, color: colors.secondary)) }
                footer.append(attributed(code, size: base * 0.45, weight: .regular, color: colors.secondary, mono: true))
            }
            result.append(Block(text: footer, maxLines: design.look == .shelf ? 2 : 1, spaceBefore: base * 0.22,
                                ruleAbove: design.look == .shelf))
        }
        return result
    }

    private static func measure(_ block: Block, width: CGFloat) -> CGFloat {
        let bounds = block.text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                             options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        var lineHeight: CGFloat = 0
        block.text.enumerateAttribute(.font, in: NSRange(location: 0, length: block.text.length)) { value, _, _ in
            if let font = value as? UIFont { lineHeight = max(lineHeight, font.lineHeight) }
        }
        return min(ceil(bounds.height), ceil(lineHeight * CGFloat(block.maxLines)))
    }

    private static func drawText(_ label: LabelContent, design: LabelDesign, colors: Palette, in rect: CGRect) {
        guard rect.width > 4, rect.height > 4 else { return }

        // Start from a title size proportional to the label and shrink until everything fits.
        var base = min(rect.height * 0.3, rect.width * 0.16, 30)
        var laidOut: [(Block, CGFloat)] = []
        var total: CGFloat = 0
        for _ in 0..<24 {
            let candidate = blocks(for: label, design: design, colors: colors, base: base)
            laidOut = candidate.map { ($0, measure($0, width: rect.width)) }
            total = laidOut.reduce(CGFloat(0)) { sum, item in sum + item.0.spaceBefore + item.1 }
            if total <= rect.height || base <= 4 { break }
            base *= 0.9
        }

        // Center the block vertically; if it still overflows, pin to the top and let it clip.
        var y = total <= rect.height ? rect.minY + (rect.height - total) / 2 : rect.minY
        for (index, item) in laidOut.enumerated() {
            let (block, height) = item
            if index > 0 { y += block.spaceBefore }
            if block.ruleAbove {
                let rule = UIBezierPath()
                let ruleY = y - block.spaceBefore / 2
                rule.move(to: CGPoint(x: rect.minX, y: ruleY))
                rule.addLine(to: CGPoint(x: rect.maxX, y: ruleY))
                rule.lineWidth = max(0.5, base * 0.04)
                colors.secondary.setStroke()
                rule.stroke()
            }
            block.text.draw(with: CGRect(x: rect.minX, y: y, width: rect.width, height: height),
                            options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
                            context: nil)
            y += height
        }
    }
}

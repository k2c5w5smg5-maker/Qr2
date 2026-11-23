import UIKit

/// A print job: labels laid out on sticker sheets, ready to become a PDF.
struct LabelSheet {
    let template: LabelTemplate
    let design: LabelDesign
    let labels: [LabelContent]
    /// First free position on the first sheet (0-based), so part-used sheets can be reused.
    let startPosition: Int

    /// Hard cap so a typo like "5000 copies" can't produce a giant PDF.
    static let maxLabels = 2_000

    /// One entry per printed sticker, with each label repeated `quantity` times.
    var slots: [LabelContent] {
        var result: [LabelContent] = []
        for label in labels where !label.isBlank {
            let copies = min(label.quantity.clampedQuantity, Self.maxLabels - result.count)
            guard copies > 0 else { break }
            result.append(contentsOf: Array(repeating: label, count: copies))
        }
        return result
    }

    var clampedStart: Int { min(max(startPosition, 0), template.perPage - 1) }

    var pageCount: Int {
        let used = clampedStart + slots.count
        return max(1, (used + template.perPage - 1) / template.perPage)
    }

    /// Draws one page into the current context, in page points.
    /// - Parameter guides: outline every label position (used for on-screen previews).
    func drawPage(_ page: Int, slots: [LabelContent], guides: Bool) {
        let perPage = template.perPage
        for position in 0..<perPage {
            let frame = template.frame(at: position)
            let index = page * perPage + position - clampedStart
            let inRange = index >= 0 && index < slots.count

            if inRange {
                LabelRenderer.draw(slots[index], design: design, in: frame, cornerRadius: template.cornerRadius)
            }
            if (inRange && design.outlines) || guides {
                let outline = UIBezierPath(roundedRect: frame.insetBy(dx: 0.25, dy: 0.25), cornerRadius: template.cornerRadius)
                outline.lineWidth = 0.5
                (inRange ? UIColor(white: 0.55, alpha: 1) : UIColor(white: 0.85, alpha: 1)).setStroke()
                outline.stroke()
            }
        }
    }

    /// The print-ready PDF, at the sheet's real size.
    func pdfData() -> Data {
        let bounds = CGRect(origin: .zero, size: template.pageSize)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextCreator as String: "Label Maker"]
        let slots = self.slots
        return UIGraphicsPDFRenderer(bounds: bounds, format: format).pdfData { context in
            for page in 0..<pageCount {
                context.beginPage()
                drawPage(page, slots: slots, guides: false)
            }
        }
    }

    /// A picture of one page for the preview, `width` points wide.
    func previewImage(page: Int, width: CGFloat, scale: CGFloat) -> UIImage {
        let pageSize = template.pageSize
        let factor = width / pageSize.width
        let size = CGSize(width: width, height: pageSize.height * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let slots = self.slots
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            context.cgContext.scaleBy(x: factor, y: factor)
            drawPage(page, slots: slots, guides: true)
        }
    }
}

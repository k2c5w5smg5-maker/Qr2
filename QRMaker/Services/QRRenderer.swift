import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Generates QR module grids with Core Image and draws them with Core Graphics, so the
/// same grid can be rendered to a square or rectangular PNG, an SVG, or an on-screen preview.
enum QRRenderer {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// The module grid for `content`. `true` means a dark module. The quiet zone that
    /// Core Image adds is trimmed so callers control their own margins.
    static func modules(for content: String, correction: ErrorCorrection) -> [[Bool]]? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = correction.rawValue
        guard let output = filter.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }

        let width = cgImage.width, height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let cg = CGContext(data: buffer.baseAddress, width: width, height: height,
                                     bitsPerComponent: 8, bytesPerRow: width,
                                     space: CGColorSpaceCreateDeviceGray(),
                                     bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            cg.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        // Core Graphics draws with the origin at the bottom-left, so flip rows back to top-down.
        var grid: [[Bool]] = []
        grid.reserveCapacity(height)
        for row in (0..<height).reversed() {
            let start = row * width
            grid.append(pixels[start..<(start + width)].map { $0 < 128 })
        }
        return trimmed(grid)
    }

    /// Drops the all-light border rows and columns around the grid.
    private static func trimmed(_ grid: [[Bool]]) -> [[Bool]] {
        guard let firstRow = grid.firstIndex(where: { $0.contains(true) }),
              let lastRow = grid.lastIndex(where: { $0.contains(true) }) else { return grid }
        let columns = grid[0].count
        var firstCol = columns, lastCol = -1
        for row in grid[firstRow...lastRow] {
            if let f = row.firstIndex(of: true) { firstCol = min(firstCol, f) }
            if let l = row.lastIndex(of: true) { lastCol = max(lastCol, l) }
        }
        guard firstCol <= lastCol else { return grid }
        return grid[firstRow...lastRow].map { Array($0[firstCol...lastCol]) }
    }

    /// Geometry of a grid placed inside a canvas.
    struct Layout {
        let moduleSize: CGFloat
        let origin: CGPoint
        let gridSize: CGFloat

        init(moduleCount: Int, quietZone: Int, canvas: CGSize) {
            let totalModules = CGFloat(moduleCount + quietZone * 2)
            let side = min(canvas.width, canvas.height)
            // Whole-pixel modules keep edges crisp; fall back to fractional sizes for tiny canvases.
            var size = floor(side / totalModules)
            if size < 1 { size = side / totalModules }
            moduleSize = size
            gridSize = size * CGFloat(moduleCount)
            origin = CGPoint(x: ((canvas.width - gridSize) / 2).rounded(),
                             y: ((canvas.height - gridSize) / 2).rounded())
        }
    }

    /// Draws the grid into a bitmap of exactly `canvas` pixels.
    static func image(modules: [[Bool]], style: QRStyle, canvas: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = style.background.alpha >= 1
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(style.background.uiColor.cgColor)
            cg.fill(CGRect(origin: .zero, size: canvas))

            let layout = Layout(moduleCount: modules.count, quietZone: style.quietZone, canvas: canvas)
            cg.setFillColor(style.foreground.uiColor.cgColor)
            for (row, line) in modules.enumerated() {
                for (col, dark) in line.enumerated() where dark {
                    cg.fill(CGRect(x: layout.origin.x + CGFloat(col) * layout.moduleSize,
                                   y: layout.origin.y + CGFloat(row) * layout.moduleSize,
                                   width: layout.moduleSize, height: layout.moduleSize))
                }
            }
        }
    }

    /// Convenience: build the grid and draw it in one go.
    static func image(for content: String, style: QRStyle, canvas: CGSize) -> UIImage? {
        guard let grid = modules(for: content, correction: style.correction) else { return nil }
        return image(modules: grid, style: style, canvas: canvas)
    }

    /// Full-size export, using the style's own canvas size.
    static func exportImage(for content: String, style: QRStyle) -> UIImage? {
        image(for: content, style: style, canvas: style.canvas.pixelSize)
    }

    /// A preview sized to fit `maxSide` points while keeping the canvas aspect ratio.
    static func previewImage(for content: String, style: QRStyle, maxSide: CGFloat, scale: CGFloat) -> UIImage? {
        let ratio = style.canvas.aspectRatio
        let width = ratio >= 1 ? maxSide : maxSide * ratio
        let height = ratio >= 1 ? maxSide / ratio : maxSide
        return image(for: content, style: style, canvas: CGSize(width: (width * scale).rounded(),
                                                                height: (height * scale).rounded()))
    }

    static func pngData(for content: String, style: QRStyle) -> Data? {
        exportImage(for: content, style: style)?.pngData()
    }

    /// A vector version of the same artwork, for print.
    static func svg(for content: String, style: QRStyle) -> String? {
        guard let grid = modules(for: content, correction: style.correction) else { return nil }
        let canvas = style.canvas.pixelSize
        let layout = Layout(moduleCount: grid.count, quietZone: style.quietZone, canvas: canvas)
        let w = Int(canvas.width), h = Int(canvas.height)

        var svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(w)" height="\(h)" viewBox="0 0 \(w) \(h)" shape-rendering="crispEdges">
        <rect width="\(w)" height="\(h)" fill="\(style.background.hex)"/>
        <path fill="\(style.foreground.hex)" d="
        """
        let m = layout.moduleSize
        for (row, line) in grid.enumerated() {
            for (col, dark) in line.enumerated() where dark {
                let x = layout.origin.x + CGFloat(col) * m
                let y = layout.origin.y + CGFloat(row) * m
                svg += "M\(fmt(x)) \(fmt(y))h\(fmt(m))v\(fmt(m))h-\(fmt(m))z"
            }
        }
        svg += "\"/>\n</svg>\n"
        return svg
    }

    private static func fmt(_ value: CGFloat) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }
}

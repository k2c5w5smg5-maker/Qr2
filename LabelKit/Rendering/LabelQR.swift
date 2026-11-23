import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// QR codes for labels, drawn as vector rectangles so they stay sharp in the printed PDF.
/// Self-contained so LabelKit has no dependency on the QR Maker app.
enum LabelQR {
    private static let context = CIContext()
    private static var cache: [String: [[Bool]]] = [:]
    private static let lock = NSLock()

    /// Module grid for `text` (true = dark), without a quiet zone.
    static func modules(for text: String) -> [[Bool]]? {
        lock.lock()
        if let cached = cache[text] { lock.unlock(); return cached }
        lock.unlock()

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        let width = cgImage.width, height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 255, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let cg = CGContext(data: buffer.baseAddress, width: width, height: height,
                                     bitsPerComponent: 8, bytesPerRow: width,
                                     space: CGColorSpaceCreateDeviceGray(),
                                     bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            cg.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        // The first row in a bitmap context's memory is the top of the drawn image, so rows
        // are already top-down. Trim Core Image's quiet zone so we control the margin.
        var grid: [[Bool]] = (0..<height).map { row -> [Bool] in
            let start = row * width
            return pixels[start..<(start + width)].map { $0 < 128 }
        }
        guard let top = grid.firstIndex(where: { $0.contains(true) }),
              let bottom = grid.lastIndex(where: { $0.contains(true) }) else { return nil }
        grid = Array(grid[top...bottom])
        let left = grid.compactMap { $0.firstIndex(of: true) }.min() ?? 0
        let right = grid.compactMap { $0.lastIndex(of: true) }.max() ?? (width - 1)
        grid = grid.map { Array($0[left...right]) }

        lock.lock()
        if cache.count > 200 { cache.removeAll() }
        cache[text] = grid
        lock.unlock()
        return grid
    }

    /// Draws the code into `rect` (square) with a 2-module light margin, in the current context.
    static func draw(_ modules: [[Bool]], in rect: CGRect, dark: UIColor = .black, light: UIColor = .white) {
        guard let ctx = UIGraphicsGetCurrentContext(), !modules.isEmpty else { return }
        let quiet = 2
        let count = modules.count + quiet * 2
        let module = rect.width / CGFloat(count)
        ctx.setFillColor(light.cgColor)
        ctx.fill(rect)
        ctx.setFillColor(dark.cgColor)
        for (row, line) in modules.enumerated() {
            // Merge runs of dark modules into one rectangle each.
            var col = 0
            while col < line.count {
                guard line[col] else { col += 1; continue }
                var end = col
                while end + 1 < line.count, line[end + 1] { end += 1 }
                ctx.fill(CGRect(x: rect.minX + CGFloat(col + quiet) * module,
                                y: rect.minY + CGFloat(row + quiet) * module,
                                width: CGFloat(end - col + 1) * module,
                                height: module))
                col = end + 1
            }
        }
    }
}

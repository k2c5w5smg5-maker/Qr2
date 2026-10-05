import Photos
import UIKit

/// Saves images to the user's photo library using add-only permission.
enum PhotoSaver {
    enum SaveError: LocalizedError {
        case denied
        var errorDescription: String? {
            "Allow QR Maker to add photos in Settings to save codes to your library."
        }
    }

    static func save(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.denied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
}

/// Writes export files to a temporary folder so they can be handed to the share sheet.
enum ExportFiles {
    static func write(code: SavedCode) -> (png: URL?, svg: URL?) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = "qr-\(code.id.uuidString.prefix(8).lowercased())"

        var pngURL: URL?
        if let data = QRRenderer.pngData(for: code.content, style: code.style) {
            let url = folder.appendingPathComponent("\(base).png")
            if (try? data.write(to: url, options: .atomic)) != nil { pngURL = url }
        }

        var svgURL: URL?
        if let svg = QRRenderer.svg(for: code.content, style: code.style) {
            let url = folder.appendingPathComponent("\(base).svg")
            if (try? svg.write(to: url, atomically: true, encoding: .utf8)) != nil { svgURL = url }
        }
        return (pngURL, svgURL)
    }
}

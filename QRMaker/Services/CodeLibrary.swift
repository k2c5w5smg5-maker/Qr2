import Foundation
import Combine

/// Stores purchased codes as JSON in Application Support.
@MainActor
final class CodeLibrary: ObservableObject {
    @Published private(set) var codes: [SavedCode] = []

    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("QRMaker", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("codes.json")
        load()
    }

    func add(_ code: SavedCode) {
        codes.insert(code, at: 0)
        save()
    }

    func rename(_ id: SavedCode.ID, to title: String) {
        guard let index = codes.firstIndex(where: { $0.id == id }) else { return }
        codes[index].title = title
        save()
    }

    func delete(at offsets: IndexSet) {
        codes.remove(atOffsets: offsets)
        save()
    }

    func delete(_ id: SavedCode.ID) {
        codes.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        codes = (try? decoder.decode([SavedCode].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(codes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

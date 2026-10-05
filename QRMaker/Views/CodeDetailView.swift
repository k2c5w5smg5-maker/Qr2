import SwiftUI

/// A purchased code at full quality, with save and share actions.
struct CodeDetailView: View {
    @EnvironmentObject private var library: CodeLibrary

    let code: SavedCode

    @State private var title: String
    @State private var exportImage: UIImage?
    @State private var pngURL: URL?
    @State private var svgURL: URL?
    @State private var isSaving = false
    @State private var message: String?

    init(code: SavedCode) {
        self.code = code
        _title = State(initialValue: code.title)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                QRImage(content: code.content, style: code.style, maxSide: 320)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)

                VStack(spacing: 6) {
                    Text(code.content)
                        .font(.footnote.monospaced())
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                    Text("\(code.style.canvas.shape.title) · \(code.style.canvas.summary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                TextField("Name", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { library.rename(code.id, to: title) }

                VStack(spacing: 12) {
                    Button {
                        Task { await saveToPhotos() }
                    } label: {
                        Label(isSaving ? "Saving…" : "Save to Photos", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)

                    HStack(spacing: 12) {
                        if let pngURL {
                            ShareLink(item: pngURL) {
                                Label("Share PNG", systemImage: "photo")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        if let svgURL {
                            ShareLink(item: svgURL) {
                                Label("Share SVG", systemImage: "scribble.variable")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Button {
                        UIPasteboard.general.string = code.content
                        message = "Link copied."
                    } label: {
                        Label("Copy link", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let code = code
            let result = await Task.detached(priority: .userInitiated) {
                (QRRenderer.exportImage(for: code.content, style: code.style), ExportFiles.write(code: code))
            }.value
            exportImage = result.0
            pngURL = result.1.png
            svgURL = result.1.svg
        }
        .alert("QR Maker", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func saveToPhotos() async {
        guard let image = exportImage ?? QRRenderer.exportImage(for: code.content, style: code.style) else {
            message = "The code could not be rendered."
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await PhotoSaver.save(image)
            message = "Saved to Photos."
        } catch {
            message = error.localizedDescription
        }
    }
}

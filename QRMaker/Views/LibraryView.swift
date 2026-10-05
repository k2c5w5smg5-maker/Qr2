import SwiftUI

/// Every code the user has paid for.
struct LibraryView: View {
    @EnvironmentObject private var library: CodeLibrary
    @EnvironmentObject private var store: StoreManager

    var body: some View {
        NavigationStack {
            Group {
                if library.codes.isEmpty {
                    ContentUnavailableView(
                        "No codes yet",
                        systemImage: "qrcode",
                        description: Text("Codes you unlock appear here so you can download them again any time.")
                    )
                } else {
                    List {
                        ForEach(library.codes) { code in
                            NavigationLink(value: code) {
                                row(for: code)
                            }
                        }
                        .onDelete { library.delete(at: $0) }
                    }
                }
            }
            .navigationTitle("My Codes")
            .navigationDestination(for: SavedCode.self) { code in
                CodeDetailView(code: code)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text(store.credits == 1 ? "1 credit" : "\(store.credits) credits")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(for code: SavedCode) -> some View {
        HStack(spacing: 12) {
            QRImage(content: code.content, style: code.style, maxSide: 56)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(code.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(code.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(code.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

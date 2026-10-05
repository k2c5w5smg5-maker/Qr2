import SwiftUI

/// The main screen: choose a destination, style the code, preview it, and pay to unlock it.
struct BuilderView: View {
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var library: CodeLibrary

    @State private var target = QRTarget()
    @State private var style = QRStyle.standard
    @State private var foreground: Color = .black
    @State private var background: Color = .white
    @State private var showPurchase = false
    @State private var unlockedCode: SavedCode?
    @State private var isUnlocking = false

    private var resolvedURL: URL? { target.resolvedURL }
    private var inputIsEmpty: Bool {
        target.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                destinationSection
                Section("Preview") {
                    HStack {
                        Spacer()
                        QRImage(content: resolvedURL?.absoluteString, style: style, maxSide: 260, obscured: true)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                Section("Shape & size") {
                    ShapeSettingsView(canvas: $style.canvas)
                }
                Section("Colors") {
                    ColorPicker("Code color", selection: $foreground, supportsOpacity: false)
                    ColorPicker("Background", selection: $background, supportsOpacity: false)
                    Picker("Error correction", selection: $style.correction) {
                        ForEach(ErrorCorrection.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                }
                purchaseSection
            }
            .navigationTitle("QR Maker")
            .onChange(of: foreground) { _, newValue in style.foreground = RGBAColor(newValue) }
            .onChange(of: background) { _, newValue in style.background = RGBAColor(newValue) }
            .sheet(isPresented: $showPurchase) {
                PurchaseSheet()
            }
            .sheet(item: $unlockedCode) { code in
                NavigationStack {
                    CodeDetailView(code: code)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { unlockedCode = nil }
                            }
                        }
                }
            }
            .alert("Store", isPresented: storeErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.lastError ?? "")
            }
        }
    }

    private var destinationSection: some View {
        Section("What should the code open?") {
            Picker("Type", selection: $target.kind) {
                ForEach(QRKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            if target.kind == .meta {
                Picker("Platform", selection: $target.metaPlatform) {
                    ForEach(MetaPlatform.allCases) { platform in
                        Text(platform.title).tag(platform)
                    }
                }
            }

            TextField(target.kind == .meta ? target.metaPlatform.placeholder : target.kind.placeholder,
                      text: $target.input)
                .keyboardType(target.kind == .meta && target.metaPlatform == .whatsapp ? .phonePad : .URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Text(target.kind.help)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let url = resolvedURL {
                Label(url.absoluteString, systemImage: "link")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if !inputIsEmpty {
                Label("That doesn't look like a valid \(target.kind == .meta ? target.metaPlatform.title : target.kind.title) link yet.",
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var purchaseSection: some View {
        Section {
            Button {
                Task { await unlock() }
            } label: {
                HStack {
                    if isUnlocking || store.isPurchasing {
                        ProgressView()
                    }
                    Text(unlockTitle)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(resolvedURL == nil || isUnlocking || store.isPurchasing)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)

            Button("Buy credit packs") { showPurchase = true }
        } footer: {
            Text(store.credits == 1 ? "You have 1 credit." : "You have \(store.credits) credits. Each unlock uses one credit and saves the code to My Codes for unlimited downloads.")
        }
    }

    private var unlockTitle: String {
        if store.credits > 0 { return "Unlock with 1 credit" }
        if let product = store.singleProduct { return "Unlock for \(product.displayPrice)" }
        return "Unlock"
    }

    private var storeErrorBinding: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )
    }

    private func unlock() async {
        guard let url = resolvedURL else { return }
        isUnlocking = true
        defer { isUnlocking = false }

        if store.credits == 0 {
            guard let product = store.singleProduct else {
                showPurchase = true
                return
            }
            guard await store.purchase(product) else { return }
        }
        guard store.useCredit() else { return }

        let code = SavedCode(title: target.suggestedTitle, target: target, style: style, content: url.absoluteString)
        library.add(code)
        unlockedCode = code
    }
}

#Preview {
    BuilderView()
        .environmentObject(StoreManager())
        .environmentObject(CodeLibrary())
}

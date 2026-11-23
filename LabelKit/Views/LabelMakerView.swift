import SwiftUI

/// The label maker's root screen. Drop it into any app: it owns its own state, so
/// `LabelMakerView()` is all a host app needs (QR Maker shows it as a tab; the standalone
/// Label Maker app uses it as its only screen).
struct LabelMakerView: View {
    @StateObject private var studio = LabelStudio()
    @StateObject private var dictation = Dictation()

    enum Source: String, CaseIterable, Identifiable {
        case page, words
        var id: String { rawValue }
        var title: String { self == .page ? "Product page" : "Tell it" }
    }

    /// Which text box dictation is filling.
    enum Field { case instructions, revision }

    @State private var source: Source = .page
    @State private var pageURL = ""
    @State private var instructions = ""
    @State private var revision = ""
    @State private var dictationField: Field?
    @State private var dictationBase = ""
    @State private var showSettings = false
    @State private var shareItem: ShareItem?
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                inputSection
                if !studio.labels.isEmpty {
                    labelsSection
                    reviseSection
                    SheetSettingsSection(studio: studio)
                    Section("Preview") {
                        SheetPreview(studio: studio)
                    }
                }
            }
            .navigationTitle("Label Maker")
            .toolbar { toolbarContent }
            .sheet(isPresented: $showSettings) {
                ModelSettingsView(studio: studio)
            }
            .sheet(item: $shareItem) { item in
                ActivityView(items: [item.url])
                    .ignoresSafeArea()
            }
            .alert("Label Maker", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(studio.errorMessage ?? dictation.errorMessage ?? "")
            }
            .confirmationDialog("Remove all labels?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Remove all", role: .destructive) { studio.clear() }
            }
            .onChange(of: dictation.transcript) { _, text in
                guard let field = dictationField else { return }
                let combined = dictationBase.isEmpty ? text : dictationBase + " " + text
                switch field {
                case .instructions: instructions = combined
                case .revision: revision = combined
                }
            }
            .onChange(of: dictation.isListening) { _, listening in
                if !listening { dictationField = nil }
            }
        }
    }

    // MARK: - Sections

    private var inputSection: some View {
        Section {
            Picker("Source", selection: $source) {
                ForEach(Source.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            switch source {
            case .page:
                TextField("Paste a product link", text: $pageURL)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                PasteButton(payloadType: String.self) { strings in
                    if let text = strings.first { pageURL = text.trimmed }
                }
                .labelStyle(.titleAndIcon)
                instructionsField(prompt: "Optional: anything to change, e.g. \"6 copies, no price\"")
            case .words:
                instructionsField(prompt: "e.g. \"Pantry labels for flour, sugar and rice with today's date\"")
            }

            Button {
                dictation.stop()
                Task { await studio.generate(pageURL: source == .page ? pageURL : "", instructions: instructions, revise: false) }
            } label: {
                HStack {
                    if studio.isWorking { ProgressView() }
                    Text(studio.isWorking ? (studio.status.isEmpty ? "Working…" : studio.status) : "Make labels")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(studio.isWorking || !canGenerate)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            Text("What are the labels for?")
        } footer: {
            Text(studio.hasRemoteModel
                 ? "Labels are written by your model. Set it up under Settings."
                 : "Labels are written on this device. Connect your own model in Settings for smarter results.")
        }
    }

    private func instructionsField(prompt: String) -> some View {
        HStack(alignment: .top) {
            TextField(prompt, text: $instructions, axis: .vertical)
                .lineLimit(2...6)
            MicButton(isActive: dictationField == .instructions && dictation.isListening) {
                toggleDictation(into: .instructions)
            }
        }
    }

    private var labelsSection: some View {
        Section {
            ForEach($studio.labels) { $label in
                NavigationLink {
                    LabelEditView(label: $label, design: studio.design, template: studio.template)
                } label: {
                    LabelRow(label: label)
                }
            }
            .onDelete { studio.labels.remove(atOffsets: $0) }
            .onMove { studio.labels.move(fromOffsets: $0, toOffset: $1) }

            Button {
                studio.addBlankLabel()
            } label: {
                Label("Add a label", systemImage: "plus")
            }
        } header: {
            HStack {
                Text("Labels")
                Spacer()
                Button("Clear", role: .destructive) { confirmClear = true }
                    .font(.caption)
                    .textCase(nil)
            }
        } footer: {
            if !studio.madeBy.isEmpty { Text("Written by: \(studio.madeBy)") }
        }
    }

    private var reviseSection: some View {
        Section {
            HStack(alignment: .top) {
                TextField("e.g. \"Make 10 of each and add $4.99\"", text: $revision, axis: .vertical)
                    .lineLimit(1...4)
                MicButton(isActive: dictationField == .revision && dictation.isListening) {
                    toggleDictation(into: .revision)
                }
            }
            Button("Apply changes") {
                dictation.stop()
                Task {
                    await studio.generate(pageURL: "", instructions: revision, revise: true)
                    if studio.errorMessage == nil { revision = "" }
                }
            }
            .disabled(studio.isWorking || revision.trimmed.isEmpty)
        } header: {
            Text("Change them by asking")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Settings")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if !studio.labels.isEmpty {
                Button {
                    if let url = studio.exportPDF() { shareItem = ShareItem(url: url) }
                } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share PDF")
                Button {
                    if let url = studio.exportPDF() { PrintController.print(pdf: url) }
                } label: { Image(systemName: "printer") }
                    .accessibilityLabel("Print")
            }
        }
    }

    // MARK: - Helpers

    private var canGenerate: Bool {
        switch source {
        case .page: return !pageURL.trimmed.isEmpty
        case .words: return !instructions.trimmed.isEmpty
        }
    }

    private func toggleDictation(into field: Field) {
        if dictation.isListening, dictationField == field {
            dictation.stop()
            return
        }
        // Switching fields: start() restarts the recognizer without isListening ever
        // reading false, so the onChange handler doesn't clear the new field.
        dictationField = field
        dictationBase = (field == .instructions ? instructions : revision).trimmed
        Task { await dictation.start() }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { studio.errorMessage != nil || dictation.errorMessage != nil },
            set: { if !$0 { studio.errorMessage = nil; dictation.errorMessage = nil } }
        )
    }
}

/// One row in the label list.
private struct LabelRow: View {
    let label: LabelContent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label.title.isEmpty ? "Untitled" : label.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if label.quantity > 1 {
                    Text("×\(label.quantity)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            let secondLine = ([label.subtitle] + label.visibleDetails + [label.price]).map(\.trimmed).filter { !$0.isEmpty }
            if !secondLine.isEmpty {
                Text(secondLine.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !label.qr.trimmed.isEmpty {
                Label(label.qr, systemImage: "qrcode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Microphone toggle for dictating instructions.
struct MicButton: View {
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isActive ? "stop.circle.fill" : "mic.circle.fill")
                .font(.title2)
                .foregroundStyle(isActive ? Color.red : Color.accentColor)
                .symbolEffect(.pulse, isActive: isActive)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isActive ? "Stop dictation" : "Dictate")
    }
}

/// A file handed to the share sheet.
struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

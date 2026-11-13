import SwiftUI

/// State for the label maker: the current labels, sheet settings and model settings.
/// Drafts are saved so they survive relaunches.
@MainActor
final class LabelStudio: ObservableObject {
    @Published var labels: [LabelContent] = [] { didSet { save() } }
    @Published var templateID: String = LabelTemplate.all[0].id { didSet { save() } }
    @Published var design = LabelDesign() { didSet { save() } }
    /// 1-based first free position on the first sheet.
    @Published var startPosition = 1
    @Published var settings = ModelSettings() { didSet { save() } }

    @Published private(set) var isWorking = false
    @Published private(set) var status = ""
    @Published var errorMessage: String?
    /// Which model wrote the current labels, e.g. "Your model (label-maker)" or "On-device".
    @Published private(set) var madeBy = ""

    /// The request behind the current labels, kept for training examples.
    private var lastRequest: LabelRequest?
    private let defaults: UserDefaults
    private var loading = false

    private static let apiKeyAccount = "model-api-key"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    var template: LabelTemplate { LabelTemplate.with(id: templateID) }

    var sheet: LabelSheet {
        LabelSheet(template: template, design: design, labels: labels, startPosition: startPosition - 1)
    }

    var apiKey: String {
        get { Keychain.string(for: Self.apiKeyAccount) ?? "" }
        set { Keychain.set(newValue, for: Self.apiKeyAccount); objectWillChange.send() }
    }

    var hasRemoteModel: Bool { settings.endpoint != nil }

    // MARK: - Making labels

    /// Reads the page (if any), asks the model, and replaces or revises the labels.
    /// - Parameter revise: send the current labels so the instructions edit them.
    func generate(pageURL: String, instructions: String, revise: Bool) async {
        guard !isWorking else { return }
        let url = pageURL.trimmed
        let text = instructions.trimmed
        guard !url.isEmpty || !text.isEmpty else {
            errorMessage = LabelModelError.nothingToLabel.errorDescription
            return
        }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false; status = "" }

        do {
            var request = LabelRequest(instructions: text, current: revise ? labels : [])
            if !url.isEmpty {
                status = "Reading the page…"
                request.product = try await ProductPageReader.read(url)
            }
            status = "Writing labels…"
            let (result, model) = try await run(request)
            labels = result
            madeBy = model
            lastRequest = request
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func run(_ request: LabelRequest) async throws -> ([LabelContent], String) {
        let onDevice = OnDeviceLabelModel()
        guard let endpoint = settings.endpoint else {
            return (try await onDevice.makeLabels(for: request), onDevice.displayName)
        }
        let remote = RemoteLabelModel(endpoint: endpoint, model: settings.model.trimmed, apiKey: apiKey)
        do {
            return (try await remote.makeLabels(for: request), remote.displayName)
        } catch {
            guard settings.fallbackOnDevice, !(error is CancellationError) else { throw error }
            let labels = try await onDevice.makeLabels(for: request)
            return (labels, "On-device (your model failed: \(error.localizedDescription))")
        }
    }

    /// Sends a tiny request to check the model settings. Returns a human-readable result.
    func testModel() async -> String {
        guard let endpoint = settings.endpoint else { return "Enter a valid address first, e.g. https://your-server/v1" }
        let model = RemoteLabelModel(endpoint: endpoint, model: settings.model.trimmed, apiKey: apiKey)
        do {
            let labels = try await model.makeLabels(for: LabelRequest(instructions: "Two pantry labels: flour and sugar"))
            return "Connected. The model returned: " + labels.map(\.title).joined(separator: ", ")
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Editing

    func addBlankLabel() {
        labels.append(LabelContent(title: "New label"))
    }

    func clear() {
        labels = []
        lastRequest = nil
        madeBy = ""
    }

    // MARK: - Output

    /// Writes the PDF to a temporary file for sharing or printing.
    func exportPDF() -> URL? {
        let sheet = self.sheet
        guard !sheet.slots.isEmpty else { return nil }
        let title = labels.first?.title.trimmed ?? ""
        let name = "\(title.isEmpty ? "Labels" : title) - \(template.name)"
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".pdf")
        do {
            try sheet.pdfData().write(to: url, options: .atomic)
            recordTrainingExample()
            return url
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Saves the last request and the labels as finally edited, when the user opted in.
    func recordTrainingExample() {
        guard settings.saveTrainingExamples, let request = lastRequest else { return }
        TrainingLog.append(request: request, labels: labels)
    }

    // MARK: - Persistence

    private struct Saved: Codable {
        var labels: [LabelContent]
        var templateID: String
        var design: LabelDesign
        var settings: ModelSettings
    }

    private static let storageKey = "LabelKit.studio.v1"

    private func save() {
        guard !loading else { return }
        let saved = Saved(labels: labels, templateID: templateID, design: design, settings: settings)
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        loading = true
        defer { loading = false }
        labels = saved.labels
        templateID = saved.templateID
        design = saved.design
        settings = saved.settings
    }
}

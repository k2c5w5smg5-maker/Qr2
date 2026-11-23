import SwiftUI

/// Connect the app to your own label model, and collect training examples for it.
struct ModelSettingsView: View {
    @ObservedObject var studio: LabelStudio
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = ""
    @State private var testResult = ""
    @State private var isTesting = false
    @State private var exampleCount = 0
    @State private var shareItem: ShareItem?
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://your-server.example.com/v1", text: $studio.settings.baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    LabeledContent("Model name") {
                        TextField("label-maker", text: $studio.settings.model)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    SecureField("API key (optional)", text: $apiKey)
                        .onSubmit { studio.apiKey = apiKey }
                    Toggle("Fall back to on-device", isOn: $studio.settings.fallbackOnDevice)
                    Button {
                        studio.apiKey = apiKey
                        isTesting = true
                        Task {
                            testResult = await studio.testModel()
                            isTesting = false
                        }
                    } label: {
                        HStack {
                            Text("Test connection")
                            if isTesting { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isTesting || studio.settings.baseURL.trimmed.isEmpty)
                    if !testResult.isEmpty {
                        Text(testResult).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Your label model")
                } footer: {
                    Text("Any server with an OpenAI-compatible chat completions API works (llama.cpp, Ollama, vLLM, LM Studio). Leave the address empty to write labels on this device only. The product page is read on this phone; your server receives the page summary and your instructions.")
                }

                Section {
                    Toggle("Save training examples", isOn: $studio.settings.saveTrainingExamples)
                    LabeledContent("Saved examples", value: "\(exampleCount)")
                    if exampleCount > 0 {
                        Button("Share training file") { shareItem = ShareItem(url: TrainingLog.fileURL) }
                        Button("Delete training file", role: .destructive) { confirmClear = true }
                    }
                } header: {
                    Text("Train your model")
                } footer: {
                    Text("When on, each sheet you print or share is saved as an example: what the model was asked and the labels as you finally edited them. The file stays on this device until you share it. Feed it to llm/train_lora.py.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        studio.apiKey = apiKey
                        dismiss()
                    }
                }
            }
            .onAppear {
                apiKey = studio.apiKey
                exampleCount = TrainingLog.count
            }
            .sheet(item: $shareItem) { item in
                ActivityView(items: [item.url]).ignoresSafeArea()
            }
            .confirmationDialog("Delete all saved training examples?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    TrainingLog.clear()
                    exampleCount = 0
                }
            }
        }
    }
}

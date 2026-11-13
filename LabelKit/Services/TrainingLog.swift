import Foundation

/// Saves finished jobs as fine-tuning examples: the exact prompt the model saw, and the labels
/// as the user finally printed them (after any hand edits). Every correction you make in the
/// app becomes a better training example for your own model. Off by default; nothing is
/// uploaded. The file is shared by hand from Settings.
///
/// Format: one JSON object per line, `{"messages":[system, user, assistant]}`, the chat format
/// that `llm/train_lora.py` reads.
enum TrainingLog {
    static var fileURL: URL {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("label-training.jsonl")
    }

    static func append(request: LabelRequest, labels: [LabelContent]) {
        let finished = labels.filter { !$0.isBlank }
        guard !request.isEmpty, !finished.isEmpty else { return }
        let record: [String: Any] = [
            "messages": [
                ["role": "system", "content": LabelPrompt.systemPrompt],
                ["role": "user", "content": LabelPrompt.userMessage(for: request)],
                ["role": "assistant", "content": LabelPrompt.assistantMessage(for: finished)],
            ],
        ]
        guard var line = try? JSONSerialization.data(withJSONObject: record, options: [.withoutEscapingSlashes]) else { return }
        line.append(0x0A)

        let url = fileURL
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url, options: .atomic)
        }
    }

    static var count: Int {
        guard let data = try? Data(contentsOf: fileURL) else { return 0 }
        return data.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

import Foundation

/// Anything that can turn a `LabelRequest` into label text. The app ships two:
/// `RemoteLabelModel` (your own LLM, served over an OpenAI-compatible API) and
/// `OnDeviceLabelModel` (rules only, works offline with no model at all).
protocol LabelModel {
    var displayName: String { get }
    func makeLabels(for request: LabelRequest) async throws -> [LabelContent]
}

enum LabelModelError: LocalizedError {
    case notConfigured
    case nothingToLabel
    case server(Int, String)
    case unreadableReply(String)
    case noLabels

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No label model is set up. Add your model's address in Settings."
        case .nothingToLabel:
            return "Give me a product link or tell me what the labels should say."
        case .server(let status, let body):
            return "The label model returned an error (\(status)). \(body)"
        case .unreadableReply(let reply):
            return "The label model replied with something that isn't label JSON: \(reply)"
        case .noLabels:
            return "The label model didn't return any labels. Try rephrasing."
        }
    }
}

/// Where your model is served. Any server with an OpenAI-compatible
/// `POST {baseURL}/chat/completions` endpoint works: llama.cpp `llama-server`, Ollama,
/// vLLM, LM Studio, or your own gateway.
struct ModelSettings: Codable, Equatable {
    /// e.g. "https://labels.example.com/v1" or "http://192.168.1.20:8080/v1".
    var baseURL = ""
    /// The model name the server expects.
    var model = "label-maker"
    /// Fall back to the on-device rules when the model can't be reached.
    var fallbackOnDevice = true
    /// Keep a copy of each finished request + your edited labels as training data.
    var saveTrainingExamples = false

    init() {}

    /// Missing keys keep their defaults, so saved settings survive new fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = (try? c.decodeIfPresent(String.self, forKey: .baseURL)) ?? baseURL
        model = (try? c.decodeIfPresent(String.self, forKey: .model)) ?? model
        fallbackOnDevice = (try? c.decodeIfPresent(Bool.self, forKey: .fallbackOnDevice)) ?? fallbackOnDevice
        saveTrainingExamples = (try? c.decodeIfPresent(Bool.self, forKey: .saveTrainingExamples)) ?? saveTrainingExamples
    }

    var endpoint: URL? {
        let trimmed = baseURL.trimmed
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme != nil, url.host != nil else { return nil }
        if url.path.hasSuffix("/chat/completions") { return url }
        return url.appendingPathComponent("chat").appendingPathComponent("completions")
    }
}

/// Calls your own LLM. The request is a standard chat completion with the shared system
/// prompt, so the same model can be swapped between servers without app changes.
struct RemoteLabelModel: LabelModel {
    let endpoint: URL
    let model: String
    let apiKey: String?

    var displayName: String { "Your model (\(model))" }

    func makeLabels(for request: LabelRequest) async throws -> [LabelContent] {
        guard !request.isEmpty || !request.current.isEmpty else { throw LabelModelError.nothingToLabel }
        let messages = [
            ChatMessage(role: "system", content: LabelPrompt.systemPrompt),
            ChatMessage(role: "user", content: LabelPrompt.userMessage(for: request)),
        ]
        do {
            return try await send(messages, jsonMode: true)
        } catch LabelModelError.server(let status, _) where status == 400 || status == 422 {
            // Some servers don't support `response_format`. Ask again without it.
            return try await send(messages, jsonMode: false)
        }
    }

    private func send(_ messages: [ChatMessage], jsonMode: Bool) async throws -> [LabelContent] {
        var urlRequest = URLRequest(url: endpoint, timeoutInterval: 90)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let body = ChatRequest(model: model, messages: messages, temperature: 0.2, max_tokens: 1500,
                               response_format: jsonMode ? ["type": "json_object"] : nil)
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let text = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw LabelModelError.server(http.statusCode, text)
        }
        let reply = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = reply.choices.first?.message.content else { throw LabelModelError.noLabels }
        let labels = try LabelPrompt.parseReply(content)
        guard !labels.isEmpty else { throw LabelModelError.noLabels }
        return labels
    }

    private struct ChatMessage: Codable {
        var role: String
        var content: String
    }

    private struct ChatRequest: Encodable {
        var model: String
        var messages: [ChatMessage]
        var temperature: Double
        var max_tokens: Int
        var response_format: [String: String]?
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { var content: String? }
            var message: Message
        }
        var choices: [Choice]
    }
}

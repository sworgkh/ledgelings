import Foundation

/// One language model behind an OpenAI-style chat endpoint. LM Studio on this
/// Mac and OpenRouter on the internet both speak that dialect, so one client
/// serves both; only the address, the key and the model differ.
///
/// Any feature that wants words from a model builds one of these (normally
/// through `AppSettings.chatClient()`) and calls `reply`. Banter is the first
/// such feature; it is not special here.
///
/// One trap this guards against: ask LM Studio for a model that is not
/// installed and it silently answers with whatever model happens to be loaded.
/// So `checkModel` compares the id against the server's list before any line
/// is asked for. OpenRouter refuses unknown ids by itself, but the same check
/// gives the settings window the same clear answer.
struct ChatClient: Sendable {
    enum Provider: String, CaseIterable, Codable, Sendable {
        case lmStudio, openRouter

        var title: String {
            switch self {
            case .lmStudio: "LM Studio"
            case .openRouter: "OpenRouter"
            }
        }
    }

    enum Failure: Error, CustomStringConvertible {
        case serverDown(String)
        case modelMissing(String, available: [String])
        case refused(String)
        case badReply(String)

        var description: String {
            switch self {
            case .serverDown(let why): "the server is not answering: \(why)"
            case .modelMissing(let model, let available):
                "model \(model) is not available" + (available.isEmpty ? "" : " (have: \(available.prefix(8).joined(separator: ", ")))")
            case .refused(let message): "the server refused: \(message)"
            case .badReply(let what): "unexpected reply: \(what)"
            }
        }
    }

    static let openRouterURL = URL(string: "https://openrouter.ai/api/v1")!

    var provider: Provider
    /// The `/v1` root: `http://localhost:1234/v1` or `https://openrouter.ai/api/v1`.
    var baseURL: URL
    var apiKey: String?
    var model: String
    var timeout: TimeInterval = 60

    static func lmStudio(server: URL, model: String) -> ChatClient {
        ChatClient(provider: .lmStudio, baseURL: server.appendingPathComponent("v1"), apiKey: nil, model: model)
    }

    static func openRouter(key: String, model: String) -> ChatClient {
        ChatClient(provider: .openRouter, baseURL: openRouterURL, apiKey: key, model: model)
    }

    /// Enough to read OpenRouter's public model list; it needs no key.
    static let openRouterPublic = ChatClient(provider: .openRouter, baseURL: openRouterURL, apiKey: nil, model: "")

    var modelsURL: URL { baseURL.appendingPathComponent("models") }

    // MARK: Requests and replies, no network

    func request(system: String, user: String, maxTokens: Int = 80, temperature: Double = 0.9) throws -> URLRequest {
        struct Body: Encodable {
            struct Message: Encodable { let role: String; let content: String }
            let model: String; let messages: [Message]; let temperature: Double; let max_tokens: Int
        }
        var request = authorised(URLRequest(url: baseURL.appendingPathComponent("chat/completions"), timeoutInterval: timeout))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(
            model: model,
            messages: [.init(role: "system", content: system), .init(role: "user", content: user)],
            temperature: temperature, max_tokens: maxTokens
        ))
        return request
    }

    static func parseReply(_ data: Data) throws -> String {
        struct Reply: Decodable {
            struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }
            let choices: [Choice]
        }
        if let message = serverError(in: data) { throw Failure.refused(message) }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data), let text = reply.choices.first?.message.content else {
            throw Failure.badReply(String(decoding: data.prefix(160), as: UTF8.self))
        }
        return text
    }

    static func parseModels(_ data: Data) throws -> [String] { try ModelCatalog.parse(data).map(\.id) }

    /// Both servers report trouble as `{"error": {"message": ...}}`.
    static func serverError(in data: Data) -> String? {
        struct Reply: Decodable { struct Error: Decodable { let message: String }; let error: Error }
        return (try? JSONDecoder().decode(Reply.self, from: data))?.error.message
    }

    private func authorised(_ request: URLRequest) -> URLRequest {
        var request = request
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        if provider == .openRouter {
            // OpenRouter asks callers to say who they are; it shows up in their usage page.
            request.setValue("https://github.com/sworgkh/ledgelings", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("Ledgelings", forHTTPHeaderField: "X-Title")
        }
        return request
    }

    // MARK: Network

    func listModels() async throws -> [String] { try await catalog().models.map(\.id) }

    /// Everything the provider offers, with names and prices where it gives them.
    func catalog() async throws -> ModelCatalog {
        ModelCatalog(models: try ModelCatalog.parse(try await fetch(authorised(URLRequest(url: modelsURL, timeoutInterval: 15)))))
    }

    func checkModel() async throws {
        let models = try await listModels()
        guard models.contains(model) else { throw Failure.modelMissing(model, available: models) }
    }

    /// OpenRouter only: the key's label and how much it has spent, or a refusal if the key is bad.
    func describeKey() async throws -> String {
        struct Reply: Decodable {
            struct Key: Decodable { let label: String?; let usage: Double?; let limit: Double? }
            let data: Key
        }
        let data = try await fetch(authorised(URLRequest(url: baseURL.appendingPathComponent("auth/key"), timeoutInterval: 10)))
        if let message = Self.serverError(in: data) { throw Failure.refused(message) }
        guard let key = try? JSONDecoder().decode(Reply.self, from: data).data else {
            throw Failure.badReply(String(decoding: data.prefix(120), as: UTF8.self))
        }
        var parts = [key.label ?? "key"]
        if let usage = key.usage { parts.append(String(format: "spent $%.2f", usage)) }
        if let limit = key.limit { parts.append(String(format: "of $%.2f", limit)) }
        return parts.joined(separator: " ")
    }

    /// One completion. `system` is who the speaker is; `user` is the moment.
    func reply(system: String, user: String, maxTokens: Int = 80, temperature: Double = 0.9) async throws -> String {
        try Self.parseReply(try await fetch(try request(system: system, user: user, maxTokens: maxTokens, temperature: temperature)))
    }

    private func fetch(_ request: URLRequest) async throws -> Data {
        do { return try await URLSession.shared.data(for: request).0 } catch { throw Failure.serverDown(error.localizedDescription) }
    }
}

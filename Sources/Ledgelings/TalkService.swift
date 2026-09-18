import Foundation
import LedgelingsCore

/// Talks to LM Studio's local server, which speaks the OpenAI chat API.
///
/// One trap this guards against: ask that server for a model that is not
/// installed and it silently answers with whatever model happens to be loaded.
/// So the model id is checked against `/v1/models` before any line is asked for.
struct TalkService: Sendable {
    enum Failure: Error, CustomStringConvertible {
        case serverDown(String)
        case modelMissing(String, available: [String])
        case badReply(String)

        var description: String {
            switch self {
            case .serverDown(let why): "LM Studio is not answering: \(why)"
            case .modelMissing(let model, let available):
                "model \(model) is not installed" + (available.isEmpty ? "" : " (have: \(available.joined(separator: ", ")))")
            case .badReply(let what): "unexpected reply: \(what)"
            }
        }
    }

    var baseURL: URL
    var model: String
    var timeout: TimeInterval = 60

    func listModels() async throws -> [String] {
        struct Reply: Decodable { struct Row: Decodable { let id: String }; let data: [Row] }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/models"), timeoutInterval: 5)
        request.httpMethod = "GET"
        let data: Data
        do { (data, _) = try await URLSession.shared.data(for: request) } catch { throw Failure.serverDown(error.localizedDescription) }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw Failure.badReply(String(decoding: data.prefix(120), as: UTF8.self))
        }
        return reply.data.map(\.id)
    }

    func checkModel() async throws {
        let models = try await listModels()
        guard models.contains(model) else { throw Failure.modelMissing(model, available: models) }
    }

    /// One completion. `system` is who the speaker is; `user` is the moment.
    func line(system: String, user: String) async throws -> String {
        struct Body: Encodable {
            struct Message: Encodable { let role: String; let content: String }
            let model: String; let messages: [Message]; let temperature: Double; let max_tokens: Int
        }
        struct Reply: Decodable {
            struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }
            let choices: [Choice]
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(
            model: model,
            messages: [.init(role: "system", content: system), .init(role: "user", content: user)],
            temperature: 0.9, max_tokens: 80
        ))
        let data: Data
        do { (data, _) = try await URLSession.shared.data(for: request) } catch { throw Failure.serverDown(error.localizedDescription) }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data), let text = reply.choices.first?.message.content else {
            throw Failure.badReply(String(decoding: data.prefix(160), as: UTF8.self))
        }
        return text
    }
}

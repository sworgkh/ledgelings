import Foundation
import LedgelingsCore

/// The one call dictation makes (§7.13): the recording, as a WAV in the request,
/// to an OpenRouter model that listens, and its transcript back with its price.
/// OpenRouter only: LM Studio has no model that takes audio.
struct DictationClient: Sendable {
    var key: String
    var model: String

    var chat: ChatClient { .openRouter(key: key, model: model) }

    func request(wav: Data, instruction: String, seconds: Double) throws -> URLRequest {
        // The audio has to go up before anything comes back: a minute of it is
        // about 2.5 MB of base64, so the wait grows with the recording.
        var request = chat.authorised(URLRequest(url: ChatClient.openRouterURL.appendingPathComponent("chat/completions"),
                                                 timeoutInterval: 30 + seconds / 2))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Dictation.requestBody(model: model, instruction: instruction, wav: wav)
        return request
    }

    /// The transcript and what it used. A dropped connection is tried once more,
    /// a second later; a refusal (bad key, no credit, unknown model) is not.
    func transcribe(wav: Data, instruction: String, seconds: Double) async throws -> ChatClient.Answer {
        let request = try request(wav: wav, instruction: instruction, seconds: seconds)
        var lastError: Error = ChatClient.Failure.serverDown("")
        for attempt in 0..<2 {
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                return try ChatClient.parseReply(data)
            } catch let failure as ChatClient.Failure {
                throw failure
            } catch {
                lastError = ChatClient.Failure.serverDown(error.localizedDescription)
                if attempt == 0 { try? await Task.sleep(for: .seconds(1)) }
            }
        }
        throw lastError
    }

    /// The models that listen, from OpenRouter's public list (no key needed).
    static func listeningModels() async throws -> [Dictation.Model] {
        let (data, _) = try await URLSession.shared.data(for: URLRequest(url: ChatClient.openRouterPublic.modelsURL, timeoutInterval: 15))
        if let message = ChatClient.serverError(in: data) { throw ChatClient.Failure.refused(message) }
        return try Dictation.listeningModels(in: data)
    }
}

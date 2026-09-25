import Foundation
import LedgelingsCore

/// OpenRouter's text-to-speech: `POST /audio/speech` with a model, a voice and
/// the text, and MP3 bytes back. It uses the same key as the brain.
///
/// The reply is audio, not JSON, so it carries no price. The price comes from
/// `GET /generation?id=…` with the id from the `X-Generation-Id` header, which
/// OpenRouter fills in a few seconds after the call.
struct SpeechClient: Sendable {
    /// A speech model from OpenRouter's list, with the voices it has.
    struct Model: Identifiable, Hashable, Sendable {
        let id: String
        var name: String
        /// Dollars per million input tokens (roughly characters) and per million
        /// output tokens; most speech models charge only for the input.
        var inputPerMillion: Double?
        var outputPerMillion: Double?
        var voices: [String]

        var priceLabel: String {
            guard let inputPerMillion else { return "price unknown" }
            if inputPerMillion == 0 && (outputPerMillion ?? 0) == 0 { return "free" }
            if let outputPerMillion, outputPerMillion > 0 {
                return String(format: "$%.2f in · $%.2f out per M", inputPerMillion, outputPerMillion)
            }
            return String(format: "$%.2f per M chars", inputPerMillion)
        }
    }

    var key: String
    var model: String
    var timeout: TimeInterval = 30

    static var modelsURL: URL {
        var parts = URLComponents(url: ChatClient.openRouterURL.appendingPathComponent("models"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "output_modalities", value: "speech")]
        return parts.url!
    }

    // MARK: Requests and replies, no network

    func request(text: String, voice: String?, speed: Double) throws -> URLRequest {
        struct Body: Encodable {
            let model: String; let input: String; let voice: String?; let response_format: String; let speed: Double
        }
        var request = chat.authorised(URLRequest(url: ChatClient.openRouterURL.appendingPathComponent("audio/speech"), timeoutInterval: timeout))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(model: model, input: text, voice: voice?.isEmpty == false ? voice : nil,
                                                         response_format: "mp3", speed: speed))
        return request
    }

    /// The audio, or the server's complaint when it sent JSON instead.
    static func audio(_ data: Data, contentType: String?) throws -> Data {
        if contentType?.contains("json") == true || data.first == UInt8(ascii: "{") {
            if let message = ChatClient.serverError(in: data) { throw ChatClient.Failure.refused(message) }
            throw ChatClient.Failure.badReply(String(decoding: data.prefix(160), as: UTF8.self))
        }
        guard !data.isEmpty else { throw ChatClient.Failure.badReply("no audio") }
        return data
    }

    static func parseModels(_ data: Data) throws -> [Model] {
        struct Reply: Decodable {
            struct Row: Decodable {
                struct Pricing: Decodable { let prompt: String?; let completion: String? }
                let id: String; let name: String?; let pricing: Pricing?; let supported_voices: [String]?
            }
            let data: [Row]
        }
        if let message = ChatClient.serverError(in: data) { throw ChatClient.Failure.refused(message) }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw ChatClient.Failure.badReply(String(decoding: data.prefix(120), as: UTF8.self))
        }
        func perMillion(_ raw: String?) -> Double? { raw.flatMap(Double.init).map { ($0 * 1_000_000 * 1_000_000).rounded() / 1_000_000 } }
        return reply.data.map {
            Model(id: $0.id, name: $0.name ?? $0.id, inputPerMillion: perMillion($0.pricing?.prompt),
                  outputPerMillion: perMillion($0.pricing?.completion), voices: $0.supported_voices ?? [])
        }
        .sorted { ($0.inputPerMillion ?? .infinity, $0.id) < ($1.inputPerMillion ?? .infinity, $1.id) }
    }

    /// What `/generation` says one call cost; nil while OpenRouter has not filled it in yet.
    static func parseGeneration(_ data: Data) -> Spend.Usage? {
        struct Reply: Decodable {
            struct Row: Decodable { let usage: Double?; let total_cost: Double?; let tokens_prompt: Int?; let tokens_completion: Int? }
            let data: Row
        }
        guard let row = (try? JSONDecoder().decode(Reply.self, from: data))?.data, let cost = row.total_cost ?? row.usage else { return nil }
        return Spend.Usage(promptTokens: row.tokens_prompt ?? 0, completionTokens: row.tokens_completion ?? 0, cost: cost)
    }

    // MARK: Network

    /// Every speech model OpenRouter offers. Public: no key needed.
    static func models() async throws -> [Model] {
        let data: Data
        do { data = try await URLSession.shared.data(for: URLRequest(url: modelsURL, timeoutInterval: 15)).0 }
        catch { throw ChatClient.Failure.serverDown(error.localizedDescription) }
        return try parseModels(data)
    }

    /// The line as MP3, and the id to ask its price by.
    func speak(_ text: String, voice: String?, speed: Double) async throws -> (audio: Data, generation: String?) {
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: try request(text: text, voice: voice, speed: speed)) }
        catch let failure as ChatClient.Failure { throw failure }
        catch { throw ChatClient.Failure.serverDown(error.localizedDescription) }
        let http = response as? HTTPURLResponse
        let audio = try Self.audio(data, contentType: http?.value(forHTTPHeaderField: "Content-Type"))
        return (audio, http?.value(forHTTPHeaderField: "X-Generation-Id"))
    }

    /// What the call cost, asked a few times because the answer lands late.
    /// Nil if it never did; the call is then recorded without a price.
    func cost(of generation: String, tries: Int = 4) async -> Spend.Usage? {
        var parts = URLComponents(url: ChatClient.openRouterURL.appendingPathComponent("generation"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "id", value: generation)]
        for attempt in 0..<tries {
            try? await Task.sleep(for: .seconds(attempt == 0 ? 3 : 5))
            let request = chat.authorised(URLRequest(url: parts.url!, timeoutInterval: 20))
            if let data = try? await URLSession.shared.data(for: request).0, let usage = Self.parseGeneration(data) { return usage }
        }
        return nil
    }

    private var chat: ChatClient { .openRouter(key: key, model: model) }
}

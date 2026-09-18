import Foundation

/// The models a provider offers, with what OpenRouter says about each, and a
/// search over them for the settings window. LM Studio's list has ids only.
struct ModelCatalog: Sendable {
    struct Model: Identifiable, Hashable, Sendable {
        let id: String
        var name: String
        /// Dollars per million tokens. Nil when the provider did not say.
        var promptPerMillion: Double?
        var completionPerMillion: Double?
        var context: Int?

        var isFree: Bool { promptPerMillion == 0 && completionPerMillion == 0 }

        /// Dollars for one creature meeting: two calls of about 300 tokens in and 80 out.
        var exchangeCost: Double? {
            guard let promptPerMillion, let completionPerMillion else { return nil }
            return 2 * (300 * promptPerMillion + 80 * completionPerMillion) / 1_000_000
        }

        var priceLabel: String {
            guard let promptPerMillion, let completionPerMillion else { return "price unknown" }
            if isFree { return "free" }
            return String(format: "$%.2f in · $%.2f out per M", promptPerMillion, completionPerMillion)
        }
    }

    var models: [Model]

    /// OpenRouter's `/models`, which is also the OpenAI shape plus `name`, `pricing` and `context_length`.
    static func parse(_ data: Data) throws -> [Model] {
        struct Reply: Decodable {
            struct Row: Decodable {
                struct Pricing: Decodable { let prompt: String?; let completion: String? }
                let id: String; let name: String?; let pricing: Pricing?; let context_length: Int?
            }
            let data: [Row]
        }
        if let message = ChatClient.serverError(in: data) { throw ChatClient.Failure.refused(message) }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw ChatClient.Failure.badReply(String(decoding: data.prefix(120), as: UTF8.self))
        }
        func perMillion(_ raw: String?) -> Double? { raw.flatMap(Double.init).map { ($0 * 1_000_000 * 1_000_000).rounded() / 1_000_000 } }
        return reply.data.map {
            Model(id: $0.id, name: $0.name ?? $0.id,
                  promptPerMillion: perMillion($0.pricing?.prompt), completionPerMillion: perMillion($0.pricing?.completion),
                  context: $0.context_length)
        }
    }

    /// Every word must appear in the id or the name, any case. Cheapest first; unpriced last.
    func search(_ query: String) -> [Model] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let hits = models.filter { model in
            let haystack = (model.id + " " + model.name).lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
        return hits.sorted { a, b in
            switch (a.exchangeCost, b.exchangeCost) {
            case let (x?, y?) where x != y: x < y
            case (nil, _?): false
            case (_?, nil): true
            default: a.id < b.id
            }
        }
    }
}

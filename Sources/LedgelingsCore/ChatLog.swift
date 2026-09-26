import Foundation

/// Every conversation the creatures have, kept on disk: one JSON-lines file
/// per local calendar day, `YYYY-MM-DD.jsonl`, one exchange per line. Plain
/// files on purpose, so a Finder window or `cat` is a perfectly good viewer.
public struct ChatLog: Sendable {
    public struct Line: Codable, Equatable, Sendable {
        public var speaker: String
        public var text: String
        public init(speaker: String, text: String) { self.speaker = speaker; self.text = text }
    }

    public struct Exchange: Codable, Equatable, Sendable {
        public var time: Date
        public var situation: String
        public var provider: String
        public var model: String
        public var lines: [Line]
        /// What the two calls cost in US dollars and tokens, when the server said.
        public var cost: Double?
        public var tokens: Int?
        /// The story the pair was playing out, and which part of it this was (`Bonds`).
        public var plot: String?

        public init(time: Date, situation: String, provider: String, model: String, lines: [Line],
                    cost: Double? = nil, tokens: Int? = nil, plot: String? = nil) {
            self.time = time; self.situation = situation; self.provider = provider; self.model = model; self.lines = lines
            self.cost = cost; self.tokens = tokens; self.plot = plot
        }
    }

    /// One line said out loud by a paid voice: what it cost, and whose line it
    /// was, so the Chats tab can put it next to its conversation. Kept in a
    /// side file per day, `YYYY-MM-DD.voice.jsonl`, because the price only comes
    /// back seconds after the conversation was written down.
    public struct VoiceCharge: Codable, Equatable, Sendable {
        /// When the line was said, not when its price came back.
        public var time: Date
        public var speaker: String
        /// The words as said (`Voices.speakable` of the line).
        public var text: String
        public var model: String
        /// Nil when OpenRouter never said; 0 for a line played from the voice archive.
        public var cost: Double?
        public var kept: Bool
        public init(time: Date, speaker: String, text: String, model: String, cost: Double?, kept: Bool = false) {
            self.time = time; self.speaker = speaker; self.text = text; self.model = model; self.cost = cost; self.kept = kept
        }
    }

    /// What the voice of one conversation cost.
    public struct VoiceTotal: Equatable, Sendable {
        public var cost = 0.0
        /// Lines said by a paid voice, lines of those without a price, lines replayed free.
        public var lines = 0
        public var unpriced = 0
        public var kept = 0
        public var models: [String] = []
        public init() {}
    }

    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public func voiceFile(for day: String) -> URL { directory.appendingPathComponent("\(day).voice.jsonl") }

    public func appendVoice(_ charge: VoiceCharge) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var line = try encoder.encode(charge)
        line.append(0x0A)
        let url = voiceFile(for: Self.day(of: charge.time))
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url)
        }
    }

    public func voiceCharges(on day: String) -> [VoiceCharge] {
        guard let data = try? Data(contentsOf: voiceFile(for: day)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(VoiceCharge.self, from: $0) }
    }

    /// Which conversation each voice charge belongs to, summed per conversation
    /// (by index into `exchanges`). A charge goes to the latest conversation
    /// that has the same speaker saying the same words and was written down no
    /// later than a minute after the line was said: scripted conversations are
    /// written as they start, model ones when they end.
    public static func voiceTotals(_ charges: [VoiceCharge], for exchanges: [Exchange]) -> [Int: VoiceTotal] {
        var totals: [Int: VoiceTotal] = [:]
        for charge in charges {
            let match = exchanges.indices.filter { i in
                exchanges[i].time <= charge.time.addingTimeInterval(60)
                    && exchanges[i].lines.contains { $0.speaker == charge.speaker && Voices.speakable($0.text) == charge.text }
            }.max { exchanges[$0].time < exchanges[$1].time }
            guard let i = match else { continue }
            var t = totals[i] ?? VoiceTotal()
            if charge.kept { t.kept += 1 } else {
                t.lines += 1
                if let cost = charge.cost { t.cost += cost } else { t.unpriced += 1 }
            }
            if !t.models.contains(charge.model) { t.models.append(charge.model) }
            totals[i] = t
        }
        return totals
    }

    /// The file name's day part, in the local calendar.
    public static func day(of time: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: time)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public func file(for day: String) -> URL { directory.appendingPathComponent("\(day).jsonl") }

    public func append(_ exchange: Exchange) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var line = try encoder.encode(exchange)
        line.append(0x0A)
        let url = file(for: Self.day(of: exchange.time))
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url)
        }
    }

    /// Days that have a log, newest first.
    public func days() throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".jsonl") && $0.count == 16 }
            .map { String($0.dropLast(6)) }
            .sorted(by: >)
    }

    /// One day's exchanges in the order they happened. A damaged line is skipped.
    public func exchanges(on day: String) throws -> [Exchange] {
        guard let data = try? Data(contentsOf: file(for: day)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(Exchange.self, from: $0) }
    }
}

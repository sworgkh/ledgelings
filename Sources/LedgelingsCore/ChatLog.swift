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

        public init(time: Date, situation: String, provider: String, model: String, lines: [Line],
                    cost: Double? = nil, tokens: Int? = nil) {
            self.time = time; self.situation = situation; self.provider = provider; self.model = model; self.lines = lines
            self.cost = cost; self.tokens = tokens
        }
    }

    public let directory: URL

    public init(directory: URL) { self.directory = directory }

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

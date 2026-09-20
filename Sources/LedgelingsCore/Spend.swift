import Foundation

/// What the talking costs. One record per model call, kept as JSON lines in
/// one file, summed by day, month, all time and model.
public enum Spend {

    /// What a server reported for one call. `cost` is in US dollars and only
    /// OpenRouter sends it; a local server's call is priced at zero by the app.
    public struct Usage: Codable, Equatable, Sendable {
        public var promptTokens: Int
        public var completionTokens: Int
        public var cost: Double?
        public init(promptTokens: Int, completionTokens: Int, cost: Double?) {
            self.promptTokens = promptTokens; self.completionTokens = completionTokens; self.cost = cost
        }
    }

    public struct Record: Codable, Equatable, Sendable {
        public var time: Date
        public var provider: String
        public var model: String
        public var usage: Usage
        public init(time: Date, provider: String, model: String, usage: Usage) {
            self.time = time; self.provider = provider; self.model = model; self.usage = usage
        }
    }

    /// A sum of records. `cost` adds up the priced ones; `unpriced` counts the rest.
    public struct Total: Equatable, Sendable {
        public var calls = 0
        public var promptTokens = 0
        public var completionTokens = 0
        public var cost = 0.0
        public var unpriced = 0
        public init() {}

        public var tokens: Int { promptTokens + completionTokens }

        mutating func add(_ u: Usage) {
            calls += 1; promptTokens += u.promptTokens; completionTokens += u.completionTokens
            if let c = u.cost { cost += c } else { unpriced += 1 }
        }
    }

    public struct Summary: Equatable, Sendable {
        public var today = Total()
        public var month = Total()
        public var allTime = Total()
        /// Dearest first; ties by calls.
        public var byModel: [(model: String, total: Total)] = []
        public init() {}

        public static func == (a: Summary, b: Summary) -> Bool {
            a.today == b.today && a.month == b.month && a.allTime == b.allTime
                && a.byModel.map(\.model) == b.byModel.map(\.model) && a.byModel.map(\.total) == b.byModel.map(\.total)
        }
    }

    public static func summarise(_ records: [Record], now: Date = Date(), calendar: Calendar = .current) -> Summary {
        var s = Summary()
        var models: [String: Total] = [:]
        for r in records {
            s.allTime.add(r.usage)
            if calendar.isDate(r.time, equalTo: now, toGranularity: .month) { s.month.add(r.usage) }
            if calendar.isDate(r.time, inSameDayAs: now) { s.today.add(r.usage) }
            models[r.model, default: Total()].add(r.usage)
        }
        s.byModel = models.map { (model: $0.key, total: $0.value) }
            .sorted { ($0.total.cost, $0.total.calls, $1.model) > ($1.total.cost, $1.total.calls, $0.model) }
        return s
    }

    /// Money for people: cents when there are any, otherwise tenths of a cent.
    public static func label(_ usd: Double) -> String {
        if usd == 0 { return "$0.00" }
        if usd < 0.001 { return "<$0.001" }
        if usd < 0.1 { return String(format: "$%.3f", usd) }
        return String(format: "$%.2f", usd)
    }

    /// The file: `spend.jsonl` in a folder, one record a line, appended as calls happen.
    public struct Ledger: Sendable {
        public let directory: URL
        public init(directory: URL) { self.directory = directory }
        public var file: URL { directory.appendingPathComponent("spend.jsonl") }

        public func append(_ record: Record) throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var line = try encoder.encode(record)
            line.append(0x0A)
            if let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: file)
            }
        }

        /// Every record in the order it was written. A damaged line is skipped.
        public func records() throws -> [Record] {
            guard let data = try? Data(contentsOf: file) else { return [] }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return data.split(separator: 0x0A).compactMap { try? decoder.decode(Record.self, from: $0) }
        }
    }
}

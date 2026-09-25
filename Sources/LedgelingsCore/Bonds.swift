import Foundation

/// How two characters who share a screen get on, and the small story playing
/// out between them.
///
/// Every pair of characters on screen at the same time adds up time together.
/// Once a pair has lived side by side long enough, the model writes them a
/// **plot**: a few words of story (a rivalry, a secret, a favour owed) that
/// colours their next few conversations, and a one-line **bond** saying how
/// they get on. When the plot has been played out, the next one grows from the
/// bond and from what they said lately. The prompt carries only those few
/// words, never the whole history, so a long friendship costs no more tokens
/// than a new one.
///
/// Pairs are kept by character name: a rename is a new character with no past.
public enum Bonds {

    /// The story between two characters, and how far into it they are.
    public struct Plot: Codable, Equatable, Sendable {
        public var text: String
        /// Conversations it is meant to last.
        public var length: Int
        /// Conversations already had under it.
        public var told: Int
        public var started: Date
        public init(text: String, length: Int, told: Int = 0, started: Date) {
            self.text = text; self.length = max(1, length); self.told = told; self.started = started
        }
    }

    public struct Bond: Codable, Equatable, Sendable {
        /// The two names, in order.
        public var names: [String]
        /// Seconds both have been on screen at the same time.
        public var together: Double = 0
        /// Conversations with a model between them.
        public var talks: Int = 0
        /// How they get on, as the model last put it.
        public var summary: String?
        public var plot: Plot?
        /// The plot before this one, so the next can follow on.
        public var lastPlot: String?
        /// Plots written for them so far.
        public var plots: Int = 0
        /// The last few lines they said to each other, for the next plot.
        public var recent: [ChatLog.Line] = []
        /// When a plot was last asked for, so a failing model is not asked every conversation.
        public var lastAsked: Date?
        /// What their plots have cost, US dollars, when the server said.
        public var cost: Double?

        public init(names: [String]) { self.names = names }
    }

    /// Lines kept per pair for the next plot.
    public static let recentLines = 4
    /// After a plot request that came to nothing, wait this long before asking again.
    public static let retryAfter: TimeInterval = 10 * 60

    public static func key(_ a: String, _ b: String) -> String {
        [a, b].sorted().joined(separator: " & ")
    }

    /// Every bond, by pair.
    public struct Book: Codable, Equatable, Sendable {
        public var bonds: [String: Bond] = [:]
        public init() {}

        public func bond(_ a: String, _ b: String) -> Bond? { bonds[key(a, b)] }

        public mutating func update(_ a: String, _ b: String, _ change: (inout Bond) -> Void) {
            let k = key(a, b)
            var bond = bonds[k] ?? Bond(names: [a, b].sorted())
            change(&bond)
            bonds[k] = bond
        }

        /// `seconds` passed with all of `names` on screen: every pair of them was together that long.
        public mutating func liveTogether(_ seconds: Double, names: [String]) {
            let unique = Array(Set(names)).sorted()
            guard seconds > 0, unique.count >= 2 else { return }
            for i in unique.indices {
                for j in unique.indices where j > i { update(unique[i], unique[j]) { $0.together += seconds } }
            }
        }

        /// A pair is due a plot when plots are on, it has lived together at least
        /// `after` seconds, has no story running, and was not asked lately.
        public func needsPlot(_ a: String, _ b: String, after: Double, now: Date) -> Bool {
            guard a != b, let bond = bond(a, b), bond.together >= after, bond.plot == nil else { return false }
            if let asked = bond.lastAsked, now.timeIntervalSince(asked) < retryAfter { return false }
            return true
        }

        /// A conversation between them ended with `lines` said: one more part of
        /// the plot is told, and it is over once all its parts are.
        public mutating func talked(_ a: String, _ b: String, lines: [ChatLog.Line]) {
            guard !lines.isEmpty else { return }
            update(a, b) { bond in
                bond.talks += 1
                bond.recent = Array((bond.recent + lines).suffix(recentLines))
                guard var plot = bond.plot else { return }
                plot.told += 1
                if plot.told >= plot.length {
                    bond.lastPlot = plot.text
                    bond.plot = nil
                } else {
                    bond.plot = plot
                }
            }
        }

        /// The model wrote them a new story.
        public mutating func begin(_ a: String, _ b: String, _ written: Written, length: Int, at now: Date) {
            update(a, b) { bond in
                if let summary = written.bond { bond.summary = summary }
                bond.plot = Plot(text: written.plot, length: length, started: now)
                bond.plots += 1
            }
        }

        /// A plot call was made (whatever came of it): note when, and what it cost.
        public mutating func asked(_ a: String, _ b: String, at now: Date, cost: Double?) {
            update(a, b) { bond in
                bond.lastAsked = now
                if let cost { bond.cost = (bond.cost ?? 0) + cost }
            }
        }

        /// Forget one pair, or everyone.
        public mutating func forget(_ key: String) { bonds.removeValue(forKey: key) }

        /// Pairs with the most time together first.
        public var closest: [Bond] {
            bonds.values.sorted { ($0.together, $1.names.joined()) > ($1.together, $0.names.joined()) }
        }
    }

    // MARK: Asking for a plot

    /// What the model sent back: a new bond line (optional) and the plot.
    public struct Written: Equatable, Sendable {
        public var bond: String?
        public var plot: String
        public init(bond: String?, plot: String) { self.bond = bond; self.plot = plot }
    }

    public static let placeholders = ["speaker", "speakerKind", "speakerPersona", "listener", "listenerKind", "listenerPersona",
                                      "together", "bond", "lastPlot", "recent", "length"]

    /// The system side of the plot call: short, so the user prompt carries the work.
    public static let plotSystemPrompt = "You write tiny, playful stories for small characters. Follow the answer format exactly."

    /// One call, one small answer: the story for a pair's next few conversations.
    public static let defaultPlotPrompt = """
    Do not write their conversations. Write only the two lines described at the end.

    Two small creatures live on the edges of a computer screen and have shared it for {together}.
    {speaker}, {speakerKind}: {speakerPersona}
    {listener}, {listenerKind}: {listenerPersona}
    How they get on so far: {bond}
    Their last story: {lastPlot}
    What they said lately:
    {recent}

    Think up what happens between them over their next {length} conversations: a small plot (a rivalry, a secret, \
    a favour owed, a shared plan, a misunderstanding, a crush), true to both of them and growing from how they get on.

    Answer with exactly these two lines and nothing else:
    BOND: how they get on now, at most 15 words
    PLOT: the story to play out, at most 30 words
    """

    /// The values for the plot prompt. `a` and `b` are (name, kind, persona).
    public static func plotValues(_ bond: Bond, a: (name: String, kind: String, persona: String),
                                  b: (name: String, kind: String, persona: String), length: Int) -> [String: String] {
        ["speaker": a.name, "speakerKind": a.kind, "speakerPersona": a.persona,
         "listener": b.name, "listenerKind": b.kind, "listenerPersona": b.persona,
         "together": duration(bond.together),
         "bond": bond.summary ?? "they have not really made their minds up about each other yet",
         "lastPlot": bond.lastPlot ?? "none yet; this is their first",
         "recent": bond.recent.isEmpty ? "(nothing yet)" : bond.recent.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n"),
         "length": "\(length)"]
    }

    /// The two lines out of the model's answer. Nil when there is no plot in it.
    public static func parse(_ raw: String) -> Written? {
        var text = raw
        if let close = text.range(of: "</think>") { text = String(text[close.upperBound...]) }
        var bond: String?, plot: String?
        for line in text.split(whereSeparator: \.isNewline) {
            let bare = line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "*#-_ "))
            for (label, isPlot) in [("BOND:", false), ("PLOT:", true)] {
                guard bare.uppercased().hasPrefix(label) else { continue }
                let value = clean(String(bare.dropFirst(label.count)))
                guard !value.isEmpty else { continue }
                if isPlot { plot = plot ?? value } else { bond = bond ?? value }
            }
        }
        guard let plot else { return nil }
        return Written(bond: bond, plot: plot)
    }

    private static func clean(_ value: String, maxLength: Int = 240) -> String {
        var v = value.trimmingCharacters(in: CharacterSet(charactersIn: "* ").union(.whitespaces))
        while let f = v.first, let l = v.last, v.count > 1, ["\"", "“", "'"].contains(String(f)), ["\"", "”", "'"].contains(String(l)) {
            v = String(v.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        if v.count > maxLength { v = String(v.prefix(maxLength)).trimmingCharacters(in: .whitespaces) + "…" }
        return v
    }

    // MARK: Using it

    /// What goes into `speaker`'s prompt about `other`: the bond and, if one is
    /// running, the plot and which part of it this is. Empty for strangers.
    public static func context(_ bond: Bond?, speaker: String, other: String) -> String {
        guard let bond, bond.summary != nil || bond.plot != nil else { return "" }
        var parts = ["You and \(other) have shared this screen for \(duration(bond.together))."]
        if let summary = bond.summary { parts.append("How you get on: \(summary)") }
        if let plot = bond.plot {
            let part = min(plot.told + 1, plot.length)
            parts.append("What is going on between you (part \(part) of \(plot.length)): \(plot.text)")
            parts.append(part == plot.length
                ? "This is the last part: let your line bring it to an end."
                : "Let it colour your line and move the story on a little; never explain it.")
        }
        return parts.joined(separator: " ")
    }

    /// Put `context` into a rendered system prompt: where the template says
    /// `{relationship}`, or after it when the template does not mention it.
    public static func withRelationship(_ template: String, _ values: [String: String], context: String) -> String {
        if template.contains("{relationship}") {
            return Banter.render(template, values.merging(["relationship": context]) { $1 })
        }
        let rendered = Banter.render(template, values)
        return context.isEmpty ? rendered : rendered + "\n" + context
    }

    /// "40 minutes", "3 hours", "2 days", for people and for prompts.
    public static func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        func plural(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s")" }
        if minutes < 1 { return "a moment" }
        if minutes < 60 { return plural(minutes, "minute") }
        let hours = minutes / 60
        if hours < 24 { return plural(hours, "hour") }
        return plural(hours / 24, "day")
    }

    /// The book on disk: `bonds.json` in a folder, rewritten whole on each save.
    public struct Store: Sendable {
        public let directory: URL
        public init(directory: URL) { self.directory = directory }
        public var file: URL { directory.appendingPathComponent("bonds.json") }

        public func load() -> Book {
            guard let data = try? Data(contentsOf: file) else { return Book() }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return (try? decoder.decode(Book.self, from: data)) ?? Book()
        }

        public func save(_ book: Book) throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(book).write(to: file, options: .atomic)
        }
    }
}

import Foundation

/// How two characters who share a screen get on, and the small story playing
/// out between them.
///
/// Every pair of characters on screen at the same time adds up time together.
/// Once a pair has lived side by side long enough, the model writes them a
/// **plot**: a few words of story (a rivalry, a secret, a favour owed) that
/// colours their next few conversations, and a one-line **bond** saying how
/// they get on. When the plot has been played out, the next one grows from the
/// bond, from what they said lately and from their **storyline**: a short
/// chronicle of everything they have lived through together (talks, tea
/// parties, flowers, paper planes, a cursor grab), rewritten with each new
/// story to take in what happened since (`Bonds+Storyline.swift`). The prompt
/// carries that chronicle and the latest moments, never the raw history, so a
/// long friendship costs only a little more than a new one.
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
        /// Their story so far, a few dozen words, rewritten with each new plot.
        public var chronicle: String?
        /// What they have lived through since the chronicle was last written, oldest first.
        public var moments: [Moment] = []
        /// Everything they ever did together, counted by kind (`Moment.Kind` raw values).
        public var tally: [String: Int] = [:]
        /// The first moment they shared.
        public var met: Date?
        /// Their past in the chat log, from before moments were kept, has been read in.
        public var seeded = false

        public init(names: [String]) { self.names = names }

        /// A `bonds.json` from before a field existed still loads, the field at its default.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            names = try c.decode([String].self, forKey: .names)
            together = try c.decodeIfPresent(Double.self, forKey: .together) ?? 0
            talks = try c.decodeIfPresent(Int.self, forKey: .talks) ?? 0
            summary = try c.decodeIfPresent(String.self, forKey: .summary)
            plot = try c.decodeIfPresent(Plot.self, forKey: .plot)
            lastPlot = try c.decodeIfPresent(String.self, forKey: .lastPlot)
            plots = try c.decodeIfPresent(Int.self, forKey: .plots) ?? 0
            recent = try c.decodeIfPresent([ChatLog.Line].self, forKey: .recent) ?? []
            lastAsked = try c.decodeIfPresent(Date.self, forKey: .lastAsked)
            cost = try c.decodeIfPresent(Double.self, forKey: .cost)
            chronicle = try c.decodeIfPresent(String.self, forKey: .chronicle)
            moments = try c.decodeIfPresent([Moment].self, forKey: .moments) ?? []
            tally = try c.decodeIfPresent([String: Int].self, forKey: .tally) ?? [:]
            met = try c.decodeIfPresent(Date.self, forKey: .met)
            seeded = try c.decodeIfPresent(Bool.self, forKey: .seeded) ?? false
        }
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
        /// the plot is told, and it is over once all its parts are. It is a moment
        /// of their storyline too (`kind`: `.tea` for a whole tea party).
        public mutating func talked(_ a: String, _ b: String, lines: [ChatLog.Line],
                                    as kind: Moment.Kind = .talk, at now: Date = Date()) {
            guard !lines.isEmpty else { return }
            note(a, b, Moment(time: now, kind: kind, who: lines[0].speaker, detail: lines[0].text))
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

        /// The model (or the built-in lines) wrote them a new story. Their storyline
        /// takes in the moments since the last one: the model's rewrite when it sent
        /// one (`STORY:`), else the moments folded in plainly, at most `words` words.
        /// `keepsStory` false (storylines off): the chronicle is left as it was.
        public mutating func begin(_ a: String, _ b: String, _ written: Written, length: Int, at now: Date,
                                   keepsStory: Bool = true, words: Int = Bonds.storyWords) {
            update(a, b) { bond in
                if keepsStory {
                    if let story = written.story {
                        bond.chronicle = Bonds.trimmed(story, words: words)
                    } else {
                        bond.chronicle = Bonds.fold(bond.chronicle, bond.moments, names: bond.names, lastPlot: bond.lastPlot, words: words)
                    }
                    bond.moments = []
                }
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

        /// Start one pair's storyline over: no chronicle, no moments, no stories,
        /// as if they had only just met, though their time together stays. The chat
        /// log is not read back in again.
        public mutating func resetStory(_ key: String) {
            guard var bond = bonds[key] else { return }
            bond.chronicle = nil; bond.moments = []; bond.tally = [:]; bond.met = nil; bond.seeded = true
            bond.summary = nil; bond.plot = nil; bond.lastPlot = nil; bond.plots = 0; bond.recent = []; bond.lastAsked = nil
            bonds[key] = bond
        }

        public mutating func resetAllStories() { for key in Array(bonds.keys) { resetStory(key) } }

        /// Pairs with the most time together first.
        public var closest: [Bond] {
            bonds.values.sorted { ($0.together, $1.names.joined()) > ($1.together, $0.names.joined()) }
        }
    }

    // MARK: Asking for a plot

    /// What the model sent back: a new bond line (optional), the plot, and
    /// their storyline rewritten to take in what happened since (optional).
    public struct Written: Equatable, Sendable {
        public var bond: String?
        public var plot: String
        public var story: String?
        public init(bond: String?, plot: String, story: String? = nil) { self.bond = bond; self.plot = plot; self.story = story }
    }

    public static let placeholders = ["speaker", "speakerKind", "speakerPersona", "listener", "listenerKind", "listenerPersona",
                                      "together", "bond", "lastPlot", "recent", "length",
                                      "today", "story", "since", "storyWords"]

    /// The answer is about 200 tokens; the rest is room for a model that thinks first.
    public static let plotMaxTokens = 1000

    /// The system side of the plot call: short, so the user prompt carries the work.
    public static let plotSystemPrompts = Translated(english: englishPlotSystemPrompt, [.russian: russianPlotSystemPrompt])
    public static var plotSystemPrompt: String { plotSystemPrompts() }
    public static let englishPlotSystemPrompt = "You write tiny, playful stories for small characters. Follow the answer format exactly."

    /// One call, one small answer: the story for a pair's next few conversations.
    public static let plotPrompts = Translated(english: englishPlotPrompt, [.russian: russianPlotPrompt])
    public static var defaultPlotPrompt: String { plotPrompts() }

    public static let englishPlotPrompt = """
    Do not write their conversations. Write only the three lines described at the end.

    Two small creatures live on the edges of a computer screen and have shared it for {together}.
    {speaker}, {speakerKind}: {speakerPersona}
    {listener}, {listenerKind}: {listenerPersona}
    How they get on so far: {bond}
    Their story so far: {story}
    Their last story: {lastPlot}
    What they have lived through since (today is {today}):
    {since}
    What they said lately:
    {recent}

    Think up what happens between them over their next {length} conversations: a small plot (a rivalry, a secret, \
    a favour owed, a shared plan, a misunderstanding, a crush), true to both of them, growing from how they get on \
    and from their story so far: it may bring back something that happened, and it never contradicts it.

    Answer with exactly these three lines and nothing else:
    BOND: how they get on now, at most 15 words
    PLOT: the story to play out, at most 30 words
    STORY: their story so far, rewritten to take in what they have lived through since, at most {storyWords} words; \
    keep what matters most from before, with dates rather than "today" or "yesterday"
    """

    /// The values for the plot prompt. `a` and `b` are (name, kind, persona).
    /// `story` nil: storylines are off, and the prompt says none is kept.
    public static func plotValues(_ bond: Bond, a: (name: String, kind: String, persona: String),
                                  b: (name: String, kind: String, persona: String), length: Int,
                                  story: Telling? = Telling(), now: Date = Date()) -> [String: String] {
        let told = story.map { history(bond, $0, now: now) }
        return ["today": day(now),
         "story": told?.story ?? tr("(not kept)"), "since": told?.since ?? tr("(not kept)"),
         "storyWords": "\(story?.words ?? storyWords)",
         "speaker": a.name, "speakerKind": Banter.spoken(a.kind), "speakerPersona": Banter.persona(a.persona),
         "listener": b.name, "listenerKind": Banter.spoken(b.kind), "listenerPersona": Banter.persona(b.persona),
         "together": duration(bond.together),
         "bond": bond.summary ?? tr("they have not really made their minds up about each other yet"),
         "lastPlot": bond.lastPlot ?? tr("none yet; this is their first"),
         "recent": bond.recent.isEmpty ? tr("(nothing yet)") : bond.recent.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n"),
         "length": "\(length)"]
    }

    /// The two lines out of the model's answer. Nil when there is no plot in it.
    public static func parse(_ raw: String) -> Written? {
        var text = raw
        if let close = text.range(of: "</think>") { text = String(text[close.upperBound...]) }
        var found: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let bare = line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "*#-_ "))
            for label in ["BOND:", "PLOT:", "STORY:"] where found[label] == nil {
                guard bare.uppercased().hasPrefix(label) else { continue }
                // The storyline is longer than the other two: room for a few hundred words, trimmed later to the setting.
                let value = clean(String(bare.dropFirst(label.count)), maxLength: label == "STORY:" ? 2000 : 240)
                if !value.isEmpty { found[label] = value }
            }
        }
        guard let plot = found["PLOT:"] else { return nil }
        return Written(bond: found["BOND:"], plot: plot, story: found["STORY:"])
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
        var parts = [tr("You and %@ have shared this screen for %@.", other, duration(bond.together))]
        if let summary = bond.summary { parts.append(tr("How you get on: %@", summary)) }
        if let plot = bond.plot {
            let part = min(plot.told + 1, plot.length)
            parts.append(tr("What is going on between you (part %d of %d): %@", part, plot.length, plot.text))
            parts.append(part == plot.length
                ? tr("This is the last part: let your line bring it to an end.")
                : tr("Let it colour your line and move the story on a little; never explain it."))
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
        if minutes < 1 { return tr("a moment") }
        if minutes < 60 { return trCount(minutes, "minute", "minutes") }
        let hours = minutes / 60
        if hours < 24 { return trCount(hours, "hour", "hours") }
        return trCount(hours / 24, "day", "days")
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

import Foundation

/// Chat with the creatures (§7.18): the owner writes to one creature, or to
/// everyone on screen, in a paper window on ⌃⌥C, and they answer in their own
/// persona and kind, out loud and in a bubble when the settings say so.
///
/// Each character keeps a short **memory** of these talks: its last few
/// exchanges with the owner, and a summary of the older ones. Both go into its
/// next chat prompt, so it remembers what it was told yesterday. When an
/// exchange falls out of the kept ones, the summary is rewritten to take it in
/// (one model call, priced as `Spend.Purpose.chat`). Nothing here calls a model.
public enum OwnerChat {

    // MARK: How long an answer is

    public enum Length: String, CaseIterable, Codable, Sendable {
        case short, medium, long

        public var title: String {
            switch self {
            case .short: tr("Short: a line")
            case .medium: tr("Medium: a few sentences")
            case .long: tr("Long: a paragraph")
            }
        }

        /// At most this many words, as the prompt asks.
        public var words: Int {
            switch self {
            case .short: 25
            case .medium: 60
            case .long: 120
            }
        }

        /// Room for the answer, thinking included.
        public var maxTokens: Int {
            switch self {
            case .short: 600
            case .medium: 900
            case .long: 1400
            }
        }

        /// The longest answer shown, in characters; a longer one ends on a whole sentence.
        public var maxCharacters: Int {
            switch self {
            case .short: 220
            case .medium: 480
            case .long: 900
            }
        }
    }

    public static let defaultEveryone = 3
    public static let everyoneRange = 1...8
    public static let defaultExchanges = 10
    public static let exchangesRange = 0...50
    /// The summary of the older talks is kept to about this many words.
    public static let summaryWords = 80
    public static let summaryMaxTokens = 700

    // MARK: Who answers "Everyone"

    /// Someone who could answer: a name, and whether it is asleep.
    public struct Candidate: Equatable, Sendable {
        public var name: String
        public var asleep: Bool
        public init(name: String, asleep: Bool) { self.name = name; self.asleep = asleep }
    }

    /// Who answers a message to everyone, in the order they answer: at most
    /// `count`, each once, the awake ones in a random order first, then sleepers
    /// woken by it. They answer one after another, each hearing the ones before.
    public static func answerers(_ candidates: [Candidate], count: Int, using rng: inout some RandomNumberGenerator) -> [String] {
        var seen = Set<String>()
        let unique = candidates.filter { seen.insert($0.name).inserted }
        let awake = unique.filter { !$0.asleep }.shuffled(using: &rng), asleep = unique.filter(\.asleep).shuffled(using: &rng)
        return (awake + asleep).prefix(max(0, count)).map(\.name)
    }

    // MARK: Memory

    /// One message from the owner and the answer it got.
    public struct Exchange: Codable, Equatable, Sendable {
        public var time: Date
        /// What the owner wrote.
        public var said: String
        public var answer: String
        /// Written to everyone, not to this one alone.
        public var everyone: Bool
        public init(time: Date, said: String, answer: String, everyone: Bool = false) {
            self.time = time; self.said = said; self.answer = answer; self.everyone = everyone
        }
    }

    /// What one character remembers of talking with the owner.
    public struct Memory: Codable, Equatable, Sendable {
        public var exchanges: [Exchange] = []
        /// The older talks in a few sentences, as the model put them.
        public var summary: String?
        public var summaryAt: Date?
        /// What writing the summary has cost, in US dollars.
        public var summaryCost: Double?
        public init() {}

        public var isEmpty: Bool { exchanges.isEmpty && (summary ?? "").isEmpty }
    }

    /// Everyone's memory of the owner, by character name.
    public struct Book: Codable, Equatable, Sendable {
        public var memories: [String: Memory] = [:]
        public init() {}

        public func memory(of name: String) -> Memory? { memories[name] }

        /// Keep `exchange` among `name`'s last `keep`; what no longer fits comes
        /// back, oldest first, for the summary to take in.
        @discardableResult
        public mutating func remember(_ name: String, _ exchange: Exchange, keep: Int) -> [Exchange] {
            var memory = memories[name] ?? Memory()
            memory.exchanges.append(exchange)
            let over = max(0, memory.exchanges.count - max(0, keep))
            let dropped = Array(memory.exchanges.prefix(over))
            memory.exchanges.removeFirst(over)
            memories[name] = memory
            return dropped
        }

        /// Every character down to its last `keep` exchanges; what was dropped, by name.
        @discardableResult
        public mutating func keep(_ keep: Int) -> [String: [Exchange]] {
            var dropped: [String: [Exchange]] = [:]
            for (name, var memory) in memories {
                let over = max(0, memory.exchanges.count - max(0, keep))
                guard over > 0 else { continue }
                dropped[name] = Array(memory.exchanges.prefix(over))
                memory.exchanges.removeFirst(over)
                memories[name] = memory
            }
            return dropped
        }

        /// The summary rewritten (nil: the call came back with nothing; only its cost is kept).
        public mutating func summarised(_ name: String, _ summary: String?, at now: Date = Date(), cost: Double?) {
            var memory = memories[name] ?? Memory()
            if let summary, !summary.isEmpty { memory.summary = summary; memory.summaryAt = now }
            if let cost { memory.summaryCost = (memory.summaryCost ?? 0) + cost }
            memories[name] = memory
        }

        public mutating func forget(_ name: String) { memories.removeValue(forKey: name) }
        public mutating func forgetAll() { memories = [:] }

        /// Names with something remembered, A to Z.
        public var names: [String] { memories.filter { !$0.value.isEmpty }.keys.sorted() }
    }

    /// The file: `owner-chats.json` in a folder, beside the bonds.
    public struct Store: Sendable {
        public let directory: URL
        public init(directory: URL) { self.directory = directory }
        public var file: URL { directory.appendingPathComponent("owner-chats.json") }

        /// The book as saved; an empty one when there is none, or it cannot be read.
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

    /// What `name` remembers, for its prompt: the summary, then the kept
    /// exchanges oldest first, each with its day. "" when there is nothing.
    public static func memoryBlock(_ memory: Memory?, now: Date = Date()) -> String {
        guard let memory, !memory.isEmpty else { return "" }
        var parts: [String] = []
        if let summary = memory.summary, !summary.isEmpty { parts.append(tr("What you remember of earlier talks with the owner: %@", summary)) }
        if !memory.exchanges.isEmpty {
            let told = memory.exchanges.map { e in
                tr("%@, the owner: \"%@\"; you: \"%@\"", when(e.time, now: now), e.said, e.answer)
            }
            parts.append(tr("Your last talks with the owner, oldest first: %@.", told.joined(separator: " · ")))
        }
        return parts.joined(separator: "\n")
    }

    /// "today 14:05", "yesterday 09:12", "3 Nov 18:40".
    public static func when(_ time: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let clock = f.string(from: time)
        if calendar.isDate(time, inSameDayAs: now) { return tr("today %@", clock) }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(time, inSameDayAs: y) { return tr("yesterday %@", clock) }
        return Bonds.day(time) + " " + clock
    }

    // MARK: The prompts

    public static let systemPrompts = Translated(english: englishSystemPrompt, [.russian: russianSystemPrompt])
    public static let messagePrompts = Translated(english: englishMessagePrompt, [.russian: russianMessagePrompt])
    public static let summaryPrompts = Translated(english: englishSummaryPrompt, [.russian: russianSummaryPrompt])

    public static let englishSystemPrompt = """
    You are {speaker}, {speakerKind}, living on the edge of a computer screen. {speakerPersona}
    The person who owns this computer has written to you in a little chat window. Answer them yourself, in your own voice and manner, at most {words} words.
    You may tease them, but you are fond of them. Never say you are an AI, a program or a language model.
    {memory}
    Output only your answer. No quotes, no name prefix, no explanation.
    """

    public static let englishMessagePrompt = """
    Right now: {situation}
    {others}The owner writes {to}: "{message}"
    Your answer:
    """

    public static let englishSummaryPrompt = """
    {speaker}, {speakerKind}, lives on the edge of a computer screen and chats now and then with the person who owns the computer. \
    Keep what {speaker} remembers of those talks short and true.
    What it remembered until now: {summary}
    Older talks to take in, oldest first:
    {talks}

    Write what {speaker} remembers now, in at most {words} words: what the owner told it about themselves and their days, \
    promises, plans, likes, and how they get on. Dates rather than "today". Only the text, nothing else.
    """

    public static let placeholders = ["speaker", "speakerKind", "speakerPersona", "words", "memory", "situation", "others", "to", "message"]

    /// The values for one creature's answer. `earlier`: what the ones before it
    /// said to the same message (to everyone), so it can react and not repeat.
    public static func values(speaker: String, kind: String, persona: String, length: Length, memory: String,
                              situation: String, message: String, everyone: Bool, earlier: [(name: String, text: String)]) -> [String: String] {
        let others = earlier.isEmpty ? ""
            : tr("The others have answered already: %@. Say something of your own: react to them if you like, never the same answer.",
                 earlier.map { "\($0.name): \"\($0.text)\"" }.joined(separator: "; ")) + "\n"
        return ["speaker": speaker, "speakerKind": Banter.spoken(kind.isEmpty ? Banter.defaultKind : kind), "speakerPersona": Banter.persona(persona),
                "words": "\(length.words)", "memory": memory, "situation": situation,
                "others": others, "to": everyone ? tr("to all of you") : tr("to you"), "message": message]
    }

    /// The system and user prompt for one answer, from the shipped templates in the current language.
    public static func prompt(_ values: [String: String]) -> (system: String, user: String) {
        let system = Banter.render(systemPrompts(), values).replacingOccurrences(of: "\n\n", with: "\n")
        return (system, Banter.render(messagePrompts(), values))
    }

    /// The summary's prompt: the old summary and the exchanges that fell out of memory.
    public static func summaryPrompt(speaker: String, kind: String, summary: String?, dropped: [Exchange], now: Date = Date()) -> String {
        let talks = dropped.map { "- " + tr("%@, the owner: \"%@\"; you: \"%@\"", when($0.time, now: now), $0.said, $0.answer) }.joined(separator: "\n")
        return Banter.render(summaryPrompts(), ["speaker": speaker, "speakerKind": Banter.spoken(kind.isEmpty ? Banter.defaultKind : kind),
                                                "summary": summary.flatMap { $0.isEmpty ? nil : $0 } ?? tr("(nothing yet)"),
                                                "talks": talks, "words": "\(summaryWords)"])
    }

    /// A model's answer as the window and the bubble show it: no thinking, no
    /// "Name:" prefix, no wrapping quotes, its lines joined, at most `length`'s
    /// characters ending on a whole sentence. "" when nothing is left.
    public static func clean(_ raw: String, speaker: String, length: Length, cut: Bool = false) -> String {
        var text = raw
        if let close = text.range(of: "</think>") { text = String(text[close.upperBound...]) }
        else if text.contains("<think>") { return "" }
        let joined = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        return Banter.cleanLine(joined, speaker: speaker, maxLength: length.maxCharacters, cut: cut)
    }

    /// The summary as the model wrote it, cleaned; nil for nothing.
    public static func cleanSummary(_ raw: String) -> String? {
        var text = raw
        if let close = text.range(of: "</think>") { text = String(text[close.upperBound...]) }
        let joined = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        let trimmed = joined.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”«» ").union(.whitespaces))
        return trimmed.isEmpty ? nil : String(trimmed.prefix(1200))
    }

    // MARK: The window's controls

    /// Every control on the chat window that acts: a pixel picture each, and a
    /// tag naming the action and its key (AGENTS.md §4).
    public enum Button: String, CaseIterable, Sendable {
        case send, everyone, close, settings

        public var tooltip: String {
            switch self {
            case .send: tr("Send (%@)", "⏎")
            case .everyone: tr("Write to everyone (%@)", "⌘0")
            case .close: tr("Close the chat (%@)", "⎋")
            case .settings: tr("Chat settings (%@)", "⌘,")
            }
        }

        /// 11×11, `#` ink, `.` paper, drawn like the game: square pixels, no curves.
        public var icon: [String] {
            switch self {
            // A paper dart flying right.
            case .send: ["...........", "#..........", "###........", "#.###......", "#...###....", "#.....####.", "#...###....", "#.###......", "###........", "#..........", "..........."]
            // Three little blocky creatures side by side.
            case .everyone: ["...........", "...........", "...........", "...###.....", "...#.#.....", "##.###.##..", "#.#...#.#..", "###...###..", "##.#.#.##..", "...........", "..........."]
            case .close: ["...........", ".#.......#.", "..#.....#..", "...#...#...", "....#.#....", ".....#.....", "....#.#....", "...#...#...", "..#.....#..", ".#.......#.", "..........."]
            // A stepped cog.
            case .settings: ["...........", "....###....", ".#.#...#.#.", "..#.....#..", ".#..###..#.", ".#..#.#..#.", ".#..###..#.", "..#.....#..", ".#.#...#.#.", "....###....", "..........."]
            }
        }
    }

    /// A creature's chip in the To: row: its sprite is the picture, this the tag.
    public static func writeTo(_ name: String, number: Int?) -> String {
        number.map { tr("Write to %@ (%@)", name, "⌘\($0)") } ?? tr("Write to %@", name)
    }

    /// The Tools tile and the Creature Actions button: a speech bubble with three dots.
    public static let icon = ["...........", "#########..", "#.......#..", "#.......#..", "#.#.#.#.#..", "#.......#..", "#.......#..", "####.####..", "...#.#.....", "...##......", "...#......."]

    // MARK: Words on the window

    /// "Blocky is thinking…".
    public static func thinking(_ name: String) -> String { tr("%@ is thinking…", name) }

    /// Shown in the window when no model can answer, with a button to the settings.
    public static var noModel: String { tr("Nobody can answer: they need a model. Choose LM Studio or OpenRouter as the Brain, with its key, in Settings › Talk.") }
}

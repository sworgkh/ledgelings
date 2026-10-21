import Foundation

/// Deeds: what a creature does because of what it said or read.
///
/// A conversation used to be words only: a letter saying "soccer?" changed
/// nothing on screen. Now the line a creature says may end with a tag,
/// `DO: invite soccer`, the way a story's answer carries `BOND:` and `PLOT:`.
/// The list of deeds is closed and small (an invitation to a game or to tea,
/// an answer to one, a flower, a letter, a visit, following someone, going to
/// sleep), and each prompt offers only the ones possible right now (`Options`).
/// Whatever comes back is checked against what was offered (`check`) and
/// against the limits the owner set (`Ledger`), so an unknown, impossible or
/// too-frequent deed is simply ignored: the words stay, nothing moves.
///
/// The tag never reaches a bubble or a voice: `split` takes it off the line.
/// Without a model, the built-in lines invite and answer in each character's
/// own voice (`Deeds+Lines.swift`), and chance decides the answer.
public enum Deeds {

    /// What one creature can invite another to: a game they play together, or tea.
    public enum Offer: Equatable, Hashable, Sendable {
        case game(Plays.Kind)
        case tea

        /// As the tag says it: `soccer`, `tea`.
        public var tag: String {
            switch self {
            case .game(let kind): kind.rawValue
            case .tea: "tea"
            }
        }

        /// From a tag word, English or Russian: `soccer`, `футбол`, `tea`, `чай`.
        public init?(word: String) {
            let w = word.lowercased()
            if ["tea", "чай", "чаепитие", "чаю"].contains(w) { self = .tea; return }
            if let kind = Plays.Kind(rawValue: w), Deeds.invitable.contains(kind) { self = .game(kind); return }
            let aliases: [String: Plays.Kind] = [
                "catch": .tag, "салки": .tag, "догонялки": .tag, "football": .soccer, "футбол": .soccer,
                "баскетбол": .basketball, "бейсбол": .baseball, "hoops": .basketball,
            ]
            guard let kind = aliases[w] else { return nil }
            self = .game(kind)
        }

        /// In a word, as a line says it: "Soccer", "Tea".
        public var word: String {
            switch self {
            case .game(.tag): tr("Catch-me-if-you-can")
            case .game(.basketball): tr("Basketball")
            case .game(.soccer): tr("Soccer")
            case .game(.baseball): tr("Baseball")
            case .game(let kind): kind.title
            case .tea: tr("Tea together")
            }
        }

        /// For a prompt or a fact: "a game of soccer", "tea".
        public var title: String {
            switch self {
            case .game(let kind): kind.title
            case .tea: tr("tea together")
            }
        }
    }

    /// The games one can be invited to: the ones two or more play. The rope and
    /// the parachute are played alone.
    public static let invitable: [Plays.Kind] = [.tag, .basketball, .soccer, .baseball]

    /// One deed. A proposal to play or have tea is an invitation: it happens only
    /// once the other says yes.
    public enum Deed: Equatable, Sendable {
        case invite(Offer)
        case accept
        case decline
        case flower
        case letter
        case visit(String)
        case follow
        case sleep

        /// The kind of deed, for limits and for the trace: `invite`, `accept`…
        public var verb: String {
            switch self {
            case .invite: "invite"
            case .accept: "accept"
            case .decline: "decline"
            case .flower: "flower"
            case .letter: "letter"
            case .visit: "visit"
            case .follow: "follow"
            case .sleep: "sleep"
            }
        }

        /// As the tag writes it: `invite soccer`, `visit Boo`.
        public var tag: String {
            switch self {
            case .invite(let offer): "invite " + offer.tag
            case .visit(let name): "visit " + name
            default: verb
            }
        }
    }

    // MARK: Reading the tag

    /// A line as the model wrote it, taken apart: the words to say, the deed, and
    /// a fact to remember (`NOTE:`). `unknown`: a `DO:` that named no deed.
    public struct Tagged: Equatable, Sendable {
        public var text: String
        public var deed: Deed?
        public var note: String?
        public var unknown: String?
        public init(text: String, deed: Deed? = nil, note: String? = nil, unknown: String? = nil) {
            self.text = text; self.deed = deed; self.note = note; self.unknown = unknown
        }
    }

    /// `raw` with its `DO:` and `NOTE:` tags taken off, wherever they are: on a
    /// line of their own, at the end of the line, in brackets or stars. A model's
    /// thinking (`<think>…</think>`) is left in place for `Banter.cleanLine`.
    public static func split(_ raw: String) -> Tagged {
        let tags = try! Regex(#"(?:\bDO|\bNOTE|(?m:^)\s*[\[*(]*\s*(?i:do|note))\s*:"#)
        // Only what comes after the thinking can carry a tag.
        let start = raw.range(of: "</think>")?.upperBound ?? raw.startIndex
        let matches = raw[start...].matches(of: tags)
        guard let first = matches.first else { return Tagged(text: raw) }
        var out = Tagged(text: String(raw[..<first.range.lowerBound]))
        out.text = out.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "[(*")))
        for (n, match) in matches.enumerated() {
            let end = n + 1 < matches.count ? matches[n + 1].range.lowerBound : raw.endIndex
            let label = raw[match.range].uppercased()
            let value = String(raw[match.range.upperBound..<end].split(whereSeparator: \.isNewline).first ?? "")
                .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "[]()*\"'`«».")))
            if label.contains("NOTE") {
                if out.note == nil, !value.isEmpty { out.note = String(value.prefix(160)) }
            } else if out.deed == nil, out.unknown == nil {
                switch parse(value) {
                case .some(.some(let deed)): out.deed = deed
                case .some(.none): break                       // "none"
                case .none: out.unknown = value
                }
            }
        }
        return out
    }

    /// One tag's value: a deed, `.some(nil)` for "none", nil for something unknown.
    public static func parse(_ value: String) -> Deed?? {
        let words = value.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ":" }).map(String.init)
        guard let head = words.first?.lowercased() else { return .some(nil) }
        let rest = Array(words.dropFirst())
        switch head {
        case "none", "nothing", "-", "—", "ничего":
            return .some(nil)
        case "invite", "play", "ask", "propose", "пригласить", "играть":
            guard let word = rest.first(where: { !["to", "a", "game", "of", "в"].contains($0.lowercased()) }),
                  let offer = Offer(word: word) else { return nil }
            return .invite(offer)
        case "accept", "yes", "agree", "ok", "okay", "да", "принять":
            return .accept
        case "decline", "no", "refuse", "нет", "отказ", "отказать":
            return .decline
        case "flower", "give", "gift", "цветок":
            return .flower
        case "letter", "write", "plane", "письмо":
            return .letter
        case "visit", "go", "walk":
            let name = rest.filter { !["to", "see"].contains($0.lowercased()) }.joined(separator: " ")
            if ["sleep", "bed"].contains(name.lowercased()) { return .sleep }
            return name.isEmpty ? nil : .visit(name)
        case "follow", "следовать":
            return .follow
        case "sleep", "nap", "bed", "спать":
            return .sleep
        default:
            return Offer(word: head).map { .invite($0) }
        }
    }

    // MARK: What is offered

    /// An invitation waiting for its answer. Times are the colony's clock.
    public struct Invitation: Equatable, Sendable {
        public var from: String
        public var to: String
        public var offer: Offer
        public var at: Double
        /// Sent in a paper plane, so the answer comes in the plane back.
        public var byLetter: Bool
        public init(from: String, to: String, offer: Offer, at: Double, byLetter: Bool) {
            self.from = from; self.to = to; self.offer = offer; self.at = at; self.byLetter = byLetter
        }
    }

    /// The deeds one creature may take right now, with the one it is speaking to.
    public struct Options: Equatable, Sendable {
        public var games: [Plays.Kind] = []
        public var tea = false
        public var flower = false
        public var letter = false
        /// Who it could walk over to: on screen, awake, not the one it is talking to.
        public var visit: [String] = []
        public var follow = false
        public var sleep = false
        /// The invitation it is answering, if any.
        public var answering: Invitation?
        public init() {}

        public var isEmpty: Bool {
            games.isEmpty && !tea && !flower && !letter && visit.isEmpty && !follow && !sleep && answering == nil
        }

        /// Each offered deed as its tag says it.
        public var tags: [String] {
            var out = games.map { "invite " + $0.rawValue }
            if tea { out.append("invite tea") }
            if flower { out.append("flower") }
            if letter { out.append("letter") }
            out += visit.map { "visit " + $0 }
            if follow { out.append("follow") }
            if sleep { out.append("sleep") }
            return out
        }
    }

    /// Why a deed is not done. Traced, never shown.
    public enum Refusal: String, Equatable, Sendable {
        case notOffered = "not offered"
        case nothingToAnswer = "nothing to answer"
        case tooSoon = "too soon after the last deed"
        case tooMany = "too many deeds this hour"
        case pairTooSoon = "this pair did that lately"
        case loopGuard = "this pair just did something"
        case notFree = "not free"
        case lapsed = "waited too long"
    }

    /// Whether `deed` was one of the `options`.
    public static func check(_ deed: Deed, _ options: Options) -> Refusal? {
        switch deed {
        case .invite(.game(let kind)): options.games.contains(kind) ? nil : .notOffered
        case .invite(.tea): options.tea ? nil : .notOffered
        case .accept, .decline: options.answering == nil ? .nothingToAnswer : nil
        case .flower: options.flower ? nil : .notOffered
        case .letter: options.letter ? nil : .notOffered
        case .visit(let name): options.visit.contains { $0.lowercased() == name.lowercased() } ? nil : .notOffered
        case .follow: options.follow ? nil : .notOffered
        case .sleep: options.sleep ? nil : .notOffered
        }
    }

    // MARK: How often

    /// The owner's limits, in seconds and counts. Zero turns a limit off; the
    /// loop guard stays, so two creatures can never set each other off forever.
    public struct Limits: Equatable, Sendable {
        /// After a deed, the next one anywhere waits this long.
        public var gap: Double
        /// Most deeds started in an hour; 0: no limit.
        public var perHour: Int
        /// The same pair takes the same deed again only after this.
        public var pairGap: Double
        public init(gap: Double, perHour: Int, pairGap: Double) { self.gap = gap; self.perHour = perHour; self.pairGap = pairGap }
    }

    /// Seconds the same pair waits between any two deeds, whatever the settings say.
    public static let loopGuard = 15.0

    /// The deeds done lately, to keep them within the limits.
    public struct Ledger: Equatable, Sendable {
        public struct Entry: Equatable, Sendable {
            public var at: Double
            public var pair: String
            public var verb: String
        }
        public var done: [Entry] = []
        public init() {}

        /// Why `verb` between `a` and `b` may not start now, or nil when it may.
        /// Answers (accept, decline) are free: the invitation was counted.
        public func refusal(_ verb: String, _ a: String, _ b: String, at now: Double, _ limits: Limits) -> Refusal? {
            guard verb != "accept", verb != "decline" else { return nil }
            let pair = Bonds.key(a, b)
            if done.contains(where: { $0.pair == pair && now - $0.at < Deeds.loopGuard }) { return .loopGuard }
            if let last = done.last, limits.gap > 0, now - last.at < limits.gap { return .tooSoon }
            if limits.perHour > 0, done.filter({ now - $0.at < 3600 }).count >= limits.perHour { return .tooMany }
            if limits.pairGap > 0, done.contains(where: { $0.pair == pair && $0.verb == verb && now - $0.at < limits.pairGap }) { return .pairTooSoon }
            return nil
        }

        public mutating func record(_ verb: String, _ a: String, _ b: String, at now: Double) {
            done.append(Entry(at: now, pair: Bonds.key(a, b), verb: verb))
            // Four hours: the longest pair gap the settings allow.
            done.removeAll { now - $0.at > 4 * 3600 }
        }
    }

    // MARK: The prompt

    public static let menuTexts = Translated(english: englishMenu, [.russian: russianMenu])
    public static let englishMenu = """
    If what you say means you really do something, end your answer with one more line: DO: and one of these: {deeds} | none. \
    Most lines need no deed: then write DO: none, or nothing.
    """
    public static let answerTexts = Translated(english: englishAnswer, [.russian: russianAnswer])
    public static let englishAnswer = "{inviter} has invited you to {offer}. End your answer with DO: accept or DO: decline, as you would really answer."
    public static let noteTexts = Translated(english: englishNote, [.russian: russianNote])
    public static let englishNote = """
    If you learn something about {listener} worth remembering for weeks (a promise, a debt, a secret, a rivalry, something they love or hate), \
    you may add a line NOTE: and it, in at most 12 words.
    """

    /// What the prompt says about deeds for `options`; "" when nothing is offered.
    /// `notes`: the model may also write a fact down (`NOTE:`), about `listener`.
    public static func prompt(_ options: Options, notes: Bool = false, listener: String = "") -> String {
        var parts: [String] = []
        if let invitation = options.answering {
            parts.append(Banter.render(answerTexts(), ["inviter": invitation.from, "offer": invitation.offer.title]))
        }
        let tags = options.tags
        if !tags.isEmpty { parts.append(Banter.render(menuTexts(), ["deeds": tags.joined(separator: " | ")])) }
        if notes { parts.append(Banter.render(noteTexts(), ["listener": listener])) }
        return parts.joined(separator: " ")
    }

    // MARK: Without a model

    /// Whether a built-in answer is yes: `chance` percent for a pair who barely
    /// know each other, up to half again as likely for the closest friends.
    public static func builtInYes(closeness: Double, chance: Double, using rng: inout some RandomNumberGenerator) -> Bool {
        let p = min(1, max(0, chance / 100) * (0.75 + 0.5 * min(max(closeness, 0), 1)))
        return Double.random(in: 0..<1, using: &rng) < p
    }

    /// What a built-in invitation is to: a rematch of the game the inviter last
    /// lost to this one if it is offered, else any offered game or tea.
    public static func builtInOffer(_ options: Options, rematch: Plays.Kind? = nil,
                                    using rng: inout some RandomNumberGenerator) -> Offer? {
        if let rematch, options.games.contains(rematch) { return .game(rematch) }
        let all = options.games.map { Offer.game($0) } + (options.tea ? [.tea] : [])
        return all.randomElement(using: &rng)
    }
}

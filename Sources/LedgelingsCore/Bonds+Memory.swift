import Foundation

/// A pair's long-term memory: what two characters remember of each other in
/// every conversation, kept small enough to send with each line.
///
/// Beside the chronicle (their story so far) a pair keeps a few **facts**
/// (a promise, a debt, a rivalry, each dated), a **record** of the games one
/// won against the other, and one **day** entry for each day they shared
/// anything: what they did, counted, the games' results, and a line the model
/// wrote about it. The days are for the owner to read (the Relationships
/// window); a prompt gets only today and yesterday.
///
/// `memory` builds the block a prompt carries, cut to a budget in tokens:
/// what happened today goes in first, then the facts, the record, yesterday,
/// and the chronicle last, trimmed sentence by sentence. Nothing here calls a
/// model: the **diary** (`diaryPrompt`, `parseDiary`) is the app's one call a
/// pair, at the colony's nightfall, that rewrites the chronicle and the facts
/// and writes the day's line. Without a model the counts and results still
/// accumulate, and facts come from deeds and games.
extension Bonds {

    public struct Fact: Codable, Equatable, Sendable {
        public var text: String
        public var time: Date
        /// Who wrote it: `note` (a line's NOTE:), `deed`, `diary`, `seed`.
        public var source: String
        public init(text: String, time: Date, source: String) { self.text = text; self.time = time; self.source = source }
    }

    public struct Day: Codable, Equatable, Sendable {
        /// The user's calendar day, `2026-10-20`.
        public var day: String
        /// What they shared, by `Moment.Kind` raw value.
        public var counts: [String: Int] = [:]
        /// Each game's result in a few words: "soccer 3-2, Boo won".
        public var games: [String] = []
        /// The day in one line, as the model put it.
        public var line: String?
        public init(day: String) { self.day = day }
    }

    /// The facts a pair keeps by default.
    public static let memoryFacts = 5
    /// Days of timeline kept by default.
    public static let memoryDays = 60
    /// Tokens of memory a prompt carries by default.
    public static let memoryTokens = 150

    /// A rough count of tokens: a token is about four bytes of UTF-8, which is
    /// cautious for Russian, where a letter takes two.
    public static func tokens(_ text: String) -> Int { (text.utf8.count + 3) / 4 }

    /// `2026-10-20`, on the user's calendar.
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The day a key names, at its start, or nil.
    public static func date(ofDay key: String, calendar: Calendar = .current) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    /// A moment is counted on its day, and a game's result goes in the record.
    static func keep(_ moment: Moment, in bond: inout Bond) {
        let key = dayKey(moment.time)
        if !bond.days.contains(where: { $0.day == key }) {
            bond.days.append(Day(day: key))
            bond.days.sort { $0.day < $1.day }
        }
        guard let i = bond.days.firstIndex(where: { $0.day == key }) else { return }
        bond.days[i].counts[moment.kind.rawValue, default: 0] += 1
        guard moment.kind == .play else { return }
        if let r = gameLine(moment) { bond.days[i].games.append(r) }
        guard let kind = moment.detail, let winners = moment.winners, bond.names.count == 2 else { return }
        let a = bond.names[0], b = bond.names[1]
        let aWon = winners.contains(a), bWon = winners.contains(b)
        if aWon != bWon { bond.record["\(kind)|\(aWon ? a : b)", default: 0] += 1 }
        else if winners.isEmpty { bond.record["\(kind)|=", default: 0] += 1 }
    }

    // MARK: Games in words

    /// How a game ended: "Boo won, 3-2", "a draw, 2-2", "Blocky asked for it"; nil when there is nothing to say.
    public static func result(_ moment: Moment) -> String? {
        var parts: [String] = []
        if let winners = moment.winners {
            if winners.isEmpty { parts.append(moment.score.map { tr("a draw, %@", $0) } ?? tr("a draw")) }
            else {
                let who = winners.joined(separator: ", ")
                parts.append(moment.score.map { tr("won by %@, %@", who, $0) } ?? tr("won by %@", who))
            }
        } else if let score = moment.score {
            parts.append(score)
        }
        if let asked = moment.asked { parts.append(tr("%@ asked for it", asked)) }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    /// A game for a day's entry: "Soccer: won by Boo, 3-2".
    static func gameLine(_ moment: Moment) -> String? {
        let game = moment.detail.flatMap(Plays.Kind.init(rawValue:)).map { Deeds.Offer.game($0).word } ?? Plays.name(of: moment.detail)
        return result(moment).map { tr("%@: %@", game, $0) } ?? game
    }

    /// Their record, game by game: "Soccer: Boo 3, Blocky 1, 1 draw"; nil before any game was won.
    public static func recordLine(_ bond: Bond) -> String? {
        var games: [String] = []
        for kind in Plays.Kind.allCases {
            let wins = bond.names.compactMap { name in bond.record["\(kind.rawValue)|\(name)"].map { (name, $0) } }
                .sorted { $0.1 > $1.1 }
            let draws = bond.record["\(kind.rawValue)|="] ?? 0
            guard !wins.isEmpty || draws > 0 else { continue }
            var parts = wins.map { "\($0.0) \($0.1)" }
            if draws > 0 { parts.append(trCount(draws, "draw", "draws")) }
            games.append(tr("%@: %@", Deeds.Offer.game(kind).word, parts.joined(separator: ", ")))
        }
        return games.isEmpty ? nil : games.joined(separator: "; ")
    }

    /// The last game `name` lost to the other of the pair, for a rematch.
    public static func lastLost(by name: String, _ bond: Bond?) -> Plays.Kind? {
        guard let bond, let other = bond.names.first(where: { $0 != name }) else { return nil }
        return bond.moments.last { $0.kind == .play && $0.winners?.contains(other) == true && $0.winners?.contains(name) == false }
            .flatMap { $0.detail.flatMap(Plays.Kind.init(rawValue:)) }
    }

    /// A day in words, without a model: "5 talks, 1 tea party; Soccer: won by Boo, 3-2".
    public static func dayLine(_ day: Day) -> String {
        let counted = tallied(day.counts)
        let games = day.games.joined(separator: "; ")
        return [counted, games].filter { !$0.isEmpty }.joined(separator: "; ")
    }

    // MARK: What a prompt carries

    /// What `speaker` remembers of `other`, at most `budget` tokens: what they did
    /// today, the facts, their games, yesterday, how they met and their story,
    /// in that order of need. Empty for strangers or a budget of 0.
    public static func memory(_ bond: Bond?, speaker: String, other: String, budget: Int, now: Date = Date()) -> String {
        guard let bond, budget > 0 else { return "" }
        let today = dayKey(now)
        let yesterday = dayKey(Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now)
        var parts: [Int: String] = [:]          // by place in the text
        var used = 0
        func fits(_ text: String) -> Bool { used + tokens(text) + 1 <= budget }
        func take(_ text: String?, at place: Int) {
            guard let text, !text.isEmpty, fits(text) else { return }
            parts[place] = text
            used += tokens(text) + 1
        }
        let todays = bond.days.first { $0.day == today }
        take(todays.map { tr("Today together: %@.", dayLine($0)) }, at: 6)
        // The facts, newest first, as many as fit.
        var remembered: [String] = []
        for fact in bond.facts.reversed() {
            let text = fact.source == "diary" || fact.source == "seed" ? fact.text : fact.text + " (" + day(fact.time) + ")"
            let all = tr("You remember: %@.", (remembered + [text]).joined(separator: " · "))
            guard fits(all) else { break }
            remembered.append(text)
        }
        if !remembered.isEmpty { take(tr("You remember: %@.", remembered.joined(separator: " · ")), at: 4) }
        take(recordLine(bond).map { tr("Games between you: %@.", $0) }, at: 3)
        take(bond.days.first { $0.day == yesterday }.map { tr("Yesterday: %@.", $0.line ?? dayLine($0)) }, at: 5)
        if let met = bond.met, !bond.tally.isEmpty {
            take(tr("You and %@ first met on %@; all told: %@.", other, day(met), tallied(bond.tally)), at: 1)
        }
        if let chronicle = bond.chronicle, !chronicle.isEmpty {
            // As much of the story as is left room for, newest sentences kept.
            let room = budget - used - 1
            var words = chronicle.split(whereSeparator: \.isWhitespace).count
            while words > 0 {
                let text = tr("Your story so far: %@", trimmed(chronicle, words: words))
                if tokens(text) <= room { take(text, at: 2); break }
                words -= max(1, words / 6)
            }
        }
        return parts.keys.sorted().compactMap { parts[$0] }.joined(separator: " ")
    }

    // MARK: Their day, from one side

    /// What `name` has done today with everyone, newest first, at most `items`
    /// things: "played soccer with Boo and Zed (won by Boo, 3-2) at 10:40; had tea
    /// with Unit 7 at 12:05". Talks are left out: there are too many. "" for none.
    public static func daySoFar(of name: String, in book: Book, now: Date = Date(), items: Int) -> String {
        guard items > 0 else { return "" }
        let calendar = Calendar.current
        struct Seen { var moment: Moment; var with: [String] }
        var seen: [Seen] = []
        for bond in book.bonds.values where bond.names.contains(name) {
            guard let other = bond.names.first(where: { $0 != name }) else { continue }
            for m in bond.moments where m.kind != .talk && calendar.isDate(m.time, inSameDayAs: now) {
                if m.kind == .grab && m.who != name { continue }
                // One game is a moment of every pair that played it: it is told once, with everyone.
                if let k = seen.firstIndex(where: { $0.moment.kind == m.kind && $0.moment.detail == m.detail
                                                    && abs($0.moment.time.timeIntervalSince(m.time)) < 120 && (m.kind == .play || m.kind == .grab) }) {
                    if !seen[k].with.contains(other) { seen[k].with.append(other) }
                    continue
                }
                seen.append(Seen(moment: m, with: [other]))
            }
        }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let told = seen.sorted { $0.moment.time > $1.moment.time }.prefix(items).map { s -> String in
            let m = s.moment, others = s.with.joined(separator: ", "), at = f.string(from: m.time)
            switch m.kind {
            case .play:
                let played = tr("played %@ with %@ at %@", Plays.name(of: m.detail), others, at)
                return result(m).map { played + " (" + $0 + ")" } ?? played
            case .tea: return tr("had tea with %@ at %@", others, at)
            case .flower:
                let flower = Gifts.name(of: m.detail ?? "")
                return m.who == name ? tr("gave %@ a %@ at %@", others, flower, at) : tr("got a %@ from %@ at %@", flower, m.who, at)
            case .plane: return m.who == name ? tr("sent %@ a paper plane at %@", others, at) : tr("got a paper plane from %@ at %@", m.who, at)
            case .grab: return tr("grabbed the cursor at %@", at)
            case .talk: return ""
            }
        }
        return told.isEmpty ? "" : tr("Your day so far: %@.", told.joined(separator: "; "))
    }

    // MARK: The diary

    /// What the model sends back for a pair's memory: their story rewritten,
    /// the facts worth keeping, and a line for each day (keyed `2026-10-20`; "" for
    /// a line that named no day).
    public struct Diary: Equatable, Sendable {
        public var story: String?
        public var facts: [String]
        public var days: [String: String]
        public init(story: String? = nil, facts: [String] = [], days: [String: String] = [:]) {
            self.story = story; self.facts = facts; self.days = days
        }
    }

    public static let diaryMaxTokens = 1200

    public static let diarySystemPrompts = Translated(english: englishDiarySystemPrompt, [.russian: russianDiarySystemPrompt])
    public static let englishDiarySystemPrompt = "You keep short, true memories for small characters. Follow the answer format exactly."

    public static let diaryPrompts = Translated(english: englishDiaryPrompt, [.russian: russianDiaryPrompt])
    public static let englishDiaryPrompt = """
    Two small creatures live on the edges of a computer screen. Keep their long-term memory of each other short and true.
    {speaker}, {speakerKind}: {speakerPersona}
    {listener}, {listenerKind}: {listenerPersona}
    How they get on: {bond}
    Their story so far: {story}
    What they remember: {facts}
    Games between them: {record}
    What happened since their memory was last written (today is {today}):
    {since}
    Some of what they said:
    {lines}

    Answer with these lines and nothing else:
    STORY: their story so far, rewritten to take in what happened since, at most {storyWords} words; dates rather than "today"
    FACT: one thing worth remembering for weeks (a promise, a debt, a secret, a rivalry, a liking), at most 12 words, with its date. \
    Up to {factCount} FACT: lines in all: keep the old facts that still matter, drop what is settled. Events, never catchphrases.
    DAY: {todayKey}: today in one line, at most 25 words
    """

    public static let seedPrompts = Translated(english: englishSeedPrompt, [.russian: russianSeedPrompt])
    public static let englishSeedPrompt = """
    Two small creatures live on the edges of a computer screen. Below is what passed between them over the last {days} days. \
    Write their long-term memory of each other: short, true, in their own small world.
    {speaker}, {speakerKind}: {speakerPersona}
    {listener}, {listenerKind}: {listenerPersona}
    How they get on: {bond}
    Their story so far, as kept until now: {story}
    Day by day, what they shared:
    {digest}
    Some of what they said, oldest first:
    {lines}

    Answer with these lines and nothing else:
    STORY: their story so far, at most {storyWords} words, with dates rather than "today"
    FACT: one thing worth remembering for weeks (a promise, a debt, a secret, a rivalry, a liking), at most 12 words, with its date. \
    Up to {factCount} FACT: lines. Events, never catchphrases.
    DAY: one line for each day above, as "DAY: 2026-10-19: what happened that day", at most 20 words each
    """

    public static let diaryPlaceholders = ["speaker", "speakerKind", "speakerPersona", "listener", "listenerKind", "listenerPersona",
                                           "bond", "story", "facts", "record", "today", "todayKey", "since", "lines",
                                           "storyWords", "factCount", "days", "digest"]

    /// The values shared by the diary and the seed prompts.
    public static func memoryValues(_ bond: Bond, a: (name: String, kind: String, persona: String),
                                    b: (name: String, kind: String, persona: String),
                                    lines: [ChatLog.Line], words: Int, facts: Int, now: Date = Date()) -> [String: String] {
        let shown = bond.moments.filter { m in bond.diaryAt.map { m.time > $0 } ?? true }
        return ["speaker": a.name, "speakerKind": Banter.spoken(a.kind), "speakerPersona": Banter.persona(a.persona),
                "listener": b.name, "listenerKind": Banter.spoken(b.kind), "listenerPersona": Banter.persona(b.persona),
                "bond": bond.summary ?? tr("they have not really made their minds up about each other yet"),
                "story": bond.chronicle ?? tr("nothing yet; they have only just met"),
                "facts": bond.facts.isEmpty ? tr("(nothing yet)") : bond.facts.map { $0.text }.joined(separator: " · "),
                "record": recordLine(bond) ?? tr("(nothing yet)"),
                "today": day(now), "todayKey": dayKey(now),
                "since": shown.isEmpty ? tr("(nothing yet)") : shown.map { "- " + day($0.time) + ": " + describe($0, names: bond.names) }.joined(separator: "\n"),
                "lines": lines.isEmpty ? tr("(nothing yet)") : lines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n"),
                "storyWords": "\(words)", "factCount": "\(facts)"]
    }

    /// The diary's or the seed's answer; nil when it holds none of the three lines.
    public static func parseDiary(_ raw: String) -> Diary? {
        var text = raw
        if let close = text.range(of: "</think>") { text = String(text[close.upperBound...]) }
        var out = Diary()
        let dated = try! Regex(#"^(\d{4}-\d{2}-\d{2})\s*[:—–-]?\s*(.*)$"#)
        for line in text.split(whereSeparator: \.isNewline) {
            let bare = line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "*#-_ "))
            let upper = bare.uppercased()
            func value(_ label: String) -> String {
                clean(String(bare.dropFirst(label.count)))
            }
            if upper.hasPrefix("STORY:"), out.story == nil {
                let v = value("STORY:"); if !v.isEmpty { out.story = String(v.prefix(2000)) }
            } else if upper.hasPrefix("FACT:") || upper.hasPrefix("FACTS:") {
                let v = value(upper.hasPrefix("FACTS:") ? "FACTS:" : "FACT:")
                for one in v.split(separator: "·").map({ clean(String($0)) }) where !one.isEmpty {
                    out.facts.append(String(one.prefix(160)))
                }
            } else if upper.hasPrefix("DAY:") {
                let v = value("DAY:")
                if let m = v.wholeMatch(of: dated), let key = m.output[1].substring, let rest = m.output[2].substring {
                    let line = clean(String(rest)); if !line.isEmpty { out.days[String(key)] = String(line.prefix(240)) }
                } else if !v.isEmpty {
                    out.days[""] = String(v.prefix(240))
                }
            }
        }
        return out.story == nil && out.facts.isEmpty && out.days.isEmpty ? nil : out
    }

    private static func clean(_ value: String) -> String {
        var v = value.trimmingCharacters(in: CharacterSet(charactersIn: "* ").union(.whitespaces))
        while let f = v.first, let l = v.last, v.count > 1, ["\"", "“", "«"].contains(String(f)), ["\"", "”", "»"].contains(String(l)) {
            v = String(v.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return v
    }
}

extension Bonds.Book {

    /// A fact for the pair to remember, unless they already do; the oldest goes
    /// once there are more than `keep`. `keep` 0: no facts are kept at all.
    public mutating func remember(_ a: String, _ b: String, _ text: String, source: String, at now: Date = Date(), keep: Int) {
        let fact = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard a != b, !fact.isEmpty else { return }
        update(a, b) { bond in
            guard keep > 0 else { bond.facts = []; return }
            let key = fact.lowercased()
            guard !bond.facts.contains(where: { $0.text.lowercased() == key }) else { return }
            bond.facts.append(Bonds.Fact(text: fact, time: now, source: source))
            if bond.facts.count > keep { bond.facts.removeFirst(bond.facts.count - keep) }
        }
    }

    /// The diary's answer, written into their memory: the story, the facts in
    /// place of the old ones (the model saw them all), and the day lines. `today`
    /// names the day a line without a date belongs to.
    public mutating func write(_ a: String, _ b: String, _ diary: Bonds.Diary, source: String, at now: Date = Date(),
                               words: Int, keep: Int, cost: Double? = nil) {
        update(a, b) { bond in
            if let story = diary.story { bond.chronicle = Bonds.trimmed(story, words: words) }
            if !diary.facts.isEmpty || keep == 0 {
                bond.facts = Array(diary.facts.suffix(keep)).map { Bonds.Fact(text: $0, time: now, source: source) }
            }
            for (key, line) in diary.days {
                let day = key.isEmpty ? Bonds.dayKey(now) : key
                if let i = bond.days.firstIndex(where: { $0.day == day }) { bond.days[i].line = line }
                else { var d = Bonds.Day(day: day); d.line = line; bond.days.append(d) }
            }
            bond.days.sort { $0.day < $1.day }
            bond.diaryAt = now
            if let cost { bond.memoryCost = (bond.memoryCost ?? 0) + cost }
        }
    }

    /// A pair whose memory call was made, whatever came of it: when, and what it cost.
    public mutating func wroteMemory(_ a: String, _ b: String, at now: Date, cost: Double?) {
        update(a, b) { bond in
            bond.diaryAt = now
            if let cost { bond.memoryCost = (bond.memoryCost ?? 0) + cost }
        }
    }

    /// Keep every pair within the owner's caps: `facts` facts, `days` days of timeline.
    public mutating func keepMemory(facts: Int, days: Int, now: Date = Date()) {
        let oldest = Bonds.dayKey(Calendar.current.date(byAdding: .day, value: -max(0, days), to: now) ?? now)
        for key in Array(bonds.keys) {
            guard var bond = bonds[key] else { continue }
            if bond.facts.count > facts { bond.facts.removeFirst(bond.facts.count - max(0, facts)) }
            bond.days.removeAll { $0.day < oldest || days == 0 }
            bonds[key] = bond
        }
    }

    /// Pairs whose memory is due its diary: something new since it was last
    /// written, and that at least `every` seconds ago. Most new moments first.
    public func diaryDue(every: TimeInterval, now: Date = Date()) -> [Bonds.Bond] {
        bonds.values.compactMap { bond -> (Bonds.Bond, Int)? in
            let fresh = bond.moments.filter { m in bond.diaryAt.map { m.time > $0 } ?? true }.count
            guard fresh > 0, bond.diaryAt.map({ now.timeIntervalSince($0) >= every }) ?? true else { return nil }
            return (bond, fresh)
        }.sorted { ($0.1, $0.0.names.joined()) > ($1.1, $1.0.names.joined()) }.map(\.0)
    }
}

import Foundation

/// A pair's storyline: everything two characters have lived through together,
/// kept small enough to send with every new story.
///
/// Each thing they share is a **moment** (a talk, a tea party, a flower, a paper
/// plane, a cursor grab one of them pulled off with the other there). Moments
/// pile up until the next story is written; then they are folded into the
/// pair's **chronicle**, a few dozen words of "their story so far", and start
/// again. The model rewrites the chronicle itself in the same call that writes
/// the plot (`STORY:`); without a model, or when it sends none, the moments are
/// folded in plainly, a sentence per kind, the oldest sentences dropping off
/// once it is too long. A **tally** counts every moment ever, so even a long
/// past is a number away.
extension Bonds {

    public struct Moment: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, CaseIterable, Sendable {
            case talk, tea, flower, plane, grab
        }
        public var time: Date
        public var kind: Kind
        /// Who did it: the first to speak, the giver, the thrower, the grabber.
        public var who: String
        /// The first line said, the flower given, the note sent; nil for a grab.
        public var detail: String?
        public init(time: Date, kind: Kind, who: String, detail: String? = nil) {
            self.time = time; self.kind = kind; self.who = who; self.detail = detail
        }
    }

    /// Moments kept per pair between stories; the prompt shows the last few of them.
    public static let momentsKept = 20
    /// The chronicle's length by default, in words.
    public static let storyWords = 80
    /// Moments the prompt shows one by one by default; any older are folded first.
    public static let storyMoments = 8

    /// How much of their history a new story is told with.
    public struct Telling: Equatable, Sendable {
        public var words: Int
        public var moments: Int
        public init(words: Int = Bonds.storyWords, moments: Int = Bonds.storyMoments) {
            self.words = words; self.moments = moments
        }
    }

}

extension Bonds.Book {
    /// Something the two lived through together: a moment of their storyline.
    public mutating func note(_ a: String, _ b: String, _ moment: Bonds.Moment) {
        guard a != b else { return }
        update(a, b) { bond in
            bond.moments = Array((bond.moments + [moment]).suffix(Bonds.momentsKept))
            bond.tally[moment.kind.rawValue, default: 0] += 1
            if bond.met.map({ moment.time < $0 }) ?? true { bond.met = moment.time }
        }
    }

    /// Their past in the chat log, from before moments were kept: every
    /// conversation both spoke in, older than the first moment kept, read in
    /// once. The newest become moments, all of them count.
    public mutating func seed(_ a: String, _ b: String, from exchanges: [ChatLog.Exchange]) {
        guard a != b, bond(a, b)?.seeded != true else { return }
        update(a, b) { bond in
            bond.seeded = true
            let before = bond.moments.first?.time ?? .distantFuture
            let shared = exchanges.filter { e in
                e.time < before && e.lines.contains { $0.speaker == a } && e.lines.contains { $0.speaker == b }
            }.sorted { $0.time < $1.time }
            guard let first = shared.first else { return }
            let old = shared.map { Bonds.Moment(time: $0.time, kind: .talk, who: $0.lines[0].speaker, detail: $0.lines[0].text) }
            bond.moments = Array((old + bond.moments).suffix(Bonds.momentsKept))
            bond.tally[Bonds.Moment.Kind.talk.rawValue, default: 0] += shared.count
            if bond.met.map({ first.time < $0 }) ?? true { bond.met = first.time }
        }
    }
}

extension Bonds {

    // MARK: For the prompt

    /// Their story so far and what has happened since, as the plot prompt has
    /// them: moments beyond the last `telling.moments` are folded into the
    /// chronicle first, so nothing kept is left out and the prompt stays small.
    public static func history(_ bond: Bond, _ telling: Telling, now: Date = Date()) -> (story: String, since: String) {
        let shown = Array(bond.moments.suffix(max(1, telling.moments)))
        let older = Array(bond.moments.dropLast(shown.count))
        let story = older.isEmpty ? bond.chronicle : fold(bond.chronicle, older, names: bond.names, lastPlot: nil, words: telling.words)
        var opening = story ?? ""
        if let met = bond.met, !bond.tally.isEmpty {
            let since = tr("They first met on %@; all told: %@.", day(met), tallied(bond.tally))
            opening = opening.isEmpty ? since : since + " " + opening
        }
        let lines = shown.map { "- " + day($0.time) + ": " + describe($0, names: bond.names) }
        return (opening.isEmpty ? tr("nothing yet; they have only just met") : opening,
                lines.isEmpty ? tr("(nothing yet)") : lines.joined(separator: "\n"))
    }

    /// "14 Oct", in the current language: the chronicle keeps dates, never "today".
    public static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Language.current == .russian ? "ru_RU" : "en_GB")
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f.string(from: date)
    }

    /// "5 talks, 2 tea parties, 1 flower": everything they ever did together.
    public static func tallied(_ tally: [String: Int]) -> String {
        Moment.Kind.allCases.compactMap { kind in
            guard let n = tally[kind.rawValue], n > 0 else { return nil }
            return count(n, kind)
        }.joined(separator: ", ")
    }

    static func count(_ n: Int, _ kind: Moment.Kind) -> String {
        switch kind {
        case .talk: trCount(n, "talk", "talks")
        case .tea: trCount(n, "tea party", "tea parties")
        case .flower: trCount(n, "flower", "flowers")
        case .plane: trCount(n, "paper plane", "paper planes")
        case .grab: trCount(n, "cursor grab", "cursor grabs")
        }
    }

    /// One moment in a few words: `Pip and Blocky talked; Pip said: "Hi!"`.
    public static func describe(_ moment: Moment, names: [String]) -> String {
        let other = names.first { $0 != moment.who } ?? moment.who
        let said = moment.detail.map { short($0) } ?? ""
        switch moment.kind {
        case .talk: return tr("%1$@ and %2$@ talked; %1$@ said: \"%3$@\"", moment.who, other, said)
        case .tea: return tr("%1$@ and %2$@ had a tea party; %1$@ told a story: \"%3$@\"", moment.who, other, said)
        case .flower: return tr("%1$@ gave %2$@ a %3$@", moment.who, other, Gifts.name(of: moment.detail ?? ""))
        case .plane: return tr("%1$@ sent %2$@ a paper plane: \"%3$@\"", moment.who, other, said)
        case .grab: return tr("%1$@ grabbed the cursor while %2$@ looked on", moment.who, other)
        }
    }

    /// A line cut to its first dozen words, for a moment.
    static func short(_ text: String, words: Int = 12) -> String {
        let all = text.split(whereSeparator: \.isWhitespace)
        return all.count <= words ? all.joined(separator: " ") : all.prefix(words).joined(separator: " ") + "…"
    }

    // MARK: Folding, without a model

    /// The chronicle with `moments` folded in plainly: a sentence per kind of
    /// moment (how many, between which days, the latest of them), then the story
    /// that just ended, all kept to `words` words by dropping the oldest sentences.
    public static func fold(_ chronicle: String?, _ moments: [Moment], names: [String], lastPlot: String?, words: Int) -> String? {
        var sentences = chronicle.map(Self.sentences) ?? []
        for kind in Moment.Kind.allCases {
            let these = moments.filter { $0.kind == kind }
            guard let first = these.first, let last = these.last else { continue }
            let when = day(first.time) == day(last.time) ? tr("On %@", day(last.time))
                : tr("Between %@ and %@", day(first.time), day(last.time))
            let what = these.count == 1 ? describe(last, names: names)
                : tr("%@ in all, the last: %@", count(these.count, kind), describe(last, names: names))
            let sentence = tr("%@, %@", when, what)
            // A quoted line that ends its own sentence needs no second full stop.
            let ends = sentence.trimmingCharacters(in: CharacterSet(charactersIn: "\"»”")).last.map { ".!?…".contains($0) } ?? false
            sentences.append(ends ? sentence : sentence + ".")
        }
        if let lastPlot { sentences.append(tr("Then this story played out: %@", lastPlot)) }
        guard !sentences.isEmpty else { return chronicle }
        return trimmed(sentences.joined(separator: " "), words: words)
    }

    /// `text` kept to `words` words: whole sentences from the end, newest kept;
    /// a single sentence longer than that is cut with "…".
    public static func trimmed(_ text: String, words: Int) -> String {
        let limit = max(1, words)
        var kept: [String] = []
        var count = 0
        for sentence in sentences(text).reversed() {
            let n = sentence.split(whereSeparator: \.isWhitespace).count
            if count + n > limit { break }
            kept.insert(sentence, at: 0)
            count += n
        }
        if kept.isEmpty { return short(text, words: limit) }
        return kept.joined(separator: " ")
    }

    /// `text` cut into sentences; a quoted line ("Tea? I baked a pixel.") stays whole.
    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        var quoted = false
        let characters = Array(text)
        for (i, c) in characters.enumerated() {
            current.append(c)
            if c == "\"" { quoted.toggle() } else if c == "«" || c == "“" { quoted = true } else if c == "»" || c == "”" { quoted = false }
            let ends = !quoted && ".!?…\"»”".contains(c) && (i + 1 == characters.count || characters[i + 1].isWhitespace)
                && (".!?…".contains(c) || (i > 0 && ".!?…".contains(characters[i - 1])))
            if ends {
                let s = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { out.append(s) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { out.append(rest) }
        return out
    }

    // MARK: A story without a model

    /// The next story from the built-in lines, no network: it grows from the
    /// most telling thing they lived through since the last one (a flower over a
    /// tea party over a plane over a grab over a talk), with when it was, and a
    /// bond line from everything they ever did together, unless they already have one.
    public static func builtInPlot(_ bond: Bond, now: Date = Date(), using rng: inout some RandomNumberGenerator) -> Written {
        let order: [Moment.Kind] = [.flower, .tea, .plane, .grab, .talk]
        let moment = order.lazy.compactMap { kind in bond.moments.last { $0.kind == kind } }.first
        let names = bond.names
        let a = names.first ?? "", b = names.last ?? ""
        let plot: String
        if let moment {
            let who = moment.who, other = names.first { $0 != moment.who } ?? moment.who
            let when = ago(moment.time, now: now)
            let said = moment.detail.map { short($0, words: 8) } ?? ""
            let choices: [String]
            switch moment.kind {
            case .flower:
                let flower = Gifts.name(of: moment.detail ?? "")
                choices = [tr("Since %1$@ gave %2$@ the %3$@ %4$@, %2$@ has been looking for a gift to give back.", who, other, flower, when),
                           tr("%2$@ has kept the %3$@ %1$@ gave %4$@, and wants to know what it means.", who, other, flower, when)]
            case .tea:
                choices = [tr("Ever since the tea party %3$@, %2$@ wants to hear how %1$@'s story ends.", who, other, when),
                           tr("%1$@ is planning another tea party for %2$@, better than the one %3$@.", who, other, when)]
            case .plane:
                choices = [tr("%2$@ still has the paper plane %1$@ sent %3$@ (\"%4$@\") and is writing an answer.", who, other, when, said),
                           tr("%1$@ waits for %2$@ to answer the paper plane from %3$@.", who, other, when)]
            case .grab:
                choices = [tr("%2$@ cannot decide whether %1$@ grabbing the cursor %3$@ was brave or silly.", who, other, when),
                           tr("%1$@ wants %2$@ to help grab the cursor next time, after %3$@.", who, other, when)]
            case .talk:
                choices = [tr("%2$@ keeps coming back to what %1$@ said %3$@: \"%4$@\"", who, other, when, said),
                           tr("%1$@ and %2$@ have not settled what they talked about %3$@.", who, other, when)]
            }
            plot = choices.randomElement(using: &rng) ?? choices[0]
        } else {
            let choices = [tr("%@ and %@ take turns guarding their favourite corner of the screen.", a, b),
                           tr("%@ and %@ share a secret about the bottom edge.", a, b)]
            plot = choices.randomElement(using: &rng) ?? choices[0]
        }
        // A bond line a model once wrote says more than a count: it stays.
        let total = bond.tally.values.reduce(0, +)
        let summary: String? = bond.summary != nil || total == 0 ? bond.summary
            : total >= 10 ? tr("After %@, they know each other well.", tallied(bond.tally))
            : tr("After %@, they are getting to know each other.", tallied(bond.tally))
        return Written(bond: summary, plot: plot)
    }

    /// "today", "yesterday", "3 days ago": when a moment was, from now.
    public static func ago(_ time: Date, now: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: time), to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 0 { return tr("today") }
        if days == 1 { return tr("yesterday") }
        if days < 14 { return tr("%@ ago", trCount(days, "day", "days")) }
        return tr("%@ ago", trCount(days / 7, "week", "weeks"))
    }
}

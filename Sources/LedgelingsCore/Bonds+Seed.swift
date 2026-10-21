import Foundation

/// The seed: a pair's starting memory, read from the chat log of the last few
/// weeks. Without a model the log gives the days their counts; with one, a
/// digest of it (the counts day by day and a sample of what was said) goes in
/// one call per pair, and the answer is written as the diary's would be.
///
/// Only the creatures' own words and what kind of moment each was go into the
/// digest. The situation a conversation was had in is read to tell a letter
/// from a tea party from a flower, and never sent: it carries the user's clock,
/// holidays and cursor counts.
extension Bonds {

    /// What the chat log holds about one pair over the seed's days.
    public struct SeedDigest: Equatable, Sendable {
        /// Day by day (`2026-10-19`): what they shared, by `Moment.Kind` raw value.
        public var days: [String: [String: Int]] = [:]
        /// The lines picked to show the model, by day, oldest first.
        public var lines: [(day: String, line: ChatLog.Line)] = []
        /// Every conversation both spoke in.
        public var exchanges = 0
        public init() {}

        public static func == (a: SeedDigest, b: SeedDigest) -> Bool {
            a.days == b.days && a.exchanges == b.exchanges
                && a.lines.map(\.day) == b.lines.map(\.day) && a.lines.map(\.line) == b.lines.map(\.line)
        }
    }

    /// A tea party is one sitting: rounds this close together count once.
    public static let teaSitting: TimeInterval = 15 * 60

    /// What kind of moment a logged conversation was, from its situation, in either language.
    public static func classify(_ situation: String) -> Moment.Kind {
        let s = situation.lowercased()
        if s.contains("paper plane") || s.contains("бумажн") { return .plane }
        if s.contains("tea") && (s.contains("table") || s.contains("sit down")) || s.contains("столик") || s.contains("пить чай") { return .tea }
        if s.contains("gave") && s.contains("a ") && s.contains("walked into") || s.contains("дарит") { return .flower }
        return .talk
    }

    /// The digest of `a` and `b`'s conversations in `exchanges` between `from`
    /// and `to`: every day's counts, and about `lines` lines spread across the
    /// days, letters first, then the first round of each tea party, then talks.
    public static func seedDigest(_ exchanges: [ChatLog.Exchange], _ a: String, _ b: String,
                                  from: Date, to: Date, lines: Int) -> SeedDigest {
        var out = SeedDigest()
        let shared = exchanges.filter { e in
            e.time >= from && e.time <= to && e.lines.contains { $0.speaker == a } && e.lines.contains { $0.speaker == b }
        }.sorted { $0.time < $1.time }
        out.exchanges = shared.count
        var byDay: [String: [(ChatLog.Exchange, Moment.Kind, Int)]] = [:]
        var lastTea: Date?
        for e in shared {
            let kind = classify(e.situation)
            let key = dayKey(e.time)
            var rank = 3
            switch kind {
            case .plane: rank = 0
            case .tea:
                let newSitting = lastTea.map { e.time.timeIntervalSince($0) > teaSitting } ?? true
                lastTea = e.time
                if newSitting { out.days[key, default: [:]][kind.rawValue, default: 0] += 1; rank = 1 } else { rank = 4 }
            case .flower: rank = 2
            default: break
            }
            if kind != .tea { out.days[key, default: [:]][kind.rawValue, default: 0] += 1 }
            byDay[key, default: []].append((e, kind, rank))
        }
        let keys = byDay.keys.sorted()
        guard !keys.isEmpty, lines > 0 else { return out }
        // An even share of lines for every day, the best-ranked conversations of each.
        let share = max(2, lines / keys.count)
        var picked: [(day: String, time: Date, line: ChatLog.Line)] = []
        for key in keys {
            var taken = 0
            for (e, _, _) in byDay[key]!.sorted(by: { ($0.2, $0.0.time) < ($1.2, $1.0.time) }) {
                guard taken < share else { break }
                for line in e.lines where taken < share { picked.append((key, e.time, line)); taken += 1 }
            }
        }
        out.lines = Array(picked.sorted { $0.time < $1.time }.prefix(lines)).map { ($0.day, $0.line) }
        return out
    }

    /// The seed prompt's values for one pair.
    public static func seedValues(_ bond: Bond, _ digest: SeedDigest, a: (name: String, kind: String, persona: String),
                                  b: (name: String, kind: String, persona: String), days: Int, words: Int, facts: Int) -> [String: String] {
        var values = memoryValues(bond, a: a, b: b, lines: [], words: words, facts: facts)
        values["days"] = "\(days)"
        values["digest"] = digest.days.keys.sorted().map { key in "- \(key): " + tallied(digest.days[key] ?? [:]) }.joined(separator: "\n")
        values["lines"] = digest.lines.map { "[\($0.day)] \($0.line.speaker): \($0.line.text)" }.joined(separator: "\n")
        return values
    }
}

extension Bonds.Book {

    /// The digest's counts written into the pair's days: a day already counted
    /// keeps the larger of the two, so a seed run twice counts nothing twice.
    public mutating func seedDays(_ a: String, _ b: String, _ digest: Bonds.SeedDigest, at now: Date = Date()) {
        update(a, b) { bond in
            for (key, counts) in digest.days {
                if let i = bond.days.firstIndex(where: { $0.day == key }) {
                    bond.days[i].counts.merge(counts) { max($0, $1) }
                } else {
                    var day = Bonds.Day(day: key); day.counts = counts; bond.days.append(day)
                }
            }
            bond.days.sort { $0.day < $1.day }
            bond.memorySeeded = now
        }
    }
}

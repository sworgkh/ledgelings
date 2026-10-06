import Foundation

/// How often the user's cursor has hunted each character: chased it off its
/// edge or picked it up, the same moments `Annoyance` counts towards a
/// complaint. Kept per character name by the user's own calendar day, so it
/// can say today, yesterday, this week (the week starts where the system's
/// locale starts it) and in all, and it survives a relaunch in `hunts.json`.
///
/// The creatures use it three ways, none of them a model call of its own:
/// - a sentence for `{situation}` (`sentence`): the numbers, how today compares
///   with yesterday and with the week, a record, who is the most chased, and
///   what the speaker makes of it in the current cursor mood;
/// - built-in lines in each character's voice and mood (`line`), said at a
///   milestone, or now and then instead of a complaint, a tea story or a note;
/// - in the bad mood, a much-hunted creature keeps further from the cursor.
public enum Hunts {
    /// One character's count: by day ("2026-10-06", the user's calendar), and in all.
    public struct Tally: Codable, Equatable, Sendable {
        public var days: [String: Int] = [:]
        public var all = 0
        public init() {}
    }

    /// What a creature knows of its own count, as of one moment.
    public struct Numbers: Equatable, Sendable {
        public var today = 0, yesterday = 0, week = 0, all = 0
        /// Its busiest day before today, among the days still kept.
        public var bestBefore = 0
        /// Days of this week before today, for the week's daily average.
        public var daysBeforeToday = 0
        public init(today: Int = 0, yesterday: Int = 0, week: Int = 0, all: Int = 0, bestBefore: Int = 0, daysBeforeToday: Int = 0) {
            self.today = today; self.yesterday = yesterday; self.week = week; self.all = all
            self.bestBefore = bestBefore; self.daysBeforeToday = daysBeforeToday
        }

        /// This week's days before today, on average; nil on the week's first day.
        public var weekAverageBefore: Double? {
            daysBeforeToday > 0 ? Double(week - today) / Double(daysBeforeToday) : nil
        }
    }

    /// Days kept per character: enough for a record and any week, small enough to stay a tiny file.
    public static let daysKept = 92

    /// Every character's tally, and since when it has been counting.
    public struct Book: Codable, Equatable, Sendable {
        public var tallies: [String: Tally] = [:]
        /// The first count after the book was started or reset.
        public var since: Date?
        public init() {}

        /// One more hunt of `name` at `now`. Days older than `daysKept` are let go.
        public mutating func count(_ name: String, at now: Date, calendar: Calendar = .current) {
            var tally = tallies[name] ?? Tally()
            let key = Hunts.day(now, calendar)
            tally.days[key, default: 0] += 1
            tally.all += 1
            if tally.days.count > daysKept, let oldest = calendar.date(byAdding: .day, value: -daysKept, to: now) {
                let cut = Hunts.day(oldest, calendar)
                tally.days = tally.days.filter { $0.key > cut }        // "yyyy-MM-dd" sorts by date
            }
            tallies[name] = tally
            if since == nil { since = now }
        }

        public func numbers(of name: String, at now: Date, calendar: Calendar = .current) -> Numbers {
            guard let tally = tallies[name] else { return Numbers() }
            let todayKey = Hunts.day(now, calendar)
            var n = Numbers(all: tally.all)
            n.today = tally.days[todayKey] ?? 0
            if let y = calendar.date(byAdding: .day, value: -1, to: now) { n.yesterday = tally.days[Hunts.day(y, calendar)] ?? 0 }
            n.bestBefore = tally.days.filter { $0.key != todayKey }.values.max() ?? 0
            if let week = calendar.dateInterval(of: .weekOfYear, for: now) {
                var day = week.start
                while day < now, Hunts.day(day, calendar) != todayKey {
                    n.week += tally.days[Hunts.day(day, calendar)] ?? 0
                    n.daysBeforeToday += 1
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    day = next
                }
            }
            n.week += n.today
            return n
        }

        /// Everyone's together.
        public func total(at now: Date, calendar: Calendar = .current) -> Numbers {
            tallies.keys.reduce(into: Numbers()) { sum, name in
                let n = numbers(of: name, at: now, calendar: calendar)
                sum.today += n.today; sum.yesterday += n.yesterday; sum.week += n.week; sum.all += n.all
            }
        }

        /// Start over: one character's count, or everyone's.
        public mutating func reset(_ name: String? = nil) {
            if let name { tallies[name] = nil } else { self = Book() }
            if tallies.isEmpty { since = nil }
        }
    }

    /// `hunts.json` beside the chats and the bonds.
    public struct Store: Sendable {
        public let directory: URL
        public init(directory: URL) { self.directory = directory }
        public var file: URL { directory.appendingPathComponent("hunts.json") }

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

    /// "2026-10-06": the day `date` falls on in `calendar`, which sorts as the dates do.
    public static func day(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: When it is worth saying

    /// Today's counts a creature remarks on as it reaches them.
    public static let dayMilestones = [10, 25, 50, 100, 200, 300, 500]
    /// All-time counts likewise.
    public static let allMilestones = [100, 250, 500, 1000, 2500, 5000, 10_000]

    /// The hunt that just made these numbers is one to remark on: a round number
    /// today or in all, or the first hunt that makes today a record (over a best
    /// day of at least five).
    public static func isMilestone(_ n: Numbers) -> Bool {
        dayMilestones.contains(n.today) || allMilestones.contains(n.all) || (n.bestBefore >= 5 && n.today == n.bestBefore + 1)
    }

    /// Built-in lines need numbers worth saying: two today at least.
    public static func hasLine(_ n: Numbers) -> Bool { n.today >= 2 }

    /// In the bad mood, hunted at least `after` times today, a creature jumps away
    /// from further off: its flee radius times this.
    public static let waryFactor = 1.35
    public static func isWary(_ n: Numbers, after: Int, mood: CursorMood = .current) -> Bool {
        mood == .bad && n.today >= after
    }

    // MARK: For a model

    /// What `name` knows of its count, for `{situation}`, in the current language
    /// and mood; "" when the cursor has never hunted it. `everyone`: today's count of
    /// each character on screen, to know who is the most hunted.
    public static func sentence(for name: String, _ n: Numbers, everyone: [String: Int] = [:], mood: CursorMood = .current) -> String {
        guard n.all > 0 else { return "" }
        func times(_ k: Int) -> String { trCount(k, "time", "times") }
        var parts = [tr("Today the user's cursor has chased or picked up %@ %@ (yesterday %@), %@ this week and %@ in all.",
                        name, times(n.today), times(n.yesterday), times(n.week), times(n.all))]
        if n.today == 0 {
            parts.append(tr("Today has been quiet so far."))
        } else {
            if n.today > n.yesterday { parts.append(tr("That is more than yesterday already.")) }
            else if n.today < n.yesterday { parts.append(tr("That is fewer than yesterday.")) }
            if let average = n.weekAverageBefore, average >= 1, Double(n.today) >= 2 * average {
                parts.append(tr("Earlier days this week averaged %d.", Int(average.rounded())))
            }
            if n.bestBefore >= 5, n.today > n.bestBefore { parts.append(tr("It is %@'s most hunted day on record.", name)) }
            let others = everyone.filter { $0.key != name }
            if !others.isEmpty, n.today > others.values.max() ?? 0 { parts.append(tr("%@ is the most hunted of everyone on screen today.", name)) }
        }
        switch mood {
        case .good: parts.append(tr("%@ keeps this score proudly, like a game being won.", name))
        case .neutral: parts.append(tr("%@ knows these numbers and is matter-of-fact about them.", name))
        case .bad: parts.append(tr("%@ keeps it as a tally of grievances.", name))
        }
        parts.append(tr("%@ may bring the numbers up, or compare them, if it fits.", name))
        return parts.joined(separator: " ")
    }

    // MARK: Built-in lines

    /// A built-in line about the count, by `name` in its own voice and the current
    /// mood and language: `{today}`, `{week}` and `{all}` filled in.
    public static func line(by name: String, _ n: Numbers, mood: CursorMood = .current, using rng: inout some RandomNumberGenerator) -> String {
        let pool = lineSets(for: mood)()[name] ?? anyones(for: mood)()
        return Banter.render(pool.randomElement(using: &rng)!, ["today": "\(n.today)", "week": "\(n.week)", "all": "\(n.all)"])
    }

    public static func lineSets(for mood: CursorMood) -> Translated<[String: [String]]> {
        switch mood {
        case .good: Translated(english: englishGoodLines, [.russian: russianGoodLines])
        case .neutral: Translated(english: englishNeutralLines, [.russian: russianNeutralLines])
        case .bad: Translated(english: englishBadLines, [.russian: russianBadLines])
        }
    }

    public static func anyones(for mood: CursorMood) -> Translated<[String]> {
        switch mood {
        case .good: Translated(english: englishGoodAnyone, [.russian: russianGoodAnyone])
        case .neutral: Translated(english: englishNeutralAnyone, [.russian: russianNeutralAnyone])
        case .bad: Translated(english: englishBadAnyone, [.russian: russianBadAnyone])
        }
    }
}

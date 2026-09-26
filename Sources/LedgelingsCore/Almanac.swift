import Foundation

/// What the creatures know of the world outside the screen: the time of day,
/// the date, and the holidays of the faiths the user ticked. Pure date work
/// on the Mac's own calendars (Gregorian, Hebrew, Islamic Umm al-Qura), so it
/// needs no network and is testable with a fixed date.
///
/// Holidays are counted by the civil day: a Jewish or Muslim holiday that
/// begins at sundown is "today" from the morning after, and "begins this
/// evening" the evening before. Islamic dates follow the Umm al-Qura
/// calendar; where the new moon is sighted locally a date can fall a day
/// apart.
public enum Almanac {
    public enum Faith: String, CaseIterable, Codable, Sendable {
        case jewish, christian, muslim

        public var title: String {
            switch self {
            case .jewish: "Jewish"
            case .christian: "Christian"
            case .muslim: "Muslim"
            }
        }
    }

    /// What the app lets the creatures know.
    public struct Awareness: Equatable, Sendable {
        public var timeOfDay: Bool
        public var date: Bool
        public var faiths: Set<Faith>
        /// Days before a holiday that it starts being mentioned; 0 = only on the day.
        public var lookAhead: Int

        public init(timeOfDay: Bool = true, date: Bool = true, faiths: Set<Faith> = Set(Faith.allCases), lookAhead: Int = 3) {
            self.timeOfDay = timeOfDay; self.date = date; self.faiths = faiths; self.lookAhead = max(0, lookAhead)
        }
    }

    /// A holiday happening on a given day: which day of it, out of how many.
    public struct Holiday: Equatable, Sendable {
        public var name: String
        public var faith: Faith
        public var day: Int
        public var length: Int
        public init(name: String, faith: Faith, day: Int = 1, length: Int = 1) {
            self.name = name; self.faith = faith; self.day = day; self.length = length
        }
    }

    /// A holiday still to come: `days` from today (1 = tomorrow).
    public struct Upcoming: Equatable, Sendable {
        public var name: String
        public var faith: Faith
        public var days: Int
    }

    // MARK: The sentence for the prompt

    /// One or two sentences for `{situation}`, or "" when nothing is switched on.
    /// "For the person at this computer it is Saturday, 26 September 2026, late
    /// evening (22:40). Today is day 1 of Sukkot, a Jewish holiday."
    public static func sentence(at now: Date, _ aware: Awareness, calendar: Calendar = .current) -> String {
        var parts: [String] = []
        let clock = timePhrase(at: now, calendar: calendar)
        switch (aware.date, aware.timeOfDay) {
        case (true, true): parts.append("For the person at this computer it is \(datePhrase(at: now, calendar: calendar)), \(clock).")
        case (true, false): parts.append("For the person at this computer it is \(datePhrase(at: now, calendar: calendar)).")
        case (false, true): parts.append("For the person at this computer it is \(clock).")
        case (false, false): break
        }
        if !aware.faiths.isEmpty {
            let hour = calendar.component(.hour, from: now)
            for h in holidays(on: now, faiths: aware.faiths, calendar: calendar) {
                let what = "a \(h.faith.title) holiday"
                parts.append(h.length > 1 ? "Today is day \(h.day) of \(h.name), \(what)." : "Today is \(h.name), \(what).")
            }
            for u in upcoming(from: now, within: aware.lookAhead, faiths: aware.faiths, calendar: calendar) {
                let what = "a \(u.faith.title) holiday"
                if u.days == 1, u.faith != .christian, hour >= 17 {
                    parts.append("\(u.name), \(what), begins this evening.")
                } else if u.days == 1 {
                    parts.append("Tomorrow is \(u.name), \(what).")
                } else {
                    parts.append("\(u.name), \(what), is in \(u.days) days.")
                }
            }
        }
        return parts.joined(separator: " ")
    }

    /// "Saturday, 26 September 2026".
    public static func datePhrase(at now: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = calendar.timeZone
        f.dateFormat = "EEEE, d MMMM yyyy"
        return f.string(from: now)
    }

    /// "late evening (22:40)".
    public static func timePhrase(at now: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: now), minute = calendar.component(.minute, from: now)
        return "\(partOfDay(hour: hour)) (\(String(format: "%02d:%02d", hour, minute)))"
    }

    /// The part of the day an hour falls in, in words.
    public static func partOfDay(hour: Int) -> String {
        switch hour {
        case 5..<8: "early morning"
        case 8..<12: "morning"
        case 12..<14: "midday"
        case 14..<17: "afternoon"
        case 17..<21: "evening"
        case 21..<24: "late evening"
        default: "the middle of the night"
        }
    }

    // MARK: Holidays

    /// Everything the ticked faiths celebrate on the civil day of `date`.
    public static func holidays(on date: Date, faiths: Set<Faith>, calendar: Calendar = .current) -> [Holiday] {
        let chosen = feasts.filter { faiths.contains($0.faith) }
        guard let longest = chosen.map(\.length).max() else { return [] }
        // The day and the ones before it, each worked out once: days[k] is k days ago.
        let days = (0..<longest).map { k in shift(date, by: -k, calendar).map { Day($0, calendar) } }
        var found: [Holiday] = []
        for feast in chosen {
            guard let ago = (0..<feast.length).first(where: { days[$0].map(feast.starts) ?? false }) else { continue }
            if ago > 0, let still = feast.stillOn, let today = days[0], !still(today) { continue }
            found.append(Holiday(name: feast.name, faith: feast.faith, day: ago + 1, length: feast.length))
        }
        return found
    }

    /// Holidays starting in the next `days` days (tomorrow is 1), nearest first,
    /// leaving out any already under way today.
    public static func upcoming(from date: Date, within days: Int, faiths: Set<Faith>, calendar: Calendar = .current) -> [Upcoming] {
        guard days > 0 else { return [] }
        let today = Set(holidays(on: date, faiths: faiths, calendar: calendar).map(\.name))
        var found: [Upcoming] = []
        for ahead in 1...days {
            guard let later = shift(date, by: ahead, calendar) else { continue }
            let day = Day(later, calendar)
            for feast in feasts where faiths.contains(feast.faith) && feast.starts(day)
                && !today.contains(feast.name) && !found.contains(where: { $0.name == feast.name }) {
                found.append(Upcoming(name: feast.name, faith: feast.faith, days: ahead))
            }
        }
        return found
    }

    /// The first holiday name for today, for a built-in line's `{holiday}`.
    public static func today(_ date: Date, faiths: Set<Faith>, calendar: Calendar = .current) -> String? {
        holidays(on: date, faiths: faiths, calendar: calendar).first?.name
    }

    private static func shift(_ date: Date, by days: Int, _ calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: days, to: date)
    }

    /// One civil day seen through every calendar a holiday is counted in.
    struct Day: Sendable {
        var weekday: Int                            // 1 = Sunday … 7 = Saturday
        var civil: (month: Int, day: Int)
        var hebrew: (month: Int, day: Int)          // 1 Tishrei … 13 Elul; 6 is Adar I, 7 Adar (Adar II)
        var islamic: (month: Int, day: Int)         // 1 Muharram … 12 Dhu al-Hijjah
        var fromEaster: Int                         // days after Western Easter this year (negative before)
        var fromOrthodoxEaster: Int

        init(_ date: Date, _ calendar: Calendar) {
            func parts(_ id: Calendar.Identifier) -> DateComponents {
                var c = Calendar(identifier: id); c.timeZone = calendar.timeZone
                return c.dateComponents([.year, .month, .day, .weekday], from: date)
            }
            let g = parts(.gregorian), h = parts(.hebrew), i = parts(.islamicUmmAlQura)
            weekday = g.weekday ?? 1
            civil = (g.month ?? 1, g.day ?? 1)
            hebrew = (h.month ?? 1, h.day ?? 1)
            islamic = (i.month ?? 1, i.day ?? 1)
            let year = g.year ?? 2000
            let ordinal = Almanac.dayOfYear(year, civil.month, civil.day)
            let e = Almanac.westernEaster(year), o = Almanac.orthodoxEaster(year)
            fromEaster = ordinal - Almanac.dayOfYear(year, e.month, e.day)
            fromOrthodoxEaster = ordinal - Almanac.dayOfYear(year, o.month, o.day)
        }
    }

    struct Feast: Sendable {
        var name: String
        var faith: Faith
        var length = 1
        var starts: @Sendable (Day) -> Bool
        /// For a holiday whose length varies (a month of Ramadan): still going on this day?
        var stillOn: (@Sendable (Day) -> Bool)? = nil
    }

    private static func hebrew(_ name: String, _ month: Int, _ day: Int, length: Int = 1) -> Feast {
        Feast(name: name, faith: .jewish, length: length) { $0.hebrew == (month, day) }
    }
    private static func islamic(_ name: String, _ month: Int, _ day: Int, length: Int = 1) -> Feast {
        Feast(name: name, faith: .muslim, length: length) { $0.islamic == (month, day) }
    }
    private static func civil(_ name: String, _ month: Int, _ day: Int) -> Feast {
        Feast(name: name, faith: .christian) { $0.civil == (month, day) }
    }
    private static func easter(_ name: String, _ offset: Int) -> Feast {
        Feast(name: name, faith: .christian) { $0.fromEaster == offset }
    }

    static let feasts: [Feast] = [
        hebrew("Rosh Hashanah", 1, 1, length: 2),
        hebrew("Yom Kippur", 1, 10),
        hebrew("Sukkot", 1, 15, length: 7),
        hebrew("Simchat Torah", 1, 22),
        hebrew("Hanukkah", 3, 25, length: 8),
        hebrew("Tu BiShvat", 5, 15),
        hebrew("Purim", 7, 14),
        hebrew("Passover", 8, 15, length: 7),
        hebrew("Lag BaOmer", 9, 18),
        hebrew("Shavuot", 10, 6),
        // The fast of 9 Av moves to Sunday when the 9th is a Saturday.
        Feast(name: "Tisha B'Av", faith: .jewish) {
            ($0.hebrew == (12, 9) && $0.weekday != 7) || ($0.hebrew == (12, 10) && $0.weekday == 1)
        },

        civil("Epiphany", 1, 6),
        civil("Orthodox Christmas", 1, 7),
        easter("Ash Wednesday", -46),
        easter("Palm Sunday", -7),
        easter("Good Friday", -2),
        easter("Easter", 0),
        Feast(name: "Orthodox Easter", faith: .christian) { $0.fromOrthodoxEaster == 0 && $0.fromEaster != 0 },
        easter("Ascension Day", 39),
        easter("Pentecost", 49),
        civil("All Saints' Day", 11, 1),
        civil("Christmas Eve", 12, 24),
        civil("Christmas", 12, 25),

        islamic("Islamic New Year", 1, 1),
        islamic("Ashura", 1, 10),
        islamic("the Prophet's Birthday (Mawlid)", 3, 12),
        islamic("Isra and Mi'raj", 7, 27),
        Feast(name: "Ramadan", faith: .muslim, length: 30, starts: { $0.islamic == (9, 1) }, stillOn: { $0.islamic.month == 9 }),
        islamic("Laylat al-Qadr", 9, 27),
        islamic("Eid al-Fitr", 10, 1, length: 3),
        islamic("the Day of Arafah", 12, 9),
        islamic("Eid al-Adha", 12, 10, length: 4),
    ]

    // MARK: Easter

    /// Western Easter Sunday (Gregorian computus, the anonymous algorithm).
    public static func westernEaster(_ year: Int) -> (month: Int, day: Int) {
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        return (month, (h + l - 7 * m + 114) % 31 + 1)
    }

    /// Orthodox Easter Sunday, as a Gregorian date (Julian computus plus the
    /// calendars' gap, 13 days from 1900 to 2099).
    public static func orthodoxEaster(_ year: Int) -> (month: Int, day: Int) {
        let a = year % 4, b = year % 7, c = year % 19
        let d = (19 * c + 15) % 30, e = (2 * a + 4 * b - d + 34) % 7
        let month = (d + e + 114) / 31, day = (d + e + 114) % 31 + 1
        let julian = dayOfYear(year, month, day) + (year / 100 - year / 400 - 2)
        return fromDayOfYear(year, julian)
    }

    static func dayOfYear(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return lengths.prefix(month - 1).reduce(0, +) + day
    }

    static func fromDayOfYear(_ year: Int, _ ordinal: Int) -> (month: Int, day: Int) {
        var left = ordinal, month = 1
        while left > dayOfYear(year, month + 1, 1) - 1, month < 12 { month += 1 }
        left -= dayOfYear(year, month, 1) - 1
        return (month, left)
    }
}

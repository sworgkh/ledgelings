import Foundation
import Testing
@testable import LedgelingsCore

/// The cursor's hunts: counted per character by the user's calendar day and
/// week, kept on disk, reset, and known to the creatures in every mood and language.
@Suite struct HuntsTests {
    /// Monday-first, like most of Europe; tests that need Sunday-first say so.
    static func calendar(firstWeekday: Int = 2) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        c.firstWeekday = firstWeekday
        return c
    }

    /// 2026-10-06 is a Tuesday.
    static func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10, calendar: Calendar = calendar()) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func itCountsTodayYesterdayTheWeekAndInAll() {
        let cal = Self.calendar()
        var book = Hunts.Book()
        for _ in 0..<4 { book.count("Blocky", at: Self.at(4, 12), calendar: cal) }     // Sunday: last week
        for _ in 0..<2 { book.count("Blocky", at: Self.at(5, 9), calendar: cal) }      // Monday
        for _ in 0..<3 { book.count("Blocky", at: Self.at(6, 10), calendar: cal) }     // Tuesday
        book.count("Zed", at: Self.at(6, 11), calendar: cal)
        let n = book.numbers(of: "Blocky", at: Self.at(6, 18), calendar: cal)
        #expect(n.today == 3)
        #expect(n.yesterday == 2)
        #expect(n.week == 5, "Monday and Tuesday; Sunday was last week")
        #expect(n.all == 9)
        #expect(n.bestBefore == 4)
        #expect(n.daysBeforeToday == 1)
        let total = book.total(at: Self.at(6, 18), calendar: cal)
        #expect(total.today == 4 && total.week == 6 && total.all == 10)
        #expect(book.numbers(of: "Nobody", at: Self.at(6, 18), calendar: cal) == Hunts.Numbers())
    }

    @Test func aNewDayStartsAtTheUsersMidnight() {
        let cal = Self.calendar()
        var book = Hunts.Book()
        book.count("Pip", at: Self.at(6, 23, 59), calendar: cal)
        book.count("Pip", at: Self.at(7, 0, 1), calendar: cal)
        let n = book.numbers(of: "Pip", at: Self.at(7, 0, 2), calendar: cal)
        #expect(n.today == 1 && n.yesterday == 1 && n.week == 2 && n.all == 2)
        let nextDay = book.numbers(of: "Pip", at: Self.at(8, 12), calendar: cal)
        #expect(nextDay.today == 0 && nextDay.yesterday == 1 && nextDay.week == 2)
    }

    @Test func theWeekStartsWhereTheLocaleStartsIt() {
        var book = Hunts.Book()
        let sunday = Self.calendar(firstWeekday: 1), monday = Self.calendar(firstWeekday: 2)
        book.count("Dot", at: Self.at(4, 12), calendar: sunday)        // Sunday the 4th
        let tuesday = Self.at(6, 12)
        #expect(book.numbers(of: "Dot", at: tuesday, calendar: sunday).week == 1, "a Sunday-first week holds the 4th")
        #expect(book.numbers(of: "Dot", at: tuesday, calendar: monday).week == 0, "a Monday-first week started on the 5th")
        // A new week starts over; the count in all does not.
        let nextMonday = Self.at(12, 9)
        #expect(book.numbers(of: "Dot", at: nextMonday, calendar: monday).week == 0)
        #expect(book.numbers(of: "Dot", at: nextMonday, calendar: monday).all == 1)
    }

    @Test func oldDaysAreLetGoButTheCountInAllStays() {
        let cal = Self.calendar()
        var book = Hunts.Book()
        let start = Self.at(1, 12, month: 1)
        for d in 0..<200 { book.count("Ruth", at: cal.date(byAdding: .day, value: d, to: start)!, calendar: cal) }
        #expect(book.tallies["Ruth"]!.days.count <= Hunts.daysKept + 1)
        #expect(book.tallies["Ruth"]!.all == 200)
    }

    @Test func itSurvivesARelaunchAndResets() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-hunts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let cal = Self.calendar(), now = Self.at(6, 12)
        var book = Hunts.Book()
        book.count("Blocky", at: now, calendar: cal); book.count("Blocky", at: now, calendar: cal); book.count("Pip", at: now, calendar: cal)
        try Hunts.Store(directory: dir).save(book)
        var loaded = Hunts.Store(directory: dir).load()
        #expect(loaded == book)
        #expect(loaded.since != nil)
        loaded.reset("Blocky")
        #expect(loaded.tallies["Blocky"] == nil && loaded.tallies["Pip"]?.all == 1 && loaded.since != nil)
        loaded.reset()
        #expect(loaded == Hunts.Book(), "reset all forgets since when, too")
        #expect(Hunts.Store(directory: dir.appendingPathComponent("none")).load() == Hunts.Book())
    }

    @Test func milestonesAndRecords() {
        #expect(Hunts.isMilestone(Hunts.Numbers(today: 10, all: 40)))
        #expect(Hunts.isMilestone(Hunts.Numbers(today: 3, all: 100)))
        #expect(Hunts.isMilestone(Hunts.Numbers(today: 8, all: 60, bestBefore: 7)), "the first hunt past the best day")
        #expect(!Hunts.isMilestone(Hunts.Numbers(today: 9, all: 60, bestBefore: 7)), "only the first")
        #expect(!Hunts.isMilestone(Hunts.Numbers(today: 4, all: 60, bestBefore: 3)), "a best day of three is no record")
        #expect(!Hunts.isMilestone(Hunts.Numbers(today: 11, all: 61)))
        #expect(Hunts.isWary(Hunts.Numbers(today: 20), after: 20, mood: .bad))
        #expect(!Hunts.isWary(Hunts.Numbers(today: 19), after: 20, mood: .bad))
        #expect(!Hunts.isWary(Hunts.Numbers(today: 50), after: 20, mood: .good), "a playmate is not wary")
        #expect(!Hunts.isWary(Hunts.Numbers(today: 50), after: 20, mood: .neutral))
    }

    @Test func thePromptCarriesTheNumbersAndTheMood() {
        let n = Hunts.Numbers(today: 7, yesterday: 3, week: 10, all: 412, bestBefore: 6, daysBeforeToday: 1)
        Language.$override.withValue(.english) {
            let bad = Hunts.sentence(for: "Blocky", n, everyone: ["Blocky": 7, "Zed": 2], mood: .bad)
            #expect(bad.contains("7 times") && bad.contains("yesterday 3 times") && bad.contains("10 times this week") && bad.contains("412 times in all"))
            #expect(bad.contains("more than yesterday"))
            #expect(bad.contains("most hunted day on record"))
            #expect(bad.contains("Blocky is the most hunted of everyone on screen"))
            #expect(bad.contains("grievances"))
            #expect(bad.contains("Earlier days this week averaged 3."))
            #expect(Hunts.sentence(for: "Blocky", n, mood: .good).contains("proudly"))
            #expect(Hunts.sentence(for: "Blocky", n, mood: .neutral).contains("matter-of-fact"))
            #expect(!Hunts.sentence(for: "Blocky", n, everyone: ["Blocky": 7, "Zed": 9]).contains("most hunted of everyone"))
            #expect(Hunts.sentence(for: "Blocky", Hunts.Numbers(yesterday: 2, week: 2, all: 5)).contains("quiet so far"))
            #expect(Hunts.sentence(for: "Blocky", Hunts.Numbers()) == "", "never hunted, nothing to say")
            #expect(Hunts.sentence(for: "Blocky", Hunts.Numbers(today: 1, all: 1)).contains("1 time (yesterday 0 times)"))
        }
        Language.$override.withValue(.russian) {
            let ru = Hunts.sentence(for: "Blocky", n, mood: .bad)
            #expect(ru.contains("сегодня 7 раз") && ru.contains("вчера 3 раза") && ru.contains("всего 412 раз"))
            #expect(ru.contains("обидам"))
            #expect(Hunts.sentence(for: "Blocky", n, mood: .good).contains("гордится"))
        }
    }

    /// The characters the app ships, from the complaints: every one has its own count lines.
    static let shippedNames = Set(Complaints.englishLines.keys)

    @Test func everyCharacterSaysItsCountInEveryMoodAndLanguage() {
        let allowed: Set<String> = ["today", "week", "all"]
        for mood in CursorMood.allCases {
            for l in Language.allCases {
                let sets = Hunts.lineSets(for: mood)(l)
                #expect(Set(sets.keys) == Self.shippedNames, "\(mood) \(l.code): \(Self.shippedNames.symmetricDifference(sets.keys))")
                let all = sets.values.flatMap { $0 } + Hunts.anyones(for: mood)(l)
                #expect(!Hunts.anyones(for: mood)(l).isEmpty)
                for line in all {
                    let used = Set(line.matches(of: /\{(\w+)\}/).map { String($0.1) })
                    #expect(!used.isEmpty && used.isSubset(of: allowed), "\(mood) \(l.code): \(line)")
                }
                if l != .english {
                    #expect(sets != Hunts.lineSets(for: mood)(.english), "\(mood) \(l.code) is its own text")
                }
            }
            for name in Self.shippedNames {
                #expect(Hunts.lineSets(for: mood)(.english)[name]!.count == Hunts.lineSets(for: mood)(.russian)[name]!.count, "\(mood) \(name): line for line")
            }
        }
        // Each mood its own words.
        #expect(Hunts.englishBadLines["Unit 7"] != Hunts.englishGoodLines["Unit 7"])
        #expect(Hunts.englishGoodLines["Unit 7"] != Hunts.englishNeutralLines["Unit 7"])
    }

    @Test func aLineIsSaidWithTheNumbersFilledIn() {
        var rng = SystemRandomNumberGenerator()
        let n = Hunts.Numbers(today: 7, week: 31, all: 412)
        for mood in CursorMood.allCases {
            for name in ["Unit 7", "Somebody New"] {
                let line = Language.$override.withValue(.english) { Hunts.line(by: name, n, mood: mood, using: &rng) }
                #expect(!line.contains("{") && (line.contains("7") || line.contains("31") || line.contains("412")), "\(mood) \(name): \(line)")
            }
        }
        #expect(!Hunts.hasLine(Hunts.Numbers(today: 1, all: 50)), "one is no number to boast or grumble about")
        #expect(Hunts.hasLine(Hunts.Numbers(today: 2, all: 2)))
    }
}

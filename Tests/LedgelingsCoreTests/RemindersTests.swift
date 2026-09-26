import Foundation
import Testing
@testable import LedgelingsCore

struct RemindersTests {
    /// Jerusalem time: a real calendar with a weekend, fixed so the tests do not depend on this Mac.
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        return c
    }()
    static func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func aOneOffIsDueFromItsTimeAndFinishedOnceSent() {
        var r = Reminders.Reminder(text: "Call mom", time: Self.at(26, 14, 30))
        #expect(!r.isDue(at: Self.at(26, 14, 29)))
        #expect(r.isDue(at: Self.at(26, 14, 30)))
        #expect(r.isDue(at: Self.at(28, 9)), "missed while the Mac was off: still delivered, late")
        r.markSent(at: Self.at(26, 14, 31), calendar: Self.calendar)
        #expect(r.isFinished && !r.isDue(at: Self.at(30, 9)))
    }

    @Test func aDailyReminderSkipsTheMorningsItMissedAndKeepsItsTime() {
        var r = Reminders.Reminder(text: "Stretch", time: Self.at(20, 9), repeats: .daily)
        // Off for a week: one letter now, the next tomorrow at nine.
        r.markSent(at: Self.at(26, 11), calendar: Self.calendar)
        #expect(!r.isFinished)
        #expect(r.time == Self.at(27, 9))
        #expect(!r.isDue(at: Self.at(26, 23)) && r.isDue(at: Self.at(27, 9)))
    }

    @Test func weekdaysSkipTheWeekendAndWeeklyKeepsItsDay() {
        // 25 September 2026 is a Friday.
        var weekdays = Reminders.Reminder(text: "Stand-up", time: Self.at(25, 10), repeats: .weekdays)
        weekdays.markSent(at: Self.at(25, 10), calendar: Self.calendar)
        #expect(weekdays.time == Self.at(28, 10), "Friday → Monday")
        var weekly = Reminders.Reminder(text: "Bins", time: Self.at(25, 19), repeats: .weekly)
        weekly.markSent(at: Self.at(25, 19, 1), calendar: Self.calendar)
        #expect(weekly.time == Self.at(2, 19, month: 10))
    }

    @Test func theBookListsWaitingOnesFirstAndGivesTheDueOnesOldestFirst() {
        var book = Reminders.Book()
        book.add(.init(text: "later", time: Self.at(27, 9)))
        book.add(.init(text: "second", time: Self.at(26, 10)))
        book.add(.init(text: "first", time: Self.at(26, 8)))
        book.add(.init(text: "done", time: Self.at(25, 8), sentAt: Self.at(25, 8)))
        #expect(book.due(at: Self.at(26, 12)).map(\.text) == ["first", "second"])
        #expect(book.sorted.map(\.text) == ["first", "second", "later", "done"])
        #expect(book.upcoming?.text == "first")
        book.markSent(book.reminders[2].id, at: Self.at(26, 12))
        book.clearFinished()
        #expect(book.reminders.map(\.text) == ["later", "second"])
    }

    @Test func theBookSurvivesARelaunch() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("reminders-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Reminders.Store(directory: dir)
        #expect(store.load() == Reminders.Book())
        var book = Reminders.Book()
        book.add(.init(text: "Water the plant", time: Self.at(26, 18), repeats: .weekly))
        try store.save(book)
        #expect(Reminders.Store(directory: dir).load() == book)
    }

    @Test func everyBuiltInCharacterWritesTheReminderInItsOwnWords() {
        let everyone = Banter.defaultCharacters.map(\.name) + Letters.voices.keys
        var rng = SystemRandomNumberGenerator()
        for name in Set(everyone) {
            let lines = Reminders.notes[name]
            #expect(lines != nil && lines!.count >= 2, "\(name) has its own reminder notes")
            #expect(lines?.allSatisfy { $0.contains("{reminder}") } == true, "\(name) names the reminder")
            #expect(Reminders.note(by: name, reminder: "Stretch", using: &rng).lowercased().contains("stretch"))
        }
        #expect(Reminders.note(by: "Somebody New", reminder: "Stretch", using: &rng).contains("Stretch"))
    }

    @Test func midSentenceTheReminderStartsSmallUnlessItShouts() {
        #expect(Reminders.fill("Well, {reminder}!", reminder: "Call mom") == "Well, call mom!")
        #expect(Reminders.fill("It's time for {reminder}.", reminder: "Stretching") == "It's time for stretching.")
        #expect(Reminders.fill("Well, {reminder}!", reminder: "NASA call") == "Well, NASA call!")
        #expect(Reminders.fill("{reminder}! Now.", reminder: "Call mom") == "Call mom! Now.")
    }

    @Test func thePaperIsDrawnInBlockysRules() {
        let rows = Reminders.paper(width: 40, height: 24)
        #expect(rows.count == 24 && rows.allSatisfy { $0.count == 40 })
        #expect(rows[0][0] == .rim && rows[0][39] == .rim && rows[23][0] == .rim, "a dark rim all round")
        #expect(rows[1][5] == .light && rows[5][1] == .light, "a light line top-left")
        #expect(rows[22][5] == .shade && rows[5][38] == .shade, "a shade line bottom-right")
        #expect(rows[23][39] == nil, "the bottom-right corner is folded down")
        #expect(rows.flatMap { $0 }.contains(.deepShade), "and the flap shows")
        #expect(rows[12][10] == .crease, "the creases of an unfolded plane")
    }
}

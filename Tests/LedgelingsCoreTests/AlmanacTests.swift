import Foundation
import Testing
@testable import LedgelingsCore

@Suite struct AlmanacTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        return c
    }()

    func at(_ y: Int, _ m: Int, _ d: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
    }

    func names(_ y: Int, _ m: Int, _ d: Int, _ faiths: Set<Almanac.Faith> = Set(Almanac.Faith.allCases)) -> [String] {
        Almanac.holidays(on: at(y, m, d), faiths: faiths, calendar: calendar).map(\.name)
    }

    @Test func thePartOfTheDayFollowsTheClock() {
        #expect(Almanac.partOfDay(hour: 3) == "the middle of the night")
        #expect(Almanac.partOfDay(hour: 6) == "early morning")
        #expect(Almanac.partOfDay(hour: 9) == "morning")
        #expect(Almanac.partOfDay(hour: 13) == "midday")
        #expect(Almanac.partOfDay(hour: 15) == "afternoon")
        #expect(Almanac.partOfDay(hour: 19) == "evening")
        #expect(Almanac.partOfDay(hour: 23) == "late evening")
    }

    @Test func theSentenceSaysOnlyWhatIsSwitchedOn() {
        let now = at(2026, 9, 26, 22, 40)
        let none = Almanac.Awareness(timeOfDay: false, date: false, faiths: [])
        #expect(Almanac.sentence(at: now, none, calendar: calendar) == "")
        let clock = Almanac.Awareness(timeOfDay: true, date: false, faiths: [])
        #expect(Almanac.sentence(at: now, clock, calendar: calendar) == "For the person at this computer it is late evening (22:40).")
        let date = Almanac.Awareness(timeOfDay: false, date: true, faiths: [])
        #expect(Almanac.sentence(at: now, date, calendar: calendar) == "For the person at this computer it is Saturday, 26 September 2026.")
        let all = Almanac.sentence(at: now, Almanac.Awareness(), calendar: calendar)
        #expect(all.hasPrefix("For the person at this computer it is Saturday, 26 September 2026, late evening (22:40). Today is day 1 of Sukkot, a Jewish holiday."))
    }

    @Test func jewishHolidaysComeFromTheHebrewCalendar() {
        #expect(names(2026, 9, 12, [.jewish]) == ["Rosh Hashanah"])
        #expect(names(2026, 9, 13, [.jewish]) == ["Rosh Hashanah"])
        #expect(names(2026, 9, 21, [.jewish]) == ["Yom Kippur"])
        #expect(names(2026, 10, 3, [.jewish]) == ["Simchat Torah"])
        #expect(names(2026, 12, 5, [.jewish]) == ["Hanukkah"])
        #expect(names(2026, 12, 12, [.jewish]) == ["Hanukkah"])         // the 8th day, in Tevet
        #expect(names(2026, 12, 13, [.jewish]).isEmpty)
        #expect(names(2026, 3, 3, [.jewish]) == ["Purim"])
        #expect(names(2027, 3, 23, [.jewish]) == ["Purim"])             // a leap year: Adar II
        #expect(names(2027, 2, 21, [.jewish]).isEmpty)                  // 14 Adar I is not Purim
        #expect(names(2026, 4, 2, [.jewish]) == ["Passover"])
        #expect(names(2026, 5, 22, [.jewish]) == ["Shavuot"])
        #expect(names(2026, 7, 23, [.jewish]) == ["Tisha B'Av"])
        // 9 Av 5785 was a Sunday already; 9 Av 5782 (6 Aug 2022) a Saturday, kept on the 7th.
        #expect(names(2022, 8, 6, [.jewish]).isEmpty)
        #expect(names(2022, 8, 7, [.jewish]) == ["Tisha B'Av"])
    }

    @Test func aHolidayOfSeveralDaysSaysWhichDay() {
        let sukkot = Almanac.holidays(on: at(2026, 9, 28), faiths: [.jewish], calendar: calendar)
        #expect(sukkot == [Almanac.Holiday(name: "Sukkot", faith: .jewish, day: 3, length: 7)])
    }

    @Test func christianHolidaysIncludeBothEasters() {
        #expect(Almanac.westernEaster(2026) == (4, 5))
        #expect(Almanac.westernEaster(2025) == (4, 20))
        #expect(Almanac.westernEaster(2027) == (3, 28))
        #expect(Almanac.orthodoxEaster(2026) == (4, 12))
        #expect(Almanac.orthodoxEaster(2027) == (5, 2))
        #expect(names(2026, 4, 5, [.christian]) == ["Easter"])
        #expect(names(2026, 4, 3, [.christian]) == ["Good Friday"])
        #expect(names(2026, 4, 12, [.christian]) == ["Orthodox Easter"])
        #expect(names(2025, 4, 20, [.christian]) == ["Easter"])         // both on one day: said once
        #expect(names(2026, 2, 18, [.christian]) == ["Ash Wednesday"])
        #expect(names(2026, 12, 25, [.christian]) == ["Christmas"])
        #expect(names(2027, 1, 7, [.christian]) == ["Orthodox Christmas"])
    }

    @Test func muslimHolidaysComeFromTheIslamicCalendar() {
        #expect(names(2026, 2, 18, [.muslim]) == ["Ramadan"])
        let tenth = Almanac.holidays(on: at(2026, 2, 27), faiths: [.muslim], calendar: calendar)
        #expect(tenth.first == Almanac.Holiday(name: "Ramadan", faith: .muslim, day: 10, length: 30))
        #expect(names(2026, 3, 20, [.muslim]) == ["Eid al-Fitr"])       // Ramadan is over
        #expect(names(2026, 5, 26, [.muslim]) == ["the Day of Arafah"])
        #expect(names(2026, 5, 27, [.muslim]) == ["Eid al-Adha"])
    }

    @Test func onlyTheTickedFaithsCount() {
        #expect(names(2026, 2, 18, []).isEmpty)
        #expect(Set(names(2026, 2, 18)) == ["Ramadan", "Ash Wednesday"])
    }

    @Test func holidaysAheadAreMentionedWithinTheLookAhead() {
        let before = at(2026, 12, 2, 10)
        let soon = Almanac.upcoming(from: before, within: 3, faiths: [.jewish], calendar: calendar)
        #expect(soon == [Almanac.Upcoming(name: "Hanukkah", faith: .jewish, days: 3)])
        #expect(Almanac.upcoming(from: before, within: 2, faiths: [.jewish], calendar: calendar).isEmpty)
        #expect(Almanac.upcoming(from: before, within: 0, faiths: [.jewish], calendar: calendar).isEmpty)
        let aware = Almanac.Awareness(timeOfDay: false, date: false, faiths: [.jewish], lookAhead: 3)
        #expect(Almanac.sentence(at: before, aware, calendar: calendar) == "Hanukkah, a Jewish holiday, is in 3 days.")
        // The evening before, a Jewish holiday has already begun; a Christian one is still tomorrow.
        #expect(Almanac.sentence(at: at(2026, 12, 4, 19), aware, calendar: calendar) == "Hanukkah, a Jewish holiday, begins this evening.")
        #expect(Almanac.sentence(at: at(2026, 12, 4, 9), aware, calendar: calendar) == "Tomorrow is Hanukkah, a Jewish holiday.")
        let christian = Almanac.Awareness(timeOfDay: false, date: false, faiths: [.christian], lookAhead: 1)
        #expect(Almanac.sentence(at: at(2026, 12, 23, 20), christian, calendar: calendar) == "Tomorrow is Christmas Eve, a Christian holiday.")
    }

    @Test func aHolidayUnderWayIsNotAlsoUpcoming() {
        let during = Almanac.upcoming(from: at(2026, 9, 26), within: 7, faiths: [.jewish], calendar: calendar)
        #expect(during.map(\.name) == ["Simchat Torah"])
    }
}

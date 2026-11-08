import Foundation
import Testing
@testable import LedgelingsCore

/// The gang's roster: who is new, who left, who came back, nothing on the first
/// look, and a sleeper or a move to another monitor is no departure; the news
/// and how often it comes up; every character's lines about it.
@Suite struct GangTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let kinds = ["Blocky": "a blocky creature", "Boo": "a little ghost", "Pip": "a blocky creature"]

    func present(_ names: String...) -> [String: String] {
        Dictionary(uniqueKeysWithValues: names.map { ($0, kinds[$0] ?? "a creature") })
    }

    @Test func theFirstLookKnowsEveryoneOnScreenAndEveryoneTheBondsRemember() {
        var r = Gang.Roster()
        #expect(r.observe(present("Blocky", "Boo"), now: t0, known: ["Blocky", "Mossy"]).isEmpty)
        #expect(r.started == t0 && r.members.count == 3 && r.events.isEmpty)
        #expect(r.members["Mossy"]?.away == t0, "remembered by the bonds, not on screen: gone, quietly")
        // Mossy turning up later is a return with a past, not a newcomer.
        r.observe(present("Blocky", "Boo", "Mossy"), now: t0 + 30)
        let back = r.observe(present("Blocky", "Boo", "Mossy"), now: t0 + 200)
        #expect(back.map(\.kind) == [.returned] && back.first?.name == "Mossy")
    }

    @Test func aNewcomerCountsOnceItHasStayedAndAFlickerIsNobody() {
        var r = Gang.Roster()
        r.observe(present("Blocky", "Boo"), now: t0)
        // The count dragged up and down again within a minute: nobody arrived.
        #expect(r.observe(present("Blocky", "Boo", "Pip"), now: t0 + 30).isEmpty)
        #expect(r.observe(present("Blocky", "Boo"), now: t0 + 60).isEmpty)
        #expect(r.members["Pip"] == nil)
        // This time Pip stays.
        r.observe(present("Blocky", "Boo", "Pip"), now: t0 + 100)
        #expect(r.observe(present("Blocky", "Boo", "Pip"), now: t0 + 160).isEmpty)
        let joined = r.observe(present("Blocky", "Boo", "Pip"), now: t0 + 230)
        #expect(joined == [Gang.Event(kind: .joined, name: "Pip", species: "a blocky creature", time: t0 + 100)])
        #expect(r.observe(present("Blocky", "Boo", "Pip"), now: t0 + 300).isEmpty, "told once")
    }

    @Test func someoneGoneForTwoMinutesHasLeftAndComesBackWithItsPast() {
        var r = Gang.Roster()
        r.observe(present("Blocky", "Boo", "Pip"), now: t0)
        #expect(r.observe(present("Blocky", "Pip"), now: t0 + 60).isEmpty)
        let left = r.observe(present("Blocky", "Pip"), now: t0 + 130)
        #expect(left == [Gang.Event(kind: .left, name: "Boo", species: "a little ghost", time: t0)])
        #expect(r.observe(present("Blocky", "Pip"), now: t0 + 400).isEmpty, "gone is told once")
        // A day later Boo is back, and stays.
        let day = t0 + 86_400
        #expect(r.observe(present("Blocky", "Pip", "Boo"), now: day).isEmpty)
        let back = r.observe(present("Blocky", "Pip", "Boo"), now: day + 120)
        #expect(back == [Gang.Event(kind: .returned, name: "Boo", species: "a little ghost", time: day, awaySince: t0)])
        #expect(r.members["Boo"]?.away == nil)
    }

    @Test func sleepingHidingOrMovingMonitorIsNotLeaving() {
        // Asleep, in the house, parachuting to another monitor: still a creature
        // of the colony, so still in what the roster is shown.
        var r = Gang.Roster()
        r.observe(present("Blocky", "Boo"), now: t0)
        for minute in 1...600 { #expect(r.observe(present("Blocky", "Boo"), now: t0 + Double(minute) * 30).isEmpty) }
        // The app quit overnight with the same gang: nobody left.
        #expect(r.observe(present("Blocky", "Boo"), now: t0 + 3 * 86_400).isEmpty)
    }

    @Test func theNewsIsFreshForTheDaysSetAndDeparturesCanBeLeftOut() {
        var r = Gang.Roster()
        r.observe(present("Blocky", "Boo"), now: t0)
        r.fake(.joined, "Pip", species: "a blocky creature", at: t0)
        r.fake(.left, "Boo", species: "a little ghost", at: t0 + 60)
        #expect(r.fresh(days: 3, now: t0 + 86_400).map(\.name) == ["Pip", "Boo"])
        #expect(r.fresh(days: 3, departures: false, now: t0 + 86_400).map(\.name) == ["Pip"])
        #expect(r.fresh(days: 3, now: t0 + 3 * 86_400 + 120).isEmpty, "gone after three days")
        #expect(r.fresh(days: 7, now: t0 + 3 * 86_400 + 120).count == 2)
        // Only each one's newest event: Boo back again is no longer gone.
        r.fake(.returned, "Boo", species: nil, at: t0 + 3600)
        #expect(r.fresh(days: 3, now: t0 + 7200).map(\.kind) == [.joined, .returned])
        #expect(r.newcomers(days: 3, now: t0 + 7200) == ["Pip"])
        r.forgetNews()
        #expect(r.fresh(days: 3, now: t0 + 7200).isEmpty && r.members.count == 3)
    }

    @Test func theChanceFadesOverTheDays() {
        let e = [Gang.Event(kind: .joined, name: "Pip", time: t0)]
        #expect(Gang.chance(0.4, e, days: 4, now: t0) == 0.4)
        #expect(abs(Gang.chance(0.4, e, days: 4, now: t0 + 2 * 86_400) - 0.2) < 1e-9)
        #expect(Gang.chance(0.4, e, days: 4, now: t0 + 4 * 86_400) == 0)
        #expect(Gang.chance(0.4, [], days: 4, now: t0) == 0)
    }

    @Test func theNewsIsToldFromEachSide() {
        let joined = Gang.Event(kind: .joined, name: "Pip", species: "a blocky creature", time: t0)
        let left = Gang.Event(kind: .left, name: "Boo", species: "a little ghost", time: t0)
        var book = Bonds.Book()
        book.update("Blocky", "Boo") { $0.summary = "rivals for the bottom edge" }
        let blocky = Gang.news([joined, left], speaker: "Blocky", book: book, now: t0)
        #expect(blocky.hasPrefix("News in the gang: Pip, a blocky creature, is new to the gang: arrived today."))
        #expect(blocky.contains("Boo has left the gang (today); nobody has seen Boo since") && blocky.contains("You and Boo: rivals for the bottom edge"))
        #expect(blocky.contains("bring it up in your own way"))
        let pip = Gang.news([joined], speaker: "Pip", now: t0)
        #expect(pip.contains("You are new here: you joined the gang today"))
        let story = Gang.news([joined], speaker: nil, now: t0)
        #expect(story.hasSuffix("It may touch their story."))
        #expect(Gang.news([], speaker: "Blocky", now: t0).isEmpty)
        #expect(Gang.withNews("prompt", "") == "prompt" && Gang.withNews("prompt", "news") == "prompt\nnews")
        Language.$override.withValue(.russian) {
            let ru = Gang.news([joined, left], speaker: "Blocky", book: book, now: t0)
            #expect(ru.hasPrefix("Новости компании: ") && ru.contains("Boo уходит из компании (сегодня), и с тех пор Boo не видно"))
        }
    }

    @Test func everyCharacterHasItsOwnLineInEveryTableInBothLanguages() {
        let names = BedsTests.shipped
        #expect(names.count == 39)
        let tables: [(String, Translated<[String: String]>)] = [("new", Gang.newSets), ("gone", Gang.goneSets),
                                                                 ("back", Gang.backSets), ("arrival", Gang.arrivalSets)]
        for (label, table) in tables {
            for language in Language.allCases {
                let lines = table(language)
                #expect(Set(lines.keys) == Set(names), "\(label) \(language.code)")
                for (name, line) in lines {
                    #expect(!line.isEmpty, "\(label) \(language.code) \(name)")
                    if label != "arrival" { #expect(line.contains("{name}"), "\(label) \(language.code) \(name): who is it about?") }
                    else { #expect(!line.contains("{name}"), "\(label) \(language.code) \(name)") }
                }
                #expect(Set(lines.values).count == lines.count, "\(label) \(language.code): no two say the same")
            }
        }
        for anyone in [Gang.newAnyone, Gang.goneAnyone, Gang.backAnyone] {
            for language in Language.allCases { #expect(!anyone(language).isEmpty && anyone(language).allSatisfy { $0.contains("{name}") }) }
        }
        #expect(Gang.russianNewLines["Blocky"] != Gang.englishNewLines["Blocky"])
    }

    @Test func aLineIsAboutWhoeverItIsAboutInTheSpeakersVoice() {
        var rng = SystemRandomNumberGenerator()
        let pip = Gang.Event(kind: .joined, name: "Pip", time: t0)
        #expect(Gang.line(about: pip, by: "Unit 7", using: &rng) == "New unit detected: Pip. Gang size up by 1.")
        #expect(Gang.line(about: pip, by: "Pip", using: &rng) == Gang.englishArrivalLines["Pip"])
        #expect(Gang.englishNewAnyone.map { $0.replacingOccurrences(of: "{name}", with: "Pip") }
            .contains(Gang.line(about: pip, by: "Somebody Imported", using: &rng)))
        let boo = Gang.Event(kind: .left, name: "Boo", time: t0)
        #expect(Gang.line(about: boo, by: "Unit 7", using: &rng) == "Boo: no signal. Gang size down by 1.")
        let back = Gang.Event(kind: .returned, name: "Boo", time: t0, awaySince: t0 - 86_400)
        #expect(Gang.englishBackSelfAnyone.contains(Gang.line(about: back, by: "Boo", using: &rng)))
    }

    @Test func aFirstMeetingIsAMomentOfTheirStoryline() {
        var book = Bonds.Book()
        book.note("Pip", "Blocky", Bonds.Moment(time: t0, kind: .meet, who: "Pip"))
        let bond = book.bond("Pip", "Blocky")!
        #expect(bond.tally["meet"] == 1 && bond.met == t0)
        #expect(Bonds.describe(bond.moments[0], names: bond.names) == "Pip, new to the gang, met Blocky for the first time")
        #expect(Bonds.tallied(bond.tally) == "1 first meeting")
        var rng = SystemRandomNumberGenerator()
        #expect(Bonds.builtInPlot(bond, now: t0, using: &rng).plot.contains("Pip"))
    }

    @Test func theRosterIsKeptInBondsJsonAndAnOldFileStillLoads() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-gang-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Bonds.Store(directory: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"bonds":{"Blocky & Boo":{"names":["Blocky","Boo"],"together":60}}}"#.utf8).write(to: store.file)
        var book = store.load()
        #expect(book.bonds.count == 1 && book.gang.started == nil, "a file from before the roster")
        book.gang.observe(present("Blocky", "Boo"), now: t0)
        book.gang.fake(.joined, "Pip", species: "a blocky creature", at: t0 + 60)
        try store.save(book)
        #expect(store.load() == book)
    }
}

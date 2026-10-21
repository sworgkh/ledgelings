import Foundation
import Testing
@testable import LedgelingsCore

/// A pair's long-term memory: facts, days, the games record, the block a prompt
/// carries within its budget, a creature's day so far, the diary's answer, and
/// the seed's digest of the chat log.
@Suite struct MemoryTests {
    let day = Date(timeIntervalSince1970: 1_760_950_800)     // 20 Oct 2025, 09:00 UTC

    func game(_ kind: Plays.Kind, at time: Date, winners: [String]?, score: String?, asked: String? = nil, who: String = "Blocky") -> Bonds.Moment {
        Bonds.Moment(time: time, kind: .play, who: who, detail: kind.rawValue, score: score, winners: winners, asked: asked)
    }

    @Test func gamesCountTheirWinnerAndTheirDay() {
        var book = Bonds.Book()
        book.note("Blocky", "Boo", game(.soccer, at: day, winners: ["Boo"], score: "2-3", asked: "Boo"))
        book.note("Blocky", "Boo", game(.soccer, at: day.addingTimeInterval(600), winners: ["Boo", "Blocky"], score: "4-1"))
        book.note("Blocky", "Boo", game(.basketball, at: day.addingTimeInterval(900), winners: [], score: "1-1"))
        book.note("Blocky", "Boo", game(.rope, at: day.addingTimeInterval(950), winners: nil, score: nil))
        let bond = book.bond("Blocky", "Boo")!
        #expect(bond.record == ["soccer|Boo": 1, "basketball|=": 1], "teammates who win together beat nobody")
        #expect(Bonds.recordLine(bond) == "Basketball: 1 draw; Soccer: Boo 1")
        #expect(bond.days.count == 1 && bond.days[0].day == Bonds.dayKey(day) && bond.days[0].counts == ["play": 4])
        #expect(bond.days[0].games.first == "Soccer: won by Boo, 2-3; Boo asked for it")
        #expect(Bonds.lastLost(by: "Blocky", bond) == .soccer && Bonds.lastLost(by: "Boo", bond) == nil)
        #expect(Bonds.describe(bond.moments[0], names: bond.names).hasSuffix("(won by Boo, 2-3; Boo asked for it)"))
    }

    @Test func factsAreDatedDeduplicatedAndCapped() {
        var book = Bonds.Book()
        for (k, text) in ["Boo owes Blocky a sunflower", "boo owes blocky a sunflower", "They share the cache at six", "Blocky guards the garden"].enumerated() {
            book.remember("Blocky", "Boo", text, source: "note", at: day.addingTimeInterval(Double(k)), keep: 2)
        }
        #expect(book.bond("Blocky", "Boo")!.facts.map(\.text) == ["They share the cache at six", "Blocky guards the garden"])
        book.remember("Blocky", "Boo", "anything", source: "note", keep: 0)
        #expect(book.bond("Blocky", "Boo")!.facts.isEmpty, "0 keeps none")
    }

    @Test func theMemoryBlockStaysWithinItsBudgetAndDropsTheStoryFirst() {
        var book = Bonds.Book()
        book.note("Blocky", "Boo", game(.soccer, at: day, winners: ["Boo"], score: "2-3"))
        book.remember("Blocky", "Boo", "Boo owes Blocky a sunflower", source: "note", at: day, keep: 5)
        book.update("Blocky", "Boo") { $0.chronicle = "They met on the bottom edge. They argued about the garden. They made up over tea. They guard the garden together now." }
        let bond = book.bond("Blocky", "Boo")!
        let full = Bonds.memory(bond, speaker: "Blocky", other: "Boo", budget: 400, now: day)
        #expect(full.contains("You and Boo first met on") && full.contains("Your story so far: They met"))
        #expect(full.contains("Games between you: Soccer: Boo 1.") && full.contains("You remember: Boo owes Blocky a sunflower (20 Oct)."))
        #expect(full.hasSuffix("Today together: 1 game; Soccer: won by Boo, 2-3."))
        #expect(full.range(of: "Your story")!.lowerBound < full.range(of: "Today")!.lowerBound, "the story first, today last")
        for budget in [10, 30, 60, 90] {
            let cut = Bonds.memory(bond, speaker: "Blocky", other: "Boo", budget: budget, now: day)
            #expect(Bonds.tokens(cut) <= budget, "\(budget): \(cut)")
        }
        let small = Bonds.memory(bond, speaker: "Blocky", other: "Boo", budget: 30, now: day)
        #expect(small.contains("Today together") && !small.contains("Your story"), "today stays, the story goes")
        #expect(Bonds.memory(bond, speaker: "Blocky", other: "Boo", budget: 0, now: day).isEmpty)
        #expect(Bonds.memory(nil, speaker: "Blocky", other: "Boo", budget: 150).isEmpty)
    }

    @Test func aCreaturesDayIsToldFromItsSideAndAGameOnce() {
        var book = Bonds.Book()
        let soccer = game(.soccer, at: day, winners: ["Boo", "Zed"], score: "2-3")
        book.note("Blocky", "Boo", soccer)
        book.note("Blocky", "Zed", soccer)
        book.note("Blocky", "Boo", Bonds.Moment(time: day.addingTimeInterval(600), kind: .flower, who: "Boo", detail: "poppy"))
        book.note("Blocky", "Zed", Bonds.Moment(time: day.addingTimeInterval(900), kind: .talk, who: "Zed", detail: "Hi"))
        book.note("Blocky", "Zed", Bonds.Moment(time: day.addingTimeInterval(-86_400), kind: .tea, who: "Zed"))
        let told = Bonds.daySoFar(of: "Blocky", in: book, now: day.addingTimeInterval(1000), items: 4)
        #expect(told.hasPrefix("Your day so far: got a poppy from Boo at "))
        #expect(told.contains("played a game of soccer with ") && told.contains("Boo") && told.contains("Zed") && told.contains("(won by Boo, Zed, 2-3)"))
        #expect(!told.contains("tea") && !told.contains("Hi"), "yesterday's tea and the talks are left out")
        #expect(told.components(separatedBy: "a game of soccer").count == 2, "once, not once per pair")
        #expect(Bonds.daySoFar(of: "Blocky", in: book, now: day, items: 0).isEmpty)
    }

    @Test func theDiaryIsReadAndWrittenIn() throws {
        let raw = """
        <think>hmm</think>
        **STORY:** Since 22 Oct they guard the garden together.
        FACT: Boo owes Blocky a sunflower (19 Oct)
        FACT: They meet at the cache at six · Blocky screams if the cursor comes
        DAY: 2025-10-20: soccer, lost 2-3, made up over tea
        DAY: a quiet day
        """
        let diary = try #require(Bonds.parseDiary(raw))
        #expect(diary.story == "Since 22 Oct they guard the garden together.")
        #expect(diary.facts == ["Boo owes Blocky a sunflower (19 Oct)", "They meet at the cache at six", "Blocky screams if the cursor comes"])
        #expect(diary.days == ["2025-10-20": "soccer, lost 2-3, made up over tea", "": "a quiet day"])
        #expect(Bonds.parseDiary("No idea.") == nil)
        var book = Bonds.Book()
        book.note("Blocky", "Boo", Bonds.Moment(time: day, kind: .talk, who: "Boo", detail: "Hi"))
        book.write("Blocky", "Boo", diary, source: "diary", at: day.addingTimeInterval(86_400), words: 5, keep: 2, cost: 0.001)
        let bond = book.bond("Blocky", "Boo")!
        #expect(bond.chronicle == "Since 22 Oct they guard…" || bond.chronicle!.split(separator: " ").count <= 6)
        #expect(bond.facts.map(\.text) == ["They meet at the cache at six", "Blocky screams if the cursor comes"])
        #expect(bond.days.map(\.day) == ["2025-10-20", "2025-10-21"] && bond.days[0].line == "soccer, lost 2-3, made up over tea")
        #expect(bond.days[0].counts == ["talk": 1], "counts stay")
        #expect(bond.diaryAt == day.addingTimeInterval(86_400) && bond.memoryCost == 0.001)
        #expect(book.diaryDue(every: 3600, now: day.addingTimeInterval(90_000)).isEmpty, "nothing new since")
    }

    @Test func theDiaryIsDueForPairsWithSomethingNew() {
        var book = Bonds.Book()
        book.note("A", "B", Bonds.Moment(time: day, kind: .talk, who: "A"))
        book.note("C", "D", Bonds.Moment(time: day, kind: .talk, who: "C"))
        book.note("C", "D", Bonds.Moment(time: day, kind: .tea, who: "D"))
        #expect(book.diaryDue(every: 3600, now: day).map(\.names) == [["C", "D"], ["A", "B"]], "most new first")
        book.wroteMemory("C", "D", at: day, cost: nil)
        book.note("C", "D", Bonds.Moment(time: day.addingTimeInterval(60), kind: .talk, who: "C"))
        #expect(book.diaryDue(every: 3600, now: day.addingTimeInterval(120)).map(\.names) == [["A", "B"]], "written too lately")
        #expect(book.diaryDue(every: 3600, now: day.addingTimeInterval(4000)).count == 2)
    }

    @Test func theCapsAreKept() {
        var book = Bonds.Book()
        for k in 0..<10 { book.note("A", "B", Bonds.Moment(time: day.addingTimeInterval(Double(-k) * 86_400), kind: .talk, who: "A")) }
        for k in 0..<6 { book.remember("A", "B", "fact \(k)", source: "note", keep: 10) }
        book.keepMemory(facts: 3, days: 4, now: day)
        let bond = book.bond("A", "B")!
        #expect(bond.facts.map(\.text) == ["fact 3", "fact 4", "fact 5"] && bond.days.count == 5)
        book.keepMemory(facts: 0, days: 0, now: day)
        #expect(book.bond("A", "B")!.days.isEmpty && book.bond("A", "B")!.facts.isEmpty)
    }

    @Test func anOldBondsFileStillLoads() throws {
        let old = #"{"bonds":{"A & B":{"names":["A","B"],"together":60,"moments":[{"time":"2025-10-20T09:00:00Z","kind":"play","who":"A","detail":"tag"}]}}}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let book = try decoder.decode(Bonds.Book.self, from: Data(old.utf8))
        let bond = try #require(book.bond("A", "B"))
        #expect(bond.facts.isEmpty && bond.days.isEmpty && bond.record.isEmpty && bond.diaryAt == nil)
        #expect(bond.moments[0].winners == nil && bond.moments[0].score == nil)
    }

    @Test func theSeedDigestCountsDaysAndPicksLinesSpreadAcrossThem() {
        func e(_ hours: Double, _ situation: String, _ lines: [(String, String)]) -> ChatLog.Exchange {
            ChatLog.Exchange(time: day.addingTimeInterval(hours * 3600), situation: situation, provider: "p", model: "m",
                             lines: lines.map { ChatLog.Line(speaker: $0.0, text: $0.1) })
        }
        let log = [
            e(0, "Blocky sent Boo a paper plane.", [("Blocky", "The cache at six."), ("Boo", "Fine.")]),
            e(1, "Blocky and Boo have put a little table out on the ceiling and are sitting down to tea together.", [("Blocky", "Once…"), ("Boo", "Ha!")]),
            e(1.1, "Blocky and Boo have put a little table out on the ceiling and are sitting down to tea together.", [("Boo", "And I…"), ("Blocky", "No.")]),
            e(2, "Boo just walked into Blocky and gave Blocky a poppy.", [("Boo", "Here."), ("Blocky", "Hm.")]),
            e(3, "They just walked into each other.", [("Boo", "Boo!"), ("Blocky", "Move.")]),
            e(24, "Boo отправляет Blocky бумажный самолётик.", [("Boo", "Тайник цел."), ("Blocky", "Ладно.")]),
            e(25, "They just walked into each other.", [("Zed", "zzz"), ("Blocky", "Shh.")]),
            e(-500, "They just walked into each other.", [("Boo", "Old."), ("Blocky", "Old.")]),
        ]
        let digest = Bonds.seedDigest(log, "Blocky", "Boo", from: day.addingTimeInterval(-3600), to: day.addingTimeInterval(48 * 3600), lines: 6)
        #expect(digest.exchanges == 6)
        #expect(digest.days[Bonds.dayKey(day)] == ["plane": 1, "tea": 1, "flower": 1, "talk": 1], "two rounds, one tea party")
        #expect(digest.days[Bonds.dayKey(day.addingTimeInterval(86_400))] == ["plane": 1])
        #expect(digest.lines.count == 5 && digest.lines.first?.line.text == "The cache at six." && digest.lines.last?.line.text == "Ладно.")
        #expect(!digest.lines.contains { $0.line.text == "zzz" || $0.line.text == "Old." })
        let values = Bonds.seedValues(Bonds.Bond(names: ["Blocky", "Boo"]), digest, a: ("Blocky", "a box", "grumpy"),
                                      b: ("Boo", "a ghost", "spooky"), days: 14, words: 80, facts: 5)
        #expect(values["digest"]!.contains("1 paper plane") && !values["lines"]!.contains("walked into"), "situations are never sent")
        var book = Bonds.Book()
        book.seedDays("Blocky", "Boo", digest, at: day)
        book.seedDays("Blocky", "Boo", digest, at: day)
        #expect(book.bond("Blocky", "Boo")!.days.first!.counts == ["plane": 1, "tea": 1, "flower": 1, "talk": 1], "a second seed counts nothing twice")
    }

    @Test func theMemoryPurposesLandInTheirOwnRows() {
        let records = [Spend.Record(time: day, provider: "OpenRouter", model: "m", usage: Spend.Usage(promptTokens: 900, completionTokens: 250, cost: 0.0002), purpose: .memory),
                       Spend.Record(time: day, provider: "OpenRouter", model: "m", usage: Spend.Usage(promptTokens: 2500, completionTokens: 600, cost: 0.0006), purpose: .memorySeed)]
        let s = Spend.summarise(records, now: day)
        #expect(s.byPurpose.map(\.purpose) == ["Memory: reading the past", "Long-term memory"])
    }
}

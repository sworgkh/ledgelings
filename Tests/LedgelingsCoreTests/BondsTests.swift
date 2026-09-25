import Foundation
import Testing
@testable import LedgelingsCore

/// Living together: time side by side, a story once it has been long enough,
/// and the few words of it that go into each one's prompt.
@Suite struct BondsTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func everyPairOnScreenAddsUpTimeTogetherOnce() {
        var book = Bonds.Book()
        book.liveTogether(60, names: ["Blocky", "Pip", "Dot", "Pip"])
        book.liveTogether(30, names: ["Pip", "Blocky"])
        #expect(book.bonds.count == 3, "three names, three pairs; a name twice is one character")
        #expect(book.bond("Pip", "Blocky")?.together == 90)
        #expect(book.bond("Blocky", "Pip") == book.bond("Pip", "Blocky"), "a pair is the same pair either way round")
        #expect(book.bond("Dot", "Pip")?.together == 60)
        book.liveTogether(60, names: ["Blocky"])
        #expect(book.bond("Blocky", "Pip")?.together == 90, "alone is not together")
    }

    @Test func aPairIsDueAStoryOnlyAfterLivingTogetherLongEnough() {
        var book = Bonds.Book()
        #expect(!book.needsPlot("Blocky", "Pip", after: 3600, now: Self.now), "strangers")
        book.liveTogether(3599, names: ["Blocky", "Pip"])
        #expect(!book.needsPlot("Blocky", "Pip", after: 3600, now: Self.now))
        book.liveTogether(1, names: ["Blocky", "Pip"])
        #expect(book.needsPlot("Blocky", "Pip", after: 3600, now: Self.now))
        book.asked("Blocky", "Pip", at: Self.now, cost: 0.0002)
        #expect(!book.needsPlot("Blocky", "Pip", after: 3600, now: Self.now.addingTimeInterval(60)), "a failed ask waits before the next")
        #expect(book.needsPlot("Blocky", "Pip", after: 3600, now: Self.now.addingTimeInterval(Bonds.retryAfter)))
        book.begin("Blocky", "Pip", Bonds.Written(bond: "Rivals", plot: "A feud"), length: 3, at: Self.now)
        #expect(!book.needsPlot("Blocky", "Pip", after: 0, now: Self.now.addingTimeInterval(1e6)), "one story at a time")
        #expect(book.bond("Blocky", "Pip")?.cost == 0.0002)
    }

    @Test func aStoryIsToldOverItsConversationsThenMakesRoomForTheNext() {
        var book = Bonds.Book()
        book.liveTogether(7200, names: ["Blocky", "Pip"])
        book.begin("Pip", "Blocky", Bonds.Written(bond: "Grudging friends.", plot: "Pip hides Blocky's favourite pixel."), length: 2, at: Self.now)
        let line = [ChatLog.Line(speaker: "Pip", text: "Hi!"), ChatLog.Line(speaker: "Blocky", text: "No.")]
        book.talked("Blocky", "Pip", lines: line)
        #expect(book.bond("Blocky", "Pip")?.plot?.told == 1)
        book.talked("Blocky", "Pip", lines: [])
        #expect(book.bond("Blocky", "Pip")?.plot?.told == 1, "a conversation where nothing was said does not count")
        book.talked("Blocky", "Pip", lines: line + line + line)
        let bond = book.bond("Blocky", "Pip")!
        #expect(bond.plot == nil && bond.lastPlot == "Pip hides Blocky's favourite pixel.")
        #expect(bond.summary == "Grudging friends.", "the bond outlives the story")
        #expect(bond.talks == 2 && bond.plots == 1)
        #expect(bond.recent.count == Bonds.recentLines, "only the last few lines are kept for the next story")
        #expect(book.needsPlot("Blocky", "Pip", after: 3600, now: Self.now))
    }

    @Test func theModelsAnswerIsReadFromItsTwoLabelledLines() {
        #expect(Bonds.parse("BOND: Old rivals, secretly fond.\nPLOT: Blocky owes Pip a favour and hates it.")
            == Bonds.Written(bond: "Old rivals, secretly fond.", plot: "Blocky owes Pip a favour and hates it."))
        #expect(Bonds.parse("<think>hmm</think>\n**Bond:** \"Wary.\"\n- **PLOT:** *A secret map of the ceiling.*")
            == Bonds.Written(bond: "Wary.", plot: "A secret map of the ceiling."), "marks, quotes and hidden reasoning are cleaned off")
        #expect(Bonds.parse("PLOT: Just a plot.") == Bonds.Written(bond: nil, plot: "Just a plot."))
        #expect(Bonds.parse("BOND: No story here.") == nil)
        #expect(Bonds.parse("") == nil)
    }

    @Test func eachSideHearsTheBondAndWhichPartOfTheStoryThisIs() {
        var bond = Bonds.Bond(names: ["Blocky", "Pip"])
        #expect(Bonds.context(bond, speaker: "Blocky", other: "Pip") == "", "no bond, no story: nothing to add")
        #expect(Bonds.context(nil, speaker: "Blocky", other: "Pip") == "")
        bond.together = 3 * 86400 + 5
        bond.summary = "Rivals."
        bond.plot = Bonds.Plot(text: "A feud over the corner.", length: 3, told: 1, started: Self.now)
        let heard = Bonds.context(bond, speaker: "Blocky", other: "Pip")
        #expect(heard.hasPrefix("You and Pip have shared this screen for 3 days."))
        #expect(heard.contains("How you get on: Rivals.") && heard.contains("(part 2 of 3): A feud over the corner."))
        bond.plot?.told = 2
        #expect(Bonds.context(bond, speaker: "Pip", other: "Blocky").contains("last part"))
        #expect(heard.split(separator: " ").count < 60, "a few dozen words, not a history")
    }

    @Test func theStoryGoesWhereThePromptSaysOrAtTheEnd() {
        let values = ["speaker": "Blocky"]
        #expect(Bonds.withRelationship("I am {speaker}.", values, context: "Rivals.") == "I am Blocky.\nRivals.")
        #expect(Bonds.withRelationship("I am {speaker}. {relationship} Go.", values, context: "Rivals.") == "I am Blocky. Rivals. Go.")
        #expect(Bonds.withRelationship("I am {speaker}.", values, context: "") == "I am Blocky.", "strangers get the prompt as it was")
    }

    @Test func thePlotPromptIsFilledForThePair() {
        var bond = Bonds.Bond(names: ["Blocky", "Pip"])
        bond.together = 7200
        bond.recent = [ChatLog.Line(speaker: "Pip", text: "Hi!")]
        let values = Bonds.plotValues(bond, a: ("Blocky", "a small square creature", "Grumpy."), b: ("Pip", "a small square creature", "Cheerful."), length: 6)
        let prompt = Banter.render(Bonds.defaultPlotPrompt, values)
        #expect(prompt.contains("shared it for 2 hours") && prompt.contains("Blocky, a small square creature: Grumpy.")
            && prompt.contains("Pip: Hi!") && prompt.contains("next 6 conversations") && prompt.contains("this is their first"))
        #expect(!prompt.contains("{"), "every placeholder filled")
    }

    @Test func durationsReadLikePeopleSayThem() {
        #expect(Bonds.duration(20) == "a moment")
        #expect(Bonds.duration(60) == "1 minute")
        #expect(Bonds.duration(45 * 60) == "45 minutes")
        #expect(Bonds.duration(3600 * 5) == "5 hours")
        #expect(Bonds.duration(86400 * 2 + 10) == "2 days")
    }

    @Test func theBookSurvivesTheDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bonds-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Bonds.Store(directory: dir)
        #expect(store.load() == Bonds.Book(), "no file, no bonds")
        var book = Bonds.Book()
        book.liveTogether(5000, names: ["Blocky", "Pip"])
        book.begin("Blocky", "Pip", Bonds.Written(bond: "Rivals.", plot: "A feud."), length: 4, at: Self.now)
        try store.save(book)
        #expect(store.load() == book)
        try Data("not json".utf8).write(to: store.file)
        #expect(store.load() == Bonds.Book(), "a damaged file starts over rather than failing")
    }

    @Test func storiesAreTheirOwnLineInTheCosts() {
        let r = Spend.Record(time: Self.now, provider: "OpenRouter", model: "m",
                             usage: Spend.Usage(promptTokens: 250, completionTokens: 50, cost: 0.0003), purpose: .plots)
        let s = Spend.summarise([r], now: Self.now)
        #expect(s.byPurpose.map(\.purpose) == ["Relationship plots"])
        #expect(s.byPurpose[0].total.calls == 1)
    }
}

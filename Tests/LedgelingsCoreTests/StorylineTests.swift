import Foundation
import Testing
@testable import LedgelingsCore

/// A pair's storyline: every moment they share is kept, folded into their story
/// so far with each new story, and sent with the next one in a few hundred tokens.
@Suite struct StorylineTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static func at(_ daysAgo: Double) -> Date { now.addingTimeInterval(-daysAgo * 86400) }

    /// Blocky and Pip after a week: talks, a tea party, a flower, a plane, a grab.
    static func week() -> Bonds.Book {
        var book = Bonds.Book()
        book.liveTogether(7200, names: ["Blocky", "Pip"])
        book.talked("Blocky", "Pip", lines: [ChatLog.Line(speaker: "Blocky", text: "The cursor again."), ChatLog.Line(speaker: "Pip", text: "Hi!")], at: at(7))
        book.talked("Blocky", "Pip", lines: [ChatLog.Line(speaker: "Pip", text: "Tea? I baked a pixel.")], as: .tea, at: at(5))
        book.note("Pip", "Blocky", Bonds.Moment(time: at(3), kind: .flower, who: "Pip", detail: "poppy"))
        book.note("Blocky", "Pip", Bonds.Moment(time: at(2), kind: .plane, who: "Blocky", detail: "Stop waving."))
        book.note("Pip", "Blocky", Bonds.Moment(time: at(1), kind: .grab, who: "Pip"))
        return book
    }

    @Test func everyMomentTheyShareIsKeptAndCounted() {
        let bond = Self.week().bond("Pip", "Blocky")!
        #expect(bond.moments.map(\.kind) == [.talk, .tea, .flower, .plane, .grab])
        #expect(bond.tally == ["talk": 1, "tea": 1, "flower": 1, "plane": 1, "grab": 1])
        #expect(bond.met == Self.at(7) && bond.talks == 2)
        var book = Self.week()
        for i in 0..<50 { book.note("Blocky", "Pip", Bonds.Moment(time: Self.now, kind: .talk, who: "Pip", detail: "\(i)")) }
        #expect(book.bond("Blocky", "Pip")!.moments.count == Bonds.momentsKept, "a few kept between stories")
        #expect(book.bond("Blocky", "Pip")!.tally["talk"] == 51, "but every one counted")
        book.note("Pip", "Pip", Bonds.Moment(time: Self.now, kind: .talk, who: "Pip"))
        #expect(book.bond("Pip", "Pip") == nil, "nobody shares a moment with themself")
    }

    @Test func aNewStoryFoldsTheMomentsIntoTheirStorySoFar() {
        var book = Self.week()
        book.begin("Blocky", "Pip", Bonds.Written(bond: "Wary.", plot: "A feud."), length: 3, at: Self.now)
        let bond = book.bond("Blocky", "Pip")!
        let story = bond.chronicle ?? ""
        #expect(bond.moments.isEmpty, "folded in, so the next story starts afresh")
        #expect(story.contains("Pip gave Blocky a poppy") && story.contains("tea party") && story.contains("paper plane")
            && story.contains("grabbed the cursor"), "\(story)")
        #expect(!story.contains("today") && !story.contains("yesterday"), "dates, which do not go stale")
        #expect(story.split(separator: " ").count <= Bonds.storyWords)
    }

    @Test func theModelsRewriteIsTheirStorySoFarAndTheNextStorySeesIt() {
        var book = Self.week()
        book.begin("Blocky", "Pip", Bonds.Written(bond: "Wary.", plot: "A feud.", story: "They met over the cursor; Pip gave Blocky a poppy."),
                   length: 2, at: Self.now)
        book.talked("Blocky", "Pip", lines: [ChatLog.Line(speaker: "Pip", text: "Sorry about the feud.")], at: Self.now)
        book.talked("Blocky", "Pip", lines: [ChatLog.Line(speaker: "Blocky", text: "Hmph.")], at: Self.now)
        let bond = book.bond("Blocky", "Pip")!
        #expect(bond.plot == nil && bond.lastPlot == "A feud.")
        let values = Bonds.plotValues(bond, a: ("Blocky", "a robot", "Grumpy."), b: ("Pip", "a blob", "Cheerful."), length: 6, now: Self.now)
        let prompt = Banter.render(Bonds.defaultPlotPrompt, values)
        #expect(prompt.contains("Their story so far:") && prompt.contains("Pip gave Blocky a poppy"), "continuity: the last chapter is in the next")
        #expect(prompt.contains("Their last story: A feud.") && prompt.contains("Sorry about the feud.") && prompt.contains("STORY:"))
        #expect(prompt.contains("all told: 3 talks, 1 tea party, 1 flower, 1 paper plane, 1 cursor grab"), "the whole past, as numbers")
        #expect(!prompt.contains("{"), "every placeholder filled")
        // Without a STORY line, the next fold keeps the model's sentence and adds what came since.
        book.begin("Blocky", "Pip", Bonds.Written(bond: nil, plot: "Making up."), length: 2, at: Self.now)
        let next = book.bond("Blocky", "Pip")!.chronicle ?? ""
        #expect(next.hasPrefix("They met over the cursor") && next.contains("2 talks in all") && next.contains("\"Hmph.\" Then this story played out: A feud."), "\(next)")
    }

    @Test func thePromptStaysSmallHoweverLongTheFriendship() {
        var book = Self.week()
        let long = String(repeating: "word ", count: 60)
        for i in 0..<200 {
            book.talked("Blocky", "Pip", lines: [ChatLog.Line(speaker: i.isMultiple(of: 2) ? "Pip" : "Blocky", text: long)], at: Self.at(Double(200 - i) / 10))
            if i.isMultiple(of: 6) {
                book.begin("Blocky", "Pip", Bonds.Written(bond: "Fine.", plot: long, story: long + long + long), length: 6, at: Self.now)
                book.update("Blocky", "Pip") { $0.plot = nil }
            }
        }
        let bond = book.bond("Blocky", "Pip")!
        let values = Bonds.plotValues(bond, a: ("Blocky", "a robot", "Grumpy."), b: ("Pip", "a blob", "Cheerful."), length: 6, now: Self.now)
        let prompt = Banter.render(Bonds.defaultPlotPrompt, values)
        let tokens = prompt.count / 4
        #expect(tokens < 900, "about \(tokens) tokens")
        #expect((bond.chronicle ?? "").split(separator: " ").count <= Bonds.storyWords)
        let before = Banter.render(Bonds.defaultPlotPrompt, Bonds.plotValues(Bonds.Bond(names: ["Blocky", "Pip"]),
            a: ("Blocky", "a robot", "Grumpy."), b: ("Pip", "a blob", "Cheerful."), length: 6, now: Self.now)).count / 4
        #expect(before < 450, "a new pair's prompt: about \(before) tokens")
    }

    @Test func momentsBeyondThoseShownAreFoldedNotLost() {
        let bond = Self.week().bond("Blocky", "Pip")!
        let told = Bonds.history(bond, Bonds.Telling(words: 80, moments: 2), now: Self.now)
        #expect(told.since.split(separator: "\n").count == 2 && told.since.contains("paper plane") && told.since.contains("cursor"))
        #expect(told.story.contains("poppy") && told.story.contains("tea party"), "the three older ones are in the story so far")
    }

    @Test func withoutAModelTheStoryGrowsFromWhatTheyLivedThrough() {
        var rng = SystemRandomNumberGenerator()
        let bond = Self.week().bond("Blocky", "Pip")!
        for _ in 0..<10 {
            let written = Bonds.builtInPlot(bond, now: Self.now, using: &rng)
            #expect(written.plot.contains("poppy") && written.plot.contains("3 days ago"), "the flower, and when: \(written.plot)")
            #expect(written.bond?.contains("1 tea party") == true && written.story == nil)
        }
        var described = bond
        described.summary = "Grudging friends."
        #expect(Bonds.builtInPlot(described, now: Self.now, using: &rng).bond == "Grudging friends.", "a written bond line stays")
        var talkOnly = Bonds.Bond(names: ["Blocky", "Pip"])
        talkOnly.moments = [Bonds.Moment(time: Self.at(1), kind: .talk, who: "Pip", detail: "Nice ceiling.")]
        talkOnly.tally = ["talk": 1]
        let plot = Bonds.builtInPlot(talkOnly, now: Self.now, using: &rng).plot
        #expect(plot.contains("yesterday"), "\(plot)")
        #expect(!Bonds.builtInPlot(Bonds.Bond(names: ["Blocky", "Pip"]), using: &rng).plot.isEmpty, "strangers get a story too")
    }

    @Test func theModelsStoryLineIsRead() {
        let w = Bonds.parse("BOND: Wary.\nPLOT: A feud.\n**STORY:** They met on 3 Oct. Pip gave Blocky a poppy.")
        #expect(w == Bonds.Written(bond: "Wary.", plot: "A feud.", story: "They met on 3 Oct. Pip gave Blocky a poppy."))
        #expect(Bonds.parse("PLOT: A feud.")?.story == nil)
    }

    @Test func aLongStoryIsTrimmedFromItsOldestSentences() {
        #expect(Bonds.trimmed("One two three. Four five. Six seven.", words: 4) == "Four five. Six seven.")
        #expect(Bonds.trimmed("One two three four five six", words: 3) == "One two three…")
        #expect(Bonds.trimmed("Old news here. Pip said: \"Tea? I baked a pixel.\" Then a feud.", words: 10)
            == "Pip said: \"Tea? I baked a pixel.\" Then a feud.", "a quoted line is one sentence")
    }

    @Test func anOldPairsPastIsReadFromTheChatLogOnce() {
        var book = Bonds.Book()
        book.liveTogether(7200, names: ["Blocky", "Pip"])
        book.talked("Blocky", "Pip", lines: [ChatLog.Line(speaker: "Pip", text: "Live.")], at: Self.at(1))
        func exchange(_ daysAgo: Double, _ who: [String]) -> ChatLog.Exchange {
            ChatLog.Exchange(time: Self.at(daysAgo), situation: "", provider: "", model: "",
                             lines: who.map { ChatLog.Line(speaker: $0, text: "Line of \($0).") })
        }
        let log = [exchange(30, ["Blocky", "Pip"]), exchange(20, ["Pip", "Blocky"]), exchange(10, ["Blocky", "Zed"]),
                   exchange(15, ["Blocky"]), exchange(1, ["Pip", "Blocky"])]
        book.seed("Pip", "Blocky", from: log)
        let bond = book.bond("Blocky", "Pip")!
        #expect(bond.seeded && bond.tally["talk"] == 3, "two from the log, one live; the live one not counted twice")
        #expect(bond.met == Self.at(30) && bond.moments.first?.who == "Blocky" && bond.moments.count == 3)
        book.seed("Pip", "Blocky", from: log)
        #expect(book.bond("Blocky", "Pip")!.tally["talk"] == 3, "only once")
    }

    @Test func aStoryCanBeStartedOverForOnePairOrAll() {
        var book = Self.week()
        book.liveTogether(100, names: ["Blocky", "Zed"])
        book.begin("Blocky", "Pip", Bonds.Written(bond: "Wary.", plot: "A feud."), length: 3, at: Self.now)
        book.resetStory(Bonds.key("Pip", "Blocky"))
        let bond = book.bond("Blocky", "Pip")!
        #expect(bond.chronicle == nil && bond.moments.isEmpty && bond.tally.isEmpty && bond.plot == nil && bond.summary == nil)
        #expect(bond.together == 7200 && bond.seeded, "their time stays, and the log is not read back in")
        book.note("Blocky", "Zed", Bonds.Moment(time: Self.now, kind: .talk, who: "Zed"))
        book.resetAllStories()
        #expect(book.bond("Blocky", "Zed")!.moments.isEmpty && book.bonds.count == 2)
    }

    @Test func theStorylineSurvivesARelaunchAndAnOldFileStillLoads() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("story-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Bonds.Store(directory: dir)
        var book = Self.week()
        book.begin("Blocky", "Pip", Bonds.Written(bond: "Wary.", plot: "A feud.", story: "They met."), length: 3, at: Self.now)
        book.note("Blocky", "Pip", Bonds.Moment(time: Self.now, kind: .plane, who: "Pip", detail: "Hello."))
        try store.save(book)
        #expect(store.load() == book)
        // A bonds.json from before storylines: no chronicle, moments, tally, met or seeded.
        try Data(#"{"bonds": {"Blocky & Pip": {"names": ["Blocky", "Pip"], "together": 60, "talks": 2, "plots": 0, "recent": []}}}"#.utf8)
            .write(to: store.file)
        let old = store.load().bond("Blocky", "Pip")
        #expect(old?.together == 60 && old?.talks == 2 && old?.moments == [] && old?.seeded == false)
    }

    @Test func theStorylineIsToldInRussian() {
        Language.$override.withValue(.russian) {
            let bond = Self.week().bond("Blocky", "Pip")!
            let told = Bonds.history(bond, Bonds.Telling(), now: Self.now)
            #expect(told.story.contains("Знакомы с") && told.since.contains("подарок от Pip для Blocky"))
            var rng = SystemRandomNumberGenerator()
            #expect(Bonds.builtInPlot(bond, now: Self.now, using: &rng).plot.contains("3 дня назад"))
            #expect(Bonds.plotPrompts(.russian).contains("STORY:") && Bonds.plotPrompts(.russian).contains("{story}"))
        }
    }
}

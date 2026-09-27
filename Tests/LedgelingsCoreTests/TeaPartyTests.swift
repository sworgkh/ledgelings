import CoreGraphics
import Foundation
import Testing
@testable import LedgelingsCore

@Suite struct TeaPartyTests {
    /// Step the party `seconds` in tenths, collecting what it asks for.
    func run(_ party: inout TeaParty, from start: Double, for seconds: Double, each: (Double, TeaParty.Event, inout TeaParty) -> Void = { _, _, _ in }) -> [TeaParty.Event] {
        var events: [TeaParty.Event] = []
        var t = start
        while t < start + seconds - 1e-9 {
            t += 0.1
            for e in party.update(at: t) { events.append(e); each(t, e, &party) }
        }
        return events
    }

    @Test func aPartySeatsLaysTheTableTakesTurnsAndPacksAwayOnTime() {
        var party = TeaParty(a: 2, b: 5, at: 0, length: 60, pause: 6)
        #expect(party.phase == .seating && party.scale(at: 0) == 0 && party.isOn)
        party.seated(at: 1)
        #expect(party.phase == .laying)
        _ = party.update(at: 1.2)
        #expect(abs(party.scale(at: 1.2) - 0.5) < 1e-9, "grows up out of the edge")
        // Each round takes 10 s to say; the party answers with the next after the sip.
        var tellers: [Int] = []
        let events = run(&party, from: 1.2, for: 80) { t, e, p in
            if case .round(let teller, let listener) = e {
                tellers.append(teller)
                #expect(Set([teller, listener]) == [2, 5])
                p.roundDone(at: t + 10)          // said by then; its own clock catches up below
            }
        }
        #expect(tellers.prefix(4) == [2, 5, 2, 5], "they take turns telling, a first")
        #expect(events.last == .finished && party.isOver)
        #expect(party.rounds == tellers.count)
        #expect(party.rounds >= 3 && party.rounds <= 4, "one round every 16 s or so over a minute: \(party.rounds)")
    }

    @Test func aRoundUnderWayIsLetFinishAfterTheTimeIsUp() {
        var party = TeaParty(a: 0, b: 1, at: 0, length: 5, pause: 0)
        party.seated(at: 0)
        #expect(run(&party, from: 0, for: 2) == [.round(teller: 0, listener: 1)])
        #expect(run(&party, from: 2, for: 20).isEmpty && party.phase == .tea, "still telling at 22 s")
        party.roundDone(at: 22)
        #expect(run(&party, from: 22, for: 1) == [.finished], "then straight to packing, no new round")
    }

    @Test func aStragglerStillGetsTheTableAfterTheSeatingCap() {
        var party = TeaParty(a: 0, b: 1, at: 0, length: 60, pause: 1)
        _ = run(&party, from: 0, for: 3.9)
        #expect(party.phase == .seating)
        _ = run(&party, from: 3.9, for: 0.2)
        #expect(party.phase == .laying)
    }

    @Test func postponingARoundAsksForItAgainAndCountsNothing() {
        var party = TeaParty(a: 0, b: 1, at: 0, length: 60, pause: 1)
        party.seated(at: 0)
        #expect(run(&party, from: 0, for: 2).count == 1)
        party.postpone(at: 2)
        #expect(party.rounds == 0 && !party.inRound)
        #expect(run(&party, from: 2, for: 1.05) == [.round(teller: 0, listener: 1)], "the same teller again")
    }

    @Test func breakingUpPacksTheTableOrWithNoTableEndsAtOnce() {
        var laid = TeaParty(a: 0, b: 1, at: 0, length: 60, pause: 1)
        laid.seated(at: 0)
        _ = run(&laid, from: 0, for: 2)
        laid.end(at: 2)
        #expect(laid.phase == .packing && !laid.isOn && !laid.inRound)
        #expect(abs(laid.scale(at: 2.25) - 0.5) < 1e-9)
        #expect(run(&laid, from: 2, for: 1) == [.finished])

        var seating = TeaParty(a: 0, b: 1, at: 0, length: 60, pause: 1)
        seating.end(at: 1)
        #expect(seating.isOver, "no table yet, nothing to pack")
    }

    @Test func seatsAreEitherSideOfTheMiddleAndNeverRoundACorner() throws {
        let loop = EdgeLoop(rect: CGRect(x: 10, y: 10, width: 780, height: 580))
        // On the floor, a middle at x = 300: the one facing right (+1) sits to the left of it.
        let middle = CGPoint(x: 300, y: 10)
        let left = try #require(TeaParty.seat(on: loop, segment: 0, middle: middle, facing: 1, offset: 50))
        let right = try #require(TeaParty.seat(on: loop, segment: 0, middle: middle, facing: -1, offset: 50))
        #expect(loop.point(at: left) == CGPoint(x: 250, y: 10))
        #expect(loop.point(at: right) == CGPoint(x: 350, y: 10))
        // Near the corner there is no room for the one behind.
        #expect(TeaParty.seat(on: loop, segment: 0, middle: CGPoint(x: 40, y: 10), facing: 1, offset: 50) == nil)
        // On the right wall, going up: the same rule along its own direction.
        let up = try #require(TeaParty.seat(on: loop, segment: 1, middle: CGPoint(x: 790, y: 300), facing: 1, offset: 40))
        #expect(loop.point(at: up) == CGPoint(x: 790, y: 260))
    }

    @Test func theChanceIsAShareOfBumps() {
        var rng = SeededRNG(state: 11)
        let yes = (0..<2000).filter { _ in TeaParty.wanted(percent: 10, using: &rng) }.count
        #expect(yes > 150 && yes < 250, "about one in ten: \(yes)")
        #expect(!(0..<200).contains { _ in TeaParty.wanted(percent: 0, using: &rng) })
        #expect((0..<200).allSatisfy { _ in TeaParty.wanted(percent: 100, using: &rng) })
    }

    @Test func everyBuiltInCharacterHasItsOwnStoriesAndAnswers() {
        // The same 27 as the complaints: every built-in character, in its own voice.
        #expect(Set(Tea.stories.keys) == Set(Complaints.lines.keys))
        #expect(Set(Tea.replies.keys) == Set(Complaints.lines.keys))
        for (name, stories) in Tea.stories {
            #expect(stories.count == 4 && Set(stories).count == 4, "\(name)")
            #expect(stories.allSatisfy { !$0.contains("{") }, "\(name): a story needs nothing filled in")
        }
        for (name, replies) in Tea.replies { #expect(replies.count == 3, "\(name)") }
        let all = Tea.stories.values.flatMap { $0 }
        #expect(Set(all).count == all.count, "nobody tells someone else's story")
    }

    @Test func aStoryIsNotToldTwiceAtOnePartyAndAnAnswerNamesTheTeller() {
        var rng = SeededRNG(state: 3)
        var told: Set<String> = []
        for _ in 0..<4 { told.insert(Tea.story(by: "Blocky", avoiding: told, using: &rng)) }
        #expect(told == Set(Tea.stories["Blocky"]!))
        #expect(Tea.stories["Blocky"]!.contains(Tea.story(by: "Blocky", avoiding: told, using: &rng)), "all told: one again")
        #expect(Tea.anyoneStories.contains(Tea.story(by: "Someone New", avoiding: [], using: &rng)))
        let replies = (0..<30).map { _ in Tea.reply(by: "Pip", to: "Zed", using: &rng) }
        #expect(replies.allSatisfy { !$0.contains("{other}") })
        #expect(replies.contains { $0.contains("Zed") })
    }

    @Test func thePromptsCarryWhoTheyAreAndWhatWasSaidAtTheTable() {
        #expect(Tea.systemPrompt.contains("{speakerPersona}") && Tea.systemPrompt.contains("{speakerKind}"))
        #expect(Tea.storyPrompt.contains("{party}") && Tea.replyPrompt.contains("{line}"))
        #expect(Tea.transcript([]).contains("just been poured"))
        let lines = (1...10).map { ChatLog.Line(speaker: $0.isMultiple(of: 2) ? "Pip" : "Zed", text: "line \($0)") }
        let shown = Tea.transcript(lines)
        #expect(!shown.contains("line 2\n") && shown.hasPrefix("Zed: line 3") && shown.hasSuffix("Pip: line 10"), "the last eight")
    }
}

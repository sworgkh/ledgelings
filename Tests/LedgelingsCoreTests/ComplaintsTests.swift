import CoreGraphics
import Foundation
import Testing
@testable import LedgelingsCore

@Suite struct ComplaintsTests {
    @Test func theFifthBotherInARowGetsAComplaintAndTheCountStartsOver() {
        var a = Annoyance(limit: 4, calmAfter: 20)
        let first = (1...4).map { a.bothered(0, at: Double($0)) }
        #expect(first == [false, false, false, false], "four in a row it puts up with")
        #expect(a.streak(of: 0, at: 4) == 4)
        let fifth = a.bothered(0, at: 5)
        #expect(fifth, "the fifth is one too many")
        #expect(a.streak(of: 0, at: 5) == 5)
        a.forgive(0)
        let sixth = a.bothered(0, at: 6)
        #expect(!sixth, "after complaining it needs a fresh streak")
        #expect(a.streak(of: 0, at: 6) == 1)
    }

    @Test func aQuietSpellStartsTheCountOverAndEachCreatureCountsAlone() {
        var a = Annoyance(limit: 2, calmAfter: 10)
        _ = a.bothered(0, at: 0); _ = a.bothered(0, at: 5)
        let later = a.bothered(0, at: 16)
        #expect(!later, "11 s of peace: this is the first again")
        #expect(a.streak(of: 0, at: 16) == 1)
        #expect(a.streak(of: 0, at: 30) == 0, "calm by now")
        _ = a.bothered(1, at: 16)
        #expect(a.streak(of: 1, at: 16) == 1)
        a.forget(creaturesFrom: 1)
        #expect(a.streak(of: 1, at: 16) == 0 && a.streak(of: 0, at: 16) == 1)
    }

    @Test func everyBuiltInCharacterComplainsInItsOwnWords() {
        let everyone = Banter.defaultCharacters.map(\.name) + Letters.voices.keys
        var rng = SystemRandomNumberGenerator()
        for name in Set(everyone) {
            let lines = Complaints.lines[name]
            #expect(lines != nil && lines!.count >= 3, "\(name) has its own complaints")
            #expect(lines?.contains { $0.contains("{times}") } == true, "\(name) counts at least once")
            #expect(!Complaints.line(by: name, times: 5, using: &rng).contains("{"))
        }
        #expect(Complaints.lines.keys.allSatisfy { Set(everyone).contains($0) }, "no lines for a character that does not exist")
        #expect(Complaints.anyone.contains { $0.contains("{times}") })
        #expect(Complaints.prompt.contains("{situation}") && Complaints.prompt.contains("{times}"))
    }

    @Test func updateSaysWhenTheCursorMadeItJump() {
        let world = EdgeWorld(screens: [CGRect(x: 0, y: 0, width: 1020, height: 620)], inset: 10)
        var c = Creature(world: world, spot: .init(loop: 0, t: 300))
        var rng = SeededRNG(state: 3)
        let far = c.update(dt: 1.0 / 30, cursor: CGPoint(x: -500, y: -500), using: &rng)
        #expect(!far, "cursor far away")
        let near = c.update(dt: 1.0 / 30, cursor: c.position, using: &rng)
        #expect(near && c.isJumping, "cursor on it: it jumps")
        let again = c.update(dt: 1.0 / 30, cursor: c.position, using: &rng)
        #expect(!again, "already in the air: once per jump")
    }

    @Test func complaintsAreTheirOwnLineInTheCosts() {
        let usage = Spend.Usage(promptTokens: 120, completionTokens: 20, cost: 0.0001)
        let records = [Spend.Record(time: Date(), provider: "OpenRouter", model: "m", usage: usage, purpose: .complaints)]
        #expect(Spend.summarise(records, now: Date()).byPurpose.map(\.purpose) == ["Complaints"])
    }
}

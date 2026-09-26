import Foundation
import Testing
@testable import LedgelingsCore

/// Characters say something new until they have run through what they know.
@Suite struct LineMemoryTests {
    @Test func remembersTheLastLinesOfEachCharacter() {
        var memory = LineMemory(limit: 2)
        memory.remember("One.", by: "Blocky")
        memory.remember("Two.", by: "Blocky")
        memory.remember("Three.", by: "Blocky")
        memory.remember("Hi!", by: "Pip")
        #expect(memory.recent(of: "Blocky") == ["Two.", "Three."])
        #expect(memory.recent(of: "Pip") == ["Hi!"])
        #expect(memory.recent(of: "Zed").isEmpty)
        memory.remember("two", by: "Blocky")
        #expect(memory.recent(of: "Blocky") == ["Three.", "two"], "the same line again moves to the end, not twice")
    }

    @Test func picksALineNotSaidLatelyThenTheOneSaidLongestAgo() {
        var memory = LineMemory(limit: 10)
        var rng = SystemRandomNumberGenerator()
        let lines = ["A paper plane.", "Paper beats cursor.", "Fine. A reply."]
        memory.remember("A paper plane.", by: "Blocky")
        memory.remember("Paper beats cursor!", by: "Blocky")
        for _ in 0..<20 { #expect(memory.pick(from: lines, by: "Blocky", using: &rng) == 2) }
        memory.remember("Fine. A reply.", by: "Blocky")
        for _ in 0..<20 { #expect(memory.pick(from: lines, by: "Blocky", using: &rng) == 0, "all said: the oldest comes back") }
        #expect(memory.pick(from: lines, by: "Pip", using: &rng) != nil)
        #expect(memory.pick(from: [], by: "Pip", using: &rng) == nil)
    }

    @Test func aRoundOfLettersNeverRepeatsALine() {
        var memory = LineMemory(limit: 12)
        var rng = SystemRandomNumberGenerator()
        let count = Letters.voice(of: "Blocky").musings.count
        var said: [String] = []
        for _ in 0..<(count * 3) {
            let line = Letters.musing(by: "Blocky", from: "Pip", memory: memory, using: &rng)
            said.append(line)
            memory.remember(line, by: "Blocky")
        }
        for start in stride(from: 0, to: said.count, by: count) {
            #expect(Set(said[start..<start + count]).count == count, "every musing once before any comes back")
        }
    }

    @Test func offRemembersNothing() {
        var memory = LineMemory(limit: 0)
        memory.remember("Hello.", by: "Pip")
        #expect(memory.recent(of: "Pip").isEmpty)
        #expect(LineMemory.withRecent("System.", []) == "System.")
    }

    @Test func tellsTheModelWhatItSaidLately() {
        let prompt = LineMemory.withRecent("You are Blocky.", ["Watch where you're going.", "The bottom edge is respectable."])
        #expect(prompt.hasPrefix("You are Blocky.\n"))
        #expect(prompt.contains("- Watch where you're going.\n- The bottom edge is respectable."))
        #expect(prompt.contains("do not repeat"))
    }

    @Test func learnsFromAnExchangeAndTrims() {
        var memory = LineMemory(limit: 3)
        memory.remember(ChatLog.Exchange(time: Date(), situation: "", provider: "", model: "",
                                         lines: [.init(speaker: "Blocky", text: "Hm."), .init(speaker: "Pip", text: "Ha!")]))
        #expect(memory.recent(of: "Pip") == ["Ha!"])
        memory.trim(to: 0)
        #expect(memory.recent(of: "Blocky").isEmpty)
    }
}

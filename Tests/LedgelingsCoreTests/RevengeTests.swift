import CoreGraphics
import Foundation
import Testing
@testable import LedgelingsCore

/// Revenge: when it is due, what counts as shaking the cursor off, and the words.
@Suite struct RevengeTests {

    @Test func theTenthHuntInsideTheWindowMakesItDue() {
        var fuse = Revenge.Fuse(after: 10, window: 120, cooldown: 600)
        for k in 0..<9 { let due = fuse.hunted(0, at: Double(k) * 10); #expect(!due, "hunt \(k + 1)") }
        let r2 = fuse.hunted(0, at: 95)
        #expect(r2, "the tenth inside two minutes")
        #expect(fuse.recent(0, at: 95) == 10)
        #expect(fuse.recent(1, at: 95) == 0, "counted per creature")
    }

    @Test func huntsSpreadOutNeverAddUp() {
        var fuse = Revenge.Fuse(after: 3, window: 60, cooldown: 0)
        for t in [0.0, 50, 115] { let due = fuse.hunted(0, at: t); #expect(!due, "at \(t)") }
        #expect(fuse.recent(0, at: 115) == 1, "the first two fell out of the window")
        _ = fuse.hunted(0, at: 116)
        let due = fuse.hunted(0, at: 117)
        #expect(due)
    }

    @Test func afterAGrabNobodyGrabsAgainUntilTheCooldownIsOver() {
        var fuse = Revenge.Fuse(after: 2, window: 60, cooldown: 600)
        _ = fuse.hunted(0, at: 0)
        let r7 = fuse.hunted(0, at: 1)
        #expect(r7)
        fuse.grabbed(at: 1)
        #expect(fuse.recent(0, at: 1) == 0, "the count starts over")
        _ = fuse.hunted(1, at: 100)
        let r8 = fuse.hunted(1, at: 101)
        #expect(!r8, "another creature waits out the cooldown too")
        _ = fuse.hunted(1, at: 650)
        let r9 = fuse.hunted(1, at: 651)
        #expect(r9)
    }

    @Test func quickStrokesBackAndForthShakeItOff() {
        var shake = Revenge.Shake(needed: 6)
        var t = 0.0, shaken = false, strokes = 0
        while !shaken, strokes < 20 {
            let way: Double = strokes.isMultiple(of: 2) ? 1 : -1
            for _ in 0..<3 { t += 1.0 / 60; shaken = shake.moved(dx: way * 20, dy: 0, at: t) || shaken }
            strokes += 1
        }
        #expect(shaken)
        #expect(strokes == 7, "six turns back after full strokes: \(strokes)")
    }

    @Test func jitterAndSlowDriftDoNotCount() {
        var jitter = Revenge.Shake(needed: 3)
        for k in 0..<200 {
            let off = jitter.moved(dx: k.isMultiple(of: 2) ? 5 : -5, dy: k.isMultiple(of: 3) ? 4 : -4, at: Double(k) / 60)
            #expect(!off, "small strokes")
        }
        var drift = Revenge.Shake(needed: 3)
        for k in 0..<12 {
            // A long stroke each way, two seconds apart: turns too slow to add up.
            let off = drift.moved(dx: k.isMultiple(of: 2) ? 200 : -200, dy: 0, at: Double(k) * 2)
            #expect(!off)
        }
        #expect(drift.vigour(at: 24) < 1)
    }

    @Test func theStrokeAndTheWindowAreTunable() {
        var gentle = Revenge.Shake(needed: 2, stroke: 10, window: 2)
        _ = gentle.moved(dx: 12, dy: 0, at: 0)
        _ = gentle.moved(dx: -12, dy: 0, at: 0.8)
        let off = gentle.moved(dx: 12, dy: 0, at: 1.6)
        #expect(off, "short strokes count when the stroke is short")
        var strict = Revenge.Shake(needed: 2, stroke: 40, window: 1)
        _ = strict.moved(dx: 50, dy: 0, at: 0)
        _ = strict.moved(dx: -50, dy: 0, at: 0.8)
        let late = strict.moved(dx: 50, dy: 0, at: 1.9)
        #expect(!late, "too slow for a one-second window")
    }

    @Test func noLimitMeansUntilShakenOffExceptWhenHeldStill() {
        #expect(Revenge.longestHold(limit: 0, pinned: false) == .infinity)
        #expect(Revenge.longestHold(limit: 0, pinned: true) == Revenge.pinnedHoldCap)
        #expect(Revenge.longestHold(limit: 20, pinned: true) == 10)
        #expect(Revenge.longestHold(limit: 5, pinned: false) == 5)
    }

    @Test func shakingUpAndDownCountsToo() {
        var shake = Revenge.Shake(needed: 2)
        let r12 = shake.moved(dx: 0, dy: 40, at: 0)
        #expect(!r12)
        let r13 = shake.moved(dx: 0, dy: -40, at: 0.1)
        #expect(!r13)
        #expect(shake.vigour(at: 0.1) == 0.5)
        let r14 = shake.moved(dx: 0, dy: 40, at: 0.2)
        #expect(r14)
        #expect(shake.vigour(at: 5) == 0, "it fades when the shaking stops")
    }

    static let shippedNames = Set(Complaints.englishLines.keys)

    @Test func everyCharacterHasItsLinesInEveryMoodAndLanguage() {
        let allowed: Set<String> = ["today", "all"]
        for mood in CursorMood.allCases {
            for l in Language.allCases {
                let sets = Revenge.lineSets(for: mood)(l), last = Revenge.lastWordSets(for: mood)(l)
                #expect(Set(sets.keys) == Self.shippedNames, "\(mood) \(l.code): \(Self.shippedNames.symmetricDifference(sets.keys))")
                #expect(Set(last.keys) == Self.shippedNames, "\(mood) \(l.code) last words: \(Self.shippedNames.symmetricDifference(last.keys))")
                #expect(!Revenge.anyones(for: mood)(l).isEmpty && !Revenge.anyoneLastWords(for: mood)(l).isEmpty)
                for line in sets.values.flatMap({ $0 }) + Revenge.anyones(for: mood)(l) {
                    let used = Set(line.matches(of: /\{(\w+)\}/).map { String($0.1) })
                    #expect(used.isSubset(of: allowed), "\(mood) \(l.code): \(line)")
                }
                for line in last.values.flatMap({ $0 }) + Revenge.anyoneLastWords(for: mood)(l) {
                    #expect(!line.contains("{"), "\(mood) \(l.code): \(line)")
                }
                if l != .english {
                    #expect(sets != Revenge.lineSets(for: mood)(.english), "\(mood) \(l.code) is its own text")
                    #expect(last != Revenge.lastWordSets(for: mood)(.english))
                    #expect(Revenge.prompts(for: mood)(l) != Revenge.prompts(for: mood)(.english))
                }
            }
            for name in Self.shippedNames {
                #expect(Revenge.lineSets(for: mood)(.english)[name]!.count == Revenge.lineSets(for: mood)(.russian)[name]!.count,
                        "\(mood) \(name): line for line")
            }
            for l in Language.allCases {
                let prompt = Revenge.prompts(for: mood)(l)
                #expect(prompt.contains("{situation}") && prompt.contains("{times}"), "\(mood) \(l.code)")
            }
        }
        #expect(Revenge.englishBadLines["Blocky"] != Revenge.englishGoodLines["Blocky"], "each mood its own words")
        #expect(Revenge.englishGoodLines["Blocky"] != Revenge.englishNeutralLines["Blocky"])
    }

    @Test func aLineHasItsNumbersFilledIn() {
        var rng = SystemRandomNumberGenerator()
        for mood in CursorMood.allCases {
            for name in ["Blocky", "Somebody New"] {
                for _ in 0..<10 {
                    let line = Language.$override.withValue(.english) { Revenge.line(by: name, today: 17, all: 403, mood: mood, using: &rng) }
                    #expect(!line.contains("{"), "\(mood) \(name): \(line)")
                }
                let last = Language.$override.withValue(.english) { Revenge.lastWord(by: name, mood: mood, using: &rng) }
                #expect(!last.isEmpty)
            }
        }
    }

    @Test func revengeIsItsOwnLineInTheCosts() {
        let usage = Spend.Usage(promptTokens: 120, completionTokens: 20, cost: 0.0001)
        let records = [Spend.Record(time: Date(), provider: "OpenRouter", model: "m", usage: usage, purpose: .revenge)]
        #expect(Spend.summarise(records, now: Date()).byPurpose.map(\.purpose) == ["Revenge"])
    }

    @Test func aClingerTumblesDownWhenShakenOff() {
        let world = EdgeWorld(screens: [CGRect(x: 0, y: 0, width: 800, height: 600)], inset: 10)
        var c = Creature(world: world)
        var rng = SystemRandomNumberGenerator()
        c.toggleNap(using: &rng)
        let clung = c.cling()
        #expect(clung && c.isHeld && !c.isSleeping, "awake, whatever it was doing")
        let again = c.cling()
        #expect(!again, "already holding on")
        c.drag(to: CGPoint(x: 400, y: 300))
        c.drop(tumbling: true)
        guard case .jumping(let jump) = c.mode else { Issue.record("it falls"); return }
        #expect(abs(jump.spin) == 4 * .pi && jump.duration >= 0.6)
        var turned = 0.0, last = c.rotation
        for _ in 0..<60 { c.update(dt: 1.0 / 60, cursor: nil, using: &rng); turned += abs(c.rotation - last); last = c.rotation }
        #expect(turned > 2 * .pi, "it turns head over heels on the way down")
        #expect(!c.isJumping)
    }
}

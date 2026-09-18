import Testing
@testable import LedgelingsCore

/// The little house: appears, swallows everyone, packs itself away, and lets them out later.
@Suite struct HideoutTests {
    @Test func theWholeCycleFromHideToWelcomeBack() {
        var h = Hideout()
        #expect(!h.isActive && h.scale(at: 0) == 0)
        h.hide(count: 3, at: 100, for: 60)
        #expect(h.isActive && h.phase == .appearing)
        #expect(abs(h.scale(at: 100.2) - 0.5) < 1e-9)
        #expect(h.update(at: 100.4).isEmpty && h.phase == .gathering)
        #expect(h.scale(at: 101) == 1)
        h.entered(0, at: 101); h.entered(1, at: 102)
        #expect(h.phase == .gathering && h.isInside(1) && !h.isInside(2))
        h.entered(2, at: 103)
        #expect(h.phase == .shrinking)
        #expect(abs(h.scale(at: 103.25) - 0.5) < 1e-9)
        _ = h.update(at: 103.5)
        #expect(h.phase == .hidden && h.scale(at: 120) == 0)
        #expect(h.remaining(at: 120) == 40)
        _ = h.update(at: 159)
        #expect(h.phase == .hidden)
        _ = h.update(at: 160)
        #expect(h.phase == .growing)
        _ = h.update(at: 160.4)
        #expect(h.phase == .releasing)
        var out: [Int] = []
        for t in stride(from: 160.4, through: 163.0, by: 0.1) {
            for event in h.update(at: t) { if case .letOut(let i) = event { out.append(i) } }
        }
        #expect(out == [0, 1, 2])
        #expect(h.phase == .vanishing || h.phase == .away)
        _ = h.update(at: 164)
        #expect(h.phase == .away && !h.isActive && h.scale(at: 164) == 0)
    }

    @Test func stragglersAreForcedInsideWhenTheGatheringTakesTooLong() {
        var h = Hideout()
        h.hide(count: 2, at: 0, for: 600)
        _ = h.update(at: 0.4)
        h.entered(0, at: 1)
        let events = h.update(at: 0.4 + h.gatherCap)
        #expect(events.contains(.forceInside([1])))
        h.entered(1, at: 26)
        #expect(h.phase == .shrinking)
    }

    @Test func bringingThemBackEarlyOpensTheHouseNow() {
        var h = Hideout()
        h.hide(count: 1, at: 0, for: 3600)
        _ = h.update(at: 0.4); h.entered(0, at: 1); _ = h.update(at: 1.5)
        #expect(h.phase == .hidden)
        h.recall(at: 10)
        #expect(h.phase == .growing)
        #expect(h.remaining(at: 10) == 0)
    }

    @Test func recallingDuringTheGatheringJustLetsThemStay() {
        var h = Hideout()
        h.hide(count: 2, at: 0, for: 3600)
        _ = h.update(at: 0.4); h.entered(0, at: 1)
        h.recall(at: 2)
        #expect(h.phase == .releasing)
        let events = h.update(at: 2)
        #expect(events.contains(.letOut(0)))
    }

    @Test func hidingAgainWhileActiveIsIgnored() {
        var h = Hideout()
        h.hide(count: 2, at: 0, for: 60)
        h.hide(count: 5, at: 1, for: 5)
        #expect(h.count == 2 && h.remaining(at: 1) == 59 + 0.4 + 0.5 || h.remaining(at: 1) == 59)
    }
}

import CoreGraphics
import Testing
@testable import LedgelingsCore

/// The little burst of pixel stars when two creatures bump.
@Suite struct SparksTests {
    @Test func aBurstThrowsStarsUpAndTheyFallBackAndDie() {
        var rng = SeededRNG(state: 7)
        var sparks = Sparks()
        sparks.burst(at: CGPoint(x: 100, y: 10), inward: CGVector(dx: 0, dy: 1), count: 8, using: &rng)
        #expect(sparks.alive.count == 8)
        sparks.update(dt: 0.1)
        #expect(sparks.alive.allSatisfy { $0.position.y > 10 }, "all thrown into the screen at first")
        for _ in 0..<20 { sparks.update(dt: 0.05) }
        #expect(sparks.alive.isEmpty, "gone after about a second")
    }

    @Test func starsFadeAsTheyAge() {
        var rng = SeededRNG(state: 8)
        var sparks = Sparks(life: 1)
        sparks.burst(at: .zero, inward: CGVector(dx: 0, dy: 1), count: 3, using: &rng)
        sparks.update(dt: 0.2)
        let early = sparks.alive.map(\.opacity)
        sparks.update(dt: 0.6)
        let late = sparks.alive.map(\.opacity)
        #expect(zip(early, late).allSatisfy { $0 > $1 })
        #expect(late.allSatisfy { $0 > 0 && $0 < 0.5 })
    }

    @Test func gravityPullsThemBackTowardTheEdgeTheyCameFrom() {
        var rng = SeededRNG(state: 9)
        var sparks = Sparks(life: 5)
        sparks.burst(at: .zero, inward: CGVector(dx: -1, dy: 0), count: 4, using: &rng)   // a right-hand wall: "up" is leftwards
        sparks.update(dt: 0.1)
        let before = sparks.alive.map(\.velocity.dx)
        sparks.update(dt: 0.5)
        let after = sparks.alive.map(\.velocity.dx)
        #expect(zip(before, after).allSatisfy { $1 > $0 }, "each star's leftward speed shrinks")
    }
}

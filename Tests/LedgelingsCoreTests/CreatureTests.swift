import CoreGraphics
import Testing
@testable import LedgelingsCore

/// Deterministic, so a failing test fails the same way twice.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite struct CreatureTests {
    let world = EdgeWorld(screens: [CGRect(x: 0, y: 0, width: 1020, height: 620)], inset: 10)
    var loop: EdgeLoop { world.loops[0] }
    func creature(at t: CGFloat) -> Creature { Creature(world: world, spot: .init(loop: 0, t: t)) }

    func run(_ creature: inout Creature, seconds: Double, cursor: CGPoint? = nil, night: Bool = false,
             rng: inout SeededRNG, each: (Creature) -> Void = { _ in }) {
        for _ in 0..<Int(seconds * 30) {
            creature.update(dt: 1.0 / 30, cursor: cursor, isNight: night, using: &rng)
            each(creature)
        }
    }

    @Test func walksAlongTheEdgeAtItsSpeed() {
        var rng = SeededRNG(state: 1)
        var c = creature(at: 100)
        run(&c, seconds: 1, rng: &rng)
        #expect(abs(c.t - (100 + c.config.walkSpeed)) < 0.01)
        #expect(c.position.y == 10)
        #expect(c.animation == "walk")
    }

    @Test func turnsTheCornerOntoTheNextSide() {
        var rng = SeededRNG(state: 1)
        var c = creature(at: 990)
        run(&c, seconds: 1.5, rng: &rng)
        #expect(c.segment == 1)
        #expect(c.position.x == 1010)
        #expect(abs(c.rotation - .pi / 2) < 0.0001)
    }

    @Test func blinksOnItsOwnAndReopens() {
        var rng = SeededRNG(state: 7)
        var c = creature(at: 100)
        var seen: Set<Eyes> = []
        run(&c, seconds: 12, rng: &rng) { seen.insert($0.eyes) }
        #expect(seen == [.open, .half, .closed])
    }

    @Test func aDistantCursorIsIgnored() {
        var rng = SeededRNG(state: 3)
        var c = creature(at: 100)
        run(&c, seconds: 2, cursor: CGPoint(x: 500, y: 400), rng: &rng) { #expect(!$0.isJumping) }
    }

    @Test(arguments: 1...40)
    func aNearCursorMakesItJumpToADifferentSide(seed: Int) {
        var rng = SeededRNG(state: UInt64(seed))
        var c = creature(at: CGFloat(seed * 79))
        let before = c.segment
        c.update(dt: 1.0 / 30, cursor: c.position, using: &rng)
        #expect(c.isJumping)
        #expect(c.animation == "jump")
        run(&c, seconds: 1.2, rng: &rng)
        #expect(!c.isJumping)
        #expect(c.segment != before)
        #expect(c.position == loop.point(at: c.t))
        #expect(abs(Creature.shortestArc(from: c.rotation, to: c.restingRotation)) < 0.0001)
    }

    @Test func squashesOnLandingThenWalksAgain() {
        var rng = SeededRNG(state: 5)
        var c = creature(at: 100)
        c.startle(using: &rng)
        var animations: [String] = []
        run(&c, seconds: 1.5, rng: &rng) { if animations.last != $0.animation { animations.append($0.animation) } }
        #expect(animations == ["jump", "land", "walk"])
    }

    @Test func staysInsideTheScreenWhileJumping() {
        var rng = SeededRNG(state: 11)
        var c = creature(at: 100)
        for _ in 0..<25 {
            c.startle(using: &rng)
            run(&c, seconds: 1.2, rng: &rng) {
                #expect(CGRect(x: 9.5, y: 9.5, width: 1001, height: 601).contains($0.position))
            }
        }
    }

    @Test func isNotCatchableMidAir() {
        var rng = SeededRNG(state: 2)
        var c = creature(at: 100)
        c.startle(using: &rng)
        guard case .jumping(let first) = c.mode else { Issue.record("not jumping"); return }
        c.update(dt: 1.0 / 30, cursor: c.position, using: &rng)
        guard case .jumping(let second) = c.mode else { Issue.record("not jumping"); return }
        #expect(second.to == first.to)
    }

    @Test func survivesAMonitorBeingUnplugged() {
        var rng = SeededRNG(state: 9)
        let two = EdgeWorld(screens: [CGRect(x: 0, y: 0, width: 1000, height: 600),
                                      CGRect(x: 1000, y: 0, width: 1000, height: 600)], inset: 10)
        var c = Creature(world: two, spot: two.nearest(to: CGPoint(x: 1700, y: 10)))
        c.startle(using: &rng)
        let one = EdgeWorld(screens: [CGRect(x: 0, y: 0, width: 1000, height: 600)], inset: 10)
        c.rehome(to: one)
        #expect(!c.isJumping)
        #expect(c.position == one.point(at: c.spot))
        #expect(CGRect(x: 10, y: 10, width: 980, height: 580).contains(c.position) || c.position.x == 990)
    }

    @Test func walksFromOneMonitorOntoTheNext() {
        var rng = SeededRNG(state: 4)
        let two = EdgeWorld(screens: [CGRect(x: 0, y: 0, width: 1000, height: 600),
                                      CGRect(x: 1000, y: 0, width: 1000, height: 600)], inset: 10)
        var c = Creature(world: two, spot: two.nearest(to: CGPoint(x: 980, y: 10)))
        c.config.walkSpell = 100...100
        c.rehome(to: two)
        run(&c, seconds: 2, rng: &rng)
        #expect(c.position.x > 1000)          // crossed the seam without noticing it
        #expect(c.position.y == 10)
    }

    @Test(arguments: 1...20)
    func jumpsCanLandOnAnotherMonitor(seed: Int) {
        var rng = SeededRNG(state: UInt64(seed))
        let apart = EdgeWorld(screens: [CGRect(x: 0, y: 0, width: 1000, height: 600),
                                        CGRect(x: 1000, y: 600, width: 1000, height: 600)], inset: 10)
        var c = Creature(world: apart)
        var visited: Set<Int> = []
        for _ in 0..<12 {
            c.startle(using: &rng)
            run(&c, seconds: 1.2, rng: &rng)
            visited.insert(c.spot.loop)
        }
        #expect(visited == [0, 1])
    }

    @Test func fallsAsleepAtNightWithItsEyesShut() {
        var rng = SeededRNG(state: 6)
        var c = creature(at: 100)
        run(&c, seconds: 8, night: true, rng: &rng)
        #expect(c.isSleeping)
        #expect(c.animation == "sleep")
        let where_ = c.position
        run(&c, seconds: 20, night: true, rng: &rng) { #expect($0.eyes == .closed) }
        #expect(c.position == where_)
    }

    @Test func wakesUpWhenDayBreaks() {
        var rng = SeededRNG(state: 6)
        var c = creature(at: 100)
        run(&c, seconds: 8, night: true, rng: &rng)
        run(&c, seconds: 4, night: false, rng: &rng)
        #expect(!c.isSleeping)
        #expect(c.animation == "walk" || c.animation == "idle")
    }

    @Test func aSleeperIgnoresTheCursorSoItCanBePickedUp() {
        var rng = SeededRNG(state: 8)
        var c = creature(at: 100)
        run(&c, seconds: 8, night: true, rng: &rng)
        run(&c, seconds: 2, cursor: c.position, night: true, rng: &rng) { #expect($0.isSleeping) }
    }

    @Test func shiftClickPutsItToSleepInBroadDaylightAndItStaysAsleep() {
        var rng = SeededRNG(state: 8)
        var c = creature(at: 100)
        c.toggleNap(using: &rng)
        #expect(c.isSleeping && c.isNapping)
        run(&c, seconds: 30, night: false, rng: &rng) { #expect($0.isSleeping) }
    }

    @Test func shiftClickingASleeperWakesIt() {
        var rng = SeededRNG(state: 8)
        var c = creature(at: 100)
        c.toggleNap(using: &rng)
        c.toggleNap(using: &rng)
        #expect(!c.isSleeping && !c.isNapping)
        #expect(c.animation == "walk")
    }

    @Test func theNextDawnEndsANap() {
        var rng = SeededRNG(state: 8)
        var c = creature(at: 100)
        c.toggleNap(using: &rng)
        run(&c, seconds: 3, night: true, rng: &rng)
        run(&c, seconds: 5, night: false, rng: &rng)
        #expect(!c.isSleeping)
    }

    @Test func anAwakeCreatureCannotBePickedUp() {
        var c = creature(at: 100)
        let picked = c.pickUp()
        #expect(!picked)
        #expect(!c.isHeld)
    }

    @Test func aSleeperCanBeCarriedAndDropsToTheNearestEdgeStillAsleep() {
        var rng = SeededRNG(state: 8)
        var c = creature(at: 100)
        c.toggleNap(using: &rng)
        let picked = c.pickUp()
        #expect(picked)
        c.drag(to: CGPoint(x: 700, y: 560))              // near the ceiling, mid-air
        run(&c, seconds: 1, cursor: c.position, rng: &rng) { held in
            #expect(held.isHeld)
            #expect(held.position == CGPoint(x: 700, y: 560))
            #expect(held.eyes == .closed)
        }
        c.drop()
        run(&c, seconds: 1.5, rng: &rng) { falling in
            #expect(falling.looksAsleep)
            #expect(falling.eyes == .closed)
        }
        #expect(c.isSleeping && !c.isHeld)
        #expect(c.position == CGPoint(x: 700, y: 610))   // straight up onto the ceiling
        #expect(abs(c.rotation - .pi) < 0.0001)
        run(&c, seconds: 10, night: false, rng: &rng) { #expect($0.isSleeping) }   // still a nap
    }

    @Test func aCarriedSleeperCanBeDroppedOnAnotherMonitor() {
        var rng = SeededRNG(state: 8)
        let two = EdgeWorld(screens: [CGRect(x: 0, y: 0, width: 1000, height: 600),
                                      CGRect(x: 1000, y: 0, width: 1000, height: 600)], inset: 10)
        var c = Creature(world: two, spot: two.nearest(to: CGPoint(x: 200, y: 10)))
        c.toggleNap(using: &rng)
        c.pickUp()
        c.drag(to: CGPoint(x: 1960, y: 300))
        c.drop()
        run(&c, seconds: 1.5, rng: &rng)
        #expect(c.position == CGPoint(x: 1990, y: 300))
        #expect(c.isSleeping)
    }

    @Test func shortestArcGoesTheShortWayRound() {
        #expect(abs(Creature.shortestArc(from: 3 * .pi / 2, to: 0) - .pi / 2) < 1e-9)
        #expect(abs(Creature.shortestArc(from: 0, to: 3 * .pi / 2) + .pi / 2) < 1e-9)
    }
}

@Suite struct MeetingBehaviourTests {
    let world = EdgeWorld(screens: [CGRect(x: 0, y: 0, width: 1020, height: 620)], inset: 10)
    func creature(at t: CGFloat) -> Creature { Creature(world: world, spot: .init(loop: 0, t: t)) }

    func run(_ creature: inout Creature, seconds: Double, cursor: CGPoint? = nil, rng: inout SeededRNG) {
        for _ in 0..<Int(seconds * 30) { creature.update(dt: 1.0 / 30, cursor: cursor, using: &rng) }
    }

    @Test func meetingStopsItFacingTheOtherAndWalkingOnRestoresItsCourse() {
        var rng = SeededRNG(state: 3)
        var c = creature(at: 200)
        #expect(c.direction == 1)
        c.meet(facing: -1)
        let stood = c.position
        #expect(c.isChatting)
        #expect(c.isMirrored, "turned round to face the one behind it")
        #expect(c.animation == "land", "a little squash on impact")
        run(&c, seconds: 1, rng: &rng)
        #expect(c.position == stood)
        #expect(c.animation == "idle")
        c.walkOn(using: &rng)
        #expect(!c.isChatting)
        #expect(c.direction == 1, "back on its old course, not the way it turned to chat")
        run(&c, seconds: 1, rng: &rng)
        #expect(c.position != stood)
    }

    @Test func aChatEndsOnItsOwnAfterItsTimeLimit() {
        var rng = SeededRNG(state: 4)
        var c = creature(at: 200)
        c.meet(facing: 1, for: 2)
        run(&c, seconds: 1.5, rng: &rng)
        #expect(c.isChatting)
        run(&c, seconds: 1, rng: &rng)
        #expect(!c.isChatting)
    }

    @Test func theCursorStillStartlesAChatterAway() {
        var rng = SeededRNG(state: 5)
        var c = creature(at: 200)
        c.meet(facing: 1)
        run(&c, seconds: 0.2, cursor: c.position, rng: &rng)
        #expect(c.isJumping)
        #expect(!c.isChatting)
    }

    @Test func aSleeperOrJumperCannotBePulledIntoAChat() {
        var rng = SeededRNG(state: 6)
        var c = creature(at: 200)
        c.toggleNap(using: &rng)
        c.meet(facing: 1)
        #expect(c.isSleeping && !c.isChatting)
    }
}

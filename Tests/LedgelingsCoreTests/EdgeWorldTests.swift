import CoreGraphics
import Testing
@testable import LedgelingsCore

@Suite struct EdgeLoopTests {
    let loop = EdgeLoop(rect: CGRect(x: 10, y: 10, width: 1000, height: 600))

    @Test func runsCounterClockwiseFromTheBottomLeftCorner() {
        #expect(loop.length == 3200)
        #expect(loop.point(at: 500) == CGPoint(x: 510, y: 10))
        #expect(loop.point(at: 1300) == CGPoint(x: 1010, y: 310))
        #expect(loop.point(at: 2100) == CGPoint(x: 510, y: 610))
        #expect(loop.point(at: 2900) == CGPoint(x: 10, y: 310))
    }

    @Test func segmentsChangeExactlyAtCorners() {
        #expect(loop.segment(at: 999) == 0)
        #expect(loop.segment(at: 1000) == 1)
        #expect(loop.segment(at: 1600) == 2)
        #expect(loop.segment(at: 2600) == 3)
    }

    @Test func wrapsInBothDirections() {
        #expect(loop.wrap(3250) == 50)
        #expect(loop.wrap(-50) == 3150)
        #expect(loop.point(at: -300) == loop.point(at: 2900))
    }

    @Test func rotationStandsTheCreatureOnEachEdgeFacingInwards() {
        #expect(loop.rotation(ofSegment: 0) == 0)                       // floor
        #expect(abs(loop.rotation(ofSegment: 1) - .pi / 2) < 1e-9)      // right wall
        #expect(abs(loop.rotation(ofSegment: 2) - .pi) < 1e-9)          // ceiling
        #expect(abs(loop.rotation(ofSegment: 3) - 3 * .pi / 2) < 1e-9)  // left wall
        #expect(loop.inward(ofSegment: 0) == CGVector(dx: 0, dy: 1))
        #expect(loop.inward(ofSegment: 1) == CGVector(dx: -1, dy: 0))
    }

    @Test func findsTheNearestPointOnTheLoop() {
        let hit = loop.nearest(to: CGPoint(x: 400, y: 30))
        #expect(hit.t == 390)
        #expect(hit.distance == 20)
    }
}

@Suite struct EdgeWorldTests {
    @Test func oneScreenIsItsRectPulledInByTheInset() {
        let world = EdgeWorld(screens: [CGRect(x: 0, y: 0, width: 1020, height: 620)], inset: 10)
        #expect(world.loops == [EdgeLoop(rect: CGRect(x: 10, y: 10, width: 1000, height: 600))])
    }

    @Test func twoEqualScreensSideBySideBecomeOneLoopWithNoSeam() {
        let world = EdgeWorld(screens: [CGRect(x: 0, y: 0, width: 1000, height: 600),
                                        CGRect(x: 1000, y: 0, width: 1000, height: 600)], inset: 10)
        #expect(world.loops == [EdgeLoop(rect: CGRect(x: 10, y: 10, width: 1980, height: 580))])
    }

    /// A tall screen on the left, a short one on the right, floors level:
    ///
    ///     +------+
    ///     |      +------+
    ///     |      :      |
    ///     +------+------+
    @Test func aShorterNeighbourMakesAnOutsideCornerToWalkRound() {
        let world = EdgeWorld(screens: [CGRect(x: 0, y: 0, width: 1000, height: 800),
                                        CGRect(x: 1000, y: 0, width: 600, height: 500)], inset: 10)
        #expect(world.loops.count == 1)
        #expect(world.loops[0].vertices == [
            CGPoint(x: 10, y: 10), CGPoint(x: 1590, y: 10), CGPoint(x: 1590, y: 490),
            CGPoint(x: 990, y: 490),      // under the short screen's ceiling, reaching the tall one...
            CGPoint(x: 990, y: 790),      // ...then up the tall screen's wall
            CGPoint(x: 10, y: 790),
        ])
    }

    @Test func negativeCoordinatesWorkBecauseSecondaryScreensHaveThem() {
        let world = EdgeWorld(screens: [CGRect(x: 0, y: 0, width: 1000, height: 600),
                                        CGRect(x: -800, y: -200, width: 800, height: 600)], inset: 10)
        #expect(world.loops.count == 1)
        #expect(world.loops[0].vertices.count == 8)
        #expect(world.loops[0].vertices.first == CGPoint(x: -790, y: -190))
    }

    @Test func screensTouchingOnlyAtACornerStaySeparateLoops() {
        let world = EdgeWorld(screens: [CGRect(x: 0, y: 0, width: 1000, height: 600),
                                        CGRect(x: 1000, y: 600, width: 1000, height: 600)], inset: 10)
        #expect(world.loops.count == 2)
    }

    @Test func nearestPicksTheRightLoop() {
        let world = EdgeWorld(screens: [CGRect(x: 0, y: 0, width: 1000, height: 600),
                                        CGRect(x: 1000, y: 600, width: 1000, height: 600)], inset: 10)
        #expect(world.nearest(to: CGPoint(x: 1500, y: 1195)).loop == 1)
        #expect(world.nearest(to: CGPoint(x: 500, y: 0)).loop == 0)
    }

    @Test func anAbsurdInsetStillLeavesALoop() {
        let world = EdgeWorld(screens: [CGRect(x: 0, y: 0, width: 40, height: 40)], inset: 500)
        #expect(world.loops[0].length > 0)
    }
}

@Suite struct DayNightTests {
    let clock = DayNight(day: 180, night: 300)

    @Test func threeMinutesOfDayThenFiveOfNightForever() {
        #expect(!clock.isNight(at: 0))
        #expect(!clock.isNight(at: 179))
        #expect(clock.isNight(at: 180))
        #expect(clock.isNight(at: 479))
        #expect(!clock.isNight(at: 480))
        #expect(clock.isNight(at: 480 + 200))
    }

    @Test func skippingLandsAtTheStartOfTheOtherHalf() {
        #expect(clock.skippingToNextPhase(from: 50) == 180)
        #expect(clock.skippingToNextPhase(from: 200) == 480)
        #expect(clock.remaining(at: 200) == 280)
    }

    @Test func aZeroLengthNightMeansTheyNeverSleep() {
        #expect(!DayNight(day: 60, night: 0).isNight(at: 59.9))
        #expect(!DayNight(day: 60, night: 0).isNight(at: 60))
    }
}

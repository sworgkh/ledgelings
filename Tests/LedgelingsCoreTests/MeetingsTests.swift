import CoreGraphics
import Testing
@testable import LedgelingsCore

@Suite struct MeetingsTests {
    /// Two creatures of body half-size 10 on the bottom edge, `gap` points apart.
    func pair(gap: CGFloat, segment: (Int, Int) = (0, 0), loop: (Int, Int) = (0, 0),
              canTalk: (Bool, Bool) = (true, true)) -> [Meetings.Party] {
        [Meetings.Party(loop: loop.0, segment: segment.0, position: CGPoint(x: 100, y: 10), halfSize: 10, canTalk: canTalk.0),
         Meetings.Party(loop: loop.1, segment: segment.1, position: CGPoint(x: 120 + gap, y: 10), halfSize: 10, canTalk: canTalk.1)]
    }

    @Test func walkingIntoEachOtherBumpsOnceNotEveryFrame() {
        var meetings = Meetings()
        #expect(meetings.update(pair(gap: 40), at: 0).isEmpty)
        let bumps = meetings.update(pair(gap: 4), at: 1)
        #expect(bumps == [Meetings.Bump(a: 0, b: 1, count: 1, gift: false)])
        #expect(meetings.update(pair(gap: 2), at: 1.1).isEmpty)
        #expect(meetings.update(pair(gap: 0), at: 1.2).isEmpty)
    }

    @Test func onlyCreaturesOnTheSameEdgeOfTheSameMonitorBump() {
        var meetings = Meetings()
        #expect(meetings.update(pair(gap: 0, segment: (0, 1)), at: 1).isEmpty)
        #expect(meetings.update(pair(gap: 0, loop: (0, 1)), at: 2).isEmpty)
    }

    @Test func aSleeperOrJumperDoesNotBump() {
        var meetings = Meetings()
        #expect(meetings.update(pair(gap: 0, canTalk: (true, false)), at: 1).isEmpty)
    }

    @Test func aPairWaitsOutTheCooldownBeforeBumpingAgain() {
        var meetings = Meetings(cooldown: 60)
        #expect(meetings.update(pair(gap: 0), at: 0).count == 1)
        #expect(meetings.update(pair(gap: 100), at: 10).isEmpty)
        #expect(meetings.update(pair(gap: 0), at: 20).isEmpty)          // too soon
        #expect(meetings.update(pair(gap: 100), at: 30).isEmpty)
        #expect(meetings.update(pair(gap: 0), at: 61).count == 1)      // cooldown over
    }

    @Test func theThirdBumpIsAGiftAndTheCountStartsOver() {
        var meetings = Meetings(cooldown: 0, giftEvery: 3)
        var seen: [Meetings.Bump] = []
        for i in 0..<4 {
            let t = Double(i * 10)
            seen += meetings.update(pair(gap: 0), at: t)
            #expect(meetings.update(pair(gap: 100), at: t + 5).isEmpty)
        }
        #expect(seen.map(\.count) == [1, 2, 3, 1])
        #expect(seen.map(\.gift) == [false, false, true, false])
    }

    @Test func threeOnOneEdgeReportEveryTouchingPair() {
        var meetings = Meetings()
        var three = pair(gap: 0)
        three.append(Meetings.Party(loop: 0, segment: 0, position: CGPoint(x: 140, y: 10), halfSize: 10, canTalk: true))
        let bumps = meetings.update(three, at: 1)
        #expect(bumps.map { [$0.a, $0.b] } == [[0, 1], [1, 2]])
    }
}

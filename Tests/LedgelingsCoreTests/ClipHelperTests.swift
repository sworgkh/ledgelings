import Foundation
import Testing
@testable import LedgelingsCore

/// SPEC §7.11.1: who brings the clipboard picker, where it holds the paper, and its leap.
@Suite struct ClipHelperTests {
    typealias C = ClipHelper.Candidate

    @Test func theNamedOneComesWhenFreeElseTheNearestAwakeOne() {
        let centre = CGPoint(x: 500, y: 400)
        let all = [C(name: "Blocky", position: CGPoint(x: 0, y: 0), asleep: false, free: true),
                   C(name: "Zed", position: CGPoint(x: 480, y: 400), asleep: true, free: true),
                   C(name: "Pip", position: CGPoint(x: 900, y: 400), asleep: false, free: true),
                   C(name: "Dot", position: CGPoint(x: 500, y: 390), asleep: false, free: false)]
        #expect(ClipHelper.choose(all, centre: centre, wanted: "") == 2, "awake before asleep; Dot is busy")
        #expect(ClipHelper.choose(all, centre: centre, wanted: "Blocky") == 0)
        #expect(ClipHelper.choose(all, centre: centre, wanted: "Dot") == 2, "the named one is busy: the nearest comes")
        #expect(ClipHelper.choose(Array(all[1...1]), centre: centre, wanted: "") == 0, "a sleeper, when nobody else is free")
        #expect(ClipHelper.choose([all[3]], centre: centre, wanted: "") == nil)
    }

    @Test func itPerchesOverThePapersTopLeftCorner() {
        let paper = CGRect(x: 100, y: 200, width: 600, height: 484)
        let p = ClipHelper.perch(paper: paper, half: 20)
        #expect(p.x < paper.minX && p.x > paper.minX - 20)
        #expect(p.y > paper.maxY && p.y < paper.maxY + 20)
    }

    @Test func aLeapCrouchesArcsAndLands() {
        var leap = ClipHelper.Leap(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 400, y: 300), flight: 0.2)
        #expect(leap.pose == "land" && leap.position == CGPoint(x: 0, y: 0))
        leap.update(dt: ClipHelper.Leap.crouch + 0.1)
        #expect(leap.pose == "jump")
        #expect(leap.rotation < -3 && leap.rotation > -3.3, "half a flip, turning the way it travels")
        #expect(abs(leap.position.x - 200) < 0.01)
        #expect(leap.position.y > 300, "halfway, it is over the higher end")
        leap.update(dt: 1)
        #expect(leap.isDone && leap.pose == "idle" && leap.position == CGPoint(x: 400, y: 300))
        #expect(leap.rotation == 0, "upright once landed")
    }

    @Test func aLeapIsQuickAndFollowsTheSpeed() {
        #expect(ClipHelper.flight(distance: 0, speed: 1) == 0.14)
        #expect(ClipHelper.flight(distance: 1440, speed: 1) < 0.4)
        #expect(ClipHelper.flight(distance: 99_999, speed: 1) == 0.4)
        #expect(ClipHelper.flight(distance: 600, speed: 2) == ClipHelper.flight(distance: 600, speed: 1) / 2)
    }

    @Test func everyCharacterHasItsLinesInEveryLanguage() {
        for language in Language.allCases {
            for name in BedsTests.shipped {
                #expect(ClipHelper.lineSets(language)[name]?.count == 2, "\(name) \(language)")
            }
            #expect(!ClipHelper.anyoneLines(language).isEmpty)
        }
        var rng = SystemRandomNumberGenerator()
        #expect(ClipHelper.englishAnyone.contains(Language.$override.withValue(.english) { ClipHelper.line(by: "Stranger", using: &rng) }))
    }
}

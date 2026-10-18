import CoreGraphics
import Testing
@testable import LedgelingsCore

/// Which monitors the colony lives on, and the spring off a monitor it leaves.
@Suite struct HomeScreenTests {
    let left = HomeScreen.Monitor(id: "A", name: "DELL U2415 (1)", frame: CGRect(x: -1920, y: 0, width: 1920, height: 1200))
    let laptop = HomeScreen.Monitor(id: "B", name: "Built-in Retina Display", frame: CGRect(x: 0, y: 0, width: 1728, height: 1117))

    @Test func allIsEveryMonitorAndAChosenOneIsJustThatOne() {
        #expect(HomeScreen.home(HomeScreen.all, among: [left, laptop]) == [left, laptop])
        #expect(HomeScreen.home("B", among: [left, laptop]) == [laptop])
        #expect(!HomeScreen.isAway("B", among: [left, laptop]) && !HomeScreen.isAway(HomeScreen.all, among: [left]))
    }

    @Test func anUnpluggedChoiceMeansEveryMonitorLeftUntilItIsBack() {
        #expect(HomeScreen.home("B", among: [left]) == [left], "the laptop is shut: they live on what is left")
        #expect(HomeScreen.isAway("B", among: [left]))
        #expect(HomeScreen.home("B", among: [laptop, left]) == [laptop], "plugged back in, the choice applies again")
    }

    @Test func homeIsInsideAHomeMonitorWithAsMuchSlackAsAsked() {
        let home = [laptop.frame]
        #expect(HomeScreen.isHome(CGPoint(x: 10, y: 10), in: home, slack: 0))
        #expect(!HomeScreen.isHome(CGPoint(x: -10, y: 10), in: home, slack: 0))
        #expect(HomeScreen.isHome(CGPoint(x: -10, y: 10), in: home, slack: 12))
    }

    @Test func theHopCrouchesThenSpringsOutThroughTheTopTurningOnceRound() {
        var hop = HomeScreen.Hop(from: CGPoint(x: 100, y: 20), rotation: 0, gone: 1300, way: 1)
        hop.update(dt: 0.1)
        #expect(hop.position == CGPoint(x: 100, y: 20) && hop.pose == "land", "a crouch first")
        var last = hop.position.y, steps = 0
        while !hop.isGone && steps < 1000 {
            hop.update(dt: 1.0 / 30); steps += 1
            #expect(hop.position.y >= last, "still going up when it leaves the screen")
            last = hop.position.y
        }
        #expect(hop.isGone && hop.position.y >= 1300 && hop.pose == "jump")
        #expect(abs(abs(hop.rotation) - HomeScreen.Hop.spin) < 0.3, "one turn by the time it is gone")
        #expect(hop.flightTime > 0.3 && hop.flightTime < 2, "quick, but seen")
        #expect(Double(steps) / 30 < HomeScreen.Hop.crouch + hop.flightTime + 0.1)
    }

    @Test func aSleeperCanBeWokenToTakeOffAGameCannot() {
        let world = EdgeWorld(screens: [CGRect(x: 0, y: 0, width: 800, height: 600)], inset: 20)
        var c = Creature(world: world, spot: .init(loop: 0, t: 100), facingForwards: true)
        c.settle()
        #expect(c.looksAsleep)
        let forAGame = c.takeOff()
        #expect(!forAGame, "a game never wakes anyone")
        let forAMove = c.takeOff(waking: true)
        #expect(forAMove && c.isPlaying && !c.looksAsleep)
    }
}

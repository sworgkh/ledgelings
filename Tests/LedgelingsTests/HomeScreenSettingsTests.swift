import AppKit
import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// The `homeScreen` setting, and the colony on two monitors keeping to the one chosen.
@MainActor
@Suite(.serialized) struct HomeScreenSettingsTests {
    static let suite = "ledgelings-home-screen-tests"
    static let left = Display(frame: CGRect(x: 0, y: 0, width: 800, height: 600), scale: 1, id: "L", name: "Left")
    static let right = Display(frame: CGRect(x: 800, y: 0, width: 800, height: 500), scale: 1, id: "R", name: "Right")
    static let rightMonitor = HomeScreen.Monitor(id: "R", name: "Right", frame: right.frame)

    @Test func everyScreenByDefaultAndAChoiceSurvivesARelaunch() {
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        defer { defaults.removePersistentDomain(forName: Self.suite) }
        let s = AppSettings(defaults: defaults, keychain: Keychain(service: Self.suite))
        #expect(s.homeScreen == HomeScreen.all && s.homeScreenName.isEmpty)
        s.liveOn(Self.rightMonitor)
        let again = AppSettings(defaults: defaults, keychain: Keychain(service: Self.suite))
        #expect(again.homeScreen == "R" && again.homeScreenName == "Right")
        again.liveOn(nil)
        #expect(AppSettings(defaults: defaults, keychain: Keychain(service: Self.suite)).homeScreen == HomeScreen.all)
    }

    @MainActor final class World {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-home-\(UUID().uuidString)")
        let defaults: UserDefaults
        let settings: AppSettings
        let colony: Colony
        init(count: Int = 6, stages: [Display] = [left, right]) throws {
            defaults = UserDefaults(suiteName: HomeScreenSettingsTests.suite)!
            defaults.removePersistentDomain(forName: HomeScreenSettingsTests.suite)
            settings = AppSettings(defaults: defaults, keychain: SettingsTests.SpyStore())
            settings.creatureCount = count
            settings.brain = .script
            settings.talkEnabled = false
            settings.playEnabled = false
            colony = try Colony(settings: settings, history: ChatHistory(directory: dir.appendingPathComponent("chats")),
                                library: SpriteLibrary(directory: dir.appendingPathComponent("sprites")),
                                spend: SpendLedger(directory: dir.appendingPathComponent("spend")), stages: stages)
            colony.meetings = Meetings(gap: -1e6)
        }
        func step(_ seconds: Double, cursor: CGPoint = CGPoint(x: -5000, y: -5000)) {
            var left = seconds
            while left > 0 { colony.advance(dt: min(left, 0.05), cursor: cursor, shift: true); left -= 0.05 }
        }
        func choose(_ monitor: HomeScreen.Monitor?) { settings.liveOn(monitor); colony.applySettings() }
        func forget() {
            defaults.removePersistentDomain(forName: HomeScreenSettingsTests.suite)
            try? FileManager.default.removeItem(at: dir)
        }
    }

    @Test func choosingAMonitorSendsEveryoneOverByParachuteAndTheyStayThere() throws {
        let w = try World()
        defer { w.forget() }
        // Two on the left monitor for sure.
        let leftWorld = w.colony.world(forSize: w.colony.sizes[0])
        w.colony.creatures[0].rehome(to: leftWorld)
        var lines: [String] = []
        w.colony.trace = { lines.append($0) }
        w.choose(Self.rightMonitor)
        #expect(w.colony.homeFrames == [Self.right.frame])
        #expect(w.colony.worlds.values.allSatisfy { world in world.loops.allSatisfy { $0.length < 2 * (800 + 500) } }, "edges of the right monitor only")
        let movers = Set(w.colony.moves.keys)
        #expect(!movers.isEmpty && movers.isSubset(of: w.colony.busy), "movers are busy: nothing else starts with them")
        #expect(lines.contains { $0.hasPrefix("move") && $0.contains("hops off Left") })
        w.step(1)
        #expect(movers.allSatisfy { w.colony.creatures[$0].isPlaying }, "in the air, not teleported")
        w.step(15)
        #expect(w.colony.moves.isEmpty && w.colony.busy.isEmpty)
        #expect(w.colony.creatures.allSatisfy { Self.right.frame.contains($0.position) }, "everyone on the right monitor")
        #expect(lines.contains { $0.contains("comes down") } && lines.contains { $0.contains("lands at") })
        w.step(30)
        #expect(w.colony.creatures.allSatisfy { Self.right.frame.contains($0.position) }, "and they stay")
        for _ in 0..<5 { w.colony.startleEveryone(); w.step(3) }
        #expect(w.colony.creatures.allSatisfy { Self.right.frame.contains($0.position) }, "even jumping")
    }

    @Test func whileTheChosenMonitorIsAwayTheyLiveOnEveryOneAndTheChoiceIsKept() throws {
        let w = try World(stages: [Self.left])
        defer { w.forget() }
        w.choose(Self.rightMonitor)
        #expect(w.colony.homeFrames == [Self.left.frame], "the right one is unplugged: all that is left")
        #expect(w.colony.moves.isEmpty, "nobody moves for a monitor that is not there")
        #expect(w.settings.homeScreen == "R", "the choice is kept for when it is back")
    }

    @Test func theCursorIsOnlyGrabbedOnTheHomeMonitorAndLetGoWhenItLeaves() throws {
        let w = try World(count: 2)
        defer { w.forget() }
        w.choose(Self.rightMonitor)
        w.step(16)
        w.settings.complainEnabled = false
        w.settings.huntTalkEnabled = false
        w.settings.revengeAfter = 3
        w.colony.applySettings()
        w.colony.pointer = nil
        w.colony.mouseIsDown = { false }
        w.colony.pointerLocation = { CGPoint(x: 300, y: 300) }       // on the left monitor
        for _ in 0..<3 { w.colony.bothered(0) }
        #expect(w.colony.grab == nil, "not while the cursor is off their monitor")
        w.colony.revengeFuse = Revenge.Fuse()
        w.colony.revengeFuse.after = 3
        w.colony.pointerLocation = { CGPoint(x: 1200, y: 300) }      // on the right one
        for _ in 0..<3 { w.colony.bothered(1) }
        #expect(w.colony.grab?.index == 1)
        var lines: [String] = []
        w.colony.trace = { lines.append($0) }
        w.step(0.1, cursor: CGPoint(x: 1200, y: 300))
        #expect(w.colony.grab != nil)
        w.step(0.1, cursor: CGPoint(x: 300, y: 300))
        #expect(w.colony.grab == nil && lines.contains { $0.contains("leftHome") }, "ridden off their monitor, it lets go")
        w.step(3)
        #expect(Self.right.frame.contains(w.colony.creatures[1].position), "and drops back onto it")
    }

    @Test func planesTheHouseAndTheGardenKeepToTheHomeMonitor() throws {
        let w = try World(count: 2)
        defer { w.forget() }
        w.choose(Self.rightMonitor)
        var plane = PaperPlane(from: 0, to: 1, start: CGPoint(x: 900, y: 100), inward: CGVector(dx: 0, dy: 1), target: CGPoint(x: 1400, y: 100))
        w.colony.keepOnScreen(&plane, scale: 2)
        #expect(plane.sky == [Self.right.frame])
        #expect(Self.right.frame.contains(CGPoint(x: w.colony.doorPoint.x, y: w.colony.doorPoint.y + 1)), "the house stands on it")
    }

    @Test func theSheetShowsWhichScreenInFewWords() {
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        defer { defaults.removePersistentDomain(forName: Self.suite) }
        let s = AppSettings(defaults: defaults, keychain: Keychain(service: Self.suite))
        #expect(ActionsController.screenTitle(s) == "SCREEN: ALL")
        s.liveOn(HomeScreen.Monitor(id: "gone", name: "Old TV", frame: .zero))
        #expect(ActionsController.screenTitle(s) == "SCREEN: ALL", "unplugged: they are on all of them")
        #expect(ScreenChoice.current(s).hasPrefix("Old TV (unplugged"))
        if let attached = ScreenChoice.attached.first {
            s.liveOn(attached)
            #expect(ActionsController.screenTitle(s).hasPrefix("SCREEN: "))
            #expect(ScreenChoice.said(s).contains("only"))
        }
    }
}

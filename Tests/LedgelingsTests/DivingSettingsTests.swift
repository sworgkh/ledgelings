import AppKit
import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// Scuba diving in the colony and its settings, and the shared Stop activity:
/// the dive never starts on its own, covers the set share of the screen, and
/// Stop activity (or using the computer) clears everything at once.
@MainActor
@Suite(.serialized) struct DivingSettingsTests {
    static let suite = "ledgelings-diving-tests"

    @MainActor final class World {
        let dir: URL
        let defaults: UserDefaults
        let settings: AppSettings
        let colony: Colony
        init(count: Int = 4) throws {
            dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-dive-\(UUID().uuidString)")
            defaults = UserDefaults(suiteName: DivingSettingsTests.suite)!
            defaults.removePersistentDomain(forName: DivingSettingsTests.suite)
            settings = AppSettings(defaults: defaults, keychain: SettingsTests.SpyStore())
            settings.creatureCount = count
            settings.brain = .script
            settings.planesEnabled = false
            settings.teaPartiesEnabled = false
            settings.nightMinutes = 0
            colony = try Colony(settings: settings, history: ChatHistory(directory: dir.appendingPathComponent("chats")),
                                library: SpriteLibrary(directory: dir.appendingPathComponent("sprites")),
                                spend: SpendLedger(directory: dir.appendingPathComponent("spend")),
                                bonds: BondBook(directory: dir),
                                stage: Display(frame: CGRect(x: 0, y: 0, width: 1200, height: 800), scale: 1))
            colony.meetings = Meetings(gap: -1e6)
        }
        func step(_ seconds: Double) {
            var left = seconds
            while left > 0 { colony.advance(dt: min(left, 0.05), cursor: CGPoint(x: -500, y: -500), shift: true); left -= 0.05 }
        }
        func forget() {
            Activities.shared.unregister(.dive); Activities.shared.unregister(.game)
            defaults.removePersistentDomain(forName: DivingSettingsTests.suite)
            try? FileManager.default.removeItem(at: dir)
        }
    }

    @Test func theDefaultsAndAChangeSurviveARelaunch() {
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        defer { defaults.removePersistentDomain(forName: Self.suite) }
        let s = AppSettings(defaults: defaults, keychain: SettingsTests.SpyStore())
        #expect(abs(s.diveWaterShare - 1.0 / 3) < 1e-9 && s.diveWaterOpacity == 0.3 && s.diveMinutes == 3)
        #expect(s.diveDivers == 3 && s.diveSeaLife == 12 && !s.diveAllScreens && s.diveTalk)
        #expect(s.stopActivityShortcutEnabled && s.stopActivityShortcut == .stopActivity && s.stopOnUse)
        s.diveWaterShare = 0.5; s.diveWaterOpacity = 0.6; s.diveMinutes = 8; s.diveDivers = 6; s.diveSeaLife = 30
        s.diveAllScreens = true; s.diveTalk = false; s.stopOnUse = false; s.stopActivityShortcutEnabled = false
        s.stopActivityShortcut = Shortcut(keyCode: 47, modifiers: [.control, .option])
        let again = AppSettings(defaults: defaults, keychain: SettingsTests.SpyStore())
        #expect(again.diveWaterShare == 0.5 && again.diveWaterOpacity == 0.6 && again.diveMinutes == 8)
        #expect(again.diveDivers == 6 && again.diveSeaLife == 30 && again.diveAllScreens && !again.diveTalk)
        #expect(!again.stopOnUse && !again.stopActivityShortcutEnabled && again.stopActivityShortcut == Shortcut(keyCode: 47, modifiers: [.control, .option]))
        for (key, value) in [("diveWaterShare", 0.99), ("diveWaterOpacity", 1.0), ("diveMinutes", 999.0)] { defaults.set(value, forKey: key) }
        defaults.set(50, forKey: "diveDivers"); defaults.set(0, forKey: "diveSeaLife")
        let clamped = AppSettings(defaults: defaults, keychain: SettingsTests.SpyStore())
        #expect(clamped.diveWaterShare == 0.6 && clamped.diveWaterOpacity == 0.7 && clamped.diveMinutes == 15, "clamped on load")
        #expect(clamped.diveDivers == 8 && clamped.diveSeaLife == 3)
    }

    @Test func stopActivityIsATakenShortcutWhoseKeyCanBeChanged() {
        #expect(Shortcut.stopActivity == Shortcut(keyCode: 53, modifiers: [.control, .option]), "⌃⌥⎋")
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        defer { defaults.removePersistentDomain(forName: Self.suite) }
        let s = AppSettings(defaults: defaults, keychain: SettingsTests.SpyStore())
        // A key nobody else would hold, so the system takes it.
        s.stopActivityShortcut = Shortcut(keyCode: 105, modifiers: [.command, .shift, .option, .control])
        var pressed = 0
        let held = GlobalShortcut(settings: s, enabled: s.$stopActivityShortcutEnabled, shortcut: s.$stopActivityShortcut,
                                  problem: { s.stopActivityShortcutProblem = $0 }, pressed: { pressed += 1 })
        #expect(s.stopActivityShortcutProblem.isEmpty, "registered")
        s.stopActivityShortcut = Shortcut(keyCode: 107, modifiers: [.command, .shift, .option, .control])
        #expect(s.stopActivityShortcutProblem.isEmpty, "and again under its new key")
        _ = held
        #expect(SettingsIndex.sections.contains { $0.page == .diving && $0.keys.contains("stopActivityShortcutKeyCode") })
    }

    @Test func aDiveNeverStartsOnItsOwn() throws {
        let w = try World()
        defer { w.forget() }
        w.settings.playEveryMinutes = 1
        w.step(30 * 60)
        #expect(w.colony.dive == nil, "half an hour with games every minute and no dive")
    }

    @Test func theWaterCoversTheSetShareAndTheDiversGoInGeared() throws {
        let w = try World()
        defer { w.forget() }
        w.settings.diveWaterShare = 0.4
        w.settings.diveDivers = 2
        #expect(w.colony.startDive())
        #expect(!w.colony.startDive(), "one at a time")
        w.step(Dive.riseSeconds + 3)
        let dive = try #require(w.colony.dive)
        #expect(abs(dive.model.water(0).height - 800 * 0.4) < 0.01)
        #expect(dive.model.divers.count == 2 && dive.model.divers.allSatisfy { w.colony.creatures[$0.index].isPlaying })
        let gear = w.colony.diveProps().filter { $0.image != nil }
        #expect(gear.count >= 4, "a mask and a tank each")
        #expect(!w.colony.waterSnapshots().isEmpty && w.colony.overlays[0].hasWater)
        #expect(!w.colony.takesClick(at: CGPoint(x: 1150, y: 150), shift: false), "the water lets clicks through")
    }

    @Test func stopActivityClearsADiveAndAGameWithinHalfASecond() throws {
        let w = try World()
        defer { w.forget() }
        let activities = Activities.shared
        let colony = w.colony
        activities.register(.dive, isRunning: { colony.isDiving }, stop: { colony.stopDive() })
        activities.register(.game, isRunning: { colony.play != nil }, stop: { colony.endPlay(completed: false) })
        #expect(colony.startDive())
        w.step(Dive.riseSeconds + 4)
        #expect(activities.isRunning && activities.running == [Activities.Kind.dive])
        #expect(activities.stopAll() == [Activities.Kind.dive])
        w.step(0.5)
        #expect(colony.dive == nil && !colony.overlays[0].hasWater && colony.diveProps().isEmpty)
        #expect(!colony.creatures.contains { $0.isPlaying }, "everyone back to normal")
        // And a game.
        var waited = 0.0
        while !colony.startPlay(.parachute), waited < 20 { w.step(0.5); waited += 0.5 }
        #expect(activities.running == [.game])
        activities.stopAll()
        #expect(colony.play == nil && !activities.isRunning)
    }

    @Test func usingTheComputerStopsItWhenThatIsOn() throws {
        let w = try World()
        defer { w.forget() }
        let colony = w.colony
        Activities.shared.register(.dive, isRunning: { colony.isDiving }, stop: { colony.stopDive() })
        let watch = UseWatch(settings: w.settings)
        defer { watch.stop() }
        var sinceKey = 1000.0
        watch.secondsSince = { $0 == .keyDown ? sinceKey : 1000 }
        #expect(colony.startDive())
        let start = Date()
        watch.check(now: start)
        watch.check(now: start.addingTimeInterval(3))
        #expect(colony.isDiving, "nothing pressed: moving the mouse is not using it")
        w.settings.stopOnUse = false
        sinceKey = 0.1
        watch.check(now: start.addingTimeInterval(4))
        #expect(colony.isDiving, "off: a key does not stop it")
        w.settings.stopOnUse = true
        watch.check(now: start.addingTimeInterval(5))
        #expect(!colony.isDiving, "on: a key stops it")
    }
}

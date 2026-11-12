import AppKit
import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// The effects' settings and the colony's use of them (SPEC §7.19): the defaults, a change surviving a
/// relaunch, a switch turning its effect off, the master switch, and a style wearing off.
@MainActor
@Suite(.serialized) struct EffectsSettingsTests {
    static let suite = "ledgelings-effects-tests"

    func fresh() -> (UserDefaults, AppSettings) {
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        return (defaults, AppSettings(defaults: defaults, keychain: SettingsTests.SpyStore()))
    }

    func colony(_ settings: AppSettings) throws -> Colony {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-fx-\(UUID().uuidString)")
        settings.creatureCount = 3
        settings.brain = .script
        settings.planesEnabled = false
        settings.teaPartiesEnabled = false
        settings.nightMinutes = 0
        let c = try Colony(settings: settings, history: ChatHistory(directory: dir.appendingPathComponent("chats")),
                           library: SpriteLibrary(directory: dir.appendingPathComponent("sprites")),
                           spend: SpendLedger(directory: dir.appendingPathComponent("spend")), bonds: BondBook(directory: dir),
                           stage: Display(frame: CGRect(x: 0, y: 0, width: 1200, height: 800), scale: 1))
        c.meetings = Meetings(gap: -1e6)
        return c
    }

    @Test func theDefaultsAreChosen() {
        let (_, s) = fresh()
        #expect(s.effectsEnabled)
        #expect(s.effectsOff.isEmpty)
        #expect(s.effectsFrequency == .sometimes)
        #expect(s.effectsReduceMotion == .system)
        #expect(s.effectStyleSeconds == 12)
        #expect(s.effectsAmbientSeconds == 60)
        #expect(s.effectsAmbientEveryMinutes == 10)
        #expect(s.effectsAloneMinutes == 30)
        #expect(s.effectsTypingKeys == 5000)
        #expect(s.effectsDailyBudget == 1)
        #expect(!s.effectsCalendar)
        let switches = s.effectSwitches(systemReduceMotion: false)
        #expect(switches.styles.count == 5 && switches.moments.count == 20)
    }

    @Test func aChangeSurvivesARelaunch() {
        let (defaults, s) = fresh()
        s.effectsEnabled = false
        s.setEffect(Effects.Style.haunted.key, on: false)
        s.setEffect(Effects.Moment.goal.key, on: false)
        s.effectsFrequency = .often
        s.effectsReduceMotion = .on
        s.effectStyleSeconds = 30
        s.effectsAmbientSeconds = 120
        s.effectsAmbientEveryMinutes = 5
        s.effectsAloneMinutes = 60
        s.effectsTypingKeys = 8000
        s.effectsDailyBudget = 2.5
        s.effectsCalendar = true
        let again = AppSettings(defaults: defaults, keychain: SettingsTests.SpyStore())
        #expect(!again.effectsEnabled)
        #expect(!again.effectOn(Effects.Style.haunted.key) && !again.effectOn(Effects.Moment.goal.key))
        #expect(again.effectOn(Effects.Style.frost.key))
        #expect(again.effectsFrequency == .often && again.effectsReduceMotion == .on)
        #expect(again.effectStyleSeconds == 30 && again.effectsAmbientSeconds == 120 && again.effectsAmbientEveryMinutes == 5)
        #expect(again.effectsAloneMinutes == 60 && again.effectsTypingKeys == 8000 && again.effectsDailyBudget == 2.5 && again.effectsCalendar)
        // Out of range on disk is clamped on load.
        defaults.set(1000.0, forKey: "effectStyleSeconds")
        defaults.set(["effectMoment.nonsense"], forKey: "effectsOff")
        let clamped = AppSettings(defaults: defaults, keychain: SettingsTests.SpyStore())
        #expect(clamped.effectStyleSeconds == AppSettings.effectStyleSecondsRange.upperBound)
        #expect(clamped.effectsOff.isEmpty)
        defaults.removePersistentDomain(forName: Self.suite)
    }

    @Test func aSwitchOffAndTheMasterKeepTheirEffectAway() throws {
        let (defaults, s) = fresh()
        defer { defaults.removePersistentDomain(forName: Self.suite) }
        let c = try colony(s)
        c.advance(dt: 0.05, cursor: CGPoint(x: -500, y: -500), shift: true)
        s.setEffect(Effects.Moment.dizzy.key, on: false)
        c.refreshEffectSwitches()
        c.mark(.dizzy, on: 0)
        #expect(c.fx.on[0] == nil)
        c.mark(.goal, on: 0)
        #expect(c.fx.on[0]?.moment == .goal)
        s.effectsEnabled = false
        c.refreshEffectSwitches()
        c.mark(.bloom, on: 1)
        #expect(c.fx.on[1] == nil)
        // What was showing goes when the master goes off.
        for _ in 0..<20 { c.advance(dt: 0.05, cursor: CGPoint(x: -500, y: -500), shift: true) }
        #expect(c.fx.on[0] == nil)
    }

    @Test func aStyleWearsOffAndIsDrawnAroundItsCreature() throws {
        let (defaults, s) = fresh()
        defer { defaults.removePersistentDomain(forName: Self.suite) }
        s.effectStyleSeconds = 4
        let c = try colony(s)
        c.advance(dt: 0.05, cursor: CGPoint(x: -500, y: -500), shift: true)
        #expect(c.wear(.smitten, on: 0, byHand: true))
        c.advance(dt: 0.05, cursor: CGPoint(x: -500, y: -500), shift: true)
        let image = c.frames[0].frame(animation: "idle", time: 0)
        let shot = try #require(c.effectSnapshot(of: 0, image: image))
        #expect(shot.front != nil || shot.back != nil)
        #expect(!shot.hidesBody)
        for _ in 0..<100 { c.advance(dt: 0.05, cursor: CGPoint(x: -500, y: -500), shift: true) }
        #expect(c.fx.on[0] == nil)
        // Previews play whatever the switch says.
        s.setEffect(Effects.Style.frost.key, on: false)
        c.refreshEffectSwitches()
        #expect(c.preview("frost", on: 1))
        #expect(c.preview("goal", on: 2))
        #expect(!c.preview("no such effect", on: 2))
    }
}

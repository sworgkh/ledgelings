import AppKit
import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// The weather's settings and the colony's use of them (SPEC §7.20): the defaults, a change surviving a relaunch,
/// clamping, and each switch turning its part off.
@MainActor
@Suite(.serialized) struct WeatherSettingsTests {
    static let suite = "ledgelings-weather-tests"

    func fresh() -> (UserDefaults, AppSettings) {
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        return (defaults, AppSettings(defaults: defaults, keychain: SettingsTests.SpyStore()))
    }

    func colony(_ settings: AppSettings) throws -> Colony {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-wx-\(UUID().uuidString)")
        settings.creatureCount = 3
        settings.brain = .script
        settings.planesEnabled = false
        settings.teaPartiesEnabled = false
        settings.nightMinutes = 0
        settings.weatherReduceMotion = .off
        let c = try Colony(settings: settings, history: ChatHistory(directory: dir.appendingPathComponent("chats")),
                           library: SpriteLibrary(directory: dir.appendingPathComponent("sprites")),
                           spend: SpendLedger(directory: dir.appendingPathComponent("spend")), bonds: BondBook(directory: dir),
                           stage: Display(frame: CGRect(x: 0, y: 0, width: 1200, height: 800), scale: 1))
        c.meetings = Meetings(gap: -1e6)
        c.weather.fakeWindows = [WeatherWatch.Window(id: 5, frame: CGRect(x: 200, y: 200, width: 500, height: 300))]
        return c
    }

    func run(_ c: Colony, seconds: Double) {
        for _ in 0..<Int(seconds * 30) { c.advance(dt: 1.0 / 30, cursor: CGPoint(x: -500, y: -500), shift: false) }
    }

    @Test func theDefaultsAreChosen() {
        let (_, s) = fresh()
        #expect(s.weatherEnabled && s.weatherSnow && s.weatherRain && s.weatherWind)
        #expect(s.weatherQuietMinutes == 5)
        #expect(s.weatherFrequency == .sometimes)
        #expect(s.weatherMinutes == 3)
        #expect(s.weatherSnowDepth == .medium && s.weatherRainHeaviness == .medium && s.weatherWindStrength == .medium)
        #expect(s.weatherShareDistance == 40)
        #expect(s.weatherFollowSeason && s.weatherWindowTops && s.weatherTalk)
        #expect(s.weatherReduceMotion == .system)
    }

    @Test func aChangeSurvivesARelaunch() {
        let (defaults, s) = fresh()
        s.weatherEnabled = false
        s.weatherSnow = false
        s.weatherRain = false
        s.weatherWind = false
        s.weatherQuietMinutes = 12
        s.weatherFrequency = .often
        s.weatherMinutes = 9
        s.weatherSnowDepth = .high
        s.weatherRainHeaviness = .low
        s.weatherWindStrength = .high
        s.weatherShareDistance = 120
        s.weatherFollowSeason = false
        s.weatherWindowTops = false
        s.weatherReduceMotion = .on
        s.weatherTalk = false
        let again = AppSettings(defaults: defaults, keychain: SettingsTests.SpyStore())
        #expect(!again.weatherEnabled && !again.weatherSnow && !again.weatherRain && !again.weatherWind)
        #expect(again.weatherQuietMinutes == 12 && again.weatherFrequency == .often && again.weatherMinutes == 9)
        #expect(again.weatherSnowDepth == .high && again.weatherRainHeaviness == .low && again.weatherWindStrength == .high)
        #expect(again.weatherShareDistance == 120 && !again.weatherFollowSeason && !again.weatherWindowTops)
        #expect(again.weatherReduceMotion == .on && !again.weatherTalk)
        // Out of range on disk is clamped on load.
        defaults.set(500.0, forKey: "weatherQuietMinutes")
        defaults.set(0.0, forKey: "weatherMinutes")
        defaults.set(-5.0, forKey: "weatherShareDistance")
        defaults.set("sideways", forKey: "weatherSnowDepth")
        let clamped = AppSettings(defaults: defaults, keychain: SettingsTests.SpyStore())
        #expect(clamped.weatherQuietMinutes == AppSettings.weatherQuietRange.upperBound)
        #expect(clamped.weatherMinutes == AppSettings.weatherMinutesRange.lowerBound)
        #expect(clamped.weatherShareDistance == 0)
        #expect(clamped.weatherSnowDepth == .medium)
        defaults.removePersistentDomain(forName: Self.suite)
    }

    @Test func theSwitchesReachTheRules() {
        let (_, s) = fresh()
        s.weatherSnow = false
        s.weatherReduceMotion = .system
        let w = s.weatherSwitches(systemReduceMotion: true)
        #expect(!w.allows(.snow) && w.allows(.rain) && w.reduceMotion)
        s.weatherEnabled = false
        #expect(!s.weatherSwitches(systemReduceMotion: false).allows(.rain), "the master switch")
    }

    @Test func snowPilesOnTheBottomAndTheWindowTopsAndMelts() throws {
        let (_, s) = fresh()
        let c = try colony(s)
        #expect(c.startWeather(.snow))
        run(c, seconds: 40)
        let sky = try #require(c.weather.skies.first?.sky)
        #expect(sky.bottom.average > 1)
        #expect((sky.ledgePile(5)?.average ?? 0) > 0.5)
        #expect(!c.weatherPictures().isEmpty)
        c.clearWeather()
        run(c, seconds: Weather.Spell.easeOff + 1)
        #expect(!c.weatherShowing, "it eased off")
        #expect(!c.weather.skies.isEmpty, "the snow lying there stays a while to melt")
        // Snow on window tops off: the window's snow goes.
        s.weatherWindowTops = false
        c.startWeather(.snow)
        run(c, seconds: 2)
        #expect(c.weather.skies.first?.sky.ledgePile(5)?.isEmpty ?? true)
        c.resetWeather()
    }

    @Test func rainOpensUmbrellasAndTheDistanceDecidesWhoShares() throws {
        let (_, s) = fresh()
        let c = try colony(s)
        // Everyone on the floor, the first two close.
        let world = c.world(forSize: c.sizes[0])
        let floor = try #require(world.segments.first { world.loops[$0.loop].inward(ofSegment: $0.segment).dy > 0.9 })
        for (i, f) in [(0, 0.40), (1, 0.42), (2, 0.8)] {
            let tAt = world.loops[floor.loop].t(onSegment: floor.segment, fraction: CGFloat(f))
            c.creatures[i] = Creature(world: c.world(forSize: c.sizes[i]), spot: .init(loop: floor.loop, t: tAt), config: c.creatures[i].config)
            c.creatures[i].pause(for: 1e4)
        }
        #expect(c.startWeather(.rain))
        run(c, seconds: 8)
        #expect(c.weather.groups.map(\.count).sorted() == [1, 2], "two share, one has its own: \(c.weather.groups)")
        #expect(c.weatherProps().count >= 2, "two umbrellas")
        s.weatherShareDistance = 0
        run(c, seconds: 2)
        #expect(c.weather.groups.map(\.count) == [1, 1, 1], "distance 0: everyone their own")
        c.resetWeather()
    }

    @Test func theMasterSwitchEasesOffWhatCameByItself() throws {
        let (_, s) = fresh()
        let c = try colony(s)
        #expect(c.startWeather(.rain, byHand: false))
        run(c, seconds: 2)
        s.weatherEnabled = false
        run(c, seconds: Weather.Spell.easeOff + 1)
        #expect(!c.weatherShowing)
        // Off, it never comes by itself; by hand (the menu, Play now) it still does.
        #expect(!c.startWeather(.rain, byHand: false))
        #expect(c.startWeather(.rain))
        c.resetWeather()
    }

    @Test func whileItFallsTheSeasonParticlesPause() throws {
        let (_, s) = fresh()
        let c = try colony(s)
        c.startAmbient(.autumn, preview: false)
        #expect(c.fx.ambient != nil)
        c.startWeather(.wind)
        run(c, seconds: 3)
        #expect(c.fx.ambient == nil)
        c.resetWeather()
    }

    @Test func theWeatherPageIsInTheSearch() {
        #expect(SettingsIndex.search("umbrella").contains { $0.page == .weather })
        #expect(SettingsPage.named("weather") == .weather)
    }
}

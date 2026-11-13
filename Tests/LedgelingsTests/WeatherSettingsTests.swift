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
        #expect(s.weatherSnowDepth == .medium && s.weatherWindStrength == .medium)
        // Very sparse: two dozen flakes and forty drops on a whole monitor at once.
        #expect(s.weatherSnowCount == 24 && s.weatherRainCount == 40)
        #expect(s.weatherFlakeSize == .medium && s.weatherSnowSpeed == 1 && s.weatherRainSpeed == 1)
        #expect(s.weatherSnowPiles && s.weatherPuddles && s.weatherUmbrellas && s.weatherMenuBarUmbrella && s.weatherWindPushes && s.weatherStorm)
        #expect(s.weatherGustSeconds == 9)
        #expect(s.weatherPausedDay.isEmpty && !s.weatherPaused())
        #expect(s.skyWinterSnow && s.skyAutumnLeaves && s.skySpringPetals && s.skyFireflies)
        #expect(s.skyWinterCount == 10 && s.skyAutumnCount == 10 && s.skySpringCount == 10)
        #expect(s.skyFirefliesCount == 6 && s.skyFirefliesFrom == AppSettings.skyNightFollowsColony)
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
        s.weatherSnowCount = 80
        s.weatherFlakeSize = .large
        s.weatherSnowSpeed = 1.5
        s.weatherSnowPiles = false
        s.weatherRainCount = 120
        s.weatherRainSpeed = 0.7
        s.weatherPuddles = false
        s.weatherUmbrellas = false
        s.weatherMenuBarUmbrella = false
        s.weatherGustSeconds = 20
        s.weatherWindPushes = false
        s.weatherStorm = false
        s.skyWinterSnow = false
        s.skyWinterCount = 30
        s.skyAutumnLeaves = false
        s.skyAutumnCount = 5
        s.skySpringPetals = false
        s.skySpringCount = 40
        s.skyFireflies = false
        s.skyFirefliesCount = 12
        s.skyFirefliesFrom = 21
        s.pauseWeather(true)
        s.weatherWindStrength = .high
        s.weatherShareDistance = 120
        s.weatherFollowSeason = false
        s.weatherWindowTops = false
        s.weatherReduceMotion = .on
        s.weatherTalk = false
        let again = AppSettings(defaults: defaults, keychain: SettingsTests.SpyStore())
        #expect(!again.weatherEnabled && !again.weatherSnow && !again.weatherRain && !again.weatherWind)
        #expect(again.weatherQuietMinutes == 12 && again.weatherFrequency == .often && again.weatherMinutes == 9)
        #expect(again.weatherSnowDepth == .high && again.weatherWindStrength == .high)
        #expect(again.weatherSnowCount == 80 && again.weatherFlakeSize == .large && again.weatherSnowSpeed == 1.5 && !again.weatherSnowPiles)
        #expect(again.weatherRainCount == 120 && again.weatherRainSpeed == 0.7 && !again.weatherPuddles && !again.weatherUmbrellas && !again.weatherMenuBarUmbrella)
        #expect(again.weatherGustSeconds == 20 && !again.weatherWindPushes && !again.weatherStorm)
        #expect(!again.skyWinterSnow && again.skyWinterCount == 30 && !again.skyAutumnLeaves && again.skyAutumnCount == 5)
        #expect(!again.skySpringPetals && again.skySpringCount == 40 && !again.skyFireflies && again.skyFirefliesCount == 12 && again.skyFirefliesFrom == 21)
        #expect(again.weatherPaused(), "paused for today, still today")
        #expect(again.weatherShareDistance == 120 && !again.weatherFollowSeason && !again.weatherWindowTops)
        #expect(again.weatherReduceMotion == .on && !again.weatherTalk)
        // Out of range on disk is clamped on load.
        defaults.set(500.0, forKey: "weatherQuietMinutes")
        defaults.set(0.0, forKey: "weatherMinutes")
        defaults.set(-5.0, forKey: "weatherShareDistance")
        defaults.set("sideways", forKey: "weatherSnowDepth")
        defaults.set(5000.0, forKey: "weatherSnowCount")
        defaults.set(0.0, forKey: "weatherRainSpeed")
        defaults.set(14, forKey: "skyFirefliesFrom")
        let clamped = AppSettings(defaults: defaults, keychain: SettingsTests.SpyStore())
        #expect(clamped.weatherQuietMinutes == AppSettings.weatherQuietRange.upperBound)
        #expect(clamped.weatherMinutes == AppSettings.weatherMinutesRange.lowerBound)
        #expect(clamped.weatherShareDistance == 0)
        #expect(clamped.weatherSnowDepth == .medium)
        #expect(clamped.weatherSnowCount == Weather.snowCountRange.upperBound && clamped.weatherRainSpeed == Weather.speedRange.lowerBound)
        #expect(clamped.skyFirefliesFrom == AppSettings.skyNightFollowsColony, "not an hour on offer")
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
        #expect(c.weather.light?.kind == .leaves, "the season's leaves fall over the whole monitor, from the top")
        #expect(c.fx.ambient == nil, "not as tiles along the bottom")
        c.startWeather(.wind)
        run(c, seconds: 3)
        #expect(c.weather.light == nil)
        c.resetWeather()
    }

    @Test func theSeasonParticlesFallFromTheTopSparsely() throws {
        let (_, s) = fresh()
        let c = try colony(s)
        #expect(c.startAmbient(.winter, preview: true))
        run(c, seconds: 20)
        let sky = try #require(c.weather.skies.first?.sky)
        #expect(sky.spawnTop < 0, "born above the top edge")
        #expect(sky.falling > 0 && sky.falling < 20, "a few: \(sky.falling)")
        #expect(sky.bottom.isEmpty, "light snow never piles")
        c.resetWeather()
    }

    @Test func fireflesAreAFewAlongTheBottom() throws {
        let (_, s) = fresh()
        s.skyFirefliesCount = 4
        let c = try colony(s)
        #expect(c.startAmbient(.night, preview: true))
        let tiles = try #require(c.fx.ambient?.tiles)
        #expect(!tiles.isEmpty)
        #expect(c.ambientSnapshots().allSatisfy { $0.bottomLeft.y == 0 }, "they stay low")
        c.stopWeather()
        run(c, seconds: 1.5)
        #expect(c.fx.ambient == nil, "Stop sends them off")
    }

    @Test func eachSwitchTurnsItsPartOff() throws {
        let (_, s) = fresh()
        let c = try colony(s)
        let world = c.world(forSize: c.sizes[0])
        let floor = try #require(world.segments.first { world.loops[$0.loop].inward(ofSegment: $0.segment).dy > 0.9 })
        for (i, f) in [(0, 0.40), (1, 0.42), (2, 0.8)] {
            let tAt = world.loops[floor.loop].t(onSegment: floor.segment, fraction: CGFloat(f))
            c.creatures[i] = Creature(world: c.world(forSize: c.sizes[i]), spot: .init(loop: floor.loop, t: tAt), config: c.creatures[i].config)
            c.creatures[i].pause(for: 1e4)
        }
        s.weatherUmbrellas = false
        c.startWeather(.rain)
        run(c, seconds: 8)
        #expect(c.weather.groups.isEmpty && c.weatherProps().isEmpty, "no umbrellas")
        c.resetWeather()
        s.weatherSnowPiles = false
        c.startWeather(.snow)
        run(c, seconds: 30)
        #expect(c.weather.skies.first?.sky.bottom.isEmpty == true, "snow that does not pile")
        c.resetWeather()
        s.weatherStorm = false
        #expect(!c.startWeather(.storm, byHand: false), "storm off: it never comes by itself")
        s.skyAutumnLeaves = false
        #expect(!s.effectSwitches(systemReduceMotion: false).allows(.autumn))
        #expect(s.effectSwitches(systemReduceMotion: false).allows(.spring))
        s.skyFireflies = false
        #expect(!s.effectSwitches(systemReduceMotion: false).allows(.night))
    }

    @Test func stopClearsTheWeatherAndThePilesInASecond() throws {
        let (_, s) = fresh()
        let c = try colony(s)
        let activities = Activities.shared
        activities.register(.weather, isRunning: { c.weatherRunning }, stop: { c.stopWeather(why: "test") })
        defer { activities.unregister(.weather) }
        #expect(!activities.isRunning(.weather))
        c.startWeather(.snow)
        run(c, seconds: 30)
        #expect(c.weather.skies.first?.sky.bottom.average ?? 0 > 0.5, "snow lying")
        #expect(activities.isRunning(.weather))
        #expect(!activities.isRunning(besides: .weather), "weather does not keep weather away")
        #expect(activities.stopAll(why: "test") == [.weather])
        run(c, seconds: 0.5)
        let fading = try #require(c.weatherPictures().first)
        #expect(fading.opacity > 0 && fading.opacity < 1, "it eases out, not all at once")
        #expect(c.weatherProps().isEmpty)
        run(c, seconds: 0.7)
        #expect(!c.weatherShowing && c.weather.skies.isEmpty, "gone, piles and all, in about a second")
        #expect(!c.weatherRunning)
        #expect(s.weatherEnabled, "Stop switches nothing off")
        // The season's particles stop the same way, and stay away until their next time out.
        c.startAmbient(.autumn, preview: false)
        run(c, seconds: 1)
        activities.stopAll(why: "test")
        run(c, seconds: 1.2)
        #expect(c.weather.light == nil && c.weather.skies.isEmpty)
    }

    @Test func pausedForTodayNothingComesUntilTomorrow() throws {
        let (_, s) = fresh()
        let c = try colony(s)
        let today = Date(timeIntervalSince1970: 1_794_000_000)      // November 2026
        c.now = { today }
        s.effectsAmbientEveryMinutes = 1
        s.effectsAmbientSeconds = 60
        c.elapsed = 60 * 7 + 1                                       // a time out of the season's particles
        run(c, seconds: 1)
        #expect(c.weather.light != nil, "not paused: the autumn leaves come out")
        s.pauseWeather(true, at: today)
        c.stopWeather()
        run(c, seconds: 2)
        #expect(c.weather.light == nil, "paused: they went, and stay away")
        #expect(s.weatherPaused(on: today) && !s.weatherPaused(on: today.addingTimeInterval(86_400)), "only today")
        c.now = { today.addingTimeInterval(86_400) }
        c.elapsed = 60 * 9 + 1
        run(c, seconds: 1)
        #expect(c.weather.light != nil, "tomorrow they come again")
        c.resetWeather()
    }

    @Test func theMomentsSwitchesMoveToTheSky() {
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        defer { defaults.removePersistentDomain(forName: Self.suite) }
        // As an older version saved them: fireflies and autumn switched off on the Moments page, with a style.
        defaults.set(["effectMoment.night", "effectMoment.autumn", "effectStyle.frost"], forKey: "effectsOff")
        let s = AppSettings(defaults: defaults, keychain: SettingsTests.SpyStore())
        #expect(!s.skyFireflies && !s.skyAutumnLeaves && s.skySpringPetals && s.skyWinterSnow)
        #expect(s.effectsOff == ["effectStyle.frost"], "the moved ones leave the Moments list")
        #expect(defaults.object(forKey: "skyFireflies") as? Bool == false)
        let again = AppSettings(defaults: defaults, keychain: SettingsTests.SpyStore())
        #expect(!again.skyFireflies && !again.skyAutumnLeaves, "and stay off")
        #expect(!again.effectSwitches(systemReduceMotion: false).allows(.night))
    }

    @Test func theWeatherPageIsInTheSearch() {
        Language.$override.withValue(.english) {
            #expect(SettingsIndex.search("umbrella").contains { $0.page == .weather })
            #expect(SettingsIndex.search("fireflies").first?.page == .weather, "fireflies land on Weather & Sky")
            #expect(SettingsIndex.search("autumn leaves").first?.page == .weather)
            #expect(SettingsIndex.search("pause for today").first?.page == .weather)
        }
        #expect(SettingsPage.named("weather") == .weather)
        #expect(SettingsPage.weather.title == tr("Weather & Sky"))
    }
}

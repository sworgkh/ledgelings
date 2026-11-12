import CoreGraphics
import Foundation
import Testing
@testable import LedgelingsCore

/// Weather on a quiet screen (SPEC §7.20): the quiet rule, the seasons, a spell easing off, the snow piles, the
/// umbrellas, the bowl on the top edge, the wind, the switches, the props and the lines.
@Suite struct WeatherTests {
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
    }

    // MARK: Quiet

    static let quiet = Weather.Screen(keyIdle: 600, cursorTravel: 20)

    @Test func quietNeedsEveryConditionAtOnce() {
        #expect(Weather.isQuiet(Self.quiet, minutes: 5))
        var s = Self.quiet; s.keyIdle = 200
        #expect(!Weather.isQuiet(s, minutes: 5), "a key three minutes ago")
        s = Self.quiet; s.cursorTravel = 400
        #expect(!Weather.isQuiet(s, minutes: 5), "the cursor moved about")
        s = Self.quiet; s.cursorTravel = Weather.cursorAllowance
        #expect(Weather.isQuiet(s, minutes: 5), "a nudge of the mouse is still quiet")
        s = Self.quiet; s.fullScreen = true
        #expect(!Weather.isQuiet(s, minutes: 5), "a full-screen app")
        s = Self.quiet; s.activity = true
        #expect(!Weather.isQuiet(s, minutes: 5), "a game, a surf or a dive")
        s = Self.quiet; s.meeting = true
        #expect(!Weather.isQuiet(s, minutes: 5), "a meeting")
        #expect(!Weather.isQuiet(Self.quiet, minutes: 15), "ten minutes is not fifteen")
    }

    @Test func comingBackIsAKeyOrMoreThanANudge() {
        #expect(Weather.isBack(keyIdle: 0.5, recentTravel: 0))
        #expect(Weather.isBack(keyIdle: 100, recentTravel: 200))
        #expect(!Weather.isBack(keyIdle: 100, recentTravel: 10))
    }

    @Test func theCursorTrailAddsUpWhereItWent() {
        var trail = Weather.CursorTrail()
        trail.add(CGPoint(x: 0, y: 0), at: 0, keep: 60)
        trail.add(CGPoint(x: 30, y: 40), at: 1, keep: 60)
        trail.add(CGPoint(x: 30, y: 40), at: 2, keep: 60)
        #expect(trail.travel(since: 0) == 50)
        #expect(trail.travel(since: 1.5) == 0)
        trail.add(CGPoint(x: 0, y: 0), at: 100, keep: 60)
        #expect(trail.span == 0, "older than the window is dropped")
    }

    // MARK: Seasons

    @Test func theSeasonWeighsWhichWeatherComes() {
        let s = Weather.Switches()
        let winter = Weather.weights(.winter, switches: s), summer = Weather.weights(.summer, switches: s), autumn = Weather.weights(.autumn, switches: s)
        #expect(winter[.snow]! > winter[.rain]! && winter[.snow]! > winter[.wind]!, "snow mostly in winter")
        #expect(summer[.snow] == nil, "no snow in summer")
        #expect(autumn[.wind]! > autumn[.rain]! && autumn[.wind]! > (autumn[.snow] ?? 0), "wind in autumn")
        #expect(Weather.Kind.allCases.filter { [.winter, .spring, .summer, .autumn].allSatisfy { Weather.weights($0, switches: s)[.rain] != nil } && $0 == .rain } == [.rain], "rain any time")
        // Picked by the roll, in proportion.
        var counts: [Weather.Kind: Int] = [:]
        for k in 0..<1000 { counts[Weather.pick(.winter, switches: s, roll: Double(k) / 1000)!, default: 0] += 1 }
        #expect(counts[.snow]! > 600)
        var off = s; off.followSeason = false
        #expect(Weather.weights(.summer, switches: off)[.snow] == 1, "not following the season, snow comes in summer too")
    }

    @Test func aWeatherSwitchedOffNeverComes() {
        var s = Weather.Switches()
        s.snow = false
        #expect(Weather.weights(.winter, switches: s)[.snow] == nil)
        s.rain = false
        #expect(Weather.weights(.winter, switches: s)[.storm] == nil, "a storm needs rain")
        s.wind = false
        #expect(Weather.pick(.winter, switches: s, roll: 0.3) == nil)
        s = Weather.Switches(); s.enabled = false
        #expect(Weather.pick(.autumn, switches: s, roll: 0.3) == nil, "the master switch")
        #expect(Weather.chance(step: 10, frequency: .often) > Weather.chance(step: 10, frequency: .rarely))
    }

    // MARK: A spell

    @Test func aSpellComesInStaysAndEasesOffSlowly() {
        var spell = Weather.Spell(kind: .snow, lasts: 60)
        spell.update(3)
        #expect(spell.intensity > 0.4 && spell.intensity < 0.6, "coming in")
        spell.update(10)
        #expect(spell.intensity == 1 && !spell.isEasing)
        // Someone comes back: it does not stop at the first key, it eases off.
        spell.ease()
        spell.update(0.1)
        #expect(spell.intensity > 0.9 && spell.isEasing && !spell.isOver)
        spell.update(Weather.Spell.easeOff / 2)
        #expect(spell.intensity > 0.3 && spell.intensity < 0.7)
        spell.update(Weather.Spell.easeOff)
        #expect(spell.isOver)
        // Left alone, it eases off at its time.
        var timed = Weather.Spell(kind: .rain, lasts: 30)
        timed.update(31)
        #expect(timed.isEasing)
    }

    // MARK: Snow piles

    @Test func thePileGrowsToItsCapAndMelts() {
        var pile = Weather.Pile(width: 40, cap: Weather.bottomCap(.medium))
        for _ in 0..<1000 { pile.grow(by: 0.1) }
        #expect(pile.deepest == Weather.bottomCap(.medium) && pile.average == pile.cap, "never past the cap")
        for x in 0..<40 { pile.land(at: x, amount: 3) }
        #expect(pile.deepest <= pile.cap)
        pile.melt(by: 2)
        #expect(pile.deepest == pile.cap - 2)
        pile.melt(by: 100)
        #expect(pile.isEmpty)
        #expect(Weather.bottomCap(.low) < Weather.bottomCap(.medium) && Weather.bottomCap(.medium) < Weather.bottomCap(.high))
        #expect(Weather.windowCap(.medium) < Weather.bottomCap(.medium))
    }

    @Test func flakesHeapUpAndSlideOffASteepColumn() {
        var pile = Weather.Pile(width: 9, cap: 20)
        for _ in 0..<20 { pile.land(at: 4, amount: 1) }
        #expect(pile.height(at: 4) > pile.height(at: 0))
        for x in 1..<9 { #expect(abs(pile.height(at: x) - pile.height(at: x - 1)) <= 2.5, "no column stands far above its neighbour") }
    }

    @Test func aFootprintIsADent() {
        var pile = Weather.Pile(width: 10, cap: 8)
        pile.grow(by: 6)
        pile.step(at: 4)
        #expect(pile.height(at: 4) == 5 && pile.height(at: 5) == 5 && pile.height(at: 3) == 6)
    }

    @Test func wadingInDeepSnowIsSlower() {
        #expect(Weather.wading(depth: 0, cap: 8) == 1)
        #expect(Weather.wading(depth: 8, cap: 8) == 0.5)
        #expect(Weather.wading(depth: 4, cap: 8) == 0.75)
    }

    @Test func theSkyPilesSnowOnTheBottomAndOnWindowTopsAndDropsIt() {
        let sky = Weather.Sky(width: 120, height: 80, depth: .medium, seed: 3)
        sky.setLedges([7: Weather.Ledge(x: 20, y: 40, open: Array(repeating: true, count: 60))], depth: .medium)
        for _ in 0..<(30 * 120) {
            sky.update(1.0 / 30, kind: .snow, intensity: 1, drift: 0, heaviness: .medium, depth: .medium, windowTops: true, reduced: false)
        }
        #expect(sky.bottom.average > 4, "the bottom pile grew")
        #expect((sky.ledgePile(7)?.average ?? 0) > 2, "so did the window's top")
        #expect(sky.bottom.deepest <= Weather.bottomCap(.medium))
        // The window moves: its snow falls off as a shower.
        var flakes = 0
        sky.onShower = { _, n in flakes = n }
        sky.setLedges([7: Weather.Ledge(x: 50, y: 40, open: Array(repeating: true, count: 60))], depth: .medium)
        #expect(flakes > 20)
        #expect((sky.ledgePile(7)?.average ?? 1) == 0, "it starts bare where it went")
        // Snow tops off: the window tops' snow goes, the bottom's stays.
        sky.fillLedges(by: 3)
        sky.update(0.1, kind: .snow, intensity: 1, drift: 0, heaviness: .medium, depth: .medium, windowTops: false, reduced: false)
        #expect(sky.ledgePile(7)?.isEmpty == true)
        // It stops: slowly, all of it melts.
        let before = sky.bottom.average
        sky.update(10, kind: nil, intensity: 0, drift: 0, heaviness: .medium, depth: .medium, windowTops: true, reduced: false)
        #expect(sky.bottom.average < before && sky.bottom.average > before - 1, "slowly")
        for _ in 0..<100 { sky.update(10, kind: nil, intensity: 0, drift: 0, heaviness: .medium, depth: .medium, windowTops: true, reduced: false) }
        #expect(sky.bottom.isEmpty)
    }

    @Test func rainMakesPuddlesThatDry() {
        let sky = Weather.Sky(width: 100, height: 60, depth: .medium, seed: 5)
        for _ in 0..<(30 * 60) { sky.update(1.0 / 30, kind: .rain, intensity: 1, drift: 0, heaviness: .high, depth: .medium, windowTops: true, reduced: false) }
        #expect(sky.wet.max()! > 0.5, "a puddle")
        #expect(sky.bottom.isEmpty, "rain piles nothing")
        sky.update(Weather.drySeconds + 1, kind: nil, intensity: 0, drift: 0, heaviness: .high, depth: .medium, windowTops: true, reduced: false)
        #expect(sky.wet.max()! == 0)
    }

    @Test func reduceMotionHalvesTheParticles() {
        func count(_ reduced: Bool) -> Int {
            let sky = Weather.Sky(width: 200, height: 400, depth: .medium, seed: 9)
            for _ in 0..<60 { sky.update(1.0 / 30, kind: .snow, intensity: 1, drift: 0, heaviness: .medium, depth: .medium, windowTops: true, reduced: reduced) }
            return sky.particles.count
        }
        let full = count(false), half = count(true)
        #expect(half < full * 2 / 3 && half > full / 3)
    }

    // MARK: Umbrellas

    @Test func whoSharesAnUmbrella() {
        let one = [Weather.Standing(index: 0, edge: 0, along: 100)]
        #expect(Weather.umbrellaGroups(one, distance: 40) == [[0]], "alone: its own")
        let two = one + [Weather.Standing(index: 1, edge: 0, along: 130)]
        #expect(Weather.umbrellaGroups(two, distance: 40) == [[0, 1]], "two close: one between them")
        let three = two + [Weather.Standing(index: 2, edge: 0, along: 400)]
        #expect(Weather.umbrellaGroups(three, distance: 40) == [[0, 1], [2]], "three: two groups")
        #expect(Weather.umbrellaGroups(two, distance: 0) == [[0], [1]], "distance 0: everyone their own")
        let walls = [Weather.Standing(index: 0, edge: 0, along: 100), Weather.Standing(index: 1, edge: 1, along: 105)]
        #expect(Weather.umbrellaGroups(walls, distance: 40) == [[0], [1]], "never across two edges")
        let crowd = (0..<5).map { Weather.Standing(index: $0, edge: 0, along: Double($0) * 10) }
        #expect(Weather.umbrellaGroups(crowd, distance: 40).map(\.count) == [3, 2], "at most three under one")
        #expect(Weather.holder(of: [4, 5, 6]) == 5)
        #expect(Weather.umbrellaWidth(for: 2) > Weather.umbrellaWidth(for: 1))
    }

    @Test func theBowlOnTheTopEdgeFillsTipsAndFalls() {
        var bowl = Weather.Bowl()
        var events: [Weather.Bowl.Event] = []
        var t = 0.0
        while t < 60 {
            if let e = bowl.update(0.1, intensity: 1, heaviness: .medium) { events.append(e) }
            t += 0.1
            if bowl.state == .fallen { break }
        }
        #expect(events == [.full, .spills])
        #expect(t >= Weather.Bowl.fillSeconds && t < Weather.Bowl.fillSeconds + Weather.Bowl.tipSeconds + 1)
        #expect(bowl.tip == 1 && bowl.water == 0)
        var heavy = Weather.Bowl(), light = Weather.Bowl()
        _ = heavy.update(5, intensity: 1, heaviness: .high)
        _ = light.update(5, intensity: 1, heaviness: .low)
        #expect(heavy.water > light.water, "heavier rain fills it sooner")
    }

    // MARK: Wind

    @Test func theWindPushesTheLightOnesAndSlowsThoseWalkingIntoIt() {
        let wind = Weather.Wind(fromLeft: true, strength: .medium)
        #expect(wind.force(at: Weather.Wind.gustLasts / 2) > 0.99, "a gust at its height")
        #expect(wind.force(at: Weather.Wind.gustEvery - 1) < 0.31, "a breeze between gusts")
        #expect(wind.peaks(at: Weather.Wind.gustLasts / 2 + 0.01, dt: 0.03))
        #expect(!wind.peaks(at: 4, dt: 0.03))
        #expect(Weather.push(size: 1, force: 1, strength: .medium) >= 4, "a light one, a few pixels")
        #expect(Weather.push(size: 2.5, force: 1, strength: .medium) <= 1, "a heavy one, hardly at all")
        #expect(Weather.push(size: 1, force: 1, strength: .high) > Weather.push(size: 1, force: 1, strength: .low))
        #expect(Weather.windPace(walking: 1, wind: wind, force: 1) > 1, "with it, faster")
        #expect(Weather.windPace(walking: -1, wind: wind, force: 1) < 1, "into it, slower")
        #expect(Weather.blowsOff(size: 0.7, force: 1, strength: .medium))
        #expect(!Weather.blowsOff(size: 2, force: 1, strength: .medium))
        #expect(Weather.turnsInsideOut(force: 1, strength: .medium, roll: 0.1))
        #expect(!Weather.turnsInsideOut(force: 0.4, strength: .medium, roll: 0.1))
        #expect(wind.lean(at: 1.25, intensity: 1) < 0, "leaning into a wind from the left")
    }

    @Test func aGustShovesACreatureAlongItsEdgeOnly() {
        let world = EdgeWorld(screens: [CGRect(x: 0, y: 0, width: 800, height: 600)], inset: 10)
        var c = Creature(world: world, spot: .init(loop: 0, t: 300))
        c.pause(for: 100)
        let x = c.position.x
        c.shove(by: 4)
        #expect(c.position.x == x + 4)
        c.shove(by: -10_000)
        #expect(c.loop.segment(at: c.t) == 0, "never round the corner")
    }

    // MARK: Props and lines

    @Test func thePropsAreDrawnInBlockysStyle() {
        for art in [Weather.umbrella(width: 27, colour: Weather.umbrellaColours[0]), Weather.umbrella(width: 49, colour: Weather.umbrellaColours[1], insideOut: true),
                    Weather.snowman(), Weather.snowball(), Weather.gusts(), Weather.sun()] {
            #expect(art.pixels.contains { $0 != 0 })
            // Square pixels with 1-bit alpha: every pixel is a colour or nothing.
            #expect(art.rgba.enumerated().allSatisfy { $0.offset % 4 != 3 || $0.element == 0 || $0.element == 255 })
        }
        let u = Weather.umbrella(width: 27, colour: Weather.umbrellaColours[0])
        #expect(u.w % 2 == 1, "the handle in the middle")
        #expect(u.at(u.w / 2, u.h - 2) != 0, "a handle down the middle")
        #expect(Weather.umbrellaColour(for: "Blocky") == Weather.umbrellaColour(for: "Blocky"), "always the same colour for the same one")
    }

    static let cast = ["Blocky", "Pip", "Mortimer", "Zed", "Dot", "Ruth", "Whiskers", "Mittens", "Sir Pounce", "Hopper", "Mossy", "Croak",
                       "Boo", "Wisp", "Sheet", "Morel", "Puff", "Cap", "Unit 7", "Sprocket", "Glitch", "Goop", "Puddle", "Blorp",
                       "Spike", "Wedge", "Delta", "Prickles", "Saguaro", "Tumble", "Click", "Scarab", "Crumb", "Shard", "Quartz", "Prism",
                       "Sprout", "Fern", "Bud"]

    @Test func everyCharacterHasItsOwnWeatherLinesInEveryLanguage() {
        for (language, table, anyone) in [("en", Weather.englishLines, Weather.englishAnyone), ("ru", Weather.russianLines, Weather.russianAnyone)] {
            #expect(Set(table.keys) == Set(Self.cast), "\(language): every built-in character")
            for (name, lines) in table.merging(["anyone": anyone], uniquingKeysWith: { a, _ in a }) {
                for kind in Weather.lineKinds { #expect(!(lines[kind] ?? []).isEmpty, "\(language) \(name) has no \(kind) line") }
                for kind in ["throw", "hit", "share"] {
                    for line in lines[kind] ?? [] { #expect(line.components(separatedBy: "{friend}").count == 2, "\(language) \(name): \(line)") }
                }
            }
        }
        var rng = Seeded(state: 4)
        let line = Weather.line(by: "Blocky", "throw", friend: "Boo", using: &rng)
        #expect(line.contains("Boo") && !line.contains("{friend}"))
        #expect(!Weather.line(by: "Someone New", "rain", using: &rng).isEmpty, "a character the user made says anyone's line")
        Language.$override.withValue(.russian) {
            var rng = Seeded(state: 4)
            #expect(Weather.line(by: "Unit 7", "snow", using: &rng).range(of: "[а-яА-Я]", options: .regularExpression) != nil)
        }
    }
}

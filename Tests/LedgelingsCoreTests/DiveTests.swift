import CoreGraphics
import Foundation
import Testing
@testable import LedgelingsCore

/// Scuba diving's water, divers and sea life, the lines every character says
/// on a dive, and when "Stop when I use the computer" stops an activity.
@Suite struct DiveTests {
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
    }

    static let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)

    static func dive(share: Double = 1.0 / 3, seconds: Double = 30, divers: Int = 3) -> (Dive, Seeded) {
        var rng = Seeded(state: 7)
        let d = Dive(pools: [screen], share: share, seconds: seconds, scale: 2.5,
                     divers: (0..<divers).map { (index: $0, at: CGPoint(x: 200 + Double($0) * 300, y: 27), half: 27) },
                     seaLife: 12, using: &rng)
        return (d, rng)
    }

    @Test func theWaterRisesToTheSetShareOfTheScreenAndDrainsAway() {
        for share in [0.2, 1.0 / 3, 0.5] {
            var (d, rng) = Self.dive(share: share, seconds: 5)
            #expect(d.water(0).height == 0)
            var events: [Dive.Event] = []
            for _ in 0..<Int(Dive.riseSeconds / 0.05) + 2 { events += d.update(dt: 0.05, using: &rng) }
            #expect(d.phase == .on && events.contains(.filled))
            #expect(abs(d.water(0).height - Self.screen.height * share) < 0.01, "a \(share) share of 800 points")
            while !d.isOver, d.time < 60 { events += d.update(dt: 0.05, using: &rng) }
            #expect(d.isOver && d.water(0).height == 0 && events.contains(.drained))
        }
    }

    @Test func everyDiverJumpsInWithASplashSwimsUnderAndComesUpForAir() {
        var (d, rng) = Self.dive(seconds: 60)
        var events: [Dive.Event] = []
        while d.time < 50 { events += d.update(dt: 0.05, using: &rng) }
        #expect(events.filter { if case .splash = $0 { return true }; return false }.count == 3, "one splash a diver")
        #expect(Set(events.compactMap { if case .surfaced(let i) = $0 { return i }; return nil }) == [0, 1, 2], "each comes up for air")
        for diver in d.divers where diver.isUnder {
            #expect(d.water(0).contains(diver.position), "under the surface")
        }
        #expect(events.contains { if case .sees = $0 { return true }; return false })
    }

    @Test func theSeaLifeIsAllThereAndKeepsToTheWater() {
        var (d, rng) = Self.dive(seconds: 60)
        let kinds = Set(d.critters.map(\.kind))
        #expect(kinds == Set(Dive.Life.allCases), "three fish, a jellyfish, a crab, a turtle and an octopus")
        #expect(d.critters.filter(\.kind.isFish).count == 12 && !d.weeds.isEmpty)
        while d.time < 40 { _ = d.update(dt: 0.05, using: &rng) }
        let water = d.water(0)
        for c in d.critters { #expect(water.insetBy(dx: -1, dy: -1).contains(c.position), "\(c.kind) at \(c.position)") }
        let crab = d.critters.first { $0.kind == .crab }!
        #expect(abs(crab.position.y - Dive.Life.crab.halfSize.height * 2.5) < 0.5, "the crab walks the floor")
    }

    @Test func fishScatterFromADiverWhoComesNear() {
        var (d, rng) = Self.dive(seconds: 60, divers: 1)
        while d.phase != .on { _ = d.update(dt: 0.05, using: &rng) }
        while case .gearing = d.divers[0].state { _ = d.update(dt: 0.05, using: &rng) }
        while d.divers[0].state != .swimming { _ = d.update(dt: 0.05, using: &rng) }
        // Put the diver right beside a fish.
        let k = d.critters.firstIndex(where: \.kind.isFish)!
        d.divers[0].position = CGPoint(x: d.critters[k].position.x - 20, y: d.critters[k].position.y)
        d.divers[0].target = d.divers[0].position
        let before = hypot(d.critters[k].position.x - d.divers[0].position.x, d.critters[k].position.y - d.divers[0].position.y)
        var events: [Dive.Event] = []
        for _ in 0..<10 { events += d.update(dt: 0.05, using: &rng) }
        let after = hypot(d.critters[k].position.x - d.divers[0].position.x, d.critters[k].position.y - d.divers[0].position.y)
        #expect(d.critters[k].scared > 0 && after > before, "it darts away: \(before) → \(after)")
        #expect(events.contains(.scattered(diver: 0)))
    }

    @Test func drainingEarlyBringsEveryoneDown() {
        var (d, rng) = Self.dive(seconds: 600)
        while d.time < 10 { _ = d.update(dt: 0.05, using: &rng) }
        d.drain()
        #expect(d.phase == .draining)
        while !d.isOver { _ = d.update(dt: 0.05, using: &rng) }
        for diver in d.divers { #expect(diver.position.y <= Self.screen.minY + diver.half + 1, "on the floor") }
    }

    // MARK: Words

    static let cast = ["Blocky", "Pip", "Mortimer", "Zed", "Dot", "Ruth", "Whiskers", "Mittens", "Sir Pounce", "Hopper", "Mossy", "Croak",
                       "Boo", "Wisp", "Sheet", "Morel", "Puff", "Cap", "Unit 7", "Sprocket", "Glitch", "Goop", "Puddle", "Blorp",
                       "Spike", "Wedge", "Delta", "Prickles", "Saguaro", "Tumble", "Click", "Scarab", "Crumb", "Shard", "Quartz", "Prism",
                       "Sprout", "Fern", "Bud"]
    static let kinds = ["in", "see", "fish", "octopus", "air", "out"]

    @Test func everyCharacterHasItsOwnLinesInEveryLanguage() {
        for (language, table, anyone) in [("en", Dive.englishLines, Dive.englishAnyone), ("ru", Dive.russianLines, Dive.russianAnyone)] {
            #expect(Set(table.keys) == Set(Self.cast), "\(language): every built-in character")
            for (name, lines) in table.merging(["anyone": anyone], uniquingKeysWith: { a, _ in a }) {
                for kind in Self.kinds {
                    #expect(!(lines[kind] ?? []).isEmpty, "\(language) \(name) has no \(kind) line")
                }
                for line in lines["see"] ?? [] { #expect(line.components(separatedBy: "{what}").count == 2, "\(language) \(name): \(line)") }
            }
        }
        var rng = Seeded(state: 3)
        let line = Dive.line(by: "Unit 7", "see", what: .turtle, using: &rng)
        #expect(line.contains("a turtle") && !line.contains("{what}"))
        #expect(!Dive.line(by: "Someone New", "in", using: &rng).isEmpty, "a character the user made says anyone's line")
        #expect(Dive.fill("Hmph. {what}. Down here.", what: "a turtle") == "Hmph. A turtle. Down here.")
        #expect(Dive.fill("Look, {what}!", what: "a turtle") == "Look, a turtle!")
        Language.$override.withValue(.russian) {
            var rng = Seeded(state: 3)
            #expect(Dive.line(by: "Unit 7", "see", what: .turtle, using: &rng).lowercased().contains("черепаха"))
        }
    }

    @Test func aDiveLandsInThePairsStory() {
        var book = Bonds.Book()
        book.note("Blocky", "Pip", Bonds.Moment(time: Date(), kind: .dive, who: "Blocky", detail: Dive.memory([.turtle, .fishB, .fishA])))
        let moment = book.bond("Blocky", "Pip")!.moments.last!
        #expect(Bonds.describe(moment, names: ["Blocky", "Pip"]) == "Blocky and Pip went diving together and saw a school of fish, a turtle")
        #expect(book.bond("Blocky", "Pip")!.tally["dive"] == 1)
    }

    // MARK: Stop when I use the computer

    @Test func aKeyOrAClickOutsideTheCreaturesStopsAnActivityButMovingTheMouseDoesNot() {
        let long = 1e6
        // Nothing pressed since it started (moving the mouse is no key and no click).
        #expect(!UsePolicy.stops(runningFor: 10, sinceKey: 30, sinceClick: 40, sinceOwnClick: long))
        #expect(UsePolicy.stops(runningFor: 10, sinceKey: 0.2, sinceClick: 40, sinceOwnClick: long), "a key")
        #expect(UsePolicy.stops(runningFor: 10, sinceKey: 30, sinceClick: 0.2, sinceOwnClick: long), "a click on an app")
        #expect(!UsePolicy.stops(runningFor: 10, sinceKey: 30, sinceClick: 0.2, sinceOwnClick: 0.21), "a click on a creature")
        #expect(!UsePolicy.stops(runningFor: 0.3, sinceKey: 0.1, sinceClick: 0.1, sinceOwnClick: long), "the press that started it")
        #expect(!UsePolicy.stops(runningFor: 5, sinceKey: 4.8, sinceClick: 40, sinceOwnClick: long), "a key before it started")
    }
}

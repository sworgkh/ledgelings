import CoreGraphics
import Foundation
import Testing
@testable import LedgelingsCore

/// The games: who plays and how often, tag's touches, the rope's swing, the
/// parachute's fall, the ball's flight, the creature off its edge, and the words.
@Suite struct PlaysTests {
    static let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    static let inset: CGFloat = 25
    let world = EdgeWorld(screens: [PlaysTests.screen], inset: PlaysTests.inset)

    // MARK: Who plays, and when

    @Test func closenessCountsTheMomentsTheyShared() {
        #expect(Plays.closeness(nil) == 0)
        var bond = Bonds.Bond(names: ["Blocky", "Pip"])
        #expect(Plays.closeness(bond) == 0)
        bond.tally = ["talk": 6, "tea": 4]
        #expect(Plays.closeness(bond) == 0.5)
        bond.tally = ["talk": 40]
        #expect(Plays.closeness(bond) == 1, "no closer than close")
        bond.tally = [:]; bond.talks = 5
        #expect(Plays.closeness(bond) == 0.25, "before storylines, their talks count")
    }

    @Test func friendsWaitLessForTheNextGame() {
        var rng = SeededRNG(state: 1)
        for _ in 0..<50 {
            let strangers = Plays.wait(everyMinutes: 5, boost: 100, closeness: 0, using: &rng)
            #expect(strangers >= 5 * 60 * 0.6 && strangers <= 5 * 60 * 1.4)
            let friends = Plays.wait(everyMinutes: 5, boost: 100, closeness: 1, using: &rng)
            #expect(friends >= 5 * 60 * 0.3 && friends <= 5 * 60 * 0.7, "at 100 % the best of friends wait half as long")
            let noBoost = Plays.wait(everyMinutes: 5, boost: 0, closeness: 1, using: &rng)
            #expect(noBoost >= 5 * 60 * 0.6)
        }
    }

    @Test func strangersPlayAloneAndFriendsMostlyTogether() {
        var rng = SeededRNG(state: 7)
        let all = Set(Plays.Kind.allCases)
        for _ in 0..<100 {
            let chosen = Plays.choose(initiator: 0, others: [(1, 0.1), (2, 0)], enabled: all, using: &rng)
            #expect(chosen?.players == [0] && chosen?.kind.canSolo == true, "a stranger never plays tag")
        }
        var together = 0
        for _ in 0..<400 {
            let chosen = Plays.choose(initiator: 0, others: [(1, 1), (2, 0.5)], enabled: all, using: &rng)!
            if chosen.players.count == 2 {
                together += 1
                #expect(chosen.players == [0, 1], "with its closest friend")
                #expect(chosen.kind.canPair)
            }
        }
        #expect(abs(Double(together) / 400 - Plays.pairChance(1)) < 0.08)
        #expect(Plays.choose(initiator: 0, others: [], enabled: [.tag], using: &rng) == nil, "tag alone is no game")
        #expect(Plays.choose(initiator: 0, others: [(1, 1)], enabled: [.tag], using: &rng)?.kind == .tag)
        #expect(Plays.choose(initiator: 0, others: [(1, 1)], enabled: [], using: &rng) == nil)
    }

    // MARK: Tag

    @Test func tagSwapsWhoIsItOnATouchAndEndsOutOfBreath() {
        var tag = Plays.Tag(it: 3, other: 8, length: 20)
        #expect(tag.it == 3 && tag.runner == 8 && tag.itIsCounting)
        let touch1 = tag.near(gap: 0, reach: 50)
        #expect(touch1 == nil, "not before the go")
        var events: [Plays.Tag.Event] = []
        for _ in 0..<12 { events += tag.update(dt: 0.1) }
        #expect(events == [.go])
        let touch2 = tag.near(gap: 40, reach: 50)
        #expect(touch2 == .tagged(by: 3, now: 8))
        #expect(tag.it == 8 && tag.runner == 3 && tag.itIsCounting, "the new one counts first")
        let touch3 = tag.near(gap: 0, reach: 50)
        #expect(touch3 == nil, "no tagging back while counting")
        for _ in 0..<11 { _ = tag.update(dt: 0.1) }
        #expect(!tag.itIsCounting)
        let touch4 = tag.near(gap: 60, reach: 50)
        #expect(touch4 == nil, "too far to touch")
        let touch5 = tag.near(gap: 10, reach: 50)
        #expect(touch5 == .tagged(by: 8, now: 3))
        events = []
        for _ in 0..<300 { events += tag.update(dt: 0.1) }
        #expect(events == [.puffing, .over])
        #expect(tag.touches == 2 && tag.phase == .over)
    }

    // MARK: The rope

    @Test func theRopeSwingsClearOfTheFloorAndLandsBackOnIt() throws {
        let floor = try #require(world.floor(under: CGPoint(x: 300, y: 100)))
        let ceiling = try #require(world.ceiling(over: CGPoint(x: 300, y: 100)))
        #expect(floor.y == Self.inset && ceiling.y == Self.screen.height - Self.inset)
        let start = CGPoint(x: 300, y: floor.y), top = Self.screen.height
        var rope = try #require(Plays.Rope(from: start, ceilingY: top, floor: floor.span, way: 1, clearance: 60))
        #expect(rope.way == 1 && rope.anchor.y == top && rope.anchor.x > start.x)
        var events: [Plays.Rope.Event] = []
        var lowest = CGFloat.infinity, t = 0.0
        while rope.phase != .landed, t < 20 {
            events += rope.update(dt: 1.0 / 30)
            t += 1.0 / 30
            if rope.phase == .swing { lowest = min(lowest, rope.position.y) }
            if rope.phase == .swing || rope.phase == .reel {
                let length = hypot(rope.position.x - rope.anchor.x, rope.position.y - rope.anchor.y)
                #expect(length <= rope.firedLength + 0.5)
            }
        }
        #expect(events == [.fired, .hooked, .swinging, .letGo, .landed])
        #expect(lowest >= floor.y + 60 - 2, "never scrapes the floor at the bottom of the swing")
        #expect(rope.position.y == floor.y && rope.rotation == 0)
        #expect(rope.position.x > rope.anchor.x, "let go past the hook, and flew on")
        #expect(floor.span.contains(rope.position.x))
    }

    @Test func noRopeUnderALowCeilingAndTheOtherWayWhenThereIsNoRoom() throws {
        let floor = try #require(world.floor(under: CGPoint(x: 300, y: 100)))
        #expect(Plays.Rope(from: CGPoint(x: 300, y: 25), ceilingY: 120, floor: floor.span, way: 1, clearance: 60) == nil)
        let nearRight = CGPoint(x: floor.span.upperBound - 40, y: floor.y)
        let rope = try #require(Plays.Rope(from: nearRight, ceilingY: 900, floor: floor.span, way: 1, clearance: 60))
        #expect(rope.way == -1)
    }

    // MARK: The parachute

    @Test func theParachuteOpensFloatsDownAtItsSpeedAndPacksAway() throws {
        let top = CGPoint(x: 700, y: 875)
        var chute = Plays.Chute(from: top, floorY: 25, floor: 25...1415, fallSpeed: 70)
        var events: [Plays.Chute.Event] = [], t = 0.0
        var floating: [(Double, CGFloat)] = []
        while chute.phase != .packed, t < 60 {
            events += chute.update(dt: 1.0 / 30)
            t += 1.0 / 30
            if chute.phase == .float { floating.append((t, chute.position.y)) }
            #expect(abs(chute.position.x - top.x) <= Plays.Chute.sway + 0.01)
        }
        #expect(events == [.jumped, .opened, .landed, .packed])
        let first = try #require(floating.first), last = try #require(floating.last)
        let speed = (first.1 - last.1) / CGFloat(last.0 - first.0)
        #expect(abs(speed - 70) < 3, "comes down at its speed: \(speed)")
        #expect(chute.position.y == 25 && chute.canopy == 0 && chute.rotation == 0)
        #expect(t > 8 && t < 14, "about ten seconds down a laptop screen: \(t)")
    }

    // MARK: Basketball

    @Test func theHoopHangsOnItsWallAndATrueThrowGoesIn() {
        let hoop = Plays.Hoop(wallX: 1440, side: 1, floorY: 0, height: 180, scale: 2)
        #expect(hoop.rimX == 1440 - 15 * 2 && hoop.rimHalf == 18 && hoop.rimY == 180)
        #expect(hoop.front.x == CGFloat(1392))
        let mirrored = Plays.Hoop(wallX: 0, side: -1, floorY: 0, height: 180, scale: 2)
        #expect(mirrored.rimX == 30 && mirrored.front.x == 48)
        for (h, from) in [(hoop, CGPoint(x: 1100, y: 60)), (mirrored, CGPoint(x: 340, y: 60))] {
            for apex in [50.0, 100, 150] {
                let v = Plays.Ball.aim(from: from, hoop: h, apex: CGFloat(apex))
                var ball = Plays.Ball(at: from, velocity: v, radius: 10, bounce: 0.6, hoop: h, floorY: 0, court: 0...1440)
                var events: [Plays.Ball.Event] = []
                for _ in 0..<300 { events += ball.step(dt: 1.0 / 30) }
                #expect(events.contains(.scored), "apex \(apex): \(events)")
                #expect(ball.resting, "comes to rest on the floor")
                #expect(ball.position.y == 10)
            }
        }
    }

    @Test func aShortThrowMissesAndADeadBallDoesNotBounce() {
        let hoop = Plays.Hoop(wallX: 1440, side: 1, floorY: 0, height: 180, scale: 2)
        let from = CGPoint(x: 1100, y: 60)
        var v = Plays.Ball.aim(from: from, hoop: hoop, apex: 100)
        v.dx *= 0.7
        var ball = Plays.Ball(at: from, velocity: v, radius: 12, bounce: 0.6, hoop: hoop, floorY: 0, court: 0...1440)
        var events: [Plays.Ball.Event] = []
        for _ in 0..<300 { events += ball.step(dt: 1.0 / 30) }
        #expect(!events.contains(.scored) && !ball.scored)
        var dead = Plays.Ball(at: CGPoint(x: 700, y: 300), velocity: .zero, radius: 12, bounce: 0, hoop: hoop, floorY: 0, court: 0...1440)
        for _ in 0..<60 { _ = dead.step(dt: 1.0 / 30) }
        #expect(dead.resting && dead.position.y == 12)
        var lively = Plays.Ball(at: CGPoint(x: 700, y: 300), velocity: .zero, radius: 12, bounce: 0.8, hoop: hoop, floorY: 0, court: 0...1440)
        var highest = CGFloat(0), landed = false
        for _ in 0..<60 {
            _ = lively.step(dt: 1.0 / 30)
            if lively.position.y <= 13 { landed = true } else if landed { highest = max(highest, lively.position.y) }
        }
        #expect(highest > 100, "a bouncy ball comes back up")
    }

    // MARK: The edges

    @Test func floorsCeilingsAndTheWallsAtAFloorsEnds() throws {
        let floor = try #require(world.floor(under: CGPoint(x: 700, y: 400)))
        #expect(floor.span == 25...1415)
        let walls = world.walls(of: floor)
        #expect(Set(walls.map(\.side)) == [-1, 1] && walls.allSatisfy { $0.height == 850 })
        #expect(world.ceilings.count == 1)
        // Two monitors side by side, the right one lower: the step between them is a wall seen from
        // the lower floor, and a drop (no wall) seen from the upper one.
        let two = EdgeWorld(screens: [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: -200, width: 800, height: 600)], inset: 20)
        let lower = try #require(two.floor(under: CGPoint(x: 1400, y: 0)))
        #expect(lower.y == -180)
        #expect(two.walls(of: lower).map(\.side) == [1, -1])
        #expect(two.walls(of: lower).last?.height == 200)
        let upper = try #require(two.floor(under: CGPoint(x: 500, y: 300)))
        #expect(two.walls(of: upper).map(\.side) == [-1])
        #expect(two.ceiling(over: CGPoint(x: 1400, y: 0))?.y == 380)
    }

    // MARK: The creature

    @Test func aPlayerIsCarriedIgnoresTheCursorAndComesBackDown() {
        var rng = SeededRNG(state: 3)
        var c = Creature(world: world, spot: .init(loop: 0, t: 300))
        let tookOff = c.takeOff()
        #expect(tookOff && c.isPlaying && !c.isAtLeisure)
        c.carry(to: CGPoint(x: 400, y: 400), rotation: 0.5, pose: "jump")
        #expect(c.position == CGPoint(x: 400, y: 400) && c.rotation == 0.5 && c.animation == "jump")
        let fled = c.update(dt: 0.1, cursor: CGPoint(x: 400, y: 400), using: &rng)
        #expect(!fled && c.isPlaying, "the cursor does not startle a player")
        let picked = c.pickUp(evenAwake: true)
        #expect(!picked, "nor can it be picked up mid-game")
        c.startle(using: &rng)
        #expect(c.isPlaying)
        c.touchDown()
        #expect(c.isJumping, "dropped back to the nearest edge")
        for _ in 0..<40 { c.update(dt: 0.05, cursor: nil, using: &rng) }
        #expect(!c.isPlaying && !c.isJumping)
        // Standing on the edge already, it just stands a moment.
        var standing = Creature(world: world, spot: .init(loop: 0, t: 300))
        standing.takeOff()
        standing.touchDown(standingFor: 2)
        #expect(standing.mode == .idle(remaining: 2))
        var asleep = Creature(world: world, spot: .init(loop: 0, t: 300))
        asleep.settle()
        let sleeperPlays = asleep.takeOff()
        #expect(!sleeperPlays, "a sleeper does not play")
    }

    @Test func runningCanBeSteeredEveryFrameWithoutLosingItsStride() {
        var rng = SeededRNG(state: 4)
        var c = Creature(world: world, spot: .init(loop: 0, t: 300))
        c.run(to: 900, pace: 2)
        c.update(dt: 0.2, cursor: nil, using: &rng)
        let stride = c.animationTime
        c.run(to: 950, pace: 2)
        #expect(c.isRunning && c.animationTime == stride)
        c.standStill(for: 3)
        #expect(c.mode == .idle(remaining: 3))
    }

    // MARK: Words

    @Test func everyCharacterHasALineForEveryGameAndTwoForTheEndInEveryLanguage() {
        for language in Language.allCases {
            for name in BedsTests.shipped {
                for kind in Plays.Kind.allCases {
                    #expect(Plays.startSets(language)[name]?[kind.rawValue]?.isEmpty == false, "\(name) \(kind) \(language)")
                }
                #expect(Plays.doneSets(language)[name]?.count == 2, "\(name) \(language)")
            }
            for kind in Plays.Kind.allCases { #expect(Plays.startAnyone(language)[kind.rawValue] != nil) }
            // {other} only where English has it, and in every tag line: it names the one who is "it".
            for (name, lines) in Plays.startSets(language) {
                for (kind, line) in lines {
                    let english = Plays.englishStartLines[name]?[kind] ?? ""
                    #expect(line.contains("{other}") == english.contains("{other}"), "\(name) \(kind) \(language)")
                    #expect(kind != "tag" || line.contains("{other}"), "\(name) \(language)")
                }
            }
        }
        Language.$override.withValue(.english) {
            #expect(Plays.startLine(by: "Pip", .tag, other: "Zed").contains("Zed!"))
            #expect(Plays.startLine(by: "Nobody Made", .rope, other: "") == Plays.englishStartAnyone["rope"])
            var rng = SeededRNG(state: 5)
            #expect(Plays.englishDoneAnyone.contains(Plays.doneLine(by: "Nobody Made", using: &rng)))
        }
        for p in Plays.placeholders where p != "others" { #expect(Plays.englishLinePrompt.contains("{\(p)}") && Plays.russianLinePrompt.contains("{\(p)}")) }
    }

    @Test func everyCharacterCheersInItsOwnVoiceAtEveryBigMoment() {
        for language in Language.allCases {
            for name in BedsTests.shipped {
                for moment in Plays.Moment.allCases {
                    #expect(Plays.cheerSets(language)[name]?[moment.rawValue]?.isEmpty == false, "\(name) \(moment) \(language)")
                }
            }
            for moment in Plays.Moment.allCases { #expect(Plays.cheerAnyone(language)[moment.rawValue] != nil) }
        }
        Language.$override.withValue(.english) {
            #expect(Plays.cheerLine(by: "Unit 7", .goal).contains("100%"), "Unit 7 in numbers")
            #expect(Plays.cheerLine(by: "Zed", .goal).contains("lie down"), "Zed sleepy")
            #expect(Plays.cheerLine(by: "Blocky", .goal).hasPrefix("Goal. Don't cheer."), "Blocky grumpy-proud")
            #expect(Plays.cheerLine(by: "Nobody Made", .homeRun) == Plays.englishCheerAnyone["homeRun"])
            #expect(Plays.startLine(by: "Pip", .soccer, other: "").contains("Pass to me"))
        }
        for p in Plays.cheerPlaceholders { #expect(Plays.englishCheerPrompt.contains("{\(p)}") && Plays.russianCheerPrompt.contains("{\(p)}"), "\(p)") }
        #expect(Plays.Moment.goal.asksTheModel && Plays.Moment.homeRun.asksTheModel && !Plays.Moment.oops.asksTheModel)
    }

    @Test func whatTheBallGamesLinesCostIsCountedUnderTheirOwnPurpose() {
        let usage = Spend.Usage(promptTokens: 150, completionTokens: 15, cost: 0.0006)
        let records = [Spend.Record(time: Date(), provider: "OpenRouter", model: "m", usage: usage, purpose: .ballGames)]
        let s = Spend.summarise(records, now: Date())
        Language.$override.withValue(.english) {
            #expect(s.byPurpose.first { $0.purpose == "Soccer and baseball" }?.total.cost == 0.0006)
        }
    }

    @Test func aGameIsAMomentOfTheirStory() {
        var book = Bonds.Book()
        let now = Date()
        book.note("Blocky", "Pip", Bonds.Moment(time: now, kind: .play, who: "Pip", detail: "tag"))
        let bond = book.bond("Blocky", "Pip")!
        #expect(bond.tally["play"] == 1)
        Language.$override.withValue(.english) {
            #expect(Bonds.describe(bond.moments[0], names: bond.names) == "Pip and Blocky played: a game of catch me if you can")
            #expect(Bonds.tallied(bond.tally) == "1 game")
            var rng = SeededRNG(state: 6)
            let plot = Bonds.builtInPlot(bond, now: now, using: &rng).plot
            #expect(plot.contains("a game of catch me if you can"), "the next story grows from it: \(plot)")
        }
    }

    @Test func whatTheModelsLinesCostIsCountedUnderPlays() {
        let usage = Spend.Usage(promptTokens: 120, completionTokens: 20, cost: 0.0004)
        let records = [Spend.Record(time: Date(), provider: "OpenRouter", model: "m", usage: usage, purpose: .plays)]
        let s = Spend.summarise(records, now: Date())
        Language.$override.withValue(.english) {
            #expect(s.byPurpose.first { $0.purpose == "Plays" }?.total.cost == 0.0004)
        }
    }
}

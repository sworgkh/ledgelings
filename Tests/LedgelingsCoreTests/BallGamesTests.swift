import CoreGraphics
import Foundation
import Testing
@testable import LedgelingsCore

/// Soccer and baseball: who plays on which side, where the pitch and the bases
/// go, goals, throw-ins, home runs, and whole games played to the end.
@Suite struct BallGamesTests {
    static let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    static let inset: CGFloat = 25
    let world = EdgeWorld(screens: [BallGamesTests.screen], inset: BallGamesTests.inset)
    /// Two monitors: a wide one, raised, and a narrower, taller one to its right whose floor is lower.
    static let stepped = EdgeWorld(screens: [CGRect(x: 0, y: 300, width: 1600, height: 900), CGRect(x: 1600, y: 0, width: 800, height: 1300)], inset: 25)

    // MARK: Who plays, on which side

    @Test func theLineupFollowsHowManyThereAre() {
        #expect(Plays.Lineup.soccer(1) == .solo && Plays.Lineup.soccer(2) == .duel)
        #expect(Plays.Lineup.soccer(3) == .keeper, "three play one goal")
        #expect(Plays.Lineup.soccer(4) == .teams && Plays.Lineup.soccer(7) == .teams)
        #expect(Plays.Lineup.baseball(1) == .solo && Plays.Lineup.baseball(2) == .duel)
        #expect(Plays.Lineup.baseball(3) == .rotation && Plays.Lineup.baseball(5) == .rotation)
        #expect(Plays.Lineup.baseball(6) == .teams)
    }

    @Test func bestFriendsEndUpOnTheSameSide() {
        // 0 & 3 are best friends, so are 1 & 2: the split keeps both pairs together.
        let close: (Int, Int) -> Double = { a, b in Set([a, b]) == [0, 3] || Set([a, b]) == [1, 2] ? 1 : 0.05 }
        let four = Plays.split([0, 1, 2, 3], closeness: close)
        #expect(Set(four[0]) == [0, 3] && Set(four[1]) == [1, 2])
        let six = Plays.split([0, 1, 2, 3, 4, 5], closeness: close)
        #expect(six[0].count == 3 && six[1].count == 3, "even sides")
        #expect(six.contains { Set([0, 3]).isSubset(of: $0) } && six.contains { Set([1, 2]).isSubset(of: $0) })
        let five = Plays.split([0, 1, 2, 3, 4], closeness: close)
        #expect(five[0].count == 3 && five[1].count == 2 && five[0].contains(0), "the starter's side the bigger")
        // From six a side has a keeper: the one with fewest friends there.
        #expect(Plays.keeper(of: [0, 3, 4], closeness: close) == 4)
    }

    @Test func friendsJoinFirstUpToTheMost() {
        let crowd: [(index: Int, closeness: Double)] = [(1, 0.1), (2, 0.9), (3, 0.5), (4, 0)]
        #expect(Plays.joining(initiator: 0, crowd: crowd, max: 3) == [0, 2, 3])
        #expect(Plays.joining(initiator: 0, crowd: crowd, max: 1) == [0], "alone")
        var rng = SeededRNG(state: 2)
        var picked: Set<Plays.Kind> = []
        for _ in 0..<200 {
            if let game = Plays.chooseTeamGame(initiator: 0, crowd: crowd, enabled: Set(Plays.Kind.allCases),
                                               maxPlayers: [.soccer: 4, .baseball: 2], using: &rng) {
                picked.insert(game.kind)
                #expect(game.players.count == (game.kind == .soccer ? 4 : 2))
            }
        }
        #expect(picked == [.soccer, .baseball])
        #expect(Plays.chooseTeamGame(initiator: 0, crowd: crowd, enabled: [.tag, .rope], maxPlayers: [:], using: &rng) == nil)
        #expect(Plays.teamChance(crowd: 0) < Plays.teamChance(crowd: 4), "a crowd plays together more")
        // The old games never pick a team game for one or two.
        for _ in 0..<100 {
            let game = Plays.choose(initiator: 0, others: [(1, 1)], enabled: Set(Plays.Kind.allCases), using: &rng)
            #expect(game.map { !$0.kind.isTeamGame } == true)
        }
    }

    // MARK: Soccer

    @Test func thePitchIsTheWidestFloor() throws {
        // A wide monitor standing higher than a narrower one beside it: the wide one's floor wins.
        let pitch = try #require(Plays.Pitch.choose(in: Self.stepped, inset: 25))
        #expect(pitch.floorY == 300 && pitch.span == 0...1600)
        #expect(pitch.wallLeft && !pitch.wallRight, "the floor steps down onto the next monitor: no wall, the ball falls off")
        let one = try #require(Plays.Pitch.choose(in: world, inset: Self.inset))
        #expect(one.span == 0...1440 && one.wallLeft && one.wallRight)
        let tiny = EdgeWorld(screens: [CGRect(x: 0, y: 0, width: 250, height: 400)], inset: 25)
        #expect(Plays.Pitch.choose(in: tiny, inset: 25) == nil, "too short to play on")
    }

    func match(_ ids: [Int], teams: [[Int]]? = nil, keepers: Set<Int> = [], goals: Int = 3, length: Double = 120,
               in w: EdgeWorld? = nil, seed: UInt64 = 1) throws -> (Plays.Soccer, SeededRNG) {
        var rng = SeededRNG(state: seed)
        let pitch = try #require(Plays.Pitch.choose(in: w ?? world, inset: Self.inset))
        let s = Plays.Soccer(players: ids, teams: teams, keepers: keepers, halves: Dictionary(uniqueKeysWithValues: ids.map { ($0, 25) }),
                             pitch: pitch, scale: 2.5, goalsToWin: goals, length: length, using: &rng)
        return (s, rng)
    }

    func play(_ s: inout Plays.Soccer, _ rng: inout SeededRNG, seconds: Double = 400) -> [Plays.Soccer.Event] {
        var events: [Plays.Soccer.Event] = []
        var t = 0.0
        while !s.isFinished, t < seconds {
            events += s.update(dt: 1.0 / 60, using: &rng)
            t += 1.0 / 60
        }
        return events
    }

    @Test func eachCountHasItsGoals() throws {
        #expect(try match([0]).0.goals.count == 1, "one alone shoots at one goal")
        #expect(try match([0]).0.phase == .juggling, "and starts with keepy-uppy")
        let duel = try match([0, 1]).0
        #expect(duel.goals.count == 2 && Set(duel.players.map(\.team)) == [0, 1])
        let three = try match([0, 1, 2]).0
        #expect(three.goals.count == 1 && three.players.filter(\.isKeeper).map(\.index) == [2], "one goal, one keeper, two attackers")
        let four = try match([0, 1, 2, 3], teams: [[0, 3], [1, 2]]).0
        #expect(four.goals.count == 2 && four.players.filter(\.isKeeper).isEmpty, "no keepers under six")
        let six = try match([0, 1, 2, 3, 4, 5], teams: [[0, 1, 2], [3, 4, 5]], keepers: [2, 5]).0
        #expect(Set(six.players.filter(\.isKeeper).map(\.index)) == [2, 5])
        #expect(six.player(2)?.team == 0 && six.player(5)?.team == 1)
    }

    @Test func aMatchIsPlayedToTheEnd() throws {
        for (ids, seed) in [([0], UInt64(1)), ([0, 1], 2), ([0, 1, 2], 3), ([0, 1, 2, 3, 4], 4)] {
            let teams = ids.count >= 4 ? Plays.split(ids) { _, _ in 0 } : nil
            var (s, rng) = try match(ids, teams: teams, goals: 2, length: 90, seed: seed)
            let events = play(&s, &rng)
            #expect(s.isFinished, "\(ids.count) players: the match ends")
            #expect(events.contains(.over))
            let goals = events.filter { if case .goal = $0 { true } else { false } }.count
            #expect(goals == s.goalsBy.values.reduce(0, +), "every goal counted")
            #expect(goals >= 1 || s.clock >= 90, "\(ids.count) players: a goal, or the time ran out (\(s.clock))")
            if ids.count == 1 { #expect(events.contains { if case .touches = $0 { true } else { false } }, "keepy-uppy first") }
            if ids.count == 3, goals > 0 { #expect(events.contains { if case .keeperNow = $0 { true } else { false } }, "the keeper changes after a goal") }
            for p in s.players { #expect(s.pitch.span.contains(p.x), "nobody leaves the pitch") }
        }
    }

    @Test func aGoalIsScoredOnlyUnderTheBar() throws {
        var (s, rng) = try match([0, 1], goals: 3)
        s.phase = .play
        let right = s.goals.first { $0.side > 0 }!
        // Low, into the right goal: team 0 (who attacks right) scores, the scorer credited.
        s.lastTouch = 0
        s.ball.position = CGPoint(x: right.x - 6, y: s.pitch.floorY + s.ball.radius + 4)
        s.ball.velocity = CGVector(dx: 600, dy: 0)
        let events = s.update(dt: 0.05, using: &rng)
        #expect(events.contains(.goal(by: 0, score: "0 1 : 0 1")), "\(events)")
        #expect(s.teamGoals == [1, 0] && s.goalsBy[0] == 1 && s.phase == .goal)
        #expect(s.board { ["Blocky", "Zed"][$0] } == "Blocky 1 : 0 Zed")
        // Over the bar: no goal.
        var (high, rng2) = try match([0, 1], goals: 3)
        high.phase = .play
        high.lastTouch = 0
        high.ball.position = CGPoint(x: right.x - 6, y: high.pitch.floorY + right.height + 30)
        high.ball.velocity = CGVector(dx: 600, dy: 0)
        _ = high.update(dt: 0.05, using: &rng2)
        #expect(high.teamGoals == [0, 0])
    }

    @Test func offTheEndWithNoWallItIsBroughtBackWithAThrowIn() throws {
        var (s, rng) = try match([0, 1], in: Self.stepped)
        s.phase = .play
        s.lastTouch = 1
        // Over the bar at the right, where the floor just ends.
        s.ball.position = CGPoint(x: s.pitch.span.upperBound - 8, y: s.pitch.floorY + 200)
        s.ball.velocity = CGVector(dx: 500, dy: 0)
        var events: [Plays.Soccer.Event] = []
        for _ in 0..<600 { events += s.update(dt: 1.0 / 60, using: &rng); if events.contains(where: { if case .throwIn = $0 { true } else { false } }) { break } }
        #expect(events.contains(.out(by: 1)))
        #expect(events.contains(.throwIn(by: 0)), "the other side brings it back: \(events)")
        #expect(s.phase == .play && s.pitch.span.contains(s.ball.position.x))
        // With a wall, the same ball bounces back in.
        var (walled, rng2) = try match([0, 1])
        walled.phase = .play
        walled.ball.position = CGPoint(x: walled.pitch.span.upperBound - 8, y: walled.pitch.floorY + 200)
        walled.ball.velocity = CGVector(dx: 500, dy: 0)
        var more: [Plays.Soccer.Event] = []
        for _ in 0..<30 { more += walled.update(dt: 1.0 / 60, using: &rng2) }
        #expect(!more.contains { if case .out = $0 { true } else { false } } && walled.ball.velocity.dx < 0, "off the wall")
    }

    @Test func theTimeRunsOut() throws {
        var (s, rng) = try match([0, 1, 2, 3], teams: [[0, 1], [2, 3]], goals: 99, length: 30)
        _ = play(&s, &rng)
        #expect(s.isFinished && s.clock >= 30 && s.clock < 45)
    }

    // MARK: Baseball

    @Test func theBasesGoOnThreeOtherEdgesRoundTheScreen() throws {
        let home = world.nearest(to: CGPoint(x: 300, y: 25))
        let field = try #require(Plays.Field.choose(in: world, inset: Self.inset, batter: home))
        #expect(field.home.edge.y == 0, "home on the batter's floor")
        #expect(field.mound.edge.y == 0 && abs(field.mound.edge.x - field.home.edge.x) > 300, "the pitcher on the same floor, away from home")
        // First on the right wall, second on the ceiling, third on the left wall: a diamond the size of the screen.
        let b = field.bases.map(\.edge)
        #expect(b[0].x == 1440 && b[1].y == 900 && b[2].x == 0, "\(b)")
        // A batter on a wall: home goes on the floor.
        let onWall = try #require(Plays.Field.choose(in: world, inset: Self.inset, batter: world.nearest(to: CGPoint(x: 1415, y: 400))))
        #expect(onWall.home.edge.y == 0)
        // Two monitors: still three other edges, as far apart as can be.
        let two = EdgeWorld(screens: [CGRect(x: 0, y: 0, width: 1600, height: 900), CGRect(x: 1600, y: 200, width: 1000, height: 1100)], inset: 25)
        let wide = try #require(Plays.Field.choose(in: two, inset: 25, batter: two.nearest(to: CGPoint(x: 400, y: 25))))
        let spread = wide.bases.map { hypot($0.edge.x - wide.home.edge.x, $0.edge.y - wide.home.edge.y) }
        #expect(spread.allSatisfy { $0 > 500 }, "\(wide.bases.map(\.edge))")
    }

    func game(_ ids: [Int], innings: Int = 1, seed: UInt64 = 1, closeness: @escaping (Int, Int) -> Double = { _, _ in 0 }) throws -> (Plays.Baseball, SeededRNG) {
        let home = world.nearest(to: CGPoint(x: 300, y: 25))
        let field = try #require(Plays.Field.choose(in: world, inset: Self.inset, batter: home))
        let starts = Dictionary(uniqueKeysWithValues: ids.map { ($0, field.home) })
        let teams = ids.count >= 6 ? Plays.split(ids, closeness: closeness) : nil
        let g = Plays.Baseball(players: ids, teams: teams, starts: starts, halves: Dictionary(uniqueKeysWithValues: ids.map { ($0, 25) }),
                               field: field, innings: innings, closeness: closeness)
        return (g, SeededRNG(state: seed))
    }

    func play(_ g: inout Plays.Baseball, _ rng: inout SeededRNG, seconds: Double = 1200) -> [Plays.Baseball.Event] {
        var events: [Plays.Baseball.Event] = []
        var t = 0.0
        while !g.isFinished, t < seconds {
            events += g.update(dt: 1.0 / 60, using: &rng)
            t += 1.0 / 60
        }
        return events
    }

    @Test func aGameIsPlayedToTheEndForEveryCount() throws {
        for (ids, seed) in [([0], UInt64(1)), ([0, 1], 2), ([0, 1, 2], 3), ([0, 1, 2, 3, 4], 4), ([0, 1, 2, 3, 4, 5], 5)] {
            var (g, rng) = try game(ids, seed: seed)
            let events = play(&g, &rng)
            #expect(g.isFinished, "\(ids.count) players: the game ends")
            let runs = events.filter { if case .scored = $0 { true } else { false } }.count
            #expect(runs == g.runsBy.values.reduce(0, +) && runs == g.sideRuns.reduce(0, +), "every run counted")
            if ids.count == 1 {
                #expect(g.swings == g.practiceSwings && !events.contains { if case .pitch = $0 { true } else { false } }, "alone: practice swings, no pitcher")
            } else {
                #expect(events.contains { if case .pitch = $0 { true } else { false } })
                #expect(events.contains { if case .out = $0 { true } else { false } })
                #expect(events.contains { if case .sidesChange = $0 { true } else { false } } || ids.count == 1)
            }
            for a in g.actors { #expect(!a.isHopping, "everyone has landed") }
        }
    }

    @Test func threeStrikesAndYouAreOut() throws {
        var (g, rng) = try game([0, 1])
        var events: [Plays.Baseball.Event] = []
        var t = 0.0
        while !events.contains(where: { if case .out(_, "struck out") = $0 { true } else { false } }), t < 600 {
            events += g.update(dt: 1.0 / 60, using: &rng); t += 1.0 / 60
        }
        let strikes = events.compactMap { if case .strike(let by, let n) = $0 { (by, n) } else { nil } }
        let out = try #require(events.firstIndex { if case .out(_, "struck out") = $0 { true } else { false } })
        if case .out(let by, _) = events[out] { #expect(strikes.last { $0.0 == by }?.1 == 3) }
    }

    @Test func aHomeRunGoesOutTheTopAndBringsEveryoneHome() throws {
        // Best of friends pitching: more hits, and more home runs.
        var found = false
        for seed in UInt64(1)...40 where !found {
            var (g, rng) = try game([0, 1, 2], innings: 2, seed: seed, closeness: { _, _ in 1 })
            var t = 0.0
            while !g.isFinished, t < 900 {
                for e in g.update(dt: 1.0 / 60, using: &rng) {
                    guard case .homeRun(let by, let runs) = e, runs > 1 else { continue }
                    let before = g.runsBy.values.reduce(0, +)
                    #expect(g.lastHomeRun.map { $0.y >= g.field.top - 20 } == true, "out through the top")
                    for _ in 0..<(60 * 8) { _ = g.update(dt: 1.0 / 60, using: &rng) }
                    #expect(g.runsBy.values.reduce(0, +) >= before + runs, "\(by) and every runner score")
                    found = true
                }
                if found { break }
                t += 1.0 / 60
            }
        }
        #expect(found, "a home run with someone on base")
    }

    @Test func friendsHitMore() throws {
        func hits(_ c: Double) throws -> Int {
            var total = 0
            for seed in UInt64(1)...6 {
                var (g, rng) = try game([0, 1], innings: 2, seed: seed, closeness: { _, _ in c })
                _ = play(&g, &rng)
                total += g.hits
            }
            return total
        }
        #expect(try hits(1) > hits(0))
    }

    @Test func theBoardSaysTheScore() throws {
        Language.$override.withValue(.english) {
            var (g, _) = try! game([0])
            g.hits = 3; g.homeRuns = 1
            #expect(g.board { _ in "Blocky" } == "Blocky: 3 hits, 1 home run")
            var (two, _) = try! game([0, 1])
            two.sideRuns = [2, 1]
            #expect(two.board { ["Blocky", "Zed"][$0] } == "Blocky 2  Zed 1  · inning 1/1, 0 out")
        }
    }
}

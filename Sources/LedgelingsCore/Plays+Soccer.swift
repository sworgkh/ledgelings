import CoreGraphics
import Foundation

/// Soccer on one long floor: the widest one there is becomes the pitch, with a
/// little net at its ends. One plays keepy-uppy and shoots at an empty goal; two
/// have a goal each; three play one goal, a keeper and two attackers, the keeper
/// changing after each goal; four or more split into two teams by friendship,
/// with a keeper each from six.
///
/// They dribble, pass, steal the ball with a slide (nobody is knocked down),
/// shoot, head it, and the keepers dive. A ball over the bar bounces off the
/// screen's wall behind the goal, or, where the floor just ends, falls off and
/// is brought back with a throw-in. First to `goalsToWin`, or the best score
/// when time is up.
///
/// Pure, like the other games: the colony reads where everyone is each frame.
extension Plays {

    /// The pitch: the widest floor, in screen points (the edge itself, not where
    /// a creature's centre goes). Nil when no floor is long enough to play on.
    public struct Pitch: Equatable, Sendable {
        public static let shortest: CGFloat = 300
        public var level: EdgeWorld.Level
        /// The screen's floor, and its two ends.
        public var floorY: CGFloat
        public var span: ClosedRange<CGFloat>
        /// A wall rises at that end: the ball bounces off it rather than falling off.
        public var wallLeft: Bool
        public var wallRight: Bool
        public var length: CGFloat { span.upperBound - span.lowerBound }

        public init(level: EdgeWorld.Level, floorY: CGFloat, span: ClosedRange<CGFloat>, wallLeft: Bool, wallRight: Bool) {
            self.level = level
            self.floorY = floorY
            self.span = span
            self.wallLeft = wallLeft
            self.wallRight = wallRight
        }

        /// The widest floor of `world` (whose loops are `inset` in from the screens),
        /// the lower one when two are as wide.
        public static func choose(in world: EdgeWorld, inset: CGFloat) -> Pitch? {
            guard let widest = world.floors.max(by: { a, b in
                let la = a.span.upperBound - a.span.lowerBound, lb = b.span.upperBound - b.span.lowerBound
                return abs(la - lb) > 0.5 ? la < lb : a.y > b.y
            }) else { return nil }
            let walls = world.walls(of: widest)
            let wallLeft = walls.contains { $0.side < 0 }, wallRight = walls.contains { $0.side > 0 }
            // A wall stands half a body beyond the line a creature walks; where the floor
            // steps down, the edge ends half a body before it.
            let span = (widest.span.lowerBound + (wallLeft ? -inset : inset))...(widest.span.upperBound + (wallRight ? inset : -inset))
            guard span.upperBound - span.lowerBound >= shortest else { return nil }
            return Pitch(level: widest, floorY: widest.y - inset, span: span, wallLeft: wallLeft, wallRight: wallRight)
        }
    }

    public struct Soccer: Equatable, Sendable {
        public enum Phase: Equatable, Sendable { case juggling, kickoff, play, goal, outOfPlay, over }

        public enum Event: Equatable, Sendable {
            case kickoff(by: Int)
            /// Keepy-uppy, done: this many touches before it dropped.
            case touches(by: Int, count: Int)
            case pass(from: Int, to: Int)
            case shot(by: Int)
            case header(by: Int)
            /// In: `score` as the board shows it.
            case goal(by: Int, score: String)
            case save(by: Int)
            /// Off the post or the bar.
            case woodwork(by: Int)
            /// Swung at it and kicked the air.
            case whiff(by: Int)
            case tackle(by: Int, from: Int)
            /// Off the pitch; whoever touched it last.
            case out(by: Int?)
            case throwIn(by: Int)
            case wandersOff(Int)
            case comesBack(Int)
            /// In keeper mode: the new one in goal.
            case keeperNow(Int)
            case over
        }

        /// One player: where it is on the pitch and what it is doing. `index` is the creature.
        public struct Player: Equatable, Sendable {
            public let index: Int
            public internal(set) var team: Int
            public internal(set) var isKeeper: Bool
            public let half: CGFloat
            public let speed: CGFloat
            public internal(set) var x: CGFloat
            /// How far above standing it is: jumping, diving, celebrating.
            public internal(set) var lift: CGFloat = 0
            public internal(set) var rotation: Double = 0
            public internal(set) var facing: CGFloat = 1
            public internal(set) var pose = "idle"
            var rise: CGFloat = 0
            var act: Act = .none
            var actLeft = 0.0
            var cooldown = 0.0
            var spot: CGFloat?
            var shootFrom: CGFloat?

            enum Act: Equatable, Sendable { case none, dive(CGFloat), slide(CGFloat), stagger, whiff, wander(CGFloat), cheer, header }
            public var isWandering: Bool { if case .wander = act { true } else { false } }
            var isBusy: Bool { act != .none && act != .cheer }
        }

        /// A net at one end of the pitch: its mouth `x` (the goal line), `side` +1 at the right end.
        public struct Goal: Equatable, Sendable {
            public var x: CGFloat
            public var side: CGFloat
            /// The crossbar, above the floor.
            public var height: CGFloat
            /// The team that keeps it, or nil (nobody's: one plays alone).
            public var keptBy: Int?
        }

        public struct Ball: Equatable, Sendable {
            public internal(set) var position: CGPoint
            public internal(set) var velocity: CGVector = .zero
            public let radius: CGFloat
            /// Spun this far, for drawing.
            public internal(set) var turn: Double = 0
            public internal(set) var opacity: Double = 1
        }

        /// The net's shape in sheet pixels, as `spritetool/painters/play.py` draws it in
        /// its 32×28 cell, mouth to the left: the post's outer column, the crossbar's top row.
        public enum Net {
            public static let mouthColumn: CGFloat = 16
            public static let barRow: CGFloat = 4
            /// The ball's radius, in sheet pixels.
            public static let ballRadius: CGFloat = 4
        }

        public static let gravity: CGFloat = 1400
        public static let goalTime = 2.8
        public static let overTime = 2.6
        /// A second's worth of steps: the match is stepped this finely.
        static let step = 1.0 / 120

        public let lineup: Lineup
        public let pitch: Pitch
        public let scale: CGFloat
        public let goalsToWin: Int
        public let length: Double
        public internal(set) var players: [Player]
        public internal(set) var goals: [Goal]
        public internal(set) var ball: Ball
        public internal(set) var phase: Phase
        /// Goals by creature, and by team (in duel and team play).
        public internal(set) var goalsBy: [Int: Int] = [:]
        public internal(set) var teamGoals = [0, 0]
        public internal(set) var clock = 0.0
        public internal(set) var lastScorer: Int?
        /// The one bringing the ball back for a throw-in, and the one holding it up for a header.
        public internal(set) var thrower: Int?
        /// The ball is in someone's hands, up for a throw-in.
        public internal(set) var ballHeld = false
        var phaseLeft = 0.0
        var lastTouch: Int?
        var juggles = 0
        var juggleTarget = 6
        var kicker: Int?
        var wanderAt: Double?
        var keeperOrder: [Int] = []
        var finished = false

        /// A match on `pitch` for `players` (creature indices, the first started it),
        /// lined up by how many there are; `teams` the two sides for team play
        /// (`Plays.split`), `keepers` their keepers. `halves` each one's half size in
        /// points, `scale` points per sheet pixel for the net and the ball; `at` where
        /// each stands along the pitch to begin with (the middle, if not given).
        public init(players ids: [Int], teams: [[Int]]? = nil, keepers: Set<Int> = [], halves: [Int: CGFloat], at: [Int: CGFloat] = [:],
                    pitch: Pitch, scale: CGFloat, goalsToWin: Int, length: Double,
                    using rng: inout some RandomNumberGenerator) {
            lineup = Lineup.soccer(ids.count)
            self.pitch = pitch
            self.scale = scale
            self.goalsToWin = max(1, goalsToWin)
            self.length = max(20, length)
            let lo = pitch.span.lowerBound, hi = pitch.span.upperBound
            let height = (Plays.Props.cell.height - Net.barRow) * scale
            let depth = (Plays.Props.cell.width - Net.mouthColumn) * scale
            let right = Goal(x: hi - depth, side: 1, height: height, keptBy: nil)
            let left = Goal(x: lo + depth, side: -1, height: height, keptBy: nil)
            var sides: [[Int]]
            switch lineup {
            case .solo: sides = [ids, []]; goals = [right]
            case .duel: sides = [[ids[0]], [ids[1]]]; goals = [left.kept(by: 0), right.kept(by: 1)]
            case .keeper: sides = [Array(ids.prefix(2)), [ids[2]]]; goals = [right.kept(by: 1)]
            case .teams, .rotation: sides = teams ?? Plays.split(ids) { _, _ in 0 }; goals = [left.kept(by: 0), right.kept(by: 1)]
            }
            var everyone: [Player] = []
            for (team, members) in sides.enumerated() {
                for id in members {
                    everyone.append(Player(index: id, team: team, isKeeper: keepers.contains(id) || (lineup == .keeper && team == 1),
                                           half: halves[id] ?? 20, speed: 150 * .random(in: 0.88...1.12, using: &rng),
                                           x: min(max(at[id] ?? (lo + hi) / 2, lo), hi)))
                }
            }
            players = everyone
            keeperOrder = lineup == .keeper ? [ids[2], ids[0], ids[1]] : []
            ball = Ball(position: CGPoint(x: (lo + hi) / 2, y: pitch.floorY + Net.ballRadius * scale), radius: Net.ballRadius * scale)
            phase = .kickoff
            if lineup == .solo {
                phase = .juggling
                juggleTarget = .random(in: 4...9, using: &rng)
                ball.position = CGPoint(x: players[0].x + 4, y: pitch.floorY + players[0].half * 2.6)
            } else {
                lineUp(kickoffBy: 1, using: &rng)
            }
            if ids.count >= 3, Double.random(in: 0..<1, using: &rng) < 0.45 {
                wanderAt = self.length * .random(in: 0.25...0.6, using: &rng)
            }
        }

        /// The match is over and everyone has cheered: let them go.
        public var isFinished: Bool { finished }

        public func player(_ index: Int) -> Player? { players.first { $0.index == index } }

        /// Where creature `index` is: its centre in screen points.
        public func position(of index: Int) -> CGPoint? {
            player(index).map { CGPoint(x: $0.x, y: pitch.floorY + $0.half + $0.lift) }
        }

        /// The score as the board shows it: "Blocky 2 : 1 Zed" for two sides,
        /// each player's goals for one goal or one player. `name` names a creature.
        public func board(_ name: (Int) -> String) -> String {
            switch lineup {
            case .solo:
                return "\(name(players[0].index)) \(goalsBy[players[0].index, default: 0])"
            case .keeper:
                return players.map { "\(name($0.index)) \(goalsBy[$0.index, default: 0])" }.joined(separator: "  ")
            case .duel, .teams, .rotation:
                func side(_ t: Int) -> String {
                    let members = players.filter { $0.team == t }
                    return members.count == 1 ? name(members[0].index) : tr("%@'s team", name(members[0].index))
                }
                return "\(side(0)) \(teamGoals[0]) : \(teamGoals[1]) \(side(1))"
            }
        }

        // MARK: Running

        public mutating func update(dt: Double, using rng: inout some RandomNumberGenerator) -> [Event] {
            var events: [Event] = []
            var left = dt
            while left > 1e-9, !finished {
                let h = min(left, Self.step)
                left -= h
                tick(h, &events, &rng)
            }
            return events
        }

        mutating func tick(_ dt: Double, _ events: inout [Event], _ rng: inout some RandomNumberGenerator) {
            if phase != .over, phase != .goal { clock += dt }
            phaseLeft -= dt
            for k in players.indices { players[k].cooldown -= dt }
            switch phase {
            case .juggling: juggle(dt, &events, &rng)
            case .kickoff:
                for k in players.indices { run(k, to: players[k].spot ?? players[k].x, dt, pace: 1.1) }
                settle(dt)
                if lineup == .solo {
                    // Carrying the ball back over its head, for more keepy-uppy.
                    ball.position = CGPoint(x: players[0].x, y: pitch.floorY + players[0].half * 2 + ball.radius)
                    if phaseLeft <= 0 {
                        phase = .juggling
                        ballHeld = false
                        juggles = 0
                        juggleTarget = .random(in: 4...9, using: &rng)
                        ball.velocity = CGVector(dx: 0, dy: 200)
                    }
                } else if phaseLeft <= 0 {
                    phase = .play
                    if let k = kicker.flatMap(slot) {
                        let d = attack(players[k].team)
                        kick(k, CGVector(dx: d * 170, dy: 60))
                        events.append(.kickoff(by: players[k].index))
                    }
                }
            case .play:
                play(dt, &events, &rng)
                if clock >= length { end(&events) }
            case .goal:
                celebrate(dt)
                settle(dt)
                if phaseLeft <= 0 {
                    if lineup == .solo {
                        phase = .kickoff
                        phaseLeft = 2.4
                        ballHeld = true
                        ball.velocity = .zero
                        ball.opacity = 1
                        players[0].act = .none
                        players[0].spot = lo + (hi - lo) * 0.35
                    } else {
                        lineUp(kickoffBy: conceding, using: &rng)
                    }
                    if won { end(&events) }
                }
            case .outOfPlay:
                throwIn(dt, &events, &rng)
            case .over:
                celebrate(dt)
                settle(dt)
                if phaseLeft <= 0 { finished = true }
            }
            if !ballHeld { flight(dt, &events, &rng) }
        }

        var won: Bool {
            switch lineup {
            case .solo, .keeper: goalsBy.values.contains { $0 >= goalsToWin }
            default: teamGoals.contains { $0 >= goalsToWin }
            }
        }

        /// The side that let the last one in kicks off.
        var conceding: Int {
            guard let s = lastScorer, let p = player(s) else { return 1 }
            return 1 - p.team
        }

        mutating func end(_ events: inout [Event]) {
            guard phase != .over else { return }
            phase = .over
            phaseLeft = Self.overTime
            events.append(.over)
            for k in players.indices where players[k].isBusy { players[k].act = .none }
            for k in players.indices where winners.contains(players[k].index) { players[k].act = .cheer }
        }

        /// Who won: the best side, or the best scorer; nobody when it is level.
        public var winners: Set<Int> {
            switch lineup {
            case .solo:
                return goalsBy.isEmpty ? [] : [players[0].index]
            case .keeper:
                guard let best = goalsBy.values.max(), goalsBy.values.filter({ $0 == best }).count == 1 else { return [] }
                return Set(goalsBy.filter { $0.value == best }.keys)
            default:
                guard teamGoals[0] != teamGoals[1] else { return [] }
                let t = teamGoals[0] > teamGoals[1] ? 0 : 1
                return Set(players.filter { $0.team == t }.map(\.index))
            }
        }

        func slot(_ index: Int) -> Int? { players.firstIndex { $0.index == index } }

        /// Which way a team attacks: team 0 to the right.
        func attack(_ team: Int) -> CGFloat { team == 0 ? 1 : -1 }

        /// The goal a team shoots at.
        func target(of team: Int) -> Goal? {
            lineup == .solo || lineup == .keeper ? (team == 0 ? goals[0] : nil) : goals.first { $0.keptBy == 1 - team }
        }

        func own(_ team: Int) -> Goal? { goals.first { $0.keptBy == team } }

        var lo: CGFloat { pitch.span.lowerBound }
        var hi: CGFloat { pitch.span.upperBound }
        var middle: CGFloat { (lo + hi) / 2 }

        /// Everyone to their own half (keepers in goal), the ball on the spot, `team` to kick off.
        mutating func lineUp(kickoffBy team: Int, using rng: inout some RandomNumberGenerator) {
            phase = .kickoff
            phaseLeft = 2.2
            ball.position = CGPoint(x: middle, y: pitch.floorY + ball.radius)
            ball.velocity = .zero
            ball.opacity = 1
            lastTouch = nil
            for t in 0...1 {
                let members = players.indices.filter { players[$0].team == t && !players[$0].isKeeper }
                for (n, k) in members.enumerated() {
                    let d = attack(t)
                    // Spread through the own half, the kicker on the ball.
                    let share = CGFloat(n + 1) / CGFloat(members.count + 1)
                    players[k].spot = middle - d * (40 + (hi - lo) / 2 * 0.7 * share)
                }
                for k in players.indices where players[k].team == t && players[k].isKeeper {
                    if let g = own(t) { players[k].spot = g.x - g.side * (players[k].half + 6) }
                }
            }
            let takers = players.indices.filter { players[$0].team == team && !players[$0].isKeeper }
            if let k = takers.randomElement(using: &rng) ?? players.indices.first(where: { !players[$0].isKeeper }) {
                players[k].spot = middle - attack(players[k].team) * (players[k].half + ball.radius)
                kicker = players[k].index
            }
            for k in players.indices {
                players[k].act = .none
                players[k].spot = players[k].spot.map { clamp($0, k) }
            }
        }

        func clamp(_ x: CGFloat, _ k: Int) -> CGFloat {
            min(max(x, lo + players[k].half), hi - players[k].half)
        }

        /// Run player `k` toward `x` at its speed (times `pace`), facing the way it goes.
        mutating func run(_ k: Int, to x: CGFloat, _ dt: Double, pace: CGFloat = 1) {
            let to = clamp(x, k)
            let gap = to - players[k].x
            let stride = players[k].speed * pace * CGFloat(dt)
            if abs(gap) > 2 {
                players[k].x += max(-stride, min(stride, gap))
                players[k].facing = gap > 0 ? 1 : -1
                if players[k].lift == 0, !players[k].isBusy { players[k].pose = "walk" }
            } else if players[k].lift == 0, !players[k].isBusy {
                players[k].pose = "idle"
                players[k].facing = ball.position.x >= players[k].x ? 1 : -1
            }
        }

        /// Falling back down after a jump, and the rotation coming back upright.
        mutating func settle(_ dt: Double) {
            for k in players.indices {
                var p = players[k]
                if p.lift > 0 || p.rise > 0 {
                    p.rise -= Self.gravity * CGFloat(dt)
                    p.lift += p.rise * CGFloat(dt)
                    if p.lift <= 0 { p.lift = 0; p.rise = 0; p.pose = "land" }
                }
                p.actLeft -= dt
                if p.actLeft <= 0, p.isBusy, !p.isWandering {
                    p.act = .none
                    p.rotation = 0
                }
                if p.act == .none, p.lift == 0, abs(p.rotation) > 0.01 { p.rotation *= max(0, 1 - 10 * dt) }
                players[k] = p
            }
        }

        mutating func kick(_ k: Int, _ v: CGVector) {
            ball.velocity = v
            lastTouch = players[k].index
            players[k].cooldown = 0.3
            players[k].facing = v.dx >= 0 ? 1 : -1
        }

        // MARK: Keepy-uppy

        mutating func juggle(_ dt: Double, _ events: inout [Event], _ rng: inout some RandomNumberGenerator) {
            let k = 0
            run(k, to: ball.position.x, dt, pace: 0.7)
            settle(dt)
            let foot = pitch.floorY + players[k].half * 0.9
            guard ball.velocity.dy < 0, ball.position.y < foot, abs(ball.position.x - players[k].x) < players[k].half * 1.3 else {
                if ball.position.y <= pitch.floorY + ball.radius + 0.5, ball.velocity.dy == 0 { dropped(&events) }
                return
            }
            juggles += 1
            players[k].pose = "jump"
            players[k].rise = 120
            players[k].lift = max(players[k].lift, 0.1)
            let fumble = juggles >= 3 && Double.random(in: 0..<1, using: &rng) < 0.1
            if juggles >= juggleTarget || fumble {
                // The last one goes off sideways and it is a game again.
                kick(k, CGVector(dx: (fumble ? -1 : 1) * .random(in: 60...120, using: &rng), dy: 240))
                events.append(.touches(by: players[k].index, count: juggles))
                phase = .play
            } else {
                kick(k, CGVector(dx: (players[k].x - ball.position.x) * 2 + .random(in: -25...25, using: &rng),
                                 dy: .random(in: 330...430, using: &rng)))
            }
        }

        mutating func dropped(_ events: inout [Event]) {
            events.append(.touches(by: players[0].index, count: juggles))
            phase = .play
        }

        // MARK: Open play

        mutating func play(_ dt: Double, _ events: inout [Event], _ rng: inout some RandomNumberGenerator) {
            if let at = wanderAt, clock >= at { wanderAt = nil; wander(&events, &rng) }
            let low = ball.position.y - pitch.floorY < 30
            // Who has it at their feet.
            let holder = players.indices.filter { k in
                !players[k].isBusy && !players[k].isKeeper && players[k].lift == 0 && low && abs(ball.position.x - players[k].x) < players[k].half + ball.radius + 6
            }.min { abs(ball.position.x - players[$0].x) < abs(ball.position.x - players[$1].x) }
            let chasers = Set((0...1).compactMap { t in
                players.indices.filter { players[$0].team == t && !players[$0].isKeeper && !players[$0].isBusy }
                    .min { abs(players[$0].x - ball.position.x) < abs(players[$1].x - ball.position.x) }
            })
            for k in players.indices {
                let p = players[k]
                switch p.act {
                case .wander(let to):
                    run(k, to: to, dt, pace: 0.35)
                    if abs(players[k].x - clamp(to, k)) < 3 { players[k].facing = to > middle ? 1 : -1; players[k].pose = "idle" }
                    if players[k].actLeft <= 0 { players[k].act = .none; events.append(.comesBack(p.index)) }
                    continue
                case .slide(let d):
                    players[k].x = clamp(players[k].x + d * 220 * CGFloat(dt), k)
                    continue
                case .dive(let d):
                    players[k].x = clamp(players[k].x + d * 140 * CGFloat(dt), k)
                    continue
                case .stagger, .whiff, .header, .cheer:
                    if p.act == .whiff { players[k].rotation += 9 * dt * Double(p.facing) }
                    continue
                case .none: break
                }
                if p.isKeeper { keep(k, dt, &events, &rng); continue }
                let d = attack(p.team)
                if k == holder {
                    hold(k, dt, &events, &rng)
                } else if chasers.contains(k) {
                    run(k, to: ball.position.x - d * (p.half * 0.6), dt)
                    if let h = holder, players[h].team != p.team, p.cooldown <= 0,
                       abs(players[h].x - p.x) < players[h].half + p.half + 12,
                       Double.random(in: 0..<1, using: &rng) < 0.8 * dt {
                        tackle(k, h, &events, &rng)
                    }
                } else if let h = holder, players[h].team == p.team {
                    // Up the pitch ahead of a teammate with the ball, for a pass.
                    run(k, to: max(lo, min(hi, players[h].x + d * 140)), dt, pace: 0.9)
                } else if let g = own(p.team) {
                    // Back between the ball and its own goal.
                    run(k, to: (ball.position.x * 2 + g.x) / 3, dt, pace: 0.8)
                } else {
                    run(k, to: ball.position.x - d * 120, dt, pace: 0.7)
                }
            }
            settle(dt)
            touch(&events)
        }

        /// Player `k` has the ball: dribble on, pass, or shoot.
        mutating func hold(_ k: Int, _ dt: Double, _ events: inout [Event], _ rng: inout some RandomNumberGenerator) {
            let p = players[k], d = attack(p.team)
            guard let goal = target(of: p.team) else {
                // Nothing to shoot at (the keeper's own attackers have it): back to them.
                return run(k, to: ball.position.x, dt)
            }
            let dist = abs(goal.x - p.x)
            if players[k].shootFrom == nil { players[k].shootFrom = .random(in: 140...360, using: &rng) }
            guard p.cooldown <= 0 else { return run(k, to: ball.position.x + d * 4, dt, pace: 0.8) }
            if (goal.x - p.x) * d > 0, dist < players[k].shootFrom ?? 220 {
                players[k].shootFrom = nil
                if Double.random(in: 0..<1, using: &rng) < 0.12 {
                    // A big swing at the ball, and it is not there: round it goes.
                    players[k].act = .whiff
                    players[k].actLeft = 0.7
                    players[k].pose = "jump"
                    players[k].cooldown = 0.9
                    events.append(.whiff(by: p.index))
                    return
                }
                let aim = goal.height * CGFloat.random(in: 0.15...1.25, using: &rng)
                let speed = CGFloat.random(in: 400...600, using: &rng)
                let t = max(0.15, dist / speed)
                let rise = (aim - (ball.position.y - pitch.floorY) + Self.gravity * t * t / 2) / t
                kick(k, CGVector(dx: d * dist / t, dy: max(40, rise)))
                events.append(.shot(by: p.index))
                return
            }
            let mates = players.indices.filter { players[$0].team == p.team && $0 != k && !players[$0].isKeeper && !players[$0].isBusy }
            let pressed = players.contains { $0.team != p.team && !$0.isKeeper && ($0.x - p.x) * d > -10 && abs($0.x - p.x) < 80 }
            if pressed, let m = mates.filter({ (players[$0].x - p.x) * d > 40 }).randomElement(using: &rng),
               Double.random(in: 0..<1, using: &rng) < 2 * dt {
                let gap = players[m].x - ball.position.x
                let t = max(0.25, abs(gap) / 380)
                kick(k, CGVector(dx: gap / t, dy: Self.gravity * CGFloat(t) / 2.4))
                events.append(.pass(from: p.index, to: players[m].index))
                players[k].shootFrom = nil
                return
            }
            // Dribble: run on, tapping it ahead.
            run(k, to: p.x + d * 60, dt, pace: 0.85)
            if (ball.position.x - players[k].x) * d < p.half * 0.9 || ball.velocity.dx * d < p.speed * 0.6 {
                kick(k, CGVector(dx: d * p.speed * 1.2, dy: 50))
                players[k].cooldown = 0.18
            }
        }

        mutating func tackle(_ k: Int, _ from: Int, _ events: inout [Event], _ rng: inout some RandomNumberGenerator) {
            let d = attack(players[k].team)
            players[k].act = .slide(players[from].x > players[k].x ? 1 : -1)
            players[k].actLeft = 0.45
            players[k].pose = "land"
            players[k].rotation = Double(-d) * 0.45
            players[from].act = .stagger
            players[from].actLeft = 0.5
            players[from].pose = "land"
            players[from].shootFrom = nil
            players[from].cooldown = 0.9
            kick(k, CGVector(dx: d * .random(in: 200...300, using: &rng), dy: 90))
            events.append(.tackle(by: players[k].index, from: players[from].index))
        }

        /// A keeper: in front of its goal, a little toward the ball; a dive at a shot coming in.
        mutating func keep(_ k: Int, _ dt: Double, _ events: inout [Event], _ rng: inout some RandomNumberGenerator) {
            guard let g = own(players[k].team) else { return }
            let p = players[k]
            let out = min(80, abs(ball.position.x - g.x) * 0.15)
            run(k, to: g.x - g.side * (p.half + 4 + out), dt, pace: 0.9)
            // At its feet: a long kick up the pitch.
            if p.cooldown <= 0, ball.position.y - pitch.floorY < p.half, abs(ball.position.x - p.x) < p.half + ball.radius + 4 {
                kick(k, CGVector(dx: -g.side * .random(in: 380...520, using: &rng), dy: .random(in: 250...400, using: &rng)))
                return
            }
            let v = ball.velocity
            guard v.dx * g.side > 150 else { return }
            let t = (g.x - ball.position.x) / v.dx
            guard t > 0.05, t < 0.6, p.cooldown <= 0 else { return }
            let up = ball.position.y - pitch.floorY + v.dy * t - Self.gravity * t * t / 2
            guard up < g.height + ball.radius * 2 else { return }
            // Read it (or not quite): a dive toward where it is going.
            let reads = Double.random(in: 0..<1, using: &rng) < 0.55
            let height = reads ? max(0, up - p.half) : max(0, up - p.half) * 0.3 + 60
            players[k].act = .dive(-g.side * 0.2)
            players[k].actLeft = 0.75
            players[k].rise = sqrt(2 * Self.gravity * max(10, height))
            players[k].lift = max(players[k].lift, 0.1)
            players[k].pose = "jump"
            players[k].rotation = Double(g.side) * .pi / 2 * (up > p.half * 2 ? 0.6 : 1)
        }

        /// The ball against bodies: a header, a chest, a keeper's save.
        mutating func touch(_ events: inout [Event]) {
            for k in players.indices where players[k].cooldown <= 0 && !players[k].isWandering {
                let p = players[k]
                let centre = CGPoint(x: p.x, y: pitch.floorY + p.half + p.lift)
                let dx = ball.position.x - centre.x, dy = ball.position.y - centre.y
                guard hypot(dx, dy) < p.half + ball.radius, ball.position.y - pitch.floorY > p.half * 1.2 || p.act != .none else { continue }
                if case .dive = p.act, let g = own(p.team) {
                    ball.velocity = CGVector(dx: -g.side * max(120, abs(ball.velocity.dx) * 0.45), dy: 300)
                    lastTouch = p.index
                    players[k].cooldown = 0.6
                    events.append(.save(by: p.index))
                    continue
                }
                guard ball.position.y - pitch.floorY > p.half * 1.2 else { continue }
                let d = p.isKeeper ? -(own(p.team)?.side ?? 1) : attack(p.team)
                // Near the goal it is nodded down at it; elsewhere up and on.
                if !p.isKeeper, let g = target(of: p.team), abs(g.x - p.x) < 260, (g.x - p.x) * d > 0 {
                    kick(k, CGVector(dx: d * 300, dy: -140))
                } else {
                    kick(k, CGVector(dx: d * 330, dy: 220))
                }
                if p.lift > 0 { events.append(.header(by: p.index)) }
            }
            // A ball dropping onto a player's head: up it goes for a header.
            for k in players.indices where players[k].lift == 0 && !players[k].isBusy && !players[k].isKeeper {
                let p = players[k], over = ball.position.y - pitch.floorY
                if ball.velocity.dy < 0, over > p.half * 2.2, over < p.half * 4, abs(ball.position.x - p.x) < p.half,
                   p.cooldown <= 0 {
                    players[k].rise = 380
                    players[k].lift = 0.1
                    players[k].pose = "jump"
                    players[k].act = .header
                    players[k].actLeft = 0.5
                }
            }
        }

        // MARK: The ball

        mutating func flight(_ dt: Double, _ events: inout [Event], _ rng: inout some RandomNumberGenerator) {
            guard phase != .over || ball.opacity > 0 else { return }
            let h = CGFloat(dt)
            let before = ball.position
            ball.velocity.dy -= Self.gravity * h
            ball.position.x += ball.velocity.dx * h
            ball.position.y += ball.velocity.dy * h
            ball.turn += Double(ball.velocity.dx * h / max(1, ball.radius))
            let ground = pitch.floorY + ball.radius
            // Past the floor's end there is nothing to land on.
            let onPitch = pitch.span.contains(ball.position.x)
            if onPitch, ball.position.y < ground, before.y >= ground - 1 {
                ball.position.y = ground
                ball.velocity.dy = ball.velocity.dy < -80 ? -ball.velocity.dy * 0.5 : 0
            }
            if onPitch, ball.position.y <= ground + 0.5 { ball.velocity.dx *= CGFloat(exp(-1.1 * dt)) }
            // Gone off: it falls away, fading, while someone fetches it.
            if phase == .outOfPlay { ball.opacity = max(0, ball.opacity - dt * 2); return }
            if phase == .goal || phase == .over { return bounceOffEnds() }
            for g in goals {
                let crossed = g.side > 0 ? before.x < g.x && ball.position.x >= g.x : before.x > g.x && ball.position.x <= g.x
                guard crossed else { continue }
                let up = ball.position.y - pitch.floorY
                if up < g.height - ball.radius * 0.5 {
                    return scored(at: g, &events, &rng)
                }
                if up < g.height + ball.radius {
                    // Off the bar.
                    ball.velocity = CGVector(dx: -ball.velocity.dx * 0.5, dy: abs(ball.velocity.dy) * 0.6 + 80)
                    ball.position.x = g.x - g.side * ball.radius
                    if let t = lastTouch { events.append(.woodwork(by: t)) }
                    return
                }
            }
            // Past an end: off a wall behind the goal, or over the edge.
            if ball.position.x < lo + ball.radius || ball.position.x > hi - ball.radius {
                let right = ball.position.x > middle
                if right ? pitch.wallRight : pitch.wallLeft {
                    bounceOffEnds()
                } else if ball.position.x < lo - ball.radius * 2 || ball.position.x > hi + ball.radius * 2 {
                    out(&events, &rng)
                }
            }
            // Over a goal's net and dropping behind it, where there is a wall: back into play.
            for g in goals where (ball.position.x - g.x) * g.side > 0 && ball.position.y - pitch.floorY < g.height + ball.radius {
                ball.position.y = pitch.floorY + g.height + ball.radius
                ball.velocity.dy = abs(ball.velocity.dy) * 0.4
                ball.velocity.dx = -g.side * max(60, abs(ball.velocity.dx) * 0.6)
            }
        }

        mutating func bounceOffEnds() {
            if ball.position.x < lo + ball.radius, pitch.wallLeft || phase != .play {
                ball.position.x = lo + ball.radius
                ball.velocity.dx = abs(ball.velocity.dx) * 0.55
            }
            if ball.position.x > hi - ball.radius, pitch.wallRight || phase != .play {
                ball.position.x = hi - ball.radius
                ball.velocity.dx = -abs(ball.velocity.dx) * 0.55
            }
        }

        mutating func scored(at g: Goal, _ events: inout [Event], _ rng: inout some RandomNumberGenerator) {
            let attackers = lineup == .solo || lineup == .keeper ? 0 : 1 - (g.keptBy ?? 1)
            // The last attacker on it scores; an own goal counts for them all the same.
            let scorer = lastTouch.flatMap(player).flatMap { $0.team == attackers ? $0.index : nil }
                ?? players.filter { $0.team == attackers }.min { abs($0.x - g.x) < abs($1.x - g.x) }?.index
                ?? players[0].index
            goalsBy[scorer, default: 0] += 1
            if lineup != .solo, lineup != .keeper { teamGoals[attackers] += 1 }
            lastScorer = scorer
            ball.velocity = CGVector(dx: ball.velocity.dx * 0.25, dy: 0)
            phase = .goal
            phaseLeft = Self.goalTime
            for k in players.indices {
                players[k].act = players[k].index == scorer ? .cheer : .none
                players[k].pose = "idle"
            }
            events.append(.goal(by: scorer, score: board { "\($0)" }))
            if lineup == .keeper { rotateKeeper(&events) }
        }

        /// Three at one goal: the one in goal goes out, the next comes in.
        mutating func rotateKeeper(_ events: inout [Event]) {
            guard keeperOrder.count == 3 else { return }
            keeperOrder.append(keeperOrder.removeFirst())
            let next = keeperOrder[0]
            for k in players.indices {
                players[k].isKeeper = players[k].index == next
                players[k].team = players[k].isKeeper ? 1 : 0
            }
            events.append(.keeperNow(next))
        }

        mutating func celebrate(_ dt: Double) {
            for k in players.indices where players[k].act == .cheer && players[k].lift == 0 && players[k].rise <= 0 {
                players[k].rise = 300
                players[k].lift = 0.1
                players[k].pose = "jump"
            }
        }

        // MARK: Out, and brought back

        mutating func out(_ events: inout [Event], _ rng: inout some RandomNumberGenerator) {
            phase = .outOfPlay
            let touched = lastTouch.flatMap(player)
            events.append(.out(by: touched?.index))
            let x = ball.position.x < middle ? lo : hi
            // The other side brings it back (anyone, when everyone is on one side).
            let pool = players.indices.filter { !players[$0].isKeeper && players[$0].team != touched?.team }
            let from = pool.isEmpty ? players.indices.filter { !players[$0].isKeeper } : pool
            let k = from.min { abs(players[$0].x - x) < abs(players[$1].x - x) } ?? 0
            thrower = players[k].index
            ballHeld = false
            players[k].spot = clamp(x, k)
            phaseLeft = 6
            for j in players.indices where players[j].isBusy && !players[j].isWandering { players[j].act = .none }
        }

        mutating func throwIn(_ dt: Double, _ events: inout [Event], _ rng: inout some RandomNumberGenerator) {
            guard let id = thrower, let k = slot(id) else { phase = .play; return }
            let to = players[k].spot ?? players[k].x
            run(k, to: to, dt, pace: 1.2)
            settle(dt)
            guard ballHeld || abs(players[k].x - clamp(to, k)) < 3 || phaseLeft <= 0 else { return }
            if !ballHeld {
                // Held up over its head, facing into the pitch.
                ballHeld = true
                ball.opacity = 1
                ball.velocity = .zero
                phaseLeft = 0.8
                players[k].facing = players[k].x > middle ? -1 : 1
            }
            ball.position = CGPoint(x: players[k].x, y: pitch.floorY + players[k].half * 2 + ball.radius)
            players[k].pose = "jump"
            guard phaseLeft <= 0 else { return }
            ballHeld = false
            kick(k, CGVector(dx: players[k].facing * .random(in: 220...320, using: &rng), dy: 320))
            players[k].spot = nil
            thrower = nil
            phase = .play
            events.append(.throwIn(by: id))
        }

        // MARK: Wandering off

        mutating func wander(_ events: inout [Event], _ rng: inout some RandomNumberGenerator) {
            let pool = players.indices.filter { !players[$0].isKeeper && abs(players[$0].x - ball.position.x) > 60 }
            guard let k = pool.randomElement(using: &rng) else { return }
            // To the far end from the ball, to look at something else for a while.
            let to = ball.position.x > middle ? lo + 20 : hi - 20
            players[k].act = .wander(to)
            players[k].actLeft = .random(in: 6...9, using: &rng)
            events.append(.wandersOff(players[k].index))
        }
    }
}

extension Plays.Soccer.Goal {
    func kept(by team: Int) -> Self { var g = self; g.keptBy = team; return g }
}

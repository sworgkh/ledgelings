import CoreGraphics
import Foundation

/// Baseball on every edge they walk: home plate where the batter stands, the
/// three bases on three other edges as far apart as can be (on one screen: the
/// right wall, the ceiling, the left wall), the pitcher on the batter's own
/// floor. A pitch, a swing (a hit, a foul or a miss: closer friends pitch kinder
/// balls, a good mood helps, and some luck), and a hit ball flies in an arc to
/// some edge. Fielders hop edge to edge to catch it or fetch it and throw it
/// in; the batter runs the bases by hopping edge to edge, as far as it dares.
/// A ball hit out through the top of the screen is a home run.
///
/// One creature takes practice swings and fetches the ball itself; two pitch
/// to each other in turns; three to five bat one at a time while the rest
/// field; six or more play as two teams. A runner who has to bat again leaves a
/// ghost on its base, which runs on as it would.
///
/// Pure, like the other games: the colony reads where everyone is each frame.
extension Plays {

    /// A place on the screen's outline: the edge point, the way into the screen
    /// from it, the edge's turn and its walking direction. A creature stands on it
    /// with its centre `half` along `inward`.
    public struct Place: Equatable, Sendable {
        public var edge: CGPoint
        public var inward: CGVector
        public var rotation: Double
        public var along: CGVector

        public func centre(_ half: CGFloat) -> CGPoint {
            CGPoint(x: edge.x + inward.dx * half, y: edge.y + inward.dy * half)
        }

        /// The place at `spot` of `world`, whose loops are `inset` in from the screens.
        public init(_ spot: EdgeWorld.Spot, in world: EdgeWorld, inset: CGFloat) {
            let loop = world.loops[spot.loop], s = loop.segment(at: spot.t)
            let p = loop.point(at: spot.t), n = loop.inward(ofSegment: s)
            edge = CGPoint(x: p.x - n.dx * inset, y: p.y - n.dy * inset)
            inward = n
            rotation = loop.rotation(ofSegment: s)
            along = loop.direction(ofSegment: s)
        }

        public init(edge: CGPoint, inward: CGVector, rotation: Double, along: CGVector) {
            self.edge = edge; self.inward = inward; self.rotation = rotation; self.along = along
        }

        /// +1 when `point` lies the way the edge is walked.
        func facing(toward point: CGPoint) -> CGFloat {
            (point.x - edge.x) * along.dx + (point.y - edge.y) * along.dy >= 0 ? 1 : -1
        }
    }

    /// Home, the three bases, the pitcher's mound, and where the fielders wait.
    public struct Field: Equatable, Sendable {
        public var home: Place
        public var bases: [Place]
        public var mound: Place
        public var posts: [Place]
        /// Every edge of the world, for where a hit ball comes down.
        var edges: [Edge]
        /// The outlines, in screen points, for keeping a ball's arc on screen.
        var outlines: [[CGPoint]]
        /// The screen's top over home: above this a ball is gone.
        public var top: CGFloat

        struct Edge: Equatable, Sendable {
            var from: CGPoint, to: CGPoint, inward: CGVector, rotation: Double
        }

        public static func == (a: Field, b: Field) -> Bool {
            a.home == b.home && a.bases == b.bases && a.mound == b.mound && a.posts == b.posts && a.top == b.top
        }

        /// A field in `world` (loops `inset` in from the screens) with home at
        /// `batter`'s spot when its edge is long enough to pitch along, else on the
        /// widest floor. The bases go on the three other edges that are furthest
        /// apart from home and each other, in turn round the screen the way a real
        /// diamond goes (first to the batter's right). Nil when there are not three.
        public static func choose(in world: EdgeWorld, inset: CGFloat, batter: EdgeWorld.Spot) -> Field? {
            func length(_ l: Int, _ s: Int) -> CGFloat { world.loops[l].length(ofSegment: s) }
            var homeLoop = batter.loop, homeSeg = world.loops[batter.loop].segment(at: batter.t)
            let pitchable: CGFloat = 420
            if length(homeLoop, homeSeg) < pitchable || abs(world.loops[homeLoop].direction(ofSegment: homeSeg).dy) > 0.5 {
                guard let floor = world.floors.max(by: { ($0.span.upperBound - $0.span.lowerBound) < ($1.span.upperBound - $1.span.lowerBound) }),
                      floor.span.upperBound - floor.span.lowerBound >= pitchable else { return nil }
                homeLoop = floor.loop; homeSeg = floor.segment
            }
            let loop = world.loops[homeLoop]
            let start = loop.t(onSegment: homeSeg, fraction: 0), seg = length(homeLoop, homeSeg)
            // Home where the batter is, kept to the outer part of its edge: the pitcher needs room.
            let at = homeLoop == batter.loop && loop.segment(at: batter.t) == homeSeg ? loop.wrap(batter.t - start) : seg * 0.25
            let homeShare = min(max(at / seg, 0.12), 0.88)
            let homeT = start + seg * homeShare
            let moundT = start + seg * (homeShare < 0.5 ? min(0.85, homeShare + 0.45) : max(0.15, homeShare - 0.45))
            let home = Place(EdgeWorld.Spot(loop: homeLoop, t: loop.wrap(homeT)), in: world, inset: inset)
            let mound = Place(EdgeWorld.Spot(loop: homeLoop, t: loop.wrap(moundT)), in: world, inset: inset)

            // Candidate bases: the middle of every other edge long enough to stand on.
            var candidates: [Place] = []
            for (l, s, len) in world.segments where len >= 80 && !(l == homeLoop && s == homeSeg) {
                candidates.append(Place(EdgeWorld.Spot(loop: l, t: world.loops[l].t(onSegment: s, fraction: 0.5)), in: world, inset: inset))
            }
            guard candidates.count >= 3 else { return nil }
            func d(_ a: Place, _ b: Place) -> CGFloat { hypot(a.edge.x - b.edge.x, a.edge.y - b.edge.y) }
            var best: (score: CGFloat, picks: [Place])?
            let n = candidates.count
            for i in 0..<n { for j in (i + 1)..<n where j < n { for k in (j + 1)..<n where k < n {
                let picks = [candidates[i], candidates[j], candidates[k]], all = [home] + picks
                var score = CGFloat.infinity
                for a in all.indices { for b in all.indices where b > a { score = min(score, d(all[a], all[b])) } }
                if best == nil || score > best!.score + 0.5 { best = (score, picks) }
            } } }
            // Round the field counter-clockwise from home, as a diamond is run.
            let all = [home] + best!.picks
            let centre = CGPoint(x: all.map(\.edge.x).reduce(0, +) / 4, y: all.map(\.edge.y).reduce(0, +) / 4)
            func angle(_ p: Place) -> Double {
                let a = atan2(Double(p.edge.y - centre.y), Double(p.edge.x - centre.x)) - atan2(Double(home.edge.y - centre.y), Double(home.edge.x - centre.x))
                return a < 0 ? a + 2 * .pi : a
            }
            let bases = best!.picks.sorted { angle($0) < angle($1) }

            // Where the fielders wait: a little way along from each base, second base's first.
            var posts: [Place] = []
            for (n, b) in [bases[1], bases[0], bases[2], bases[1], bases[0], bases[2], bases[1], bases[0], bases[2]].enumerated() {
                let shift: CGFloat = n < 3 ? 70 : n < 6 ? -70 : 140
                var p = b
                p.edge = CGPoint(x: b.edge.x + b.along.dx * shift, y: b.edge.y + b.along.dy * shift)
                posts.append(p)
            }
            var edges: [Edge] = []
            var outlines: [[CGPoint]] = []
            for l in world.loops.indices {
                let lp = world.loops[l]
                var outline: [CGPoint] = []
                for s in 0..<lp.segmentCount {
                    let n = lp.inward(ofSegment: s)
                    let a = lp.vertices[s], b = lp.vertices[(s + 1) % lp.segmentCount]
                    let ea = CGPoint(x: a.x - n.dx * inset, y: a.y - n.dy * inset), eb = CGPoint(x: b.x - n.dx * inset, y: b.y - n.dy * inset)
                    edges.append(Edge(from: ea, to: eb, inward: n, rotation: lp.rotation(ofSegment: s)))
                    outline.append(ea)
                }
                outlines.append(outline)
            }
            let top = (world.ceiling(over: home.centre(inset))?.y).map { $0 + inset } ?? (home.edge.y + 600)
            return Field(home: home, bases: bases, mound: mound, posts: posts, edges: edges, outlines: outlines, top: top)
        }

        /// Inside one of the screens (well, the outlines): a ball there is still in the air.
        func isInside(_ p: CGPoint) -> Bool {
            outlines.contains { poly in
                var inside = false
                var j = poly.count - 1
                for i in poly.indices {
                    let a = poly[i], b = poly[j]
                    if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
                    j = i
                }
                return inside
            }
        }

        /// A random point on some edge at least `away` from `from`, with its place.
        func landing(awayFrom from: CGPoint, away: CGFloat, using rng: inout some RandomNumberGenerator) -> Place? {
            let total = edges.reduce(0) { $0 + hypot($1.to.x - $1.from.x, $1.to.y - $1.from.y) }
            guard total > 0 else { return nil }
            for _ in 0..<40 {
                var pick = CGFloat.random(in: 0..<total, using: &rng)
                for e in edges {
                    let len = hypot(e.to.x - e.from.x, e.to.y - e.from.y)
                    if pick > len { pick -= len; continue }
                    let k = min(max(pick / max(len, 1), 0.08), 0.92)
                    let p = CGPoint(x: e.from.x + (e.to.x - e.from.x) * k, y: e.from.y + (e.to.y - e.from.y) * k)
                    guard hypot(p.x - from.x, p.y - from.y) >= away else { break }
                    let along = CGVector(dx: (e.to.x - e.from.x) / max(len, 1), dy: (e.to.y - e.from.y) / max(len, 1))
                    return Place(edge: p, inward: e.inward, rotation: e.rotation, along: along)
                }
            }
            return nil
        }
    }

    public struct Baseball: Equatable, Sendable {
        public enum Phase: Equatable, Sendable { case gettingReady, pitching, inPlay, over }

        public enum Swing: String, Equatable, Sendable { case hit, foul, miss }

        public enum Event: Equatable, Sendable {
            case pitch(by: Int)
            /// The batter tosses it up for itself: practice.
            case toss(by: Int)
            case swing(by: Int, Swing)
            case strike(by: Int, count: Int)
            /// Out: "struck out", "caught", or "at first"… (`how`).
            case out(by: Int, how: String)
            case caught(by: Int)
            /// Dropped it: a funny miss.
            case fumble(by: Int)
            case runs(by: Int, to: Int)
            case safe(by: Int, at: Int)
            case scored(by: Int, score: String)
            case homeRun(by: Int, runs: Int)
            case fetch(by: Int)
            /// The other side bats now: `inning` counted from 1.
            case sidesChange(inning: Int, batting: [Int])
            case ghost(Int, base: Int)
            case over
        }

        /// One player: where it stands, and the hops it is making.
        public struct Actor: Equatable, Sendable {
            public let index: Int
            public let half: CGFloat
            public internal(set) var place: Place
            public internal(set) var facing: CGFloat = 1
            var from: Place?
            var hop = 0.0
            var hopTime = 0.0
            var hops: [Place] = []
            var landed = 1.0
            var squat = 0.0
            var cheer = 0.0
            public var isHopping: Bool { from != nil }
        }

        public enum BallState: Equatable, Sendable {
            case gone
            case held(by: Int)
            case flying(from: CGPoint, velocity: CGVector, gravity: CGFloat, clock: Double, time: Double)
            case resting(at: CGPoint)
        }

        public struct Runner: Equatable, Sendable {
            public var owner: Int
            public var ghost: Bool
        }

        enum Step: Equatable, Sendable {
            case hop(Int, [Place])
            case fly(from: CGPoint, to: CGPoint, time: Double, gravity: CGFloat)
            case flyOut(from: CGPoint, velocity: CGVector)
            case hold(Int)
            case rest(CGPoint)
            case event(Event)
            case out(Int, String)
            case score(Int)
            case occupy(base: Int, Runner?)
            case resolve
            case batterUp
            case swingBat
            case cheer(Int, Double)
        }

        public static let gravity: CGFloat = 700
        public static let hopSpeed: CGFloat = 1300
        public static let throwSpeed: CGFloat = 900

        public let lineup: Lineup
        public let field: Field
        public let innings: Int
        /// Who bats in turn: one list per side.
        public let sides: [[Int]]
        public internal(set) var actors: [Actor]
        public internal(set) var ball: BallState = .gone
        public internal(set) var bases: [Runner?] = [nil, nil, nil]
        public internal(set) var phase: Phase = .gettingReady
        public internal(set) var inning = 1
        public internal(set) var batting = 0
        public internal(set) var batter: Int
        public internal(set) var pitcher: Int?
        public internal(set) var strikes = 0
        public internal(set) var outs = 0
        /// Runs in this side's turn at bat: a small game's turn ends at `mercy` of them.
        public internal(set) var turnRuns = 0
        public internal(set) var runsBy: [Int: Int] = [:]
        public internal(set) var sideRuns: [Int] = []
        public internal(set) var swings = 0
        public internal(set) var hits = 0
        public internal(set) var homeRuns = 0
        /// The bat's swing, 0 at rest over the shoulder to 1 right through.
        public internal(set) var batSwing = 0.0
        /// A home run has just gone out: where, for the fireworks.
        public internal(set) var lastHomeRun: CGPoint?
        let mood: Double
        let close: [Int: [Int: Double]]
        let practiceSwings: Int
        var clock = 0.0
        var overUntil = 0.0
        var schedule: [(at: Double, step: Step)] = []
        var next: [Int] = []
        var finished = false

        public static func == (a: Baseball, b: Baseball) -> Bool {
            a.actors == b.actors && a.ball == b.ball && a.bases == b.bases && a.phase == b.phase && a.inning == b.inning
                && a.batting == b.batting && a.outs == b.outs && a.strikes == b.strikes && a.runsBy == b.runsBy && a.clock == b.clock
        }

        /// A game on `field` for `players` (creature indices; the first started it)
        /// standing at `starts`, each `halves` in half size; `teams` the two sides
        /// from six. `innings` long; `mood` −1…1 (a playful cursor helps).
        public init(players ids: [Int], teams: [[Int]]? = nil, starts: [Int: Place], halves: [Int: CGFloat], field: Field,
                    innings: Int, mood: Double = 0, closeness: (Int, Int) -> Double = { _, _ in 0 }) {
            lineup = Lineup.baseball(ids.count)
            self.field = field
            self.innings = max(1, innings)
            self.mood = min(max(mood, -1), 1)
            var close: [Int: [Int: Double]] = [:]
            for a in ids { for b in ids where b != a { close[a, default: [:]][b] = closeness(a, b) } }
            self.close = close
            switch lineup {
            case .solo, .duel, .rotation, .keeper: sides = ids.map { [$0] }
            case .teams: sides = teams ?? Plays.split(ids, closeness: closeness)
            }
            sideRuns = sides.map { _ in 0 }
            practiceSwings = self.innings * 4
            actors = ids.map { Actor(index: $0, half: halves[$0] ?? 20, place: starts[$0] ?? field.home) }
            batter = sides[0][0]
            next = sides.map { _ in 0 }
            next[0] = 1
            takePositions(first: true)
        }

        public var isFinished: Bool { finished }

        public func actor(_ index: Int) -> Actor? { actors.first { $0.index == index } }

        /// Runs that end a turn at bat early: three in a small game, five for teams.
        public var mercy: Int { lineup == .teams ? 5 : 3 }

        /// Who is fielding: everyone not on the batting side.
        public var fielders: [Int] { lineup == .solo ? [] : actors.map(\.index).filter { !sides[batting].contains($0) } }

        /// Creature `index`'s centre, turn, pose and facing, as the colony draws it.
        public func pose(of index: Int) -> (position: CGPoint, rotation: Double, pose: String, facing: CGFloat)? {
            guard let a = actor(index) else { return nil }
            if let from = a.from {
                let s = min(1, a.hop / max(a.hopTime, 0.01))
                let p0 = from.centre(a.half), p1 = a.place.centre(a.half)
                let dist = hypot(p1.x - p0.x, p1.y - p0.y)
                var bulge = CGVector(dx: from.inward.dx + a.place.inward.dx, dy: from.inward.dy + a.place.inward.dy)
                let bl = hypot(bulge.dx, bulge.dy)
                if bl < 0.3 { bulge = CGVector(dx: -(p1.y - p0.y) / max(dist, 1), dy: (p1.x - p0.x) / max(dist, 1)) } else { bulge.dx /= bl; bulge.dy /= bl }
                let rise = min(240, dist * 0.3) * CGFloat(4 * s * (1 - s))
                var turn = a.place.rotation - from.rotation
                while turn > .pi { turn -= 2 * .pi }
                while turn < -.pi { turn += 2 * .pi }
                return (CGPoint(x: p0.x + (p1.x - p0.x) * CGFloat(s) + bulge.dx * rise, y: p0.y + (p1.y - p0.y) * CGFloat(s) + bulge.dy * rise),
                        from.rotation + turn * s, "jump", a.facing)
            }
            let c = a.place.centre(a.half)
            let lift = a.cheer > 0 ? CGFloat(abs(sin(a.cheer * 9))) * a.half * 0.6 : 0
            let pose = a.cheer > 0 ? (lift > 2 ? "jump" : "land") : a.landed < 0.15 || a.squat > 0 ? "land" : "idle"
            return (CGPoint(x: c.x + a.place.inward.dx * lift, y: c.y + a.place.inward.dy * lift), a.place.rotation, pose, a.facing)
        }

        /// Where the ball is, or nil while nobody can see it.
        public var ballPosition: CGPoint? {
            switch ball {
            case .gone: return nil
            case .resting(let p): return p
            case .held(let i):
                guard let a = actor(i), let pose = pose(of: i) else { return nil }
                return CGPoint(x: pose.position.x + a.place.inward.dx * a.half * 0.5 + a.place.along.dx * a.facing * a.half * 0.7,
                               y: pose.position.y + a.place.inward.dy * a.half * 0.5 + a.place.along.dy * a.facing * a.half * 0.7)
            case .flying(let from, let v, let g, let t, _):
                return CGPoint(x: from.x + v.dx * CGFloat(t), y: from.y + v.dy * CGFloat(t) - g * CGFloat(t * t) / 2)
            }
        }

        /// The board: runs by side (or by player), the inning and the outs.
        public func board(_ name: (Int) -> String) -> String {
            if lineup == .solo {
                return "\(name(batter)): \(trCount(hits, "hit", "hits")), \(trCount(homeRuns, "home run", "home runs"))"
            }
            let scores: String
            if lineup == .teams {
                scores = "\(tr("%@'s team", name(sides[0][0]))) \(sideRuns[0]) : \(sideRuns[1]) \(tr("%@'s team", name(sides[1][0])))"
            } else {
                scores = sides.indices.map { "\(name(sides[$0][0])) \(sideRuns[$0])" }.joined(separator: "  ")
            }
            return scores + "  · " + tr("inning %d/%d, %d out", min(inning, innings), innings, outs)
        }

        func slot(_ index: Int) -> Int? { actors.firstIndex { $0.index == index } }

        // MARK: Positions

        /// Everyone to their places for the next batter: the batter to home, the
        /// pitcher to the mound, the fielders to their posts, the rest of the
        /// batting side by home, out of the way.
        mutating func takePositions(first: Bool = false) {
            phase = .gettingReady
            let side = sides[batting]
            pitcher = lineup == .solo ? nil : fielders.first
            for (n, f) in fielders.dropFirst().enumerated() { go(f, to: field.posts[n % field.posts.count]) }
            if let p = pitcher { go(p, to: field.mound) }
            go(batter, to: field.home)
            var bench = 0
            for m in side where m != batter && !bases.contains(where: { $0?.owner == m && $0?.ghost == false }) {
                bench += 1
                var p = field.home
                let shift = CGFloat(bench) * 46 * -facingMound
                p.edge = CGPoint(x: p.edge.x + p.along.dx * shift, y: p.edge.y + p.along.dy * shift)
                go(m, to: p)
            }
            batSwing = 0
            schedule = []
            let catcher = pitcher ?? batter
            if first || ballPosition == nil {
                ball = .held(by: catcher)
            } else if case .held(let by) = ball, by == catcher {
            } else if let at = ballPosition, let c = actor(catcher) {
                // Thrown back to the pitcher (or picked up by the batter, alone).
                let spot = pitcher == nil ? field.home : field.mound
                later(0.1, .fly(from: at, to: spot.centre(c.half * 1.5), time: 0.8, gravity: Self.gravity))
                later(0.9, .hold(catcher))
            }
            later(first ? 0.4 : 1.0, .batterUp)
        }

        /// From home, which way the mound is along home's edge.
        var facingMound: CGFloat { field.home.facing(toward: field.mound.edge) }

        mutating func go(_ index: Int, to place: Place) {
            guard let k = slot(index) else { return }
            if actors[k].place == place, actors[k].from == nil { return }
            actors[k].hops = [place]
            if actors[k].from == nil { startHop(k) }
        }

        mutating func startHop(_ k: Int) {
            guard !actors[k].hops.isEmpty else { return }
            let to = actors[k].hops.removeFirst()
            let a = actors[k]
            let d = hypot(to.edge.x - a.place.edge.x, to.edge.y - a.place.edge.y)
            if d < 4, a.place.rotation == to.rotation { actors[k].place = to; return }
            actors[k].from = a.place
            actors[k].facing = a.place.facing(toward: to.edge)
            actors[k].place = to
            actors[k].hop = 0
            actors[k].hopTime = Self.hopTime(d)
        }

        /// Seconds for a hop of `distance` points.
        public static func hopTime(_ distance: CGFloat) -> Double {
            min(max(0.35 + Double(distance / hopSpeed), 0.45), 1.3)
        }

        public static func throwTime(_ distance: CGFloat) -> Double {
            min(max(Double(distance / throwSpeed), 0.3), 1.2)
        }

        /// Seconds for `index` to make every hop in `places` from where it is.
        func hopping(_ index: Int, through places: [Place]) -> Double {
            guard let a = actor(index) else { return 0 }
            var at = a.place.edge, total = 0.0
            for p in places {
                total += Self.hopTime(hypot(p.edge.x - at.x, p.edge.y - at.y)) + 0.05
                at = p.edge
            }
            return total
        }

        /// The throw from `from` that lands at `to` in `time`.
        static func velocity(from: CGPoint, to: CGPoint, time: Double, gravity: CGFloat) -> CGVector {
            let t = CGFloat(max(0.05, time))
            return CGVector(dx: (to.x - from.x) / t, dy: (to.y - from.y) / t + gravity * t / 2)
        }

        // MARK: Running

        public mutating func update(dt: Double, using rng: inout some RandomNumberGenerator) -> [Event] {
            var events: [Event] = []
            guard !finished else { return events }
            clock += dt
            for k in actors.indices {
                actors[k].landed += dt
                actors[k].squat = max(0, actors[k].squat - dt)
                if actors[k].cheer > 0 { actors[k].cheer = max(0, actors[k].cheer - dt) }
                guard actors[k].from != nil else { continue }
                actors[k].hop += dt
                if actors[k].hop >= actors[k].hopTime {
                    actors[k].from = nil
                    actors[k].landed = 0
                    startHop(k)
                }
            }
            if case .flying(let from, let v, let g, let t, let time) = ball {
                ball = .flying(from: from, velocity: v, gravity: g, clock: min(t + dt, time), time: time)
            }
            batSwing = batSwing > 0 && batSwing < 1 ? min(1, batSwing + dt / 0.22) : batSwing
            if phase == .over {
                finished = clock >= overUntil
                return events
            }
            // Facing: the batter the mound, everyone else the ball.
            if let b = slot(batter), actors[b].from == nil, phase != .inPlay { actors[b].facing = facingMound }
            if let ballAt = ballPosition {
                for k in actors.indices where actors[k].from == nil && (actors[k].index != batter || phase == .inPlay) {
                    actors[k].facing = actors[k].place.facing(toward: ballAt)
                }
            }
            while let first = schedule.first, first.at <= clock {
                schedule.removeFirst()
                perform(first.step, &events, &rng)
                if finished { break }
            }
            return events
        }

        mutating func later(_ seconds: Double, _ step: Step) {
            schedule.append((clock + seconds, step))
            schedule.sort { $0.at < $1.at }
        }

        mutating func perform(_ step: Step, _ events: inout [Event], _ rng: inout some RandomNumberGenerator) {
            switch step {
            case .hop(let i, let places):
                guard let k = slot(i) else { return }
                actors[k].hops = places
                if actors[k].from == nil { startHop(k) }
            case .fly(let from, let to, let time, let g):
                ball = .flying(from: from, velocity: Self.velocity(from: from, to: to, time: time, gravity: g), gravity: g, clock: 0, time: time)
            case .flyOut(let from, let v):
                ball = .flying(from: from, velocity: v, gravity: Self.gravity, clock: 0, time: 3)
            case .hold(let i): ball = .held(by: i)
            case .rest(let p): ball = .resting(at: p)
            case .event(let e):
                events.append(e)
            case .out(let i, let how):
                outs += 1
                atBatOver = true
                events.append(.out(by: i, how: how))
            case .score(let i):
                runsBy[i, default: 0] += 1
                turnRuns += 1
                if let s = sides.firstIndex(where: { $0.contains(i) }) { sideRuns[s] += 1 }
                events.append(.scored(by: i, score: "\(sideRuns.map(String.init).joined(separator: "-"))"))
            case .occupy(let base, let runner):
                bases[base] = runner
            case .resolve:
                resolve(&events, &rng)
            case .batterUp:
                batterUp(&events, &rng)
            case .swingBat:
                batSwing = 0.01
            case .cheer(let i, let seconds):
                if let k = slot(i) { actors[k].cheer = seconds }
            }
        }

        /// Everyone is in place: the pitch (or, alone, the toss).
        mutating func batterUp(_ events: inout [Event], _ rng: inout some RandomNumberGenerator) {
            // Still hopping into place: wait for them.
            if actors.contains(where: { $0.from != nil }) { return later(0.2, .batterUp) }
            phase = .pitching
            guard let b = actor(batter) else { return }
            let hands = b.place.centre(b.half * 1.6)
            let swing = outcome(using: &rng)
            swings += 1
            let flight: Double
            if let p = pitcher, let pa = actor(p) {
                if let k = slot(p) { actors[k].squat = 0.6 }
                let from = pa.place.centre(pa.half * 1.5)
                flight = 0.6
                later(0.6, .event(.pitch(by: p)))
                later(0.6, .fly(from: from, to: hands, time: flight, gravity: 150))
            } else {
                // Practice: up it goes, and down to the bat.
                flight = 0.9
                later(0.3, .event(.toss(by: batter)))
                later(0.3, .fly(from: hands, to: hands, time: flight, gravity: 1400))
            }
            let contact = (pitcher == nil ? 0.3 : 0.6) + flight
            pending = swing
            later(contact - 0.12, .swingBat)
            later(contact, .event(.swing(by: batter, swing)))
            later(contact, .resolve)
            phase = .pitching
        }

        var pending: Swing = .miss
        /// The batter's turn is over: a hit, or out.
        var atBatOver = false

        /// Hit, foul or miss: kinder pitches between friends, a good mood, and luck.
        mutating func outcome(using rng: inout some RandomNumberGenerator) -> Swing {
            let friends = pitcher.flatMap { close[batter]?[$0] } ?? 0
            let hit = (pitcher == nil ? 0.6 : 0.34) + 0.22 * friends + 0.06 * mood + .random(in: -0.08...0.08, using: &rng)
            let roll = Double.random(in: 0..<1, using: &rng)
            if roll < hit { return .hit }
            return roll < hit + (pitcher == nil ? 0 : 0.2) ? .foul : .miss
        }

        /// The ball reaches the bat: what happens next.
        mutating func resolve(_ events: inout [Event], _ rng: inout some RandomNumberGenerator) {
            guard phase == .pitching else { return afterPlay(&events, &rng) }
            guard let b = actor(batter) else { return }
            let from = b.place.centre(b.half * 1.6)
            switch pending {
            case .miss, .foul:
                let back = -facingMound
                if pending == .miss {
                    // Past the bat and away behind home, where it rolls to a stop.
                    var behind = field.home
                    behind.edge = CGPoint(x: behind.edge.x + behind.along.dx * back * 120, y: behind.edge.y + behind.along.dy * back * 120)
                    ball = .flying(from: from, velocity: Self.velocity(from: from, to: behind.centre(4), time: 0.4, gravity: 300), gravity: 300, clock: 0, time: 0.4)
                } else {
                    var behind = field.home
                    behind.edge = CGPoint(x: behind.edge.x + behind.along.dx * back * 260, y: behind.edge.y + behind.along.dy * back * 260)
                    let to = field.isInside(behind.centre(4)) ? behind.centre(4) : field.home.centre(140)
                    ball = .flying(from: from, velocity: Self.velocity(from: from, to: to, time: 1.0, gravity: Self.gravity), gravity: Self.gravity, clock: 0, time: 1.0)
                }
                if pending == .miss || strikes < 2 {
                    strikes += 1
                    events.append(.strike(by: batter, count: strikes))
                }
                if strikes >= 3, lineup != .solo { later(0.5, .out(batter, "struck out")) }
                phase = .inPlay
                later(1.0, .resolve)
            case .hit:
                hits += 1
                atBatOver = true
                phase = .inPlay
                hit(from: from, &events, &rng)
            }
        }

        /// A hit ball: a home run out over the top, or an arc to some edge, fielded.
        mutating func hit(from: CGPoint, _ events: inout [Event], _ rng: inout some RandomNumberGenerator) {
            let friends = pitcher.flatMap { close[batter]?[$0] } ?? 0
            let power = 0.13 + 0.08 * friends + 0.04 * mood
            if Double.random(in: 0..<1, using: &rng) < power {
                return homeRun(from: from, &events, &rng)
            }
            guard let landing = field.landing(awayFrom: field.home.edge, away: 260, using: &rng) else { return homeRun(from: from, &events, &rng) }
            let to = landing.centre(Plays.Props.ballRadius)
            let dist = hypot(to.x - from.x, to.y - from.y)
            // The highest arc that stays on screen, or a line drive.
            var time = 0.0, g = Self.gravity
            for t in [1.7, 1.45, 1.2, 1.0, 0.8] {
                let tt = min(t, max(0.7, Double(dist / 500)))
                let v = Self.velocity(from: from, to: to, time: tt, gravity: g)
                let onScreen = (1...11).allSatisfy { k in
                    let s = CGFloat(tt) * CGFloat(k) / 12
                    return field.isInside(CGPoint(x: from.x + v.dx * s, y: from.y + v.dy * s - g * s * s / 2))
                }
                if onScreen { time = tt; break }
            }
            if time == 0 { time = max(0.5, Double(dist / 900)); g = 0 }
            ball = .flying(from: from, velocity: Self.velocity(from: from, to: to, time: time, gravity: g), gravity: g, clock: 0, time: time)

            if lineup == .solo { return fetchAlone(landing, after: time) }

            // The fielder who gets there first goes for it.
            let pool = fielders
            guard let catcher = pool.min(by: { hopping($0, through: [landing]) < hopping($1, through: [landing]) }) else { return }
            let arrive = 0.25 + hopping(catcher, through: [landing])
            later(0.25, .hop(catcher, [landing]))
            let caught = arrive <= time + 0.05 && Double.random(in: 0..<1, using: &rng) < 0.72
            if caught {
                later(time, .hold(catcher))
                later(time, .event(.caught(by: catcher)))
                later(time + 0.3, .out(batter, "caught"))
                later(time + 1.0, .resolve)
                // The batter sets off anyway, and turns back.
                later(0.15, .hop(batter, [field.bases[0]]))
                later(time + 0.6, .hop(batter, [field.home]))
                return
            }
            var pickup = max(arrive, time) + 0.3
            if arrive <= time + 0.05 {
                // There in time, and it bounces off its head.
                later(time, .event(.fumble(by: catcher)))
                pickup += 0.8
            }
            later(time, .rest(to))
            later(pickup, .hold(catcher))
            later(pickup - 0.3, .event(.fetch(by: catcher)))
            run(fielder: catcher, at: landing, pickup: pickup, &events, &rng)
        }

        /// The batter runs as far as it dares before the throw comes in; the others go as far.
        mutating func run(fielder: Int, at landing: Place, pickup: Double, _ events: inout [Event], _ rng: inout some RandomNumberGenerator) {
            let catcherAt = landing.centre(actor(fielder)?.half ?? 20)
            let courage = Double.random(in: -0.3...0.5, using: &rng)
            let route = field.bases + [field.home]
            var reach = 1
            while reach < 4 {
                let mine = 0.15 + hopping(batter, through: Array(route.prefix(reach + 1)))
                let target = route[reach]
                let theirs = pickup + Self.throwTime(hypot(target.edge.x - catcherAt.x, target.edge.y - catcherAt.y))
                if mine + courage < theirs { reach += 1 } else { break }
            }
            let target = route[reach - 1]
            let arrive = 0.15 + hopping(batter, through: Array(route.prefix(reach)))
            let throwArrives = pickup + Self.throwTime(hypot(target.edge.x - catcherAt.x, target.edge.y - catcherAt.y))
            let safe = arrive < throwArrives
            later(0.15, .hop(batter, Array(route.prefix(reach))))
            for b in 0..<reach { later(0.15 + hopping(batter, through: Array(route.prefix(b))), .event(.runs(by: batter, to: b + 1))) }
            // The throw, to whoever waits at that base (or straight there).
            let receiver = fielders.filter { $0 != fielder }.min { a, b in
                let pa = actor(a)!.place.edge, pb = actor(b)!.place.edge
                return hypot(pa.x - target.edge.x, pa.y - target.edge.y) < hypot(pb.x - target.edge.x, pb.y - target.edge.y)
            }
            if let r = receiver { later(max(0.2, throwArrives - 1.2), .hop(r, [Self.beside(target)])) }
            later(pickup, .fly(from: catcherAt, to: target.centre(30), time: throwArrives - pickup, gravity: Self.gravity))
            later(throwArrives, receiver.map { .hold($0) } ?? .rest(target.centre(8)))
            // The runners already on base go as far as the batter gets safely.
            let advance = safe ? reach : reach - 1
            advanceRunners(by: advance, start: 0.15)
            if reach == 4, safe {
                later(arrive, .score(batter))
                later(arrive, .cheer(batter, 1.5))
            } else if safe {
                later(arrive, .event(.safe(by: batter, at: reach)))
                later(arrive, .occupy(base: reach - 1, Runner(owner: batter, ghost: false)))
            } else {
                later(throwArrives, .out(batter, reach == 4 ? "at home" : ["at first", "at second", "at third"][reach - 1]))
                later(throwArrives + 0.4, .hop(batter, [field.home]))
            }
            later(max(arrive, throwArrives) + 0.8, .resolve)
        }

        /// Next to a base, where a fielder takes the throw.
        static func beside(_ base: Place) -> Place {
            var p = base
            p.edge = CGPoint(x: base.edge.x + base.along.dx * 34, y: base.edge.y + base.along.dy * 34)
            return p
        }

        /// The runners on base move up `by` bases; past third they score.
        mutating func advanceRunners(by count: Int, start: Double) {
            guard count > 0 else { return }
            let route = field.bases + [field.home]
            var moved: [Runner?] = [nil, nil, nil]
            for b in (0..<3).reversed() {
                guard let runner = bases[b] else { continue }
                let to = b + count
                let path = Array(route[(b + 1)...min(3, to)])
                let arrive = runner.ghost ? 0.6 : hopping(runner.owner, through: path)
                if !runner.ghost { later(start, .hop(runner.owner, path)) }
                if to >= 3 {
                    later(start + arrive, .score(runner.owner))
                    if !runner.ghost { later(start + arrive + 0.3, .hop(runner.owner, [benchSpot(runner.owner)])) }
                } else {
                    moved[to] = runner
                }
                bases[b] = nil
            }
            for b in 0..<3 where moved[b] != nil { later(start + 0.6, .occupy(base: b, moved[b])) }
        }

        /// A place by home for a batter waiting its turn.
        func benchSpot(_ index: Int) -> Place {
            let n = CGFloat((sides[batting].firstIndex(of: index) ?? 0) + 1)
            var p = field.home
            let shift = n * 46 * -facingMound
            p.edge = CGPoint(x: p.edge.x + p.along.dx * shift, y: p.edge.y + p.along.dy * shift)
            return p
        }

        mutating func homeRun(from: CGPoint, _ events: inout [Event], _ rng: inout some RandomNumberGenerator) {
            homeRuns += 1
            // Up and out through the top of the screen, somewhere over the field.
            let out = CGPoint(x: from.x + facingMound * .random(in: 100...500, using: &rng), y: field.top + 200)
            let time = 1.3
            ball = .flying(from: from, velocity: Self.velocity(from: from, to: out, time: time, gravity: Self.gravity),
                           gravity: Self.gravity, clock: 0, time: time)
            let exit = CGPoint(x: from.x + (out.x - from.x) * 0.85, y: field.top - 10)
            lastHomeRun = exit
            let runs = 1 + bases.compactMap { $0 }.count
            events.append(.homeRun(by: batter, runs: runs))
            if lineup == .solo {
                later(0.3, .cheer(batter, 2))
                later(2.6, .resolve)
                return
            }
            // A lap of honour round every base, the runners ahead of it.
            advanceRunners(by: 4, start: 0.3)
            let route = field.bases + [field.home]
            later(0.4, .hop(batter, route))
            let lap = 0.4 + hopping(batter, through: route)
            later(lap, .score(batter))
            later(lap + 0.1, .event(.safe(by: batter, at: 4)))
            later(lap + 0.1, .cheer(batter, 1.5))
            later(lap + 1.8, .resolve)
        }

        /// Alone: off it goes to fetch the ball, and back to home with it.
        mutating func fetchAlone(_ landing: Place, after time: Double) {
            later(time, .rest(landing.centre(Plays.Props.ballRadius)))
            let there = time + 0.2 + hopping(batter, through: [landing])
            later(time + 0.2, .hop(batter, [landing]))
            later(time + 0.2, .event(.fetch(by: batter)))
            later(there, .hold(batter))
            later(there + 0.1, .hop(batter, [field.home]))
            later(there + 0.2 + Self.hopTime(hypot(landing.edge.x - field.home.edge.x, landing.edge.y - field.home.edge.y)) + 0.5, .resolve)
        }

        /// The play is over: count the outs, change sides, or the next batter.
        mutating func afterPlay(_ events: inout [Event], _ rng: inout some RandomNumberGenerator) {
            if lineup == .solo {
                if swings >= practiceSwings { return end(&events) }
                takePositions()
                return
            }
            let limit = lineup == .teams ? 3 : 2
            if outs >= limit || turnRuns >= mercy {
                outs = 0
                turnRuns = 0
                bases = [nil, nil, nil]
                batting += 1
                if batting >= sides.count {
                    batting = 0
                    inning += 1
                    if inning > innings { return end(&events) }
                }
                events.append(.sidesChange(inning: inning, batting: sides[batting]))
                atBatOver = true
            }
            if atBatOver {
                atBatOver = false
                strikes = 0
                batter = nextBatter(&events)
            }
            takePositions()
        }

        /// Next in the batting order; a runner who is the only one left leaves a ghost on its base.
        mutating func nextBatter(_ events: inout [Event]) -> Int {
            let side = sides[batting]
            for step in 0..<side.count {
                let m = side[(next[batting] + step) % side.count]
                if !bases.contains(where: { $0?.owner == m && $0?.ghost == false }) {
                    next[batting] = (next[batting] + step + 1) % side.count
                    return m
                }
            }
            // Everyone is on base: the one furthest round runs home to bat, leaving a ghost.
            let b = (0..<3).reversed().first { bases[$0]?.owner != nil && bases[$0]?.ghost == false } ?? 0
            let m = bases[b]?.owner ?? side[0]
            bases[b] = Runner(owner: m, ghost: true)
            events.append(.ghost(m, base: b + 1))
            return m
        }

        mutating func end(_ events: inout [Event]) {
            phase = .over
            events.append(.over)
            ball = .gone
            let best = sideRuns.max() ?? 0
            let winners = sideRuns.filter { $0 == best }.count == 1 ? sides[sideRuns.firstIndex(of: best)!] : []
            for k in actors.indices where winners.contains(actors[k].index) || lineup == .solo { actors[k].cheer = 2.4 }
            schedule = []
            overUntil = clock + 2.6
        }

        /// Who won: the side with the most runs, or nobody when it is level (or alone).
        public var winners: [Int] {
            guard lineup != .solo, let best = sideRuns.max(), sideRuns.filter({ $0 == best }).count == 1 else { return [] }
            return sides[sideRuns.firstIndex(of: best)!]
        }
    }
}

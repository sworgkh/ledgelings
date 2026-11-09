import CoreGraphics
import Foundation

/// Surfing: the tide comes in along the bottom edge of the screen, a band of
/// see-through water a little deeper than a creature is tall, and waves roll
/// along it from one end of the floor to the other. Everyone who plays
/// paddles out on its own board to a spot near the end the waves come from
/// and waits, bobbing. As a wave's face reaches it, it catches the wave
/// (`catchChance`) or lets it roll by underneath; a rider stands up and rides
/// the face, carving, and now and then tries a trick, a hop or a spin. A ride
/// scores `pointsPerSecond` while it lasts plus each trick landed, banked when
/// the rider kicks out at the far end; a wipe-out (a trick gone wrong, or just
/// bad luck) splashes, tumbles the rider under, loses that ride's points, and
/// it paddles back out. After `waves` waves, or once `length` seconds are up,
/// the last wave rides out and the tide goes out again, setting everyone down
/// on the floor. The best score wins; one surfing alone just surfs.
///
/// Pure, like the other games: the colony asks where each rider and board is,
/// frame by frame, and draws them and the water (`surface(at:)`).
extension Plays {

    public struct Surf: Equatable, Sendable {
        public enum Phase: Equatable, Sendable { case tideIn, session, tideOut, over }
        public enum Trick: String, Equatable, Sendable { case hop, spin }

        public enum Event: Equatable, Sendable {
            case tideIn
            /// Wave `number` (from 1) starts rolling in, `way` +1 toward growing x.
            case wave(number: Int, way: CGFloat)
            case caught(by: Int)
            /// The wave rolled by under it.
            case missed(by: Int)
            case trick(by: Int, Trick)
            case wipeout(by: Int, at: CGPoint)
            /// Rode it to the end: `points` for the ride, banked.
            case kickOut(by: Int, points: Int)
            /// Back out where it waits for the next one.
            case back(by: Int)
            case tideOut
            /// The best score: one winner, several for a tie; empty alone.
            case won(by: [Int])
            case over
        }

        public enum State: Equatable, Sendable {
            case paddling(to: CGFloat)
            case waiting
            case riding
            case trick(Trick, left: Double)
            case tumbling(left: Double)
            /// Waiting for the tide to go out.
            case done
        }

        public struct Rider: Equatable, Sendable {
            public let index: Int
            public let half: CGFloat
            /// Where it waits for a wave.
            public let lineup: CGFloat
            public internal(set) var x: CGFloat
            public internal(set) var y: CGFloat = 0
            public internal(set) var rotation: Double = 0
            public internal(set) var facing: CGFloat = 1
            public internal(set) var pose = "idle"
            public internal(set) var state: State
            public internal(set) var score = 0
            public internal(set) var rides = 0
            public internal(set) var wipeouts = 0
            /// Waves it let go by because two were on them already.
            public internal(set) var gaveWay = 0
            public internal(set) var tricks = 0
            /// The board: where its middle is, its turn, and whether it is under the rider's feet.
            public internal(set) var board = CGPoint.zero
            public internal(set) var boardRotation: Double = 0
            public internal(set) var onBoard = true
            /// The ride going on: how long, and its tricks' points.
            var rideTime = 0.0
            var ridePoints = 0
            var rideBonus = 0
            var lift: CGFloat = 0
            var spin = 0.0
            var bob: Double
            /// How far down the face it rides, 0 at the crest, 1 at the foot: each rider its own line.
            var pocket: Double

            public var isRiding: Bool {
                switch state { case .riding, .trick: true; default: false }
            }
        }

        /// A wave rolling along: its crest's x, and which one it is.
        public struct Wave: Equatable, Sendable {
            public var crest: CGFloat
            public var number: Int
        }

        public static let tideTime = 1.5
        public static let waveGap = 2.5
        /// Points per second: the wave, and a creature paddling.
        public static let waveSpeed: CGFloat = 170
        public static let paddleSpeed: CGFloat = 140
        public static let catchChance = 0.75
        /// Riders one wave carries: one low on the face, one up by the curl. The rest wait their turn.
        public static let perWave = 2
        /// Where they ride, down the face from the crest: the first to catch it, and the second.
        public static let pockets = [0.62, 0.18]
        /// Chances per second of riding: trying a trick (after the first second), wiping out.
        public static let trickRate = 0.35
        public static let wipeRate = 0.03
        /// A trick that goes wrong is a wipe-out.
        public static let trickFailChance = 0.2
        public static let trickTime = 0.7
        public static let tumbleTime = 1.4
        public static let pointsPerSecond = 10.0
        public static let trickPoints: [Trick: Int] = [.hop: 20, .spin: 35]
        /// The steepest a board leans riding, either way: a ride, not a climb.
        public static let steepest = 0.42
        /// Waiting on a wave that never comes (a rider who cannot get back): it starts without it.
        public static let waitAtMost = 8.0

        public let floorY: CGFloat
        public let span: ClosedRange<CGFloat>
        /// The tallest a wave stands over the calm water, and the calm water's depth.
        public let height: CGFloat
        public let depth: CGFloat
        /// +1: the waves roll toward growing x.
        public let way: CGFloat
        public let waves: Int
        public let length: Double
        public private(set) var phase: Phase = .tideIn
        public private(set) var riders: [Rider]
        public private(set) var wave: Wave?
        public private(set) var wavesRolled = 0
        /// How far in the tide is, 0 (dry) to 1.
        public private(set) var tide = 0.0
        public private(set) var clock = 0.0
        private var phaseClock = 0.0
        private var nextWaveAt = Surf.tideTime + 1.0
        private var scoring: Set<Int> = []

        /// A session on a floor at `floorY` running `span`, for `players` (each its
        /// half size and where it stands). `waveHeight` and `depth` in points;
        /// `waves` waves at most, `length` seconds at most.
        public init(players: [Int], halves: [Int: CGFloat], at: [Int: CGFloat], floorY: CGFloat, span: ClosedRange<CGFloat>,
                    waveHeight: CGFloat, depth: CGFloat, waves: Int, length: Double,
                    using rng: inout some RandomNumberGenerator) {
            self.floorY = floorY
            self.span = span
            height = max(20, waveHeight)
            self.depth = max(8, depth)
            self.waves = max(1, waves)
            self.length = max(10, length)
            let way: CGFloat = Bool.random(using: &rng) ? 1 : -1
            self.way = way
            let start = way > 0 ? span.lowerBound : span.upperBound
            let room = (span.upperBound - span.lowerBound) * 0.3
            let n = players.count
            var bobs: [Double] = []
            for _ in players { bobs.append(Double.random(in: 0...(2 * .pi), using: &rng)) }
            riders = players.enumerated().map { k, p in
                let line = start + way * room * (0.25 + 0.75 * (CGFloat(k) + 0.5) / CGFloat(max(n, 1)))
                return Rider(index: p, half: halves[p] ?? 20, lineup: line, x: at[p] ?? line, state: .paddling(to: line),
                             bob: bobs[k], pocket: Self.pockets[0])
            }
            for k in riders.indices { place(k) }
        }

        public var isFinished: Bool { phase == .over }
        public func rider(_ index: Int) -> Rider? { riders.first { $0.index == index } }
        public var scores: [Int: Int] { Dictionary(uniqueKeysWithValues: riders.map { ($0.index, $0.score) }) }

        /// The best score's riders; empty for one surfing alone.
        public var winners: [Int] {
            guard riders.count > 1, let best = riders.map(\.score).max() else { return [] }
            return riders.filter { $0.score == best }.map(\.index)
        }

        /// The scoreboard: "SURF Blocky 120 · Pip 85", the best first.
        public func board(_ name: (Int) -> String) -> String {
            tr("SURF") + " " + riders.sorted { $0.score > $1.score }.map { "\(name($0.index)) \($0.score)" }.joined(separator: " · ")
        }

        // MARK: The water

        /// The front of a wave (ahead of the crest) and its back, in points.
        public var faceWidth: CGFloat { height * 1.6 }
        public var backWidth: CGFloat { height * 2.8 }

        /// How far the wave lifts the water at `x`, 0 off it.
        public func lift(at x: CGFloat) -> CGFloat {
            guard let wave else { return 0 }
            let d = (x - wave.crest) * way
            let w = d >= 0 ? faceWidth : backWidth
            guard abs(d) < w else { return 0 }
            // The face hollow, steep under the crest and flattening to its foot; the back a long gentle slope.
            let shape = d >= 0 ? pow(1 - Double(d / w), 3) : 0.5 + 0.5 * cos(Double.pi * Double(d / w))
            return height * CGFloat(shape) * CGFloat(tide)
        }

        /// The water's top at `x`, in screen points.
        public func surface(at x: CGFloat) -> CGFloat {
            floorY + depth * CGFloat(tide) + lift(at: x)
        }

        /// The water's slope at `x`, as an angle (positive rising toward growing x).
        public func slope(at x: CGFloat) -> Double {
            atan2(Double(surface(at: x + 2) - surface(at: x - 2)), 4)
        }

        /// The far end: a wave rides out there.
        var farEnd: CGFloat { way > 0 ? span.upperBound : span.lowerBound }
        var nearEnd: CGFloat { way > 0 ? span.lowerBound : span.upperBound }

        // MARK: Running

        public mutating func update(dt: Double, using rng: inout some RandomNumberGenerator) -> [Event] {
            clock += dt
            phaseClock += dt
            var events: [Event] = []
            switch phase {
            case .tideIn:
                if phaseClock <= dt { events.append(.tideIn) }
                tide = min(1, phaseClock / Self.tideTime)
                if tide >= 1 { phase = .session; phaseClock = 0 }
            case .session:
                tide = 1
                rollWave(dt: dt, &events)
                let timeUp = clock >= Self.tideTime + length
                if wave == nil, wavesRolled >= waves || timeUp {
                    // Nobody still under: the tide goes out where they are.
                    if riders.allSatisfy({ if case .tumbling = $0.state { false } else { true } }) {
                        for k in riders.indices { riders[k].state = .done }
                        phase = .tideOut
                        phaseClock = 0
                        events.append(.tideOut)
                        events.append(.won(by: winners))
                    }
                } else if wave == nil, clock >= nextWaveAt,
                          riders.allSatisfy({ $0.state == .waiting }) || clock >= nextWaveAt + Self.waitAtMost {
                    wavesRolled += 1
                    wave = Wave(crest: nearEnd - way * backWidth, number: wavesRolled)
                    events.append(.wave(number: wavesRolled, way: way))
                }
            case .tideOut:
                tide = max(0, 1 - phaseClock / Self.tideTime)
                if tide <= 0 { phase = .over; events.append(.over) }
            case .over:
                break
            }
            for k in riders.indices { step(k, dt: dt, &events, using: &rng) }
            return events
        }

        private mutating func rollWave(dt: Double, _ events: inout [Event]) {
            guard var w = wave else { return }
            w.crest += way * Self.waveSpeed * CGFloat(dt)
            wave = w
            // Gone past the far end, its back and all.
            if (w.crest - farEnd) * way > backWidth {
                wave = nil
                nextWaveAt = clock + Self.waveGap
            }
        }

        private mutating func step(_ k: Int, dt: Double, _ events: inout [Event], using rng: inout some RandomNumberGenerator) {
            var r = riders[k]
            defer { riders[k] = r; place(k) }
            switch r.state {
            case .paddling(let to):
                guard phase != .tideIn else { break }
                let gap = to - r.x
                let move = min(abs(gap), Self.paddleSpeed * CGFloat(dt))
                r.facing = gap >= 0 ? 1 : -1
                r.x += gap >= 0 ? move : -move
                if abs(to - r.x) < 0.5 {
                    r.x = to
                    r.state = .waiting
                    r.facing = way
                    events.append(.back(by: r.index))
                }
            case .waiting:
                guard let w = wave else { break }
                let d = (r.x - w.crest) * way
                // The face reaches it: on it, or under it rolls.
                if d > 0, d < faceWidth * 0.5, !scoring.contains(r.index), (w.crest - nearEnd) * way > -backWidth * 0.2 {
                    scoring.insert(r.index)
                    let onIt = riders.filter(\.isRiding).count
                    if onIt < Self.perWave, Double.random(in: 0..<1, using: &rng) < Self.catchChance {
                        r.pocket = Self.pockets[min(onIt, Self.pockets.count - 1)]
                        r.state = .riding
                        r.rideTime = 0; r.ridePoints = 0; r.rideBonus = 0
                        r.rides += 1
                        r.facing = way
                        events.append(.caught(by: r.index))
                    } else {
                        events.append(.missed(by: r.index))
                    }
                }
                if wave == nil || d < -backWidth { scoring.remove(r.index) }
            case .riding:
                guard let w = wave else { kickOut(&r, &events); break }
                r.rideTime += dt
                r.ridePoints = Int(r.rideTime * Self.pointsPerSecond)
                // Carving up and down the face, a little ahead of the crest.
                r.x = w.crest + way * faceWidth * CGFloat(r.pocket + 0.12 * sin(r.rideTime * 2.2))
                if (r.x - farEnd) * way >= 0 { r.x = farEnd; kickOut(&r, &events); break }
                if Double.random(in: 0..<1, using: &rng) < Self.wipeRate * dt {
                    wipeOut(&r, &events)
                } else if r.rideTime > 1, Double.random(in: 0..<1, using: &rng) < Self.trickRate * dt {
                    r.state = .trick(Bool.random(using: &rng) ? .hop : .spin, left: Self.trickTime)
                }
            case .trick(let trick, let left):
                guard let w = wave else { r.lift = 0; r.spin = 0; kickOut(&r, &events); break }
                r.rideTime += dt
                r.x = w.crest + way * faceWidth * CGFloat(r.pocket + 0.12 * sin(r.rideTime * 2.2))
                if (r.x - farEnd) * way >= 0 { r.x = farEnd; r.lift = 0; r.spin = 0; kickOut(&r, &events); break }
                let p = 1 - max(0, left - dt) / Self.trickTime
                r.lift = r.half * (trick == .hop ? 1.6 : 0.8) * CGFloat(sin(Double.pi * p))
                r.spin = trick == .spin ? -Double(way) * 2 * .pi * p : 0
                if left - dt > 0 { r.state = .trick(trick, left: left - dt); break }
                r.lift = 0; r.spin = 0
                if Double.random(in: 0..<1, using: &rng) < Self.trickFailChance {
                    wipeOut(&r, &events)
                } else {
                    r.rideBonus += Self.trickPoints[trick] ?? 0
                    r.tricks += 1
                    r.state = .riding
                    events.append(.trick(by: r.index, trick))
                }
            case .tumbling(let left):
                // Rolled under and carried a little way by the wave, slowing.
                r.x += way * Self.waveSpeed * 0.4 * CGFloat(left / Self.tumbleTime) * CGFloat(dt)
                r.x = min(max(r.x, span.lowerBound), span.upperBound)
                r.spin -= Double(way) * 7 * dt
                if left - dt > 0 { r.state = .tumbling(left: left - dt); break }
                r.spin = 0
                r.onBoard = true
                r.state = .paddling(to: r.lineup)
            case .done:
                break
            }
        }

        private mutating func kickOut(_ r: inout Rider, _ events: inout [Event]) {
            let points = r.ridePoints + r.rideBonus
            r.score += points
            r.lift = 0; r.spin = 0
            r.state = phase == .session && wavesRolled < waves && clock < Self.tideTime + length ? .paddling(to: r.lineup) : .paddling(to: r.x)
            events.append(.kickOut(by: r.index, points: points))
        }

        private mutating func wipeOut(_ r: inout Rider, _ events: inout [Event]) {
            r.wipeouts += 1
            r.ridePoints = 0; r.rideBonus = 0
            r.lift = 0
            r.onBoard = false
            r.state = .tumbling(left: Self.tumbleTime)
            events.append(.wipeout(by: r.index, at: CGPoint(x: r.x, y: surface(at: r.x))))
        }

        /// Where rider `k` and its board are drawn, from its state and the water.
        private mutating func place(_ k: Int) {
            var r = riders[k]
            let water = surface(at: r.x)
            let thick = r.half * 0.25
            let angle = min(max(slope(at: r.x), -Self.steepest), Self.steepest)
            switch r.state {
            case .tumbling(let left):
                // Under the water's top, rolling; the board bobs where it was lost.
                let sink = r.half * CGFloat(0.6 * sin(Double.pi * min(1, (Self.tumbleTime - left) / Self.tumbleTime)))
                r.y = water - sink
                r.rotation = r.spin
                r.pose = "jump"
                r.board = CGPoint(x: r.x - way * r.half * 1.6, y: water + thick)
                r.boardRotation = sin(clock * 5) * 0.5
            default:
                let bob = r.state == .waiting || r.state == .done ? CGFloat(sin(clock * 2.4 + r.bob)) * 1.5 * CGFloat(tide) : 0
                let floating = water + thick + bob
                // On the floor when the tide is out.
                let onFloor = floorY + thick * 2
                let base = max(floating, onFloor)
                r.board = CGPoint(x: r.x, y: base - thick + r.lift)
                r.boardRotation = r.isRiding ? angle : angle * 0.5
                r.rotation = (r.isRiding ? angle : angle * 0.5) + r.spin
                let u = CGVector(dx: -sin(r.rotation), dy: cos(r.rotation))
                r.y = r.board.y + thick + r.half * CGFloat(u.dy)
                r.pose = switch r.state {
                case .paddling: "walk"
                case .trick: "jump"
                default: "idle"
                }
            }
            riders[k] = r
        }
    }
}

extension Plays.Kind {
    /// Which feature a model call for this game is priced under.
    public var spendPurpose: Spend.Purpose {
        switch self {
        case .soccer, .baseball: .ballGames
        case .surf: .surfing
        default: .plays
        }
    }
}

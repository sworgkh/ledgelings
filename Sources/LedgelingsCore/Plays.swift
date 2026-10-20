import CoreGraphics
import Foundation

/// Plays: now and then a creature stops walking and plays, the way the worms
/// in Worms fool about between turns, with nobody hurt. Four games here, and
/// two ball games for a crowd (`Plays+Soccer.swift`, `Plays+Baseball.swift`):
///
/// - **tag** (catch me if you can): two of them chase each other round the
///   edges; a touch makes the other one "it"; when the time is up both stand
///   puffing, a drop of sweat over their heads;
/// - **rope**: a ninja rope. It fires a grappling hook at the ceiling, is
///   reeled up off the floor, swings through, lets go at the top of the
///   swing and turns a somersault down to the floor;
/// - **parachute**: it jumps up to the ceiling, lets go, falls, and floats
///   down under a little parachute, swaying, to land softly;
/// - **basketball**: it puts a hoop on a wall at the end of its floor and
///   throws a ball at it, a few times; a pair takes turns. The ball flies,
///   hits the rim or the board, bounces on the floor, and sometimes goes in.
///
/// Closer pairs play together more often (`closeness`, from the moments of
/// their storyline): strangers mostly play alone, and only pairs who have
/// shared a few moments play tag or take turns at the hoop.
///
/// Everything here is pure: the colony asks each game where the creature and
/// the props are, frame by frame, and draws them.
public enum Plays {

    public enum Kind: String, CaseIterable, Codable, Sendable {
        case tag, rope, parachute, basketball, soccer, baseball

        /// Needs two: tag.
        public var needsPair: Bool { self == .tag }
        /// Can be played by two: tag, and turns at the hoop.
        public var canPair: Bool { self == .tag || self == .basketball }
        /// Played by however many are free, one to a crowd: soccer and baseball.
        public var isTeamGame: Bool { self == .soccer || self == .baseball }
        public var canSolo: Bool { !needsPair && !isTeamGame }

        /// In words, for a prompt and a storyline: "a game of tag".
        public var title: String {
            switch self {
            case .tag: tr("a game of catch me if you can")
            case .rope: tr("a swing on a ninja rope")
            case .parachute: tr("a parachute jump from the ceiling")
            case .basketball: tr("a game of basketball")
            case .soccer: tr("a game of soccer")
            case .baseball: tr("a game of baseball")
            }
        }
    }

    /// Screen points per second per second: what the rope, the parachute's
    /// first drop and the ball fall with.
    public static let gravity: CGFloat = 1600
    /// Share of throws at the hoop aimed true; the rest are a little short or long.
    public static let makeChance = 0.5

    // MARK: Who plays, and when

    /// Moments shared before a pair counts as close as can be.
    public static let closeAt = 20.0
    /// Moments shared before a pair plays together at all.
    public static let friendsAt = 3

    /// How close two characters are, 0...1: the moments of their storyline
    /// (or, before storylines, their talks) out of `closeAt`.
    public static func closeness(_ bond: Bonds.Bond?) -> Double {
        guard let bond else { return 0 }
        let moments = max(bond.tally.values.reduce(0, +), bond.talks)
        return min(1, Double(moments) / closeAt)
    }

    /// Seconds until the next play: about `everyMinutes` (between 0.6 and 1.4
    /// of it), shorter the closer the closest pair on screen is. `boost` is the
    /// percentage a perfectly close pair speeds it up by: 100 halves the wait.
    public static func wait(everyMinutes: Double, boost: Double, closeness: Double,
                            using rng: inout some RandomNumberGenerator) -> Double {
        let base = max(0.1, everyMinutes) * 60 * Double.random(in: 0.6...1.4, using: &rng)
        return base / (1 + max(0, boost) / 100 * min(max(closeness, 0), 1))
    }

    /// The chance a close pair plays together rather than one of them alone.
    public static func pairChance(_ closeness: Double) -> Double {
        min(0.85, 0.2 + 0.65 * closeness)
    }

    /// What `initiator` plays, and with whom: with its closest friend among
    /// `others` (`pairChance`), a game for two; else a game alone. `others` is
    /// everyone else free to play, with how close each is to the initiator.
    /// Nil when nothing it may play is on.
    public static func choose(initiator: Int, others: [(index: Int, closeness: Double)], enabled: Set<Kind>,
                              using rng: inout some RandomNumberGenerator) -> (kind: Kind, players: [Int])? {
        let pairs = Kind.allCases.filter { enabled.contains($0) && $0.canPair }
        let solos = Kind.allCases.filter { enabled.contains($0) && $0.canSolo }
        let friend = others.filter { $0.closeness >= Double(friendsAt) / closeAt }.max { $0.closeness < $1.closeness }
        if let friend, !pairs.isEmpty, solos.isEmpty || Double.random(in: 0..<1, using: &rng) < pairChance(friend.closeness) {
            return (pairs.randomElement(using: &rng)!, [initiator, friend.index])
        }
        guard let kind = solos.randomElement(using: &rng) else { return nil }
        return (kind, [initiator])
    }

    // MARK: Tag

    /// A game of tag between `players[0]` and `players[1]`; `it` chases.
    ///
    /// ready → chase → puffing → over. Ready is a beat for "it" to count;
    /// after each touch the new "it" counts again (`counting`) while the other
    /// runs off. When `length` is up, both stand puffing for `puffTime`.
    public struct Tag: Equatable, Sendable {
        public enum Phase: Equatable, Sendable { case ready, chase, puffing, over }
        public enum Event: Equatable, Sendable {
            case go
            /// `it` touched the other: the other is "it" now.
            case tagged(by: Int, now: Int)
            case puffing
            case over
        }
        public static let readyTime = 1.2
        public static let counting = 1.0
        public static let puffTime = 3.5
        /// Points per second: the one running away, and "it", a little faster.
        public static let fleeSpeed: CGFloat = 130
        public static let chaseSpeed: CGFloat = 190

        public let players: [Int]
        public let length: Double
        public private(set) var it: Int
        public private(set) var phase: Phase = .ready
        public private(set) var touches = 0
        private var clock = 0.0
        private var total = 0.0
        /// "It" stands counting until this.
        private var countUntil = Tag.readyTime

        public init(it: Int, other: Int, length: Double) {
            players = [it, other]
            self.it = it
            self.length = max(1, length)
        }

        public var runner: Int { players[0] == it ? players[1] : players[0] }
        /// "It" stands still, counting, before it runs after the other.
        public var itIsCounting: Bool { phase == .ready || (phase == .chase && clock < countUntil) }

        /// The chaser caught up: `gap` points between their centres along the
        /// edge, `reach` the two half sizes added up.
        public mutating func near(gap: CGFloat, reach: CGFloat) -> Event? {
            guard phase == .chase, !itIsCounting, gap <= reach else { return nil }
            let was = it
            it = runner
            touches += 1
            countUntil = clock + Self.counting
            return .tagged(by: was, now: it)
        }

        public mutating func update(dt: Double) -> [Event] {
            clock += dt
            total += dt
            switch phase {
            case .ready:
                guard clock >= Self.readyTime else { return [] }
                phase = .chase
                return [.go]
            case .chase:
                guard total >= Self.readyTime + length else { return [] }
                phase = .puffing
                clock = 0
                return [.puffing]
            case .puffing:
                guard clock >= Self.puffTime else { return [] }
                phase = .over
                return [.over]
            case .over:
                return []
            }
        }
    }

    // MARK: The rope

    /// A swing on a ninja rope, from `start` (the creature's centre on a floor)
    /// to a hook in the ceiling above and ahead of it.
    ///
    /// aim → fire → reel → swing → fly → landed. It aims, fires the hook
    /// (`hook` flies up to `anchor`), is reeled up the rope until it hangs
    /// `clearance` above the floor at the bottom of the swing, swings through
    /// as a pendulum, lets go `releaseShare` of the way up the other side, and
    /// flies, turning a somersault, until it is back down at floor height.
    public struct Rope: Equatable, Sendable {
        public enum Phase: Equatable, Sendable { case aim, fire, reel, swing, fly, landed }
        public enum Event: Equatable, Sendable { case fired, hooked, swinging, letGo, landed }
        public static let aimTime = 0.5
        public static let fireTime = 0.3
        public static let reelTime = 0.55
        public static let releaseShare = 0.55
        /// The steepest the rope may start, from straight up, and the shallowest.
        public static let steepest = 45.0 * .pi / 180
        public static let shallowest = 20.0 * .pi / 180

        public let start: CGPoint
        public let anchor: CGPoint
        public let floorY: CGFloat
        /// Where along the floor it may come down: the floor's two ends.
        public let floor: ClosedRange<CGFloat>
        /// +1 swings toward growing x.
        public let way: CGFloat
        /// The rope as fired, and once reeled in.
        public let firedLength: CGFloat
        public let length: CGFloat
        public let startAngle: Double
        public private(set) var phase: Phase = .aim
        public private(set) var position: CGPoint
        public private(set) var rotation: Double = 0
        /// Where the hook is: flying up while fired, then in the ceiling.
        public private(set) var hook: CGPoint
        public private(set) var angle: Double
        public private(set) var spin: Double = 0
        public private(set) var velocity = CGVector.zero
        private var clock = 0.0
        private var flightTurn = 0.0
        private var flightTime = 1.0

        /// Plan a swing from `start`, under a ceiling at `ceilingY`, along a floor
        /// running `floor`, going `way` if there is room (else the other way).
        /// Nil when the ceiling is too low or the floor too short either way.
        public init?(from start: CGPoint, ceilingY: CGFloat, floor: ClosedRange<CGFloat>,
                     way preferred: CGFloat, clearance: CGFloat) {
            let height = ceilingY - start.y
            let length = height - clearance
            guard length >= 60 else { return nil }
            for way in [preferred < 0 ? CGFloat(-1) : 1, preferred < 0 ? 1 : -1] {
                let room = way > 0 ? floor.upperBound - start.x : start.x - floor.lowerBound
                var theta = Self.steepest
                while theta >= Self.shallowest - 1e-9 {
                    // Ahead to the hook, on past it to where it lets go, and the flight from there to the floor.
                    let needed = height * CGFloat(tan(theta)) + Self.reach(length: length, angle: theta, above: clearance) + 10
                    if needed <= room {
                        self.start = start
                        self.floorY = start.y
                        self.floor = floor
                        self.way = way
                        anchor = CGPoint(x: start.x + way * height * CGFloat(tan(theta)), y: ceilingY)
                        firedLength = height / CGFloat(cos(theta))
                        self.length = length
                        startAngle = -Double(way) * theta
                        angle = startAngle
                        position = start
                        hook = start
                        return
                    }
                    theta -= 5 * .pi / 180
                }
            }
            return nil
        }

        /// How far past the hook a swing from `angle` (from straight down) on a rope
        /// `length` long carries it: to where it lets go, then its flight down to a
        /// floor `above` below the bottom of the swing.
        public static func reach(length: CGFloat, angle: Double, above: CGFloat) -> CGFloat {
            let release = angle * releaseShare, g = Plays.gravity
            let speed = sqrt(max(0, 2 * g * length * CGFloat(cos(release) - cos(angle))))
            let vx = speed * CGFloat(cos(release)), vy = speed * CGFloat(sin(release))
            let height = above + length * (1 - CGFloat(cos(release)))
            let time = (vy + sqrt(vy * vy + 2 * g * height)) / g
            return length * CGFloat(sin(release)) + vx * time
        }

        public var pose: String {
            switch phase {
            case .aim, .fire: "idle"
            case .reel, .swing, .fly: "jump"
            case .landed: "land"
            }
        }

        /// The rope is out, from the creature to the hook.
        public var ropeIsOut: Bool { phase == .fire || phase == .reel || phase == .swing }

        func hanging(_ angle: Double, _ length: CGFloat) -> CGPoint {
            CGPoint(x: anchor.x + length * CGFloat(sin(angle)), y: anchor.y - length * CGFloat(cos(angle)))
        }

        public mutating func update(dt: Double) -> [Event] {
            clock += dt
            switch phase {
            case .aim:
                guard clock >= Self.aimTime else { return [] }
                enter(.fire)
                return [.fired]
            case .fire:
                let p = min(1, clock / Self.fireTime)
                hook = CGPoint(x: start.x + (anchor.x - start.x) * p, y: start.y + (anchor.y - start.y) * p)
                guard p >= 1 else { return [] }
                enter(.reel)
                return [.hooked]
            case .reel:
                let p = min(1, clock / Self.reelTime), eased = p * p * (3 - 2 * p)
                position = hanging(startAngle, firedLength + (length - firedLength) * CGFloat(eased))
                rotation = angle * eased
                guard p >= 1 else { return [] }
                enter(.swing)
                return [.swinging]
            case .swing:
                // A pendulum, stepped finely so it neither gains nor loses much.
                var left = dt
                while left > 0 {
                    let h = min(left, 1.0 / 240)
                    spin += -Double(Plays.gravity / length) * sin(angle) * h
                    angle += spin * h
                    left -= h
                }
                position = hanging(angle, length)
                rotation = angle
                guard angle * Double(way) >= abs(startAngle) * Self.releaseShare, spin * Double(way) > 0 else { return [] }
                velocity = CGVector(dx: length * CGFloat(spin * cos(angle)), dy: length * CGFloat(spin * sin(angle)))
                let height = position.y - floorY, g = Plays.gravity
                let time = Double((velocity.dy + sqrt(max(0, velocity.dy * velocity.dy + 2 * g * height))) / g)
                // A whole somersault forwards, landing upright.
                flightTurn = rotation
                flightTime = max(0.2, time)
                enter(.fly)
                return [.letGo]
            case .fly:
                velocity.dy -= Plays.gravity * CGFloat(dt)
                var p = CGPoint(x: position.x + velocity.dx * CGFloat(dt), y: position.y + velocity.dy * CGFloat(dt))
                if p.x < floor.lowerBound || p.x > floor.upperBound {
                    p.x = min(max(p.x, floor.lowerBound), floor.upperBound)
                    velocity.dx = 0
                }
                position = p
                let share = min(1, clock / flightTime)
                rotation = flightTurn + (-2 * .pi * Double(way) - flightTurn) * share
                guard position.y <= floorY else { return [] }
                position.y = floorY
                rotation = 0
                enter(.landed)
                return [.landed]
            case .landed:
                return []
            }
        }

        private mutating func enter(_ next: Phase) {
            phase = next
            clock = 0
        }
    }

    // MARK: The parachute

    /// A parachute jump from `top` (the creature's centre, upside down on a
    /// ceiling) down to the floor at `floorY`.
    ///
    /// hang → drop → open → float → landed → packed. A moment hanging on, a
    /// short fall turning upright, the canopy pops open and slows it to
    /// `fallSpeed`, then it floats down swaying `sway` points either side; on
    /// the floor the canopy folds away over `packTime`.
    public struct Chute: Equatable, Sendable {
        public enum Phase: Equatable, Sendable { case hang, drop, open, float, landed, packed }
        public enum Event: Equatable, Sendable { case jumped, opened, landed, packed }
        public static let hangTime = 0.8
        public static let dropTime = 0.4
        public static let openTime = 0.4
        public static let packTime = 0.7
        public static let swayPeriod = 2.6
        public static let sway: CGFloat = 16
        public static let tilt = 0.14

        public let top: CGPoint
        public let floorY: CGFloat
        public let floor: ClosedRange<CGFloat>
        public let fallSpeed: CGFloat
        public private(set) var phase: Phase = .hang
        public private(set) var position: CGPoint
        public private(set) var rotation: Double = .pi
        /// How open the canopy is: 0 folded, 1 open.
        public private(set) var canopy: Double = 0
        private var clock = 0.0
        private var floatTime = 0.0
        private var speed: CGFloat = 0
        private var swayFrom: CGFloat

        public init(from top: CGPoint, floorY: CGFloat, floor: ClosedRange<CGFloat>, fallSpeed: CGFloat) {
            self.top = top
            self.floorY = floorY
            self.floor = floor
            self.fallSpeed = max(10, fallSpeed)
            position = top
            swayFrom = top.x
        }

        public var pose: String {
            switch phase {
            case .hang: "idle"
            case .drop, .open, .float: "jump"
            case .landed, .packed: clock < 0.3 ? "land" : "idle"
            }
        }

        public mutating func update(dt: Double) -> [Event] {
            clock += dt
            switch phase {
            case .hang:
                guard clock >= Self.hangTime else { return [] }
                enter(.drop)
                return [.jumped]
            case .drop:
                let p = min(1, clock / Self.dropTime)
                speed = Plays.gravity * CGFloat(clock)
                position.y = top.y - Plays.gravity * CGFloat(clock * clock) / 2
                rotation = .pi * (1 - p * p * (3 - 2 * p))
                if landed() { return [.landed] }
                guard p >= 1 else { return [] }
                enter(.open)
                return [.opened]
            case .open:
                let p = min(1, clock / Self.openTime)
                canopy = p
                let v = speed + (fallSpeed - speed) * CGFloat(p)
                position.y -= v * CGFloat(dt)
                rotation = 0
                if landed() { return [.landed] }
                guard p >= 1 else { return [] }
                enter(.float)
                return []
            case .float:
                floatTime += dt
                let phaseAngle = 2 * .pi * floatTime / Self.swayPeriod
                position.y -= fallSpeed * CGFloat(dt)
                position.x = min(max(swayFrom + Self.sway * CGFloat(sin(phaseAngle)), floor.lowerBound), floor.upperBound)
                rotation = -Self.tilt * cos(phaseAngle)
                return landed() ? [.landed] : []
            case .landed:
                rotation = 0
                canopy = max(0, 1 - clock / Self.packTime)
                guard clock >= Self.packTime else { return [] }
                enter(.packed)
                return [.packed]
            case .packed:
                return []
            }
        }

        private mutating func landed() -> Bool {
            guard position.y <= floorY else { return false }
            position.y = floorY
            position.x = min(max(position.x, floor.lowerBound), floor.upperBound)
            rotation = 0
            canopy = max(canopy, 0.0001)
            enter(.landed)
            return true
        }

        private mutating func enter(_ next: Phase) {
            phase = next
            clock = 0
        }
    }

    // MARK: Basketball

    /// The hoop's shape, in sheet pixels, as `spritetool/painters/play.py`
    /// draws it in its 32×28 cell: hung on a wall to its right, the rim's top
    /// row `rimRow` pixels from the cell's top, running from column `rimFrom`
    /// to `rimTo`.
    public enum Props {
        public static let cell = CGSize(width: 32, height: 28)
        public static let rimRow: CGFloat = 14
        public static let rimFrom: CGFloat = 8
        public static let rimTo: CGFloat = 25
        /// The ball's radius, in sheet pixels: 10 across, its outline a soft edge.
        public static let ballRadius: CGFloat = 5
    }

    /// A hoop on a wall, in screen points: `wallX` is the wall, `side` +1 when
    /// the wall is on the right of the court (the hoop opens leftwards).
    public struct Hoop: Equatable, Sendable {
        public var wallX: CGFloat
        public var side: CGFloat
        /// The rim's height: its top.
        public var rimY: CGFloat
        /// The middle of the rim, and half its width.
        public var rimX: CGFloat
        public var rimHalf: CGFloat
        /// Where the cell's middle goes, to draw it.
        public var centre: CGPoint

        /// A hoop drawn at `scale` points per pixel, its rim `height` points above `floorY` (the screen's floor).
        public init(wallX: CGFloat, side: CGFloat, floorY: CGFloat, height: CGFloat, scale: CGFloat) {
            self.wallX = wallX
            self.side = side < 0 ? -1 : 1
            let fromWall = (Props.cell.width - (Props.rimFrom + Props.rimTo + 1) / 2) * scale
            rimX = wallX - self.side * fromWall
            rimHalf = (Props.rimTo + 1 - Props.rimFrom) / 2 * scale
            rimY = floorY + height
            let cellTop = rimY + Props.rimRow * scale
            centre = CGPoint(x: wallX - self.side * Props.cell.width / 2 * scale, y: cellTop - Props.cell.height / 2 * scale)
        }

        /// The rim's end away from the wall: the ball bounces off it.
        public var front: CGPoint { CGPoint(x: rimX - side * rimHalf, y: rimY) }
    }

    /// The ball: thrown, falling, bouncing on the floor, the wall behind the
    /// hoop and the rim's front end, coming to rest. It is in when it drops
    /// down through the rim.
    public struct Ball: Equatable, Sendable {
        public enum Event: Equatable, Sendable { case floor, rim, board, scored }
        public var position: CGPoint
        public var velocity: CGVector
        public let radius: CGFloat
        /// Share of its speed kept on each bounce, 0...0.95.
        public let bounce: CGFloat
        public let hoop: Hoop
        /// The floor's height (the screen's), and the court's two ends.
        public let floorY: CGFloat
        public let court: ClosedRange<CGFloat>
        public private(set) var scored = false
        /// Spun this far, for drawing: it turns as it flies and rolls.
        public private(set) var turn: Double = 0
        public private(set) var resting = false

        public init(at position: CGPoint, velocity: CGVector, radius: CGFloat, bounce: CGFloat,
                    hoop: Hoop, floorY: CGFloat, court: ClosedRange<CGFloat>) {
            self.position = position
            self.velocity = velocity
            self.radius = radius
            self.bounce = min(max(bounce, 0), 0.95)
            self.hoop = hoop
            self.floorY = floorY
            self.court = court
        }

        /// The throw from `from` that peaks `apex` points above the rim and
        /// comes down through its middle.
        public static func aim(from: CGPoint, hoop: Hoop, apex: CGFloat) -> CGVector {
            let g = Plays.gravity
            let top = max(hoop.rimY, from.y) + max(10, apex)
            let up = sqrt(2 * g * (top - from.y)), rise = up / g
            let fall = sqrt(2 * (top - (hoop.rimY + 1)) / g)
            return CGVector(dx: (hoop.rimX - from.x) / (rise + fall), dy: up)
        }

        public mutating func step(dt: Double) -> [Event] {
            var events: [Event] = []
            var left = dt
            while left > 0, !resting {
                let h = CGFloat(min(left, 1.0 / 240))
                left -= Double(h)
                let before = position
                velocity.dy -= Plays.gravity * h
                position.x += velocity.dx * h
                position.y += velocity.dy * h
                turn += Double(velocity.dx * h / max(radius, 1))
                // Down through the rim, between its ends: in.
                if !scored, before.y >= hoop.rimY, position.y < hoop.rimY, velocity.dy < 0,
                   abs(position.x - hoop.rimX) <= hoop.rimHalf - radius * 0.4 {
                    scored = true
                    events.append(.scored)
                }
                // The rim's front end: a hard little point.
                let f = hoop.front
                let dx = position.x - f.x, dy = position.y - f.y, d = hypot(dx, dy)
                if d < radius, d > 0 {
                    let n = CGVector(dx: dx / d, dy: dy / d)
                    let along = velocity.dx * n.dx + velocity.dy * n.dy
                    if along < 0 {
                        velocity.dx -= (1 + bounce) * along * n.dx
                        velocity.dy -= (1 + bounce) * along * n.dy
                        events.append(.rim)
                    }
                    position = CGPoint(x: f.x + n.dx * radius, y: f.y + n.dy * radius)
                }
                // The wall the hoop hangs on (the board), and the court's other end.
                let wall = hoop.wallX - hoop.side * radius
                if hoop.side > 0 ? position.x > wall : position.x < wall {
                    position.x = wall
                    if velocity.dx * hoop.side > 0 { velocity.dx = -velocity.dx * bounce; events.append(.board) }
                }
                let lo = court.lowerBound + radius, hi = court.upperBound - radius
                if position.x < lo, velocity.dx < 0 { position.x = lo; velocity.dx = -velocity.dx * bounce }
                if position.x > hi, velocity.dx > 0 { position.x = hi; velocity.dx = -velocity.dx * bounce }
                if position.y < floorY + radius {
                    position.y = floorY + radius
                    if velocity.dy < -40 { events.append(.floor) }
                    velocity.dy = abs(velocity.dy) * bounce
                    velocity.dx *= 0.9
                    if velocity.dy < 30 { velocity.dy = 0 }
                    if abs(velocity.dx) < 8, velocity.dy == 0 { resting = true }
                }
            }
            return events
        }
    }
}

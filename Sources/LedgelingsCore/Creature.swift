import CoreGraphics
import Foundation

public enum Eyes: String, Sendable { case open, half, closed }

/// One creature's whole behaviour, with no window and no clock of its own.
/// Feed it `update(dt:cursor:using:)`; read back where and how to draw it.
public struct Creature: Sendable {
    public struct Config: Sendable {
        public var walkSpeed: CGFloat = 55          // points per second
        public var fleeRadius: CGFloat = 90         // cursor closer than this -> jump
        public var turnSpeed: Double = 9            // radians per second, at corners
        public var jumpSpeed: CGFloat = 1500        // points per second through the air
        public var jumpDuration: ClosedRange<Double> = 0.35...0.8
        public var landDuration: Double = 0.16
        public var walkSpell: ClosedRange<Double> = 3...9
        public var idleSpell: ClosedRange<Double> = 0.8...2.5
        public var blinkEvery: ClosedRange<Double> = 1.5...5
        /// At nightfall each creature keeps going this long before it nods off,
        /// so a colony does not drop asleep in the same frame.
        public var dozeOffAfter: ClosedRange<Double> = 0.5...7
        public var wakeUpAfter: ClosedRange<Double> = 0...3
        /// Startled awake at night: how long it wanders before sleeping again.
        public var restlessSpell: ClosedRange<Double> = 1.5...3.5
        public var reverseChance: Double = 0.35
        public init() {}
    }

    public struct Jump: Sendable, Equatable {
        public var from: CGPoint
        public var fromRotation: Double
        public var to: EdgeWorld.Spot
        /// Which way the flight path bows, as a vector of length 0...1.
        public var bulge: CGVector
        public var duration: Double
        public var elapsed: Double = 0
    }

    public enum Mode: Sendable, Equatable {
        case walking(remaining: Double)
        case idle(remaining: Double)
        case jumping(Jump)
        case landing(remaining: Double)
        /// `wakeIn` is nil while it is night, and counts down once day breaks.
        case sleeping(wakeIn: Double?)
        /// Picked up by the user, fast asleep, going wherever the cursor goes.
        case held
    }

    public private(set) var world: EdgeWorld
    public var config: Config
    public private(set) var spot: EdgeWorld.Spot
    /// +1 walks counter-clockwise (rightwards along the bottom edge), -1 clockwise.
    public private(set) var direction: CGFloat = 1
    public private(set) var position: CGPoint
    public private(set) var rotation: Double
    public private(set) var mode: Mode
    public private(set) var eyes: Eyes = .open
    /// Seconds spent in the current animation; the renderer turns it into a frame.
    public private(set) var animationTime: Double = 0

    private var blinkIn: Double
    private var blinkElapsed: Double?
    private var knowsItIsNight = false
    /// Put to sleep by hand. Daylight does not end a nap; the next dawn does.
    public private(set) var isNapping = false
    /// Set while a dropped sleeper falls back to an edge, so it lands still asleep.
    private var sleepsThroughLanding = false

    /// half -> closed -> half, in seconds.
    static let blinkPhases: [(Eyes, Double)] = [(.half, 0.05), (.closed, 0.09), (.half, 0.05)]

    public init(world: EdgeWorld, spot: EdgeWorld.Spot = .init(loop: 0, t: 0),
                facingForwards: Bool = true, config: Config = Config()) {
        self.world = world
        direction = facingForwards ? 1 : -1
        self.config = config
        self.spot = EdgeWorld.Spot(loop: spot.loop, t: world.loops[spot.loop].wrap(spot.t))
        position = world.point(at: spot)
        rotation = world.loops[spot.loop].rotation(ofSegment: world.loops[spot.loop].segment(at: spot.t))
        mode = .walking(remaining: config.walkSpell.upperBound)
        blinkIn = config.blinkEvery.lowerBound
    }

    // MARK: What to draw

    public var loop: EdgeLoop { world.loops[spot.loop] }
    public var t: CGFloat { spot.t }
    public var segment: Int { loop.segment(at: spot.t) }
    /// The angle the creature should stand at where it is now.
    public var restingRotation: Double { loop.rotation(ofSegment: segment) }

    public var animation: String {
        switch mode {
        case .walking: "walk"
        case .idle: "idle"
        case .jumping: "jump"
        case .landing: "land"
        case .sleeping, .held: "sleep"
        }
    }

    /// Asleep on an edge, or asleep in the user's hand.
    public var isSleeping: Bool {
        switch mode {
        case .sleeping, .held: true
        default: false
        }
    }

    public var isHeld: Bool { mode == .held }
    /// Eyes shut and Zs floating: asleep, or a sleeper falling back to an edge.
    public var looksAsleep: Bool { isSleeping || sleepsThroughLanding }

    /// The sheet is drawn facing right; mirror it to walk the other way.
    public var isMirrored: Bool { direction < 0 }

    public var isJumping: Bool { if case .jumping = mode { true } else { false } }

    // MARK: Driving it

    public mutating func update(dt: Double, cursor: CGPoint?, isNight: Bool = false,
                                using rng: inout some RandomNumberGenerator) {
        guard dt > 0 else { return }
        if looksAsleep { eyes = .closed; blinkElapsed = nil } else { updateBlink(dt: dt, using: &rng) }
        noticeTimeOfDay(isNight: isNight, using: &rng)

        // A sleeper does not notice the cursor. That is what lets you pick it up.
        if !isJumping, !looksAsleep, let cursor, hypot(cursor.x - position.x, cursor.y - position.y) < config.fleeRadius {
            startle(using: &rng)
        }

        animationTime += dt
        switch mode {
        case .walking(let remaining):
            spot.t = loop.wrap(spot.t + direction * config.walkSpeed * dt)
            position = world.point(at: spot)
            turn(toward: restingRotation, dt: dt)
            if remaining - dt <= 0 {
                enter(isNight ? .sleeping(wakeIn: nil) : .idle(remaining: .random(in: config.idleSpell, using: &rng)))
            } else {
                mode = .walking(remaining: remaining - dt)
            }

        case .idle(let remaining):
            turn(toward: restingRotation, dt: dt)
            if remaining - dt <= 0 {
                if isNight { enter(.sleeping(wakeIn: nil)); break }
                if Double.random(in: 0..<1, using: &rng) < config.reverseChance { direction = -direction }
                enter(.walking(remaining: .random(in: config.walkSpell, using: &rng)))
            } else {
                mode = .idle(remaining: remaining - dt)
            }

        case .jumping(var jump):
            jump.elapsed += dt
            let p = min(1, jump.elapsed / jump.duration)
            let eased = p * p * (3 - 2 * p)
            let target = world.point(at: jump.to)
            let landing = world.loops[jump.to.loop]
            // Arc through the air, bulging away from the edges it leaves and lands on.
            let distance = hypot(target.x - jump.from.x, target.y - jump.from.y)
            let pull = sin(.pi * p) * 0.2 * distance
            position = CGPoint(
                x: jump.from.x + (target.x - jump.from.x) * eased + jump.bulge.dx * pull,
                y: jump.from.y + (target.y - jump.from.y) * eased + jump.bulge.dy * pull
            )
            let goal = landing.rotation(ofSegment: landing.segment(at: jump.to.t))
            rotation = jump.fromRotation + Self.shortestArc(from: jump.fromRotation, to: goal) * eased
            if p >= 1 {
                spot = jump.to
                position = target
                rotation = goal
                enter(.landing(remaining: config.landDuration))
            } else {
                mode = .jumping(jump)
            }

        case .landing(let remaining):
            if remaining - dt <= 0, sleepsThroughLanding {
                sleepsThroughLanding = false
                enter(.sleeping(wakeIn: nil))
            } else if remaining - dt <= 0 {
                enter(.walking(remaining: .random(in: isNight ? config.restlessSpell : config.walkSpell, using: &rng)))
            } else {
                mode = .landing(remaining: remaining - dt)
            }

        case .sleeping(let wakeIn):
            turn(toward: restingRotation, dt: dt)
            guard let wakeIn else { break }
            if wakeIn - dt <= 0 {
                enter(.walking(remaining: .random(in: config.walkSpell, using: &rng)))
            } else {
                mode = .sleeping(wakeIn: wakeIn - dt)
            }

        case .held:
            turn(toward: 0, dt: dt)      // dangles upright
        }
    }

    // MARK: The user's hand

    /// Shift-click: put an awake creature down for a nap, or wake a sleeper.
    public mutating func toggleNap(using rng: inout some RandomNumberGenerator) {
        guard !isJumping, !isHeld else { return }
        if isSleeping {
            isNapping = false
            enter(.walking(remaining: .random(in: config.walkSpell, using: &rng)))
        } else {
            isNapping = true
            enter(.sleeping(wakeIn: nil))
        }
    }

    /// Only a sleeper can be picked up. Returns whether it was.
    @discardableResult
    public mutating func pickUp() -> Bool {
        guard case .sleeping = mode else { return false }
        enter(.held)
        return true
    }

    public mutating func drag(to point: CGPoint) {
        guard isHeld else { return }
        position = point
    }

    /// Let go: it drops to the nearest edge of any monitor, without waking.
    public mutating func drop() {
        guard isHeld else { return }
        let to = world.nearest(to: position)
        let target = world.point(at: to)
        let distance = hypot(target.x - position.x, target.y - position.y)
        sleepsThroughLanding = true
        enter(.jumping(Jump(from: position, fromRotation: rotation, to: to, bulge: .zero,
                            duration: max(0.12, min(Double(distance / config.jumpSpeed), config.jumpDuration.upperBound)))))
    }

    /// React to dusk and dawn, once each.
    private mutating func noticeTimeOfDay(isNight: Bool, using rng: inout some RandomNumberGenerator) {
        if isNight, !knowsItIsNight {
            let awakeFor = Double.random(in: config.dozeOffAfter, using: &rng)
            switch mode {
            case .walking(let remaining): mode = .walking(remaining: min(remaining, awakeFor))
            case .idle(let remaining): mode = .idle(remaining: min(remaining, awakeFor))
            default: break
            }
        }
        if !isNight, knowsItIsNight { isNapping = false }      // dawn ends every nap
        if !isNight, !isNapping, case .sleeping(nil) = mode {
            mode = .sleeping(wakeIn: .random(in: config.wakeUpAfter, using: &rng))
        }
        if isNight, case .sleeping(.some(_)) = mode { mode = .sleeping(wakeIn: nil) }
        knowsItIsNight = isNight
    }

    /// Jump to a random spot on a random OTHER edge -- of any monitor. Longer
    /// edges are likelier, so a big monitor gets its fair share of landings.
    public mutating func startle(using rng: inout some RandomNumberGenerator) {
        guard !isJumping else { return }
        let here = (loop: spot.loop, segment: segment)
        let others = world.segments.filter { ($0.loop, $0.segment) != here && $0.length > 1 }
        guard !others.isEmpty else { return }
        var pick = CGFloat.random(in: 0..<others.reduce(0) { $0 + $1.length }, using: &rng)
        let chosen = others.first { pick -= $0.length; return pick < 0 } ?? others[others.count - 1]
        let landing = world.loops[chosen.loop]
        let to = EdgeWorld.Spot(loop: chosen.loop,
                                t: landing.t(onSegment: chosen.segment, fraction: .random(in: 0.15...0.85, using: &rng)))
        let target = world.point(at: to)
        let distance = hypot(target.x - position.x, target.y - position.y)
        let duration = min(max(Double(distance / config.jumpSpeed), config.jumpDuration.lowerBound),
                           config.jumpDuration.upperBound)
        let a = loop.inward(ofSegment: segment), b = landing.inward(ofSegment: chosen.segment)
        direction = Bool.random(using: &rng) ? 1 : -1
        enter(.jumping(Jump(from: position, fromRotation: rotation, to: to,
                            bulge: CGVector(dx: (a.dx + b.dx) / 2, dy: (a.dy + b.dy) / 2), duration: duration)))
    }

    /// The monitors changed under the creature -- resized, unplugged, rearranged.
    /// Put it on the nearest edge that still exists and abandon any jump.
    public mutating func rehome(to newWorld: EdgeWorld) {
        world = newWorld
        spot = newWorld.nearest(to: position)
        position = newWorld.point(at: spot)
        rotation = restingRotation
        let asleep = looksAsleep
        sleepsThroughLanding = false
        enter(asleep ? .sleeping(wakeIn: nil) : .walking(remaining: config.walkSpell.lowerBound))
        knowsItIsNight = asleep
    }

    // MARK: Internals

    private mutating func enter(_ newMode: Mode) {
        mode = newMode
        animationTime = 0
    }

    private mutating func turn(toward goal: Double, dt: Double) {
        let delta = Self.shortestArc(from: rotation, to: goal)
        let step = config.turnSpeed * dt
        rotation = abs(delta) <= step ? goal : rotation + (delta > 0 ? step : -step)
    }

    private mutating func updateBlink(dt: Double, using rng: inout some RandomNumberGenerator) {
        if let elapsed = blinkElapsed {
            var clock = elapsed + dt
            blinkElapsed = clock
            for (phase, length) in Self.blinkPhases {
                if clock < length { eyes = phase; return }
                clock -= length
            }
            eyes = .open
            blinkElapsed = nil
            blinkIn = .random(in: config.blinkEvery, using: &rng)
        } else {
            blinkIn -= dt
            if blinkIn <= 0 {
                blinkElapsed = 0
                eyes = Self.blinkPhases[0].0
            }
        }
    }

    /// The signed angle in (-π, π] that takes `from` to `to` the short way round.
    public static func shortestArc(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta <= -.pi { delta += 2 * .pi }
        return delta
    }
}

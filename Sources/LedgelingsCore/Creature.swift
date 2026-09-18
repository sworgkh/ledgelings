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
        /// Stopped to talk to another creature; walks on when told, or when this runs out.
        case chatting(remaining: Double)
        /// Hurrying to a spot on its own loop: home, when the house is out.
        case running(to: CGFloat)
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
    /// The way it was going before it turned to talk to someone.
    private var courseBeforeChat: CGFloat = 1
    /// Whether it was asleep when picked up, so it lands the same way.
    private var napsInHand = false
    /// A `leap` lands and waits instead of walking off.
    private var waitsAfterLanding = false
    /// Reached the spot it was running or leaping to, and has not moved since.
    public private(set) var hasArrived = false

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
        case .sleeping: "sleep"
        case .held: napsInHand ? "sleep" : "idle"
        case .chatting: animationTime < config.landDuration ? "land" : "idle"      // a squash on impact
        case .running: "walk"
        }
    }

    public var isRunning: Bool {
        if case .running = mode { return true }
        return false
    }

    public var isChatting: Bool {
        if case .chatting = mode { return true }
        return false
    }

    /// Asleep on an edge, or asleep in the user's hand.
    public var isSleeping: Bool {
        switch mode {
        case .sleeping: true
        case .held: napsInHand
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
        if !isJumping, !looksAsleep, !isHeld, !isRunning, let cursor, hypot(cursor.x - position.x, cursor.y - position.y) < config.fleeRadius {
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
            } else if remaining - dt <= 0, waitsAfterLanding {
                waitsAfterLanding = false
                enter(.idle(remaining: .infinity))
                hasArrived = true
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

        case .chatting(let remaining):
            turn(toward: restingRotation, dt: dt)
            if remaining - dt <= 0 { walkOn(using: &rng) } else { mode = .chatting(remaining: remaining - dt) }

        case .running(let target):
            let step = config.walkSpeed * 2.5 * dt
            let left = direction > 0 ? loop.wrap(target - spot.t) : loop.wrap(spot.t - target)
            if left <= step {
                spot.t = target
                enter(.idle(remaining: .infinity))
                hasArrived = true
            } else {
                spot.t = loop.wrap(spot.t + direction * step)
            }
            position = world.point(at: spot)
            turn(toward: restingRotation, dt: dt)
        }
    }

    // MARK: Going home

    /// Hurry to `target` on this loop, the short way round, waking up if needed.
    /// Not from the air or the user's hand; the caller waits for those.
    public mutating func run(to target: CGFloat) {
        guard !isJumping, !isHeld else { return }
        isNapping = false
        sleepsThroughLanding = false
        let ahead = loop.wrap(target - spot.t)
        direction = ahead <= loop.length / 2 ? 1 : -1
        enter(.running(to: loop.wrap(target)))
    }

    /// Jump straight to `spot` (any loop) and wait there.
    public mutating func leap(to spot: EdgeWorld.Spot) {
        guard !isJumping, !isHeld else { return }
        isNapping = false
        sleepsThroughLanding = false
        waitsAfterLanding = true
        let landing = world.loops[spot.loop]
        let target = world.point(at: spot)
        let distance = hypot(target.x - position.x, target.y - position.y)
        let duration = min(max(Double(distance / config.jumpSpeed), config.jumpDuration.lowerBound), config.jumpDuration.upperBound)
        let a = loop.inward(ofSegment: segment), b = landing.inward(ofSegment: landing.segment(at: spot.t))
        enter(.jumping(Jump(from: position, fromRotation: rotation, to: spot,
                            bulge: CGVector(dx: (a.dx + b.dx) / 2, dy: (a.dy + b.dy) / 2), duration: duration)))
    }

    /// Step out of the door at `spot`, walking `facing` (+1 or -1).
    public mutating func emerge(at spot: EdgeWorld.Spot, facing: CGFloat, using rng: inout some RandomNumberGenerator) {
        self.spot = EdgeWorld.Spot(loop: spot.loop, t: world.loops[spot.loop].wrap(spot.t))
        position = world.point(at: self.spot)
        rotation = restingRotation
        direction = facing < 0 ? -1 : 1
        isNapping = false
        sleepsThroughLanding = false
        waitsAfterLanding = false
        enter(.walking(remaining: .random(in: config.walkSpell, using: &rng)))
    }

    // MARK: Meeting someone

    /// Stop and face the other creature: `facing` is +1 when it is further along
    /// the loop, -1 when it is behind. Only an awake creature on the ground can.
    public mutating func meet(facing: CGFloat, for seconds: Double = 30) {
        guard !isJumping, !looksAsleep, !isHeld else { return }
        if !isChatting { courseBeforeChat = direction }
        direction = facing < 0 ? -1 : 1
        enter(.chatting(remaining: seconds))
    }

    /// The conversation is over: back on the old course.
    public mutating func walkOn(using rng: inout some RandomNumberGenerator) {
        guard isChatting else { return }
        direction = courseBeforeChat
        enter(.walking(remaining: .random(in: config.walkSpell, using: &rng)))
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

    /// A sleeper can always be picked up; an awake one only when the caller
    /// says so (a Shift-drag). Returns whether it was.
    @discardableResult
    public mutating func pickUp(evenAwake: Bool = false) -> Bool {
        guard !isJumping, !isHeld else { return false }
        if case .sleeping = mode { napsInHand = true } else if evenAwake { napsInHand = false } else { return false }
        enter(.held)
        return true
    }

    public mutating func drag(to point: CGPoint) {
        guard isHeld else { return }
        position = point
    }

    /// Let go: it drops to the nearest edge of any monitor, asleep if it was asleep.
    public mutating func drop() {
        guard isHeld else { return }
        let to = world.nearest(to: position)
        let target = world.point(at: to)
        let distance = hypot(target.x - position.x, target.y - position.y)
        sleepsThroughLanding = napsInHand
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
        hasArrived = false
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

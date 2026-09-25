import CoreGraphics
import Foundation

/// Air moving over the screen: a smooth, ever-changing field made of a few
/// crossing sine waves, so a paper plane drifts, swoops and wobbles instead of
/// flying a straight line. Pure and deterministic: the same point at the same
/// time always blows the same way. Every plane is thrown into its own weather
/// (`random`): other phases, another scale, another pace, another strength.
public struct Wind: Sendable, Equatable {
    /// Peak push, in points per second per second.
    public var strength: CGFloat
    /// Where each of the four waves starts, radians.
    public var phases: [CGFloat]
    /// Larger: broader gusts. Smaller: choppier air.
    public var scale: CGFloat
    /// How fast the weather changes.
    public var pace: CGFloat

    public init(strength: CGFloat = 260, phases: [CGFloat] = [0, 0, 0, 0], scale: CGFloat = 1, pace: CGFloat = 1) {
        self.strength = strength; self.phases = phases; self.scale = scale; self.pace = pace
    }

    public static func random(using rng: inout some RandomNumberGenerator) -> Wind {
        Wind(strength: .random(in: 180...480, using: &rng),
             phases: (0..<4).map { _ in .random(in: 0...(2 * .pi), using: &rng) },
             scale: .random(in: 0.6...1.6, using: &rng),
             pace: .random(in: 0.7...1.8, using: &rng))
    }

    public func at(_ p: CGPoint, time: Double) -> CGVector {
        let t = CGFloat(time) * pace, x = p.x / scale, y = p.y / scale
        let dx = sin(y / 260 + t * 0.35 + phases[0]) + 0.6 * sin((x + y) / 410 - t * 0.23 + phases[1])
        let dy = cos(x / 310 - t * 0.29 + phases[2]) + 0.6 * cos((x - y) / 470 + t * 0.19 + phases[3])
        return CGVector(dx: strength * dx / 1.6, dy: strength * dy / 1.6)
    }
}

/// One folded note in the air, from one creature to another.
///
/// It steers for the catcher's head the way a paper plane would if it could:
/// weakly at first, so its wind and its swirl carry it about, and harder the
/// longer it has been flying and the closer it gets, so it always arrives.
/// The swirl pushes it sideways, back and forth, into S-curves and now and
/// then a loop. Its speed breathes around its own cruise. Behind it, a dotted
/// trail of puffs that fade within a second.
public struct PaperPlane: Sendable {
    public struct Puff: Sendable {
        public var position: CGPoint
        public var age: Double
    }

    public var from: Int
    public var to: Int
    public private(set) var position: CGPoint
    /// Where it was a step ago, so a fast plane cannot skip past its catcher.
    public private(set) var previous: CGPoint
    public private(set) var velocity: CGVector
    public private(set) var age: Double = 0
    public private(set) var trail: [Puff] = []

    /// This plane's own weather.
    public var wind = Wind()
    /// The speed it would like to fly at, points per second, and how much it
    /// breathes around it (0.25 = up to a quarter faster and slower).
    public var cruise: CGFloat = 240
    public var surge: CGFloat = 0
    /// Sideways push, points per second per second, swinging from one side to
    /// the other `swirlRate` radians per second. Zero: no swirl.
    public var swirl: CGFloat = 0
    public var swirlRate: Double = 2
    public var phase: Double = 0
    public var speedRange: ClosedRange<CGFloat> = 90...760
    /// How far apart the trail's puffs are, and how long each lasts.
    public var puffSpacing: CGFloat = 9
    public var puffLife: Double = 1.1
    private var sinceLastPuff: CGFloat = 0

    /// Thrown from `start`, up into the screen along `inward`, roughly toward
    /// `target`, into still weather: the plain, predictable plane.
    public init(from: Int, to: Int, start: CGPoint, inward: CGVector, target: CGPoint) {
        self.from = from
        self.to = to
        position = start
        previous = start
        let d = Self.unit(CGVector(dx: target.x - start.x, dy: target.y - start.y))
        velocity = CGVector(dx: (d.dx * 0.5 + inward.dx) * 220, dy: (d.dy * 0.5 + inward.dy) * 220)
    }

    /// A real throw: its own wind, its own swirl, and a speed that is quick
    /// four times in five and a leisurely glide the fifth.
    public static func thrown(from: Int, to: Int, start: CGPoint, inward: CGVector, target: CGPoint,
                              using rng: inout some RandomNumberGenerator) -> PaperPlane {
        var plane = PaperPlane(from: from, to: to, start: start, inward: inward, target: target)
        plane.wind = .random(using: &rng)
        plane.cruise = Double.random(in: 0..<1, using: &rng) < 0.8
            ? .random(in: 380...580, using: &rng) : .random(in: 220...340, using: &rng)
        plane.surge = .random(in: 0.1...0.3, using: &rng)
        plane.swirl = .random(in: 250...1100, using: &rng)
        plane.swirlRate = .random(in: 1.2...3.4, using: &rng)
        plane.phase = .random(in: 0...(2 * .pi), using: &rng)
        let kick = plane.cruise / 240
        plane.velocity = CGVector(dx: plane.velocity.dx * kick, dy: plane.velocity.dy * kick)
        return plane
    }

    /// Which way the nose points, in radians.
    public var heading: Double { atan2(velocity.dy, velocity.dx) }

    public func distance(to point: CGPoint) -> CGFloat { hypot(point.x - position.x, point.y - position.y) }

    /// True when its last step passed within `reach` of `point`: a catch even
    /// if the plane went through the catcher between two frames.
    public func passed(within reach: CGFloat, of point: CGPoint) -> Bool {
        let seg = CGVector(dx: position.x - previous.x, dy: position.y - previous.y)
        let length2 = seg.dx * seg.dx + seg.dy * seg.dy
        let k = length2 > 0 ? min(1, max(0, ((point.x - previous.x) * seg.dx + (point.y - previous.y) * seg.dy) / length2)) : 0
        return hypot(point.x - (previous.x + seg.dx * k), point.y - (previous.y + seg.dy * k)) <= reach
    }

    /// How hard it steers: grows with time in the air and near the target.
    func grip(toward target: CGPoint) -> CGFloat {
        let far = distance(to: target)
        return min(8, 0.9 + CGFloat(age) * 0.45) * (far < 160 ? 2.2 : 1)
    }

    /// The speed it wants right now: its cruise, breathing.
    public var wantedSpeed: CGFloat { cruise * (1 + surge * CGFloat(sin(age * 1.7 + phase * 0.5))) }

    public mutating func fly(dt: Double, toward target: CGPoint, time: Double) {
        let step = CGFloat(dt)
        let toTarget = CGVector(dx: target.x - position.x, dy: target.y - position.y)
        let want = Self.unit(toTarget)
        let grip = grip(toward: target)
        let speedNow = wantedSpeed
        // Close in, wind and swirl matter less: the last swoop is the plane's own.
        let far = hypot(toTarget.dx, toTarget.dy)
        let calm = min(1, far / 220)
        let gust = wind.at(position, time: time)
        let side = Self.unit(CGVector(dx: -velocity.dy, dy: velocity.dx))
        let twist = swirl * CGFloat(sin(age * swirlRate + phase)) * calm
        velocity.dx += ((want.dx * speedNow - velocity.dx) * grip + (gust.dx + side.dx * twist) * calm) * step
        velocity.dy += ((want.dy * speedNow - velocity.dy) * grip + (gust.dy + side.dy * twist) * calm) * step
        let speed = hypot(velocity.dx, velocity.dy)
        let clamped = min(max(speed, speedRange.lowerBound), speedRange.upperBound)
        if speed > 0, clamped != speed {
            velocity.dx *= clamped / speed
            velocity.dy *= clamped / speed
        }
        previous = position
        position.x += velocity.dx * step
        position.y += velocity.dy * step
        age += dt

        for i in trail.indices { trail[i].age += dt }
        trail.removeAll { $0.age >= puffLife }
        sinceLastPuff += clamped * step
        while sinceLastPuff >= puffSpacing {
            // A fast plane still leaves evenly spaced puffs, laid back along its step.
            sinceLastPuff -= puffSpacing
            let back = sinceLastPuff / max(clamped * step, 1e-6)
            trail.append(Puff(position: CGPoint(x: position.x - velocity.dx * step * back,
                                                y: position.y - velocity.dy * step * back), age: 0))
        }
    }

    /// The trail keeps fading after the plane is gone.
    public mutating func fadeTrail(dt: Double) {
        for i in trail.indices { trail[i].age += dt }
        trail.removeAll { $0.age >= puffLife }
    }

    static func unit(_ v: CGVector) -> CGVector {
        let length = hypot(v.dx, v.dy)
        return length > 1e-6 ? CGVector(dx: v.dx / length, dy: v.dy / length) : CGVector(dx: 1, dy: 0)
    }
}

/// When the next paper plane is due: every `quietFor` seconds, counted from
/// the last plane that went up.
public struct Post: Sendable {
    /// Seconds from one plane to the next. Zero or less: never.
    public var quietFor: Double
    public private(set) var lastStir: Double = 0

    public init(quietFor: Double) { self.quietFor = quietFor }

    /// A plane just went up: the next one is a whole interval away.
    public mutating func stir(at time: Double) { lastStir = time }

    public func isDue(at time: Double) -> Bool { quietFor > 0 && time - lastStir >= quietFor }

    /// Nobody could send one just now: try again in `seconds`, not a whole quiet spell later.
    public mutating func retry(at time: Double, in seconds: Double) {
        lastStir = min(time, time - quietFor + seconds)
    }

    /// Who throws and who catches, from the creatures free to do either
    /// (`positions` by index). The sender is anyone; the catcher is one of the
    /// farther half from it, so the plane has some sky to cross.
    public static func pickPair(_ free: [Int: CGPoint], using rng: inout some RandomNumberGenerator) -> (from: Int, to: Int)? {
        guard free.count >= 2, let sender = free.keys.sorted().randomElement(using: &rng), let at = free[sender] else { return nil }
        let others = free.filter { $0.key != sender }
            .sorted { hypot($0.value.x - at.x, $0.value.y - at.y) > hypot($1.value.x - at.x, $1.value.y - at.y) }
        let far = others.prefix(max(1, (others.count + 1) / 2))
        guard let catcher = far.randomElement(using: &rng)?.key else { return nil }
        return (sender, catcher)
    }
}

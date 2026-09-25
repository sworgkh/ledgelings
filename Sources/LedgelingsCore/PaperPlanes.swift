import CoreGraphics
import Foundation

/// Air moving over the screen: a slow, smooth, ever-changing field made of a
/// few crossing sine waves, so a paper plane drifts, swoops and wobbles
/// instead of flying a straight line. Pure and deterministic: the same point
/// at the same time always blows the same way.
public struct Wind: Sendable {
    /// Peak push, in points per second per second.
    public var strength: CGFloat

    public init(strength: CGFloat = 260) { self.strength = strength }

    public func at(_ p: CGPoint, time: Double) -> CGVector {
        let t = CGFloat(time)
        let dx = sin(p.y / 260 + t * 0.35) + 0.6 * sin((p.x + p.y) / 410 - t * 0.23)
        let dy = cos(p.x / 310 - t * 0.29) + 0.6 * cos((p.x - p.y) / 470 + t * 0.19)
        return CGVector(dx: strength * dx / 1.6, dy: strength * dy / 1.6)
    }
}

/// One folded note in the air, from one creature to another.
///
/// It steers for the catcher's head the way a paper plane would if it could:
/// weakly at first, so the wind carries it about, and harder the longer it has
/// been flying and the closer it gets, so it always arrives. Behind it, a
/// dotted trail of puffs that fade within a second.
public struct PaperPlane: Sendable {
    public struct Puff: Sendable {
        public var position: CGPoint
        public var age: Double
    }

    public var from: Int
    public var to: Int
    public private(set) var position: CGPoint
    public private(set) var velocity: CGVector
    public private(set) var age: Double = 0
    public private(set) var trail: [Puff] = []

    /// The speed it would like to fly at, points per second.
    public var cruise: CGFloat = 240
    public var speedRange: ClosedRange<CGFloat> = 90...460
    /// How far apart the trail's puffs are, and how long each lasts.
    public var puffSpacing: CGFloat = 9
    public var puffLife: Double = 1.1
    private var sinceLastPuff: CGFloat = 0

    /// Thrown from `start`, up into the screen along `inward`, roughly toward `target`.
    public init(from: Int, to: Int, start: CGPoint, inward: CGVector, target: CGPoint) {
        self.from = from
        self.to = to
        position = start
        let d = Self.unit(CGVector(dx: target.x - start.x, dy: target.y - start.y))
        velocity = CGVector(dx: (d.dx * 0.5 + inward.dx) * 220, dy: (d.dy * 0.5 + inward.dy) * 220)
    }

    /// Which way the nose points, in radians.
    public var heading: Double { atan2(velocity.dy, velocity.dx) }

    public func distance(to point: CGPoint) -> CGFloat { hypot(point.x - position.x, point.y - position.y) }

    /// How hard it steers: grows with time in the air and near the target.
    func grip(toward target: CGPoint) -> CGFloat {
        let far = distance(to: target)
        return min(8, 0.9 + CGFloat(age) * 0.45) * (far < 160 ? 2.2 : 1)
    }

    public mutating func fly(dt: Double, toward target: CGPoint, wind: Wind, time: Double) {
        let step = CGFloat(dt)
        let toTarget = CGVector(dx: target.x - position.x, dy: target.y - position.y)
        let want = Self.unit(toTarget)
        let grip = grip(toward: target)
        // Close in, the wind matters less: the last swoop is the plane's own.
        let far = hypot(toTarget.dx, toTarget.dy)
        let gust = wind.at(position, time: time)
        let calm = min(1, far / 220)
        velocity.dx += ((want.dx * cruise - velocity.dx) * grip + gust.dx * calm) * step
        velocity.dy += ((want.dy * cruise - velocity.dy) * grip + gust.dy * calm) * step
        let speed = hypot(velocity.dx, velocity.dy)
        let clamped = min(max(speed, speedRange.lowerBound), speedRange.upperBound)
        if speed > 0, clamped != speed {
            velocity.dx *= clamped / speed
            velocity.dy *= clamped / speed
        }
        position.x += velocity.dx * step
        position.y += velocity.dy * step
        age += dt

        for i in trail.indices { trail[i].age += dt }
        trail.removeAll { $0.age >= puffLife }
        sinceLastPuff += clamped * step
        if sinceLastPuff >= puffSpacing {
            sinceLastPuff = 0
            trail.append(Puff(position: position, age: 0))
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

/// When the colony has been quiet long enough for someone to write a letter.
/// A bump stirs it; so does a plane.
public struct Post: Sendable {
    /// Seconds without a bump before a plane goes up. Zero or less: never.
    public var quietFor: Double
    public private(set) var lastStir: Double = 0

    public init(quietFor: Double) { self.quietFor = quietFor }

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

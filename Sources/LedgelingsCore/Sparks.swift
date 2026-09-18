import CoreGraphics
import Foundation

/// A handful of pixel stars thrown up when two creatures bump. They fly into
/// the screen, fall back toward the edge, and fade within a second.
public struct Sparks: Sendable {
    public struct Spark: Sendable {
        public var position: CGPoint
        public var velocity: CGVector
        /// Which way "down" is for this star: back toward its edge.
        public var gravity: CGVector
        public var age: Double = 0
        public var life: Double
        /// 0, 1, 2…: lets the renderer vary the colour without the logic caring.
        public var tint: Int

        public var opacity: Double { max(0, 1 - age / life) }
    }

    public var life: Double
    public var speed: ClosedRange<CGFloat>
    public var pull: CGFloat
    public private(set) var alive: [Spark] = []

    public init(life: Double = 0.7, speed: ClosedRange<CGFloat> = 70...150, pull: CGFloat = 300) {
        self.life = life
        self.speed = speed
        self.pull = pull
    }

    /// Fan `count` stars out around `inward`, within 60° either side of it.
    public mutating func burst(at point: CGPoint, inward: CGVector, count: Int = 8,
                               using rng: inout some RandomNumberGenerator) {
        let base = atan2(inward.dy, inward.dx)
        for k in 0..<count {
            let angle = base + CGFloat.random(in: -.pi / 3 ... .pi / 3, using: &rng)
            let v = CGFloat.random(in: speed, using: &rng)
            alive.append(Spark(position: point, velocity: CGVector(dx: cos(angle) * v, dy: sin(angle) * v),
                               gravity: CGVector(dx: -inward.dx * pull, dy: -inward.dy * pull),
                               life: life * Double.random(in: 0.7...1.1, using: &rng), tint: k))
        }
    }

    public mutating func update(dt: Double) {
        for i in alive.indices {
            alive[i].velocity.dx += alive[i].gravity.dx * dt
            alive[i].velocity.dy += alive[i].gravity.dy * dt
            alive[i].position.x += alive[i].velocity.dx * dt
            alive[i].position.y += alive[i].velocity.dy * dt
            alive[i].age += dt
        }
        alive.removeAll { $0.age >= $0.life }
    }
}

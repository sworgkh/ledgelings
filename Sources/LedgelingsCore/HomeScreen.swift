import CoreGraphics
import Foundation

/// Which monitors the colony lives on (`homeScreen`): all of them, or one.
///
/// A monitor is known by an id that stays the same across relaunches and
/// re-plugging (the Mac's display UUID, Windows' device name), and shown by its
/// name. While the chosen monitor is unplugged the colony lives on every monitor
/// left, and the choice is kept: plugged back in, the creatures go back to it.
public enum HomeScreen {
    /// The setting's value for "every monitor".
    public static let all = ""

    public struct Monitor: Equatable, Sendable {
        public var id: String
        public var name: String
        public var frame: CGRect
        public init(id: String, name: String, frame: CGRect) {
            self.id = id; self.name = name; self.frame = frame
        }
    }

    /// The monitors they live on: the chosen one while it is attached, else every one.
    ///
    /// Every one, not the main one, when it is away: the main monitor is often the
    /// laptop's own, shut in a dock; and every monitor is what they did before
    /// there was a choice, so nobody lands somewhere new.
    public static func home(_ chosen: String, among monitors: [Monitor]) -> [Monitor] {
        guard chosen != all, let one = monitors.first(where: { $0.id == chosen }) else { return monitors }
        return [one]
    }

    /// A monitor is chosen but not attached: they live everywhere until it is back.
    public static func isAway(_ chosen: String, among monitors: [Monitor]) -> Bool {
        chosen != all && !monitors.contains { $0.id == chosen }
    }

    /// Whether `point` counts as on the home monitors: on one, or within `slack`
    /// of one (a body hanging over the edge after a resolution change still counts).
    public static func isHome(_ point: CGPoint, in home: [CGRect], slack: CGFloat) -> Bool {
        home.contains { $0.insetBy(dx: -slack, dy: -slack).contains(point) }
    }

    // MARK: Moving over

    /// A creature leaving a monitor the colony no longer lives on: one big spring
    /// straight up and out through the top of its screen, turning as it goes,
    /// before it comes down on the new one by parachute (`Plays.Chute`).
    public struct Hop: Equatable, Sendable {
        /// Seconds it crouches before it springs.
        public static let crouch = 0.25
        /// It turns once round on the way up, the way it faces.
        public static let spin = 2 * Double.pi

        public let from: CGPoint
        public let fromRotation: Double
        /// Where it is out of sight: past the top of its screen.
        public let gone: CGFloat
        public let speed: CGFloat
        public let way: CGFloat
        public private(set) var position: CGPoint
        public private(set) var rotation: Double
        public private(set) var clock = 0.0
        public private(set) var isGone = false

        /// `gone`: a y above the screen's top by more than a body; `way`: +1 right, −1 left.
        public init(from: CGPoint, rotation: Double, gone: CGFloat, way: CGFloat) {
            self.from = from
            fromRotation = rotation
            self.gone = max(gone, from.y + 1)
            self.way = way < 0 ? -1 : 1
            // Fast enough to be past the top while still going up.
            speed = (2 * Plays.gravity * (self.gone - from.y)).squareRoot() * 1.15
            position = from
            self.rotation = rotation
        }

        /// How it looks: crouched, then in the air.
        public var pose: String { clock < Self.crouch ? "land" : "jump" }

        /// Seconds from the spring to out of sight.
        public var flightTime: Double {
            let g = Double(Plays.gravity), v = Double(speed), h = Double(gone - from.y)
            return (v - (v * v - 2 * g * h).squareRoot()) / g
        }

        public mutating func update(dt: Double) {
            guard !isGone else { return }
            clock += dt
            let t = max(0, clock - Self.crouch)
            guard t > 0 else { return }
            position.y = from.y + speed * CGFloat(t) - Plays.gravity * CGFloat(t * t) / 2
            position.x = from.x + way * 40 * CGFloat(t)
            let share = min(1, t / max(flightTime, 0.01))
            rotation = fromRotation * (1 - share) - Double(way) * Self.spin * share
            if position.y >= gone { isGone = true }
        }
    }

    /// Seconds between one creature and the next coming down on the new monitor,
    /// so they arrive one after another, not in a heap.
    public static let arrivalGap = 0.45
}

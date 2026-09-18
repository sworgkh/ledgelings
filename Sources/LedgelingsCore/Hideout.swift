import Foundation

/// The little house the creatures hide in when asked to go away for a while.
///
/// away → appearing → gathering → shrinking → hidden → growing → releasing → vanishing → away
///
/// The colony drives it: it calls `entered` as each creature reaches the door,
/// acts on the events `update` returns, and draws the house at `scale`.
public struct Hideout: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case away, appearing, gathering, shrinking, hidden, growing, releasing, vanishing
    }

    public enum Event: Equatable, Sendable {
        /// The gathering took too long: put these creatures inside right now.
        case forceInside([Int])
        /// This creature walks out of the door.
        case letOut(Int)
    }

    public var appearTime: Double = 0.4
    public var shrinkTime: Double = 0.5
    /// Longest the house waits at the door before pulling the stragglers in.
    public var gatherCap: Double = 25
    public var releaseEvery: Double = 0.6

    public private(set) var phase: Phase = .away
    public private(set) var count = 0
    public private(set) var inside: Set<Int> = []
    private var phaseStarted: Double = 0
    private var until: Double = 0
    private var lastRelease: Double = 0

    public init() {}

    public var isActive: Bool { phase != .away }
    public func isInside(_ creature: Int) -> Bool { inside.contains(creature) }
    public func remaining(at time: Double) -> Double { max(0, until - time) }

    /// Start hiding `count` creatures for `seconds`. Ignored while already busy.
    public mutating func hide(count: Int, at time: Double, for seconds: Double) {
        guard !isActive else { return }
        self.count = count
        inside = []
        until = time + seconds
        enter(.appearing, at: time)
    }

    /// One creature reached the door.
    public mutating func entered(_ creature: Int, at time: Double) {
        guard phase == .gathering else { return }
        inside.insert(creature)
        if inside.count >= count { enter(.shrinking, at: time) }
    }

    /// "Bring them back now": open up wherever we are.
    public mutating func recall(at time: Double) {
        until = time
        switch phase {
        case .hidden: enter(.growing, at: time)
        case .shrinking: enter(.growing, at: time - appearTime * (1 - scale(at: time)))
        case .appearing, .gathering: enter(.releasing, at: time)
        default: break
        }
    }

    /// 0 = not there, 1 = full size.
    public func scale(at time: Double) -> Double {
        let sincePhase = time - phaseStarted
        switch phase {
        case .away, .hidden: return 0
        case .appearing, .growing: return min(1, max(0, sincePhase / appearTime))
        case .gathering, .releasing: return 1
        case .shrinking, .vanishing: return min(1, max(0, 1 - sincePhase / shrinkTime))
        }
    }

    public mutating func update(at time: Double) -> [Event] {
        let sincePhase = time - phaseStarted
        switch phase {
        case .away:
            return []
        case .appearing:
            if sincePhase >= appearTime { enter(.gathering, at: phaseStarted + appearTime) }
            return []
        case .gathering:
            if inside.count >= count { enter(.shrinking, at: time); return [] }
            guard sincePhase >= gatherCap else { return [] }
            return [.forceInside((0..<count).filter { !inside.contains($0) })]
        case .shrinking:
            if sincePhase >= shrinkTime { enter(.hidden, at: time) }
            return []
        case .hidden:
            if time >= until { enter(.growing, at: time) }
            return []
        case .growing:
            if sincePhase >= appearTime { enter(.releasing, at: time) }
            return []
        case .releasing:
            guard let next = inside.min() else { enter(.vanishing, at: time); return [] }
            guard time - lastRelease >= releaseEvery else { return [] }
            inside.remove(next)
            lastRelease = time
            return [.letOut(next)]
        case .vanishing:
            if sincePhase >= shrinkTime { enter(.away, at: time) }
            return []
        }
    }

    private mutating func enter(_ next: Phase, at time: Double) {
        phase = next
        phaseStarted = time
        if next == .releasing { lastRelease = time - releaseEvery }     // the first one steps out at once
    }
}

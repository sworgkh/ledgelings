import CoreGraphics

/// Notices when two creatures walk into each other on the same edge.
///
/// A "bump" fires once when a pair comes together, not every frame they stay
/// together, and the same pair cannot bump again until `cooldown` seconds have
/// passed. Every `giftEvery`-th bump of a pair is a gift.
public struct Meetings: Sendable {
    /// One creature, as far as meeting is concerned.
    public struct Party: Sendable {
        public var loop: Int
        public var segment: Int
        public var position: CGPoint
        /// Half the body width, so bumping means the two squares nearly touch.
        public var halfSize: CGFloat
        /// Awake, on the edge, not in the user's hand.
        public var canTalk: Bool

        public init(loop: Int, segment: Int, position: CGPoint, halfSize: CGFloat, canTalk: Bool) {
            self.loop = loop; self.segment = segment; self.position = position
            self.halfSize = halfSize; self.canTalk = canTalk
        }
    }

    /// Two creatures just came together. `a < b`. `count` is how many times
    /// this pair has bumped since its last gift, this one included.
    public struct Bump: Equatable, Sendable {
        public var a: Int
        public var b: Int
        public var count: Int
        public var gift: Bool

        public init(a: Int, b: Int, count: Int, gift: Bool) {
            self.a = a; self.b = b; self.count = count; self.gift = gift
        }
    }

    private struct Pair: Hashable { let a: Int; let b: Int }

    /// How close the two bodies must be, beyond touching, to count.
    public var gap: CGFloat
    public var cooldown: Double
    public var giftEvery: Int

    private var touching: Set<Pair> = []
    private var lastBump: [Pair: Double] = [:]
    private var counts: [Pair: Int] = [:]

    public init(gap: CGFloat = 12, cooldown: Double = 60, giftEvery: Int = 3) {
        self.gap = gap; self.cooldown = cooldown; self.giftEvery = giftEvery
    }

    /// Feed it everyone, every frame. Returns the pairs that came together this frame.
    public mutating func update(_ parties: [Party], at time: Double) -> [Bump] {
        var bumps: [Bump] = []
        var nowTouching: Set<Pair> = []
        for a in parties.indices {
            for b in parties.indices where b > a {
                let p = parties[a], q = parties[b]
                guard p.canTalk, q.canTalk, p.loop == q.loop, p.segment == q.segment else { continue }
                let distance = hypot(q.position.x - p.position.x, q.position.y - p.position.y)
                guard distance <= p.halfSize + q.halfSize + gap else { continue }
                let pair = Pair(a: a, b: b)
                nowTouching.insert(pair)
                guard !touching.contains(pair) else { continue }
                if let last = lastBump[pair], time - last < cooldown { continue }
                lastBump[pair] = time
                let count = (counts[pair] ?? 0) + 1
                let gift = giftEvery > 0 && count >= giftEvery
                counts[pair] = gift ? 0 : count
                bumps.append(Bump(a: a, b: b, count: count, gift: gift))
            }
        }
        touching = nowTouching
        return bumps
    }
}

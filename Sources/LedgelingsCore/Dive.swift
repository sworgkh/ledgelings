import CoreGraphics
import Foundation

/// Scuba diving (§7.19): started by hand only, never on its own. Water rises
/// from the bottom edge to cover a share of the screen; a few creatures gear up
/// (a mask and a tank), jump in with a splash and swim among fish, a jellyfish,
/// a crab, a turtle and an octopus, coming up for air now and then; when the
/// time is up the water drains and they climb out dripping. Stop activity
/// clears it at once.
///
/// The sea life is not characters: it says nothing and has no persona. It
/// reacts to the divers (fish scatter, the crab raises its claws, the octopus
/// inks and jets off) and the divers react to it (`Event`), which is what they
/// talk about and what lands in their pair's memory.
///
/// Pure: global points, y up, stepped by `update(dt:using:)`.
public struct Dive: Sendable {

    public enum Phase: Equatable, Sendable {
        /// The water coming up; the divers gear up meanwhile.
        case rising
        case on
        /// Time is up: the water going down, the divers going down with it.
        case draining
        /// Dry again: the colony lets the divers go.
        case over
    }

    /// The kinds of sea life. Their sheet frames are named after these.
    public enum Life: String, CaseIterable, Sendable {
        case fishA = "fish-a", fishB = "fish-b", fishC = "fish-c", jelly, crab, turtle, octopus

        public var isFish: Bool { self == .fishA || self == .fishB || self == .fishC }

        /// What a diver calls it when it points: "a turtle".
        public var spoken: String {
            switch self {
            case .fishA, .fishB, .fishC: tr("a school of fish")
            case .jelly: tr("a jellyfish")
            case .crab: tr("a crab")
            case .turtle: tr("a turtle")
            case .octopus: tr("an octopus")
            }
        }

        /// Half its body, in sheet pixels: how near counts as touching.
        var halfSize: CGSize {
            switch self {
            case .fishA, .fishB, .fishC: CGSize(width: 6, height: 4)
            case .jelly: CGSize(width: 6, height: 8)
            case .crab: CGSize(width: 8, height: 5)
            case .turtle: CGSize(width: 12, height: 7)
            case .octopus: CGSize(width: 9, height: 9)
            }
        }
    }

    /// One animal.
    public struct Critter: Sendable {
        public var kind: Life
        /// Which pool (monitor) it lives in.
        public var pool: Int
        public var position: CGPoint
        public var velocity: CGVector
        /// The fish swim in schools; -1 for everyone else.
        public var school: Int
        public var facingRight: Bool
        /// Seconds into its swimming, for its two frames.
        public var time: Double
        /// Frightened for this many more seconds: fleeing, claws up, inking.
        public var scared: Double = 0
        /// Where it wanders about: the crab's and the octopus's patch of floor.
        public var home: CGFloat
    }

    /// An air bubble rising to the surface.
    public struct Bubble: Sendable {
        public var position: CGPoint
        /// 0, 1 or 2: small, middle, big.
        public var size: Int
        public var rise: CGFloat
        public var wobble: Double
    }

    /// A strand of seaweed on the floor.
    public struct Weed: Sendable {
        public var pool: Int
        public var x: CGFloat
        /// Its height, in sheet pixels.
        public var height: Int
        public var phase: Double
    }

    public struct Diver: Sendable {
        public enum State: Equatable, Sendable {
            /// Putting the gear on, standing where it was.
            case gearing(until: Double)
            /// In the air over the water, `from` to `to`, starting at `start`.
            case leaping(from: CGPoint, to: CGPoint, start: Double, duration: Double)
            case swimming
            /// At the surface, getting its breath, until then.
            case breathing(until: Double)
            /// Going down with the draining water.
            case settling
        }
        /// The creature's index in the colony.
        public var index: Int
        public var pool: Int
        public var state: State
        public var position: CGPoint
        public var velocity: CGVector = .zero
        public var target: CGPoint
        public var facingRight: Bool
        /// When it next needs air.
        public var nextAir: Double
        public var nextBubble: Double
        /// When it last saw each kind, so it points once a while, not every frame.
        public var saw: [Life: Double] = [:]
        public var lastScatter = -100.0
        /// How big its body is, in points (half), to keep it inside the water.
        public var half: CGFloat

        public var isUnder: Bool { state == .swimming || state == .settling }
    }

    /// What happened this step, for lines, sounds and memory.
    public enum Event: Equatable, Sendable {
        case splash(CGPoint)
        case sees(diver: Int, Life)
        /// The fish scattered round it.
        case scattered(diver: Int)
        /// The octopus gave it a fright.
        case startled(diver: Int)
        case surfaced(diver: Int)
        /// The water has filled; the dive is on.
        case filled
        case drained
    }

    /// Seconds the water takes to come up, and to go down.
    public static let riseSeconds = 2.5
    public static let drainSeconds = 2.5
    /// Seconds between one diver jumping in and the next.
    public static let jumpGap = 0.45
    public static let leapSeconds = 0.8
    /// A diver needs air every so often (seconds), and stays up this long.
    public static let airEvery = 16.0...32.0
    public static let breathSeconds = 1.6
    /// How near a diver comes to see something, or frighten it, in points.
    public static let seeRadius: CGFloat = 110
    public static let scareRadius: CGFloat = 70
    /// A diver points at the same kind again only after this many seconds.
    public static let seeAgain = 25.0
    public static let swimSpeed: CGFloat = 60
    /// Fish per school at most.
    public static let schoolSize = 4

    /// Each monitor's frame the water covers; the first is where most divers are.
    public let pools: [CGRect]
    /// The share of a pool's height the water covers when full.
    public let share: Double
    /// Seconds the dive lasts once the water is up.
    public let length: Double
    /// Screen points per sheet pixel, for the sea life's size.
    public let scale: CGFloat
    public private(set) var phase: Phase = .rising
    /// 0 dry … 1 full.
    public private(set) var level: Double = 0
    public private(set) var time: Double = 0
    /// When the water was full, on the dive's clock.
    public private(set) var filledAt: Double?
    public var critters: [Critter] = []
    public var bubbles: [Bubble] = []
    public var weeds: [Weed] = []
    public var divers: [Diver] = []
    /// Where each school is heading.
    var schoolGoals: [Int: CGPoint] = [:]

    /// `divers`: each creature's index, where it stands, and half its body in points.
    public init(pools: [CGRect], share: Double, seconds: Double, scale: CGFloat,
                divers: [(index: Int, at: CGPoint, half: CGFloat)], seaLife fish: Int,
                using rng: inout some RandomNumberGenerator) {
        self.pools = pools.isEmpty ? [CGRect(x: 0, y: 0, width: 1000, height: 600)] : pools
        self.share = share
        length = seconds
        self.scale = scale
        let first = self.pools[0]
        let fullTop = first.minY + first.height * share
        for (k, d) in divers.enumerated() {
            let pool = self.pools.firstIndex { $0.insetBy(dx: -1, dy: -1).contains(d.at) } ?? 0
            let target = CGPoint(x: d.at.x, y: (self.pools[pool].minY + fullTop) / 2)
            self.divers.append(Diver(index: d.index, pool: pool, state: .gearing(until: Self.riseSeconds + Double(k) * Self.jumpGap),
                                     position: d.at, target: target, facingRight: Bool.random(using: &rng),
                                     nextAir: Self.riseSeconds + Double.random(in: Self.airEvery, using: &rng),
                                     nextBubble: 0, half: d.half))
        }
        populate(fish: fish, using: &rng)
    }

    // MARK: Where the water is

    /// The surface's height in pool `k`, now.
    public func surface(_ k: Int) -> CGFloat {
        let p = pools[k]
        return p.minY + p.height * CGFloat(share * level)
    }

    /// The surface when the water is full.
    public func fullSurface(_ k: Int) -> CGFloat { pools[k].minY + pools[k].height * CGFloat(share) }

    /// The water in pool `k` now, as a rectangle.
    public func water(_ k: Int) -> CGRect {
        let p = pools[k]
        return CGRect(x: p.minX, y: p.minY, width: p.width, height: surface(k) - p.minY)
    }

    public var isOver: Bool { phase == .over }

    // MARK: Filling the sea

    private mutating func populate(fish: Int, using rng: inout some RandomNumberGenerator) {
        let widths = pools.map(\.width), total = max(1, widths.reduce(0, +))
        func randomPool() -> Int {
            var pick = CGFloat.random(in: 0..<total, using: &rng)
            for (k, w) in widths.enumerated() { if pick < w { return k }; pick -= w }
            return 0
        }
        func point(in k: Int, low: CGFloat = 0.15, high: CGFloat = 0.85) -> CGPoint {
            let p = pools[k], top = fullSurface(k)
            return CGPoint(x: .random(in: p.minX + 30...p.maxX - 30, using: &rng),
                           y: p.minY + (top - p.minY) * .random(in: low...high, using: &rng))
        }
        let kinds: [Life] = [.fishA, .fishB, .fishC]
        var left = max(0, fish), school = 0
        while left > 0 {
            let n = min(left, Int.random(in: 2...Self.schoolSize, using: &rng))
            let k = randomPool(), centre = point(in: k), kind = kinds[school % kinds.count]
            let right = Bool.random(using: &rng)
            for _ in 0..<n {
                let at = CGPoint(x: centre.x + .random(in: -24...24, using: &rng), y: centre.y + .random(in: -14...14, using: &rng))
                critters.append(Critter(kind: kind, pool: k, position: at, velocity: CGVector(dx: right ? 30 : -30, dy: 0), school: school,
                                        facingRight: right, time: .random(in: 0...1, using: &rng), home: at.x))
            }
            schoolGoals[school] = point(in: k)
            school += 1
            left -= n
        }
        // One each of the others in the first pool, the crab and the octopus on its floor.
        let p = pools[0]
        func floorY(_ kind: Life) -> CGFloat { p.minY + kind.halfSize.height * scale }
        let jelly = point(in: 0, low: 0.4, high: 0.8)
        critters.append(Critter(kind: .jelly, pool: 0, position: jelly, velocity: CGVector(dx: 6, dy: 0), school: -1,
                                facingRight: true, time: 0, home: jelly.x))
        let crabX = CGFloat.random(in: p.minX + p.width * 0.1...p.minX + p.width * 0.4, using: &rng)
        critters.append(Critter(kind: .crab, pool: 0, position: CGPoint(x: crabX, y: floorY(.crab)), velocity: CGVector(dx: 14, dy: 0),
                                school: -1, facingRight: true, time: 0, home: crabX))
        let turtle = point(in: 0, low: 0.35, high: 0.7)
        critters.append(Critter(kind: .turtle, pool: 0, position: turtle, velocity: CGVector(dx: 18, dy: 0), school: -1,
                                facingRight: true, time: 0, home: turtle.x))
        let octoX = CGFloat.random(in: p.minX + p.width * 0.6...p.minX + p.width * 0.9, using: &rng)
        critters.append(Critter(kind: .octopus, pool: 0, position: CGPoint(x: octoX, y: floorY(.octopus)), velocity: .zero,
                                school: -1, facingRight: false, time: 0, home: octoX))
        // Seaweed along every floor, every 60-140 points.
        for (k, pool) in pools.enumerated() {
            var x = pool.minX + .random(in: 20...80, using: &rng)
            while x < pool.maxX - 10 {
                weeds.append(Weed(pool: k, x: x, height: .random(in: 10...24, using: &rng), phase: .random(in: 0...6, using: &rng)))
                x += .random(in: 60...140, using: &rng)
            }
        }
    }

    // MARK: The step

    /// Time is up early: start draining now (the Actions sheet's "Out of the water").
    public mutating func drain() {
        guard phase == .rising || phase == .on else { return }
        phase = .draining
        for k in divers.indices where divers[k].isUnder || isBreathing(k) { divers[k].state = .settling }
    }

    private func isBreathing(_ k: Int) -> Bool {
        if case .breathing = divers[k].state { return true }
        return false
    }

    public mutating func update(dt: Double, using rng: inout some RandomNumberGenerator) -> [Event] {
        var events: [Event] = []
        time += dt
        switch phase {
        case .rising:
            level = min(1, level + dt / Self.riseSeconds)
            if level >= 1 { phase = .on; filledAt = time; events.append(.filled) }
        case .on:
            if let at = filledAt, time - at >= length { drain() }
        case .draining:
            level = max(0, level - dt / Self.drainSeconds)
            if level <= 0 { phase = .over; events.append(.drained) }
        case .over:
            return events
        }
        updateDivers(dt: dt, events: &events, using: &rng)
        updateCritters(dt: dt, events: &events, using: &rng)
        updateBubbles(dt: dt)
        return events
    }

    private mutating func updateDivers(dt: Double, events: inout [Event], using rng: inout some RandomNumberGenerator) {
        for k in divers.indices {
            var d = divers[k]
            let pool = pools[d.pool], top = surface(d.pool)
            switch d.state {
            case .gearing(let until):
                // Jumps once the water is up, one after another.
                if phase == .on, time >= until {
                    let entry = CGPoint(x: min(max(d.position.x + (d.facingRight ? 40 : -40), pool.minX + 40), pool.maxX - 40), y: top)
                    d.state = .leaping(from: d.position, to: entry, start: time, duration: Self.leapSeconds)
                } else if phase == .draining || phase == .over {
                    d.state = .settling
                }
            case .leaping(let from, let to, let start, let duration):
                let u = min(1, (time - start) / duration)
                let peak = max(from.y, to.y) + 70
                // A parabola through from, peak and to.
                let x = from.x + (to.x - from.x) * CGFloat(u)
                let a = 1 - u
                let y = CGFloat(a * a) * from.y + CGFloat(2 * a * u) * peak + CGFloat(u * u) * to.y
                d.facingRight = to.x >= from.x
                d.position = CGPoint(x: x, y: y)
                if u >= 1 {
                    events.append(.splash(CGPoint(x: to.x, y: top)))
                    d.state = phase == .draining ? .settling : .swimming
                    d.velocity = CGVector(dx: d.facingRight ? 20 : -20, dy: -90)
                    d.target = randomTarget(d.pool, half: d.half, using: &rng)
                }
            case .swimming:
                if time >= d.nextAir {
                    d.target = CGPoint(x: d.position.x, y: top - d.half * 0.5)
                }
                let breathingUp = time >= d.nextAir
                steer(&d, dt: dt, speed: breathingUp ? Self.swimSpeed * 1.3 : Self.swimSpeed)
                if breathingUp, d.position.y >= top - d.half * 0.7 {
                    d.state = .breathing(until: time + Self.breathSeconds)
                    d.velocity = .zero
                    events.append(.surfaced(diver: d.index))
                } else if !breathingUp, hypot(d.target.x - d.position.x, d.target.y - d.position.y) < 14 {
                    d.target = randomTarget(d.pool, half: d.half, using: &rng)
                }
                if time >= d.nextBubble {
                    d.nextBubble = time + .random(in: 0.5...1.1, using: &rng)
                    bubbles.append(Bubble(position: CGPoint(x: d.position.x + (d.facingRight ? d.half * 0.6 : -d.half * 0.6), y: d.position.y + d.half * 0.5),
                                          size: Int.random(in: 0...1, using: &rng), rise: .random(in: 40...60, using: &rng), wobble: .random(in: 0...6, using: &rng)))
                }
            case .breathing(let until):
                // Bobbing at the surface.
                d.position.y = top - d.half * 0.5 + CGFloat(sin(time * 5)) * 1.5
                if time >= until {
                    d.state = .swimming
                    d.nextAir = time + .random(in: Self.airEvery, using: &rng)
                    d.target = randomTarget(d.pool, half: d.half, using: &rng)
                }
            case .settling:
                // Down with the water, and to the floor.
                let floor = pool.minY + d.half
                d.velocity = .zero
                d.position.y = max(floor, min(d.position.y - CGFloat(dt) * 40, top - d.half * 0.5))
            }
            // Inside the water, whatever it does under it.
            if d.isUnder || d.state == .swimming {
                d.position.x = min(max(d.position.x, pool.minX + d.half), pool.maxX - d.half)
                d.position.y = max(d.position.y, pool.minY + d.half)
            }
            divers[k] = d
        }
    }

    private func randomTarget(_ k: Int, half: CGFloat, using rng: inout some RandomNumberGenerator) -> CGPoint {
        let p = pools[k], top = surface(k)
        let low = p.minY + half + 6, high = max(low + 1, top - half * 2)
        return CGPoint(x: .random(in: p.minX + half + 20...max(p.minX + half + 21, p.maxX - half - 20), using: &rng), y: .random(in: low...high, using: &rng))
    }

    private func steer(_ d: inout Diver, dt: Double, speed: CGFloat) {
        let dx = d.target.x - d.position.x, dy = d.target.y - d.position.y
        let distance = max(1, hypot(dx, dy))
        let want = CGVector(dx: dx / distance * speed, dy: dy / distance * speed)
        let k = CGFloat(min(1, dt * 2.5))
        d.velocity = CGVector(dx: d.velocity.dx + (want.dx - d.velocity.dx) * k, dy: d.velocity.dy + (want.dy - d.velocity.dy) * k)
        d.position.x += d.velocity.dx * CGFloat(dt)
        d.position.y += d.velocity.dy * CGFloat(dt)
        if abs(d.velocity.dx) > 6 { d.facingRight = d.velocity.dx > 0 }
    }

    private mutating func updateCritters(dt: Double, events: inout [Event], using rng: inout some RandomNumberGenerator) {
        let under = divers.filter(\.isUnder)
        // The schools' goals move on once reached.
        for (school, goal) in schoolGoals {
            let members = critters.filter { $0.school == school }
            guard let first = members.first else { continue }
            let cx = members.map(\.position.x).reduce(0, +) / CGFloat(members.count)
            let cy = members.map(\.position.y).reduce(0, +) / CGFloat(members.count)
            if hypot(goal.x - cx, goal.y - cy) < 30 {
                let p = pools[first.pool], top = surface(first.pool)
                schoolGoals[school] = CGPoint(x: .random(in: p.minX + 30...p.maxX - 30, using: &rng),
                                              y: p.minY + max(10, (top - p.minY)) * .random(in: 0.15...0.85, using: &rng))
            }
        }
        for k in critters.indices {
            var c = critters[k]
            c.time += dt
            c.scared = max(0, c.scared - dt)
            let p = pools[c.pool], top = surface(c.pool)
            let half = CGSize(width: c.kind.halfSize.width * scale, height: c.kind.halfSize.height * scale)
            // The nearest diver under water in the same pool.
            let near = under.filter { $0.pool == c.pool }.min {
                hypot($0.position.x - c.position.x, $0.position.y - c.position.y) < hypot($1.position.x - c.position.x, $1.position.y - c.position.y)
            }
            let distance = near.map { hypot($0.position.x - c.position.x, $0.position.y - c.position.y) } ?? .infinity
            if let diver = near, distance < Self.seeRadius {
                let last = divers.firstIndex { $0.index == diver.index }
                if let last, time - (divers[last].saw[c.kind] ?? -100) > Self.seeAgain, phase == .on {
                    divers[last].saw[c.kind] = time
                    events.append(c.kind == .octopus && distance < Self.scareRadius ? .startled(diver: diver.index) : .sees(diver: diver.index, c.kind))
                }
                if distance < Self.scareRadius, c.scared == 0 {
                    c.scared = c.kind == .octopus ? 2.5 : 1.2
                    if c.kind.isFish, let last, time - divers[last].lastScatter > 12, phase == .on {
                        divers[last].lastScatter = time
                        events.append(.scattered(diver: diver.index))
                    }
                    if c.kind == .octopus, let last, time - (divers[last].saw[.octopus] ?? -100) > 1, phase == .on {
                        divers[last].saw[.octopus] = time
                        events.append(.startled(diver: diver.index))
                    }
                }
            }
            let away: CGVector = near.map {
                let dx = c.position.x - $0.position.x, dy = c.position.y - $0.position.y, d = max(1, hypot(dx, dy))
                return CGVector(dx: dx / d, dy: dy / d)
            } ?? .zero
            switch c.kind {
            case .fishA, .fishB, .fishC:
                let goal = schoolGoals[c.school] ?? c.position
                let dx = goal.x - c.position.x, dy = goal.y - c.position.y, d = max(1, hypot(dx, dy))
                var want = CGVector(dx: dx / d * 36, dy: dy / d * 22)
                // Keep a little apart from the rest of the school.
                for other in critters where other.school == c.school {
                    let ox = c.position.x - other.position.x, oy = c.position.y - other.position.y, od = hypot(ox, oy)
                    if od > 0.5, od < 16 { want.dx += ox / od * 20; want.dy += oy / od * 20 }
                }
                if c.scared > 0 { want = CGVector(dx: away.dx * 150, dy: away.dy * 110) }
                let ease = CGFloat(min(1, dt * (c.scared > 0 ? 6 : 1.5)))
                c.velocity = CGVector(dx: c.velocity.dx + (want.dx - c.velocity.dx) * ease, dy: c.velocity.dy + (want.dy - c.velocity.dy) * ease)
            case .jelly:
                // Pulses up, drifts down; pushed off by a diver.
                let pulse = sin(c.time * 1.6)
                c.velocity = CGVector(dx: c.velocity.dx * 0.98 + (c.scared > 0 ? away.dx * 20 : 0) * CGFloat(dt * 4),
                                      dy: pulse > 0.6 ? 22 : -8)
                if abs(c.velocity.dx) < 3 { c.velocity.dx = c.facingRight ? 5 : -5 }
            case .crab:
                // Sideways along the floor about its patch; claws up and away when a diver comes.
                if c.scared > 0 {
                    c.velocity = CGVector(dx: (away.dx >= 0 ? 1 : -1) * 55, dy: 0)
                } else {
                    if abs(c.position.x - c.home) > 70 { c.velocity.dx = c.position.x > c.home ? -14 : 14 }
                }
                c.position.y = p.minY + half.height
                c.velocity.dy = 0
            case .turtle:
                c.velocity = CGVector(dx: (c.facingRight ? 1 : -1) * (c.scared > 0 ? 34 : 18), dy: CGFloat(sin(c.time * 0.5)) * 6)
                if c.position.x > p.maxX - half.width - 10 { c.facingRight = false }
                if c.position.x < p.minX + half.width + 10 { c.facingRight = true }
            case .octopus:
                if c.scared > 0 {
                    // Jets off, up and away, then sinks back to the floor.
                    c.velocity = CGVector(dx: away.dx * 90, dy: 50)
                } else {
                    c.velocity = CGVector(dx: (c.home - c.position.x) * 0.3, dy: -30)
                }
            }
            c.position.x += c.velocity.dx * CGFloat(dt)
            c.position.y += c.velocity.dy * CGFloat(dt)
            // Inside the water.
            let low = p.minY + half.height, high = max(low, top - half.height - 4)
            if c.position.y < low { c.position.y = low; if c.kind == .octopus || c.kind == .crab { c.velocity.dy = 0 } }
            if c.position.y > high { c.position.y = high; c.velocity.dy = min(0, c.velocity.dy) }
            if c.position.x < p.minX + half.width { c.position.x = p.minX + half.width; c.velocity.dx = abs(c.velocity.dx); c.home = max(c.home, c.position.x + 40) }
            if c.position.x > p.maxX - half.width { c.position.x = p.maxX - half.width; c.velocity.dx = -abs(c.velocity.dx); c.home = min(c.home, c.position.x - 40) }
            if c.kind != .turtle, abs(c.velocity.dx) > 4 { c.facingRight = c.velocity.dx > 0 }
            critters[k] = c
        }
    }

    private mutating func updateBubbles(dt: Double) {
        for k in bubbles.indices {
            bubbles[k].wobble += dt * 4
            bubbles[k].position.y += bubbles[k].rise * CGFloat(dt)
            bubbles[k].position.x += CGFloat(sin(bubbles[k].wobble)) * 0.4
        }
        let tops = pools.indices.map(surface), pools = pools
        bubbles.removeAll { b in
            let k = pools.firstIndex { $0.minX <= b.position.x && b.position.x <= $0.maxX } ?? 0
            return b.position.y >= tops[k] - 2
        }
    }

    // MARK: Words

    /// The line diver `name` says for `kind` ("in", "see", "fish", "octopus", "air", "out");
    /// `what` fills a sighting's `{what}`.
    public static func line(by name: String, _ kind: String, what: Life? = nil, using rng: inout some RandomNumberGenerator) -> String {
        let pool = lineSets()[name]?[kind] ?? anyoneSets()[kind] ?? []
        let line = pool.randomElement(using: &rng) ?? ""
        return CursorMood.current.adjust(fill(line, what: what?.spoken ?? ""))
    }

    /// `{what}` filled in, with a capital where it opens a sentence: "There. A turtle."
    static func fill(_ line: String, what: String) -> String {
        guard let range = line.range(of: "{what}") else { return line }
        let before = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        let opens = before.isEmpty || [".", "!", "?", "…"].contains(where: before.hasSuffix)
        let word = opens ? what.prefix(1).uppercased() + what.dropFirst() : what
        return line.replacingCharacters(in: range, with: word)
    }

    public static let lineSets = Translated(english: englishLines, [.russian: russianLines])
    public static let anyoneSets = Translated(english: englishAnyone, [.russian: russianAnyone])

    /// What a dive left in a pair's memory, for its storyline: "saw a turtle together".
    public static func memory(_ saw: [Life]) -> String {
        let named = Array(Set(saw.map { $0.isFish ? Life.fishA : $0 })).sorted { $0.rawValue < $1.rawValue }.map(\.spoken)
        return named.isEmpty ? "" : named.joined(separator: ", ")
    }
}

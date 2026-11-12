import Foundation

extension Weather {
    /// A window's top as the sky sees it: where it is in art pixels (y down, from the monitor's top-left), and
    /// which of its columns are open to the sky (not under another window in front).
    public struct Ledge: Equatable, Sendable {
        public var x: Int
        public var y: Int
        public var open: [Bool]
        public init(x: Int, y: Int, open: [Bool]) {
            self.x = x
            self.y = y
            self.open = open
        }
        public var width: Int { open.count }
    }

    /// What falls on one monitor and what lies there: the flakes, drops and leaves (the shared `FXParticles`,
    /// in art pixels, y down), the snow along the bottom and on the window tops, the puddles, and the splashes.
    /// Drawn into an `FXFrame` the size of the monitor in art pixels; the overlay scales it up, pixel for pixel.
    public final class Sky {
        public let w: Int, h: Int
        public let particles: FXParticles
        /// Where blown snow and the shower off a window come down: on the bottom pile.
        public private(set) var bottom: Pile
        /// Each window's ledge and the snow on it, by the window's number.
        public private(set) var ledges: [Int: (ledge: Ledge, pile: Pile)] = [:]
        /// How wet the bottom edge is, per column, 0...1: a puddle where it is over a half.
        public private(set) var wet: [Double]
        /// Where puddles can form along the bottom: a few dips, not the whole edge.
        public let dips: [Bool]
        private let rng: Rng
        private var owed = 0.0
        /// Snow showers off windows that moved or closed, as they start (for the film's steps).
        public var onShower: ((Int, Int) -> Void)?

        public static let snowColours = ["#ffffff", "#eef4ff", "#dce8f8"].map(FX.hex)
        public static let rainColour = FX.hex("#9cc4ff")
        public static let splash = ["#d8ecff", "#9cc4ff", "#6f9fe6", "#4a78c4"].map(FX.hex)
        public static let leafColours = ["#d9822b", "#c9541f", "#e0b13a", "#8f6a2f"].map(FX.hex)
        public static let dustColours = ["#c8b89a", "#a89878", "#d8ccb4"].map(FX.hex)
        // The pile in Blocky's style: a dark-tint outline on top, a light line under it, a flat fill, a shade low down.
        static let snowOutline = FX.hex("#8aa2c0"), snowLight = FX.hex("#ffffff"), snowFill = FX.hex("#e6eef8"), snowShade = FX.hex("#c4d3e6")
        static let printShade = FX.hex("#b2c4dc")
        static let puddleOutline = FX.hex("#2e5190"), puddleLight = FX.hex("#b4d4ff"), puddleFill = FX.hex("#4f82d6")

        public init(width: Int, height: Int, depth: Level, seed: Double = 7) {
            w = Swift.max(1, width)
            h = Swift.max(1, height)
            rng = Rng(seed)
            particles = FXParticles(seed: seed + 1, sparks: Self.splash)
            bottom = Pile(width: w, cap: bottomCap(depth))
            wet = Array(repeating: 0, count: w)
            var dips = Array(repeating: false, count: w)
            var x = Int(rng.range(10, 40))
            while x < w {
                let width = Int(rng.range(8, 22))
                for k in x..<Swift.min(w, x + width) { dips[k] = true }
                x += width + Int(rng.range(30, 90))
            }
            self.dips = dips
            particles.ground = { [unowned self] x in Double(self.groundY(Int(x))) }
        }

        /// The row the bottom pile's surface is on at column `x`.
        public func groundY(_ x: Int) -> Int { h - 1 - Int(bottom.height(at: Swift.min(Swift.max(0, x), w - 1)).rounded(.down)) }

        public var isEmpty: Bool { particles.count == 0 && bottom.isEmpty && ledges.values.allSatisfy { $0.pile.isEmpty } && wet.allSatisfy { $0 < 0.05 } }

        /// The depth settings changed: the caps follow.
        public func setDepth(_ depth: Level) {
            bottom.cap = bottomCap(depth)
            for (k, v) in ledges { var p = v.pile; p.cap = windowCap(depth); ledges[k] = (v.ledge, p) }
        }

        // MARK: Windows

        /// The windows as they stand now. A window gone, moved or resized drops its snow as a little shower;
        /// a new one starts bare.
        public func setLedges(_ now: [Int: Ledge], depth: Level) {
            for (id, was) in ledges {
                let still = now[id]
                if still?.x == was.ledge.x && still?.y == was.ledge.y && still?.width == was.ledge.width { continue }
                shower(was.ledge, was.pile)
                ledges.removeValue(forKey: id)
            }
            for (id, ledge) in now {
                if var have = ledges[id] { have.ledge.open = ledge.open; ledges[id] = have }
                else { ledges[id] = (ledge, Pile(width: ledge.width, cap: windowCap(depth))) }
            }
        }

        private func shower(_ ledge: Ledge, _ pile: Pile) {
            guard pile.average > 0.3 else { return }
            var flakes = 0
            for x in 0..<ledge.width where pile.height(at: x) > 0.3 && ledge.open[x] {
                let n = Int(pile.height(at: x).rounded(.up))
                for k in 0..<n where (x + k) % 2 == 0 {
                    particles.spawn(.grit, Double(ledge.x + x), Double(ledge.y - k), rng.range(-12, 12), rng.range(-30, 5), 3, Self.snowColours[k % 3], 1)
                    flakes += 1
                }
            }
            onShower?(ledge.x, flakes)
        }

        /// Snow on a window top, as an outsider sees it (tests, the film).
        public func ledgePile(_ id: Int) -> Pile? { ledges[id]?.pile }

        // MARK: Every frame

        /// One step: `kind` falling at `intensity` (0 once it is over), the wind's drift in pixels a second, with
        /// `heaviness` and `depth`. `reduced` halves the particles.
        public func update(_ dt: Double, kind: Kind?, intensity: Double, drift: Double, heaviness: Level, depth: Level,
                           windowTops: Bool, reduced: Bool) {
            particles.wind = drift
            if let kind, intensity > 0 { spawn(dt, kind: kind, intensity: intensity, drift: drift, heaviness: heaviness, depth: depth, reduced: reduced) }
            particles.update(dt)
            land(windowTops: windowTops, depth: depth)
            let snowing = kind?.snows == true && intensity > 0
            if snowing {
                bottom.grow(by: dt * snowfall(depth) * intensity)
                if windowTops { for (k, v) in ledges { var p = v.pile; p.grow(by: dt * snowfall(depth) * intensity * 0.6); ledges[k] = (v.ledge, p) } }
            } else {
                bottom.melt(by: dt * meltRate)
                for (k, v) in ledges { var p = v.pile; p.melt(by: dt * meltRate * 1.5); ledges[k] = (v.ledge, p) }
            }
            if !(kind?.rains == true && intensity > 0) {
                for x in wet.indices where wet[x] > 0 { wet[x] = Swift.max(0, wet[x] - dt / drySeconds) }
            }
            if !windowTops { for (k, v) in ledges where !v.pile.isEmpty { var p = v.pile; p.clear(); ledges[k] = (v.ledge, p) } }
        }

        private func spawn(_ dt: Double, kind: Kind, intensity: Double, drift: Double, heaviness: Level, depth: Level, reduced: Bool) {
            let share = reduced ? 0.5 : 1
            // Particles a second per hundred columns.
            var rate = 0.0
            if kind.snows { rate += 5 * depth.factor }
            if kind.rains { rate += 26 * heaviness.factor }
            if kind.blows { rate += kind.rains ? 1 : 2.2 }
            owed += dt * rate * Double(w) / 100 * intensity * share
            // Upwind, the particles start off screen, so the wind does not leave a bare strip.
            let margin = Swift.abs(drift) * 3
            while owed >= 1 {
                owed -= 1
                let x = rng.range(-margin * (drift > 0 ? 1 : 0), Double(w) + margin * (drift < 0 ? 1 : 0))
                let pick = rng.next() * rate
                if kind.snows && pick < 5 * depth.factor {
                    let near = rng.chance(0.25)
                    particles.spawn(.flake, x, rng.range(-6, -1), drift * 0.5, rng.range(8, 16), 120, rng.pick(Self.snowColours), near ? 1.6 : 1)
                } else if kind.rains && pick < (kind.snows ? 5 * depth.factor : 0) + 26 * heaviness.factor {
                    particles.spawn(.drop, x, rng.range(-8, -1), drift, rng.range(230, 290), 30, Self.rainColour, 1)
                } else if kind.blows {
                    // Leaves in autumn, dust the rest of the year (`leafy` set by the colony).
                    let side = drift >= 0 ? -4.0 : Double(w) + 4
                    let y = rng.range(Double(h) * 0.35, Double(h) - 4)
                    particles.spawn(.leaf, side, y, drift, 0, Double(w) / Swift.max(20, Swift.abs(drift)) * 1.6,
                                    rng.pick(leafy ? Self.leafColours : Self.dustColours), rng.chance(0.5) ? 1.6 : 1)
                }
            }
        }

        /// Leaves (autumn) rather than dust on the wind.
        public var leafy = false

        /// Flakes and drops that reached a surface stop there: snow on the pile, a splash and a wet patch for rain.
        private func land(windowTops: Bool, depth: Level) {
            var i = particles.list.count - 1
            while i >= 0 {
                defer { i -= 1 }
                let p = particles.list[i]
                guard p.k == .flake || p.k == .drop, p.delay <= 0 else {
                    if p.k == .leaf, p.x < -8 || p.x > Double(w) + 8 { particles.list.remove(at: i) }
                    continue
                }
                let x = Int(p.x.rounded(.down))
                if x < -40 || x > w + 40 || p.y > Double(h) + 4 { particles.list.remove(at: i); continue }
                let before = p.y - p.vy / 60
                if windowTops, let (id, top) = ledgeHit(x: x, from: before, to: p.y) {
                    particles.list.remove(at: i)
                    if p.k == .flake {
                        var pile = ledges[id]!.pile
                        pile.land(at: x - ledges[id]!.ledge.x, amount: 0.35)
                        ledges[id] = (ledges[id]!.ledge, pile)
                    } else { splash(Double(x), Double(top)) }
                    continue
                }
                guard x >= 0 && x < w else { continue }
                let g = groundY(x)
                if p.y >= Double(g) {
                    particles.list.remove(at: i)
                    if p.k == .flake { bottom.land(at: x, amount: 0.35) }
                    else {
                        splash(Double(x), Double(g))
                        for k in [x - 1, x, x + 1] where wet.indices.contains(k) && dips[k] { wet[k] = Swift.min(1, wet[k] + 0.012) }
                    }
                }
            }
        }

        /// The ledge a particle at column `x` crossed falling from `from` to `to`, and the row it hit.
        private func ledgeHit(x: Int, from: Double, to: Double) -> (Int, Int)? {
            for (id, v) in ledges {
                let col = x - v.ledge.x
                guard col >= 0, col < v.ledge.width, v.ledge.open[col] else { continue }
                let top = v.ledge.y - Int(v.pile.height(at: col).rounded(.down))
                if from < Double(top) && to >= Double(top) { return (id, top) }
            }
            return nil
        }

        private func splash(_ x: Double, _ y: Double) {
            guard rng.chance(0.35) else { return }
            for _ in 0..<2 {
                particles.spawn(.spark, x, y - 1, rng.range(-40, 40), rng.range(-110, -50), rng.range(0.18, 0.3), 0, 1)
            }
        }

        // MARK: Creatures in it

        /// A creature walked over column `x` of the bottom: a footprint, a dent in the snow.
        public func footprint(at x: Int) { bottom.step(at: x) }

        /// How deep the snow is at column `x`, and the cap: for a creature wading through it.
        public func depth(at x: Int) -> (depth: Double, cap: Double) { (bottom.height(at: x), bottom.cap) }

        /// A puff of snow kicked up, or a snowball bursting: a few white specks.
        public func puff(_ x: Double, _ y: Double, count: Int = 6) {
            for _ in 0..<count { particles.spawn(.grit, x, y, rng.range(-30, 30), rng.range(-80, -20), 1.2, rng.pick(Self.snowColours), 1) }
        }

        /// The water spilled from an umbrella: a burst of drops where it lands.
        public func spill(_ x: Double, _ y: Double) {
            for _ in 0..<14 { particles.spawn(.spark, x + rng.range(-6, 6), y, rng.range(-60, 60), rng.range(-90, 20), rng.range(0.3, 0.6), 0, 1) }
            for k in Int(x) - 6...Int(x) + 6 where wet.indices.contains(k) { wet[k] = Swift.min(1, wet[k] + 0.3) }
        }

        /// Snow lies thick enough here for a snowman.
        public func canBuildSnowman(at x: Int) -> Bool { bottom.height(at: x) >= bottom.cap * 0.4 }

        /// Fill the piles by hand: the film's and the tests' way to a given depth.
        public func fillBottom(by amount: Double) { bottom.grow(by: amount) }
        public func fillLedges(by amount: Double) {
            for (k, v) in ledges { var p = v.pile; p.grow(by: amount); ledges[k] = (v.ledge, p) }
        }

        // MARK: Drawing

        /// Everything, into `frame` (cleared first): the piles and puddles, then what is falling.
        public func draw(into frame: FXFrame) {
            frame.clear()
            let p = Painter(frame)
            p.reset()
            drawPile(bottom, x0: 0, floor: h - 1, open: nil, prints: true, into: frame)
            for (_, v) in ledges { drawPile(v.pile, x0: v.ledge.x, floor: v.ledge.y - 1, open: v.ledge.open, prints: false, into: frame) }
            drawPuddles(into: frame)
            particles.draw(p, nil)
        }

        private func put(_ f: FXFrame, _ x: Int, _ y: Int, _ c: FXColor) {
            guard x >= 0, y >= 0, x < f.w, y < f.h else { return }
            f.color[y * f.w + x] = c
        }

        private func drawPile(_ pile: Pile, x0: Int, floor: Int, open: [Bool]?, prints: Bool, into f: FXFrame) {
            guard !pile.isEmpty else { return }
            for x in 0..<pile.width {
                if let open, !open[x] { continue }
                let n = Int(pile.height(at: x).rounded(.down))
                guard n > 0 else { continue }
                let X = x0 + x
                let dent = prints && x > 0 && x < pile.width - 1 && pile.height(at: x) + 0.6 < Swift.min(pile.height(at: x - 1), pile.height(at: x + 1))
                for k in 0..<n {
                    let y = floor - k
                    let c: FXColor
                    if k == n - 1 { c = snowOutline }
                    else if k == n - 2 { c = dent ? Self.printShade : Self.snowLight }
                    else if k == 0 && n > 3 { c = Self.snowShade }
                    else { c = Self.snowFill }
                    put(f, X, y, c)
                }
            }
        }
        private var snowOutline: FXColor { Self.snowOutline }

        private func drawPuddles(into f: FXFrame) {
            var x = 0
            while x < w {
                guard wet[x] > 0.5 else { x += 1; continue }
                var end = x
                while end < w && wet[end] > 0.5 { end += 1 }
                if end - x >= 3 {
                    let g = groundY(x)
                    let deep = (wet[x..<end].max() ?? 0) > 0.85 ? 2 : 1
                    for k in x..<end {
                        let edge = k == x || k == end - 1
                        put(f, k, g - deep, edge ? Self.puddleOutline : Self.puddleOutline)
                        for d in 0..<deep { put(f, k, g - d, edge ? Self.puddleOutline : (d == deep - 1 && k < x + (end - x) / 2 ? Self.puddleLight : Self.puddleFill)) }
                    }
                }
                x = end
            }
        }
    }
}

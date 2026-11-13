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

    /// The season's light particles (Settings › Weather & Sky): a few snowflakes in winter, leaves in autumn,
    /// petals in spring, falling from above the top edge the whole height and gone at the bottom.
    public struct Light: Equatable, Sendable {
        public enum Kind: String, CaseIterable, Sendable {
            case snow, leaves, petals
            /// Pixels a second it falls: petals drift, leaves flutter, flakes float.
            public var fall: Double {
                switch self {
                case .snow: 12
                case .leaves: 22
                case .petals: 15
                }
            }
        }
        public var kind: Kind
        /// On a monitor at once, at full intensity.
        public var count: Double
        /// 0...1: rising as it comes out, falling as it goes.
        public var intensity: Double
        public init(kind: Kind, count: Double, intensity: Double = 1) {
            self.kind = kind
            self.count = count
            self.intensity = intensity
        }
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

        /// One step: `kind` falling at `intensity` (0 once it is over), the wind's drift in pixels a second, as
        /// `switches` say; and `light`, the season's light particles, if they are out. Reduce motion halves them all.
        public func update(_ dt: Double, kind: Kind?, intensity: Double, drift: Double, switches s: Switches, light: Light? = nil) {
            particles.wind = drift
            if let kind, intensity > 0 { spawn(dt, kind: kind, intensity: intensity, drift: drift, switches: s) }
            if let light, light.intensity > 0 { spawnLight(dt, light, reduced: s.reduceMotion) }
            particles.update(dt)
            land(switches: s)
            let snowing = kind?.snows == true && intensity > 0 && s.snowPiles
            if snowing {
                bottom.grow(by: dt * snowfall(s.snowDepth) * intensity)
                if s.windowTops { for (k, v) in ledges { var p = v.pile; p.grow(by: dt * snowfall(s.snowDepth) * intensity * 0.6); ledges[k] = (v.ledge, p) } }
            } else {
                bottom.melt(by: dt * meltRate)
                for (k, v) in ledges { var p = v.pile; p.melt(by: dt * meltRate * 1.5); ledges[k] = (v.ledge, p) }
            }
            if !(kind?.rains == true && intensity > 0 && s.puddles) {
                for x in wet.indices where wet[x] > 0 { wet[x] = Swift.max(0, wet[x] - dt / (s.puddles ? drySeconds : 1)) }
            }
            if !s.windowTops { for (k, v) in ledges where !v.pile.isEmpty { var p = v.pile; p.clear(); ledges[k] = (v.ledge, p) } }
        }

        /// Everything gone at once: what falls, what lies, the puddles (Stop, once the picture has faded).
        public func clearAll() {
            particles.list.removeAll()
            bottom.clear()
            for (k, v) in ledges { var p = v.pile; p.clear(); ledges[k] = (v.ledge, p) }
            for x in wet.indices { wet[x] = 0 }
        }

        /// The lowest row anything has been born on so far (rows count down from the monitor's top edge): below
        /// zero, everything starts above the screen and falls the whole height.
        public private(set) var spawnTop = -Double.infinity
        /// The falling things on the monitor now: flakes, drops and leaves, not the splashes or puffs.
        public var falling: Int { particles.list.filter { $0.k == .flake || $0.k == .drop || $0.k == .leaf }.count }

        private var owedSnow = 0.0, owedRain = 0.0, owedLeaf = 0.0, owedLight = 0.0

        /// Particles a second that keep `count` on a monitor this wide, each falling the whole height at `fall`
        /// pixels a second: as many are born as reach the bottom.
        public static func birthRate(count: Double, fall: Double, width: Int, height: Int) -> Double {
            guard height > 0, fall > 0 else { return 0 }
            return count * Double(width) / referenceWidth * fall / Double(height)
        }

        /// How fast snow, rain and the wind's leaves fall, in pixels a second.
        public static func snowFall(_ s: Switches) -> Double { 16 * s.snowSpeed }
        public static func rainFall(_ s: Switches) -> Double { 260 * s.rainSpeed }
        public static let leafFall = 28.0

        private func spawnPoint(_ drift: Double, fall: Double) -> (x: Double, y: Double) {
            // Upwind, some start off the side, so the wind carries them in and leaves no bare strip.
            let margin = Swift.min(Double(w), Swift.abs(drift) * Double(h) / fall)
            let x = rng.range(-margin * (drift > 0 ? 1 : 0), Double(w) + margin * (drift < 0 ? 1 : 0))
            return (x, rng.range(-6, -1))
        }

        private func born(_ y: Double) { spawnTop = Swift.max(spawnTop, y) }

        private func spawn(_ dt: Double, kind: Kind, intensity: Double, drift: Double, switches s: Switches) {
            let k = intensity * (s.reduceMotion ? 0.5 : 1)
            let H = Double(h)
            if kind.snows {
                let fall = Self.snowFall(s)
                owedSnow += dt * k * Self.birthRate(count: s.snowCount, fall: fall, width: w, height: h)
                while owedSnow >= 1 {
                    owedSnow -= 1
                    let (x, y) = spawnPoint(drift * 0.5, fall: fall)
                    let big = rng.chance(s.flakeSize.bigShare)
                    particles.spawn(.flake, x, y, drift * 0.5, fall * rng.range(0.5, 1), H / fall * 3 + 30, rng.pick(Self.snowColours),
                                    big ? 1.6 : 1, fall: fall)
                    born(y)
                }
            }
            if kind.rains {
                let fall = Self.rainFall(s)
                owedRain += dt * k * Self.birthRate(count: s.rainCount * (kind.blows ? 1.3 : 1), fall: fall, width: w, height: h)
                while owedRain >= 1 {
                    owedRain -= 1
                    let (x, y) = spawnPoint(drift, fall: fall)
                    particles.spawn(.drop, x, y, drift, fall * rng.range(0.9, 1.1), H / fall * 3 + 5, Self.rainColour, 1)
                    born(y)
                }
            }
            if kind.blows {
                // Leaves in autumn, dust the rest of the year (`leafy` set by the colony), falling from the top too.
                owedLeaf += dt * k * Self.birthRate(count: windLeaves * s.windStrength.factor * (kind.rains ? 0.5 : 1), fall: Self.leafFall, width: w, height: h)
                while owedLeaf >= 1 {
                    owedLeaf -= 1
                    let (x, y) = spawnPoint(drift, fall: Self.leafFall)
                    particles.spawn(.leaf, x, y, drift, 0, H / Self.leafFall * 3 + 10, rng.pick(leafy ? Self.leafColours : Self.dustColours),
                                    rng.chance(0.5) ? 1.6 : 1, fall: Self.leafFall)
                    born(y)
                }
            }
        }

        /// Leaves (autumn) rather than dust on the wind.
        public var leafy = false

        public static let petalColours = ["#ffd1dc", "#ffb3c6", "#f7a1b5", "#fff0f4"].map(FX.hex)

        private func spawnLight(_ dt: Double, _ light: Light, reduced: Bool) {
            let fall = light.kind.fall
            owedLight += dt * light.intensity * (reduced ? 0.5 : 1) * Self.birthRate(count: light.count, fall: fall, width: w, height: h)
            while owedLight >= 1 {
                owedLight -= 1
                let x = rng.range(0, Double(w)), y = rng.range(-6, -1), life = Double(h) / fall * 3 + 10
                switch light.kind {
                case .snow:
                    particles.spawn(.flake, x, y, 0, fall * 0.6, life, rng.pick(Self.snowColours), rng.chance(0.2) ? 1.6 : 1, 0, FXFlag.light, fall: fall)
                case .leaves:
                    particles.spawn(.leaf, x, y, 0, 0, life, rng.pick(Self.leafColours), rng.chance(0.5) ? 1.6 : 1, 0, FXFlag.light, fall: fall)
                case .petals:
                    particles.spawn(.leaf, x, y, 0, 0, life, rng.pick(Self.petalColours), rng.chance(0.4) ? 1.6 : 1, 0, FXFlag.light, fall: fall)
                }
                born(y)
            }
        }

        /// Flakes and drops that reached a surface stop there: snow on the pile, a splash and a wet patch for rain.
        /// The season's light ones and the leaves are simply gone.
        private func land(switches s: Switches) {
            var i = particles.list.count - 1
            while i >= 0 {
                defer { i -= 1 }
                let p = particles.list[i]
                if p.k == .leaf {
                    let x = Int(p.x.rounded(.down))
                    if p.x < -Double(w) || p.x > Double(w) * 2 || p.y >= Double(groundY(x)) { particles.list.remove(at: i) }
                    continue
                }
                guard p.k == .flake || p.k == .drop, p.delay <= 0 else { continue }
                let x = Int(p.x.rounded(.down))
                if x < -Swift.max(40, w) || x > w * 2 || p.y > Double(h) + 4 { particles.list.remove(at: i); continue }
                let light = p.flag & FXFlag.light != 0
                let before = p.y - p.vy / 60
                if !light, s.windowTops, let (id, top) = ledgeHit(x: x, from: before, to: p.y) {
                    particles.list.remove(at: i)
                    if p.k == .flake {
                        if s.snowPiles {
                            var pile = ledges[id]!.pile
                            pile.land(at: x - ledges[id]!.ledge.x, amount: 0.35)
                            ledges[id] = (ledges[id]!.ledge, pile)
                        }
                    } else { splash(Double(x), Double(top)) }
                    continue
                }
                guard x >= 0 && x < w else { continue }
                let g = groundY(x)
                if p.y >= Double(g) {
                    particles.list.remove(at: i)
                    if light { continue }
                    if p.k == .flake { if s.snowPiles { bottom.land(at: x, amount: 0.35) } }
                    else {
                        splash(Double(x), Double(g))
                        if s.puddles { for k in [x - 1, x, x + 1] where wet.indices.contains(k) && dips[k] { wet[k] = Swift.min(1, wet[k] + 0.012) } }
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

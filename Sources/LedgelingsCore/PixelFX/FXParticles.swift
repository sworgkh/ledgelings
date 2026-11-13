// Particles for the effects, ported from pixelfx (https://github.com/patch-gg/pixelfx, MIT): closed-form
// ones whose place is a function of their age (so a loop has no seam), and simulated ones that streak,
// bounce, swell and thin. pixelfx adapts the simulated kinds from Sprite Fusion's open-source pixel art VFX
// (https://www.spritefusion.com/pixel-art-vfx), MIT, Copyright (c) 2026 Hugo Duprez. Units are art pixels
// and seconds. This is the shared particle layer the creatures' moments and the seasons draw with.

import Foundation

extension FX {
    public static let gravity = 950.0
    static let cross: [(Double, Double)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    static let diag: [(Double, Double)] = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    public static let hot = ["#fff3a6", "#ffe26b", "#ff8a2a", "#f2561d"].map(hex)
    /// Fire from white-hot to smouldering, and smoke from fresh to thin.
    public static let fireRamp = ["#ffffff", "#fff3a6", "#ffe26b", "#ffc23d", "#ff8a2a", "#f2561d", "#c9281f", "#8a1f17", "#4a1712"].map(hex)
    public static let smokeRamp = ["#7b6f72", "#5d5660", "#433d48", "#2b2630", "#1a171e"].map(hex)
    @inline(__always) static func rampAt(_ r: [FXColor], _ t: Double) -> FXColor {
        r[Swift.min(r.count - 1, Swift.max(0, Int(floor(t * Double(r.count)))))]
    }

    // MARK: Closed-form particles

    /// Where a particle is after t seconds, launched from (x, y) at (vx, vy), under gravity g and linear drag.
    public static func fly(_ x: Double, _ y: Double, _ vx: Double, _ vy: Double, _ t: Double, _ g: Double = 0, _ drag: Double = 0) -> (Double, Double) {
        if drag <= 0 { return (x + vx * t, y + vy * t + 0.5 * g * t * t) }
        let f = (1 - exp(-drag * t)) / drag, vt = g / drag
        return (x + vx * f, y + vt * t + (vy - vt) * f)
    }
    /// Its velocity at t.
    public static func flyV(_ vx: Double, _ vy: Double, _ t: Double, _ g: Double = 0, _ drag: Double = 0) -> (Double, Double) {
        if drag <= 0 { return (vx, vy + g * t) }
        let e = exp(-drag * t), vt = g / drag
        return (vx * e, vt + (vy - vt) * e)
    }
    /// n one-shot particles, each with its own repeatable generator.
    public static func burst(_ n: Int, _ seed: Double, _ fn: (Rng, Int) -> Void) {
        for i in 0..<n { fn(rng(seed, Double(i)), i) }
    }
    /// Particles that repeat every `period` seconds: fn(age, life, r, i) for every live copy.
    public static func cycle(_ t: Double, _ period: Double, _ count: Int, _ seed: Double, _ life: Double,
                             _ fn: (Double, Double, Rng, Int) -> Void) {
        cycle(t, period, count, seed, { _ in life }, fn)
    }
    public static func cycle(_ t: Double, _ period: Double, _ count: Int, _ seed: Double, _ life: (Rng) -> Double,
                             _ fn: (Double, Double, Rng, Int) -> Void) {
        for i in 0..<count {
            let g = rng(seed, Double(i), 911)
            let born = g.next() * period
            let L = life(g)
            var age = mod(mod(t - born, period) + period, period)
            while age < L { fn(age, L, rng(seed, Double(i)), i); age += period }
        }
    }
    /// Particles born at a steady rate between t0 and t1: fn(age, life, r, i) for every one alive at t.
    public static func stream(_ t: Double, _ t0: Double, _ t1: Double, _ rate: Double, _ seed: Double, _ life: (Rng) -> Double,
                              _ fn: (Double, Double, Rng, Int) -> Void) {
        let n = Int(floor((Swift.min(t, t1) - t0) * rate))
        guard n >= 0 else { return }
        for i in 0...n {
            let born = t0 + Double(i) / rate, g = rng(seed, Double(i), 911), L = life(g)
            let age = t - born
            if age >= 0 && age < L { fn(age, L, rng(seed, Double(i)), i) }
        }
    }

    // MARK: Shapes

    /// A jagged lightning path by midpoint displacement; jag is how far a midpoint may move, as a share of its segment.
    public static func bolt(_ r: Rng, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, jag: Double = 0.22, depth: Int = 5) -> [(Double, Double)] {
        var pts = [(x0, y0), (x1, y1)]
        for _ in 0..<depth {
            var next = [pts[0]]
            for i in 1..<pts.count {
                let (ax, ay) = pts[i - 1], (bx, by) = pts[i], dx = bx - ax, dy = by - ay, L = hypot(dx, dy)
                let off = (r.next() * 2 - 1) * jag * L, l = L == 0 ? 1 : L
                next.append(((ax + bx) / 2 + (-dy / l) * off, (ay + by) / 2 + (dx / l) * off))
                next.append(pts[i])
            }
            pts = next
        }
        return pts
    }
    /// Forks off a bolt path: count branches, each up to len px long.
    public static func forks(_ r: Rng, _ path: [(Double, Double)], count: Int = 3, len: Double = 20, jag: Double = 0.3, spread: Double = 0.9) -> [[(Double, Double)]] {
        var out: [[(Double, Double)]] = []
        for _ in 0..<count {
            let i = 1 + Int(floor(r.next() * Double(path.count - 2))), (x, y) = path[i], (px, py) = path[i - 1]
            let a = atan2(y - py, x - px) + (r.next() < 0.5 ? -1 : 1) * spread * (0.4 + 0.6 * r.next())
            let l = len * (0.4 + 0.6 * r.next())
            out.append(bolt(r, x, y, x + cos(a) * l, y + sin(a) * l, jag: jag, depth: 3))
        }
        return out
    }
    /// A star: n points between radii r1 (tips) and r0 (inner corners).
    public static func star(_ cx: Double, _ cy: Double, _ r0: Double, _ r1: Double, _ n: Int = 5, _ rot: Double = -Double.pi / 2) -> [(Double, Double)] {
        (0..<(n * 2)).map { i in
            let a = rot + (Double(i) * Double.pi) / Double(n), r = i % 2 != 0 ? r0 : r1
            return (cx + cos(a) * r, cy + sin(a) * r)
        }
    }
    /// A regular polygon with n sides.
    public static func ngon(_ cx: Double, _ cy: Double, _ r: Double, _ n: Int = 6, _ rot: Double = 0) -> [(Double, Double)] {
        (0..<n).map { i in (cx + cos(rot + (Double(i) * tau) / Double(n)) * r, cy + sin(rot + (Double(i) * tau) / Double(n)) * r) }
    }
    /// Positions of pos(t - i·dt) for i = 0..n-1, newest first.
    public static func trail(_ pos: (Double) -> (Double, Double), _ t: Double, _ n: Int, _ dt: Double) -> [(Double, Double)] {
        (0..<n).map { i in pos(Swift.max(0, t - Double(i) * dt)) }
    }

    // MARK: Glints, flares, bands

    /// A star glint: arms of length arm in c with tips in tip, a white heart, light.
    public static func sparkle(_ p: Painter, _ x: Double, _ y: Double, _ arm: Double, _ c: FXColor, _ tip: FXColor? = nil, _ k: Double = 0.6) {
        let tip = tip ?? c
        let n = Int(round(arm))
        if n < 1 { return }
        let X = floor(x), Y = floor(y)
        for d in 1...n {
            let cc = Double(d) > Double(n) * 0.6 ? tip : c
            for (dx, dy) in cross { p.px(X + dx * Double(d), Y + dy * Double(d), cc) }
        }
        if n >= 3 { for (dx, dy) in diag { p.px(X + dx, Y + dy, c) } }
        if n >= 6 { for (dx, dy) in diag { p.px(X + dx * 2, Y + dy * 2, tip) } }
        p.px(X, Y, white)
        p.glow(x, y, 4 + Double(n) * 2, c, k)
    }
    /// An 8-ray flare: long rays on the axes, shorter between, fading along their length. ramp dark to bright.
    public static func flare(_ p: Painter, _ x: Double, _ y: Double, _ L: Double, _ k: Double, _ R: [FXColor]) {
        if L < 1 { return }
        let n = R.count
        for i in 0..<8 {
            let an = (Double(i) * Double.pi) / 4, len = i % 4 == 0 ? L : i % 2 == 0 ? L * 0.6 : L * 0.3, ca = cos(an), sa = sin(an)
            var d = 0.0
            while d <= len {
                let u = d / len
                p.dot(x + ca * d, y + sa * d, u < 0.35 ? white : u < 0.7 ? R[n - 2] : R[n - 3], u < 0.6 ? 1 : k * 1.5 * (1 - u) + 0.2)
                d += 0.5
            }
        }
    }
    /// A ring on a tilted plane (sy squashes it), thickness th inward, alpha k, coloured by depth through the band;
    /// keep(angle) picks which part to draw, so the far half can go behind and the near half in front.
    public static func band(_ p: Painter, _ cx: Double, _ cy: Double, _ r: Double, _ sy: Double, _ th: Double, _ k: Double,
                            _ R: [FXColor], _ keep: (Double) -> Bool = { _ in true }, _ hot: Bool = false) {
        if r <= 0 || k <= 0 { return }
        let n = R.count, m = Int(ceil(r * tau * 1.2))
        for j in 0..<m {
            let ang = (Double(j) / Double(m)) * tau, ca = cos(ang), sa = sin(ang)
            if !keep(ang) { continue }
            var o = th
            while o >= 0 {
                let u = o / th, c = u < 0.15 ? (hot ? white : R[n - 1]) : u < 0.4 ? R[n - 2] : u < 0.7 ? R[n - 3] : R[n - 4]
                p.dot(cx + ca * (r - o), cy + sa * (r - o) * sy, c, k * (u < 0.4 ? 1.2 : 1.15 - u))
                o -= 0.5
            }
        }
    }
}

// MARK: Simulated particles

/// Particle kinds, as pixelfx numbers them.
public enum FXKind: Int {
    case spark = 0, mote, streak, flake, vapour, dust, star, ember, smoke, fire, brand, grit
    /// Weather's own (SPEC §7.20), not pixelfx's: a raindrop falling straight at its speed, and a leaf or a
    /// speck of dust carried on the wind.
    case drop, leaf
}

/// Particle flags: smokes (a fire puff leaves smoke), big (bigger, slower smoke), back (drawn behind).
public enum FXFlag {
    public static let smokes = 1, big = 2, back = 4
    /// Weather's light season particles: they fall and are gone, never piling up or wetting the ground.
    public static let light = 8
}

/// A particle system: spawn kinds, step them, draw "back" (the soft kinds) or "front" (the rest).
public final class FXParticles {
    public struct P {
        public var k: FXKind, x: Double, y: Double, vx: Double, vy: Double, life: Double, max: Double
        public var col: FXColor, size: Double, seed: Double, delay: Double, flag: Int
        /// Weather's flakes and leaves: how fast it settles to falling, in pixels a second (0: pixelfx's own pace).
        public var fall = 0.0
    }
    public let R: Rng
    public var list: [P] = []
    public var t = 0.0
    public var ground: (Double) -> Double
    public var sparks: [FXColor]
    public var haze: FXColor?
    public var onLand: ((Double, Double) -> Void)?
    /// Weather's wind, in pixels a second: it carries the flakes, drops and leaves sideways. 0 (pixelfx's effects)
    /// changes nothing.
    public var wind = 0.0

    public init(rng: Rng? = nil, seed: Double = 1, ground: ((Double) -> Double)? = nil, sparks: [FXColor]? = nil, haze: FXColor? = nil) {
        R = rng ?? Rng(seed)
        self.ground = ground ?? { _ in .infinity }
        self.sparks = sparks ?? FX.hot
        self.haze = haze
    }
    public var count: Int { list.count }

    /// delay: seconds before it appears; col 0 lets fire and smoke use their own ramps.
    public func spawn(_ k: FXKind, _ x: Double, _ y: Double, _ vx: Double, _ vy: Double, _ life: Double,
                      _ col: FXColor = FX.white, _ size: Double = 1, _ delay: Double = 0, _ flag: Int = 0, fall: Double = 0) {
        list.append(P(k: k, x: x, y: y, vx: vx, vy: vy, life: life, max: life, col: col, size: size, seed: R.next() * 100, delay: delay, flag: flag, fall: fall))
    }

    static func soft(_ k: FXKind) -> Bool { k == .vapour || k == .dust || k == .smoke }

    public func update(_ dt: Double) {
        t += dt
        let R = self.R, t = self.t
        var i = list.count - 1
        while i >= 0 {
            defer { i -= 1 }
            var p = list[i]
            if p.delay > 0 { p.delay -= dt; list[i] = p; continue }
            p.life -= dt
            if p.life <= 0 {
                if p.k == .fire && p.flag & FXFlag.smokes != 0 {
                    let big = p.flag & FXFlag.big != 0
                    spawn(.smoke, p.x, p.y, p.vx * 0.6, p.vy * 0.6 - 6, big ? R.range(1.3, 2.3) : R.range(0.8, 1.4), 0, p.size * (big ? 0.85 : 0.7), 0, big ? FXFlag.big : 0)
                }
                list.remove(at: i)
                continue
            }
            switch p.k {
            case .fire:
                p.vy -= 95 * dt
                p.vx += sin(t * 17 + p.seed) * 30 * dt
                p.vx -= p.vx * 5 * dt
                p.vy -= p.vy * 3.2 * dt
            case .grit:
                p.vy += FX.gravity * dt
                p.vx -= p.vx * 0.8 * dt
                let g = ground(p.x), ny = p.y + p.vy * dt
                p.x += p.vx * dt
                if p.vy > 0 && p.y <= g && ny >= g {
                    p.y = g - 0.25
                    if p.vy > 130 && R.chance(0.4) { p.vy = -p.vy * 0.25; p.vx = p.vx * 0.5 + R.range(-10, 10) }
                    else { p.vx = 0; p.vy = 0; p.life = Swift.min(p.life, 0.5) }
                } else { p.y = ny }
                list[i] = p
                continue
            case .brand:
                p.vy += FX.gravity * 0.8 * dt
                p.vx -= p.vx * 0.9 * dt
                list[i] = p
                if R.chance(0.9 * Swift.min(1, dt * 60)) {
                    spawn(.fire, p.x, p.y, p.vx * 0.1 + R.range(-7, 7), p.vy * 0.1 - 10, R.range(0.16, 0.32), 0,
                          R.range(0.9, 1.7) * (0.5 + (p.life / p.max) * 0.6), 0, R.chance(0.4) ? FXFlag.smokes : 0)
                }
                let g = ground(p.x), ny = p.y + p.vy * dt
                p.x += p.vx * dt
                if p.vy > 0 && p.y <= g && ny >= g {
                    onLand?(p.x, g)
                    list.remove(at: i)
                } else { p.y = ny; list[i] = p }
                continue
            case .spark:
                p.vy += FX.gravity * 0.45 * dt
                p.vx -= p.vx * 2.2 * dt
                p.vy -= p.vy * 2.2 * dt
                let g = ground(p.x), ny = p.y + p.vy * dt
                p.x += p.vx * dt
                if p.vy > 0 && p.y <= g && ny >= g { p.vy = -p.vy * 0.45; p.vx *= 0.7; p.y = g - 0.25 }
                else { p.y = ny }
                list[i] = p
                continue
            case .streak:
                p.vx += p.vx * 3 * dt; p.vy += p.vy * 3 * dt
            case .flake:
                p.vx -= p.vx * 2.2 * dt
                p.vy -= p.vy * 2.2 * dt - (p.fall > 0 ? p.fall * 2.2 : 35) * dt
                p.x += sin(self.t * 2.5 + p.seed) * 7 * dt
                if wind != 0 { p.x += wind * dt * (0.7 + FX.mod(p.seed, 0.6)) }
            case .drop:
                p.vx += (wind - p.vx) * 4 * dt
            case .leaf:
                p.vx += (wind * (0.6 + FX.mod(p.seed, 0.6)) + sin(t * 1.3 + p.seed) * 9 - p.vx) * 2 * dt
                p.vy = sin(t * 3.1 + p.seed) * 14 + (p.fall > 0 ? p.fall : 6)
            case .ember:
                p.vy += (-30 + sin(t * 3 + p.seed) * 20) * dt
                p.vx += cos(t * 2.3 + p.seed) * 45 * dt
                p.vx -= p.vx * 1.6 * dt
                p.vy -= p.vy * 1.6 * dt
            case .smoke:
                let big = p.flag & FXFlag.big != 0
                p.vy -= (big ? 23 : 16) * dt
                p.vx += sin(t * 1.3 + p.seed) * 8 * dt
                p.vx -= p.vx * 1.6 * dt
                p.vy -= p.vy * 1.2 * dt
            case .mote:
                p.vx -= p.vx * 0.6 * dt; p.vy -= p.vy * 0.6 * dt
            default:
                let drag = Self.soft(p.k) ? 4.0 : 1.6
                p.vx -= p.vx * drag * dt
                p.vy -= p.vy * drag * dt + 5 * dt
            }
            p.x += p.vx * dt
            p.y += p.vy * dt
            list[i] = p
        }
    }

    public func draw(_ p: Painter, _ layer: FXLayer?) {
        for q in list {
            if q.delay > 0 { continue }
            if let layer, (Self.soft(q.k) || q.flag & FXFlag.back != 0 ? FXLayer.back : .front) != layer { continue }
            let k = q.life / q.max, x = q.x, y = q.y, h = hypot(q.vx, q.vy), sp = h == 0 ? 1 : h, ux = q.vx / sp, uy = q.vy / sp
            switch q.k {
            case .spark:
                let S = sparks, head = k > 0.6 ? S[0] : k > 0.3 ? S[1] : S[2], len = Swift.min(9, 1 + sp * 0.022)
                p.line(x - ux * len, y - uy * len, x - ux * len * 0.4, y - uy * len * 0.4, k > 0.5 ? head : S[S.count - 1])
                p.line(x - ux * len * 0.45, y - uy * len * 0.45, x, y, head)
                p.glow(x, y, 3, head, 0.45 * k)
            case .mote:
                let len = Swift.min(16, 0.5 + sp * 0.026) * q.size, a = k < 0.35 ? k / 0.35 : 1
                p.line(x - ux * len, y - uy * len, x - ux * len * 0.35, y - uy * len * 0.35, FX.scale(q.col, 0.55), a)
                p.line(x - ux * len * 0.4, y - uy * len * 0.4, x, y, q.col, a)
                p.glow(x, y, 2.5 + q.size, q.col, 0.4 * k)
            case .streak:
                let L = FX.clamp(sp / 30, 1, 7)
                var d = L
                while d >= 0 {
                    p.dot(x - ux * d, y - uy * d, d < 1 ? FX.white : d < L * 0.5 ? q.col : FX.scale(q.col, 0.6), d < L * 0.5 ? 1 : 1.2 - d / L)
                    d -= 0.5
                }
                p.glow(x, y, 4, q.col, 0.4)
            case .flake:
                let a = Swift.min(1, k * 3)
                p.dot(x, y, q.col, a)
                if q.size > 1.3 { for (dx, dy) in FX.cross { p.dot(x + dx, y + dy, FX.scale(q.col, 0.8), a * 0.8) } }
            case .vapour:
                let r = q.size * (0.6 + (1 - k) * 0.9)
                p.disc(x, y, r, q.col, pow(k, 1.3) * 0.45)
                if let haze { p.glow(x, y, r * 1.8, haze, 0.16 * k) }
            case .dust:
                p.disc(x, y, q.size * (0.6 + (1 - k) * 0.9), q.col, pow(k, 1.3) * 0.7)
            case .smoke:
                let age = 1 - k, big = q.flag & FXFlag.big != 0
                let r = q.size * (0.65 + Swift.min(1, age * 2.5) * 0.45 + age * (big ? 0.5 : 0.4))
                let a = Swift.min(1, age * 12) * Swift.min(1, k * 2.4) * (big ? 0.7 : 0.58)
                let c = q.col != 0 ? FX.mix(q.col, FX.rampAt(FX.smokeRamp, age), age) : FX.rampAt(FX.smokeRamp, age * 1.05)
                p.disc(x, y, r, c, a * 0.45)
                p.disc(x + r * 0.05, y + r * 0.06, r * 0.74, c, a * 0.62)
                if age < 0.5 { p.disc(x - r * 0.22, y - r * 0.3, r * 0.5, FX.mix(c, FX.white, 0.12), a * 0.4 * (1 - age * 2)) }
            case .fire:
                let age = 1 - k, heat = Swift.min(0.999, pow(age, 0.62) + FX.mod(q.seed, 1) * 0.1), F = FX.fireRamp, n = F.count
                let idx = Swift.min(n - 2, Int(FX.floor(heat * Double(n - 1))))
                let r = q.size * (0.55 + 0.45 * Swift.min(1, age * 7)) * (1 - age * 0.55), c = F[idx]
                if idx >= n - 2 { p.disc(x, y, r, c, Swift.min(1, k * 3) * 0.85) }
                else {
                    p.circle(x, y, r, F[Swift.min(n - 1, idx + 2)])
                    p.circle(x - r * 0.16, y - r * 0.22, r * 0.78, c)
                    if r > 1.6 { p.circle(x, y - r * 0.9, r * 0.42, c) }
                    if idx <= 3 && r > 1.8 { p.circle(x - r * 0.28, y - r * 0.34, r * 0.36, F[Swift.max(0, idx - 1)]) }
                    if idx < 6 { p.glow(x, y, r * 2.4 + 2, c, 0.18 * k) }
                }
            case .brand:
                p.circle(x, y, 1.6, FX.hot[3])
                p.px(x, y, sin(t * 40 + q.seed) > 0 ? FX.hot[0] : FX.hot[1])
                p.px(x + 1, y, FX.hot[1])
                p.glow(x, y, 7, FX.hot[2], 0.45)
            case .grit:
                if k > 0.25 || k * 4 > 0.5 {
                    p.px(x, y, q.col)
                    if q.size >= 2 { p.px(x + 1, y, q.col); p.px(x, y + 1, FX.scale(q.col, 0.8)); p.px(x + 1, y + 1, FX.scale(q.col, 0.7)) }
                }
            case .ember:
                let c = k > 0.6 ? sparks[0] : k > 0.3 ? sparks[1] : sparks[2]
                if k < 0.25 && sin(t * 40 + q.seed) < 0 { break }
                p.px(x, y, c)
                if q.size > 1.5 { p.px(x, y + 1, sparks[sparks.count - 1]) }
                p.glow(x, y, 3 + q.size, c, 0.35 * k)
            case .drop:
                // A streak a few pixels long along its fall, lighter at the head.
                let L = Swift.min(5, 2 + sp / 120)
                p.line(x - ux * L, y - uy * L, x - ux, y - uy, FX.scale(q.col, 0.8), 0.85)
                p.dot(x, y, q.col)
            case .leaf:
                p.dot(x, y, q.col)
                if q.size > 1.2 { p.dot(x + (sin(t * 6 + q.seed) > 0 ? 1 : -1), y, FX.scale(q.col, 0.75)) }
            case .star:
                let tw = 0.6 + 0.4 * sin(t * (8 + FX.mod(q.seed, 5)) + q.seed)
                if q.size < 1 {
                    if tw * k > 0.25 { p.px(x, y, tw > 0.8 ? FX.white : q.col) }
                    p.glow(x, y, 3, q.col, 0.4 * k * tw)
                    break
                }
                FX.sparkle(p, x, y, q.size * tw * Swift.min(1, k * 3), q.col, FX.scale(q.col, 0.75), 0.5 * k * tw)
            }
        }
    }
}

/// Little fires burning where something landed: they feed fire puffs into a particle system.
public final class FXBlazes {
    public struct Blaze { public var x: Double, y: Double, life: Double, max: Double, acc: Double, power: Double }
    public let ps: FXParticles
    public var list: [Blaze] = []
    public init(_ ps: FXParticles) { self.ps = ps }
    public var count: Int { list.count }
    public func add(_ x: Double, _ y: Double, _ life: Double, _ power: Double) {
        list.append(Blaze(x: x, y: y, life: life, max: life, acc: ps.R.next(), power: power))
    }
    public func update(_ dt: Double) {
        let R = ps.R
        var i = list.count - 1
        while i >= 0 {
            defer { i -= 1 }
            var b = list[i]
            b.life -= dt
            if b.life <= 0 { list.remove(at: i); continue }
            let k = b.life / b.max, intensity = b.power * (k > 0.7 ? 1 : 0.35 + (k / 0.7) * 0.65)
            b.acc += dt * (6 + 16 * intensity)
            while b.acc > 1 {
                let s = R.range(1.2, 2.8) * intensity
                ps.spawn(.fire, b.x + R.range(-1.5, 1.5), b.y - s * 0.6, R.range(-6, 6), R.range(-30, -12), R.range(0.28, 0.6), 0, s, 0,
                         FXFlag.back | (R.chance(0.3) ? FXFlag.smokes : 0))
                if R.chance(0.06) { ps.spawn(.ember, b.x, b.y - 1.5, R.range(-15, 15), R.range(-45, -15), R.range(0.6, 1.4), FX.hot[2], 1, 0, FXFlag.back) }
                b.acc -= 1
            }
            list[i] = b
        }
    }
    public func drawBack(_ p: Painter) {
        for b in list {
            let k = b.life / b.max
            p.px(b.x, b.y, k > 0.4 ? (sin(b.life * 31 + b.x) > 0 ? FX.hot[1] : FX.hot[2]) : FX.hot[3])
            p.glow(b.x, b.y, 6 + 5 * k * b.power, FX.hot[2], 0.3 * k * b.power)
        }
    }
}

/// Rigid debris that tumbles, bounces and settles.
public final class FXBits {
    public enum Kind { case shard, chunk, drip }
    public struct Bit {
        public var kind: Kind = .shard, x = 0.0, y = 0.0, vx = 0.0, vy = 0.0, a = 0.0, va = 0.0, s = 1.0
        public var c: FXColor = FX.white, ramp: [FXColor]? = nil, g = 1.0, drag = 0.0, bounce = 0.0, rest = false
        public var life = 1.0, max = 1.0
        public init(kind: Kind = .shard, x: Double = 0, y: Double = 0, vx: Double = 0, vy: Double = 0, a: Double = 0, va: Double = 0,
                    s: Double = 1, c: FXColor = FX.white, ramp: [FXColor]? = nil, g: Double = 1, drag: Double = 0, bounce: Double = 0, life: Double = 1) {
            self.kind = kind; self.x = x; self.y = y; self.vx = vx; self.vy = vy; self.a = a; self.va = va; self.s = s
            self.c = c; self.ramp = ramp; self.g = g; self.drag = drag; self.bounce = bounce; self.life = life; self.max = life
        }
    }
    public var list: [Bit] = []
    public var ground: (Double) -> Double
    public init(ground: ((Double) -> Double)? = nil) { self.ground = ground ?? { _ in .infinity } }
    public var count: Int { list.count }
    public func add(_ b: Bit) { var b = b; b.max = b.life; list.append(b) }
    public func update(_ dt: Double) {
        var i = list.count - 1
        while i >= 0 {
            defer { i -= 1 }
            var b = list[i]
            b.life -= dt
            if b.life <= 0 { list.remove(at: i); continue }
            if b.rest { list[i] = b; continue }
            b.vy += FX.gravity * b.g * dt
            b.vx -= b.vx * b.drag * dt
            b.vy -= b.vy * b.drag * dt
            b.x += b.vx * dt
            b.y += b.vy * dt
            b.a += b.va * dt
            let floor = ground(b.x), sp = b.vy
            if b.g <= 0 || b.y < floor || sp <= 0 { list[i] = b; continue }
            b.y = floor - 0.01
            if b.kind == .drip { b.life = 0 }
            else if b.bounce > 0 && sp > 70 { b.vy = -sp * b.bounce; b.vx *= 0.7; b.va *= 0.6 }
            else { b.rest = true; b.vx = 0; b.vy = 0 }
            list[i] = b
        }
    }
    static let chunkRamp = ["#1c2030", "#3a4a66", "#6e86a8", "#a8c0dc", "#e8f2ff"].map(FX.hex)
    public func draw(_ p: Painter) {
        for b in list {
            let a = Swift.min(1, b.life / 0.4), ca = cos(b.a), sa = sin(b.a)
            switch b.kind {
            case .shard:
                var d = -b.s / 2
                while d <= b.s / 2 { p.dot(b.x + ca * d, b.y + sa * d, d > b.s / 2 - 0.6 ? FX.white : b.c, a); d += 0.5 }
            case .drip:
                p.dot(b.x, b.y, b.c, a)
                p.dot(b.x, b.y - 1, b.c, a * 0.5)
            case .chunk:
                let R = b.ramp ?? Self.chunkRamp, n = R.count
                let x = FX.round(b.x), y = FX.round(b.y), r = Int(FX.ceil(b.s)) + 1
                for py in -r...r {
                    for px in -r...r {
                        let u = (Double(px) + 0.5) * ca + (Double(py) + 0.5) * sa, v = -(Double(px) + 0.5) * sa + (Double(py) + 0.5) * ca
                        let d = abs(u) / b.s + abs(v) / (b.s * 0.62)
                        if d > 1.3 { continue }
                        p.dot(x + Double(px), y + Double(py), d > 1 ? R[0] : v < 0 ? (u < 0 ? R[n - 1] : R[n - 2]) : u < 0 ? R[n - 3] : R[Swift.max(1, n - 4)], a)
                    }
                }
            }
        }
    }
}

/// Lights that flare and die.
public final class FXLights {
    public struct Light { public var x: Double, y: Double, r: Double, color: FXColor, k: Double, life: Double, max: Double }
    public var list: [Light] = []
    public init() {}
    public func add(_ x: Double, _ y: Double, _ r: Double, _ color: FXColor, _ k: Double, _ life: Double) {
        list.append(Light(x: x, y: y, r: r, color: color, k: k, life: life, max: life))
    }
    public func update(_ dt: Double) {
        var i = list.count - 1
        while i >= 0 { list[i].life -= dt; if list[i].life <= 0 { list.remove(at: i) }; i -= 1 }
    }
    public func draw(_ p: Painter) {
        for l in list {
            let k = l.life / l.max
            p.glow(l.x, l.y, l.r * (0.55 + 0.45 * k), l.color, l.k * k * k)
        }
    }
}

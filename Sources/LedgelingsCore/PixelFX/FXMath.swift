// Numbers, easing, randomness, noise and colours for the effects: a port of pixelfx's core
// (https://github.com/patch-gg/pixelfx, MIT, see THIRD-PARTY-NOTICES.md), kept to the same
// arithmetic so an effect drawn here at time t is the same picture pixelfx draws. Where JavaScript
// rounds, truncates or wraps a number its own way, the helpers below do it the JavaScript way.

import Foundation

/// The effects' toolkit: everything an effect draws with lives under this name.
public enum FX {
    public static let tau = Double.pi * 2

    // MARK: JavaScript's number rules

    /// `x | 0`: truncated toward zero and wrapped to 32 bits, NaN and infinity to 0.
    @inline(__always) public static func i32(_ x: Double) -> Int32 {
        guard x.isFinite else { return 0 }
        let t = x.rounded(.towardZero)
        if t >= -2_147_483_648 && t <= 2_147_483_647 { return Int32(t) }
        let m = t.truncatingRemainder(dividingBy: 4_294_967_296)
        let u = m < 0 ? m + 4_294_967_296 : m
        return Int32(bitPattern: UInt32(u))
    }
    /// `x & 255` for a double, as JavaScript reads it.
    @inline(__always) public static func byte(_ x: Double) -> UInt32 { UInt32(bitPattern: i32(x)) & 255 }
    /// `Math.round`: halves go up, toward positive infinity.
    @inline(__always) public static func round(_ x: Double) -> Double { (x + 0.5).rounded(.down) }
    @inline(__always) public static func floor(_ x: Double) -> Double { x.rounded(.down) }
    @inline(__always) public static func ceil(_ x: Double) -> Double { x.rounded(.up) }
    /// `a % b` on doubles: the sign of a.
    @inline(__always) public static func mod(_ a: Double, _ b: Double) -> Double { a.truncatingRemainder(dividingBy: b) }
    /// `Math.min`/`Math.max` of a list.
    @inline(__always) public static func min(_ a: Double, _ b: Double) -> Double { a < b ? a : b }
    @inline(__always) public static func max(_ a: Double, _ b: Double) -> Double { a > b ? a : b }

    // MARK: Numbers and easing

    @inline(__always) public static func clamp(_ x: Double, _ a: Double = 0, _ b: Double = 1) -> Double { x < a ? a : x > b ? b : x }
    @inline(__always) public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    @inline(__always) public static func invLerp(_ a: Double, _ b: Double, _ x: Double) -> Double { b == a ? 0 : (x - a) / (b - a) }
    @inline(__always) public static func remap(_ x: Double, _ a0: Double, _ a1: Double, _ b0: Double, _ b1: Double) -> Double {
        lerp(b0, b1, invLerp(a0, a1, x))
    }
    @inline(__always) public static func fract(_ x: Double) -> Double { x - floor(x) }
    @inline(__always) public static func wrap(_ x: Double, _ m: Double) -> Double { mod(mod(x, m) + m, m) }
    /// Progress 0...1 of t through the window [t0, t1]: 0 before it, 1 after it.
    @inline(__always) public static func seg(_ t: Double, _ t0: Double, _ t1: Double) -> Double { clamp((t - t0) / (t1 - t0)) }
    /// Hermite smoothstep of x between e0 and e1.
    @inline(__always) public static func smooth(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = seg(x, e0, e1)
        return t * t * (3 - 2 * t)
    }
    /// 0 → 1 → 0 over [t0, t1], a sine bump.
    @inline(__always) public static func bump(_ t: Double, _ t0: Double, _ t1: Double) -> Double {
        t <= t0 || t >= t1 ? 0 : sin(Double.pi * seg(t, t0, t1))
    }
    @inline(__always) public static func pingpong(_ x: Double) -> Double { 1 - abs(wrap(x, 2) - 1) }
    @inline(__always) public static func dist(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Double { hypot(x1 - x0, y1 - y0) }

    /// Easing curves: 0...1 in, 0...1 out (back and elastic overshoot).
    public enum Ease {
        public static func linear(_ t: Double) -> Double { t }
        public static func inQuad(_ t: Double) -> Double { t * t }
        public static func outQuad(_ t: Double) -> Double { 1 - (1 - t) * (1 - t) }
        public static func inOutQuad(_ t: Double) -> Double { t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2 }
        public static func inCubic(_ t: Double) -> Double { t * t * t }
        public static func outCubic(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
        public static func inOutCubic(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
        public static func inQuart(_ t: Double) -> Double { t * t * t * t }
        public static func outQuart(_ t: Double) -> Double { 1 - pow(1 - t, 4) }
        public static func inExpo(_ t: Double) -> Double { t <= 0 ? 0 : pow(2, 10 * t - 10) }
        public static func outExpo(_ t: Double) -> Double { t >= 1 ? 1 : 1 - pow(2, -10 * t) }
        public static func inSine(_ t: Double) -> Double { 1 - cos((t * Double.pi) / 2) }
        public static func outSine(_ t: Double) -> Double { sin((t * Double.pi) / 2) }
        public static func inOutSine(_ t: Double) -> Double { -(cos(Double.pi * t) - 1) / 2 }
        public static func inBack(_ t: Double, _ s: Double = 1.70158) -> Double {
            t <= 0 ? 0 : t >= 1 ? 1 : (s + 1) * t * t * t - s * t * t
        }
        public static func outBack(_ t: Double, _ s: Double = 1.70158) -> Double {
            t <= 0 ? 0 : t >= 1 ? 1 : 1 + (s + 1) * pow(t - 1, 3) + s * pow(t - 1, 2)
        }
        public static func outElastic(_ t: Double) -> Double {
            t <= 0 ? 0 : t >= 1 ? 1 : pow(2, -10 * t) * sin((t * 10 - 0.75) * ((2 * Double.pi) / 3)) + 1
        }
        public static func outBounce(_ t: Double) -> Double {
            let n = 7.5625, d = 2.75
            if t < 1 / d { return n * t * t }
            if t < 2 / d { let u = t - 1.5 / d; return n * u * u + 0.75 }
            if t < 2.5 / d { let u = t - 2.25 / d; return n * u * u + 0.9375 }
            let u = t - 2.625 / d
            return n * u * u + 0.984375
        }
    }

    // MARK: Randomness and noise

    @inline(__always) static func imul(_ a: UInt32, _ b: UInt32) -> UInt32 { a &* b }

    /// 32-bit integer hash of any number of integers (JavaScript's `n | 0` first).
    public static func hash(_ ns: Double...) -> UInt32 { hash(ns) }
    public static func hash(_ ns: [Double]) -> UInt32 {
        var h: UInt32 = 0x9e3779b9
        for n in ns {
            h = imul(h ^ UInt32(bitPattern: i32(n)), 0x85ebca6b)
            h ^= h >> 13
            h = imul(h, 0xc2b2ae35)
            h ^= h >> 16
        }
        return h
    }
    /// A repeatable random number in [0, 1) from integers (seed, particle index, which value...).
    public static func rand(_ ns: Double...) -> Double { Double(hash(ns)) / 4_294_967_296 }

    /// A generator for one particle: `rng(seed, i)` gives the same numbers every frame.
    public static func rng(_ ns: Double...) -> Rng { Rng(seed: hash(ns)) }

    /// Smooth 1D value noise in [-1, 1].
    public static func noise(_ x: Double, _ seed: Double = 0) -> Double {
        let i = floor(x), f = x - i, u = f * f * (3 - 2 * f)
        return lerp(rand(i, seed), rand(i + 1, seed), u) * 2 - 1
    }
    /// Smooth 2D value noise in [-1, 1].
    public static func noise2(_ x: Double, _ y: Double, _ seed: Double = 0) -> Double {
        let ix = floor(x), iy = floor(y), fx = x - ix, fy = y - iy
        let ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy)
        let a = rand(ix, iy, seed), b = rand(ix + 1, iy, seed), c = rand(ix, iy + 1, seed), d = rand(ix + 1, iy + 1, seed)
        return lerp(lerp(a, b, ux), lerp(c, d, ux), uy) * 2 - 1
    }
    /// Fractal 2D noise in about [-1, 1].
    public static func fbm(_ x: Double, _ y: Double, _ seed: Double = 0, _ octaves: Int = 3) -> Double {
        var s = 0.0, a = 0.5, n = 0.0, x = x, y = y
        for o in 0..<octaves {
            s += noise2(x, y, seed + Double(o) * 101) * a
            n += a
            x *= 2.03
            y *= 2.03
            a *= 0.5
        }
        return s / n
    }
    /// 2D value noise whose lattice repeats every px cells in x and py cells in y (0: no repeat).
    public static func tileNoise(_ x: Double, _ y: Double, _ px: Double = 0, _ py: Double = 0, _ seed: Double = 0) -> Double {
        let ix = floor(x), iy = floor(y), fx = x - ix, fy = y - iy
        let ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy)
        let x0 = px != 0 ? wrap(ix, px) : ix, x1 = px != 0 ? wrap(ix + 1, px) : ix + 1
        let y0 = py != 0 ? wrap(iy, py) : iy, y1 = py != 0 ? wrap(iy + 1, py) : iy + 1
        let a = rand(x0, y0, seed), b = rand(x1, y0, seed), c = rand(x0, y1, seed), d = rand(x1, y1, seed)
        return lerp(lerp(a, b, ux), lerp(c, d, ux), uy) * 2 - 1
    }
    /// Fractal tileNoise: every octave keeps the repeat, so scrolled fields still loop.
    public static func tileFbm(_ x: Double, _ y: Double, _ px: Double = 0, _ py: Double = 0, _ seed: Double = 0, _ octaves: Int = 3) -> Double {
        var s = 0.0, a = 0.5, n = 0.0, k = 1.0
        for o in 0..<octaves {
            s += tileNoise(x * k, y * k, px * k, py * k, seed + Double(o) * 101) * a
            n += a
            a *= 0.5
            k *= 2
        }
        return s / n
    }
    /// Noise that loops: the same value at phase 0 and phase 1.
    public static func loopNoise(_ phase: Double, _ radius: Double = 1, _ seed: Double = 0) -> Double {
        let a = phase * tau
        return noise2(cos(a) * radius + 50, sin(a) * radius + 50, seed)
    }
}

/// Seeded random generator (mulberry32), number for number the same as pixelfx's. A class, as in
/// JavaScript: an effect and its particle system share one and draw from it in turn.
public final class Rng {
    public var s: UInt32
    public init(seed: UInt32) { s = seed == 0 ? 1 : seed }
    /// `new Rng(seed)` with a JavaScript number: `seed >>> 0 || 1`.
    public convenience init(_ seed: Double = 1) { self.init(seed: UInt32(bitPattern: FX.i32(seed))) }
    public func next() -> Double {
        s = s &+ 0x6d2b79f5
        var t = s
        t = FX.imul(t ^ (t >> 15), t | 1)
        t ^= t &+ FX.imul(t ^ (t >> 7), t | 61)
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
    public func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
    public func int(_ a: Double, _ b: Double) -> Double { FX.floor(range(a, b + 1)) }
    public func chance(_ p: Double) -> Bool { next() < p }
    public func sign() -> Double { next() < 0.5 ? -1 : 1 }
    public func pick<T>(_ list: [T]) -> T { list[Int(FX.floor(next() * Double(list.count)))] }
    /// Roughly normal, mean 0, sd 1.
    public func gauss() -> Double { (next() + next() + next() + next() - 2) * 1.732 }
}

// MARK: Colours

/// Colours are 32-bit numbers laid out like the bytes of an RGBA image (R in the low byte), as in pixelfx.
/// 0 means "nothing".
public typealias FXColor = UInt32

extension FX {
    @inline(__always) public static func rgb(_ r: Double, _ g: Double, _ b: Double) -> FXColor {
        (255 << 24) | (byte(b) << 16) | (byte(g) << 8) | byte(r)
    }
    @inline(__always) public static func red(_ c: FXColor) -> Double { Double(c & 255) }
    @inline(__always) public static func green(_ c: FXColor) -> Double { Double((c >> 8) & 255) }
    @inline(__always) public static func blue(_ c: FXColor) -> Double { Double((c >> 16) & 255) }

    /// "#rgb" or "#rrggbb" to a colour.
    public static func hex(_ h: String) -> FXColor {
        var s = h.hasPrefix("#") ? String(h.dropFirst()) : h
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let v = UInt32(s.prefix(6), radix: 16) ?? 0
        return rgb(Double((v >> 16) & 255), Double((v >> 8) & 255), Double(v & 255))
    }
    public static func ramp(_ list: [String]) -> [FXColor] { list.map(hex) }

    /// Linear mix of two colours.
    @inline(__always) public static func mix(_ a: FXColor, _ b: FXColor, _ t: Double) -> FXColor {
        let t = clamp(t)
        return rgb(red(a) + (red(b) - red(a)) * t, green(a) + (green(b) - green(a)) * t, blue(a) + (blue(b) - blue(a)) * t)
    }
    /// A colour's brightness times k.
    @inline(__always) public static func scale(_ c: FXColor, _ k: Double) -> FXColor {
        rgb(min(255, red(c) * k), min(255, green(c) * k), min(255, blue(c) * k))
    }
    /// Perceived brightness 0...1.
    @inline(__always) public static func luma(_ c: FXColor) -> Double {
        (0.299 * red(c) + 0.587 * green(c) + 0.114 * blue(c)) / 255
    }
    /// A ramp resampled to exactly n steps, its ends kept.
    public static func fit(_ r: [FXColor], _ n: Int) -> [FXColor] {
        if r.count == n { return r }
        return (0..<n).map { i in r[Int(round(Double(i * (r.count - 1)) / Double(Swift.max(1, n - 1))))] }
    }
    /// The ramp step for t in 0...1, no blending.
    @inline(__always) public static func at(_ r: [FXColor], _ t: Double) -> FXColor {
        r[Int(clamp(floor(t * Double(r.count)), 0, Double(r.count - 1)))]
    }
    /// Blended colour along a ramp (for light, where smooth is right).
    public static func blend(_ r: [FXColor], _ t: Double) -> FXColor {
        let x = clamp(t) * Double(r.count - 1), i = Swift.min(r.count - 2, Int(floor(x)))
        return mix(r[i], r[i + 1], x - Double(i))
    }

    public static let white = hex("#ffffff")
    public static let black = hex("#000000")
    public static let ink = hex("#0b0a10")

    /// pixelfx's named ramps, dark to bright.
    public static let pal: [String: [String]] = [
        "fire": ["#1f0b10", "#4a1118", "#8c1d1c", "#cc3a1a", "#f2701f", "#ffae35", "#ffe27a", "#fff8d6"],
        "smoke": ["#0e0c12", "#1d1a22", "#2e2a35", "#433e4b", "#5c5664", "#7b7484", "#a39cab"],
        "dust": ["#1c1610", "#33281c", "#4f3f2c", "#6e5a40", "#927a58", "#b89f78", "#dcc8a2"],
        "ice": ["#0c1430", "#162c5c", "#1f4f94", "#2f7fcc", "#58b4ec", "#9bdcff", "#d8f4ff", "#ffffff"],
        "electric": ["#0a0f2e", "#172a78", "#2550d0", "#3f8cff", "#7cc8ff", "#c8f0ff", "#ffffff"],
        "volt": ["#24160a", "#5e3a0c", "#a8680f", "#e8a218", "#ffd23c", "#fff08a", "#ffffff"],
        "holy": ["#2a1c08", "#5a3e10", "#9a6c18", "#d8a428", "#ffd84a", "#fff09a", "#fffbe6", "#ffffff"],
        "heal": ["#08201a", "#0f3f2c", "#17663e", "#24924e", "#3ec466", "#7ee88a", "#c8ffc4", "#ffffff"],
        "arcane": ["#140a26", "#2b1252", "#481c88", "#6b2cc0", "#9a48ec", "#c684ff", "#ecc8ff", "#ffffff"],
        "shadow": ["#050308", "#0f0a18", "#1c1230", "#2c1a4a", "#432468", "#5e3290", "#8048b8", "#a970e0"],
        "earth": ["#140e0a", "#2a1e14", "#47321e", "#69492a", "#8e6638", "#b88a52", "#dcb47c"],
        "stone": ["#0e0e12", "#1c1c24", "#2c2c38", "#42424f", "#5c5c6b", "#7d7d8c", "#a4a4b2", "#d0d0da"],
        "gold": ["#1e1206", "#4a2c08", "#86520c", "#c48412", "#f0b424", "#ffe066", "#fff6c4", "#ffffff"],
        "leaf": ["#0c1a0e", "#163418", "#225224", "#357530", "#4f9a3a", "#7cc048", "#b4e070", "#e4ffb0"],
        "wood": ["#160c06", "#2e1a0c", "#4a2c14", "#6a421e", "#8e5c2c", "#b47c40", "#d8a464"],
        "candy": ["#ff4a5a", "#ff9a2a", "#ffe03c", "#5ad84a", "#3cc8ff", "#7a6cff", "#f53cd1"],
        "night": ["#07060d", "#0c0a18", "#131026", "#1b1734", "#241f44", "#2f2956"],
    ]
    public static func PAL(_ name: String) -> [FXColor] { ramp(pal[name] ?? []) }
}

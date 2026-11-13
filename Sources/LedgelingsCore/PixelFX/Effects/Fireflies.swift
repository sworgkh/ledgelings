// Fireflies wander over a meadow at night, each glowing up and fading on its own rhythm, trailing light and
// lighting the grass tips beneath them. pixelfx's `weather/fireflies` (MIT), the firefly adapted from Sprite
// Fusion's open-source fireflies (https://www.spritefusion.com/pixel-art-vfx/fireflies, MIT, Hugo Duprez).

import Foundation

final class FXFireflies: FXEffect, FXBackdropped {
    static let meta = FXMeta(id: "weather/fireflies", size: (320, 180), origin: (160, 170), duration: 12, loop: true,
                             palette: ["#2a3a10", "#5a7a1a", "#9ad02a", "#d6ff5a", "#f4ffb8", "#ffffff"], seed: 2)
    static let D = 12.0
    static let grassRamp = FX.fit(FX.ramp(["#070f0b", "#0c1a12", "#13281a", "#1d3a24", "#2b5232", "#3f6e40"]), 6)

    let o: FXOptions
    let C: [FXColor], G: [FXColor]
    /// false: no night haze over the whole canvas (drawn over the desktop); the grass and the fireflies stay.
    var backdrop = true
    /// How many of the 32 fly (Settings › Weather & Sky: a sparse few), spread over the near and far ones.
    var flies = 32
    init(_ o: FXOptions) { self.o = o; C = FX.fit(o.palette, 6); G = Self.grassRamp }

    /// The fireflies flying, picked evenly from far to near.
    func swarm(_ S: Double, _ t: Double) -> [Fly] {
        let n = Swift.max(0, Swift.min(32, flies))
        return (0..<n).map { k in Self.fly(S, n == 32 ? k : Int(Double(k) * 32 / Double(n) + 32 / Double(n) / 2), t) }
    }

    @inline(__always) static func cyc(_ t: Double, _ n: Double, _ ph: Double = 0) -> Double { (FX.tau * n * t) / D + ph }

    /// A firefly's path and glow, both whole cycles a loop. depth 0 far...2 near.
    struct Fly {
        let i: Double, depth: Int, k: Double, cx: Double, cy: Double, ax: Double, ay: Double, n1: Double, n2: Double, p1: Double, p2: Double
        let glow: Double
        func pos(_ tt: Double) -> (Double, Double) {
            (cx + ax * sin(FXFireflies.cyc(tt, n1, p1)) + 10 * k * FX.loopNoise(tt / FXFireflies.D, 1.5, i * 3),
             cy + ay * sin(FXFireflies.cyc(tt, n2, p2)) + 6 * k * FX.loopNoise(tt / FXFireflies.D, 1.5, i * 3 + 1))
        }
    }
    static func fly(_ S: Double, _ i: Int, _ t: Double) -> Fly {
        let di = Double(i)
        let R = { (n: Double) in FX.rand(S, di, n) }
        let depth = i < 14 ? 0 : i < 26 ? 1 : 2, k = [0.5, 0.8, 1][depth]
        let cx = -150 + R(1) * 300, cy = -16 - R(2) * (depth == 2 ? 70 : 130)
        let ax = (14 + R(3) * 26) * k, ay = (8 + R(4) * 14) * k, n1 = 1 + FX.floor(R(5) * 2), n2 = 1 + FX.floor(R(6) * 3)
        // its rhythm: a quick rise, a hold, a slow fade, dark; some flash twice
        let per = D / (3 + FX.floor(R(9) * 4)), u = FX.mod(FX.mod(t / per + R(10), 1) + 1, 1), two = R(11) < 0.35
        let pulse = { (v: Double) -> Double in v < 0.06 ? v / 0.06 : v < 0.14 ? 1 : v < 0.4 ? 1 - (v - 0.14) / 0.26 : 0 }
        let glow = Swift.max(pulse(u), two ? pulse(u - 0.22) * 0.8 : 0)
        return Fly(i: di, depth: depth, k: k, cx: cx, cy: cy, ax: ax, ay: ay, n1: n1, n2: n2, p1: R(7) * FX.tau, p2: R(8) * FX.tau, glow: glow)
    }

    func drawBack(_ p: Painter, _ t: Double) {
        let q = FXWeather.Clip(p, Self.meta), S = o.seed, G = self.G
        // a cool night haze, so the sky's stars don't read as fireflies
        if backdrop {
            FXWeather.rows(p, Self.meta, -170, 9) { y, R in
                let k = (y + 170) / 180
                R.fill(FX.mix(G[0], G[1], k), 0.48 + 0.14 * k, blend: true)
            }
        }
        let flies = swarm(S, t)
        grass(q, t, S, flies, false)
        for f in flies where f.depth < 2 { firefly(q, t, f) }
    }

    func draw(_ p: Painter, _ t: Double) {
        let q = FXWeather.Clip(p, Self.meta), S = o.seed
        let flies = swarm(S, t)
        grass(q, t, S, flies, true)
        for f in flies where f.depth == 2 { firefly(q, t, f) }
    }

    func firefly(_ q: FXWeather.Clip, _ t: Double, _ f: Fly) {
        let C = self.C
        let (x, y) = f.pos(t), g = f.glow, X = FX.round(x), Y = FX.round(y)
        if f.depth == 0 {
            if g < 0.08 { return }
            q.dot(X, Y, g > 0.6 ? C[4] : C[3], Swift.min(1, g * 1.6))
            q.glow(x, y, 6, C[2], 0.45 * g)
            return
        }
        // a short trail of light where it has just been, while it's lit
        if g > 0.3 {
            for j in 1...4 {
                let dj = Double(j), (tx, ty) = f.pos(t - dj * 0.05)
                q.dot(tx, ty, C[2], (g - 0.3) * (1 - dj / 5) * 1.3)
            }
        }
        if f.depth == 1 {
            q.px(X, Y, g > 0.5 ? C[5] : g > 0.15 ? C[3] : C[1])
            if g > 0.4 { q.px(X, Y + 1, C[2]) }
            q.glow(x, y, 9, C[2], 0.5 * g)
            q.glow(x, y, 3, C[4], 0.5 * g)
            return
        }
        // a close one: a dark body, wings a blur above it, a lantern at its tail; a glint at the peak
        let nx = f.pos(t + 0.05).0, dir: Double = nx >= x ? 1 : -1, beat = FX.mod(FX.floor(t * 30), 2)
        let wing = FX.mix(C[1], FX.white, 0.4)
        q.px(X + dir, Y, C[0])
        q.px(X + dir * 2, Y, C[0])
        q.dot(X, Y - 1 - beat, wing, 0.7)
        q.dot(X + dir, Y - 1 - beat, wing, 0.7)
        q.px(X, Y, g > 0.3 ? C[5] : C[1])
        q.px(X - dir, Y, g > 0.5 ? C[4] : g > 0.15 ? C[3] : C[1])
        if g > 0.6 { q.px(X - dir, Y + 1, C[3]) }
        if g > 0.7 { for (dx, dy) in [(0.0, -2.0), (0, 2), (-2, 0), (2, 0)] { q.dot(X - dir + dx, Y + dy, C[3], (g - 0.7) * 3) } }
        q.glow(x, y, 28, C[2], 0.45 * g)
        q.glow(x, y, 10, C[4], 0.5 * g)
        q.glow(x, y, 4, C[5], 0.5 * g)
    }

    /// The meadow: blades in two rows (the front row drawn over the low fireflies), swaying as the breeze rolls
    /// across, a few seed heads; blade tips near a lit firefly catch its light.
    func grass(_ q: FXWeather.Clip, _ t: Double, _ S: Double, _ flies: [Fly], _ front: Bool) {
        let C = self.C, G = self.G
        let lit = flies.filter { $0.glow > 0.25 && $0.depth > 0 }.map { f -> (Double, Double, Double) in let (x, y) = f.pos(t); return (x, y, f.glow) }
        let n = front ? 150 : 230, dn = Double(n), sd = S * 3 + (front ? 1 : 0)
        for i in 0..<n {
            let di = Double(i)
            let R = { (k: Double) in FX.rand(sd, di, k) }
            let x = -162 + (di + R(1)) * (324 / dn), h = (front ? 4 : 5) + R(2) * (front ? 8 : 11) + (R(3) < 0.1 ? 6 : 0)
            let base = (front ? 9 : 2) - R(4) * 3
            let sway = (1.2 + R(5)) * sin(Self.cyc(t, 2, -x * 0.03) + R(6)) + 0.6 * sin(Self.cyc(t, 5, x * 0.07))
            let tone = front ? 1 + Int(FX.floor(R(7) * 3)) : 1 + Int(FX.floor(R(7) * 2))
            var tipLight = 0.0
            for (fx, fy, g) in lit {
                let d = hypot(fx - (x + sway), fy - (base - h))
                if d < 28 { tipLight = Swift.max(tipLight, g * (1 - d / 28)) }
            }
            var r = 0.0
            while r < h {
                let u = r / h
                let c = u > 0.8 && tipLight > 0.2 ? (tipLight > 0.55 && u > 0.9 ? C[3] : C[2]) : u > 0.7 ? G[Swift.min(5, tone + 1)] : G[tone]
                q.px(x + sway * u * u, base - r, c)
                r += 1
            }
            if R(8) < 0.07 {
                let sx = x + sway, sy = base - h
                q.px(sx, sy - 1, tipLight > 0.2 ? C[3] : G[5])
                q.px(sx - 1, sy, G[4])
                q.px(sx + 1, sy, G[4])
            }
        }
    }
}

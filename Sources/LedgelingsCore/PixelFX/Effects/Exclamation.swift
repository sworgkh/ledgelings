// A bold ! springs up off the head, stretching as it shoots up and squashing as it lands; surprise ticks
// flick out, it wobbles, then pops away. pixelfx's `ui/exclamation` (MIT).

import Foundation

final class FXExclamation: FXEffect {
    static let meta = FXMeta(id: "ui/exclamation", size: (84, 104), origin: (42, 92), duration: 1.4, loop: false, palette: ["#2a1405", "#6a2e06", "#b85a0a", "#f08c14", "#ffc23a", "#ffe580", "#fff6c8", "#ffffff"], seed: 3)
    static let HEAD = -40.0, REST = -45.0, POP = 1.1
    let C: [FXColor]
    let R: Rng
    let ps: FXParticles
    let lights = FXLights()
    // the mark's foot: shot up off the head with a spring, so it overshoots and settles
    var my = HEAD, vy = -420.0, sq = 0.0, landed = false
    var t = 0.0, popped = false, sprung = false
    let end = meta.duration - 0.05

    init(_ o: FXOptions) {
        C = FX.fit(o.palette, 8)
        R = Rng(o.seed)
        ps = FXParticles(rng: R, sparks: [C[7], C[6], C[5], C[3]])
    }

    /// The mark: a bar tapering to its foot and a round dot, outlined, lit down its left side, turned by a.
    func bang(_ p: Painter, _ x: Double, _ y: Double, _ sx: Double, _ sy: Double, _ a: Double, _ white: Bool) {
        let C = self.C, ca = cos(a), sa = sin(a)
        let hw = { (V: Double) in 2.3 + (-V - 10) * 0.09 }
        let inBar = { (U: Double, V: Double) in V > -24 && V < -9.5 && abs(U) < hw(V) }
        let inDot = { (U: Double, V: Double) in hypot(U, V + 3.6) < 3.3 }
        let inside = { (U: Double, V: Double) in inBar(U, V) || inDot(U, V) }
        p.shade(x - 16, y - 34, x + 16, y + 6) { px, py, _ in
            let dx = px - x, dy = py - y, u = (dx * ca + dy * sa) / sx, v = (-dx * sa + dy * ca) / sy, ex = 1 / sx, ey = 1 / sy
            if !inside(u, v) { return inside(u - ex, v) || inside(u + ex, v) || inside(u, v - ey) || inside(u, v + ey) ? C[0] : 0 }
            if white { return FX.white }
            if inDot(u, v) { return hypot(u + 1.2, v + 4.8) < 1.2 ? FX.white : u + v + 3.6 < -0.5 ? C[6] : u + v + 3.6 < 1.5 ? C[5] : C[4] }
            let w = hw(v), q = (u + w) / (2 * w)
            if q < 0.28 { return v < -20 ? FX.white : C[7] }
            if q > 0.74 { return C[4] }
            return v < -18 ? C[6] : C[5]
        }
    }

    func update(_ dt: Double) {
        let C = self.C, R = self.R, HEAD = Self.HEAD, REST = Self.REST, POP = Self.POP
        t += dt
        if t < POP {
            // a stiff spring pulls it to its rest above the head
            vy += (-(my - REST) * 900 - vy * 14) * dt
            my += vy * dt
            if !landed && vy > 0 { landed = true; sq = 1 }
        }
        sq = Swift.max(0, sq - dt / 0.12)
        // it leaves the head with a little burst of light
        if !sprung && t >= 0.04 {
            sprung = true
            lights.add(0, HEAD - 4, 26, C[5], 0.6, 0.25)
            for i in 0..<8 {
                let an = -Double.pi / 2 + R.range(-1.3, 1.3), sp = R.range(40, 90)
                ps.spawn(.star, R.range(-4, 4), HEAD - 2, cos(an) * sp, sin(an) * sp, R.range(0.2, 0.4), R.pick([C[7], C[6], C[5]]), i % 3 != 0 ? 0.6 : 1.3)
            }
        }
        if !popped && t >= POP + 0.05 {
            popped = true
            lights.add(0, REST - 13, 28, C[5], 0.5, 0.2)
            for i in 0..<7 {
                let an = (Double(i) / 7) * FX.tau + R.range(-0.2, 0.2), sp = R.range(30, 60)
                ps.spawn(.star, cos(an) * 5, REST - 13 + sin(an) * 9, cos(an) * sp, sin(an) * sp, Swift.min(R.range(0.2, 0.35), end - t), R.pick([C[7], C[6], C[5]]), i % 3 != 0 ? 0.6 : 1.4)
            }
        }
        ps.update(dt)
        lights.update(dt)
    }

    func draw(_ p: Painter, _ tt: Double) {
        let C = self.C, k = t, REST = Self.REST
        // surprise ticks: three flick out each side on the spring, and again on a second beat
        for (t0, len) in [(0.04, 6.0), (0.48, 4.5)] {
            let u = (k - t0) / 0.24
            if u <= 0 || u >= 1 { continue }
            for s in [-1.0, 1.0] {
                for i in 0..<3 {
                    let an = -Double.pi / 2 + s * (0.55 + Double(i) * 0.42), r0 = 14 + 7 * FX.Ease.outCubic(u), L = len * sin(u * Double.pi) * (i == 1 ? 1 : 0.75)
                    let cx = 0.0, cy = REST - 13, ca = cos(an), sa = sin(an)
                    if L < 0.8 { continue }
                    p.line(cx + ca * r0, cy + sa * r0, cx + ca * (r0 + L), cy + sa * (r0 + L), { q in q < 0.5 ? FX.white : C[5] })
                }
            }
        }
        // the mark: stretched while it shoots up, squashed as it lands, wobbling, white on the pop
        let pu = (k - Self.POP) / 0.06
        if pu < 1 {
            let speed = Swift.min(1, abs(vy) / 420), up = vy < 0 ? speed : 0
            var sx = 1 - 0.3 * up + 0.3 * sq, sy = 1 + 0.45 * up - 0.28 * sq
            if k < 0.05 { sx *= k / 0.05; sy *= k / 0.05 }
            if pu > 0 { sx = 1 + 0.3 * pu; sy = sx }
            let wob = 0.28 * exp(-k * 4) * sin(k * 26), white = k < 0.06 || pu > 0
            if sx > 0.1 { bang(p, 0, my, sx, sy, wob, white) }
            p.glow(0, my - 13, 20, C[5], 0.35 + (white ? 0.3 : 0))
            if k > 0.6 && k < 0.85 { FX.sparkle(p, -3, my - 22, 3.5 * sin(((k - 0.6) / 0.25) * Double.pi), C[7], C[6], 0.4) }
        }
        ps.draw(p, nil)
        lights.draw(p)
    }
}

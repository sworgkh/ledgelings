// Haunted: violet smoke rises off the body in winding trails, a dark stain creeps up from the feet with a
// glowing edge, the eyes burn, a skull glitches in overhead. pixelfx's `status/cursed` (MIT); its soft lit
// smoke puffs and shaded, outlined skull adapt Sprite Fusion's open-source poison
// (https://www.spritefusion.com/pixel-art-vfx/poison), MIT, Copyright (c) 2026 Hugo Duprez.

import Foundation

final class FXCursed: FXEffect {
    static let meta = FXMeta(id: "status/cursed", size: (64, 84), origin: (32, 76), duration: 2.4, loop: true,
                             palette: ["#0c0612", "#1f0f2e", "#3a1a55", "#5e2a85", "#8a3fc0", "#b86ef0", "#e0b0ff", "#ffffff"], seed: 9)
    static let D = 2.4
    nonisolated(unsafe) static let skull = FXStatus.bitmap([
        "...#####...",
        ".#########.",
        "###########",
        "##eee#eee##",
        "##eEe#eEe##",
        "##eee#eee##",
        "#####.#####",
        ".####.####.",
        "..#######..",
        "..#.#.#.#..",
        "...#####...",
    ])
    // the skull's life in the loop: hidden, glitching in, hanging there, glitching out
    static let tIn = 0.5, hold = 0.75, tOut = 1.85, gone = 2.1
    let o: FXOptions
    let C: [FXColor]
    init(_ o: FXOptions) { self.o = o; C = FX.fit(o.palette, 8) }

    /// How high the stain has crept at column x (0 at the feet, 1 at the head): a slow tide with crawling tendrils.
    static func tide(_ t: Double) -> Double { 0.3 + 0.12 * sin((t / D) * FX.tau) }
    static func reach(_ x: Double, _ t: Double, _ seed: Double) -> Double { tide(t) + 0.13 * FX.tileFbm(x * 0.35, (t / D) * 4, 0, 4, seed, 2) }

    /// Smoke trails: each rises from a spot on the body as a ribbon of soft puffs that wind as they climb,
    /// swell, cool and thin.
    func trails(_ p: Painter, _ S: FXStatus.Shape, _ t: Double, _ front: Bool) {
        let C = self.C, a = o.actor, D = Self.D
        let spots: [(Double, Double)] = [(0.12, -1), (0.1, 1), (0.5, -1), (0.48, 1)]
        for (j, (q, side)) in spots.enumerated() {
            if (j % 2 == 0) != front { continue }
            let my = Int(FX.round(Double(S.h) * q)), (l, r) = my >= 0 && my < S.rows.count ? S.rows[my] : (0, 0)
            let fj = Double(j)
            let x0 = Double(a.x) + Double(side < 0 ? l : r + 1), y0 = Double(a.y) + Double(my), life = 1.6, n = 18
            for i in stride(from: n - 1, through: 0, by: -1) {
                let fi = Double(i)
                let age = FX.mod(FX.mod(t - (fi / Double(n)) * D - fj * 0.37, D) + D, D), tb = t - age, u = age / life
                if u >= 1 { continue }
                let sway = sin((tb / D) * FX.tau * 2 + fj * 1.7) * 4 * Swift.min(1, u * 1.6)
                let x = x0 + side * u * 7 + sway + (FX.rand(fi, fj, 71) - 0.5) * 2.5 * u, y = y0 - age * 19 - 5 * u * u
                let rad = (1.3 + 3.6 * (1 - pow(1 - u, 3))) * (0.7 + 0.6 * FX.rand(fi, fj, 72))
                let k = FX.smooth(0, 0.12, u) * (1 - FX.smooth(0.45, 1, u)) * (front ? 0.5 : 0.62)
                let c = FX.mix(FX.rand(fi, fj, 70) < 0.5 ? C[4] : FX.mix(C[4], C[3], 0.4), C[1], u * 0.85)
                p.disc(x, y, rad * 1.08, c, k * 0.4)
                p.disc(x + rad * 0.05, y + rad * 0.08, rad * 0.76, c, k * 0.55)
                p.disc(x - rad * 0.22, y - rad * 0.3, rad * 0.48, FX.mix(c, C[6], 0.25), k * 0.38 * (1 - u * 0.6))
                if i % 3 == 0 { p.glow(x, y, rad * 1.6, C[4], 0.08 * k) }
            }
        }
    }

    func drawBack(_ p: Painter, _ t: Double) {
        let C = self.C, a = o.actor, S = FXStatus.shape(a)
        // the stain pooling round the feet, its rim glowing
        let (fl, fr) = S.rows[S.h - 1], cx = Double(a.x) + Double(fl + fr + 1) / 2, rx = Double(fr - fl) / 2 + 7 + 2 * sin((t / Self.D) * FX.tau)
        var x = FX.floor(cx - rx - 1)
        while x <= cx + rx + 1 {
            defer { x += 1 }
            let q = abs(x + 0.5 - cx) / rx, n = FX.rand(x, 31)
            if q > 1 + n * 0.12 { continue }
            p.px(x, 0, q > 0.8 ? C[4] : n < 0.2 ? C[3] : C[2])
            if q < 0.85 { p.px(x, 1, C[1]) }
            if q < 0.55 && n < 0.7 { p.px(x, 2, C[1]) }
        }
        p.shade(cx - rx - 6, -4, cx + rx + 6, 5) { x, y, out in
            let d = hypot((x - cx) / (rx + 6), y / 4)
            if d < 1 { out.l = C[4]; out.k = 0.2 * (1 - d) * (1 - d) }
            return 0
        }
        trails(p, S, t, false)
    }

    func draw(_ p: Painter, _ t: Double) {
        let C = self.C, a = o.actor, S = FXStatus.shape(a), H = Double(S.h), ax = Double(a.x), ay = Double(a.y), seed = o.seed
        // the stain on the body: everything below the creeping line drowned in violet, the line itself burning
        for (mx, my) in S.body {
            let c = FXStatus.colorAt(a, mx, my), up = 1 - (Double(my) + 0.5) / H, lv = Self.reach(Double(mx), t, seed)
            if up > lv + 0.035 { continue }
            let x = ax + Double(mx), y = ay + Double(my)
            if up > lv - 0.02 { p.px(x, y, C[6]) }
            else if up > lv - 0.06 { p.px(x, y, C[4]) }
            else { p.px(x, y, FX.mix(C[1], C[3], FX.clamp(FX.luma(c) * 1.6))) }
        }
        for mx in 0..<S.w {
            let lv = Self.reach(Double(mx), t, seed), my = FX.floor((1 - lv) * H)
            if S.on(mx, Int(my)) { p.glow(ax + Double(mx), ay + my, 4, C[5], 0.14) }
        }
        // the eyes burn
        for e in FXStatus.eyes(a) {
            for (x, y) in e.px { p.px(ax + Double(x), ay + Double(y), y == e.y0 ? C[7] : C[5]) }
            p.glow(ax + Double(e.x0 + e.x1 + 1) / 2, ay + Double(e.y0 + e.y1 + 1) / 2, 5, C[5], 0.4)
        }
        trails(p, S, t, true)
        // the skull glitches in, hangs there bobbing, and glitches out
        if t >= Self.tIn && t < Self.gone {
            let glitch = t < Self.hold ? 1 - (t - Self.tIn) / (Self.hold - Self.tIn) : t > Self.tOut ? (t - Self.tOut) / (Self.gone - Self.tOut) : 0
            let f = FX.floor(t * 30), on = glitch < 0.15 || FX.rand(f, 3) > glitch * 0.6
            let x = 0.0, y = ay - 12 + sin((t / Self.D) * FX.tau * 2) * 1.2
            if on {
                let tear = { (dx: Int, dy: Int) -> Swift.Character? in
                    let row = dy + 6
                    let shift = glitch > 0 && FX.rand(f, Double(row >> 1), 7) < glitch * 0.8 ? Int(FX.round((FX.rand(f, Double(row), 9) - 0.5) * 6 * glitch)) : 0
                    return Self.skull(dx - shift, dy)
                }
                if glitch > 0 {
                    FXStatus.icon(p, x - 2, y, 7, tear, [0, C[2], C[2], C[3]], 0.7 * glitch)
                    FXStatus.icon(p, x + 2, y, 7, tear, [0, C[6], C[6], C[6]], 0.5 * glitch)
                }
                FXStatus.icon(p, x, y, 8, tear, [C[0], C[4], C[6], C[7]], 1, ["e": C[0], "E": C[7]])
                p.glow(x - 3, y - 1, 5, C[5], 0.6)
                p.glow(x + 3, y - 1, 5, C[5], 0.6)
                p.glow(x, y, 16, C[4], 0.24 + 0.3 * glitch)
            }
            // scanlines fizzing as it comes and goes
            if glitch > 0.1 {
                for k in 0..<3 {
                    let fk = Double(k)
                    let ly = y - 5 + FX.floor(FX.rand(f, fk, 11) * 11), lx = FX.round((FX.rand(f, fk, 12) - 0.5) * 10), len = 3 + FX.floor(FX.rand(f, fk, 13) * 8)
                    p.line(lx - len / 2, ly, lx + len / 2, ly, k % 2 != 0 ? C[6] : C[4], glitch)
                }
            }
        }
        p.glow(0, ay + H * (1 - Self.tide(t)), 24, C[4], 0.2)
        p.glow(0, ay + H * 0.45, 30, C[3], 0.12)
    }
}

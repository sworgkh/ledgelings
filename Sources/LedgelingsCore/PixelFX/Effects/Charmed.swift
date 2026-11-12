// Smitten: a big heart beats over the head, throwing a ring and a flush of light with every beat, little
// hearts float up, the eyes go pink and the cheeks blush. pixelfx's `status/charmed` (MIT); its shaded,
// outlined hearts adapt Sprite Fusion's open-source heal (https://www.spritefusion.com/pixel-art-vfx/heal),
// MIT, Copyright (c) 2026 Hugo Duprez.

import Foundation

final class FXCharmed: FXEffect {
    static let meta = FXMeta(id: "status/charmed", size: (60, 76), origin: (30, 68), duration: 2.4, loop: true,
                             palette: ["#3a0a1e", "#7a1238", "#c4245a", "#f04e86", "#ff8ab0", "#ffc8da", "#ffffff"], seed: 8)
    static let D = 2.4, beat = D / 2
    nonisolated(unsafe) static let heart5 = FXStatus.bitmap([".#.#.", "#####", "#####", ".###.", "..#.."])
    nonisolated(unsafe) static let heart7 = FXStatus.bitmap([".##.##.", "#######", "#######", ".#####.", "..###..", "...#..."])
    let o: FXOptions
    let C: [FXColor]
    init(_ o: FXOptions) { self.o = o; C = FX.fit(o.palette, 7) }

    /// A heartbeat: a strong lub and a softer dub.
    static func thump(_ ph: Double) -> Double {
        exp(-pow((ph - 0.04) / 0.07, 2)) + 0.6 * exp(-pow((ph - 0.26) / 0.07, 2))
    }

    /// Little hearts drifting up (a third of them behind the creature).
    func hearts(_ p: Painter, _ t: Double, _ back: Bool) {
        let C = self.C, ay = Double(o.actor.y)
        FX.cycle(t, Self.D, 12, o.seed + 4, { r in r.range(1.3, 1.9) }) { age, life, r, i in
            if (i % 3 == 0) != back { return }
            let u = age / life, side: Double = r.next() < 0.5 ? -1 : 1, ph = r.range(0, FX.tau), big = r.next() < 0.3
            let x = side * r.range(4, 15) + sin(age * 4 + ph) * 2.2, y = ay + r.range(8, 30) - age * r.range(14, 22)
            let k = Swift.min(1, u * 6)
            if u > 0.88 {
                // it pops into a twinkle
                let q = (u - 0.88) / 0.12
                FX.sparkle(p, x, y, FX.round(2 * (1 - q)), C[5], C[4], 0.4 * (1 - q))
                return
            }
            let R = back ? [C[0], C[1], C[2], C[3]] : [C[0], C[2], C[3], C[4]]
            FXStatus.icon(p, x, y, 4, big ? Self.heart7 : Self.heart5, R, k)
            if !back { p.px(x - (big ? 2 : 1), y - 1, C[6]) }
            p.glow(x, y, 6, C[3], (back ? 0.12 : 0.22) * k)
        }
    }

    func drawBack(_ p: Painter, _ t: Double) {
        let ph = FX.mod(FX.mod(t, Self.beat) + Self.beat, Self.beat), th = Self.thump(ph)
        p.glow(0, Double(o.actor.y) - 8, 26 + 8 * th, C[3], 0.16 + 0.22 * th)
        hearts(p, t, true)
    }

    func draw(_ p: Painter, _ t: Double) {
        let C = self.C, a = o.actor, ph = FX.mod(FX.mod(t, Self.beat) + Self.beat, Self.beat), th = Self.thump(ph)
        let ax = Double(a.x), ay = Double(a.y)
        // lovestruck: pink eyes with a bright catchlight, flushed cheeks
        for e in FXStatus.eyes(a) {
            for (x, y) in e.px { p.px(ax + Double(x), ay + Double(y), y == e.y0 ? C[3] : C[2]) }
            p.px(ax + Double(e.x0), ay + Double(e.y0) + 1, C[6])
            let blush = FX.mix(e.skin, C[3], 0.55), out = Double(e.x0) < Double(a.w) / 2 ? -1 : 1, bx = Double(out < 0 ? e.x0 - 1 : e.x1)
            p.px(ax + bx, ay + Double(e.y1) + 1, blush)
            p.px(ax + bx + 1, ay + Double(e.y1) + 1, blush)
        }
        hearts(p, t, false)
        // the big heart, beating
        let hx = 0.0, hy = ay - 10, s = 5.6 * (1 + 0.24 * th)
        // a heart-shaped ring thrown off with each beat
        for (t0, kk) in [(0.04, 1.0), (0.26, 0.6)] {
            let u = (ph - t0) / 0.5
            if u < 0 || u > 1 { continue }
            let S1 = 5.6 * (1.25 + 1.3 * u), outer = FXStatus.shaped(FXStatus.heartShape, S1), inner = FXStatus.shaped(FXStatus.heartShape, S1 - 1.3)
            let E = Int(FX.ceil(S1 * 1.2)) + 1
            for dy in -E...E {
                for dx in -E...E where outer(dx, dy) != nil && inner(dx, dy) == nil {
                    p.dot(hx + Double(dx), hy + Double(dy), u < 0.3 ? C[5] : C[4], (1 - u) * kk * 1.3)
                }
            }
        }
        FXStatus.icon(p, hx, hy, 9, FXStatus.shaped(FXStatus.heartShape, s), [C[0], C[2], C[3], C[4]])
        // a glint on the left lobe
        let gx = hx - FX.round(s * 0.55), gy = hy - FX.round(s * 0.45)
        p.px(gx, gy, C[6])
        p.px(gx + 1, gy, C[5])
        p.px(gx, gy + 1, C[5])
        p.glow(hx, hy, 12 + 6 * th, C[4], 0.3 + 0.4 * th)
        if th > 0.5 { FX.sparkle(p, hx + s * 0.9, hy - s * 0.8, FX.round(3 * th), C[5], C[4], 0.4 * th) }
        // twinkles round the heart
        FX.cycle(t, Self.D, 8, o.seed + 2, { r in r.range(0.3, 0.5) }) { age, life, r, _ in
            let an = r.range(0, FX.tau), d = r.range(8, 15), u = age / life
            FX.sparkle(p, hx + cos(an) * d, hy + sin(an) * d * 0.8, FX.round(1.6 * sin(Double.pi * u)), C[5], C[4], 0.3 * sin(Double.pi * u))
        }
    }
}

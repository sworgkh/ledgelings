// Clock ticking: a glassy dial behind the head ticks round in heavy steps, flashing with each, while
// drops sink in slow motion. pixelfx's `status/slowed` (MIT).

import Foundation

final class FXSlowed: FXEffect {
    static let meta = FXMeta(id: "status/slowed", size: (64, 76), origin: (32, 68), duration: 2.4, loop: true,
                             palette: ["#081a24", "#0e3446", "#165a6e", "#2a8a9a", "#52bcc4", "#9ee6e0", "#e2fff8", "#ffffff"], seed: 7)
    static let D = 2.4, ticks = 4.0, step = D / ticks, R = 18.0
    let o: FXOptions
    let C: [FXColor]
    init(_ o: FXOptions) { self.o = o; C = FX.fit(o.palette, 8) }

    /// The hand's angle: it waits, pulls back a little, snaps a quarter turn, overshoots and settles.
    static func hand(_ t: Double) -> (ang: Double, flash: Double, ph: Double) {
        let k = FX.floor(t / step), ph = (t - k * step) / step, base = -Double.pi / 2 + (k * FX.tau) / ticks, q = FX.tau / ticks
        if ph < 0.62 { return (base, 0, ph) }
        if ph < 0.72 { return (base - 0.1 * sin(((ph - 0.62) / 0.1) * Double.pi * 0.5), 0, ph) }
        let s = (ph - 0.72) / 0.28, snap = FX.Ease.outBack(FX.clamp(s / 0.35), 2.2), wob = exp(-s * 6) * sin(s * 22) * 0.05
        return (base - 0.1 * (1 - FX.clamp(s / 0.2)) + q * snap + wob, exp(-s * 5), ph)
    }
    /// The flash of the last tick, still fading after the hand has settled.
    static func afterglow(_ t: Double) -> Double {
        let s = FX.mod(FX.mod(t - step * 0.72, step) + step, step)
        return exp(-s * 4)
    }

    func dial(_ p: Painter, _ cx: Double, _ cy: Double, _ t: Double) {
        let C = self.C, R = Self.R
        let h = Self.hand(t), fl = Swift.max(h.flash, Self.afterglow(t))
        p.disc(cx, cy, R - 1, C[2], 0.2)
        p.disc(cx - R * 0.25, cy - R * 0.3, R * 0.5, C[4], 0.08)
        p.ring(cx, cy, R + 1, 1, C[0])
        p.ring(cx, cy, R, 2, { v, ang in sin(ang + 0.8) < -0.3 ? (fl > 0.4 ? C[7] : C[6]) : v > 0.5 ? C[5] : C[4] }, { _, _ in 1 })
        p.ring(cx, cy, R - 3.5, 1, C[3], 0.6)
        for i in 0..<60 where i % 5 != 0 {
            let a = (Double(i) / 60) * FX.tau
            p.dot(cx + cos(a) * (R - 2.6), cy + sin(a) * (R - 2.6), C[4], 0.8)
        }
        for i in 0..<12 {
            let a = (Double(i) / 12) * FX.tau, big = i % 3 == 0, r0 = R - 2.5, r1 = R - (big ? 6 : 4.5), c = cos(a), s = sin(a)
            p.line(cx + c * r0, cy + s * r0, cx + c * r1, cy + s * r1, big ? C[6] : C[5])
        }
        let shud = h.flash * sin(t * 60) * 0.06, ha = -Double.pi / 2 + 2.2 + shud
        p.beam(cx, cy, cx + cos(ha) * R * 0.5, cy + sin(ha) * R * 0.5, 2.2, C[5])
        let tx = cx + cos(h.ang) * (R - 4), ty = cy + sin(h.ang) * (R - 4)
        p.beam(cx, cy, tx, ty, 2.4, { u, _ in u > 0.8 ? C[7] : C[6] }, { _, _ in 1 })
        p.circle(cx, cy, 2, C[6])
        p.px(cx, cy, C[1])
        p.glow(cx, cy, R + 8, C[4], 0.14 + 0.2 * fl)
        p.glowRing(cx, cy, R, 3, C[5], 0.12 + 0.35 * fl)
        p.glow(tx, ty, 5, C[6], 0.3 + 0.3 * h.flash)
        if h.flash > 0.02 {
            let s = 1 - h.flash
            p.ring(cx, cy, R + 2 + 10 * s, 1, C[5], h.flash)
            p.glowRing(cx, cy, R + 2 + 10 * s, 3, C[4], 0.3 * h.flash)
        }
    }

    func drawBack(_ p: Painter, _ t: Double) {
        let a = o.actor
        dial(p, 0, Double(a.y) + 3, t)
        // the body lags behind itself: an after-image of its outline, dragged a step back after every tick
        let lag = Self.afterglow(t)
        if lag > 0.05 { p.outline(a.mask, Double(a.x) - 1 - FX.round(2 * lag), Double(a.y), { _, _ in self.C[5] }, { _, _ in 0.55 * lag }) }
    }

    func draw(_ p: Painter, _ t: Double) {
        let C = self.C, a = o.actor, S = FXStatus.shape(a), fl = Swift.max(Self.hand(t).flash, Self.afterglow(t))
        let ax = Double(a.x), ay = Double(a.y)
        for (mx, my) in S.body { p.blend(ax + Double(mx), ay + Double(my), C[5], 0.08 + 0.12 * fl) }
        FX.cycle(t, Self.D, 6, o.seed + 3, { r in r.range(1.6, 2.2) }) { age, life, r, _ in
            let side: Double = r.next() < 0.5 ? -1 : 1, x = side * r.range(10, 17), y0 = ay + r.range(6, 22), v0 = r.range(18, 30), k = 1.1
            let yAt = { (g: Double) in y0 + (v0 * (1 - exp(-k * g))) / k + 4 * g }
            let y = yAt(age), u = age / life
            if y < -1 {
                for (lag, al) in [(0.22, 0.35), (0.11, 0.6)] where age > lag { p.dot(x, yAt(age - lag), C[4], al) }
                p.px(x, y - 1, C[5])
                p.px(x, y, C[6])
                p.px(x, y + 1, C[5])
                p.px(x - 1, y + 1, C[4])
                p.px(x - 1, y, C[7])
                p.glow(x, y, 4, C[5], 0.3 * (1 - u))
            } else {
                var g = age
                while g > 0 && yAt(g) >= -1 { g -= 0.02 }
                let s = FX.clamp((age - g) / 0.9)
                if s < 1 {
                    let rx = 1 + 7 * s.squareRoot(), c = s < 0.3 ? C[6] : C[5]
                    for sd in [-1.0, 1.0] { p.line(x + sd * rx, -0.5, x + sd * (rx - 1.5), -0.5, c, (1 - s) * 1.2) }
                    var dx = -rx + 2
                    while dx <= rx - 2 { p.dot(x + dx, -1.5, C[4], (1 - s) * 0.5 * (1 - abs(dx) / rx)); dx += 1 }
                    p.glow(x, -1, 4 + rx, C[4], 0.12 * (1 - s))
                }
            }
        }
    }
}

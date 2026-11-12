// The moment of pickup: a white flash and a cross of light, a thin ring snapping out ahead of a softer one,
// twinkles thrown wide on curving paths that brake, hang and wink out. pixelfx's `pickups/collect-burst` (MIT),
// after Sprite Fusion's open-source pickup (https://www.spritefusion.com/pixel-art-vfx/pickup), MIT,
// Copyright (c) 2026 Hugo Duprez.

import Foundation

final class FXCollectBurst: FXEffect {
    static let meta = FXMeta(id: "pickups/collect-burst", size: (112, 108), origin: (56, 94), duration: 1.35, loop: false,
                             palette: ["#1a0516", "#3d0a33", "#701560", "#b0228f", "#f53cd1", "#ff86e6", "#ffd2f6", "#ffffff"], seed: 3)
    static let CY = -30.0
    final class Star {
        var x: Double, y: Double, a: Double, sp: Double, turn: Double, life: Double, age = 0.0, size: Double
        var tr: [(Double, Double)] = []
        let c: FXColor, ph: Double
        init(x: Double, y: Double, a: Double, sp: Double, turn: Double, life: Double, size: Double, c: FXColor, ph: Double) {
            self.x = x; self.y = y; self.a = a; self.sp = sp; self.turn = turn; self.life = life; self.size = size; self.c = c; self.ph = ph
        }
    }
    struct Mote { let x: Double, y: Double, vy: Double, life: Double, d: Double, w: Double }

    let o: FXOptions
    let C: [FXColor]
    let lights = FXLights()
    var stars: [Star] = []
    var motes: [Mote] = []
    var t = 0.0

    init(_ o: FXOptions) {
        self.o = o
        let C = FX.fit(o.palette, 8), R = Rng(o.seed), CY = Self.CY
        self.C = C
        lights.add(0, CY, 36, C[5], 0.85, 0.32)
        lights.add(0, CY, 14, FX.white, 0.75, 0.08)
        // twinkles thrown out on curving paths: each one's heading turns as it flies, and drag brakes it
        for i in 0..<14 {
            let a = (Double(i) / 14) * FX.tau + R.range(-0.2, 0.2), sp = R.range(145, 225) * (i % 3 == 0 ? 1.12 : 0.85)
            let turn = (i % 2 != 0 ? 1.0 : -1.0) * R.range(2.5, 5), life = R.range(0.75, 1.15), size = i % 3 == 0 ? 2.6 : R.range(1.2, 2)
            let c = i % 4 == 0 ? FX.white : i % 2 != 0 ? C[6] : C[5]
            stars.append(Star(x: 0, y: CY, a: a, sp: sp, turn: turn, life: life, size: size, c: c, ph: R.range(0, FX.tau)))
        }
        for _ in 0..<7 {
            let x = R.range(-8, 8), y = CY + R.range(-4, 6), vy = -R.range(12, 30), life = R.range(0.5, 0.9), d = R.range(0.05, 0.25)
            motes.append(Mote(x: x, y: y, vy: vy, life: life, d: d, w: R.range(0, FX.tau)))
        }
    }

    func update(_ dt: Double) {
        t += dt
        for s in stars {
            if s.age > s.life { continue }
            s.age += dt
            s.tr.insert((s.x, s.y), at: 0)
            if s.tr.count > 4 { s.tr.removeLast() }
            s.a += s.turn * dt * Swift.max(0, 1 - s.age * 1.5)
            s.sp -= s.sp * 4.3 * dt
            s.x += cos(s.a) * s.sp * dt
            s.y += sin(s.a) * s.sp * dt + 6 * s.age * dt
            // the floor turns them back up
            if s.y > -2 { s.y = -2; s.a = -abs(s.a); s.sp *= 0.5 }
        }
        lights.update(dt)
    }

    func draw(_ p: Painter, _ _t: Double) {
        let C = self.C, CY = Self.CY, t = self.t, W = FX.white
        // the flash: a white disc and a cross of light, gone in a few frames
        if t < 0.07 { p.circle(0, CY, 5.5 * (1 - t / 0.07) + 1, W) }
        if t < 0.16 {
            let k = 1 - t / 0.16, L = 26 * FX.Ease.outCubic(Swift.min(1, t / 0.03 + 0.4)) * k
            for (dx, dy, l) in [(1.0, 0.0, 1.0), (-1, 0, 1), (0, 1, 0.6), (0, -1, 0.6)] {
                p.line(0, CY, dx * L * l, CY + dy * L * l, { u in u < 0.3 ? W : u < 0.65 ? C[6] : C[5] }, { u in (u < 0.5 ? 1 : (1 - u) * 2) * (0.5 + k) })
            }
            p.glow(0, CY, 20 * k + 4, C[5], 0.6 * k)
        }
        // a thin ring snapping out fast, a softer ring following
        let u1 = t / 0.32
        if u1 < 1 {
            let r = 3 + 23 * FX.Ease.outExpo(u1)
            p.ring(0, CY, r, 1, u1 < 0.3 ? W : C[6], 1.3 - u1 * 1.2)
            p.glowRing(0, CY, r, 4, C[5], 0.4 * (1 - u1))
        }
        let u2 = (t - 0.04) / 0.5
        if u2 > 0 && u2 < 1 {
            let r = 2 + 16 * FX.Ease.outCubic(u2)
            p.ring(0, CY, r, Swift.max(1, 2.6 * (1 - u2)), C[5], 1 - u2)
        }
        // the twinkles, with short trails, flickering as they hang and wink out
        for s in stars {
            if s.age > s.life { continue }
            let k = 1 - s.age / s.life, tw = 0.65 + 0.35 * sin(s.age * 26 + s.ph)
            for (i, (x, y)) in s.tr.enumerated() where i > 0 { p.dot(x, y, i < 2 ? C[5] : C[4], (1 - Double(i) / 4) * k * 1.4) }
            if k < 0.3 && sin(s.age * 40 + s.ph) < 0 { continue }
            FXPickups.glint(p, s.x, s.y, FX.round(s.size * tw * Swift.min(1, k * 2.5)), s.c, 0.45 * k)
        }
        // motes drifting up after
        for m in motes {
            let a = t - m.d
            if a < 0 || a > m.life { continue }
            let k = 1 - a / m.life, x = m.x + sin(a * 6 + m.w) * 1.5, y = m.y + m.vy * a
            p.dot(x, y, k > 0.5 ? C[6] : C[5], k * 1.5)
            p.glow(x + 0.5, y + 0.5, 3, C[5], 0.3 * k)
        }
        lights.draw(p)
    }
}

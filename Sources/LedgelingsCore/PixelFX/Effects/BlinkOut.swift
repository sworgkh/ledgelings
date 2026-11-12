// Blink out: the caster crackles with gathering light, flashes white, squeezes into a line of light that
// collapses and pops away in sparks. pixelfx's `arcane/blink-out` (MIT), adapted from Sprite Fusion's
// open-source blink (https://www.spritefusion.com/pixel-art-vfx/movement), MIT, Copyright (c) 2026 Hugo Duprez.

import Foundation

final class FXBlinkOut: FXEffect {
    static let meta = FXMeta(id: "arcane/blink-out", size: (136, 96), origin: (68, 80), duration: 1.6, loop: false,
                             palette: ["#140a26", "#2b1252", "#481c88", "#6b2cc0", "#9a48ec", "#c684ff", "#ecc8ff", "#ffffff"], seed: 11)
    static let OUT = 0.32, SQUEEZE = 0.12, COLLAPSE = 0.08, POP = OUT + SQUEEZE + COLLAPSE

    let C: [FXColor], R: Rng, A: FXActor, sh: [UInt8]
    let ps: FXParticles, lights = FXLights()
    let mx: Double, my: Double, COLS: [FXColor]
    var t = 0.0, out = false, popped = false

    init(_ o: FXOptions) {
        C = FX.fit(o.palette, 8); R = Rng(o.seed); A = o.actor; sh = FXArcane.shades(A)
        ps = FXParticles(rng: R, ground: { _ in 0 }, sparks: [FX.white, C[6], C[5], C[4]])
        mx = Double(A.x) + Double(A.w) / 2; my = Double(A.y) + Double(A.h) * 0.55
        COLS = [FX.white, C[6], C[6], C[5], C[4]]
    }

    func inside(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < A.w && y < A.h && A.mask.data[y * A.w + x] != 0 }

    func actorAlpha(_ t: Double) -> Double { t < Self.OUT ? 1 : 0 }

    func update(_ dt: Double) {
        t += dt
        let C = self.C, R = self.R, A = self.A, mx = self.mx, my = self.my
        if t < Self.OUT - 0.04 && R.chance(0.7) {
            let a = R.range(0, FX.tau), D = R.range(22, 44), T = R.range(0.12, 0.18), v = (D * 3) / (exp(3 * T) - 1)
            let x = mx + cos(a) * D, y = Swift.min(-2, my + sin(a) * D), h = hypot(x - mx, y - my), l = h == 0 ? 1 : h
            ps.spawn(.streak, x, y, ((mx - x) / l) * v, ((my - y) / l) * v, T, R.chance(0.5) ? C[6] : C[5])
        }
        if !out && t >= Self.OUT {
            out = true
            lights.add(mx, my - 6, 54, C[5], 0.9, 0.3)
            lights.add(mx, my, 26, FX.white, 0.8, 0.1)
        }
        if !popped && t >= Self.POP {
            popped = true
            lights.add(mx, my - 6, 58, C[5], 0.9, 0.35)
            lights.add(mx, my, 24, FX.white, 0.9, 0.08)
            for _ in 0..<110 {
                let y = Double(A.y) + R.range(2, Double(A.h) - 2), s = R.sign()
                let x = mx + R.range(-1, 1), vx = s * R.range(25, 105), vy = R.range(-70, 10), life = R.range(0.5, 0.95)
                let c = R.pick(COLS), size: Double = R.chance(0.3) ? 2 : 1
                ps.spawn(.ember, x, y, vx, vy, life, c, size)
            }
            for _ in 0..<18 {
                let a = R.range(0, FX.tau), sp = R.range(80, 240)
                ps.spawn(.spark, mx, my, cos(a) * sp, sin(a) * sp - 40, R.range(0.2, 0.5))
            }
            for i in 0..<14 {
                let a = R.range(0, FX.tau), sp = R.range(20, 110)
                let life = R.range(0.4, 0.9), c = R.pick([FX.white, C[6], C[5]]), size = R.range(0.8, 1.8)
                ps.spawn(i % 2 != 0 ? .star : .mote, mx, my, cos(a) * sp, sin(a) * sp * 0.8 - 20, life, c, size)
            }
        }
        ps.update(dt)
        lights.update(dt)
    }

    func ring(_ p: Painter, _ far: Bool) {
        let C = self.C, k = (t - Self.POP) / 0.5
        if k >= 0 && k < 1 {
            FX.band(p, 0, 0, 4 + 30 * FX.Ease.outCubic(k), 0.2, Swift.max(1, 3 * (1 - k)), 1.15 - k, [C[3], C[5], C[6], FX.white],
                    far ? { g in sin(g) < 0 } : { g in sin(g) >= 0 }, k < 0.25)
        }
    }

    func drawBack(_ p: Painter, _ tt: Double) {
        let C = self.C, A = self.A, POP = Self.POP, OUT = Self.OUT
        // the afterimage it leaves: a translucent violet ghost that thins away
        if t > POP && t < POP + 0.6 {
            let k = 0.5 * (1 - (t - POP) / 0.6)
            for y in 0..<A.h {
                for x in 0..<A.w where sh[y * A.w + x] != 0 {
                    p.blend(Double(A.x + x), Double(A.y + y), sh[y * A.w + x] == 1 ? C[3] : C[4], k)
                }
            }
        }
        ring(p, true)
        if t < POP + 0.3 { p.glow(0, -1, 26, C[5], 0.3 * (t < OUT ? t / OUT : 1 - FX.clamp((t - POP) / 0.3))) }
    }

    func draw(_ p: Painter, _ tt: Double) {
        let C = self.C, A = self.A, mx = self.mx, my = self.my
        let OUT = Self.OUT, SQUEEZE = Self.SQUEEZE, COLLAPSE = Self.COLLAPSE, POP = Self.POP
        let f = FX.floor(t * 30)
        if t < OUT {
            // the body brightens and an outline of light crackles round it, thicker as it gathers
            let k = t / OUT, ax = Double(A.x), ay = Double(A.y)
            for y in 0..<A.h {
                for x in 0..<A.w {
                    if inside(x, y) { p.light(ax + Double(x), ay + Double(y), C[6], k * k * (sh[y * A.w + x] == 1 ? 0.3 : 0.75)) }
                    else if (inside(x - 1, y) || inside(x + 1, y) || inside(x, y - 1) || inside(x, y + 1)) && FX.rand(Double(x), Double(y), f) < 0.25 + 0.65 * k {
                        p.px(ax + Double(x), ay + Double(y), k > 0.6 && FX.rand(Double(x), Double(y), 7) < 0.5 ? FX.white : C[6])
                    }
                }
            }
            p.glow(mx, my, 30, C[5], 0.5 * k)
        } else if t < OUT + 0.05 {
            FXArcane.squeezed(p, A, sh, 1, FX.white, C[6])
            p.glow(mx, my, 40, C[5], 0.8)
        } else if t < OUT + SQUEEZE {
            // squeezed into a line
            let q = FX.Ease.inCubic((t - OUT - 0.05) / (SQUEEZE - 0.05))
            FXArcane.squeezed(p, A, sh, 1 - q, FX.white, C[6])
            p.glow(mx, my, 34, C[5], 0.8)
        } else if t < POP {
            // the line shrinks to a point
            let q = (t - OUT - SQUEEZE) / COLLAPSE, hh = (Double(A.h) / 2 + 2) * (1 - FX.Ease.inQuad(q))
            var y = -hh - 3
            while y <= hh + 3 { p.dot(mx, my + y, abs(y) < hh ? FX.white : C[6], abs(y) < hh ? 1 : 0.7); y += 1 }
            if hh > 4 {
                y = -hh * 0.7
                while y <= hh * 0.7 { p.dot(mx - 1, my + y, C[5], 0.6); p.dot(mx + 1, my + y, C[5], 0.6); y += 1 }
            }
            p.glow(mx, my, 30, C[5], 0.9)
            p.glow(mx, my, 8, FX.white, 0.5)
        }
        if t >= POP && t < POP + 0.22 {
            let q = (t - POP) / 0.22
            FX.flare(p, mx, my, 22 * pow(1 - q, 1.5) + 2, 1 - q, C)
            if q < 0.3 { p.circle(mx, my, 4 * (1 - q / 0.3) + 1, FX.white) }
        }
        ring(p, false)
        if t > POP && t < POP + 0.3 { FX.sparkle(p, mx, my - 1, 3, C[6], C[5], 0.3 * (1 - (t - POP) / 0.3)) }
        ps.draw(p, nil)
        lights.draw(p)
    }
}

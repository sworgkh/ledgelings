// Blink in: glittering bits spiral in to a point of light that opens into a line, then into a white silhouette
// that cools into the caster. pixelfx's `arcane/blink-in` (MIT), adapted from Sprite Fusion's open-source blink
// (https://www.spritefusion.com/pixel-art-vfx/movement), MIT, Copyright (c) 2026 Hugo Duprez.

import Foundation

final class FXBlinkIn: FXEffect {
    static let meta = FXMeta(id: "arcane/blink-in", size: (136, 96), origin: (68, 80), duration: 1.4, loop: false,
                             palette: ["#140a26", "#2b1252", "#481c88", "#6b2cc0", "#9a48ec", "#c684ff", "#ecc8ff", "#ffffff"], seed: 12)
    static let LINE = 0.26, GROW = 0.1, OPEN = 0.12, ARRIVE = LINE + GROW + OPEN

    struct Bit { let tx: Double, ty: Double, ox: Double, oy: Double, t0: Double, t1: Double, spin: Double, c: FXColor }

    let C: [FXColor], R: Rng, A: FXActor, sh: [UInt8]
    let ps: FXParticles, lights = FXLights()
    let mx: Double, my: Double, COLS: [FXColor]
    var bits: [Bit] = []
    var t = 0.0, arrived = false

    init(_ o: FXOptions) {
        C = FX.fit(o.palette, 8); R = Rng(o.seed); A = o.actor; sh = FXArcane.shades(A)
        ps = FXParticles(rng: R, ground: { _ in 0 }, sparks: [FX.white, C[6], C[5], C[4]])
        mx = Double(A.x) + Double(A.w) / 2; my = Double(A.y) + Double(A.h) * 0.55
        COLS = [FX.white, C[6], C[6], C[5], C[4]]
        let ay = Double(A.y), ah = Double(A.h)
        for _ in 0..<230 {
            let a = R.range(0, FX.tau), d = R.range(16, 46), ty = ay + R.range(3, ah - 2)
            var oy = sin(a) * d * 0.8 - 6
            if ty + oy > -2 { oy = -abs(oy) - 2 }
            let tx = mx + R.range(-1, 1), t0 = R.range(0, 0.1), t1 = Self.LINE + R.range(-0.02, Self.GROW)
            let spin = R.range(0.8, 1.8) * R.sign(), c = R.pick(COLS)
            bits.append(Bit(tx: tx, ty: ty, ox: cos(a) * d, oy: oy, t0: t0, t1: t1, spin: spin, c: c))
        }
    }

    func inside(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < A.w && y < A.h && A.mask.data[y * A.w + x] != 0 }

    func at(_ b: Bit, _ tt: Double) -> (Double, Double, Double) {
        let k = FX.clamp((tt - b.t0) / (b.t1 - b.t0)), e = FX.Ease.outCubic(k), r = 1 - e, sp = b.spin * r * 1.2
        let ox = b.ox * cos(sp) - b.oy * sin(sp), oy = b.ox * sin(sp) + b.oy * cos(sp)
        return (b.tx + ox * r, Swift.min(-1, b.ty + oy * r), k)
    }

    func actorAlpha(_ t: Double) -> Double { t < Self.ARRIVE ? 0 : 1 }

    func update(_ dt: Double) {
        t += dt
        let C = self.C, R = self.R
        if t < Self.LINE && R.chance(0.6) {
            let a = R.range(0, FX.tau), D = R.range(22, 44), T = R.range(0.12, 0.18), v = (D * 3) / (exp(3 * T) - 1)
            let x = mx + cos(a) * D, y = Swift.min(-2, my + sin(a) * D), h = hypot(x - mx, y - my), l = h == 0 ? 1 : h
            ps.spawn(.streak, x, y, ((mx - x) / l) * v, ((my - y) / l) * v, T, R.chance(0.5) ? C[6] : C[5])
        }
        if !arrived && t >= Self.ARRIVE {
            arrived = true
            lights.add(mx, my - 6, 56, C[5], 0.9, 0.35)
            lights.add(mx, my, 24, FX.white, 0.8, 0.1)
            for _ in 0..<30 {
                let a = R.range(0, FX.tau), sp = R.range(35, 110)
                let k: FXKind = R.chance(0.6) ? .star : .mote
                let life = R.range(0.4, 0.85), c = R.pick(COLS), s = R.range(0.6, 1.6)
                ps.spawn(k, mx, my, cos(a) * sp, sin(a) * sp * 0.7 - 30, life, c, s)
            }
            for _ in 0..<12 {
                let s = R.sign()
                let x = mx + s * R.range(2, 8), vx = s * R.range(60, 180), vy = -R.range(20, 110), life = R.range(0.2, 0.45)
                ps.spawn(.spark, x, -1, vx, vy, life)
            }
        }
        ps.update(dt)
        lights.update(dt)
    }

    func ring(_ p: Painter, _ far: Bool) {
        let C = self.C, k = (t - Self.ARRIVE + 0.03) / 0.5
        if k >= 0 && k < 1 {
            FX.band(p, 0, 0, 4 + 30 * FX.Ease.outCubic(k), 0.2, Swift.max(1, 3 * (1 - k)), 1.15 - k, [C[3], C[5], C[6], FX.white],
                    far ? { g in sin(g) < 0 } : { g in sin(g) >= 0 }, k < 0.25)
        }
    }

    func drawBack(_ p: Painter, _ tt: Double) {
        ring(p, true)
        p.glow(0, -1, 26, C[5], 0.3 * (t < Self.ARRIVE ? t / Self.ARRIVE : 1 - FX.clamp((t - Self.ARRIVE) / 0.5)))
    }

    func draw(_ p: Painter, _ tt: Double) {
        let C = self.C, A = self.A, mx = self.mx, my = self.my
        let LINE = Self.LINE, GROW = Self.GROW, OPEN = Self.OPEN, ARRIVE = Self.ARRIVE
        for b in bits {
            if t < b.t0 || t > b.t1 + 0.02 { continue }
            let (x, y, k) = at(b, t)
            p.dot(x, y, k > 0.75 ? FX.white : b.c, Swift.min(1, 0.35 + k * 2))
            if k > 0.55 {
                let (px, py, _) = at(b, t - 0.015)
                p.dot((x + px) / 2, (y + py) / 2, C[5], 0.8)
            }
            if k > 0.8 { p.glow(x, y, 3, C[6], 0.3) }
        }
        if t >= LINE - 0.04 && t < LINE {
            let q = (t - LINE + 0.04) / 0.04
            FX.sparkle(p, mx, my, 2 + 3 * q, C[6], C[5], 0.6)
        } else if t >= LINE && t < LINE + GROW {
            let q = FX.Ease.outCubic((t - LINE) / GROW), hh = (Double(A.h) / 2 + 3) * q
            var y = -hh - 2
            while y <= hh + 2 { p.dot(mx, my + y, abs(y) < hh ? FX.white : C[6], abs(y) < hh ? 1 : 0.7); y += 1 }
            y = -hh * 0.7
            while y <= hh * 0.7 { p.dot(mx - 1, my + y, C[5], 0.6); p.dot(mx + 1, my + y, C[5], 0.6); y += 1 }
            p.glow(mx, my, 30, C[5], 0.9)
            p.glow(mx, my, 8, FX.white, 0.5)
        } else if t >= LINE + GROW && t < ARRIVE {
            let q = FX.Ease.outCubic((t - LINE - GROW) / OPEN)
            FXArcane.squeezed(p, A, sh, q, FX.white, C[6])
            p.glow(mx, my, 36, C[5], 0.8)
        } else if t >= ARRIVE && t < ARRIVE + 0.42 {
            let k = 1 - (t - ARRIVE) / 0.42, f = FX.floor(t * 30)
            if k > 0.86 { FXArcane.squeezed(p, A, sh, 1, FX.white, C[6]) }
            let ax = Double(A.x), ay = Double(A.y)
            for y in 0..<A.h {
                for x in 0..<A.w {
                    if inside(x, y) { p.light(ax + Double(x), ay + Double(y), C[6], k * k * (sh[y * A.w + x] == 1 ? 0.3 : 0.8)) }
                    else if (inside(x - 1, y) || inside(x + 1, y) || inside(x, y - 1) || inside(x, y + 1)) && FX.rand(Double(x), Double(y), f) < 0.85 * k {
                        p.px(ax + Double(x), ay + Double(y), k > 0.5 && FX.rand(Double(x), Double(y), 7) < 0.5 ? FX.white : C[6])
                    }
                }
            }
            p.glow(mx, my, 34, C[5], 0.6 * k)
        }
        if t >= ARRIVE && t < ARRIVE + 0.2 {
            let q = (t - ARRIVE) / 0.2
            FX.flare(p, mx, my - 4, 18 * pow(1 - q, 1.5) + 2, 1 - q, C)
        }
        ring(p, false)
        ps.draw(p, nil)
        lights.draw(p)
    }
}

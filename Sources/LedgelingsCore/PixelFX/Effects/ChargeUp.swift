// Sparks streak and arcs whip in to a crackling core at the caster's hand that swells and pulses faster, then
// it flashes and bursts: bolts every way, a ring, a spray of sparks. pixelfx's `lightning/charge-up` (MIT),
// after Sprite Fusion's open-source energy charge (https://www.spritefusion.com/pixel-art-vfx/energy), MIT,
// Copyright (c) 2026 Hugo Duprez.

import Foundation

final class FXChargeUp: FXEffect {
    static let meta = FXMeta(id: "lightning/charge-up", size: (272, 184), origin: (124, 148), duration: 2.7, loop: false, palette: FXLightning.volt, seed: 4)
    static let CX = 15.0, CY = -21.0, BK = [1, 0.7, 0.95, 0.5, 0.8, 0.35], ash = FX.hex("#5b5566"), charge = 1.6
    nonisolated(unsafe) static let edges = FXMemo<[(Int, Int)]>()
    struct Bolt { var x1: Double, y1: Double, t0: Double }
    struct Arc { var x: Double, y: Double, t: Double, seed: Double }

    let o: FXOptions
    let C: [FXColor]
    let R: Rng
    let ps: FXParticles
    let lights = FXLights()
    var bolts: [Bolt] = []
    var arcs: [Arc] = []
    var t = 0.0, released = false, phase = 0.0, beats: [Double] = []

    init(_ o: FXOptions) {
        self.o = o
        C = FX.fit(o.palette, 8)
        R = Rng(o.seed)
        ps = FXParticles(rng: R, ground: { _ in 0 }, sparks: FX.ramp(FXLightning.plasma))
        let CX = Self.CX, CY = Self.CY, REL = Self.charge
        for i in 0..<8 {
            let a = (Double(i) / 8) * FX.tau + R.range(-0.25, 0.25), L = R.range(44, 72), x1 = CX + cos(a) * L, y1 = Swift.min(0, CY + sin(a) * L)
            bolts.append(Bolt(x1: x1, y1: y1, t0: REL + R.range(0, 0.05)))
        }
    }

    static func edgeOf(_ A: FXActor) -> [(Int, Int)] {
        edges.get(A.key) {
            let m = A.mask
            let on = { (x: Int, y: Int) in x >= 0 && y >= 0 && x < m.w && y < m.h && m.data[y * m.w + x] != 0 }
            var e: [(Int, Int)] = []
            for y in 0..<m.h { for x in 0..<m.w where on(x, y) && (!on(x - 1, y) || !on(x + 1, y) || !on(x, y - 1) || !on(x, y + 1)) {
                e.append((A.x + x, A.y + y))
            } }
            return e
        }
    }

    var level: Double { FX.clamp(t / Self.charge) }

    func update(_ dt: Double) {
        let C = self.C, R = self.R, CX = Self.CX, CY = Self.CY, REL = Self.charge
        t += dt
        let k = level, e = k * k
        if t < REL {
            // energy rushes in: long streaks spiralling in from all round, more and more of them
            var acc = (60 + 360 * e) * dt
            while acc > 0 {
                if acc < 1 && !R.chance(acc) { break }
                let a = R.range(0, FX.tau), d = R.range(30, 72) * (1 - 0.35 * k), life = R.range(0.16, 0.26), sp = (d / life) * 0.95
                ps.spawn(.mote, CX + cos(a) * d, Swift.min(-2, CY + sin(a) * d), -cos(a) * sp - sin(a) * sp * 0.4, -sin(a) * sp + cos(a) * sp * 0.4,
                         life, R.pick([C[7], C[6], C[5]]), 1)
                acc -= 1
            }
            // arcs whip in from the air, more and more of them
            if k > 0.2 && R.chance((2 + 16 * e) * dt) {
                let a = R.range(0, FX.tau), d = R.range(20, 40)
                arcs.append(Arc(x: CX + cos(a) * d, y: Swift.min(-3, CY + sin(a) * d), t: t, seed: R.int(0, 1e6)))
            }
            // the pulse quickens
            phase += (1.5 + 11 * e) * dt
            if phase >= 1 { phase -= 1; beats.append(t) }
            if R.chance(4 * e * dt) {
                let x = CX + R.range(-14, 14), y = CY + R.range(-14, 10), life = R.range(0.2, 0.35)
                ps.spawn(.star, x, y, 0, -4, life, C[6], R.range(1, 2))
            }
        } else if !released {
            released = true
            lights.add(CX, CY, 110, C[4], 0.8, 0.5)
            lights.add(CX, CY, 28, FX.white, 0.6, 0.08)
            for _ in 0..<70 {
                let a = R.range(0, FX.tau), sp = R.range(140, 330) * (sin(a) > 0.4 ? 0.55 : 1)
                let kind: FXKind = sin(a) < -0.2 && R.chance(0.35) ? .mote : .spark
                let life = R.range(0.25, 0.55), col = R.pick([C[7], C[6], C[5]])
                ps.spawn(kind, CX, CY, cos(a) * sp, sin(a) * sp, life, col, R.range(0.8, 1.4))
            }
            for _ in 0..<10 {
                let a = R.range(0, FX.tau), sp = R.range(60, 160)
                let life = R.range(0.4, 0.8), col = R.chance(0.5) ? C[6] : C[5]
                ps.spawn(.star, CX, CY, cos(a) * sp, sin(a) * sp, life, col, R.range(1.2, 2.4))
            }
            for _ in 0..<4 {
                let x = CX + R.range(-5, 5), y = CY + R.range(-4, 4), vx = R.range(-12, 12), vy = -R.range(8, 18), life = R.range(0.6, 0.85)
                let size = R.range(3, 5)
                ps.spawn(.smoke, x, y, vx, vy, life, FX.mix(Self.ash, C[4], 0.3), size, R.range(0.05, 0.15))
            }
        }
        beats = beats.filter { t - $0 < 0.22 }
        var i = arcs.count - 1
        while i >= 0 { if t - arcs[i].t > 0.07 { arcs.remove(at: i) }; i -= 1 }
        ps.update(dt)
        lights.update(dt)
    }

    func drawBack(_ p: Painter, _ _t: Double) {
        let k = level
        if t < Self.charge { p.glow(Self.CX * 0.5, -3, 40, C[3], 0.3 * k * k) }
        ps.draw(p, .back)
    }

    func draw(_ p: Painter, _ _t: Double) {
        let C = self.C, CX = Self.CX, CY = Self.CY, REL = Self.charge, seed = o.seed, t = self.t
        let k = level, e = k * k, f = Int(FX.floor(t * 30 + 1e-4)), A = o.actor
        if t < REL {
            let jit = k > 0.85 ? (f % 2 != 0 ? 1.0 : -1.0) * ((k - 0.85) / 0.15) : 0, x = CX + jit, y = CY, pr = 0.5 + 0.5 * sin(phase * FX.tau)
            // the body catches the core's light along its near edge
            for (ex, ey) in Self.edgeOf(A) {
                let d = hypot(Double(ex) + 0.5 - x, Double(ey) + 0.5 - y)
                if d < 6 + 10 * k && e > 0.08 { p.px(Double(ex), Double(ey), d < 4 + 6 * k && e > 0.4 ? C[6] : C[4]) }
            }
            // rings fall inward to the core on every beat
            for b in beats {
                let q = (t - b) / 0.22
                p.ring(x, y, 4 + 20 * (1 - FX.Ease.inQuad(q)) * (0.5 + k), 1, q > 0.6 ? C[6] : C[4], 0.4 + 0.6 * q)
            }
            // arcs whipping in to the core
            for a in arcs { FXLightning.crackle(p, FXLightning.zigzag(FX.rng(a.seed, Double(f)), a.x, a.y, x, y, 0.35, 0.4), 0.85, C, 0.4) }
            // the core: swelling, layered, with arcs racing round its skin
            let r = 1.2 + 6.5 * e + pr * (0.5 + 1.2 * k)
            p.circle(x, y, r + 1.3, C[2])
            p.circle(x, y, r, C[4])
            p.circle(x - r * 0.12, y - r * 0.12, r * 0.7, C[5])
            p.circle(x, y, r * 0.38, FX.white)
            if r > 3 {
                for s in [0, Double.pi] {
                    var a = 0.0
                    while a < 1.3 {
                        let ang = t * 10 + s + a, rr = r * (0.62 + 0.1 * sin(a * 3))
                        p.dot(x + cos(ang) * rr, y + sin(ang) * rr, a < 0.5 ? FX.white : C[6])
                        a += 0.12
                    }
                }
            }
            if k > 0.35 {
                let q = FX.rng(seed, 5, Double(f)), a = q.range(0, FX.tau), l = q.range(3, 6) * (0.5 + k)
                FXLightning.crackle(p, FXLightning.zigzag(q, x + cos(a) * r, y + sin(a) * r, x + cos(a) * (r + l), y + sin(a) * (r + l), 0.4, 0.3), 0.7, C, 0.3)
            }
            p.glow(x, y, 12 + 30 * k, C[4], 0.35 + 0.45 * k)
            p.glow(x, y, 6 + 6 * k, C[6], 0.25 + 0.3 * k)
        } else {
            let a = t - REL
            // the release: the caster flashed white, a flare, a white core blown open
            if a < 0.07 { let c = a < 0.035 ? FX.white : C[6]; p.mask(A.mask, Double(A.x), Double(A.y), { _, _ in c }) }
            if a < 0.22 {
                let q = a / 0.22
                FX.flare(p, CX, CY, 46 * pow(1 - q, 1.4), 1 - q, C)
                if q < 0.3 { p.circle(CX, CY, 12 * (1 - q * 2.5) + 1.5, FX.white) }
            }
            // bolts every way, struck and flickering
            for (i, b) in bolts.enumerated() {
                let ba = Int(FX.floor((t - b.t0) * 30 + 1e-4))
                if t < b.t0 || ba >= Self.BK.count { continue }
                FXLightning.stroke(p, FXLightning.zigzag(FX.rng(seed, 3, Double(i), Double(ba >> 1)), CX, CY, b.x1, b.y1, 0.25, 0.75), Self.BK[ba], C,
                                   ba == 0 ? 0.95 : 0.75, hero: ba == 0)
                if b.y1 > -1 { p.glow(b.x1, -3, 18, C[5], 0.5 * Self.BK[ba]) }
            }
            // a ring bursting out with a fainter echo inside it
            let q = a / 0.45
            if q < 1 {
                let r = 8 + 80 * FX.Ease.outCubic(q), rc = q < 0.25 ? FX.white : C[5]
                p.ring(CX, CY, r, Swift.max(1, 3 * (1 - q)), { _, _ in rc }, { _, g in CY + sin(g) * r > -1 ? 0 : 1.1 - q })
                let r2 = 6 + 56 * FX.Ease.outCubic(Swift.min(1, q * 1.3)), c4 = C[4]
                p.ring(CX, CY, r2, 1, { _, _ in c4 }, { _, g in CY + sin(g) * r2 > -1 ? 0 : 0.8 - q })
                p.glow(CX, CY - 6, Swift.min(r * 0.9, 46), C[3], 0.42 * (1 - q) * (1 - q))
            }
            // the charge bleeds off in a few last crackles at the hand
            if a > 0.15 && a < 0.5 {
                let qq = FX.rng(seed, 8, Double(f)), ang = qq.range(0, FX.tau), l = qq.range(5, 10)
                FXLightning.crackle(p, FXLightning.zigzag(qq, CX, CY, CX + cos(ang) * l, CY + sin(ang) * l, 0.45, 0.3), 0.8 * (1 - (a - 0.15) / 0.35) + 0.15, C, 0.3)
            }
        }
        ps.draw(p, .front)
        lights.draw(p)
    }
}

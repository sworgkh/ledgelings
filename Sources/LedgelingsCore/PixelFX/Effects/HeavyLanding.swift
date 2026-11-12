// Heavy landing: the floor dents and cracks under the feet, two rings of dust roll out along the floor one after
// the other, and pebbles hop away. pixelfx's `impacts/heavy-landing` (MIT); the rocks, grit and dust adapt
// Sprite Fusion's open-source explosion (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT,
// Copyright (c) 2026 Hugo Duprez.

import Foundation

final class FXHeavyLanding: FXEffect {
    static let meta = FXMeta(id: "impacts/heavy-landing", size: (176, 80), origin: (88, 60), duration: 1.6, loop: false,
                             palette: ["#1c1a24", "#2f2a3a", "#4a4258", "#6b6280", "#9088a4", "#bdb6cc", "#e6e1ee"], seed: 14)
    static let stoneColor = FX.hex("#4a3f69")

    /// A pebble: tumbles, bounces and settles like pixelfx's Bits, and keeps its outline and last speed.
    final class Pebble {
        var x: Double, y: Double, vx: Double, vy: Double, a: Double, va: Double, s: Double, life: Double
        let g = 1.0, drag = 0.5, bounce = 0.55, pts: [Double]
        var rest = false, pvy = 0.0
        init(x: Double, y: Double, vx: Double, vy: Double, a: Double, va: Double, s: Double, life: Double, pts: [Double]) {
            self.x = x; self.y = y; self.vx = vx; self.vy = vy; self.a = a; self.va = va; self.s = s; self.life = life; self.pts = pts
        }
    }

    let C: [FXColor], st: FXImpacts.Stone, R: Rng
    let back: FXParticles, front: FXParticles
    var bits: [Pebble] = []
    let cracks: [FXImpacts.Crack]
    let DUST: FXColor, LIT: FXColor, PH: Double
    var t = 0.0

    init(_ o: FXOptions) {
        C = FX.fit(o.palette, 7); st = FXImpacts.stone(Self.stoneColor); R = Rng(o.seed)
        let R = self.R
        back = FXParticles(rng: R, ground: { _ in 0 }); front = FXParticles(rng: R, ground: { _ in 0 })
        cracks = FXImpacts.makeCracks(R, 6, len: (8, 20), dive: 0.7, maxY: 12, forks: 0.4, x0: (2, 6))
        DUST = FX.mix(st.dust, C[5], 0.4); LIT = FX.mix(DUST, FX.white, 0.3); PH = R.range(0, FX.tau)
        // puffs riding each ring out along the floor
        let ring = { (n: Int, v0: Double, v1: Double, size: (Double, Double), delay: Double) in
            for i in 0..<n {
                let g = (Double(i) / Double(n)) * FX.tau + R.range(-0.1, 0.1), v = R.range(v0, v1), far = sin(g) < 0
                let vy = sin(g) * v * 0.16 - R.range(2, 10), life = R.range(0.45, 0.8), c = R.chance(0.45) ? self.LIT : self.DUST
                let sz = R.range(size.0, size.1), dl = delay + R.range(0, 0.03)
                (far ? self.back : self.front).spawn(.dust, cos(g) * 4, sin(g) * 0.7 - 1, cos(g) * v, vy, life, c, sz, dl)
            }
        }
        ring(20, 140, 190, (2.2, 3.4), 0.01)
        ring(18, 70, 110, (3.4, 5.4), 0.12)
        // and a low cloud at the feet that rises a little and hangs
        for i in 0..<12 {
            let s = R.sign(), up = i < 6
            let x = s * R.range(2, 10), y = -R.range(1, 4), vx = s * R.range(10, 35) * (up ? 0.6 : 1), vy = -(up ? R.range(25, 60) : R.range(4, 12))
            let life = R.range(0.55, 0.9), c = R.chance(0.5) ? LIT : DUST, sz = R.range(3, 5), dl = R.range(0.02, 0.1)
            (i % 2 != 0 ? front : back).spawn(.dust, x, y, vx, vy, life, c, sz, dl)
        }
        // pebbles that hop away along the floor, and grit
        for _ in 0..<12 {
            let s = R.sign(), v = R.range(50, 130)
            let x = s * R.range(3, 8), vy = -R.range(140, 230), life = R.range(1, 1.45), a = R.range(0, FX.tau), va = s * R.range(8, 16)
            let sz: Double = R.chance(0.3) ? 2 : 1, pts = FXImpacts.rockShape(R)
            bits.append(Pebble(x: x, y: -1, vx: s * v, vy: vy, a: a, va: va, s: sz, life: life, pts: pts))
        }
        for _ in 0..<24 {
            let s = R.sign(), a = -Double.pi / 2 + s * R.range(0.3, 1.2), v = R.range(60, 170)
            let x = s * R.range(2, 7), life = R.range(0.6, 1.1), c = R.pick([st.light, st.body, st.lip]), sz: Double = R.chance(0.3) ? 2 : 1
            front.spawn(.grit, x, -1, cos(a) * v, sin(a) * v, life, c, sz)
        }
    }

    func stepBits(_ dt: Double) {
        var i = bits.count - 1
        while i >= 0 {
            defer { i -= 1 }
            let b = bits[i]
            b.life -= dt
            if b.life <= 0 { bits.remove(at: i); continue }
            if b.rest { continue }
            b.vy += FX.gravity * b.g * dt
            b.vx -= b.vx * b.drag * dt
            b.vy -= b.vy * b.drag * dt
            b.x += b.vx * dt
            b.y += b.vy * dt
            b.a += b.va * dt
            let floor = 0.0, sp = b.vy
            if b.g <= 0 || b.y < floor || sp <= 0 { continue }
            b.y = floor - 0.01
            if b.bounce > 0 && sp > 70 { b.vy = -sp * b.bounce; b.vx *= 0.7; b.va *= 0.6 }
            else { b.rest = true; b.vx = 0; b.vy = 0 }
        }
    }

    func update(_ dt: Double) {
        t += dt
        for b in bits { b.pvy = b.vy }
        stepBits(dt)
        for b in bits where b.pvy > 80 && b.vy <= 0 {
            let vx = R.sign() * R.range(6, 20), vy = -R.range(2, 10), life = R.range(0.25, 0.45), sz = R.range(1, 1.8)
            front.spawn(.dust, b.x, -0.5, vx, vy, life, DUST, sz)
            b.pvy = 0
        }
        back.update(dt)
        front.update(dt)
    }

    /// The dent: the floor's edge pressed into a shallow dish, scuffed lips either side.
    func dent(_ p: Painter, _ k: Double) {
        for xi in -10...9 {
            let x = Double(xi), q = abs(x + 0.5) / 10, dep = FX.round(1.8 * (1 - q * q))
            if q < 0.82 {
                var y = 0.0
                while y < dep { p.dot(x, y, FXImpacts.SOOT, k); y += 1 }
                p.dot(x, dep, st.lip, k)
            } else { p.dot(x, -1, q > 0.92 ? st.light : st.lip, k) }
        }
    }

    /// The two dust rings themselves: soft bands on the floor, the second slower, lumpier and later.
    func rings(_ p: Painter, _ far: Bool) {
        let st = self.st
        for (t0, dur, r1, w, k0, edge) in [(0.01, 0.45, 58.0, 4.5, 0.75, true), (0.12, 0.85, 42.0, 6.0, 0.8, false)] {
            let g = (t - t0) / dur
            if g <= 0 || g >= 1 { continue }
            let r = 6 + r1 * FX.Ease.outCubic(g)
            FXImpacts.dustRing(p, 0, 0, r, w * (1 + g), k0 * pow(1 - g, 1.2) * Swift.min(1, g / 0.06), DUST,
                               sy: 0.2, ph: PH + t0 * 10, brk: g * 0.8, half: far ? -1 : 1)
            // the fast ring's leading edge: a crisp lit band on the floor
            if edge && g < 0.75 {
                FX.band(p, 0, 0.5, r + 2, 0.2, Swift.max(1, 2.5 * (1 - g)), 1.1 - g / 0.75, [st.body, st.light, LIT, FX.white], { a in (sin(a) < 0) == far })
            }
        }
    }

    func drawBack(_ p: Painter, _ tt: Double) {
        let D = Self.meta.duration, fade = 1 - FX.smooth(D - 0.5, D - 0.1, t), t = self.t, W = FX.white
        dent(p, fade)
        FXImpacts.drawCracks(p, cracks, { c in c.len * FX.Ease.outCubic(FX.clamp((t - c.t0) / 0.08)) }, { _ in 0 }, [W, W, W, W], FXImpacts.SOOT, st.light, fade)
        rings(p, true)
        back.draw(p, nil)
    }

    func draw(_ p: Painter, _ tt: Double) {
        let C = self.C
        rings(p, false)
        front.draw(p, nil)
        for b in bits { FXImpacts.rock(p, x: b.x, y: b.y, a: b.a, s: b.s, life: b.life, pts: b.pts, st) }
        // the thud: a flat streak of light along the floor for a frame or two
        if t < 0.035 { p.ellipse(0, 0, 15, 2.5, { d, _ in d < 0.55 ? FX.white : C[6] }, { _, _ in 1 }) }
        else if t < 0.07 { for xi in -22...22 { let x = Double(xi); p.dot(x, 0, abs(x) < 10 ? FX.white : C[5], 1 - abs(x) / 24) } }
        if t < 0.12 { p.glowLine(-20, 0, 20, 0, 8, C[6], 0.45 * (1 - t / 0.12)) }
    }
}

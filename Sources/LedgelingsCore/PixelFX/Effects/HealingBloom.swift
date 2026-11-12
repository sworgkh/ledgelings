// Healing bloom: a sprout pushes up and unfurls, a bud swells and opens round a glowing golden heart in a flare
// of healing light; its petals lift away one by one as motes. pixelfx's `nature/healing-bloom` (MIT); the healing
// light adapts Sprite Fusion's open-source heal (https://www.spritefusion.com/pixel-art-vfx/heal), MIT,
// Copyright (c) 2026 Hugo Duprez.

import Foundation

final class FXHealingBloom: FXEffect {
    static let meta = FXMeta(id: "nature/healing-bloom", size: (124, 120), origin: (62, 108), duration: 3.3, loop: false,
                             palette: ["#0c1a10", "#173a1a", "#24582a", "#357a34", "#52a03e", "#86c84e", "#c4ec7a", "#f4ffd0"], seed: 4)
    static let petalRamp = FX.ramp(["#4a1a3a", "#a8406e", "#ec8ab0", "#ffd8e8"])
    static let heartRamp = FX.ramp(["#a8641a", "#f0b42e", "#ffe680", "#fffbe0"])
    static let STEM = 0.42, BUD = 0.75, OPEN = 1.05, LIFT = 1.7, WILT = 2.4, H = 36.0, NPET = 6

    /// A bevelled cross of light.
    static func cross(_ p: Painter, _ x: Double, _ y: Double, _ L: Int, _ C: [FXColor], _ a: Double, _ glint: Bool) {
        let X = FX.round(x), Y = FX.round(y)
        func ins(_ dx: Int, _ dy: Int) -> Bool { (dx == 0 && abs(dy) <= L) || (dy == 0 && abs(dx) <= L) }
        for dy in (-L - 1)...(L + 1) {
            for dx in (-L - 1)...(L + 1) {
                if ins(dx, dy) { p.dot(X + Double(dx), Y + Double(dy), glint && dx == 0 && dy == 0 ? FX.white : dy < 0 || dx < 0 ? C[6] : C[5], a) }
                else if L > 1 && (ins(dx - 1, dy) || ins(dx + 1, dy) || ins(dx, dy - 1) || ins(dx, dy + 1)) { p.dot(X + Double(dx), Y + Double(dy), C[2], a * 0.8) }
            }
        }
        p.glow(x, y, 5 + Double(L) * 2, C[6], 0.35 * a)
    }

    /// pixelfx's glow when its strength is NaN (the floor's end pixel lies past fw, so sqrt(1 - u) is NaN): every
    /// pixel it covers has its light set to nothing, as `NaN | 0` gives 0.
    static func nanGlow(_ p: Painter, _ x: Double, _ y: Double, _ r: Double) {
        let cx = p.toX(x, y), cy = p.toY(x, y)
        let x0 = Int(FX.floor(cx - r)), x1 = Int(FX.ceil(cx + r)), y0 = Int(FX.floor(cy - r)), y1 = Int(FX.ceil(cy + r))
        for sy in y0...y1 {
            let dy = (Double(sy) + 0.5 - cy) / r
            for sx in x0...x1 {
                let dx = (Double(sx) + 0.5 - cx) / r
                if dx * dx + dy * dy >= 1 { continue }
                let lx = sx - p.ox, ly = sy - p.oy
                if lx < 0 || ly < 0 || lx >= p.w || ly >= p.h { continue }
                p.frame.light[ly * p.w + lx] = 0xff00_0000
            }
        }
    }

    final class Petal {
        let az: Double, at: Double
        var gone = false
        init(az: Double, at: Double) { self.az = az; self.at = at }
    }
    final class Flying {
        var x: Double, y: Double, vx: Double, vy: Double, a: Double, va: Double, fl = 0.0, vf: Double, life: Double, max: Double
        init(x: Double, y: Double, vx: Double, vy: Double, a: Double, va: Double, vf: Double, life: Double) {
            self.x = x; self.y = y; self.vx = vx; self.vy = vy; self.a = a; self.va = va; self.vf = vf; self.life = life; max = life
        }
    }
    struct Glyph { let x: Double, y: Double, t0: Double, life: Double, L: Int, seed: Double }

    let C: [FXColor], Pt: [FXColor], Ht: [FXColor], R: Rng
    let ps: FXParticles, lights = FXLights()
    var flying: [Flying] = [], glyphs: [Glyph] = [], petals: [Petal] = []
    var t = 0.0, popped = false, sprouted = false

    init(_ o: FXOptions) {
        C = FX.fit(o.palette, 8); Pt = FX.fit(Self.petalRamp, 4); Ht = FX.fit(Self.heartRamp, 4); R = Rng(o.seed)
        ps = FXParticles(rng: R, ground: { _ in 0 }, sparks: [Ht[3], Ht[2], Ht[1], Ht[0]])
        for i in 0..<Self.NPET {
            let di = Double(i)
            petals.append(Petal(az: (di / Double(Self.NPET)) * FX.tau + 0.3, at: Self.LIFT + FX.mod(di * 0.37, 1) * 0.55))
        }
    }

    func grow() -> Double { FX.Ease.outCubic(FX.clamp(t / Self.STEM)) * (1 - FX.Ease.inCubic(FX.clamp((t - Self.WILT) / 0.6))) }
    func sway() -> Double { sin(t * 2.6) * 1.4 * FX.smooth(0.2, 0.6, t) }
    /// The stem's points, base to tip: a gentle S that sways.
    func stem() -> [(Double, Double)] {
        let g = grow(), H = Self.H
        var pts: [(Double, Double)] = []
        for i in 0...12 {
            let s = Double(i) / 12
            pts.append((sin(s * 3.2) * 2.2 * s + sway() * s * s, (1 - g) * H * 1.1 - s * H))
        }
        return pts
    }
    func open() -> Double { FX.Ease.outBack(FX.clamp((t - Self.BUD) / (Self.OPEN - Self.BUD)), 1.4) }

    func update(_ dt: Double) {
        t += dt
        let t = self.t, C = self.C, Ht = self.Ht, Pt = self.Pt, R = self.R, D = Self.meta.duration
        let f = Swift.min(1, dt * 120), top = stem()[12]
        if !sprouted {
            sprouted = true
            for _ in 0..<8 {
                let x = R.range(-3, 3), vx = R.range(-40, 40), vy = -R.range(40, 100), life = R.range(0.5, 0.8), c = R.pick([C[2], C[3]])
                ps.spawn(.grit, x, -1, vx, vy, life, c, 1)
            }
            for _ in 0..<3 {
                let x = R.range(-3, 3), vx = R.sign() * R.range(10, 30), vy = -R.range(4, 10), life = R.range(0.4, 0.6), sz = R.range(1.5, 2.5)
                ps.spawn(.dust, x, -1, vx, vy, life, C[3], sz)
            }
        }
        // the bud draws light in as it swells
        if t > Self.STEM && t < Self.BUD && R.chance(0.3 * f) {
            let a = R.range(0, FX.tau), d = R.range(14, 26), x = top.0 + cos(a) * d, y = top.1 - 3 + sin(a) * d * 0.8
            let life = R.range(0.18, 0.26), c = R.chance(0.5) ? Ht[2] : C[6]
            ps.spawn(.streak, x, y, (top.0 - x) * 3.4, (top.1 - 3 - y) * 3.4, life, c)
        }
        if !popped && t >= Self.OPEN - 0.12 {
            popped = true
            lights.add(top.0, top.1 - 3, 22, FX.white, 0.45, 0.08)
            lights.add(top.0, top.1 - 3, 70, Ht[2], 0.5, 0.8)
            for _ in 0..<16 {
                let a = R.range(0, FX.tau), sp = R.range(40, 120)
                let life = R.range(0.4, 0.8), c = R.chance(0.5) ? Ht[3] : C[7]
                ps.spawn(.mote, top.0, top.1 - 3, cos(a) * sp, sin(a) * sp - 20, life, c, 0.7)
            }
            for _ in 0..<5 {
                let x = top.0 + R.range(-10, 10), y = top.1 - R.range(0, 14), life = R.range(0.3, 0.6), sz = R.range(1, 2.4), dl = R.range(0, 0.3)
                ps.spawn(.star, x, y, 0, -6, life, Ht[3], sz, dl)
            }
        }
        // while it blooms: crosses and motes of light drift up round it
        if t > Self.OPEN && t < Self.WILT && R.chance(0.13 * f) {
            let x = R.range(-22, 22), y = -R.range(2, 36), life = Swift.min(R.range(0.7, 1.1), D - 0.05 - t), L = R.chance(0.35) ? 3 : 2, seed = R.next() * 9
            glyphs.append(Glyph(x: x, y: y, t0: t, life: life, L: L, seed: seed))
        }
        if t > Self.OPEN - 0.1 && t < Self.WILT && R.chance(0.35 * f) {
            let x = R.range(-20, 20), y = -R.range(0, 8), vx = R.range(-6, 6), vy = -R.range(25, 55), life = Swift.min(R.range(0.6, 1.1), D - 0.05 - t)
            let c = R.chance(0.6) ? C[6] : Ht[2], sz: Double = R.chance(0.3) ? 2 : 1
            ps.spawn(.ember, x, y, vx, vy, life, c, sz)
        }
        var i = glyphs.count - 1
        while i >= 0 { if t - glyphs[i].t0 > glyphs[i].life { glyphs.remove(at: i) }; i -= 1 }
        // petals let go one by one and lift away, turning, until they twinkle out
        for q in petals where !q.gone && t >= q.at {
            q.gone = true
            let e = Double.pi / 2 - 0.15, dx = sin(e) * cos(q.az), L = 10.0
            let vx = dx * 30 + R.range(-10, 10), vy = -R.range(25, 45), va = R.range(-5, 5), vf = R.range(5, 9), life = Swift.min(R.range(0.75, 1.0), D - 0.45 - t)
            flying.append(Flying(x: top.0 + dx * L * 0.6, y: top.1 - 3 - cos(e) * L * 0.6, vx: vx, vy: vy, a: atan2(-cos(e), dx), va: va, vf: vf, life: life))
        }
        i = flying.count - 1
        while i >= 0 {
            defer { i -= 1 }
            let q = flying[i]
            q.life -= dt
            if q.life <= 0 {
                ps.spawn(.star, q.x, q.y, 0, -8, Swift.min(0.35, D - 0.05 - t), Pt[3], 1.8)
                flying.remove(at: i)
                continue
            }
            q.vx -= q.vx * 1.5 * dt
            q.vy -= q.vy * 0.8 * dt + 10 * dt
            q.x += q.vx * dt + sin(q.fl) * 12 * dt
            q.y += q.vy * dt
            q.a += q.va * dt
            q.fl += q.vf * dt
        }
        ps.update(dt)
        lights.update(dt)
    }

    /// A petal: from closed round the bud to splayed open round the heart, foreshortened by where it points.
    func petal(_ p: Painter, _ q: Petal, _ top: (Double, Double)) {
        let Pt = self.Pt
        let op = open(), e = FX.lerp(0.15, Double.pi / 2 - 0.2, op), dx = sin(e) * cos(q.az), dz = sin(e) * sin(q.az), dy = -cos(e)
        let L = FX.lerp(8, 12, op), len = L * hypot(dx, dy), ang = atan2(dy, dx), back = dz < 0, cy = top.1 - 3
        if len < 1.5 { return }
        FXNature.drawLeaf(p, top.0 + dx * L * 0.5, cy + dy * L * 0.5, len + 1, 3 + (1 - abs(dz)) * 0.8, ang, back ? 0.9 : 0.2,
                          back ? [Pt[0], Pt[0], Pt[1], Pt[2]] : [Pt[0], Pt[1], Pt[2], Pt[3]])
    }

    func drawBack(_ p: Painter, _ tt: Double) {
        let t = self.t, C = self.C, Ht = self.Ht, OPEN = Self.OPEN, WILT = Self.WILT
        let bloom = FX.smooth(OPEN - 0.15, OPEN + 0.2, t) * (1 - FX.smooth(WILT - 0.2, WILT + 0.5, t)), top = stem()[12]
        // a column of soft healing light, and a lit ring on the floor that blooms out as it opens
        var h = 0.0
        while h < 70 { p.glow(0, -h, 22, C[5], 0.12 * bloom * (1 - h / 80)); h += 7 }
        let k = FX.clamp((t - OPEN + 0.12) / 0.6)
        if k > 0 && k < 1 {
            FX.band(p, 0, 0.5, 6 + 30 * FX.Ease.outCubic(k), 0.18, Swift.max(1, 3 * (1 - k)), 1.1 - k, [C[3], C[5], Ht[2], Ht[3]], { g in sin(g) < 0 })
        }
        let fw = 6 + 16 * FX.smooth(0, 0.8, t)
        var xi = Int(FX.floor(-fw))
        while Double(xi) <= fw {
            let x = Double(xi), u = abs(x) / fw, a = (1 - u).squareRoot() * FX.smooth(0, 0.4, t) * (1 - FX.smooth(WILT, WILT + 0.6, t))
            p.dot(x, 0, u < 0.3 ? C[6] : u < 0.65 ? C[5] : C[4], a)
            if xi % 5 == 0 { if a.isNaN { Self.nanGlow(p, x, 0, 8) } else { p.glow(x, 0, 8, C[5], 0.2 * a * (1 - u)) } }
            xi += 1
        }
        // the far petals sit behind the heart
        if t > Self.BUD - 0.05 { for q in petals where sin(q.az) < 0 && !q.gone { petal(p, q, top) } }
        ps.draw(p, .back)
    }

    func draw(_ p: Painter, _ tt: Double) {
        let t = self.t, C = self.C, Ht = self.Ht, Pt = self.Pt, WILT = Self.WILT, OPEN = Self.OPEN, STEM = Self.STEM, BUD = Self.BUD
        let pts = stem(), top = pts[12], g = grow()
        if g > 0.02 {
            // the stem: a 2 px shoot, lit down its left side
            for i in 1..<pts.count {
                let (x0, y0) = pts[i - 1], (x1, y1) = pts[i]
                if y1 > 0 { continue }
                p.line(x0, y0, x1, y1, C[5])
                p.line(x0 + 1, y0, x1 + 1, y1, C[3])
            }
            // leaves unfurl off it
            for (i, sd, d) in [(4, -1.0, 0.1), (7, 1.0, 0.22)] {
                let lk = FX.Ease.outBack(FX.clamp((t - d - 0.12) / 0.3), 1.6) * (1 - FX.smooth(WILT, WILT + 0.5, t) * 0.4), (x, y) = pts[i]
                if lk <= 0 || y > -1 { continue }
                let la = sd < 0 ? -2.6 + 0.4 * (1 - lk) : -0.55 - 0.4 * (1 - lk)
                FXNature.drawLeaf(p, x + cos(la) * 6 * lk, y + sin(la) * 6 * lk, 12 * lk, 3.4, la, 0.25, [C[1], C[3], C[5], C[6]])
            }
            // the bud, then the heart once it opens
            if t > STEM - 0.1 && t < OPEN - 0.1 {
                let b = FX.clamp((t - STEM + 0.1) / (BUD - STEM)), w = 2 + 2.5 * b, h = 3.5 + 5 * b
                p.ellipse(top.0, top.1 - h * 0.6, w, h, { d, a in cos(a) < -0.2 ? Pt[2] : d > 0.7 ? Pt[0] : Pt[1] }, { _, _ in 1 })
                p.glow(top.0, top.1 - h * 0.6, 8 + 8 * b, Ht[2], 0.25 * b)
            }
        }
        for q in petals where sin(q.az) >= 0 && !q.gone && t > BUD - 0.05 { petal(p, q, top) }
        if t > OPEN - 0.12 && t < WILT + 0.3 {
            let pulse = 0.85 + 0.15 * sin(t * 9), k = 1 - FX.smooth(WILT - 0.3, WILT + 0.3, t), cy = top.1 - 4
            p.circle(top.0, cy, 3.3 * k, Ht[1])
            p.circle(top.0 - 0.5, cy - 0.5, 2.2 * k, Ht[2])
            p.px(top.0 - 1, cy - 1, Ht[3])
            p.glow(top.0, cy, 16 * pulse, Ht[2], 0.5 * k)
            p.glow(top.0, cy, 34, C[5], 0.2 * k)
        }
        let e = t - OPEN + 0.12
        if e > 0 && e < 0.16 { FX.sparkle(p, top.0, top.1 - 3, 10 * (1 - e / 0.16), Ht[3], Ht[2], 0.6) }
        for q in flying { FXNature.drawLeaf(p, q.x, q.y, 6, 2.2, q.a, q.fl, [Pt[0], Pt[1], Pt[2], Pt[3]], Swift.min(1, q.life / 0.3)) }
        for q in glyphs {
            let k = (t - q.t0) / q.life
            Self.cross(p, q.x + sin(k * 5 + q.seed) * 2, q.y - k * 24, q.L, C, sin(Double.pi * k), sin(k * 14 + q.seed) > 0.8)
        }
        ps.draw(p, .front)
        lights.draw(p)
    }
}

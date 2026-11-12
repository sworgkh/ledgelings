// Magic circle cast: a circle draws itself on the floor, runes ignite one by one, it flashes, and a column of
// light fires up and breaks apart into glints. pixelfx's `arcane/magic-circle-cast` (MIT); the column is adapted
// from Sprite Fusion's open-source holy light (https://www.spritefusion.com/pixel-art-vfx/holy-light), MIT,
// Copyright (c) 2026 Hugo Duprez.

import Foundation

final class FXMagicCircle: FXEffect {
    static let meta = FXMeta(id: "arcane/magic-circle-cast", size: (200, 220), origin: (100, 192), duration: 3.9, loop: false,
                             palette: ["#140a26", "#2b1252", "#481c88", "#6b2cc0", "#9a48ec", "#c684ff", "#ecc8ff", "#ffffff"], seed: 6)
    // the circle on the floor (plane px; the floor squashes depth by SY), the column, the beats
    static let R = 40.0, R2 = 35.0, RI = 24.0, RR = 30.0, SY = 0.3, TOP = 192.0, W = 11.0, NRUNE = 8
    static let PEN = (0.04, 0.42), PEN2 = (0.1, 0.48), INNER = (0.3, 0.6), STAR = (0.52, 0.88), RUNES = (0.9, 1.3)
    static let FLASH = 1.52, BREAK = 2.42, GONE = 3.45, END = 3.9

    static func wrap(_ a: Double) -> Double { FX.mod(FX.mod(a, FX.tau) + FX.tau, FX.tau) }
    static func fromFront(_ g: Double) -> Double { abs(atan2(sin(g - Double.pi / 2), cos(g - Double.pi / 2))) }
    static func outerAt(_ g: Double, _ w: (Double, Double)) -> Double { w.0 + (fromFront(g) / Double.pi) * (w.1 - w.0) }
    static func innerAt(_ g: Double) -> Double { INNER.0 + (wrap(g + Double.pi / 2) / FX.tau) * (INNER.1 - INNER.0) }
    static func runeAngle(_ k: Int) -> Double { -Double.pi / 2 + ((Double(k) + 0.5) * FX.tau) / Double(NRUNE) }
    static func runeLit(_ k: Int) -> Double { RUNES.0 + (Double(k) * (RUNES.1 - RUNES.0)) / Double(NRUNE - 1) }
    static func runeOut(_ k: Int) -> Double { BREAK + 0.2 + Double(k) * 0.08 }

    /// How bright the drawn circle burns: settled while it's drawn, swelling as the runes light, white at the flash.
    static func level(_ t: Double) -> Double {
        if t < RUNES.0 { return 0.55 }
        if t < FLASH { return 0.55 + 0.4 * FX.smooth(RUNES.0, FLASH, t) }
        if t < FLASH + 0.07 { return 1.2 }
        if t < BREAK { return 0.92 }
        return 0.92 * (1 - FX.smooth(BREAK, GONE, t))
    }

    struct Strand { let o: Double, w: Double, f: Double }
    struct Edge { let p0: (Double, Double), p1: (Double, Double), t0: Double, dur: Double }

    let C: [FXColor], S: Double, Rg: Rng
    let ps: FXParticles, lights = FXLights()
    let COL: [FXColor]
    var strands: [Strand] = [], edges: [Edge] = []
    var t = 0.0, flashed = false, broke = false
    var out = [Bool](repeating: false, count: NRUNE)

    init(_ o: FXOptions) {
        C = FX.fit(o.palette, 8); S = o.seed; Rg = Rng(S)
        ps = FXParticles(rng: Rg, ground: { _ in 0 }, sparks: [FX.white, C[6], C[5], C[4]])
        COL = [FX.white, C[6], C[5], C[4], C[3]]
        for _ in 0..<9 {
            let o = Rg.range(-0.85, 0.85), w = Rg.range(0.04, 0.1), f = Rg.range(1, 3)
            strands.append(Strand(o: o, w: w, f: f))
        }
        // the hexagram: two triangles inside the inner ring, each drawn edge by edge
        let tri = { (a0: Double) in (0..<3).map { k -> (Double, Double) in
            let a = a0 + (Double(k) * FX.tau) / 3
            return (cos(a) * Self.RI, sin(a) * Self.RI)
        } }
        let A = tri(-Double.pi / 2), Bt = tri(Double.pi / 2), ST = Self.STAR
        for k in 0..<3 {
            for T in [A, Bt] {
                edges.append(Edge(p0: T[k], p1: T[(k + 1) % 3], t0: ST.0 + (Double(k) * (ST.1 - ST.0)) / 3, dur: (ST.1 - ST.0) / 3))
            }
        }
    }

    func lineCol(_ lvl: Double, _ age: Double) -> FXColor {
        age < 0.05 ? FX.white : age < 0.16 ? C[6] : lvl > 1 ? FX.white : lvl > 0.8 ? C[6] : lvl > 0.45 ? C[5] : lvl > 0.28 ? C[4] : C[3]
    }
    func lineA(_ lvl: Double) -> Double { FX.clamp(lvl / 0.3) }

    /// A straight line on the floor plane, drawn by a pen from p0 to p1 over [t0, t0 + dur]; only the far or near part.
    func planeLine(_ p: Painter, _ p0: (Double, Double), _ p1: (Double, Double), _ t0: Double, _ dur: Double, _ lvl: Double, _ far: Bool) {
        let s = FX.clamp((t - t0) / dur), SY = Self.SY
        if s <= 0 { return }
        var u0 = 0.0, u1 = s
        let v0 = p0.1, v1 = p1.1
        if (v0 < 0) != (v1 < 0) {
            let uc = v0 / (v0 - v1)
            if (v0 < 0) == far { u1 = Swift.min(u1, uc) } else { u0 = uc }
        } else if (v0 < 0) != far { return }
        if u1 <= u0 { return }
        let P = { (u: Double) in (p0.0 + (p1.0 - p0.0) * u, (v0 + (v1 - v0) * u) * SY) }
        let (xa, ya) = P(u0), (xb, yb) = P(u1), t = self.t
        p.line(xa, ya, xb, yb, { q in self.lineCol(lvl, t - (t0 + (u0 + (u1 - u0) * q) * dur)) }, lineA(lvl))
    }

    func circle(_ p: Painter, _ far: Bool) {
        let t = self.t, R = Self.R, R2 = Self.R2, SY = Self.SY
        if t >= Self.GONE { return }
        let lvl = Self.level(t), a = lineA(lvl)
        let keep: (Double) -> Bool = far ? { g in sin(g) < 0 } : { g in sin(g) >= 0 }
        let ring = { (r: Double, when: @escaping (Double) -> Double, chase: ((Double) -> Bool)?) in
            FXArcane.floorRing(p, 0, 0, r, SY, { g in chase != nil && chase!(g) ? FX.white : self.lineCol(lvl, t - when(g)) },
                               { g in t < when(g) ? 0 : a }, keep)
        }
        // from the moment the runes start to light, two sparks of light chase round the outer ring, faster and faster
        var chase: ((Double) -> Bool)? = nil
        if t > Self.RUNES.0 && t < Self.BREAK {
            let run = (t - Self.RUNES.0) * 5 + pow(t - Self.RUNES.0, 2) * 4
            chase = { g in [0, Double.pi].contains { o in abs(atan2(sin(g - run - o), cos(g - run - o))) < 0.22 } }
        }
        ring(R, { g in Self.outerAt(g, Self.PEN) }, chase)
        ring(R2, { g in Self.outerAt(g, Self.PEN2) }, nil)
        ring(Self.RI, Self.innerAt, nil)
        // ticks across the band between the two outer rings
        for j in 0..<32 {
            let g = ((Double(j) + 0.5) * FX.tau) / 32
            if (sin(g) < 0) != far { continue }
            let when = Self.outerAt(g, Self.PEN2) + 0.03
            if t < when { continue }
            p.line(cos(g) * R2, sin(g) * R2 * SY, cos(g) * R, sin(g) * R * SY, lineCol(lvl, t - when), a * (j % 2 != 0 ? 0.6 : 1))
        }
        for e in edges { planeLine(p, e.p0, e.p1, e.t0, e.dur, lvl, far) }
    }

    /// The runes stand on the circle; dim when the inner pen passes, lit one by one, out one by one.
    func runes(_ p: Painter, _ far: Bool) {
        let t = self.t, C = self.C, SY = Self.SY, RR = Self.RR
        for k in 0..<Self.NRUNE {
            let g = Self.runeAngle(k)
            if (sin(g) < 0) != far { continue }
            let x = cos(g) * RR, y0 = sin(g) * RR * SY, lit = t - Self.runeLit(k), gone = FX.clamp((t - Self.runeOut(k)) / 0.25)
            if t < Self.innerAt(g) || gone >= 1 { continue }
            if lit < 0 {
                FXArcane.glyph(p, k, x, y0 - 1, C[3])
                continue
            }
            let rise = 3 * FX.Ease.outBack(FX.clamp(lit / 0.2), 2.4), bob = lit > 0.2 ? sin(t * 5 + Double(k)) * 0.5 : 0, y = y0 - 1 - rise + bob
            let hot = lit < 0.07 || (t > Self.FLASH && t < Self.FLASH + 0.07), lvl = Self.level(t)
            FXArcane.glyph(p, k, x, y, hot ? FX.white : lvl > 0.8 ? FX.white : C[6], 1 - gone, hot ? C[6] : C[4])
            if lit < 0.1 { FX.sparkle(p, x, y - 2, 4 * (1 - lit / 0.1) + 1, C[6], C[5], 0.5) }
            p.glow(x, y - 2, 8, C[5], (0.3 + 0.3 * lvl) * (1 - gone))
            p.glow(x, y0, 6, C[4], 0.2 * (1 - gone))
        }
    }

    /// The column of light: the thread that climbs first, then the beam that fires up, holds and breaks apart.
    func column(_ p: Painter) {
        let t = self.t, C = self.C, FLASH = Self.FLASH, BREAK = Self.BREAK, TOP = Self.TOP, W = Self.W
        if t < FLASH - 0.22 || t > BREAK + 0.6 { return }
        if t < FLASH {
            let a = FX.smooth(FLASH - 0.22, FLASH - 0.04, t), top = -(TOP - 10) * FX.Ease.outCubic(a)
            var y = -1.0
            while y >= top { p.dot(0, y, y > top + 6 ? C[6] : FX.white, a * (0.35 + 0.65 * (1 + y / TOP))); y -= 1 }
            p.glow(0, top, 9, C[6], 0.5 * a)
            p.glow(0, -6, 24, C[5], 0.4 * a)
            return
        }
        let u = t - FLASH, brk = FX.clamp((t - BREAK) / 0.45), top = -TOP * FX.Ease.outExpo(FX.clamp(u / 0.09))
        let w = t < BREAK ? W * (1 + 0.38 * exp(-u * 9)) : W * (1 - FX.Ease.outCubic(brk) * 0.85)
        let fade = 1 - FX.smooth(BREAK + 0.25, BREAK + 0.55, t), white = u < 0.067
        if fade <= 0 { return }
        var yi = 3
        let yEnd = Int(FX.ceil(top))
        while yi >= yEnd {
            let y = Double(yi), hi = -yi, h = Double(hi)
            let ww = w * (1 + 0.5 * exp(-Swift.max(0, h) / 6)), pulse = FX.fract(h * 0.022 - u * 2.6) < 0.07 ? 1 : 0
            var xi = Int(FX.floor(-ww * 1.3))
            let xEnd = Int(FX.ceil(ww * 1.3))
            while xi <= xEnd {
                defer { xi += 1 }
                let x = Double(xi), q = abs(x + 0.5) / ww
                // as it breaks, holes open and grow and drift upward until only shards are left
                if brk > 0 && FX.noise2(x * 0.32, h * 0.11 - (t - BREAK) * 6, S) * 0.5 + 0.5 < brk * 1.25 - 0.1 { continue }
                var lv = q < 0.2 ? 0 : q < 0.42 ? 1 : q < 0.66 ? 2 : q < 0.88 ? 3 : 4
                for s in strands where abs((x + 0.5) / ww - s.o - 0.05 * sin(t * s.f + s.o * 9)) < s.w { lv = Swift.max(0, lv - 1) }
                lv = white ? 0 : Swift.max(0, lv - pulse)
                let a = (q < 0.88 ? 1 : (1.3 - q) / 0.42) * fade
                if a <= FXArcane.bayer(x, y) * (q < 0.66 ? 0.2 : 1) { continue }
                p.px(x, y, COL[lv])
            }
            if (hi & 7) == 0 && h < TOP - ww * 2.4 - 8 { p.glow(0, y, ww * 2.4 + 6, C[5], 0.3 * fade) }
            yi -= 1
        }
        // halos climbing it
        for i in 0..<6 {
            let k = (t - (FLASH + 0.08 + Double(i) * 0.16)) / 0.8
            if k < 0 || k > 1 { continue }
            let rx = w * 1.4 * (1 + k * 0.35), ry = rx * 0.3, yc = -3 - FX.Ease.outQuad(k) * 120, n = Int(FX.ceil(rx * 7))
            for j in 0..<n {
                let g = (Double(j) / Double(n)) * FX.tau
                p.dot(cos(g) * rx, yc + sin(g) * ry, k < 0.3 ? FX.white : C[6], (1 - k) * fade * (sin(g) < 0 ? 0.6 : 1))
            }
        }
        // white-hot where it meets the floor
        p.glow(0, -4, 34, C[6], 0.45 * fade)
        p.glow(0, -60, 70, C[4], 0.25 * fade)
    }

    func shock(_ p: Painter, _ far: Bool) {
        let R = Self.R
        for (d, r0, r1, th, dur) in [(0.0, R * 0.6, R * 2, 6.0, 0.5), (0.08, R * 0.4, R * 1.4, 3.0, 0.4)] {
            let k = (t - Self.FLASH - d) / dur
            if k < 0 || k >= 1 { continue }
            FX.band(p, 0, 0, r0 + (r1 - r0) * FX.Ease.outCubic(k), Self.SY, Swift.max(1, th * (1 - k)), 1.15 - k, [C[3], C[5], C[6], FX.white],
                    { g in (sin(g) < 0) == far }, k < 0.2)
        }
    }

    func update(_ dt: Double) {
        t += dt
        let t = self.t, C = self.C, Rg = self.Rg, R = Self.R, R2 = Self.R2, RI = Self.RI, SY = Self.SY, W = Self.W, TOP = Self.TOP
        let PEN = Self.PEN, INNER = Self.INNER, STAR = Self.STAR, RUNES = Self.RUNES, FLASH = Self.FLASH, BREAK = Self.BREAK
        // the pens shed glitter as they write
        if t > PEN.0 && t < STAR.1 && Rg.chance(0.5) {
            var x = 0.0, y = 0.0
            if t < PEN.1 {
                let g = Double.pi / 2 + Rg.sign() * ((t - PEN.0) / (PEN.1 - PEN.0)) * Double.pi
                x = cos(g) * R; y = sin(g) * R * SY
            } else if t < INNER.1 {
                let g = -Double.pi / 2 + ((t - INNER.0) / (INNER.1 - INNER.0)) * FX.tau
                x = cos(g) * RI; y = sin(g) * RI * SY
            } else {
                let live = edges.filter { e in t >= e.t0 && t < e.t0 + e.dur }
                let pick = Int(FX.floor(Rg.next() * Double(live.count)))
                let e = pick < live.count ? live[pick] : edges[0], s = FX.clamp((t - e.t0) / e.dur)
                x = e.p0.0 + (e.p1.0 - e.p0.0) * s; y = (e.p0.1 + (e.p1.1 - e.p0.1) * s) * SY
            }
            let vx = Rg.range(-12, 12), vy = Rg.range(-30, -8), life = Rg.range(0.25, 0.55)
            ps.spawn(.ember, x, y - 1, vx, vy, life, C[6], 1)
        }
        // gathering: light rushes in along the floor to the heart of the circle
        if t > RUNES.1 - 0.1 && t < FLASH - 0.05 && Rg.chance(0.7) {
            let g = Rg.range(0, FX.tau), D = Rg.range(R * 0.7, R * 1.1), T = Rg.range(0.16, 0.24), v = (D * 3) / (exp(3 * T) - 1)
            let x = cos(g) * D, y = sin(g) * D * SY - 1, h = hypot(x, y + 2), l = h == 0 ? 1 : h
            ps.spawn(.streak, x, y, (-x / l) * v, ((-2 - y) / l) * v, T, Rg.chance(0.5) ? C[6] : C[5])
        }
        if !flashed && t >= FLASH {
            flashed = true
            lights.add(0, -56, 104, C[5], 0.9, 0.6)
            lights.add(0, -5, 36, FX.white, 0.8, 0.14)
            for _ in 0..<36 {
                let s = Rg.sign(), sp = Rg.range(80, 175)
                let x = s * Rg.range(0, R * 0.5), vy = -Rg.range(30, 180), life = Rg.range(0.25, 0.7)
                ps.spawn(.spark, x, -1, s * sp, vy, life)
            }
            for _ in 0..<26 {
                let x = Rg.range(-R, R), y = -Rg.range(1, 6), vx = Rg.range(-20, 20), vy = -Rg.range(40, 130), life = Rg.range(0.5, 1.1)
                let c = Rg.pick([FX.white, C[6], C[5]]), size = Rg.range(0.8, 2.3)
                ps.spawn(.star, x, y, vx, vy, life, c, size)
            }
            // and a spray of twinkles flung out low across the floor
            for _ in 0..<34 {
                let s = Rg.sign()
                let x = s * Rg.range(0, 14), y = -Rg.range(1, 4), vx = s * Rg.range(50, 140), vy = -Rg.range(10, 90), life = Rg.range(0.4, 0.95)
                let c = Rg.pick([FX.white, C[6], C[6], C[5]]), size = Rg.range(0.7, 2.2)
                ps.spawn(.star, x, y, vx, vy, life, c, size)
            }
        }
        // glints pop along the burning circle
        if t > RUNES.0 && t < BREAK + 0.2 && Rg.chance(0.12) {
            let g = Rg.range(0, FX.tau), r = Rg.pick([R, R2, RI])
            let vy = -Rg.range(2, 8), life = Rg.range(0.25, 0.45), c = Rg.pick([FX.white, C[6]]), size = Rg.range(0.8, 2)
            ps.spawn(.star, cos(g) * r, sin(g) * r * SY - 0.5, 0, vy, life, c, size)
        }
        // the column throws off stars, and light streams up inside it
        if t > FLASH && t < BREAK {
            if Rg.chance(0.5) {
                let x = Rg.range(-1, 1) * W * 1.5, y = -Rg.range(0, 120), vx = Rg.range(-10, 10), vy = -Rg.range(30, 85), life = Rg.range(0.5, 1.1)
                let c = Rg.pick([FX.white, C[6], C[5]]), size = Rg.range(0.7, 2)
                ps.spawn(.star, x, y, vx, vy, life, c, size)
            }
            if Rg.chance(0.35) {
                let x = Rg.range(-1, 1) * W * 0.8, y = -Rg.range(0, 50), vy = -Rg.range(160, 300), life = Rg.range(0.2, 0.35)
                ps.spawn(.mote, x, y, 0, vy, life, Rg.chance(0.5) ? FX.white : C[6], 0.8)
            }
        }
        // it breaks apart into glints that twinkle as they drift up
        if !broke && t >= BREAK {
            broke = true
            for _ in 0..<46 {
                let x = Rg.range(-1, 1) * W * 0.9, y = -Rg.range(2, TOP * 0.8), vx = Rg.range(-12, 12), vy = -Rg.range(8, 40), life = Rg.range(0.5, 1.15)
                let c = Rg.pick([FX.white, FX.white, C[6], C[5]]), size = Rg.range(0.6, 2.4)
                ps.spawn(.star, x, y, vx, vy, life, c, size)
            }
        }
        if t > BREAK && t < BREAK + 0.4 && Rg.chance(0.8) {
            let x = Rg.range(-1, 1) * W * 0.7, y = -Rg.range(2, TOP * 0.78), vx = Rg.range(-8, 8), vy = -Rg.range(10, 50), life = Rg.range(0.4, 0.9)
            let c = Rg.pick([FX.white, C[6], C[5]]), size = Rg.range(0.6, 1.8)
            ps.spawn(.star, x, y, vx, vy, life, c, size)
            if Rg.chance(0.4) {
                let x = Rg.range(-1, 1) * W * 0.5, y = -Rg.range(2, TOP * 0.7), vy = -Rg.range(60, 140), life = Rg.range(0.2, 0.4)
                ps.spawn(.mote, x, y, 0, vy, life, C[6], 0.7)
            }
        }
        // the runes go out one by one, each in a little puff of glints
        for k in 0..<Self.NRUNE where !out[k] && t >= Self.runeOut(k) {
            out[k] = true
            let g = Self.runeAngle(k), x = cos(g) * Self.RR, y = sin(g) * Self.RR * SY - 5
            for _ in 0..<4 {
                let px = x + Rg.range(-2, 2), py = y + Rg.range(-2, 2), vx = Rg.range(-14, 14), vy = -Rg.range(10, 40), life = Rg.range(0.3, 0.55)
                let c = Rg.pick([FX.white, C[6]]), size = Rg.range(0.6, 1.6)
                ps.spawn(.star, px, py, vx, vy, life, c, size)
            }
        }
        ps.update(dt)
        lights.update(dt)
    }

    func drawBack(_ p: Painter, _ tt: Double) {
        let t = self.t, C = self.C, R = Self.R, lvl = Self.level(t)
        if t < Self.GONE {
            let k = lvl * FX.smooth(Self.PEN.0, Self.PEN.1 + 0.2, t)
            p.glow(0, 0, R * 1.3, C[4], 0.28 * k)
            for s in [-1.0, 1.0] { p.glow(s * R * 0.6, 1, R * 0.7, C[5], 0.12 * k) }
        }
        shock(p, true)
        circle(p, true)
        runes(p, true)
        column(p)
        ps.draw(p, .back)
    }

    func draw(_ p: Painter, _ tt: Double) {
        let t = self.t, C = self.C, R = Self.R, RI = Self.RI, SY = Self.SY, PEN = Self.PEN, INNER = Self.INNER, FLASH = Self.FLASH
        shock(p, false)
        circle(p, false)
        runes(p, false)
        // the pens: white points running round, writing light
        let pen = { (x: Double, y: Double) in
            FX.sparkle(p, x, y, 2, C[6], C[5], 0.5)
            p.glow(x, y, 7, C[6], 0.45)
        }
        if t > PEN.0 && t < PEN.1 {
            for s in [-1.0, 1.0] {
                let g = Double.pi / 2 + s * ((t - PEN.0) / (PEN.1 - PEN.0)) * Double.pi
                pen(cos(g) * R, sin(g) * R * SY)
            }
        }
        if t > INNER.0 && t < INNER.1 {
            let g = -Double.pi / 2 + ((t - INNER.0) / (INNER.1 - INNER.0)) * FX.tau
            pen(cos(g) * RI, sin(g) * RI * SY)
        }
        for e in edges where t > e.t0 && t < e.t0 + e.dur {
            let s = (t - e.t0) / e.dur
            pen(e.p0.0 + (e.p1.0 - e.p0.0) * s, (e.p0.1 + (e.p1.1 - e.p0.1) * s) * SY)
        }
        // the flash
        if t >= FLASH && t < FLASH + 0.24 {
            let a = (t - FLASH) / 0.24
            FX.flare(p, 0, -8, 34 * pow(1 - a, 1.5), 1 - a, C)
            p.glow(0, -26, 56, FX.white, 0.5 * (1 - a))
        }
        ps.draw(p, .front)
        lights.draw(p)
    }
}

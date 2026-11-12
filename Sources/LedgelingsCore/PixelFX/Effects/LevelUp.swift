// Gold gathers at the feet and bursts up as a pillar of light round the hero; rings climb it, LEVEL UP!
// drops in letter by letter, a shine sweeps it, sparkles twinkle. pixelfx's `ui/level-up` (MIT); the
// pillar's strands and climbing rings adapt Sprite Fusion's open-source holy light
// (https://www.spritefusion.com/pixel-art-vfx/holy-light), and the rushing streaks its power-up
// (https://www.spritefusion.com/pixel-art-vfx/power-up), MIT License, Copyright (c) 2026 Hugo Duprez.

import Foundation

final class FXLevelUp: FXEffect {
    static let meta = FXMeta(id: "ui/level-up", size: (176, 138), origin: (88, 114), duration: 3.2, loop: false, palette: ["#2a1405", "#5c3008", "#9a5a0e", "#d48e18", "#f5b92c", "#ffde5e", "#fff4bc", "#ffffff"], seed: 5)
    static let text = "LEVEL UP!"
    // release, pillar lifts off, pillar gone, pillar height, text top, first letter, stagger, shine, letters pop
    static let REL = 0.28, RET = 1.02, GONE = 1.34, TOP = 100.0, TY = -68.0, DROP = 0.5, STAG = 0.05, LANDED = 1.06, SHINE = 1.24, EXIT = 2.3
    // strands of light streaming up the pillar in dashes: where across it, how fast, dash period and length
    struct Strand { let x: Double, sp: Double, per: Double, duty: Double, ph: Double, lvl: Int, end: Double }
    static let STRANDS: [Strand] = (0..<9).map { n in
        let i = Double(n)
        return Strand(x: (i / 8 - 0.5) * 1.5 + (FX.rand(i, 1) - 0.5) * 0.16, sp: 170 + FX.rand(i, 2) * 170, per: 10 + FX.rand(i, 3) * 16,
                      duty: 0.3 + FX.rand(i, 4) * 0.35, ph: FX.rand(i, 5), lvl: FX.rand(i, 6) < 0.35 ? 1 : 2, end: 0.5 + FX.rand(i, 7) * 0.42)
    }

    /// Half-width of the pillar at time t.
    static func widthAt(_ t: Double) -> Double {
        t < REL ? 0 : 12 * (1 + 0.4 * exp(-(t - REL) * 10)) * (1 - 0.82 * FX.smooth(RET - 0.12, RET + 0.16, t))
    }

    final class Letter {
        let g: FXUI.Glyph, w: Double, cx: Double, born: Double, pop: Double
        var off = -18.0, v = 60.0, sq = 0.0, flash = 0.0, on = false, landed = false, rest = false, burst = false
        init(g: FXUI.Glyph, w: Double, cx: Double, born: Double, pop: Double) { self.g = g; self.w = w; self.cx = cx; self.born = born; self.pop = pop }
    }
    struct Sat { let x: Double, y: Double, t0: Double, dur: Double, L: Double }
    struct Rush { var x: Double, y: Double, vx: Double, vy: Double, life: Double, len: Double, c: FXColor, back: Bool }

    let C: [FXColor]
    let R: Rng
    let A: FXActor
    let SHADOW: FXColor
    let ps: FXParticles
    let lights = FXLights()
    let BASE: Double, X0: Double, right: Double
    let lets: [Letter]
    let sats: [Sat]
    var halos: [Double] = []
    var t = 0.0, released = false, nextHalo = REL + 0.03, gather = 0.0
    var rush: [Rush] = []

    init(_ o: FXOptions) {
        C = FX.fit(o.palette, 8)
        R = Rng(o.seed)
        A = o.actor
        SHADOW = FX.scale(C[0], 0.5)
        ps = FXParticles(rng: R, ground: { _ in 0 }, sparks: [C[7], C[6], C[5], C[3]])
        let word = FXUI.spell(Self.text)
        BASE = Self.TY + 14
        X0 = -Double(word.w)
        let X0 = self.X0
        lets = word.letters.filter { $0.g != nil }.enumerated().map { i, L in
            Letter(g: L.g!, w: Double(L.w), cx: X0 + (Double(L.x) + Double(L.w) / 2) * 2, born: Self.DROP + Double(i) * Self.STAG, pop: Self.EXIT + Double(i) * 0.04)
        }
        right = X0 + Double(word.w) * 2
        // sparkles that pop round the title one after another
        let R = self.R
        sats = (0..<8).map { i in
            let s: Double = i % 2 != 0 ? 1 : -1, x = s * R.range(20, 60), y = Self.TY + 7 + (abs(x) < 50 ? R.sign() * R.range(11, 18) : R.range(-14, 14))
            let t0 = Self.SHINE - 0.1 + Double(i) * 0.13 + R.range(0, 0.05), dur = R.range(0.32, 0.5), L = R.range(3, 6)
            return Sat(x: x, y: y, t0: t0, dur: dur, L: L)
        }
    }

    /// Every particle is gone by the end.
    func spawn(_ k: FXKind, _ x: Double, _ y: Double, _ vx: Double, _ vy: Double, _ life: Double,
               _ col: FXColor = FX.white, _ size: Double = 1, _ delay: Double = 0, _ flag: Int = 0) {
        ps.spawn(k, x, y, vx, vy, Swift.min(life, Self.meta.duration - 0.05 - t), col, size, delay, flag)
    }

    /// The pillar: shoots up from the feet (one white-hot frame), then stands as light: two flowing walls, a
    /// white core and strands streaming up in dashes; at the end its foot lifts off and it shoots away.
    func column(_ p: Painter, _ t: Double) {
        let C = self.C, REL = Self.REL, RET = Self.RET, GONE = Self.GONE, TOP = Self.TOP
        let a = t - REL
        if a < 0 || t > GONE { return }
        let top = -TOP * FX.Ease.outExpo(FX.clamp(a / 0.12)), bot = -TOP * FX.Ease.inCubic(FX.seg(t, RET, GONE)), W = Self.widthAt(t), k = 1 - FX.smooth(RET, GONE, t)
        p.glowLine(0, top, 0, Swift.min(bot, -34), W * 1.6 + 6, C[5], 0.2 * k + 0.06)
        p.glowLine(0, top, 0, Swift.min(bot, -40), 5, FX.white, 0.18 * k)
        if a < 0.04 {
            var y = FX.floor(top)
            while y < bot {
                let wr = W * 0.55 * (1 - 0.3 * (-y / TOP))
                var x = FX.floor(-wr)
                while x <= FX.ceil(wr) { p.dot(x, y, abs(x + 0.5) < wr - 1.5 ? FX.white : C[6], FX.clamp((y + TOP) / 20) * 1.5); x += 1 }
                y += 1
            }
            return
        }
        var y = FX.ceil(top)
        while y < FX.ceil(bot) {
            defer { y += 1 }
            let h = -y / TOP, fade = FX.clamp((y + TOP) / 16) * (t < RET ? 1 : FX.clamp((bot - y) / 10)), head = y - top < 3 && a < 0.16
            let wr = W * (1 - 0.3 * h) + 0.9 * FX.noise2(y * 0.2, t * 12, 3)
            for s in [-1.0, 1.0] {
                let run = FX.fract(y * 0.06 + t * 3.4 + (s > 0 ? 0.5 : 0)) < 0.78, xw = s * wr
                p.dot(xw, y, head ? FX.white : run ? C[6] : C[5], fade * 1.4)
                p.dot(xw + s, y, C[4], fade * (run ? 0.5 : 0.25))
                if run { p.dot(xw - s, y, C[5], fade * 1.2) }
            }
            p.dot(0, y, FX.white, fade * 1.6)
            p.dot(-1, y, FX.noise2(y * 0.3, t * 14, 5) > -0.2 ? FX.white : C[6], fade * 1.3)
            if FX.noise2(y * 0.25, t * 9, 8) > 0.25 { p.dot(1, y, C[6], fade * 1.2) }
            for S in Self.STRANDS {
                if h > S.end { continue }
                let ph = FX.fract((y + t * S.sp) / S.per + S.ph)
                if ph > S.duty { continue }
                let u = ph / S.duty
                p.px(S.x * wr, y, head || u < 0.2 ? FX.white : u < 0.65 ? C[7 - S.lvl] : C[6 - S.lvl])
            }
        }
    }

    /// The plate of light the pillar stands on.
    func plate(_ p: Painter, _ t: Double, _ k: Double) {
        if k <= 0.02 { return }
        let C = self.C, rx = 9 + 9 * k + sin(t * 9), ry = 2.2
        p.shade(-rx, -ry, rx, ry) { x, y, o in
            let dx = x / rx, dy = y / ry, d = (dx * dx + dy * dy).squareRoot()
            if d > 1 { return 0 }
            let u = d / Swift.max(0.05, k)
            o.c = u < 0.3 ? FX.white : u < 0.55 ? C[6] : u < 0.8 ? C[5] : C[4]
            o.a = d < 0.6 * k ? 1 : k * (1 - d) * 2.2
            return 0
        }
        p.glow(0, -1, rx * 2.2, C[4], 0.35 * k)
    }

    /// Rays above and below the title, starting on an ellipse just outside the word so none crosses it.
    func rays(_ p: Painter, _ t: Double, _ k: Double, _ cx: Double, _ cy: Double) {
        if k <= 0.02 { return }
        let C = self.C
        for n in 0..<20 {
            let i = Double(n), an = (i / 20) * FX.tau + 0.08, ca = cos(an), sa = sin(an), long = n % 2 == 0
            if abs(sa) < 0.4 { continue }
            let ex = ca / 52, ey = sa / 12
            let r0 = 1 / (ex * ex + ey * ey).squareRoot() + 2 * k, len = (long ? 15 + 7 * FX.rand(i, 9) : 7 + 4 * FX.rand(i, 8)) * k
            if len < 1 { continue }
            let sh = 0.75 + 0.25 * sin(t * 7 + i * 2.1), x0 = cx + ca * r0, y0 = cy + sa * r0
            p.line(x0, y0, x0 + ca * len, y0 + sa * len, { u in u < 0.3 ? C[7] : u < 0.6 ? C[6] : C[5] }, { u in sh * (u < 0.55 ? 1.3 : (1.3 * (1 - u)) / 0.45) })
        }
    }

    /// A gathering streak: a gold tail and a white head, running straight in.
    func drawRush(_ p: Painter, _ back: Bool) {
        for m in rush {
            if m.back != back { continue }
            let sp = hypot(m.vx, m.vy), ux = m.vx / sp, uy = m.vy / sp, L = m.len
            p.line(m.x - ux * L, m.y - uy * L, m.x - ux * L * 0.4, m.y - uy * L * 0.4, m.c)
            p.line(m.x - ux * L * 0.35, m.y - uy * L * 0.35, m.x, m.y, FX.white)
            p.glow(m.x, m.y, 4, C[5], 0.25)
        }
    }

    func update(_ dt: Double) {
        let C = self.C, R = self.R, A = self.A, REL = Self.REL, RET = Self.RET, TY = Self.TY, BACK = FXFlag.back
        t += dt
        let t = self.t
        // the gathering: streaks pour in along the floor to the feet and in from all round to the body, and in
        // the last beat run up the hero from the feet; the late ones are swallowed by the burst
        gather += t < REL ? dt * 420 : 0
        while gather >= 1 {
            gather -= 1
            let kind = R.next(), sp = R.range(140, 250) * (1 + t * 2)
            var x: Double, y: Double, tx: Double, ty: Double
            if kind < 0.42 {
                let an = R.range(0, FX.tau), D = R.range(22, 70)
                x = cos(an) * D; y = -1 - abs(sin(an)) * D * 0.1; tx = cos(an) * 3; ty = -1
            } else if kind < 0.84 {
                let an = R.range(0, FX.tau), D = R.range(34, 64)
                x = cos(an) * D; y = Swift.min(-3, -20 + sin(an) * D * 0.85); tx = cos(an) * 11; ty = -20 + sin(an) * 14
            } else {
                if t < REL * 0.4 { continue }
                x = R.range(-9, 9); y = -1; tx = x * 0.7; ty = -R.range(26, 44)
            }
            let dx = tx - x, dy = ty - y, hl = hypot(dx, dy), l = hl == 0 ? 1 : hl
            let life = Swift.min(l / sp, REL + 0.06 - t), len = R.range(5, 9), c = R.chance(0.45) ? C[6] : C[5], back = kind > 0.84 && R.chance(0.5)
            rush.append(Rush(x: x, y: y, vx: (dx / l) * sp, vy: (dy / l) * sp, life: life, len: len, c: c, back: back))
        }
        var i = rush.count - 1
        while i >= 0 {
            rush[i].life -= dt
            if rush[i].life <= 0 { rush.remove(at: i) } else { rush[i].x += rush[i].vx * dt; rush[i].y += rush[i].vy * dt }
            i -= 1
        }
        if t < REL && R.chance(0.12) { spawn(.star, R.range(-30, 30), -R.range(0, 3), 0, -R.range(10, 30), R.range(0.3, 0.5), C[6], 0.6) }
        if !released && t >= REL {
            released = true
            lights.add(0, -24, 90, C[5], 0.6, 0.7)
            lights.add(0, -8, 40, FX.white, 0.6, 0.12)
            // speed lines flung out from the hero
            for n in 0..<22 {
                let an = (Double(n) / 22) * FX.tau + R.range(-0.12, 0.12), sp = R.range(260, 460)
                let y0 = -18 + sin(an) * 8, vy = sin(an) * sp * 0.8
                let life = Swift.min(R.range(0.1, 0.2), vy > 0 ? -y0 / vy : vy < 0 ? (y0 + 104) / -vy : 1, 78 / abs(cos(an) * sp))
                spawn(.mote, cos(an) * 6, y0, cos(an) * sp, vy, life, R.chance(0.4) ? C[7] : C[6], 1, 0, an > 0.3 && an < Double.pi - 0.3 ? BACK : 0)
            }
            for _ in 0..<26 {
                let an = -Double.pi / 2 + R.range(-1.3, 1.3), sp = R.range(120, 290)
                spawn(.spark, R.range(-5, 5), -2, cos(an) * sp, sin(an) * sp, R.range(0.35, 0.8))
            }
            for _ in 0..<16 {
                spawn(.star, R.range(-10, 10), R.range(-36, -4), R.range(-30, 30), -R.range(15, 60), R.range(0.6, 1.3), R.pick([C[7], C[6], C[5]]),
                      R.chance(0.35) ? R.range(1.5, 2.6) : R.range(0.4, 0.9), 0, R.chance(0.4) ? BACK : 0)
            }
        }
        let W = Self.widthAt(t)
        if t >= nextHalo && t < RET - 0.1 { halos.append(t); nextHalo += 0.16 }
        // streaks race up beside the pillar
        if t > REL && t < RET + 0.1 && R.chance(0.5) {
            let s = R.sign()
            let y = R.range(-4, -60), vy = -R.range(140, 260)
            spawn(.mote, s * R.range(0.75, 1.6) * W, y, 0, vy, Swift.min(R.range(0.16, 0.32), (y + 96) / -vy), R.chance(0.5) ? C[7] : C[6], R.range(0.6, 1), 0, R.chance(0.5) ? BACK : 0)
        }
        // motes rise from the floor while the light lasts
        if t > REL && t < 2.4 && R.chance(0.14 * (1 - FX.seg(t, 1.6, 2.4))) {
            spawn(.ember, R.range(-20, 20), -R.range(1, 30), R.range(-15, 15), -R.range(20, 55), R.range(0.8, 1.6), C[5], R.range(1, 2), 0, R.chance(0.4) ? BACK : 0)
        }
        // gold motes lift off the hero while the light lasts
        if t > REL + 0.1 && t < 2.2 && R.chance(0.09) {
            let m = A.mask
            for _ in 0..<12 {
                let i = Int(R.int(0, Double(m.w - 1))), j = Int(R.int(0, Double(m.h - 1)))
                if m.data[j * m.w + i] == 0 { continue }
                spawn(.star, Double(A.x + i) + 0.5, Double(A.y + j) + 0.5, R.range(-8, 8), -R.range(14, 34), R.range(0.6, 1.1), R.pick([C[7], C[6], C[5]]),
                      R.chance(0.2) ? 1.5 : 0.6, 0, R.chance(0.5) ? BACK : 0)
                break
            }
        }
        // twinkles round the title and the hero while it holds
        if t > 1.0 && t < 2.5 && R.chance(0.13) {
            let up = R.chance(0.6), x = up ? R.range(-58, 58) : R.range(-20, 20), y = up ? TY + 7 + R.range(-16, 16) : R.range(-44, -6)
            spawn(.star, x, y, R.range(-6, 6), -R.range(4, 14), R.range(0.4, 0.8), R.pick([C[7], C[6], C[6], C[5]]),
                  R.chance(0.3) ? R.range(1.5, 2.4) : 0.6, 0, R.chance(0.3) ? BACK : 0)
        }
        // the letters drop in, bounce and settle; then pop away one by one
        for L in lets {
            if t < L.born { continue }
            L.on = true
            if !L.rest {
                L.v += 1700 * dt
                L.off += L.v * dt
                if L.off >= 0 && L.v > 0 {
                    L.off = 0
                    if L.v > 110 {
                        L.sq = 1
                        if !L.landed {
                            L.landed = true
                            L.flash = 1
                            lights.add(L.cx, BASE - 7, 18, C[5], 0.55, 0.25)
                            for s in [-1.0, 1.0] { spawn(.star, L.cx + s * L.w, BASE - R.range(0, 3), s * R.range(15, 40), -R.range(5, 25), R.range(0.25, 0.45), C[6], R.range(0.5, 1.2)) }
                        }
                        L.v = -L.v * 0.3
                    } else { L.v = 0; L.rest = true }
                }
            }
            L.sq = Swift.max(0, L.sq - dt / 0.1)
            L.flash = Swift.max(0, L.flash - dt / 0.12)
            if !L.burst && t >= L.pop + 0.06 {
                L.burst = true
                for i in 0..<3 {
                    let an = R.range(0, FX.tau), sp = R.range(20, 55)
                    spawn(.star, L.cx + R.range(-3, 3), BASE - 7 + R.range(-4, 4), cos(an) * sp, sin(an) * sp - 15, R.range(0.3, 0.6), R.pick([C[7], C[6]]), i != 0 ? 0.6 : R.range(1.2, 2))
                }
            }
        }
        ps.update(dt)
        lights.update(dt)
    }

    /// The tilted rings: the gathering ring, the two shock rings and the halos climbing the pillar, the half keep picks.
    func rings(_ p: Painter, _ t: Double, _ keep: @escaping (Double) -> Bool) {
        let C = self.C, REL = Self.REL
        if t < REL {
            let k = FX.seg(t, 0.02, REL)
            FX.band(p, 0, 0, 4 + 52 * (1 - FX.Ease.inQuad(k)), 0.2, 1.5, k * 1.1, C, keep)
        }
        for (d, r1, th) in [(0.0, 72.0, 4.0), (0.08, 46.0, 2.5)] {
            let k = (t - REL - d) / 0.55
            if k > 0 && k < 1 { FX.band(p, 0, 0, 5 + r1 * FX.Ease.outCubic(k), 0.2, Swift.max(1, th * (1 - k)), 1.15 - k, C, keep, k < 0.15) }
        }
        for h0 in halos {
            let k = (t - h0) / 0.6
            if k > 0 && k < 1 { FX.band(p, 0, -2 - 72 * FX.Ease.outQuad(k), (Self.widthAt(t) * 1.45 + 4) * (1 - 0.4 * k), 0.3, 1.5, (1 - k) * 1.4, C, keep, k < 0.12) }
        }
    }

    func drawBack(_ p: Painter, _ tt: Double) {
        let t = self.t, REL = Self.REL
        rays(p, t, FX.Ease.outExpo(FX.seg(t, Self.LANDED, Self.LANDED + 0.2)) * (1 - FX.Ease.inQuad(FX.seg(t, Self.EXIT - 0.15, Self.EXIT + 0.1))), 0, Self.TY + 7)
        rings(p, t) { g in sin(g) < 0 }
        column(p, t)
        plate(p, t, t < REL ? 0.55 * FX.seg(t, 0.05, REL) : 1 - FX.smooth(Self.RET - 0.1, Self.GONE + 0.2, t))
        ps.draw(p, .back)
        drawRush(p, true)
    }

    func draw(_ p: Painter, _ tt: Double) {
        let C = self.C, t = self.t, A = self.A, REL = Self.REL, RET = Self.RET, GONE = Self.GONE, TY = Self.TY, BASE = self.BASE, X0 = self.X0, right = self.right
        // near halves of the rings, in front of the hero
        rings(p, t) { g in sin(g) >= 0 }
        // the hero: warming as it gathers, flashed white on the release, then lit gold with a glowing edge
        let lit = FX.smooth(REL - 0.02, REL + 0.04, t) * (1 - FX.smooth(RET, 2.5, t))
        FXUI.tintActor(p, A, t < REL ? 0 : t < REL + 0.06 ? 1 : exp(-(t - REL - 0.06) / 0.07), [C[4], C[5], C[6]])
        FXUI.lightActor(p, A, C[5], 0.1 * FX.seg(t, 0.05, REL) * (1 - lit) + 0.06 * lit, 0.6 * lit, t)
        FXUI.haloActor(p, A, C[5], 0.85 * lit * (1 - FX.smooth(RET, GONE + 0.3, t)) + 0.3 * lit, t)
        // the spark gathering at the feet, then the flare of the release
        if t < REL {
            let k = FX.seg(t, 0.05, REL), q = t - REL * 0.6, beat = 1 + 0.4 * exp(-(q * q) / 0.001)
            FX.sparkle(p, 0, -2, (1 + 4 * k * k) * beat, C[6], C[5], 0.3 + 0.4 * k)
        } else if t < REL + 0.22 {
            let a = (t - REL) / 0.22
            FX.flare(p, 0, -4, 28 * pow(1 - a, 1.5), 1 - a, C)
            p.glow(0, -16, 48, FX.white, 0.3 * (1 - a))
        }
        ps.draw(p, .front)
        drawRush(p, false)
        // the title
        var items: [FXUI.Item] = []
        let done = (t - Self.LANDED) / 0.12
        for L in lets {
            if !L.on { continue }
            var sx = 2.0, sy = 2.0, flash = L.flash
            if !L.landed && L.v > 150 { sx = 1.8; sy = 2.3 }
            if L.sq > 0 { sx = 2 * (1 + 0.22 * L.sq); sy = 2 * (1 - 0.22 * L.sq) }
            let pu = (t - L.pop) / 0.07, hop = FX.seg(t, L.pop - 0.1, L.pop)
            if pu >= 1 { continue }
            if hop > 0 && pu <= 0 { sx = 2 * (1 - 0.1 * hop); sy = 2 * (1 + 0.15 * hop) }
            if pu > 0 { sx = 2 * (1 + 0.3 * pu); sy = sx; flash = 1 }
            flash = Swift.max(flash, done > 0 && done < 1 ? 1 - done : 0)
            let h = 7 * sy, w = L.w * sx
            items.append(FXUI.Item(g: L.g, x: L.cx - w / 2, y: BASE + L.off - h - 3 * FX.Ease.outQuad(hop), sx: sx, sy: sy, a: FX.clamp((t - L.born) / 0.05), flash: flash))
        }
        let sh = FX.seg(t, Self.SHINE, Self.SHINE + 0.34), shine: Double? = sh > 0 && sh < 1 ? X0 - 14 + (right - X0 + 30) * FX.Ease.inOutSine(sh) : nil
        FXUI.drawWord(p, items, FXUI.WordStyle(fill: [C[3], C[4], C[5], C[6]], edge: FX.white, under: C[2], outline: C[0], shadow: SHADOW, shine: shine, shineY: TY, glint: C[6]))
        if let shine, shine > X0 && shine < right { p.glowLine(shine, TY, shine + 8.4, BASE, 9, C[6], 0.3) }
        let hold = FX.smooth(0.9, 1.2, t) * (1 - FX.smooth(Self.EXIT, Self.EXIT + 0.4, t))
        if hold > 0 { p.glow(0, TY + 7, 50, C[5], 0.22 * hold + (done > 0 && done < 1 ? 0.3 * (1 - done) : 0)) }
        // each letter twinkles out where it popped
        for L in lets {
            let u = (t - L.pop - 0.07) / 0.16
            if u > 0 && u < 1 { FX.sparkle(p, L.cx, BASE - 7, 6 * (1 - u) * (1 - u), C[6], C[5], 0.5) }
        }
        // the glint where the shine leaves the word, and sparkles popping round it
        let g = (t - Self.SHINE - 0.3) / 0.26
        if g > 0 && g < 1 { FX.sparkle(p, right - 2, TY + 1, 7 * sin(g * Double.pi), C[6], C[5], 0.6) }
        for s in sats {
            let u = (t - s.t0) / s.dur
            if u > 0 && u < 1 { FX.sparkle(p, s.x, s.y, s.L * pow(sin(u * Double.pi), 0.7), C[6], C[5], 0.5) }
        }
        lights.draw(p)
    }
}

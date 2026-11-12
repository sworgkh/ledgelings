// Two party poppers bang one after the other: paper bits and curly streamers burst out, stall, then tumble
// and flutter down, flipping, and settle on the floor. pixelfx's `ui/confetti` (MIT); the flutter adapts
// Sprite Fusion's open-source falling leaves (https://www.spritefusion.com/pixel-art-vfx/falling-leaves),
// MIT License, Copyright (c) 2026 Hugo Duprez.

import Foundation

final class FXConfetti: FXEffect {
    static let meta = FXMeta(id: "ui/confetti", size: (200, 140), origin: (100, 126), duration: 3.4, loop: false, palette: ["#ff4a5a", "#ff9a2a", "#ffe03c", "#5ad84a", "#3cc8ff", "#7a6cff", "#f53cd1"], seed: 11)
    struct Popper { let x: Double, y: Double, a: Double, t: Double }
    static let POPPERS = [Popper(x: -74, y: -1, a: -Double.pi / 2 + 0.62, t: 0.1), Popper(x: 74, y: -1, a: -Double.pi / 2 - 0.62, t: 0.26)]
    static let INK = FX.hex("#141019"), BACK = FX.hex("#c8c0d8"), SMOKE = FX.hex("#5d5660")

    final class Bit {
        var x: Double, y: Double, vx: Double, vy: Double, c: FXColor, w: Double, h: Double, ang: Double, spin: Double
        var flip: Double, fs: Double, ph: Double, amp: Double, fw: Double, x0 = 0.0, mode = 0, rest = 0.0, fall: Double
        init(x: Double, y: Double, vx: Double, vy: Double, c: FXColor, w: Double, h: Double, ang: Double, spin: Double,
             flip: Double, fs: Double, ph: Double, amp: Double, fw: Double, fall: Double) {
            self.x = x; self.y = y; self.vx = vx; self.vy = vy; self.c = c; self.w = w; self.h = h; self.ang = ang; self.spin = spin
            self.flip = flip; self.fs = fs; self.ph = ph; self.amp = amp; self.fw = fw; self.fall = fall
        }
    }
    final class Ribbon {
        var pts: [(Double, Double)], vx: Double, vy: Double, c: FXColor, ph: Double, amp: Double, fw: Double
        var mode = 0, x0 = 0.0, curl: Double, fall: Double
        init(pts: [(Double, Double)], vx: Double, vy: Double, c: FXColor, ph: Double, amp: Double, fw: Double, curl: Double, fall: Double) {
            self.pts = pts; self.vx = vx; self.vy = vy; self.c = c; self.ph = ph; self.amp = amp; self.fw = fw; self.curl = curl; self.fall = fall
        }
    }

    let C: [FXColor]
    let R: Rng
    let ps: FXParticles
    let lights = FXLights()
    var bits: [Bit] = [], ribbons: [Ribbon] = [], fired = [false, false]
    let end = meta.duration - 0.05
    var t = 0.0

    init(_ o: FXOptions) {
        C = FX.fit(o.palette, 7)
        R = Rng(o.seed)
        ps = FXParticles(rng: R, ground: { _ in 0 }, sparks: ["#ffffff", "#fff3a6", "#ffc23d", "#ff8a2a"].map(FX.hex))
    }

    func kick(_ t: Double, _ pp: Popper) -> Double { t < pp.t ? 0 : 3 * exp(-(t - pp.t) * 14) }

    /// A party popper: a striped cone pointing along a, kicked back k px when it fires.
    func popper(_ p: Painter, _ x: Double, _ y: Double, _ a: Double, _ k: Double, _ alpha: Double) {
        let C = self.C, ca = cos(a), sa = sin(a), bx = x - ca * k, by = y - sa * k
        p.shade(bx - 12, by - 12, bx + 12, by + 12) { px, py, o in
            let dx = px - bx, dy = py - by, u = dx * ca + dy * sa, v = -dx * sa + dy * ca
            // u along the cone (0 at its tip on the floor, 11 at its mouth), v across
            if u < 0 || u > 11 { return 0 }
            let hw = 0.8 + u * 0.32
            if abs(v) > hw + 0.6 { return 0 }
            o.a = alpha
            if abs(v) > hw - 0.4 || u > 10.2 || u < 0.8 { return Self.INK }
            let stripe = FX.mod(FX.floor((u + v * 0.6) / 2.2), 2) == 0
            return stripe ? (v < 0 ? C[2] : FX.scale(C[2], 0.75)) : v < 0 ? FX.white : Self.BACK
        }
    }

    func fire(_ pp: Popper) {
        let C = self.C, R = self.R
        let mx = pp.x + cos(pp.a) * 11, my = pp.y + sin(pp.a) * 11
        lights.add(mx, my, 34, FX.white, 0.6, 0.12)
        lights.add(mx, my, 50, C[2], 0.4, 0.4)
        for _ in 0..<6 { ps.spawn(.smoke, mx, my, cos(pp.a) * R.range(20, 60) + R.range(-10, 10), sin(pp.a) * R.range(20, 60), R.range(0.6, 1), Self.SMOKE, R.range(2.5, 4)) }
        for _ in 0..<12 {
            let an = pp.a + R.range(-0.5, 0.5), sp = R.range(120, 260)
            ps.spawn(.spark, mx, my, cos(an) * sp, sin(an) * sp, R.range(0.1, 0.25))
        }
        // paper: thrown hard up the cone, the air soon stalls it
        for _ in 0..<46 {
            let an = pp.a + R.range(-0.38, 0.38), sp = R.range(200, 380)
            let c = R.pick(C), w = R.range(2, 3), h = R.range(3, 4.6), ang = R.range(0, FX.tau), spin = R.range(-14, 14), flip = R.range(0, FX.tau)
            let fs = R.range(5, 13), ph = R.range(0, FX.tau), amp = R.range(5, 12), fw = R.range(2, 3.4), fall = R.range(26, 40)
            bits.append(Bit(x: mx, y: my, vx: cos(an) * sp, vy: sin(an) * sp, c: c, w: w, h: h, ang: ang, spin: spin, flip: flip, fs: fs, ph: ph, amp: amp, fw: fw, fall: fall))
        }
        // streamers: a head that flies like the paper, a tail that follows it and curls
        for _ in 0..<4 {
            let an = pp.a + R.range(-0.25, 0.25), sp = R.range(220, 330), n = 11
            let c = R.pick(C), ph = R.range(0, FX.tau), amp = R.range(6, 12), fw = R.range(1.5, 2.4), curl = R.range(0.7, 1.1), fall = R.range(22, 32)
            ribbons.append(Ribbon(pts: Array(repeating: (mx, my), count: n), vx: cos(an) * sp, vy: sin(an) * sp, c: c, ph: ph, amp: amp, fw: fw, curl: curl, fall: fall))
        }
    }

    func update(_ dt: Double) {
        let R = self.R
        t += dt
        for (i, pp) in Self.POPPERS.enumerated() where !fired[i] && t >= pp.t { fired[i] = true; fire(pp) }
        for b in bits {
            if b.mode == 2 { b.rest += dt; continue }
            b.flip += b.fs * dt
            if b.mode == 0 {
                // the burst: heavy drag, a little gravity, tumbling fast; once slow it starts to flutter
                b.vx -= b.vx * 3.4 * dt
                b.vy -= b.vy * 3.4 * dt - 140 * dt
                b.x += b.vx * dt
                b.y += b.vy * dt
                b.ang += b.spin * dt
                if hypot(b.vx, b.vy) < 40 { b.mode = 1; b.x0 = b.x - sin(b.ph) * b.amp }
            } else {
                b.ph += b.fw * dt
                b.x0 += b.vx * dt
                b.vx -= b.vx * 2 * dt
                b.x = b.x0 + sin(b.ph) * b.amp
                b.y += b.fall * (0.4 + 0.9 * abs(cos(b.ph))) * dt
                b.ang = cos(b.ph) * 0.9
                if b.y >= -1 { b.y = -0.5; b.mode = 2; b.ang = R.range(-0.3, 0.3); b.flip = 0 }
            }
        }
        for r in ribbons {
            if r.mode == 0 {
                r.vx -= r.vx * 3 * dt
                r.vy -= r.vy * 3 * dt - 120 * dt
                r.pts[0].0 += r.vx * dt
                r.pts[0].1 += r.vy * dt
                if hypot(r.vx, r.vy) < 35 { r.mode = 1; r.x0 = r.pts[0].0 - sin(r.ph) * r.amp }
            } else if r.pts[0].1 < -1 {
                r.ph += r.fw * dt
                r.x0 += r.vx * dt
                r.vx -= r.vx * 2 * dt
                r.pts[0].0 = r.x0 + sin(r.ph) * r.amp
                r.pts[0].1 += r.fall * (0.5 + 0.7 * abs(cos(r.ph))) * dt
            }
            // the tail follows the head link by link and hangs a little
            for i in 1..<r.pts.count {
                let a = r.pts[i - 1]
                var b = r.pts[i]
                b.1 = Swift.min(-0.5, b.1 + 20 * dt)
                let dx = b.0 - a.0, dy = b.1 - a.1, hd = hypot(dx, dy), d = hd == 0 ? 1 : hd
                if d > 2.6 { b.0 = a.0 + (dx / d) * 2.6; b.1 = a.1 + (dy / d) * 2.6 }
                r.pts[i] = b
            }
        }
        ps.update(dt)
        lights.update(dt)
    }

    func drawBack(_ p: Painter, _ tt: Double) { ps.draw(p, .back) }

    func draw(_ p: Painter, _ tt: Double) {
        let C = self.C, t = self.t
        let fade = 1 - FX.seg(t, end - 0.45, end - 0.05)
        for pp in Self.POPPERS {
            let k = kick(t, pp)
            popper(p, pp.x, pp.y, pp.a, k, 1 - FX.seg(t, 2.5, 2.9))
            let ft = t - pp.t
            if ft > 0 && ft < 0.12 { FX.sparkle(p, pp.x + cos(pp.a) * 13, pp.y + sin(pp.a) * 13, 7 * (1 - ft / 0.12), FX.white, C[2], 0.7) }
        }
        // streamers: a two-tone ribbon that curls along its length
        for r in ribbons {
            let pts = r.pts.enumerated().map { i, q in (q.0 + sin(Double(i) * r.curl + t * 9 + r.ph) * (i != 0 ? 1.6 : 0), q.1) }
            for i in 1..<pts.count {
                let (x0, y0) = pts[i - 1], (x1, y1) = pts[i], front = sin(Double(i) * r.curl + t * 9 + r.ph) > 0
                p.line(x0, y0, x1, y1, front ? r.c : FX.scale(r.c, 0.6), fade)
                p.line(x0 + 1, y0, x1 + 1, y1, front ? FX.mix(r.c, FX.white, 0.35) : FX.scale(r.c, 0.45), fade)
            }
        }
        // paper bits: a little card turned by its tilt, its width by its flip; the back side shows darker
        for b in bits {
            if b.y > 1 { continue }
            let fw = b.mode == 2 ? 1 : cos(b.flip), w = Swift.max(0.5, abs(fw) * b.w), ca = cos(b.ang), sa = sin(b.ang)
            let c = fw >= 0 ? b.c : FX.scale(b.c, 0.62), a = fade
            if b.mode == 2 {
                p.dot(b.x, b.y, FX.scale(b.c, 0.8), a)
                p.dot(b.x + 1, b.y, FX.scale(b.c, 0.6), a)
                continue
            }
            p.shade(b.x - 4, b.y - 4, b.x + 4, b.y + 4) { x, y, out in
                let dx = x - b.x, dy = y - b.y, u = dx * ca + dy * sa, v = -dx * sa + dy * ca
                if abs(u) > w / 2 + 0.2 || abs(v) > b.h / 2 { return 0 }
                out.a = a
                return abs(fw) > 0.92 && v < -b.h / 2 + 1 ? FX.white : c
            }
            // it catches the light as it turns face-on
            if abs(fw) > 0.97 { p.glow(b.x, b.y, 5, FX.mix(b.c, FX.white, 0.5), 0.35 * fade) }
        }
        ps.draw(p, .front)
        lights.draw(p)
    }
}

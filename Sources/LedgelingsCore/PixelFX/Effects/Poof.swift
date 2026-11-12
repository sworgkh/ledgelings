// A cartoon death poof: a white pop, a ring of soft round smoke balls bursting out between speed lines, little
// stars spinning off, and the cloud lifting and thinning away. pixelfx's `spawn/poof` (MIT), after Sprite
// Fusion's open-source explosion (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT,
// Copyright (c) 2026 Hugo Duprez.

import Foundation

final class FXPoof: FXEffect {
    static let meta = FXMeta(id: "spawn/poof", size: (112, 92), origin: (56, 80), duration: 1.6, loop: false,
                             palette: ["#2a2440", "#5e5878", "#9a94b4", "#cdc8e0", "#f2f0fa", "#ffffff"], seed: 21)
    static let stars = ["#ffd84a", "#fff3a6", "#ffffff"]
    static let CY = -17.0
    struct Ball { var x: Double, y: Double, vx: Double, vy: Double, r0: Double, r1: Double, life: Double, delay: Double, max = 0.0 }
    struct Line { let a: Double, r1: Double, d: Double }
    enum Layer { case shade, body, cap }

    let o: FXOptions
    let C: [FXColor], S: [FXColor]
    let R: Rng
    let ps: FXParticles
    let lights = FXLights()
    var balls: [Ball] = [], lines: [Line] = []
    var t = 0.0

    init(_ o: FXOptions) {
        self.o = o
        let C = FX.fit(o.palette, 6), S = FX.fit(FX.ramp(Self.stars), 3), R = Rng(o.seed), CY = Self.CY, W = FX.white
        self.C = C; self.S = S; self.R = R
        ps = FXParticles(rng: R, ground: { _ in 0 }, sparks: [W, S[1], S[0], C[2]])
        // a ring of fat balls round a fat core, thrown out fast and stopped by drag, each swelling as it slows
        let ring = 9
        for i in 0..<ring {
            let a = (Double(i) / Double(ring)) * FX.tau + R.range(-0.2, 0.2), sp = R.range(95, 140), r = R.range(5, 7)
            let life = R.range(0.7, 1.05)
            balls.append(Ball(x: cos(a) * 3, y: CY + sin(a) * 3, vx: cos(a) * sp, vy: sin(a) * sp * 0.8 - 12, r0: r * 0.5, r1: r, life: life, delay: R.range(0, 0.03)))
        }
        for _ in 0..<5 {
            let a = R.range(0, FX.tau), sp = R.range(20, 60)
            let r1 = R.range(6.5, 8.5), life = R.range(0.85, 1.2)
            balls.append(Ball(x: cos(a) * 2, y: CY + sin(a) * 2, vx: cos(a) * sp, vy: sin(a) * sp - 16, r0: 4, r1: r1, life: life, delay: R.range(0.02, 0.06)))
        }
        // a few small puffs flung further out, gone quickly, so the cloud's edge is ragged
        for _ in 0..<7 {
            let a = R.range(0, FX.tau), sp = R.range(170, 240), r = R.range(2.2, 3.6)
            let life = R.range(0.32, 0.5)
            balls.append(Ball(x: cos(a) * 4, y: CY + sin(a) * 4, vx: cos(a) * sp, vy: sin(a) * sp * 0.75 - 10, r0: r * 0.6, r1: r, life: life, delay: R.range(0.01, 0.04)))
        }
        for i in balls.indices { balls[i].max = balls[i].life }
        // speed lines between the balls, flicked out and gone in a few frames
        for i in 0..<12 {
            let a = (Double(i) / 12) * FX.tau + R.range(-0.12, 0.12) + 0.13, sa = sin(a)
            // the ones that point down stop at the floor
            let r1 = Swift.min(R.range(24, 34), sa > 0.1 ? (-2 - CY) / sa : 99)
            lines.append(Line(a: a, r1: r1, d: R.range(0, 0.04)))
        }
        // little stars spun off the pop
        for _ in 0..<7 {
            let a = R.range(-Double.pi, 0.3), sp = R.range(70, 125)
            let life = R.range(0.55, 0.95), col = R.pick([S[2], S[1], S[1], S[0]]), size = R.range(1.3, 2.4)
            ps.spawn(.star, cos(a) * 6, CY + sin(a) * 6, cos(a) * sp, sin(a) * sp - 30, life, col, size, R.range(0.02, 0.1))
        }
        for _ in 0..<10 {
            let a = R.range(0, FX.tau), sp = R.range(40, 110)
            let life = R.range(0.3, 0.6), col = R.pick([W, S[1]])
            ps.spawn(.star, cos(a) * 5, CY + sin(a) * 5, cos(a) * sp, sin(a) * sp - 20, life, col, 0.6, R.range(0, 0.08))
        }
        // the feet go too: a skid of dust along the floor
        for _ in 0..<6 {
            let s = R.sign()
            let x = s * R.range(1, 6), vx = s * R.range(25, 70), vy = -R.range(2, 10), life = R.range(0.4, 0.7), size = R.range(1.6, 3)
            ps.spawn(.dust, x, -1, vx, vy, life, C[2], size, R.range(0.02, 0.08))
        }
        lights.add(0, CY, 46, C[4], 0.8, 0.4)
        lights.add(0, CY, 22, W, 0.8, 0.1)
    }

    /// A ball swells out, breathes, then shrinks to nothing.
    static func radius(_ b: Ball) -> Double {
        let age = b.max - b.life, u = age / b.max
        let grow = b.r0 + (b.r1 - b.r0) * FX.Ease.outBack(FX.clamp(age / 0.22), 2), breathe = 1 + 0.06 * sin(age * 14 + b.r1)
        return grow * breathe * (u < 0.62 ? 1 : 1 - FX.Ease.inBack(FX.clamp((u - 0.62) / 0.38), 1.4))
    }
    func drawBall(_ p: Painter, _ b: Ball, _ layer: Layer) {
        let C = self.C, W = FX.white, CY = Self.CY
        let age = b.max - b.life, r = Self.radius(b), a = Swift.min(1, age * 20), lit = age < 0.12
        if r < 0.6 { return }
        // the whole cloud is lit from above: the balls underneath are a step darker
        let hy = (b.y - CY + 6) / 14, lo = hy > 0.4, hi = hy < -0.3
        switch layer {
        case .shade: p.disc(b.x + r * 0.16, b.y + r * 0.2, r, lit ? C[3] : lo ? C[1] : C[2], 0.8 * a)
        case .body: p.disc(b.x - r * 0.06, b.y - r * 0.08, r * 0.86, lit ? C[4] : lo ? C[2] : C[3], 0.88 * a)
        case .cap:
            if !lo || lit {
                p.disc(b.x - r * 0.28, b.y - r * 0.34, r * 0.42, lit || hi ? W : C[4], 0.85 * a)
                if age < 0.25 { p.disc(b.x - r * 0.3, b.y - r * 0.38, r * 0.2, W, 0.9 * a * (1 - age / 0.25)) }
            }
        }
    }

    func update(_ dt: Double) {
        t += dt
        var i = balls.count - 1
        while i >= 0 {
            defer { i -= 1 }
            var b = balls[i]
            if b.delay > 0 { b.delay -= dt; balls[i] = b; continue }
            b.life -= dt
            if b.life <= 0 {
                // each ball goes with a pip of light
                if b.r1 > 4 { ps.spawn(.star, b.x, b.y, 0, -8, 0.22, FX.white, 0.6) }
                balls.remove(at: i)
                continue
            }
            // fast burst, hard drag, then a slow lift
            b.vx -= b.vx * 7 * dt
            b.vy -= b.vy * 7 * dt + 30 * dt
            b.x += b.vx * dt
            b.y = Swift.min(b.y + b.vy * dt, -Self.radius(b) * 0.7)
            balls[i] = b
        }
        ps.update(dt)
        lights.update(dt)
    }

    func drawBack(_ p: Painter, _ _t: Double) {
        // a soft shadow where the body stood, and the light of the pop on the floor
        let s = 1 - FX.smooth(0.1, 0.9, t)
        if s > 0 { p.glow(0, -1, 26, C[4], 0.25 * s) }
        ps.draw(p, .back)
    }

    func draw(_ p: Painter, _ _t: Double) {
        let C = self.C, CY = Self.CY, t = self.t, W = FX.white
        // the cloud: shade, body, then caps, so neighbouring balls merge into one lumpy cloud
        let live = balls.filter { $0.delay <= 0 }
        for layer in [Layer.shade, .body, .cap] { for b in live { drawBall(p, b, layer) } }
        // the pop: a white ball and an 8-ray flare for a couple of frames, then a ring
        if t < 0.07 {
            let k = t / 0.07
            p.circle(0, CY, 9 + 3 * k, C[4])
            p.circle(0, CY, 7 + 3 * k, W)
            FX.flare(p, 0, CY, 20 * (1 - k * 0.5), 1 - k, C)
        }
        let rk = (t - 0.03) / 0.2
        if rk > 0 && rk < 1 { p.ring(0, CY, 8 + 18 * FX.Ease.outCubic(rk), Swift.max(1, 2.5 * (1 - rk)), rk < 0.3 ? W : C[4], 1.1 - rk) }
        for l in lines {
            let u = (t - l.d) / 0.2
            if u <= 0 || u >= 1 { continue }
            let head = 8 + (l.r1 - 8) * FX.Ease.outExpo(FX.clamp(u / 0.6)), tail = 8 + (l.r1 - 8) * FX.Ease.inCubic(u), ca = cos(l.a), sa = sin(l.a)
            p.line(ca * tail, CY + sa * tail, ca * head, CY + sa * head, { v in v > 0.6 ? W : C[4] })
            p.glowLine(ca * tail, CY + sa * tail, ca * head, CY + sa * head, 3, C[4], 0.25)
        }
        ps.draw(p, .front)
        lights.draw(p)
    }
}

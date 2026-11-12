// An enemy goes up in a soft poof and gold coins spin out of it, bounce with a glint on each hit, settle on the
// floor, twinkle, and wink out one by one. pixelfx's `spawn/coin-drop` (MIT), after Sprite Fusion's open-source
// pickup (https://www.spritefusion.com/pixel-art-vfx/pickup), MIT, Copyright (c) 2026 Hugo Duprez.

import Foundation

final class FXCoinDrop: FXEffect {
    static let meta = FXMeta(id: "spawn/coin-drop", size: (160, 88), origin: (80, 78), duration: 3, loop: false,
                             palette: ["#2a1606", "#5c3208", "#9a5a0c", "#d48c14", "#f5b82a", "#ffe066", "#fff6c4", "#ffffff"], seed: 23)
    static let smoke = ["#3a3450", "#6c6688", "#a8a2c0", "#dcd8ea"], coinCount = 7
    static let CY = -16.0
    // an original coin: a rim, a lit face, a raised mark in the middle
    static let COIN = ["..oooo..", ".ohhlmo.", "ohlmmmdo", "ohmdhmdo", "olmdhmdo", "olmmmmdo", ".oddddo.", "..oooo.."].map { Array($0) }
    // lying flat on the floor, seen from the side
    static let FLAT = [".lhhhl.", "olmmmdo", ".odddo."]

    struct Ball { var x: Double, y: Double, vx: Double, vy: Double, r: Double, life: Double, max: Double }
    struct Coin {
        var x: Double, y: Double, vx: Double, vy: Double, ph: Double, w: Double, rest = false, hits = 0
        var out: Double, glint: Double, born: Double, gone = false, restAt = 0.0
    }

    let o: FXOptions
    let C: [FXColor], SM: [FXColor]
    let PAL: [Swift.Character: FXColor]
    let R: Rng
    let ps: FXParticles
    let lights = FXLights()
    var coins: [Coin] = [], balls: [Ball] = []
    var t = 0.0

    init(_ o: FXOptions) {
        self.o = o
        let C = FX.fit(o.palette, 8), R = Rng(o.seed), CY = Self.CY
        self.C = C; self.R = R
        SM = FX.fit(FX.ramp(Self.smoke), 4)
        PAL = ["o": C[1], "h": C[6], "l": C[5], "m": C[4], "d": C[3]]
        ps = FXParticles(rng: R, ground: { _ in 0 }, sparks: [FX.white, C[6], C[5], C[3]])
        // the poof the enemy goes up in
        for i in 0..<10 {
            let a = (Double(i) / 10) * FX.tau + R.range(-0.25, 0.25), sp = R.range(60, 100)
            let life = R.range(0.55, 0.85)
            balls.append(Ball(x: cos(a) * 2, y: CY + sin(a) * 2, vx: cos(a) * sp, vy: sin(a) * sp * 0.7 - 10, r: R.range(4, 6), life: life, max: life))
        }
        // the coins: thrown up and out, each spinning at its own rate
        let n = Self.coinCount
        for i in 0..<n {
            let u = n > 1 ? Double(i) / Double(n - 1) - 0.5 : 0, a = -Double.pi / 2 + u * 1.6 + R.range(-0.1, 0.1), sp = R.range(230, 300)
            let x = R.range(-3, 3), ph = R.range(0, FX.tau), w = R.range(9, 15) * R.sign()
            let out = 2.15 + Double(i) * 0.07 + R.range(0, 0.1), glint = R.range(1.2, 1.9), born = R.range(0.04, 0.12)
            coins.append(Coin(x: x, y: CY, vx: cos(a) * sp * 0.4, vy: sin(a) * sp, ph: ph, w: w, out: out, glint: glint, born: born))
        }
        for _ in 0..<8 {
            let a = R.range(0, FX.tau), sp = R.range(50, 120)
            let life = R.range(0.3, 0.6), col = R.pick([FX.white, C[6], C[5]])
            ps.spawn(.star, 0, CY, cos(a) * sp, sin(a) * sp - 20, life, col, R.range(0.8, 1.8))
        }
        lights.add(0, CY, 44, C[4], 0.7, 0.4)
        lights.add(0, CY, 20, FX.white, 0.7, 0.1)
    }

    /// A coin turning in the air: its face squashed toward the edge, the rim showing when it's side-on.
    func drawCoin(_ p: Painter, _ x: Double, _ y: Double, _ ph: Double) {
        let C = self.C, c = cos(ph), sx = abs(c)
        if sx < 0.28 {
            for dy in -3...3 { p.px(x, y + Double(dy), abs(dy) == 3 ? C[1] : dy < 0 ? C[6] : C[5]) }
            if sx > 0.12 { for dy in -2...2 { p.px(x + (c > 0 ? 1 : -1), y + Double(dy), C[3]) } }
            return
        }
        let half = 4 * sx
        var px = FX.floor(x - half)
        while px < FX.ceil(x + half) {
            defer { px += 1 }
            var col = Int(FX.floor((px + 0.5 - x) / sx + 4))
            if col < 0 || col > 7 { continue }
            if c < 0 { col = 7 - col }
            for row in 0..<8 {
                let ch = Self.COIN[row][col]
                if ch != "." { p.px(px, FX.round(y - 4 + Double(row)), PAL[ch]!) }
            }
        }
    }

    func update(_ dt: Double) {
        let C = self.C, R = self.R
        t += dt
        var i = balls.count - 1
        while i >= 0 {
            defer { i -= 1 }
            var b = balls[i]
            b.life -= dt
            if b.life <= 0 { balls.remove(at: i); continue }
            b.vx -= b.vx * 7 * dt
            b.vy -= b.vy * 7 * dt + 26 * dt
            b.x += b.vx * dt
            b.y += b.vy * dt
            balls[i] = b
        }
        for ci in coins.indices {
            var c = coins[ci]
            defer { coins[ci] = c }
            // a coin winks out with a little burst of gold
            if !c.gone && t >= c.out {
                c.gone = true
                for _ in 0..<5 {
                    let a = R.range(-Double.pi, 0), sp = R.range(25, 60)
                    let life = R.range(0.3, 0.55), col = R.pick([FX.white, C[6], C[5]])
                    ps.spawn(.star, c.x, -3, cos(a) * sp, sin(a) * sp, life, col, R.range(0.7, 1.4))
                }
                lights.add(c.x, -3, 14, C[5], 0.6, 0.2)
            }
            if t < c.born || t > c.out || c.rest { continue }
            c.vy += 820 * dt
            c.vx -= c.vx * 0.4 * dt
            c.x += c.vx * dt
            c.y += c.vy * dt
            c.ph += c.w * dt
            if c.y >= -1.5 && c.vy > 0 {
                c.y = -1.5
                c.hits += 1
                // a tink of light and a puff of dust at each hit
                ps.spawn(.star, c.x, -3, 0, -8, 0.25, FX.white, c.hits == 1 ? 2.2 : 1.4)
                for _ in 0..<2 {
                    let x = c.x + R.range(-1, 1), vx = R.sign() * R.range(8, 24), vy = -R.range(2, 8), life = R.range(0.25, 0.45)
                    ps.spawn(.dust, x, -0.5, vx, vy, life, SM[1], R.range(1, 1.8))
                }
                lights.add(c.x, -3, 12, C[5], 0.5, 0.15)
                if c.vy > 110 { c.vy *= -0.45; c.vx *= 0.7; c.w = c.w * 0.8 + R.range(-2, 2) }
                else { c.rest = true; c.vx = 0; c.vy = 0; c.restAt = t }
            }
        }
        ps.update(dt)
        lights.update(dt)
    }

    func drawBack(_ p: Painter, _ _t: Double) {
        // a warm gleam on the floor where the coins lie
        for c in coins where c.rest && t < c.out { p.glow(c.x, -1, 7, C[4], 0.18) }
        ps.draw(p, .back)
    }

    func draw(_ p: Painter, _ _t: Double) {
        let C = self.C, SM = self.SM, CY = Self.CY, t = self.t, W = FX.white
        // the poof: soft, top-lit balls, a pop of light in the middle
        for layer in 0..<3 {
            for b in balls {
                let age = b.max - b.life, k = b.life / b.max, r = b.r * (0.6 + 0.6 * FX.Ease.outCubic(FX.clamp(age / 0.2))) * (k < 0.35 ? k / 0.35 : 1)
                if r < 0.6 { continue }
                if layer == 0 { p.disc(b.x + r * 0.15, b.y + r * 0.2, r, SM[1], 0.8) }
                else if layer == 1 { p.disc(b.x - r * 0.06, b.y - r * 0.08, r * 0.86, b.y > CY + 2 ? SM[1] : SM[2], 0.85) }
                else if b.y < CY + 2 { p.disc(b.x - r * 0.28, b.y - r * 0.34, r * 0.4, SM[3], 0.85) }
            }
        }
        if t < 0.07 {
            let k = t / 0.07
            p.circle(0, CY, 8 + 2 * k, C[6])
            p.circle(0, CY, 6 + 2 * k, W)
            FX.flare(p, 0, CY, 16 * (1 - k * 0.5), 1 - k, C)
        }
        for c in coins {
            if t < c.born || t > c.out + 0.12 { continue }
            if t > c.out {
                // a coin winks out with a last flash and a ring
                let k = (t - c.out) / 0.12
                FX.sparkle(p, c.x, -2, FX.round(5 * (1 - k)), W, C[5], 0.5)
                p.ring(c.x, -3, 2 + 5 * FX.Ease.outCubic(k), 1, C[6], 1.1 - k)
                continue
            }
            if c.rest {
                // flat on the floor; now and then a glint runs over it
                p.sprite(Self.FLAT, PAL, FX.round(c.x) - 3, -3)
                p.glow(c.x, -2, 6, C[5], 0.25)
                let g = FX.mod(t - c.restAt + c.glint, 0.95) / 0.95
                if g < 0.2 { FX.sparkle(p, c.x - 1, -3, FX.round(3 * sin((g / 0.2) * Double.pi)), W, C[5], 0.4) }
            } else {
                drawCoin(p, c.x, c.y, c.ph)
                p.glow(c.x, c.y, 8, C[4], 0.3)
                // a glint catches the face as it turns toward us
                if abs(cos(c.ph)) > 0.96 { p.px(c.x - 1, c.y - 2, W) }
            }
        }
        ps.draw(p, .front)
        lights.draw(p)
    }
}

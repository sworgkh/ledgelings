// Snow at three depths in a gusty breeze: far specks, drifting flakes, big near crystals that spin and glow;
// they settle on a sparkling drift and melt away. pixelfx's `weather/snow` (MIT), its recipe adapted from
// Sprite Fusion's open-source snow (https://www.spritefusion.com/pixel-art-vfx/snow, MIT, Hugo Duprez).

import Foundation

final class FXSnow: FXEffect, FXBackdropped {
    static let meta = FXMeta(id: "weather/snow", size: (320, 180), origin: (160, 170), duration: 12, loop: true,
                             palette: ["#0c1020", "#161d36", "#24304f", "#3a4a72", "#5f74a3", "#93abd6", "#cfe0fa", "#ffffff"], seed: 6)
    static let D = 12.0
    /// far to near: how many, falls a loop, share of a fall spent in the air (the rest lying on the drift), sway, wind
    struct Layer { let n: Int, m: (Double, Double), air: Double, sway: (Double, Double), wind: Double, gust: Double }
    static let layers = [
        Layer(n: 230, m: (1, 2), air: 1, sway: (1, 3), wind: 3, gust: 0.4),
        Layer(n: 140, m: (2, 3), air: 0.8, sway: (3, 7), wind: 6, gust: 0.7),
        Layer(n: 24, m: (2, 3), air: 0.74, sway: (8, 15), wind: 9, gust: 1),
    ]
    static let axis: [(Double, Double)] = [(1, 0), (-1, 0), (0, 1), (0, -1)], diag: [(Double, Double)] = [(1, 1), (-1, -1), (1, -1), (-1, 1)]

    let o: FXOptions
    let C: [FXColor]
    /// false: no cold haze over the whole canvas (drawn over the desktop); the snow, drift and glints stay.
    var backdrop = true
    init(_ o: FXOptions) { self.o = o; C = FX.fit(o.palette, 8) }

    /// The drift's top edge.
    static func bank(_ x: Double) -> Double { -3 + 1.6 * sin(x * 0.045 + 1.3) + 1.1 * sin(x * 0.12 + 0.4) + 0.6 * sin(x * 0.31 + 2) }
    /// The gusts: a sway of the whole snowfall, periodic so the loop closes.
    static func gust(_ t: Double) -> Double { 10 * sin((FX.tau * t) / D + 0.6) + 4 * sin((FX.tau * 2 * t) / D + 2.1) }

    func drawBack(_ p: Painter, _ t: Double) {
        let q = FXWeather.Clip(p, Self.meta), S = o.seed, C = self.C
        // a cold haze, thicker low down, so the sky's stars don't read as snow
        if backdrop {
            let haze = FX.mix(C[1], C[2], 0.4)
            FXWeather.pass(p, Self.meta, -170, 9) { _, y, out in
                out.c = haze
                out.a = 0.26 + 0.22 * FX.smooth(-170, 0, y)
                out.b = true
            }
        }
        layer(q, t, S, 0)
        drift(q, t, S)
        layer(q, t, S, 1)
    }

    func draw(_ p: Painter, _ t: Double) {
        layer(FXWeather.Clip(p, Self.meta), t, o.seed, 2)
    }

    func layer(_ q: FXWeather.Clip, _ t: Double, _ S: Double, _ L: Int) {
        let C = self.C, Ly = Self.layers[L], sd = S * 13 + Double(L), D = Self.D, white = FX.white
        FXWeather.trips(t, D, Ly.n, sd, Ly.m.0, Ly.m.1) { u, k, m, i in
            let j = FX.wrap(k, m), dur = D / m, di = Double(i)
            let R = { (n: Double) in FX.rand(sd, di, j, n) }
            let tf = dur * Ly.air, age = Swift.min(u * dur, tf), sw = Ly.sway.0 + R(3) * (Ly.sway.1 - Ly.sway.0), f = 0.25 + R(4) * 0.35, ph = R(5) * FX.tau
            let xAt = { (a: Double) in
                -175 + R(2) * 350 + Ly.wind * a + (Self.gust(t - u * dur + a) - Self.gust(t - u * dur)) * Ly.gust + sw * sin(FX.tau * f * a + ph)
            }
            let x = xAt(age), xl = xAt(tf), y0 = -176.0, y1 = L != 0 ? Self.bank(xl) - 0.5 : -110 + R(1) * 106
            let y = y0 + (y1 - y0) * (age / tf), rest = u * dur - tf
            if L == 0 {
                // far: a speck, thinning out before it's gone
                let a = Swift.min(1, (1 - u) * 6)
                q.dot(x, y, R(6) < 0.5 ? C[4] : C[5], a)
                return
            }
            let fade = rest > 0 ? 1 - rest / (dur - tf) : 1
            if L == 1 {
                // a drifting flake: a point with a smaller one beside it, a plus when it's big
                let big = R(6) < 0.3
                if rest > 0 { q.dot(xl, y1, C[7], fade * 0.9); return }
                q.px(x, y, big ? white : C[7])
                if big { for (dx, dy) in Self.axis { q.px(x + dx, y + dy, C[5]) } }
                else { q.px(x + 1, y, C[6]); q.px(x, y + 1, C[6]); q.px(x + 1, y + 1, C[5]) }
                return
            }
            // a near crystal: six arms with side branches, spinning, a white heart, a cold glow; it lies down on the drift
            let r: Double = R(6) < 0.4 ? 3 : R(6) < 0.8 ? 4 : 5, spin = 1.5 + R(7) * 2.5
            if rest > 0 {
                q.dot(xl - 1, y1, C[6], fade)
                q.dot(xl, y1, white, fade)
                q.dot(xl + 1, y1, C[6], fade)
                q.glow(xl, y1, 5, C[5], 0.25 * fade)
                return
            }
            self.crystal(q, x, y, r, FX.mod(FX.floor(age * spin + R(8) * 2), 2) != 0)
        }
    }

    /// A near crystal, kept crisp: long arms on one set of four directions, short ones on the other, nubs near the
    /// tips; turning means trading which set is long.
    func crystal(_ q: FXWeather.Clip, _ x: Double, _ y: Double, _ r: Double, _ turn: Bool) {
        let C = self.C, white = FX.white
        let X = FX.round(x), Y = FX.round(y), long = turn ? Self.diag : Self.axis, short = turn ? Self.axis : Self.diag, R = turn ? r - 1 : r
        // long arms with a white-blue tip; nubs only where they can't touch the next arm, so the gaps stay open
        for (dx, dy) in long {
            var d = 1.0
            while d <= R { q.px(X + dx * d, Y + dy * d, d == R ? white : C[6]); d += 1 }
            let nubs: [Double] = turn ? (R >= 3 ? [R - 1] : []) : R >= 5 ? [R - 1, R - 2] : R >= 4 ? [R - 1] : []
            for n in nubs {
                let ox = turn ? dx : dy, oy = turn ? -dy : -dx
                q.px(X + dx * n + (turn ? 0 : ox), Y + dy * n + oy, C[4])
                q.px(X + dx * n + (turn ? -dx : -ox) + (turn ? dx : 0), Y + dy * n + (turn ? dy * 0 : -oy), C[4])
            }
        }
        let shortLen = turn ? 1 : Swift.max(1, FX.floor(R / 2))
        for (dx, dy) in short {
            var d = 1.0
            while d <= shortLen { q.px(X + dx * d, Y + dy * d, d == 1 ? C[6] : C[5]); d += 1 }
        }
        q.px(X, Y, white)
        // a faint halo, wide enough not to fill the gaps between the arms
        q.glow(X + 0.5, Y + 0.5, r * 2.5 + 5, C[5], 0.13)
        q.light(X, Y, C[6], 0.4)
    }

    /// The drift on the floor: a lumpy bank with a white crest, blue shade below, and glints that twinkle.
    func drift(_ q: FXWeather.Clip, _ t: Double, _ S: Double) {
        let C = self.C, white = FX.white
        FXWeather.pass(q.p, Self.meta, -7, 9) { x, y, out in
            let top = Self.bank(x), d = y - top
            if d < 0 { return }
            out.c = d < 1 ? white : d < 2 ? C[7] : d < 3.5 ? C[6] : d < 6 ? C[5] : C[4]
            if d < 1 { out.l = C[6]; out.k = 0.12 }
        }
        for i in 0..<18 {
            let di = Double(i)
            let x = -156 + FX.rand(S, di, 81) * 312, c = 1 + FX.floor(FX.rand(S, di, 82) * 3)
            let tw = sin((FX.tau * c * t) / Self.D + FX.rand(S, di, 83) * FX.tau)
            if tw < 0.55 { continue }
            let y = FX.ceil(Self.bank(x)) + FX.floor(FX.rand(S, di, 84) * 3), k = (tw - 0.55) / 0.45
            q.px(x, y, white)
            if k > 0.5 { for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, -1.0)] { q.px(x + dx, y + dy, C[6]) } }
            q.glow(x + 0.5, y + 0.5, 6, C[6], 0.35 * k)
        }
    }
}

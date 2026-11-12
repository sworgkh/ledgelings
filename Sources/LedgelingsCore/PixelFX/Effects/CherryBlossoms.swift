// Pink petals flutter down on a spring breeze, tumbling in little spirals and flashing as they catch the light,
// with a few whole blossoms spinning among them. pixelfx's `weather/cherry-blossoms` (MIT), after Sprite Fusion's
// open-source falling leaves (https://www.spritefusion.com/pixel-art-vfx/falling-leaves, MIT, Hugo Duprez).

import Foundation

final class FXBlossoms: FXEffect, FXBackdropped {
    static let meta = FXMeta(id: "weather/cherry-blossoms", size: (320, 180), origin: (160, 170), duration: 10, loop: true,
                             palette: ["#4a1832", "#8e3460", "#d26a94", "#f2a2c0", "#ffd2e2", "#fff4f8"], seed: 12)
    static let D = 10.0, FLOOR = 1.0
    static let heart = FX.hex("#ffe08a")

    let o: FXOptions
    let C: [FXColor]
    /// false: no plum dusk over the whole canvas (drawn over the desktop); the fallen petals and the falling ones stay.
    var backdrop = true
    /// Petals already fallen never move, so they are shaded once and the pixels replayed.
    lazy var scatterPx: FXWeather.Recorder = makeScatter()
    init(_ o: FXOptions) { self.o = o; C = FX.fit(o.palette, 6) }

    static func gust(_ t: Double) -> Double { 22 * sin((FX.tau * t) / D + 0.4) + 7 * sin((FX.tau * 2 * t) / D - 1) }

    func drawBack(_ p: Painter, _ t: Double) {
        let q = FXWeather.Clip(p, Self.meta), S = o.seed, C = self.C
        // a soft plum dusk, so the sky's stars don't read as petals
        if backdrop {
            let top = FX.hex("#0e0a14"), low = FX.mix(FX.hex("#1a0e1a"), C[0], 0.4)
            FXWeather.rows(p, Self.meta, -170, 9) { y, R in
                let k = (y + 170) / 180
                R.fill(FX.mix(top, low, k * k), 0.3 + 0.12 * k, blend: true)
            }
        }
        scatterPx.replay(q)
        petals(q, t, S, false)
    }

    func draw(_ p: Painter, _ t: Double) {
        let q = FXWeather.Clip(p, Self.meta), S = o.seed
        petals(q, t, S, true)
        blossoms(q, t, S)
    }

    /// Petals: each tumbles in a little spiral as it falls and drifts on the breeze, flipping fast; turned full
    /// face to the light it flashes.
    func petals(_ q: FXWeather.Clip, _ t: Double, _ S: Double, _ near: Bool) {
        let C = self.C, D = Self.D, FLOOR = Self.FLOOR
        let n = near ? 54 : 90, sd = S * 7 + (near ? 1 : 0)
        FXWeather.trips(t, D, n, sd, 1, 2) { u, k, m, i in
            let j = FX.wrap(k, m), di = Double(i)
            let R = { (c: Double) in FX.rand(sd, di, j, c) }
            let dur = D / m, tf = dur * 0.84, a = Swift.min(u * dur, tf), rest = u * dur - tf
            let born = t - u * dur, x0 = -200 + R(1) * 330, y0 = -184.0, vy = (FLOOR + (near ? 2 : 0) - y0) / tf, vx = 9 + R(2) * 10
            let rho = (near ? 3 : 2) + R(3) * 3, w = 2.2 + R(4) * 2.8, ph = R(5) * FX.tau, gk = near ? 1.0 : 0.6
            let at = { (aa: Double) -> (Double, Double) in
                (x0 + vx * aa + (Self.gust(born + aa) - Self.gust(born)) * gk + rho * cos(w * aa + ph), y0 + vy * aa + rho * 0.6 * sin(w * aa + ph))
            }
            let len = (near ? 3.6 : 2.6) + R(6) * 1.1
            if rest > 0 {
                let (x, y) = at(tf)
                // a landed petal settles and shrinks away (no dither, so the ground stays clean)
                let fade = 1 - rest / (dur - tf)
                if fade > 0.15 { Self.petal(q, x, y, len * (0.35 + 0.65 * fade), (R(7) - 0.5) * 1.2, 0.5, C, 1) }
                return
            }
            let (x, y) = at(a), flip = cos(R(8) * FX.tau + a * (3 + R(9) * 5)), ang = R(10) * FX.tau + a * (R(11) - 0.5) * 3
            Self.petal(q, x, y, len, ang, flip, C, 1)
            if flip > 0.9 {
                let g = (flip - 0.9) / 0.1
                q.px(x, y - 1, FX.white)
                q.glow(x, y, near ? 7 : 5, C[4], (near ? 0.32 : 0.22) * g)
            }
        }
    }

    /// A petal: a little notched teardrop, squashed across as it flips; its pale face or its deeper back.
    static func petal(_ q: FXWeatherShading, _ x: Double, _ y: Double, _ len: Double, _ ang: Double, _ flip: Double, _ C: [FXColor], _ a: Double) {
        let fs = 0.3 + 0.7 * abs(flip), back = flip < -0.2, c = cos(ang), s = sin(ang), e = len + 1
        // deeper at the base, palest at the tip, lit on one side; the back is a step deeper all over
        let face = back ? [C[1], C[2], C[3]] : [C[2], C[3], C[4]], tip = back ? C[3] : C[5]
        q.shade(x - e, y - e, x + e, y + e) { px, py, out in
            let dx = px - x, dy = py - y, u = (dx * c + dy * s) / len, v = (-dx * s + dy * c) / (len * fs)
            if u < -1 || u > 1 { return 0 }
            let hw = 0.55 * (1 - u * u).squareRoot() * (1 + 0.35 * u)
            if abs(v) > hw || (u > 0.7 && abs(v) < 0.12) { return 0 }
            out.c = u > 0.45 && v < 0.1 ? tip : u < -0.45 ? face[0] : v < 0 ? face[2] : face[1]
            out.a = a
            return 0
        }
    }

    /// A whole blossom: five petals round a gold heart, spinning slowly as it sinks.
    func blossoms(_ q: FXWeather.Clip, _ t: Double, _ S: Double) {
        let C = self.C, D = Self.D, FLOOR = Self.FLOOR
        FXWeather.trips(t, D, 7, S * 31, 1, 1) { u, _, _, i in
            let di = Double(i)
            let R = { (c: Double) in FX.rand(S * 31, di, c) }
            let y = -190 + (FLOOR + 2 + 190) * Swift.min(1, u / 0.9), born = t - u * D
            if u > 0.9 { return }
            let x = -190 + R(1) * 330 + 14 * u * D * 0.1 + (Self.gust(t) - Self.gust(born)) + 6 * sin(u * FX.tau * 2 + R(2) * 6)
            let rot = R(3) * FX.tau + u * D * (R(4) - 0.5) * 2
            let r = 3.6 + R(5) * 1.2
            for p in 0..<5 {
                let an = rot + (Double(p) * FX.tau) / 5
                Self.petal(q, x + cos(an) * r * 0.75, y + sin(an) * r * 0.75, r * 0.7, an, 1, C, 1)
            }
            q.px(x, y, Self.heart)
            q.glow(x, y, 8, C[4], 0.2)
        }
    }

    /// Petals already fallen, scattered along the floor.
    func makeScatter() -> FXWeather.Recorder {
        let rec = FXWeather.Recorder(resetAlpha: false), S = o.seed, FLOOR = Self.FLOOR
        for i in 0..<46 {
            let di = Double(i)
            Self.petal(rec, -164 + FX.rand(S, di, 71) * 328, FLOOR + FX.floor(FX.rand(S, di, 72) * 3) * 2, 2.6 + FX.rand(S, di, 73),
                       (FX.rand(S, di, 74) - 0.5) * 1.2, 0.5, C, 1)
        }
        return rec
    }
}

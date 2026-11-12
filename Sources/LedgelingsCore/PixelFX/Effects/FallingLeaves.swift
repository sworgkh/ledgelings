// Autumn leaves swing down through the air, tilting and flipping to show their pale backs, ride a gust, land flat
// in the litter and fade. pixelfx's `weather/falling-leaves` (MIT), the falling leaf adapted from Sprite Fusion's
// open-source falling leaves (https://www.spritefusion.com/pixel-art-vfx/falling-leaves, MIT, Hugo Duprez).

import Foundation

final class FXFallingLeaves: FXEffect, FXBackdropped {
    static let meta = FXMeta(id: "weather/falling-leaves", size: (320, 180), origin: (160, 170), duration: 10, loop: true,
                             palette: ["#4a1d0c", "#8a3a14", "#c8621e", "#f0982e", "#ffcf72", "#fff0c4"], seed: 8)
    static let D = 10.0, FLOOR = 1.0
    static let reds = FX.fit(FX.ramp(["#40101a", "#7c1c22", "#b8302a", "#e85a3c", "#ff9a72", "#ffd8c4"]), 6)
    static let golds = FX.fit(FX.ramp(["#3e300c", "#7a5c14", "#b8901e", "#e8c23a", "#fff09a", "#fffbe0"]), 6)

    let o: FXOptions
    let R3: [[FXColor]]
    /// false: no dusk haze over the whole canvas (drawn over the desktop); the litter and the leaves stay.
    var backdrop = true
    /// The fallen leaves never move, so they are shaded once and the pixels replayed.
    lazy var litterPx: FXWeather.Recorder = makeLitter()
    init(_ o: FXOptions) { self.o = o; R3 = [FX.fit(o.palette, 6), Self.reds, Self.golds] }

    static func gust(_ t: Double) -> Double { 16 * sin((FX.tau * t) / D - 1.2) + 5 * sin((FX.tau * 3 * t) / D) }
    /// ∫|cos| from the start of a swing: speeds up through the bottom of each arc, so the drop does too.
    static func Hc(_ th: Double) -> Double {
        let k = FX.floor((th + Double.pi / 2) / Double.pi)
        return 2 * k + 1 + sin(th - k * Double.pi)
    }
    /// A leaf's outline in its own frame: u along it (-1 stem...1 tip), v across; 0 inside, > 1 outside.
    static func shape(_ i: Int, _ u: Double, _ v: Double) -> Double {
        switch i {
        case 0: return abs(u) >= 1 ? 9 : (v * v) / (0.36 * (1 - u * u) * (1.15 - 0.3 * u)) // a beech: a long oval, pointed tip
        case 1:
            let r = hypot(u, v * 1.1), a = atan2(v, u)
            return r / (0.62 + 0.38 * pow(abs(cos(2.5 * a)), 1.5)) // a maple: five lobes
        default: return abs(u) >= 1 ? 9 : (v * v) / (0.16 * (1 - u * u)) // a willow: long and thin
        }
    }

    func drawBack(_ p: Painter, _ t: Double) {
        let q = FXWeather.Clip(p, Self.meta), S = o.seed, C = R3[0]
        // a faint dusk haze, warmer low down, that keeps the sky's stars out of the leaves' way
        if backdrop {
            let top = FX.hex("#0e0a12"), low = FX.mix(FX.hex("#140c14"), C[0], 0.3)
            FXWeather.rows(p, Self.meta, -170, 9) { y, R in
                let k = (y + 170) / 180
                R.fill(FX.mix(top, low, k * k), 0.32 + 0.1 * k, blend: true)
            }
        }
        litterPx.replay(q)
        leaves(q, t, S, false)
    }

    func draw(_ p: Painter, _ t: Double) {
        leaves(FXWeather.Clip(p, Self.meta), t, o.seed, true)
    }

    func leaves(_ q: FXWeather.Clip, _ t: Double, _ S: Double, _ front: Bool) {
        let R3 = self.R3, D = Self.D, FLOOR = Self.FLOOR
        FXWeather.trips(t, D, 62, S * 19, 2, 3) { u, k, m, i in
            let j = FX.wrap(k, m), di = Double(i)
            let R = { (n: Double) in FX.rand(S * 19, di, j, n) }
            let near = R(1) < 0.35
            if near != front { return }
            let dur = D / m, air = 0.72, tf = dur * air, a = Swift.min(u * dur, tf), rest = u * dur - tf
            let w = 1.7 + R(2) * 1.2, ph0 = R(3) * FX.tau, amp = (near ? 14 : 8) + R(4) * 10, x0 = -180 + R(5) * 340, y0 = -186.0
            // the drop speed that lands it on the floor just as its time in the air runs out
            let path = { (aa: Double) in 0.45 * aa + (0.9 * (Self.Hc(w * aa + ph0) - Self.Hc(ph0))) / w }
            let vy = (FLOOR - y0) / path(tf)
            let born = t - u * dur
            let xAt = { (aa: Double) in x0 + 7 * aa + sin(w * aa + ph0) * amp + (Self.gust(born + aa) - Self.gust(born)) * (near ? 1 : 0.7) }
            let size = (near ? 5.8 : 4.2) + R(6) * 1.6, shape = Int(FX.floor(R(7) * 3)), col = R3[Int(FX.floor(R(8) * 3))]
            if rest > 0 {
                // lying flat in the litter, fading
                let fade = 1 - rest / (dur - tf)
                Self.leaf(q, xAt(tf), FLOOR - 1, size, (R(9) - 0.5) * 0.5, 0.42, shape, col, fade)
                return
            }
            let x = xAt(a), y = y0 + vy * path(a), tilt = cos(w * a + ph0) * 0.75 + (near ? 0 : 0.3)
            let flip = cos(R(10) * FX.tau + a * (R(11) < 0.3 ? 5 : 1.2))
            Self.leaf(q, x, y, size, tilt, flip, shape, col, 1)
            // a leaf turned full face to the light catches it for a moment
            if flip > 0.86 {
                let k = (flip - 0.86) / 0.14, hx = x - cos(tilt) * size * 0.3, hy = y - sin(tilt) * size * 0.3 - 1
                q.px(hx, hy, col[5])
                q.glow(hx, hy, 5 + size * 0.5, col[4], 0.22 * k)
            }
        }
    }

    static let backs = [FX.hex("#9c8a78"), FX.hex("#c8b49c"), FX.hex("#e0d0b8"), FX.hex("#e8dcc8")]

    /// A leaf: squashed across by `flip` (the sign says which face shows), tilted, outlined, a midrib down the
    /// middle, the face lit on one side; the back face is paler and duller.
    static func leaf(_ q: FXWeatherShading, _ x: Double, _ y: Double, _ size: Double, _ ang: Double, _ flip: Double, _ shape: Int,
                     _ col: [FXColor], _ a: Double) {
        // like a card turning: never thinner than a third, and the back shows only past edge-on
        let back = flip < -0.25, fs = 0.35 + 0.65 * abs(flip), c = cos(ang), s = sin(ang)
        let L = size, Wd = size * 0.9, ext = L + 1.5
        let face = back ? [FX.mix(col[1], backs[0], 0.2), FX.mix(col[2], backs[1], 0.22), FX.mix(col[3], backs[2], 0.22)] : [col[2], col[3], col[4]]
        let rim = col[0], vein = back ? FX.mix(col[2], backs[3], 0.5) : col[1]
        q.shade(x - ext, y - ext, x + ext, y + ext) { px, py, out in
            let dx = px - x, dy = py - y, lu = (dx * c + dy * s) / L, lv = (-dx * s + dy * c) / (Wd * fs)
            let d = Self.shape(shape, lu, lv)
            if lu < -1.25 || lu > 1.1 { return 0 }
            // the stem pokes out past the base
            if lu < -0.92 && abs(lv * Wd * fs) < 0.5 { out.c = rim; out.a = a; return 0 }
            if d > 1.32 { return 0 }
            out.a = a
            if d > 1 { out.c = rim }
            else if abs(lv * Wd * fs) < 0.45 && lu > -0.9 && lu < 0.75 { out.c = vein }
            else { out.c = lv < -0.15 ? face[2] : lv < 0.35 ? face[1] : face[0] }
            return 0
        }
    }

    /// Fallen leaves lying in a band along the floor, overlapping.
    func makeLitter() -> FXWeather.Recorder {
        let rec = FXWeather.Recorder(resetAlpha: true), S = o.seed, FLOOR = Self.FLOOR
        for i in 0..<64 {
            let di = Double(i)
            let x = -164 + FX.rand(S, di, 91) * 328, y = FLOOR - 2 + FX.floor(FX.rand(S, di, 92) * 4) * 2, col = R3[Int(FX.floor(FX.rand(S, di, 93) * 3))]
            Self.leaf(rec, x, y, 3.6 + FX.rand(S, di, 94) * 1.8, (FX.rand(S, di, 95) - 0.5) * 0.7, 0.45 + FX.rand(S, di, 96) * 0.25,
                      Int(FX.floor(FX.rand(S, di, 97) * 3)), col.map { FX.mix($0, col[0], 0.12) }, 1)
        }
        return rec
    }
}

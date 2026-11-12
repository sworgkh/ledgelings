// Helpers shared by the weather loops: pixelfx's `fx/weather/_lib.js` (MIT), the parts the ported loops use.
// Weather fills its whole canvas edge to edge, so `Clip` keeps every pixel and every bit of light inside the
// canvas; `pass` and `rows` are fast per-pixel shaders over the canvas; `trips` rains particles that fall a
// whole number of times a loop, somewhere new each time. All of it is a pure function of t.

import Foundation

/// Something a pixel shader can be run on: the clipped painter, or a recorder that keeps the pixels to replay.
protocol FXWeatherShading {
    func shade(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ fn: (Double, Double, inout FXShadeOut) -> FXColor)
}

/// What `pass` hands a shader: colour, alpha (dithered, or truly blended when b), light colour and amount.
struct FXWeatherPassOut {
    var c: FXColor = 0, a = 1.0, b = false, l: FXColor = 0, k = 0.0
}

/// One canvas row for `rows`: per column, colour (0 for none), alpha (stored as Float, as pixelfx's
/// Float32Array), blend or dither, light colour and amount.
final class FXWeatherRow {
    let w: Int
    var c: [FXColor], a: [Float], b: [Bool], l: [FXColor], k: [Float]
    init(_ w: Int) {
        self.w = w
        c = Array(repeating: 0, count: w); a = Array(repeating: 1, count: w); b = Array(repeating: false, count: w)
        l = Array(repeating: 0, count: w); k = Array(repeating: 0, count: w)
    }
    /// The whole row one colour, alpha and mode.
    func fill(_ col: FXColor, _ alpha: Double, blend: Bool) {
        let fa = Float(alpha)
        for i in 0..<w { c[i] = col; a[i] = fa; b[i] = blend }
    }
}

enum FXWeather {
    /// The canvas in local coordinates: x0 <= x < x1, y0 <= y < y1.
    struct Box { let x0: Double, y0: Double, x1: Double, y1: Double, w: Int, h: Int }
    static func box(_ meta: FXMeta) -> Box {
        let W = meta.size.w, H = meta.size.h, OX = meta.origin.x, OY = meta.origin.y
        return Box(x0: Double(-OX), y0: Double(-OY), x1: Double(W - OX), y1: Double(H - OY), w: W, h: H)
    }

    /// A painter that draws only inside the effect's canvas: the same calls, with colour, blends and light
    /// outside it dropped. Exact under the painter's flip and rotation.
    final class Clip: FXWeatherShading {
        let p: Painter
        let B: Box
        private let flat: Bool
        private var sx0 = 0, sx1 = 0, sy0 = 0, sy1 = 0

        init(_ p: Painter, _ meta: FXMeta) {
            self.p = p
            B = FXWeather.box(meta)
            flat = p.sn == 0
            if flat {
                let a = p.toX(B.x0, 0), b = p.toX(B.x1, 0)
                sx0 = Int(FX.round(Swift.min(a, b))); sx1 = Int(FX.round(Swift.max(a, b)))
                sy0 = Int(FX.round(p.toY(0, B.y0))); sy1 = Int(FX.round(p.toY(0, B.y1)))
            }
        }

        @inline(__always) func ok(_ sx: Int, _ sy: Int) -> Bool {
            if flat { return sx >= sx0 && sx < sx1 && sy >= sy0 && sy < sy1 }
            let cx = Double(sx) + 0.5, cy = Double(sy) + 0.5, lx = p.fromX(cx, cy), ly = p.fromY(cx, cy)
            return lx >= B.x0 && lx < B.x1 && ly >= B.y0 && ly < B.y1
        }
        @inline(__always) func put(_ sx: Int, _ sy: Int, _ c: FXColor, _ a: Double = 1) { if ok(sx, sy) { p.put(sx, sy, c, a) } }
        @inline(__always) func add(_ sx: Int, _ sy: Int, _ c: FXColor, _ k: Double = 1) { if ok(sx, sy) { p.add(sx, sy, c, k) } }
        @inline(__always) func blendPx(_ sx: Int, _ sy: Int, _ c: FXColor, _ a: Double) { if ok(sx, sy) { p.blendPx(sx, sy, c, a) } }

        func px(_ x: Double, _ y: Double, _ c: FXColor) { put(p.cellX(x, y), p.cellY(x, y), c, 1) }
        func dot(_ x: Double, _ y: Double, _ c: FXColor, _ a: Double = 1) { if a > 0 { put(p.cellX(x, y), p.cellY(x, y), c, a) } }
        func light(_ x: Double, _ y: Double, _ c: FXColor, _ k: Double = 1) { add(p.cellX(x, y), p.cellY(x, y), c, k) }
        func blend(_ x: Double, _ y: Double, _ c: FXColor, _ a: Double) { blendPx(p.cellX(x, y), p.cellY(x, y), c, a) }

        func shade(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ fn: (Double, Double, inout FXShadeOut) -> FXColor) {
            var o = FXShadeOut()
            p.each(x0, y0, x1, y1) { lx, ly, sx, sy in
                o.c = 0; o.a = 1; o.l = 0; o.k = 0
                let r = fn(lx, ly, &o)
                let c = r != 0 ? r : o.c
                if c != 0 { self.put(sx, sy, c, o.a) }
                if o.k > 0 { self.add(sx, sy, o.l != 0 ? o.l : c, o.k) }
            }
        }

        /// The painter's glow, with its box cut to the canvas first (big soft lights stay cheap).
        func glow(_ x: Double, _ y: Double, _ r: Double, _ c: FXColor, _ k: Double = 0.5) {
            if r < 1 || k <= 0.004 { return }
            let x0 = Swift.max(B.x0, FX.floor(x - r)), x1 = Swift.min(B.x1 - 1, FX.ceil(x + r))
            let y0 = Swift.max(B.y0, FX.floor(y - r)), y1 = Swift.min(B.y1 - 1, FX.ceil(y + r))
            var py = y0
            while py <= y1 {
                let dy = (py + 0.5 - y) / r
                var px = x0
                while px <= x1 {
                    let dx = (px + 0.5 - x) / r, d = dx * dx + dy * dy
                    if d < 1 {
                        let f = 1 - d.squareRoot()
                        light(px, py, c, f * f * k)
                    }
                    px += 1
                }
                py += 1
            }
        }
    }

    /// Records what a shader draws, to replay it with `replay` (things that never move, shaded once).
    final class Recorder: FXWeatherShading {
        var px: [(x: Double, y: Double, c: FXColor, a: Double)] = []
        /// pixelfx's litter keeps alpha between pixels; its scatter does not reset it (`resetAlpha` false).
        let resetAlpha: Bool
        init(resetAlpha: Bool) { self.resetAlpha = resetAlpha }
        func shade(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ fn: (Double, Double, inout FXShadeOut) -> FXColor) {
            var o = FXShadeOut()
            var y = FX.floor(y0)
            while y <= FX.ceil(y1) {
                var x = FX.floor(x0)
                while x <= FX.ceil(x1) {
                    o.c = 0
                    if resetAlpha { o.a = 1 }
                    let r = fn(x + 0.5, y + 0.5, &o)
                    let c = r != 0 ? r : o.c
                    if c != 0 { px.append((x + 0.5, y + 0.5, c, o.a)) }
                    x += 1
                }
                y += 1
            }
        }
        func replay(_ q: Clip) { for e in px { q.dot(e.x, e.y, e.c, e.a) } }
    }

    /// A per-pixel shader over the canvas rows y0...y1 (local, clipped to the canvas). fn(x, y, &out) sets out.c
    /// with out.a (dithered, or blended when out.b), and out.l / out.k (light). x, y are pixel centres.
    static func pass(_ p: Painter, _ meta: FXMeta, _ y0In: Double, _ y1In: Double, _ fn: (Double, Double, inout FXWeatherPassOut) -> Void) {
        let B = box(meta)
        let y0 = Swift.max(B.y0, FX.floor(y0In)), y1 = Swift.min(B.y1 - 1, FX.ceil(y1In))
        if y0 > y1 { return }
        var o = FXWeatherPassOut()
        if p.sn != 0 {
            let q = Clip(p, meta)
            var y = y0
            while y <= y1 {
                var x = B.x0
                while x < B.x1 {
                    o = FXWeatherPassOut()
                    fn(x + 0.5, y + 0.5, &o)
                    if o.c != 0 { if o.b { q.blend(x, y, o.c, o.a) } else { q.dot(x, y, o.c, o.a) } }
                    if o.k > 0 { q.light(x, y, o.l != 0 ? o.l : o.c, o.k) }
                    x += 1
                }
                y += 1
            }
            return
        }
        let f = p.frame, W = p.w, fade = p.fade, lk = p.lightK * fade, fx = p.fx, tx = p.tx
        var y = y0
        while y <= y1 {
            defer { y += 1 }
            let sy = Int(FX.floor(p.ty + y + 0.5)), ry = sy - p.oy
            if ry < 0 || ry >= p.h { continue }
            let row = ry * W, by = (sy & 3) << 2
            var sxf = tx + (B.x0 + 0.5) * fx
            var x = B.x0
            while x < B.x1 {
                defer { x += 1; sxf += fx }
                let sx = Int(FX.floor(sxf)), rx = sx - p.ox
                if rx < 0 || rx >= W { continue }
                o = FXWeatherPassOut()
                fn(x + 0.5, y + 0.5, &o)
                write(f, row + rx, o.c, o.a * fade, o.b, by | (sx & 3), o.l, o.k * lk)
            }
        }
    }

    /// The fastest whole-sky shader: fn(y, row) fills one canvas row at a time (y the row's pixel centre),
    /// column i = x - box.x0.
    static func rows(_ p: Painter, _ meta: FXMeta, _ y0In: Double, _ y1In: Double, _ fn: (Double, FXWeatherRow) -> Void) {
        let B = box(meta), w = B.w, R = FXWeatherRow(w)
        let y0 = Swift.max(B.y0, FX.floor(y0In)), y1 = Swift.min(B.y1 - 1, FX.ceil(y1In))
        let rot = p.sn != 0, q: Clip? = rot ? Clip(p, meta) : nil
        let f = p.frame, W = p.w, fade = p.fade, lk = p.lightK * fade, fx = p.fx
        var y = y0
        while y <= y1 {
            defer { y += 1 }
            for i in 0..<w { R.c[i] = 0; R.k[i] = 0; R.a[i] = 1; R.b[i] = false }
            fn(y + 0.5, R)
            if let q {
                for i in 0..<w {
                    let x = B.x0 + Double(i)
                    if R.c[i] != 0 { if R.b[i] { q.blend(x, y, R.c[i], Double(R.a[i])) } else { q.dot(x, y, R.c[i], Double(R.a[i])) } }
                    if R.k[i] > 0 { q.light(x, y, R.l[i] != 0 ? R.l[i] : R.c[i], Double(R.k[i])) }
                }
                continue
            }
            let sy = Int(FX.floor(p.ty + y + 0.5)), ry = sy - p.oy
            if ry < 0 || ry >= p.h { continue }
            let row = ry * W, by = (sy & 3) << 2
            var sxf = p.tx + (B.x0 + 0.5) * fx
            for i in 0..<w {
                defer { sxf += fx }
                let c = R.c[i], kk = Double(R.k[i])
                if c == 0 && !(kk > 0) { continue }
                let sx = Int(FX.floor(sxf)), rx = sx - p.ox
                if rx < 0 || rx >= W { continue }
                write(f, row + rx, c, Double(R.a[i]) * fade, R.b[i], by | (sx & 3), R.l[i], kk * lk)
            }
        }
    }

    /// One pixel of `pass` / `rows`: a blend or a dithered colour, then light, written straight into the frame.
    @inline(__always) private static func write(_ f: FXFrame, _ i: Int, _ c: FXColor, _ a: Double, _ blend: Bool, _ cell: Int,
                                                _ l: FXColor, _ k: Double) {
        if c != 0 {
            if blend {
                if a > 0.004 {
                    let d = f.color[i], da = Double(d >> 24) / 255, oa = a + da * (1 - a), kk = a / oa, j = 1 - kk
                    let r = FX.byte(Double(c & 255) * kk + Double(d & 255) * j)
                    let g = FX.byte(Double((c >> 8) & 255) * kk + Double((d >> 8) & 255) * j)
                    let b = FX.byte(Double((c >> 16) & 255) * kk + Double((d >> 16) & 255) * j)
                    f.color[i] = (FX.byte(oa * 255) << 24) | (b << 16) | (g << 8) | r
                }
            } else if a >= 1 || a > Painter.bayer[cell] { f.color[i] = c }
        }
        if k > 0.004 {
            let lc = l != 0 ? l : c, d = f.light[i]
            let r = UInt32(Swift.min(255, Double(d & 255) + Double(lc & 255) * k))
            let g = UInt32(Swift.min(255, Double((d >> 8) & 255) + Double((lc >> 8) & 255) * k))
            let b = UInt32(Swift.min(255, Double((d >> 16) & 255) + Double((lc >> 16) & 255) * k))
            f.light[i] = (255 << 24) | (b << 16) | (g << 8) | r
        }
    }

    /// Falling particles for a loop of D seconds: n slots, each falling m times a loop (m whole, m0...m1), each
    /// fall somewhere new. fn(u, k, m, i): u 0...1 through the current fall, k its number (wrap(k, m) names it),
    /// m, the slot i. A fall lasts D / m s.
    static func trips(_ t: Double, _ D: Double, _ n: Int, _ seed: Double, _ m0: Double, _ m1: Double,
                      _ fn: (Double, Double, Double, Int) -> Void) {
        for i in 0..<n {
            let di = Double(i)
            let m = m0 + FX.floor(FX.rand(seed, di, 72) * (m1 - m0 + 1)), s = (t / D) * m + FX.rand(seed, di, 71), k = FX.floor(s)
            fn(s - k, k, m, i)
        }
    }
}

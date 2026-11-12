// Shared by the impacts: floor cracks that glow and cool, soft lumpy dust rings, faceted tumbling rocks, and
// the stone colours they share. Ported from pixelfx's `fx/impacts/_lib.js` (MIT); its stone colours adapt
// Sprite Fusion's open-source explosion (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT,
// Copyright (c) 2026 Hugo Duprez.

import Foundation

enum FXImpacts {
    static let SOOT = FX.hex("#0d0a12")
    static let OUTLINE = FX.hex("#1a1422")
    static let LIGHT = atan2(-1.0, -1.0) // light comes from the top left

    /// Stone colours from one body colour.
    struct Stone { let light: FXColor, body: FXColor, shade: FXColor, dust: FXColor, lip: FXColor }
    static func stone(_ c: FXColor) -> Stone {
        Stone(light: FX.mix(FX.scale(c, 1.35), FX.white, 0.08), body: c, shade: FX.scale(c, 0.64),
              dust: FX.mix(FX.scale(c, 1.2), FX.rgb(150, 140, 150), 0.3), lip: FX.mix(FX.scale(c, 1.55), FX.white, 0.12))
    }

    /// A point of a crack: where, and how far along it.
    typealias Pt = (x: Double, y: Double, d: Double)
    struct Crack { let pts: [Pt], len: Double, t0: Double, kids: [[Pt]] }

    /// A jagged walk from (x, y) heading a for L px.
    static func walk(_ R: Rng, _ x: Double, _ y: Double, _ a: Double, _ L: Double, jit: Double = 0.55, steer: Double = 0.45,
                     step: (Double, Double) = (2, 4), maxY: Double = .infinity, d0: Double = 0) -> [Pt] {
        var pts: [Pt] = [(x, y, d0)], x = x, y = y, d = 0.0, cur = a
        while d < L - 0.01 {
            let s = Swift.min(L - d, R.range(step.0, step.1))
            cur += R.range(-jit, jit) + (a - cur) * steer
            x += cos(cur) * s
            y = FX.clamp(y + sin(cur) * s, 0.5, maxY)
            d += s
            pts.append((x, y, d0 + d))
        }
        return pts
    }

    /// Cracks in the floor face below (0, 0): n jagged lines, alternately left and right.
    static func makeCracks(_ R: Rng, _ n: Int, len: (Double, Double) = (14, 40), dive: Double = 0.85, maxY: Double = 22,
                           forks: Double = 0.5, x0: (Double, Double) = (1, 5)) -> [Crack] {
        var out: [Crack] = []
        for i in 0..<n {
            let side: Double = i % 2 != 0 ? 1 : -1, dip = 0.06 + pow(R.next(), 1.7) * dive, L = R.range(len.0, len.1) * (1 - (0.5 * dip) / (dive + 0.06))
            let a = side > 0 ? dip : Double.pi - dip
            let sx = side * R.range(x0.0, x0.1), sy = R.range(0.5, 1.5)
            let pts = walk(R, sx, sy, a, L, maxY: maxY)
            let t0 = R.range(0, 0.035)
            var kids: [[Pt]] = []
            var j = 2
            while j < pts.count - 1 {
                if R.chance(forks * 0.4) {
                    let f = pts[j]
                    let fa = a + R.sign() * R.range(0.45, 1), fl = R.range(3, 9) * (1 - (0.5 * Double(j)) / Double(pts.count))
                    kids.append(walk(R, f.x, f.y, fa, fl, jit: 0.7, step: (1.5, 3), maxY: maxY, d0: f.d))
                }
                j += 1
            }
            out.append(Crack(pts: pts, len: L, t0: t0, kids: kids))
        }
        return out
    }

    /// Draw cracks grown to g(c) px of their length, lit from the hot ramp by heat(d) before they cool to dark.
    static func drawCracks(_ p: Painter, _ cracks: [Crack], _ g: (Crack) -> Double, _ heat: (Double) -> Double,
                           _ hot: [FXColor], _ dark: FXColor, _ lip: FXColor, _ k: Double = 1) {
        if k <= 0 { return }
        func col(_ d: Double) -> FXColor {
            let h = heat(d)
            return h > 0.75 ? hot[0] : h > 0.5 ? hot[1] : h > 0.3 ? hot[2] : h > 0.12 ? hot[3] : dark
        }
        for c in cracks {
            let G = g(c)
            if G <= 0 { continue }
            for path in [c.pts] + c.kids {
                for i in 1..<Swift.max(1, path.count) {
                    let (x0, y0, d0) = path[i - 1], (x1, y1, d1) = path[i]
                    if d0 >= G { break }
                    let f = d1 > G ? (G - d0) / (d1 - d0) : 1, ex = x0 + (x1 - x0) * f, ey = y0 + (y1 - y0) * f
                    p.line(x0, y0 + 1, ex, ey + 1, { _ in lip }, { u in
                        FX.rand(FX.round(x0 + (ex - x0) * u), FX.round(y0 + (ey - y0) * u), 5) < 0.3 ? k * 0.8 : 0
                    })
                    p.line(x0, y0, ex, ey, { u in col(d0 + (d1 - d0) * f * u) }, k)
                    let h = heat(d0)
                    if h > 0.12 { p.glow((x0 + ex) / 2, (y0 + ey) / 2, 4 + h * 4, hot[2], 0.22 * h * k) }
                }
            }
        }
    }

    /// A soft, lumpy ring of dust round (cx, cy), translucent and lit on its upper side; half -1 the far half only,
    /// 1 the near half only.
    static func dustRing(_ p: Painter, _ cx: Double, _ cy: Double, _ r: Double, _ w: Double, _ k: Double, _ c: FXColor,
                         sy: Double = 1, ph: Double = 0, brk: Double = 0, lit: Double = 0.35, maxY: Double = .infinity, half: Double = 0) {
        if k <= 0.01 || r <= 0 { return }
        let W = w * 1.6, lite = FX.mix(c, FX.white, lit)
        var y = FX.floor(cy - (r + W) * sy) - 1
        let y1 = Swift.min(maxY - 1, FX.ceil(cy + (r + W) * sy) + 1)
        while y <= y1 {
            var x = FX.floor(cx - r - W) - 1
            let x1 = FX.ceil(cx + r + W) + 1
            while x <= x1 {
                defer { x += 1 }
                let dx = x + 0.5 - cx, dy = (y + 0.5 - cy) / sy, d = hypot(dx, dy), g = atan2(dy, dx)
                if (half < 0 && dy >= 0) || (half > 0 && dy < 0) { continue }
                let lumpy = 0.6 + 0.3 * sin(5 * g + ph) + 0.18 * sin(11 * g + ph * 2.1) + 0.12 * sin(17 * g + ph * 0.7)
                let wt = w * lumpy, off = abs(d - r - w * 0.25 * sin(7 * g + ph))
                if off >= wt { continue }
                let tear = brk > 0 ? FX.clamp((0.55 + 0.45 * sin(6 * g + ph * 1.7) - brk) / 0.25) : 1
                let a = k * (1 - pow(off / wt, 2)) * tear
                if a > 0.01 { p.blend(x, y, dy < 0 && d > r - wt * 0.3 ? lite : c, a) }
            }
            y += 1
        }
    }

    /// A rock's outline: n vertex radii round its centre.
    static func rockShape(_ R: Rng, _ n: Int = 6) -> [Double] { (0..<n).map { _ in R.range(0.7, 1.12) } }

    /// A faceted rock tumbling at angle a: every facet shaded by how it faces the light, a dark outline, dithering
    /// out over its last half second.
    static func rock(_ p: Painter, x bx: Double, y by: Double, a ba: Double, s bs: Double, life: Double, pts: [Double], _ st: Stone) {
        let r = 0.75 + bs * 0.8, n = pts.count, fade = Swift.min(1, life / 0.5), ca = cos(ba), sa = sin(ba)
        p.shade(bx - r - 2, by - r - 2, bx + r + 2, by + r + 2) { x, y, out in
            let dx = x - bx, dy = y - by, u = dx * ca + dy * sa, v = -dx * sa + dy * ca, d = hypot(u, v)
            var ang = atan2(v, u)
            if ang < 0 { ang += FX.tau }
            let f = (ang / FX.tau) * Double(n), i = Int(FX.floor(f)) % n, w = f - FX.floor(f), edge = r * (pts[i] * (1 - w) + pts[(i + 1) % n] * w)
            if d > edge + 0.85 { return 0 }
            out.a = fade
            if d > edge { return OUTLINE }
            let lit = cos(((Double(i) + 0.5) / Double(n)) * FX.tau + ba - LIGHT)
            if d < edge * 0.42 { return lit > 0.55 ? st.light : st.body }
            return lit > 0.35 ? st.light : lit < -0.4 ? st.shade : st.body
        }
    }
}

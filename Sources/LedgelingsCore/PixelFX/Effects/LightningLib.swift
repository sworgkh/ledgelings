// Shared by the lightning effects: bolts that fork and thin as they split, inked as a deep halo, a pale body
// and a white core, thin crackles, and spark trajectories for pure loops. pixelfx's `fx/lightning/_lib.js`
// (MIT), which adapts the bolt and its inking from Sprite Fusion's open-source lightning
// (https://www.spritefusion.com/pixel-art-vfx/lightning), MIT, Copyright (c) 2026 Hugo Duprez.

import Foundation

enum FXLightning {
    /// Default palette, dark to bright: deep violet shadow, electric blue, icy white.
    static let volt = ["#120a33", "#2a1b78", "#4630c0", "#5a62f0", "#58a6ff", "#9ed8ff", "#e4f6ff", "#ffffff"]
    /// Plasma sparks, head to tail.
    static let plasma = ["#ffffff", "#c8f8ff", "#7ff3ff", "#1ab8e6"]

    /// One stroke of a bolt: its points and its weight (1 the trunk, thinner for forks).
    struct Path { var pts: [(Double, Double)]; var w: Double }

    /// A bolt from (x0, y0) to (x1, y1) by midpoint displacement down to ~3 px segments, with forks that
    /// split off along the way, each thinner and forking again up to two levels. The trunk first.
    static func zigzag(_ R: Rng, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ jag: Double = 0.32,
                       _ forks: Double = 0.35, _ w: Double = 1, _ depth: Int = 0) -> [Path] {
        var out: [Path] = []
        let L = hypot(x1 - x0, y1 - y0)
        var pts = [(x0, y0), (x1, y1)], off = L * jag
        while Double(pts.count) < 2 + L / 3 {
            var nxt = [pts[0]]
            for i in 0..<(pts.count - 1) {
                let (ax, ay) = pts[i], (bx, by) = pts[i + 1], h = hypot(bx - ax, by - ay), l = h == 0 ? 1 : h, o = R.range(-off, off)
                nxt.append(((ax + bx) / 2 + (-(by - ay) / l) * o, (ay + by) / 2 + ((bx - ax) / l) * o))
                nxt.append((bx, by))
            }
            pts = nxt
            off *= 0.52
        }
        out.append(Path(pts: pts, w: w))
        if depth < 2 {
            var i = 2
            while i < pts.count - 3 {
                if R.chance(forks / Double(1 + depth) / Swift.max(4, Double(pts.count) / 6)) {
                    let (ax, ay) = pts[i], (bx, by) = pts[Swift.min(pts.count - 1, i + 3)]
                    let a = atan2(by - ay, bx - ax) + R.sign() * R.range(0.35, 0.9)
                    let l = (L - (Double(i) / Double(pts.count)) * L) * R.range(0.25, 0.55)
                    out += zigzag(R, ax, ay, ax + cos(a) * l, ay + sin(a) * l, jag * 1.1, forks, w * 0.55, depth + 1)
                }
                i += 1
            }
        }
        return out
    }

    // MARK: Inking. Pixels are gathered in a grid at a level (higher wins), then drawn once each.

    final class Ink: @unchecked Sendable {
        static let N = 1024, HALF = 512
        var grid = [UInt8](repeating: 0, count: N * N)
        var hit: [Int] = []
        @inline(__always) func mark(_ x: Double, _ y: Double, _ lvl: UInt8) {
            let X = Int(FX.floor(x)) + Self.HALF, Y = Int(FX.floor(y)) + Self.HALF
            if X < 0 || Y < 0 || X >= Self.N || Y >= Self.N { return }
            let i = Y * Self.N + X, v = grid[i]
            if v == 0 { hit.append(i) }
            if lvl > v { grid[i] = lvl }
        }
        func stamp(_ x: Double, _ y: Double, _ r: Double, _ lvl: UInt8) {
            if r <= 0.5 { return mark(FX.round(x), FX.round(y), lvl) }
            let r2 = r * r
            var py = FX.floor(y - r)
            while py <= FX.ceil(y + r) {
                let dy = py + 0.5 - y
                var px = FX.floor(x - r)
                while px <= FX.ceil(x + r) {
                    let dx = px + 0.5 - x
                    if dx * dx + dy * dy <= r2 { mark(px, py, lvl) }
                    px += 1
                }
                py += 1
            }
        }
        /// Draw what was gathered: level n in cols[n - 1] at alpha alphas[n - 1] (dithered below 1).
        func flush(_ p: Painter, _ cols: [FXColor], _ alphas: [Double]) {
            for i in hit {
                let v = Int(grid[i])
                grid[i] = 0
                let x = Double(i % Self.N - Self.HALF), y = Double(i / Self.N - Self.HALF), a = alphas[v - 1]
                if a >= 1 { p.px(x, y, cols[v - 1]) } else if a > 0 { p.dot(x, y, cols[v - 1], a) }
            }
            hit.removeAll(keepingCapacity: true)
        }
    }
    nonisolated(unsafe) static let ink = Ink()

    static func walk(_ pts: [(Double, Double)], _ fn: (Double, Double) -> Void) {
        guard pts.count > 1 else { return }
        for i in 0..<(pts.count - 1) {
            let (ax, ay) = pts[i], (bx, by) = pts[i + 1], l = Swift.max(1, hypot(bx - ax, by - ay))
            var d = 0.0
            while d <= l { fn(ax + ((bx - ax) * d) / l, ay + ((by - ay) * d) / l); d += 0.5 }
        }
    }

    /// A bolt at full power: a deep halo, a pale body, a white core on the trunk, light every few points. k is the
    /// stroke's brightness (forks drop out below 0.5, the trunk thins below 0.6), s scales the thickness;
    /// hero: a white frame, the body goes white.
    static func stroke(_ p: Painter, _ b: [Path], _ k: Double, _ C: [FXColor], _ s: Double = 1, hero: Bool = false,
                       light lk: Double = 0.5, a: Double = 1, upTo: Double? = nil, core: Double? = nil, minY: Double? = nil) {
        if k <= 0.02 { return }
        let ink = Self.ink
        for q in b {
            let trunk = q.w >= 1
            if !trunk && k < 0.5 { continue }
            let rh = (trunk ? (k > 0.6 ? 2.1 : 1.6) : 1.1) * s, rb = (trunk ? (k > 0.6 ? 1.3 : 0.8) : 0.5) * s
            let pts = upTo != nil && trunk ? Array(q.pts.prefix(Swift.max(2, Int(FX.ceil(Double(q.pts.count) * upTo!))))) : q.pts
            walk(pts) { x, y in
                ink.stamp(x, y, rh, 1)
                ink.stamp(x, y, rb, trunk ? 3 : 2)
                if trunk && k > 0.3 { if let core, core != 0 { ink.stamp(x, y, core, 4) } else { ink.mark(x, y, 4) } }
            }
            var i = 0
            while i < pts.count - 1 {
                if minY == nil || pts[i].1 > minY! { p.glow(pts[i].0, pts[i].1, (trunk ? 14 : 7) * s, C[4], lk * k * q.w) }
                i += 3
            }
        }
        ink.flush(p, hero ? [C[3], C[6], C[7], C[7]] : [C[2], C[4], C[5], C[7]], [a, a, a, a])
    }

    static let cross: [(Double, Double)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]

    /// A thin crackle: a 1 px core (white on the trunk while bright), a 2 px pale body, a dithered halo while k is
    /// high, light along it.
    static func crackle(_ p: Painter, _ b: [Path], _ k: Double, _ C: [FXColor], _ glowK: Double = 0.5, _ a: Double = 1) {
        if k <= 0.02 { return }
        let ink = Self.ink
        for q in b {
            let thick = q.w >= 1
            walk(q.pts) { x, y in
                if k > 0.45 && thick { for (dx, dy) in cross { ink.mark(x + dx * 1.5, y + dy * 1.5, 1) } }
                if k > 0.25 && (thick || q.w > 0.4) { ink.mark(x + 1, y, 2); ink.mark(x, y + 1, 2) }
                ink.mark(x, y, thick && k > 0.3 ? 4 : 3)
            }
            var i = 0
            while i < q.pts.count - 1 {
                p.glow(q.pts[i].0, q.pts[i].1, (thick ? 9 : 5) * (0.5 + k * 0.5), C[4], glowK * k * q.w)
                i += 3
            }
        }
        ink.flush(p, [C[3], C[5], C[5], C[7]], [Swift.min(1, (k - 0.45) * 1.6) * a, a, a, a])
    }

    /// Where a spark launched at (x, y, vx, vy) is after `age` seconds, stepped like the simulation's spark.
    static func flight(_ x: Double, _ y: Double, _ vx: Double, _ vy: Double, _ age: Double, g: Double = 0.45, drag: Double = 2.2,
                       floor: Double = .infinity, bounce: Double = 0.45) -> (Double, Double, Double, Double) {
        var x = x, y = y, vx = vx, vy = vy
        let dt = 1.0 / 120
        var s = 0.0
        while s < age {
            let h = Swift.min(dt, age - s)
            vy += FX.gravity * g * h
            vx -= vx * drag * h
            vy -= vy * drag * h
            let ny = y + vy * h
            x += vx * h
            if vy > 0 && y <= floor && ny >= floor { vy = -vy * bounce; vx *= 0.7; y = floor - 0.25 } else { y = ny }
            s += dt
        }
        return (x, y, vx, vy)
    }

    /// A spark drawn the way the simulation draws one, for pure loops.
    static func spark(_ p: Painter, _ x: Double, _ y: Double, _ vx: Double, _ vy: Double, _ k: Double, _ S: [FXColor]) {
        let h = hypot(vx, vy), sp = h == 0 ? 1 : h, ux = vx / sp, uy = vy / sp, head = k > 0.6 ? S[0] : k > 0.3 ? S[1] : S[2]
        let len = Swift.min(9, 1 + sp * 0.022)
        p.line(x - ux * len, y - uy * len, x - ux * len * 0.4, y - uy * len * 0.4, k > 0.5 ? head : S[S.count - 1])
        p.line(x - ux * len * 0.45, y - uy * len * 0.45, x, y, head)
        p.glow(x, y, 3, head, 0.45 * k)
    }
}

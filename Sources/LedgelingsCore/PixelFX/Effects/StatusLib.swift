// Shared by the effects a creature wears (frost, smitten, fired up, haunted, the clock, sleep, dizzy):
// the creature's shape, noise that loops, flame, smoke and ember drawn from their age alone, little shaded
// icons and the creature's eyes. Ported from pixelfx's `fx/status/_lib.js` (MIT); its flame, smoke and
// ember recipes and its shaded icons adapt Sprite Fusion's open-source fire and heal
// (https://www.spritefusion.com/pixel-art-vfx), MIT, Copyright (c) 2026 Hugo Duprez.

import Foundation

/// Worked out once per creature shape (or per shape and seed) and kept.
final class FXMemo<Value>: @unchecked Sendable {
    private var store: [Int: Value] = [:]
    private let lock = NSLock()
    init() {}
    func get(_ key: Int, _ make: () -> Value) -> Value {
        lock.lock(); defer { lock.unlock() }
        if let v = store[key] { return v }
        let v = make()
        if store.count > 512 { store.removeAll() }
        store[key] = v
        return v
    }
}

enum FXStatus {
    /// The creature's shape in mask space (0, 0 its top-left).
    struct Shape {
        let w: Int, h: Int
        let data: [UInt8]
        /// Every pixel of the body.
        let body: [(Int, Int)]
        /// Pixels with nothing above them: where flames stand.
        let up: [(Int, Int)]
        /// Pixels open to the left (-1) or right (1).
        let side: [(Int, Int, Int)]
        /// Empty cells touching it, with the outward normal.
        let outline: [(Int, Int, Double, Double)]
        /// Each column's first row, -1 if empty.
        let top: [Int]
        /// [left, right] of each row.
        let rows: [(Int, Int)]
        @inline(__always) func on(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < w && y < h && data[y * w + x] > 0 }
    }

    nonisolated(unsafe) static let shapes = FXMemo<Shape>()

    static func shape(_ a: FXActor) -> Shape {
        shapes.get(a.key) {
            let m = a.mask, w = m.w, h = m.h, data = m.data
            let on = { (x: Int, y: Int) in x >= 0 && y >= 0 && x < w && y < h && data[y * w + x] > 0 }
            var body: [(Int, Int)] = [], up: [(Int, Int)] = [], side: [(Int, Int, Int)] = []
            var outline: [(Int, Int, Double, Double)] = [], top: [Int] = [], rows: [(Int, Int)] = []
            for x in 0..<w {
                var y = 0
                while y < h && !on(x, y) { y += 1 }
                top.append(y < h ? y : -1)
            }
            for y in 0..<h {
                var l = -1, r = -1
                for x in 0..<w {
                    if !on(x, y) { continue }
                    if l < 0 { l = x }
                    r = x
                    body.append((x, y))
                    if !on(x, y - 1) { up.append((x, y)) }
                    if !on(x - 1, y) { side.append((x, y, -1)) }
                    if !on(x + 1, y) { side.append((x, y, 1)) }
                }
                rows.append((l, r))
            }
            for y in -1...h {
                for x in -1...w {
                    if on(x, y) { continue }
                    var nx = 0.0, ny = 0.0
                    for dy in -1...1 { for dx in -1...1 where on(x + dx, y + dy) { nx -= Double(dx); ny -= Double(dy) } }
                    if on(x - 1, y) || on(x + 1, y) || on(x, y - 1) || on(x, y + 1) {
                        let hl = hypot(nx, ny), l = hl == 0 ? 1 : hl
                        outline.append((x, y, nx / l, ny / l))
                    }
                }
            }
            return Shape(w: w, h: h, data: data, body: body, up: up, side: side, outline: outline, top: top, rows: rows)
        }
    }

    /// The creature's own colour at mask pixel (x, y).
    @inline(__always) static func colorAt(_ a: FXActor, _ x: Int, _ y: Int) -> FXColor { a.pixels[y * a.mask.w + x] }

    /// 1D value noise in [-1, 1] whose lattice wraps every P cells.
    static func wnoise(_ x: Double, _ P: Double, _ seed: Double = 0) -> Double {
        let i = FX.floor(x), f = x - i, u = f * f * (3 - 2 * f)
        let a = FX.rand(FX.wrap(i, P), seed), b = FX.rand(FX.wrap(i + 1, P), seed)
        return (a + (b - a) * u) * 2 - 1
    }
    /// Noise of time t that repeats every D seconds, about f wiggles a second; off slides along it.
    static func tnoise(_ t: Double, _ D: Double, _ f: Double, _ seed: Double = 0, _ off: Double = 0) -> Double {
        let P = Swift.max(2, FX.round(f * D))
        return wnoise((t / D) * P + off, P, seed)
    }
    /// How far something has moved after age a, launched at v under acceleration g with linear drag d.
    static func travel(_ v: Double, _ g: Double, _ d: Double, _ a: Double) -> Double {
        d > 0 ? (g / d) * a + ((v - g / d) * (1 - exp(-d * a))) / d : v * a + 0.5 * g * a * a
    }

    /// A tongue's nested layers: width, height, ramp step (0 brightest).
    static let layers: [(Double, Double, Int)] = [(1, 1, 6), (0.76, 0.86, 4), (0.54, 0.68, 2), (0.3, 0.42, 0)]

    /// A flame tongue standing on (x, y), h tall, w half-wide at its root, its tip swept sx sideways.
    static func tongue(_ p: Painter, _ x: Double, _ y: Double, _ h: Double, _ w: Double, _ sx: Double, _ F: [FXColor],
                       _ t: Double, _ D: Double, _ n: Double, _ layers: [(Double, Double, Int)] = layers) {
        if h < 1 { return }
        for (lw, lh, ri) in layers {
            if ri == 0 && h < 4 { continue }
            let H = h * lh, col = F[ri]
            var r = 0.0
            while r <= H {
                defer { r += 1 }
                let u = r / Swift.max(1, H)
                let half = w * lw * pow(1 - u, 0.85) * Swift.min(1, (r + 1.5) / 3.5) + tnoise(t, D, 9, n, r * 0.45) * 0.5
                if half < 0.3 { continue }
                let cx = x + sx * u * u * lh + tnoise(t, D, 4, n + 7, r * 0.2) * u * 1.1
                var px = FX.round(cx - half)
                while px <= FX.round(cx + half) { p.px(px, FX.round(y - r), col); px += 1 }
            }
        }
    }

    /// A ball of flame at age u of its life, cooling down F as it rises.
    static func flame(_ p: Painter, _ x: Double, _ y: Double, _ size: Double, _ u: Double, _ F: [FXColor], _ heatSeed: Double = 0) {
        let n = F.count, k = 1 - u
        let heat = Swift.min(0.999, pow(u, 0.62) + heatSeed * 0.1), idx = Swift.min(n - 2, Int(FX.floor(heat * Double(n - 1))))
        let r = size * (0.55 + 0.45 * Swift.min(1, u * 7)) * (1 - u * 0.55), c = F[idx]
        if idx >= n - 2 { return p.disc(x, y, r, c, Swift.min(1, k * 3) * 0.85) }
        p.circle(x, y, r, F[Swift.min(n - 1, idx + 2)])
        p.circle(x - r * 0.16, y - r * 0.22, r * 0.78, c)
        if r > 1.6 { p.circle(x, y - r * 0.9, r * 0.42, c) }
        if idx <= 3 && r > 1.8 { p.circle(x - r * 0.28, y - r * 0.34, r * 0.36, F[Swift.max(0, idx - 1)]) }
        if idx < 6 { p.glow(x, y, r * 2.4 + 2, c, 0.18 * k) }
    }

    /// A puff of smoke at age u: three soft discs, swelling and thinning; warm lights its underside.
    static func smoke(_ p: Painter, _ x: Double, _ y: Double, _ size: Double, _ u: Double, _ col: FXColor, _ k: Double = 1, _ warm: FXColor = 0) {
        let r = size * (0.65 + Swift.min(1, u * 2.5) * 0.45 + u * 0.4)
        let a = Swift.min(1, u * 12) * Swift.min(1, (1 - u) * 2.4) * 0.58 * k
        if a <= 0.01 { return }
        let c = col != 0 ? FX.mix(col, FX.rampAt(FX.smokeRamp, u), u) : FX.rampAt(FX.smokeRamp, u * 1.05)
        p.disc(x, y, r, c, a * 0.45)
        p.disc(x + r * 0.05, y + r * 0.06, r * 0.74, c, a * 0.62)
        if warm != 0 && u < 0.6 { p.disc(x + r * 0.1, y + r * 0.3, r * 0.56, FX.mix(c, warm, 0.5), a * 0.7 * (1 - u / 0.6)) }
        if u < 0.5 { p.disc(x - r * 0.22, y - r * 0.3, r * 0.5, FX.mix(c, FX.white, 0.12), a * 0.4 * (1 - u * 2)) }
    }

    /// An ember at age u: hot and flickering, cooling to a dim red that blinks out. E is hot, warm, cool.
    static func ember(_ p: Painter, _ x: Double, _ y: Double, _ u: Double, _ E: [FXColor], _ ph: Double, _ k: Double = 1) {
        let left = 1 - u
        if left < 0.22 && sin(ph * 40) < 0 { return }
        let c = left > 0.5 ? (sin(ph * 22) > -0.2 ? E[0] : E[1]) : left > 0.22 ? E[1] : E[2]
        p.px(x, y, c)
        p.glow(x, y, 3, c, 0.32 * left * k)
    }

    /// A flat, translucent bank of haze centred on (x, y), thinning to nothing at its edge.
    static func haze(_ p: Painter, _ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ col: FXColor, _ a: Double) {
        if a <= 0.01 || rx < 0.5 || ry < 0.5 { return }
        var py = FX.floor(y - ry)
        while py <= FX.ceil(y + ry) {
            var px = FX.floor(x - rx)
            while px <= FX.ceil(x + rx) {
                let dx = (px + 0.5 - x) / rx, dy = (py + 0.5 - y) / ry, d = dx * dx + dy * dy
                if d < 1 { p.blend(px, py, col, a * (1 - d)) }
                px += 1
            }
            py += 1
        }
    }

    /// A shape from a bitmap (rows, "." empty), centred on (0, 0), scaled by whole k: the character at (dx, dy), or nil.
    static func bitmap(_ rows: [String], _ k: Int = 1, _ flip: Bool = false) -> (Int, Int) -> Swift.Character? {
        let grid = rows.map { Array($0) }
        let h = grid.count, w = grid[0].count, ox = (w * k) / 2, oy = (h * k) / 2
        return { dx, dy in
            var bx = Int(FX.floor(Double(dx + ox) / Double(k)))
            let by = Int(FX.floor(Double(dy + oy) / Double(k)))
            if bx < 0 || by < 0 || bx >= w || by >= h { return nil }
            if flip { bx = w - 1 - bx }
            let c = grid[by][bx]
            return c == "." ? nil : c
        }
    }

    /// A little shaded pixel icon at (x, y): every cell inside within ext of the centre, filled from
    /// R = outline, shadow, body, light, and repainted where inside returns a character listed in paint.
    static func icon(_ p: Painter, _ x: Double, _ y: Double, _ ext: Int, _ inside: (Int, Int) -> Swift.Character?, _ R: [FXColor],
                     _ a: Double = 1, _ paint: [Swift.Character: FXColor]? = nil) {
        let X = FX.round(x), Y = FX.round(y)
        func at(_ dx: Int, _ dy: Int) -> Bool { inside(dx, dy) != nil }
        for dy in (-ext - 1)...(ext + 1) {
            for dx in (-ext - 1)...(ext + 1) {
                let c: FXColor
                if let ch = inside(dx, dy) {
                    if let paint, let pc = paint[ch] { c = pc }
                    else {
                        let top = !at(dx, dy - 1), left = !at(dx - 1, dy), bottom = !at(dx, dy + 1), right = !at(dx + 1, dy)
                        c = top || left ? R[3] : bottom || right ? R[1] : R[2]
                    }
                } else if R[0] != 0 && (at(dx - 1, dy) || at(dx + 1, dy) || at(dx, dy - 1) || at(dx, dy + 1)) { c = R[0] }
                else { continue }
                p.dot(X + Double(dx), Y + Double(dy), c, a)
            }
        }
    }

    /// inside(dx, dy) for a shape given in its own unit space by f(u, v), turned by ang and scaled by s.
    static func shaped(_ f: @escaping (Double, Double) -> Bool, _ s: Double, _ ang: Double = 0) -> (Int, Int) -> Swift.Character? {
        let c = cos(ang), n = sin(ang)
        return { dx, dy in
            let x = Double(dx) + 0.5, y = Double(dy) + 0.5
            return f((x * c + y * n) / s, (-x * n + y * c) / s) ? "#" : nil
        }
    }

    /// A five-pointed star in unit space (points at radius 1, inner corners at r0).
    static func starShape(_ r0: Double = 0.45) -> (Double, Double) -> Bool {
        { u, v in
            let a = atan2(v, u) + Double.pi / 2, d = hypot(u, v), seg = (2 * Double.pi) / 5
            let k = 1 - abs(FX.mod(FX.mod(a, seg) + seg, seg) - seg / 2) / (seg / 2)
            return d <= 1 - (1 - r0) * pow(k, 0.8)
        }
    }

    /// A heart in unit space (two lobes and a point, about 2 wide and 2 tall, centred).
    static func heartShape(_ u: Double, _ v: Double) -> Bool {
        pow(u + 0.5, 2) + pow(v + 0.32, 2) <= pow(0.55, 2) || pow(u - 0.5, 2) + pow(v + 0.32, 2) <= pow(0.55, 2)
            || (v >= -0.32 && v <= 1 && abs(u) <= 1.04 * pow(1 - (v + 0.32) / 1.32, 0.75))
    }

    /// One eye: its box, its pixels, and the skin round it to paint it shut with.
    struct Eye { let x0: Int, x1: Int, y0: Int, y1: Int; let px: [(Int, Int)]; let skin: FXColor }

    nonisolated(unsafe) static let eyeMemo = FXMemo<[Eye]>()

    /// The creature's eyes, if any can be found: small blobs of very dark pixels inside the upper body,
    /// surrounded by it, left to right. Empty when nothing looks like eyes.
    static func eyes(_ a: FXActor) -> [Eye] {
        eyeMemo.get(a.key) {
            if let given = a.eyes {
                return given.map { (x, y) in Eye(x0: x, x1: x, y0: y, y1: y + 1, px: [(x, y), (x, y + 1)], skin: colorAt(a, x, y)) }
            }
            let S = shape(a), W = S.w
            let col = { (x: Int, y: Int) -> FXColor in S.on(x, y) ? colorAt(a, x, y) : 0 }
            let dark = { (x: Int, y: Int) -> Bool in
                S.on(x, y) && Double(y) < Double(S.h) * 0.4 && FX.luma(col(x, y)) < 0.15
                    && S.on(x - 1, y) && S.on(x + 1, y) && S.on(x, y - 1) && S.on(x, y + 1)
            }
            var seen = Set<Int>()
            var list: [Eye] = []
            for (x0, y0) in S.body {
                if seen.contains(y0 * W + x0) || !dark(x0, y0) { continue }
                var px: [(Int, Int)] = [], q = [(x0, y0)]
                seen.insert(y0 * W + x0)
                while let (x, y) = q.popLast() {
                    px.append((x, y))
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = x + dx, ny = y + dy, k = ny * W + nx
                        if seen.contains(k) || !(dark(nx, ny) || (S.on(nx, ny) && FX.luma(col(nx, ny)) > 0.95)) { continue }
                        seen.insert(k)
                        q.append((nx, ny))
                    }
                }
                if px.count < 2 || px.count > 14 { continue }
                let xs = px.map(\.0), ys = px.map(\.1)
                // counted in the order JavaScript's Map keeps: first seen first
                var counts: [(FXColor, Int)] = []
                for (x, y) in px {
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0)] {
                        let c = col(x + dx, y + dy), l = FX.luma(c)
                        if c != 0 && l > 0.5 && l < 0.95 && !px.contains(where: { $0.0 == x + dx && $0.1 == y + dy }) {
                            if let i = counts.firstIndex(where: { $0.0 == c }) { counts[i].1 += 1 } else { counts.append((c, 1)) }
                        }
                    }
                }
                let skin = FX.jsSort(counts) { p, q in Double(q.1 - p.1) }.first?.0
                let e = (x0: xs.min()!, x1: xs.max()!, y0: ys.min()!, y1: ys.max()!)
                if let skin, e.x1 - e.x0 <= 4 && e.y1 - e.y0 <= 5 { list.append(Eye(x0: e.x0, x1: e.x1, y0: e.y0, y1: e.y1, px: px, skin: skin)) }
            }
            list = FX.jsSort(list) { p, q in Double(p.x0 - q.x0) }
            if list.count > 2 { list = [] }
            return list
        }
    }
}

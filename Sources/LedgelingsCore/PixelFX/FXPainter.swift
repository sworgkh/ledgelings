// The frame an effect draws into, and the painter that draws: pixelfx's `createFrame` and `Painter`
// (https://github.com/patch-gg/pixelfx, MIT). A frame holds opaque colour (faded with ordered dither,
// never blended, except the few translucent volumes) and additive light; `FXComposite` turns the two
// into the 1-bit picture the overlay shows. Effects draw in local coordinates around their origin; the
// painter places and mirrors them.

import Foundation

/// w × h pixels whose top-left sits at (ox, oy).
public final class FXFrame {
    public let w: Int, h: Int
    public var ox: Int, oy: Int
    public var color: [UInt32]
    public var light: [UInt32]
    var ownPainter: Painter?
    public init(_ w: Int, _ h: Int, ox: Int = 0, oy: Int = 0) {
        self.w = w; self.h = h; self.ox = ox; self.oy = oy
        color = Array(repeating: 0, count: w * h)
        light = Array(repeating: 0, count: w * h)
    }
    public func clear() {
        for i in color.indices { color[i] = 0; light[i] = 0 }
    }
}

/// Which pass of an effect is being drawn: behind the creature, or in front of it.
public enum FXLayer { case back, front }

/// What a pixel shader hands back: colour, alpha, light colour and amount.
public struct FXShadeOut {
    public var c: FXColor = 0, a: Double = 1, l: FXColor = 0, k: Double = 0
}

public final class Painter {
    /// 4×4 ordered (Bayer) thresholds: a pixel at alpha a is drawn when a is above its cell's threshold.
    public static let bayer: [Double] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { ($0 + 0.5) / 16 }

    public unowned let frame: FXFrame
    var w: Int, h: Int, ox: Int, oy: Int
    var tx = 0.0, ty = 0.0, fx = 1.0, cs = 1.0, sn = 0.0
    public var fade = 1.0
    public var lightK = 1.0
    public var layer: FXLayer = .front

    public init(_ frame: FXFrame) {
        self.frame = frame
        w = frame.w; h = frame.h; ox = frame.ox; oy = frame.oy
    }

    @discardableResult public func reset() -> Painter {
        w = frame.w; h = frame.h; ox = frame.ox; oy = frame.oy
        tx = 0; ty = 0; fx = 1; cs = 1; sn = 0; fade = 1; lightK = 1; layer = .front
        return self
    }

    /// The effect's origin at (x, y) in frame space, mirrored if flip, rotated by angle.
    @discardableResult public func place(_ x: Double, _ y: Double, _ flip: Bool = false, _ angle: Double = 0) -> Painter {
        tx = x; ty = y; fx = flip ? -1 : 1; cs = cos(angle); sn = sin(angle)
        return self
    }

    // MARK: Local space <-> frame space

    @inline(__always) public func toX(_ x: Double, _ y: Double) -> Double { tx + x * fx * cs - y * sn }
    @inline(__always) public func toY(_ x: Double, _ y: Double) -> Double { ty + x * fx * sn + y * cs }
    @inline(__always) public func fromX(_ sx: Double, _ sy: Double) -> Double { let dx = sx - tx, dy = sy - ty; return (dx * cs + dy * sn) * fx }
    @inline(__always) public func fromY(_ sx: Double, _ sy: Double) -> Double { let dx = sx - tx, dy = sy - ty; return -dx * sn + dy * cs }
    /// The frame pixel of the local pixel cell holding (x, y).
    @inline(__always) public func cellX(_ x: Double, _ y: Double) -> Int { Int(FX.floor(toX(FX.floor(x) + 0.5, FX.floor(y) + 0.5))) }
    @inline(__always) public func cellY(_ x: Double, _ y: Double) -> Int { Int(FX.floor(toY(FX.floor(x) + 0.5, FX.floor(y) + 0.5))) }

    // MARK: Raw writes, frame space. Colour 0 is "nothing": it never erases.

    @inline(__always) public func put(_ sx: Int, _ sy: Int, _ c: FXColor, _ a: Double = 1) {
        if c == 0 { return }
        let a = a * fade
        if a < 1 && a <= Self.bayer[((sy & 3) << 2) | (sx & 3)] { return }
        let x = sx - ox, y = sy - oy
        if x < 0 || y < 0 || x >= w || y >= h { return }
        frame.color[y * w + x] = c
    }
    @inline(__always) public func add(_ sx: Int, _ sy: Int, _ c: FXColor, _ k: Double = 1) {
        let k = k * fade * lightK
        if k <= 0.004 { return }
        let x = sx - ox, y = sy - oy
        if x < 0 || y < 0 || x >= w || y >= h { return }
        let i = y * w + x, d = frame.light[i]
        let r = UInt32(Swift.min(255, Double(d & 255) + Double(c & 255) * k))
        let g = UInt32(Swift.min(255, Double((d >> 8) & 255) + Double((c >> 8) & 255) * k))
        let b = UInt32(Swift.min(255, Double((d >> 16) & 255) + Double((c >> 16) & 255) * k))
        frame.light[i] = (255 << 24) | (b << 16) | (g << 8) | r
    }
    /// A colour over what is there at alpha a, keeping the result's own alpha: soft smoke and mist.
    @inline(__always) public func blendPx(_ sx: Int, _ sy: Int, _ c: FXColor, _ a: Double) {
        let a = a * fade
        if c == 0 || a <= 0.004 { return }
        let x = sx - ox, y = sy - oy
        if x < 0 || y < 0 || x >= w || y >= h { return }
        let i = y * w + x, d = frame.color[i], da = Double(d >> 24) / 255, oa = a + da * (1 - a), k = a / oa
        @inline(__always) func ch(_ s: UInt32) -> UInt32 {
            FX.byte(Double((c >> s) & 255) * k + Double((d >> s) & 255) * (1 - k))
        }
        frame.color[i] = (FX.byte(oa * 255) << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0)
    }
    /// A translucent pixel at a local point.
    public func blend(_ x: Double, _ y: Double, _ c: FXColor, _ a: Double) { blendPx(cellX(x, y), cellY(x, y), c, a) }
    /// A translucent disc; c and a may depend on (d: 0 centre...1 rim, angle).
    public func disc(_ cx: Double, _ cy: Double, _ r: Double, _ c: FXColor, _ a: Double) {
        disc(cx, cy, r, { _, _ in c }, { _, _ in a })
    }
    public func disc(_ cx: Double, _ cy: Double, _ r: Double, _ c: (Double, Double) -> FXColor, _ a: (Double, Double) -> Double) {
        if r < 0.5 { return blend(cx, cy, c(0, 0), a(0, 0)) }
        each(cx - r, cy - r, cx + r, cy + r) { x, y, sx, sy in
            let dx = x - cx, dy = y - cy, d2 = dx * dx + dy * dy
            if d2 > r * r { return }
            let d = d2.squareRoot() / r, ang = atan2(dy, dx)
            self.blendPx(sx, sy, c(d, ang), a(d, ang))
        }
    }
    /// The colour under a local point (0 if empty).
    public func get(_ x: Double, _ y: Double) -> FXColor {
        let sx = cellX(x, y) - ox, sy = cellY(x, y) - oy
        return sx < 0 || sy < 0 || sx >= w || sy >= h ? 0 : frame.color[sy * w + sx]
    }

    // MARK: Pixels

    /// One opaque pixel.
    @inline(__always) public func px(_ x: Double, _ y: Double, _ c: FXColor) { put(cellX(x, y), cellY(x, y), c, 1) }
    /// One pixel at alpha a, faded by ordered dither.
    @inline(__always) public func dot(_ x: Double, _ y: Double, _ c: FXColor, _ a: Double = 1) { if a > 0 { put(cellX(x, y), cellY(x, y), c, a) } }
    /// Light added to one pixel.
    @inline(__always) public func light(_ x: Double, _ y: Double, _ c: FXColor, _ k: Double = 1) { add(cellX(x, y), cellY(x, y), c, k) }

    /// Every frame pixel whose centre falls in the local box, with that centre in local space: fn(lx, ly, sx, sy).
    public func each(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ fn: (Double, Double, Int, Int) -> Void) {
        var ax = Double.infinity, bx = -Double.infinity, ay = Double.infinity, by = -Double.infinity
        for k in 0..<4 {
            let x = k & 1 != 0 ? x1 : x0, y = k & 2 != 0 ? y1 : y0, sx = toX(x, y), sy = toY(x, y)
            if sx < ax { ax = sx }; if sx > bx { bx = sx }; if sy < ay { ay = sy }; if sy > by { by = sy }
        }
        guard ax.isFinite, bx.isFinite, ay.isFinite, by.isFinite else { return }
        let sx0 = Swift.max(Int(FX.floor(ax)), ox), sx1 = Swift.min(Int(FX.ceil(bx)), ox + w - 1)
        let sy0 = Swift.max(Int(FX.floor(ay)), oy), sy1 = Swift.min(Int(FX.ceil(by)), oy + h - 1)
        if sx0 > sx1 || sy0 > sy1 { return }
        for sy in sy0...sy1 {
            for sx in sx0...sx1 {
                let cx = Double(sx) + 0.5, cy = Double(sy) + 0.5
                fn(fromX(cx, cy), fromY(cx, cy), sx, sy)
            }
        }
    }

    /// A pixel shader over a local box: fn(x, y, &out) returns a colour, or sets out's fields; 0 leaves it alone.
    public func shade(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ fn: (Double, Double, inout FXShadeOut) -> FXColor) {
        var o = FXShadeOut()
        each(x0, y0, x1, y1) { lx, ly, sx, sy in
            o.c = 0; o.a = 1; o.l = 0; o.k = 0
            let r = fn(lx, ly, &o)
            let c = r != 0 ? r : o.c
            if c != 0 { self.put(sx, sy, c, o.a) }
            if o.k > 0 { self.add(sx, sy, o.l != 0 ? o.l : c, o.k) }
        }
    }

    // MARK: Shapes

    /// A 1 px line; c and a may depend on u (0 at the start, 1 at the end).
    public func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ c: FXColor, _ a: Double = 1) {
        line(x0, y0, x1, y1, { _ in c }, { _ in a })
    }
    public func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ c: (Double) -> FXColor, _ a: Double = 1) {
        line(x0, y0, x1, y1, c, { _ in a })
    }
    public func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ c: (Double) -> FXColor, _ a: (Double) -> Double) {
        var sx = cellX(x0, y0), sy = cellY(x0, y0)
        let ex = cellX(x1, y1), ey = cellY(x1, y1)
        let dx = abs(ex - sx), dy = -abs(ey - sy), stepx = sx < ex ? 1 : -1, stepy = sy < ey ? 1 : -1
        let n = Double(Swift.max(dx, -dy) == 0 ? 1 : Swift.max(dx, -dy))
        var err = dx + dy, i = 0.0
        while true {
            let u = i / n
            i += 1
            put(sx, sy, c(u), a(u))
            if sx == ex && sy == ey { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; sx += stepx }
            if e2 <= dx { err += dx; sy += stepy }
        }
    }
    /// Lines through a list of points.
    public func polyline(_ pts: [(Double, Double)], _ c: FXColor, _ a: Double = 1) {
        guard pts.count > 1 else { return }
        for i in 1..<pts.count { line(pts[i - 1].0, pts[i - 1].1, pts[i].0, pts[i].1, c, a) }
    }
    /// A thick segment with round ends; c and a may depend on (u along, v across: 0 centre, 1 edge).
    public func beam(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ width: Double, _ c: FXColor, _ a: Double = 1) {
        beam(x0, y0, x1, y1, width, { _, _ in c }, { _, _ in a })
    }
    public func beam(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ width: Double,
                     _ c: (Double, Double) -> FXColor, _ a: (Double, Double) -> Double) {
        let r = width / 2, dx = x1 - x0, dy = y1 - y0, l2r = dx * dx + dy * dy, L2 = l2r == 0 ? 1e-9 : l2r
        shade(Swift.min(x0, x1) - r, Swift.min(y0, y1) - r, Swift.max(x0, x1) + r, Swift.max(y0, y1) + r) { x, y, o in
            let u = FX.clamp(((x - x0) * dx + (y - y0) * dy) / L2), px = x0 + dx * u - x, py = y0 + dy * u - y
            let d2 = px * px + py * py
            if d2 > r * r { return 0 }
            let v = d2.squareRoot() / r
            o.c = c(u, v)
            o.a = a(u, v)
            return 0
        }
    }
    /// A filled disc; c and a may depend on (d: 0 centre to 1 rim, angle).
    public func circle(_ cx: Double, _ cy: Double, _ r: Double, _ c: FXColor, _ a: Double = 1) {
        circle(cx, cy, r, { _, _ in c }, { _, _ in a })
    }
    public func circle(_ cx: Double, _ cy: Double, _ r: Double, _ c: (Double, Double) -> FXColor, _ a: (Double, Double) -> Double) {
        if r < 0.6 { return dot(cx, cy, c(0, 0), a(0, 0)) }
        shade(cx - r, cy - r, cx + r, cy + r) { x, y, o in
            let dx = x - cx, dy = y - cy, d2 = dx * dx + dy * dy
            if d2 > r * r { return 0 }
            let d = d2.squareRoot() / r, ang = atan2(dy, dx)
            o.c = c(d, ang)
            o.a = a(d, ang)
            return 0
        }
    }
    /// An ellipse; c and a may depend on (d, angle).
    public func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ c: FXColor, _ a: Double = 1) {
        ellipse(cx, cy, rx, ry, { _, _ in c }, { _, _ in a })
    }
    public func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ c: (Double, Double) -> FXColor, _ a: (Double, Double) -> Double) {
        if rx <= 0 || ry <= 0 { return }
        shade(cx - rx, cy - ry, cx + rx, cy + ry) { x, y, o in
            let dx = (x - cx) / rx, dy = (y - cy) / ry, d2 = dx * dx + dy * dy
            if d2 > 1 { return 0 }
            let d = d2.squareRoot(), ang = atan2(dy, dx)
            o.c = c(d, ang)
            o.a = a(d, ang)
            return 0
        }
    }
    /// A ring from radius r - w to r; c and a may depend on (v: 0 inner to 1 outer, angle).
    public func ring(_ cx: Double, _ cy: Double, _ r: Double, _ w: Double, _ c: FXColor, _ a: Double = 1) {
        ring(cx, cy, r, w, { _, _ in c }, { _, _ in a })
    }
    public func ring(_ cx: Double, _ cy: Double, _ r: Double, _ w: Double, _ c: (Double, Double) -> FXColor, _ a: (Double, Double) -> Double) {
        let r0 = Swift.max(0, r - w)
        shade(cx - r, cy - r, cx + r, cy + r) { x, y, o in
            let dx = x - cx, dy = y - cy, d2 = dx * dx + dy * dy
            if d2 > r * r || d2 < r0 * r0 { return 0 }
            let span = r - r0 == 0 ? 1 : r - r0
            let v = w > 0 ? (d2.squareRoot() - r0) / span : 1, ang = atan2(dy, dx)
            o.c = c(v, ang)
            o.a = a(v, ang)
            return 0
        }
    }
    /// A band of a ring from angle a0 to a1 (a1 > a0), radius r - w to r; c and a depend on (u: 0 at a0...1 at a1,
    /// v: 0 inner...1 outer); w may depend on u.
    public func arc(_ cx: Double, _ cy: Double, _ r: Double, _ w: (Double) -> Double, _ a0: Double, _ a1: Double,
                    _ c: (Double, Double) -> FXColor, _ a: (Double, Double) -> Double) {
        let span = a1 - a0
        shade(cx - r, cy - r, cx + r, cy + r) { x, y, o in
            let dx = x - cx, dy = y - cy, d = (dx * dx + dy * dy).squareRoot()
            if d > r { return 0 }
            var ang = atan2(dy, dx) - a0
            ang -= FX.floor(ang / (Double.pi * 2)) * Double.pi * 2
            if ang > span { return 0 }
            let u = ang / span, ww = w(u)
            if ww <= 0 || d < r - ww { return 0 }
            let v = (d - (r - ww)) / ww
            o.c = c(u, v)
            o.a = a(u, v)
            return 0
        }
    }
    public func arc(_ cx: Double, _ cy: Double, _ r: Double, _ w: Double, _ a0: Double, _ a1: Double, _ c: FXColor, _ a: Double = 1) {
        arc(cx, cy, r, { _ in w }, a0, a1, { _, _ in c }, { _, _ in a })
    }
    /// A filled rectangle.
    public func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ c: FXColor, _ a: Double = 1) {
        if sn == 0 {
            let X0 = FX.round(x), Y0 = FX.round(y), X1 = FX.round(x + w), Y1 = FX.round(y + h)
            var yy = Y0
            while yy < Y1 {
                var xx = X0
                while xx < X1 { put(cellX(xx, yy), cellY(xx, yy), c, a); xx += 1 }
                yy += 1
            }
            return
        }
        shade(x, y, x + w, y + h) { lx, ly, o in
            if lx < x || ly < y || lx >= x + w || ly >= y + h { return 0 }
            o.c = c; o.a = a
            return 0
        }
    }
    /// A filled polygon (even-odd rule); c and a may depend on (x, y).
    public func poly(_ pts: [(Double, Double)], _ c: FXColor, _ a: Double = 1) { poly(pts, { _, _ in c }, { _, _ in a }) }
    public func poly(_ pts: [(Double, Double)], _ c: (Double, Double) -> FXColor, _ a: (Double, Double) -> Double) {
        var x0 = Double.infinity, y0 = Double.infinity, x1 = -Double.infinity, y1 = -Double.infinity
        for (x, y) in pts { if x < x0 { x0 = x }; if x > x1 { x1 = x }; if y < y0 { y0 = y }; if y > y1 { y1 = y } }
        let n = pts.count
        shade(x0, y0, x1, y1) { x, y, o in
            var inside = false, j = n - 1
            for i in 0..<n {
                let (xi, yi) = pts[i], (xj, yj) = pts[j]
                if (yi > y) != (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi { inside.toggle() }
                j = i
            }
            if !inside { return 0 }
            o.c = c(x, y)
            o.a = a(x, y)
            return 0
        }
    }
    public func tri(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ c: FXColor, _ a: Double = 1) {
        poly([(x0, y0), (x1, y1), (x2, y2)], c, a)
    }

    // MARK: Light

    /// A radial glow: k at the centre, falling to 0 at radius r.
    public func glow(_ x: Double, _ y: Double, _ r: Double, _ c: FXColor, _ k: Double = 0.5) {
        if r < 1 || k <= 0.004 { return }
        let cx = toX(x, y), cy = toY(x, y)
        let x0 = Int(FX.floor(cx - r)), x1 = Int(FX.ceil(cx + r)), y0 = Int(FX.floor(cy - r)), y1 = Int(FX.ceil(cy + r))
        for sy in y0...y1 {
            let dy = (Double(sy) + 0.5 - cy) / r
            for sx in x0...x1 {
                let dx = (Double(sx) + 0.5 - cx) / r, d = dx * dx + dy * dy
                if d >= 1 { continue }
                let f = 1 - d.squareRoot()
                add(sx, sy, c, f * f * k)
            }
        }
    }
    /// A glow around a segment.
    public func glowLine(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ r: Double, _ c: FXColor, _ k: Double = 0.5) {
        if r < 1 || k <= 0.004 { return }
        let ax = toX(x0, y0), ay = toY(x0, y0), bx = toX(x1, y1), by = toY(x1, y1)
        let dx = bx - ax, dy = by - ay, l2r = dx * dx + dy * dy, L2 = l2r == 0 ? 1e-9 : l2r
        let X0 = Int(FX.floor(Swift.min(ax, bx) - r)), X1 = Int(FX.ceil(Swift.max(ax, bx) + r))
        let Y0 = Int(FX.floor(Swift.min(ay, by) - r)), Y1 = Int(FX.ceil(Swift.max(ay, by) + r))
        for sy in Y0...Y1 {
            for sx in X0...X1 {
                let px = Double(sx) + 0.5, py = Double(sy) + 0.5, u = FX.clamp(((px - ax) * dx + (py - ay) * dy) / L2)
                let ex = ax + dx * u - px, ey = ay + dy * u - py, d = (ex * ex + ey * ey).squareRoot() / r
                if d >= 1 { continue }
                let f = 1 - d
                add(sx, sy, c, f * f * k)
            }
        }
    }
    /// A glow hugging a circle of radius R, falling off over width r.
    public func glowRing(_ x: Double, _ y: Double, _ R: Double, _ r: Double, _ c: FXColor, _ k: Double = 0.5) {
        if r < 1 || k <= 0.004 { return }
        let cx = toX(x, y), cy = toY(x, y), E = R + r
        for sy in Int(FX.floor(cy - E))...Int(FX.ceil(cy + E)) {
            for sx in Int(FX.floor(cx - E))...Int(FX.ceil(cx + E)) {
                let d = abs(hypot(Double(sx) + 0.5 - cx, Double(sy) + 0.5 - cy) - R) / r
                if d >= 1 { continue }
                let f = 1 - d
                add(sx, sy, c, f * f * k)
            }
        }
    }

    // MARK: Sprites, text, masks

    /// A little sprite from strings ("." and " " empty), top-left at (x, y); pal maps characters to colours.
    public func sprite(_ rows: [String], _ pal: [Swift.Character: FXColor], _ x: Double, _ y: Double,
                       scale k: Double = 1, a: Double = 1, flip: Bool = false, flipY: Bool = false, tint: FXColor? = nil) {
        let s = rows.map { Array($0) }
        let W = s.first?.count ?? 0
        for r in s.indices {
            for q in s[r].indices {
                let ch = s[r][q]
                if ch == "." || ch == " " { continue }
                let c = tint ?? pal[ch] ?? 0
                if c == 0 { continue }
                let col = Double(flip ? W - 1 - q : q), row = Double(flipY ? s.count - 1 - r : r)
                if k == 1 { dot(x + col, y + row, c, a) } else { rect(x + col * k, y + row * k, k, k, c, a) }
            }
        }
    }
    /// Pixel text, its top at y, set left, centre or right of x.
    public func text(_ str: String, _ x: Double, _ y: Double, _ c: FXColor, font: FXFont = .mini, scale k: Double = 1,
                     align: FXFont.Align = .left, outline: FXColor? = nil, shadow: FXColor? = nil, a: Double = 1) {
        text(str, x, y, { _, _ in c }, font: font, scale: k, align: align, outline: outline, shadow: shadow, a: a)
    }
    public func text(_ str: String, _ x: Double, _ y: Double, _ c: (Double, Double) -> FXColor, font: FXFont = .mini, scale k: Double = 1,
                     align: FXFont.Align = .left, outline: FXColor? = nil, shadow: FXColor? = nil, a: Double = 1) {
        let w = Double(font.width(of: str)) * k
        let left = FX.round(align == .center ? x - w / 2 : align == .right ? x - w : x), top = FX.round(y)
        if let ol = outline { font.raster(str) { gx, gy in self.rect(left + gx * k - 1, top + gy * k - 1, k + 2, k + 2, ol, a) } }
        if let sh = shadow { font.raster(str) { gx, gy in self.rect(left + gx * k + 1, top + gy * k + 1, k, k, sh, a) } }
        font.raster(str) { gx, gy in self.rect(left + gx * k, top + gy * k, k, k, c(gx, gy), a) }
    }
    /// Fill a mask with its top-left at (x, y); c may depend on (mx, my).
    public func mask(_ m: FXMask, _ x: Double, _ y: Double, _ c: (Int, Int) -> FXColor, _ a: (Int, Int) -> Double = { _, _ in 1 }) {
        for my in 0..<m.h {
            for mx in 0..<m.w where m.data[my * m.w + mx] != 0 { dot(x + Double(mx), y + Double(my), c(mx, my), a(mx, my)) }
        }
    }
    /// The 1 px outline just outside a mask.
    public func outline(_ m: FXMask, _ x: Double, _ y: Double, _ c: (Int, Int) -> FXColor, _ a: (Int, Int) -> Double = { _, _ in 1 }) {
        let at = { (mx: Int, my: Int) in mx >= 0 && my >= 0 && mx < m.w && my < m.h && m.data[my * m.w + mx] != 0 }
        for my in -1...m.h {
            for mx in -1...m.w where !at(mx, my) && (at(mx - 1, my) || at(mx + 1, my) || at(mx, my - 1) || at(mx, my + 1)) {
                dot(x + Double(mx), y + Double(my), c(mx, my), a(mx, my))
            }
        }
    }
}

/// A 1-bit shape: which pixels of a w × h box are on.
public struct FXMask: Sendable {
    public let w: Int, h: Int
    public var data: [UInt8]
    public init(w: Int, h: Int, data: [UInt8]) { self.w = w; self.h = h; self.data = data }
}

// Shared by the arcane effects: the ordered dither, rings lying on the floor, an original rune alphabet, and the
// caster's silhouette shaded and squeezed for the blink. Ported from pixelfx's `fx/arcane/_lib.js` (MIT); its
// dithered ramp and the blink's squeeze adapt Sprite Fusion's open-source black hole and blink
// (https://www.spritefusion.com/pixel-art-vfx), MIT, Copyright (c) 2026 Hugo Duprez.

import Foundation

enum FXArcane {
    static let cross: [(Double, Double)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]

    /// The 4x4 ordered-dither threshold (0..1) of the pixel cell holding (x, y).
    static func bayer(_ x: Double, _ y: Double) -> Double {
        Painter.bayer[((Int(FX.floor(y)) & 3) << 2) | (Int(FX.floor(x)) & 3)]
    }

    /// A ring lying on the floor: centre (cx, cy), radius r, squashed by sy, 1 px thick at any size. c and a are
    /// functions of the angle g round it; keep(g) picks which part to draw.
    static func floorRing(_ p: Painter, _ cx: Double, _ cy: Double, _ r: Double, _ sy: Double,
                          _ c: (Double) -> FXColor, _ a: (Double) -> Double, _ keep: ((Double) -> Bool)? = nil) {
        if r < 0.5 { return }
        let ry = r * sy
        p.shade(cx - r - 1, cy - ry - 1, cx + r + 1, cy + ry + 1) { x, y, o in
            let nx = (x - cx) / r, ny = (y - cy) / Swift.max(0.3, ry), d = hypot(nx, ny)
            if d < 1e-6 { return 0 }
            let g = hypot(nx / r, ny / Swift.max(0.3, ry)) / d
            if abs(d - 1) / g > 0.5 { return 0 }
            let ang = atan2(ny, nx)
            if let keep, !keep(ang) { return 0 }
            o.c = c(ang)
            o.a = a(ang)
            return 0
        }
    }

    // An original rune alphabet: angular 3 x 5 glyphs that stay readable standing upright at 1x.
    static let glyphs: [[String]] = [
        [".#.", "#.#", ".#.", ".#.", "#.#"],
        ["#.#", "#.#", ".#.", "#.#", "#.#"],
        ["##.", "#.#", "##.", "#..", "#.."],
        ["#..", "#.#", "###", "#.#", "..#"],
        [".##", "#..", ".#.", "..#", "##."],
        ["###", ".#.", "###", ".#.", ".#."],
        ["#.#", "###", "#.#", "..#", "..#"],
        [".#.", ".##", ".#.", "##.", ".#."],
    ]

    /// Rune i standing on (x, y): its bottom row on y, centred on x, over an optional darker colour a pixel lower.
    static func glyph(_ p: Painter, _ i: Int, _ x: Double, _ y: Double, _ c: FXColor, _ a: Double = 1, _ under: FXColor = 0) {
        let n = glyphs.count, g = glyphs[((i % n) + n) % n], X = FX.round(x) - 1, Y = FX.round(y) - Double(g.count) + 1
        if under != 0 { p.sprite(g, [:], X, Y + 1, a: a, tint: under) }
        p.sprite(g, [:], X, Y, a: a, tint: c)
    }

    /// A character's silhouette shaded by how light each pixel is: 1 its dark outline, 2 mid, 3 light (0 empty).
    static func shades(_ A: FXActor) -> [UInt8] {
        var s = [UInt8](repeating: 0, count: A.w * A.h)
        for i in s.indices where A.mask.data[i] != 0 {
            let l = FX.luma(A.pixels[i])
            s[i] = l < 0.24 ? 1 : l < 0.62 ? 2 : 3
        }
        return s
    }

    /// Silhouette A squeezed to sx of its width about its middle and shifted by dx: body colour on its pixels,
    /// edge colour on its dark outline pixels. sh is shades(A).
    static func squeezed(_ p: Painter, _ A: FXActor, _ sh: [UInt8], _ sx: Double, _ body: FXColor, _ edge: FXColor,
                         _ a: Double = 1, _ dx: Double = 0) {
        if sx <= 0.02 { return }
        let cx = Double(A.x) + Double(A.w) / 2, half = Double(A.w) / 2 + 1
        for y in 0..<A.h {
            var x = FX.floor(cx - half * sx)
            let x1 = FX.ceil(cx + half * sx)
            while x <= x1 {
                let i = Int(FX.round(cx + (x + 0.5 - cx) / sx - 0.5)) - A.x
                let v = i < 0 || i >= A.w ? 0 : sh[y * A.w + i]
                if v != 0 { p.dot(x + dx, Double(A.y + y), v == 1 ? edge : body, a) }
                x += 1
            }
        }
    }
}

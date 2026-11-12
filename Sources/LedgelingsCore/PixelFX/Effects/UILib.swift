// Helpers for the ui effects: big pixel words with a hand-made finish and a character lit or flashed by
// the effect. pixelfx's `fx/ui/_lib.js` (MIT); tintActor adapts the body flash of Sprite Fusion's
// open-source power-up (https://www.spritefusion.com/pixel-art-vfx/power-up), MIT License,
// Copyright (c) 2026 Hugo Duprez.

import Foundation

enum FXUI {
    typealias Glyph = (w: Int, rows: [[Bool]])
    struct Letter { let ch: Swift.Character; let g: Glyph?; let x: Int; let w: Int; let h: Int }

    /// The letters of str in a pixel font, laid out left to right in font pixels.
    static func spell(_ str: String, _ font: FXFont = .big) -> (letters: [Letter], w: Int, h: Int) {
        var letters: [Letter] = [], x = 0
        for ch in str {
            let g = font.glyph(ch), w = g?.w ?? font.space
            letters.append(Letter(ch: ch, g: g, x: x, w: w, h: font.h))
            x += w + font.gap
        }
        return (letters, Swift.max(0, x - font.gap), font.h)
    }

    /// One letter of a word: its glyph, top-left, px per font pixel, alpha, white flash, italic lean.
    struct Item { var g: Glyph; var x: Double; var y: Double; var sx: Double; var sy: Double; var a = 1.0; var flash = 0.0; var slant = 0.0 }
    struct WordStyle {
        var fill: [FXColor]; var edge: FXColor? = nil; var under: FXColor? = nil; var outline: FXColor
        var ow = 1; var shadow: FXColor? = nil; var shine: Double? = nil; var shineY: Double? = nil; var glint: FXColor? = nil
    }

    /// Letters drawn as one word: a gradient down each letter, a lit top edge, a shaded underside, a 1 px dark
    /// outline and a drop shadow, an optional diagonal shine and a white flash.
    static func drawWord(_ p: Painter, _ items: [Item], _ st: WordStyle) {
        if items.isEmpty { return }
        var bx0 = Double.infinity, by0 = Double.infinity, bx1 = -Double.infinity, by1 = -Double.infinity
        for it in items {
            let h = Double(it.g.rows.count) * it.sy, w = Double(it.g.w) * it.sx, sl = abs(it.slant) * Double(it.g.rows.count)
            bx0 = Swift.min(bx0, it.x - sl); bx1 = Swift.max(bx1, it.x + w + sl)
            by0 = Swift.min(by0, it.y); by1 = Swift.max(by1, it.y + h)
        }
        let ow = st.ow
        let x0 = Int(FX.floor(bx0)) - 1 - ow, y0 = Int(FX.floor(by0)) - 1 - ow, x1 = Int(FX.ceil(bx1)) + 2 + ow, y1 = Int(FX.ceil(by1)) + 3 + ow
        let W = x1 - x0, H = y1 - y0
        var ids = [Int](repeating: 0, count: W * H), edges = [Int](repeating: 0, count: W * H)
        for (k, it) in items.enumerated() {
            let g = it.g, gh = g.rows.count, h = Double(gh) * it.sy, bot = it.y + h, sl = it.slant
            let cell = { (r: [Bool]?, i: Int) -> Bool in guard let r, i >= 0, i < r.count else { return false }; return r[i] }
            var py = FX.floor(it.y)
            while py < FX.ceil(bot) {
                defer { py += 1 }
                let gy = Int(FX.floor((py + 0.5 - it.y) / it.sy))
                if gy < 0 || gy >= gh { continue }
                let shift = FX.round(((bot - py - 0.5) / it.sy) * sl)
                let ry = py + 0.5 - it.y - Double(gy) * it.sy, row = g.rows[gy]
                var px = FX.floor(it.x + shift) - 1
                while px <= FX.ceil(it.x + shift + Double(g.w) * it.sx) {
                    defer { px += 1 }
                    let fx = px + 0.5 - it.x - shift, gxd = FX.floor(fx / it.sx)
                    if gxd < 0 || gxd >= Double(g.w) { continue }
                    let gx = Int(gxd)
                    if !row[gx] { continue }
                    let i = (Int(py) - y0) * W + (Int(px) - x0)
                    if i < 0 || i >= W * H { continue }
                    ids[i] = k + 1
                    // the bevel follows the font pixels: lit top, shaded underside, lit left; diagonals stay whole
                    let rx = fx - gxd * it.sx, up: [Bool]? = gy > 0 ? g.rows[gy - 1] : nil, dn: [Bool]? = gy < gh - 1 ? g.rows[gy + 1] : nil
                    let open = { (r: [Bool]?) -> Bool in r == nil || (!cell(r, gx) && !cell(r, gx - 1) && !cell(r, gx + 1)) }
                    edges[i] = (ry < 1 && open(up) ? 1 : 0) | (ry >= it.sy - 1 && open(dn) ? 2 : 0) | (rx < 1 && !(gx > 0 && row[gx - 1]) ? 4 : 0)
                }
            }
        }
        let at = { (x: Int, y: Int) -> Int in x < x0 || y < y0 || x >= x1 || y >= y1 ? 0 : ids[(y - y0) * W + (x - x0)] }
        let F = st.fill, nF = F.count, glint = st.glint ?? FX.white, sy0 = st.shineY ?? Double(y0)
        for y in y0..<y1 {
            for x in x0..<x1 {
                let id = at(x, y)
                if id != 0 {
                    let it = items[id - 1], v = (Double(y) + 0.5 - it.y) / (Double(it.g.rows.count) * it.sy)
                    let i = Int(Swift.min(Double(nF - 1), Swift.max(0, FX.floor((1 - v) * Double(nF)))))
                    var c = F[i]
                    let e = edges[(y - y0) * W + (x - x0)]
                    if e & 1 != 0 { c = st.edge ?? F[nF - 1] }
                    else if e & 2 != 0 { c = st.under ?? F[0] }
                    else if e & 4 != 0 && i < nF - 1 { c = F[i + 1] }
                    if let shine = st.shine {
                        let d = abs(Double(x) + 0.5 - (Double(y) + 0.5 - sy0) * 0.6 - shine)
                        if d < 1.1 { c = FX.white } else if d < 2.4 { c = glint }
                    }
                    // a flash is white all over, then wipes up off the letter (no dither)
                    if it.flash > 0.6 || (it.flash > 0.25 && v < 0.5) { c = FX.white }
                    p.dot(Double(x), Double(y), c, it.a)
                    continue
                }
                // the outline hugs every letter; the shadow drops below and right of it
                var n = 0
                var dy = -ow
                while dy <= ow && n == 0 {
                    var dx = -ow
                    while dx <= ow && n == 0 { if ow < 2 || abs(dx) + abs(dy) < 4 { n = at(x + dx, y + dy) }; dx += 1 }
                    dy += 1
                }
                if n != 0 { p.dot(Double(x), Double(y), st.outline, items[n - 1].a); continue }
                var s = at(x - ow, y - 1 - ow)
                if s == 0 { s = at(x + 1 - ow, y - 1 - ow) }
                if s == 0 { s = at(x - ow, y - ow) }
                if s != 0, let sh = st.shadow { p.dot(Double(x), Double(y), sh, items[s - 1].a * 0.9) }
            }
        }
    }

    /// Flash a character in light: its own pixels recoloured by brightness into ramp ([shadow, middle, light]);
    /// k steps down without dither, above 0.8 the lightest go white.
    static func tintActor(_ p: Painter, _ A: FXActor, _ k: Double, _ ramp: [FXColor]) {
        if k <= 0.12 { return }
        let m = A.mask, pix = A.pixels, cut = k > 0.6 ? 0 : k > 0.3 ? 0.22 : 0.5
        for j in 0..<m.h {
            for i in 0..<m.w {
                let q = j * m.w + i
                if m.data[q] == 0 { continue }
                let l = FX.luma(pix[q])
                if l < cut { continue }
                p.px(Double(A.x + i), Double(A.y + j), l > 0.5 ? (k > 0.8 ? FX.white : ramp[2]) : l > 0.22 ? ramp[1] : ramp[0])
            }
        }
    }

    /// Light a character: additive light over its body (k), stronger towards the top, and light catching the
    /// edge just inside its outline (rim), mixed into its own colours.
    static func lightActor(_ p: Painter, _ A: FXActor, _ c: FXColor, _ k: Double, _ rim: Double = 0, _ t: Double = 0) {
        if k <= 0.01 && rim <= 0.01 { return }
        let m = A.mask, pix = A.pixels
        let has = { (i: Int, j: Int) -> Bool in i >= 0 && j >= 0 && i < m.w && j < m.h && m.data[j * m.w + i] != 0 }
        for j in 0..<m.h {
            for i in 0..<m.w {
                if m.data[j * m.w + i] == 0 { continue }
                if k > 0.01 { p.light(Double(A.x + i), Double(A.y + j), c, k * (1.1 - (0.5 * Double(j)) / Double(m.h))) }
                if rim <= 0.01 || !has(i - 1, j) || !has(i + 1, j) || !has(i, j - 1) { continue }
                if has(i - 2, j) && has(i + 2, j) && has(i, j - 2) { continue }
                let f = rim * (0.75 + 0.35 * FX.noise(Double(j) * 0.6 - t * 8, Double(i) * 3))
                if f > 0.25 {
                    let own = pix[j * m.w + i]
                    p.px(Double(A.x + i), Double(A.y + j), FX.mix(own != 0 ? own : c, c, Swift.min(0.85, f)))
                }
            }
        }
    }

    /// A glowing 1 px line just outside a character, flickering: an aura's edge.
    static func haloActor(_ p: Painter, _ A: FXActor, _ c: FXColor, _ k: Double, _ t: Double = 0) {
        if k <= 0.02 { return }
        p.outline(A.mask, Double(A.x), Double(A.y), { _, _ in c }, { mx, my in k * (0.75 + 0.45 * FX.noise(Double(my) * 0.45 - t * 7, Double(mx) * 3)) })
    }
}

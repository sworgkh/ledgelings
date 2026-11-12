// Shared by the nature effects: a leaf that turns and flips about its midrib. Ported from pixelfx's
// `fx/nature/_lib.js` (MIT).

import Foundation

enum FXNature {
    /// A leaf len px long and wid px across at its widest, centred on (x, y), turned by ang and flipping about its
    /// midrib by fl (radians: edge on at pi/2, its paler underside showing past it). pal: [dark, shade, body, light].
    static func drawLeaf(_ p: Painter, _ x: Double, _ y: Double, _ len: Double, _ wid: Double, _ ang: Double, _ fl: Double,
                         _ pal: [FXColor], _ alpha: Double = 1) {
        let ca = cos(ang), sa = sin(ang), sq = cos(fl), w = Swift.max(0.55, abs(sq) * wid), under = sq < 0
        let R = Int(FX.ceil(len / 2 + 2)), X = FX.round(x), Y = FX.round(y)
        func inside(_ i: Int, _ j: Int) -> Int {
            let fi = Double(i) + 0.5, fj = Double(j) + 0.5
            let u = fi * ca + fj * sa + len / 2, v = -fi * sa + fj * ca
            if u < 0 || u > len { return 0 }
            let half = w * pow(sin((Double.pi * u) / len), 0.75)
            return abs(v) <= half ? (v < 0 ? 1 : 2) : 0
        }
        for j in -R...R {
            for i in -R...R {
                let s = inside(i, j)
                if s == 0 {
                    if inside(i - 1, j) != 0 || inside(i + 1, j) != 0 || inside(i, j - 1) != 0 || inside(i, j + 1) != 0 {
                        p.dot(X + Double(i), Y + Double(j), pal[0], alpha)
                    }
                    continue
                }
                let fi = Double(i) + 0.5, fj = Double(j) + 0.5
                let u = fi * ca + fj * sa + len / 2, v = -fi * sa + fj * ca
                let rib = abs(v) < 0.5 && u > len * 0.12 && u < len * 0.88 && w > 1.2
                p.dot(X + Double(i), Y + Double(j), rib ? pal[1] : (s == 1) != under ? pal[3] : pal[2], alpha)
            }
        }
        // the stem trails off the base
        p.dot(X - ca * (len / 2 + 1), Y - sa * (len / 2 + 1), pal[1], alpha)
    }
}

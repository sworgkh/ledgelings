// Shared by the pickup effects: pixelfx's `fx/pickups/_lib.js` (MIT), the parts the ported effects use.

import Foundation

enum FXPickups {
    /// A four-point star glint: arms of arm px in c, dimmer tips, a white heart, its own light.
    static func glint(_ p: Painter, _ x: Double, _ y: Double, _ arm: Double, _ c: FXColor, _ k: Double = 0.4, _ tip: FXColor? = nil) {
        let tip = tip ?? FX.scale(c, 0.8)
        let n = FX.round(arm), X = FX.floor(x), Y = FX.floor(y)
        if n < 0 { return }
        var d = 1.0
        while d <= n {
            let cc = d == n && n > 1 ? tip : c
            p.px(X + d, Y, cc); p.px(X - d, Y, cc); p.px(X, Y + d, cc); p.px(X, Y - d, cc)
            d += 1
        }
        p.px(X, Y, n > 0 ? FX.white : c)
        p.glow(X + 0.5, Y + 0.5, 3 + n * 2.5, c, k)
    }
}

import Foundation

extension Weather {
    /// A prop's pixels, row by row from the top, 0 for nothing: drawn in Blocky's style (square pixels, flat fill,
    /// a 1-pixel dark-tint outline, a light line top-left, a shade line bottom-right, no curves: a dome is steps).
    public struct Art: Equatable, Sendable {
        public let w: Int, h: Int
        public var pixels: [FXColor]
        public init(w: Int, h: Int) {
            self.w = w
            self.h = h
            pixels = Array(repeating: 0, count: w * h)
        }
        public func at(_ x: Int, _ y: Int) -> FXColor { x >= 0 && y >= 0 && x < w && y < h ? pixels[y * w + x] : 0 }
        mutating func set(_ x: Int, _ y: Int, _ c: FXColor) { if x >= 0 && y >= 0 && x < w && y < h { pixels[y * w + x] = c } }
        /// The pixels as RGBA bytes, for a picture.
        public var rgba: [UInt8] {
            var out = [UInt8](repeating: 0, count: w * h * 4)
            for (i, c) in pixels.enumerated() where c != 0 {
                out[i * 4] = UInt8(c & 255); out[i * 4 + 1] = UInt8((c >> 8) & 255); out[i * 4 + 2] = UInt8((c >> 16) & 255); out[i * 4 + 3] = 255
            }
            return out
        }

        /// The outline, light and shade of a filled shape (every pixel of `fill` colour), as Blocky is drawn: the
        /// edge pixels take the dark tint, the inside ones next to the top or left edge the light, next to the
        /// bottom or right edge the shade.
        mutating func shapeUp(fill: FXColor) {
            let inside = pixels.map { $0 == fill }
            func filled(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < w && y < h && inside[y * w + x] }
            let dark = FX.scale(fill, 0.45), light = FX.mix(fill, FX.white, 0.45), shade = FX.scale(fill, 0.78)
            for y in 0..<h {
                for x in 0..<w where filled(x, y) {
                    if !filled(x - 1, y) || !filled(x + 1, y) || !filled(x, y - 1) || !filled(x, y + 1) { set(x, y, dark); continue }
                    if !filled(x - 2, y) || !filled(x, y - 2) { set(x, y, light) }
                    else if !filled(x + 2, y) || !filled(x, y + 2) { set(x, y, shade) }
                }
            }
        }
    }

    /// The colours an umbrella may take, one per creature or group: bright and flat.
    public static let umbrellaColours = ["#e8463c", "#f2b134", "#3d9be9", "#5bbf5a", "#b55fd6", "#ef7fb0", "#2fb8a8", "#f07c2a"].map(FX.hex)
    static let handle = FX.hex("#3a2a1e")

    /// The colour of `name`'s umbrella: always the same one for the same character.
    public static func umbrellaColour(for name: String) -> FXColor {
        umbrellaColours[name.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 9973 } % umbrellaColours.count]
    }

    /// An umbrella `width` pixels across, open over whoever holds it (the handle's foot at the bottom middle):
    /// a stepped dome with a scalloped rim. Inside out, the canopy is a cup pointing up, its ribs showing.
    public static func umbrella(width: Int, colour: FXColor, insideOut: Bool = false) -> Art {
        let w = Swift.max(12, width | 1)                 // odd, so the handle stands in the middle
        let dome = umbrellaDome(width: w), stick = 9, h = dome + stick + 1
        var a = Art(w: w, h: h)
        let mid = w / 2
        // Each row of the dome, from the top, reaches out as far as a quarter circle would: steps, not a curve.
        let reach = (0..<dome).map { r -> Int in
            let k = 1 - Double(r + 1) / Double(dome)
            return Swift.max(2, Swift.min(mid, Int((Double(mid) * (1 - k * k).squareRoot()).rounded())))
        }
        for r in 0..<dome {
            let row = insideOut ? dome - 1 - r : r
            for x in (mid - reach[r])...(mid + reach[r]) { a.set(x, row, colour) }
        }
        // The rim: a notch between ribs every few pixels (open), or the ribs sticking out (inside out).
        if !insideOut {
            var x = mid % 5
            while x < w { if x != mid { a.set(x, dome - 1, 0) }; x += 5 }
        }
        a.shapeUp(fill: colour)
        if insideOut {
            for x in stride(from: mid % 5, to: w, by: 5) where x != mid { a.set(x, 0, handle) }
        }
        // The stick and the hook at its foot.
        let top = insideOut ? dome - 1 : 1
        for y in top..<(dome + stick) { a.set(mid, y, handle) }
        a.set(mid - 1, dome + stick, handle)
        a.set(mid - 2, dome + stick - 1, handle)
        return a
    }

    /// Rows in an umbrella's dome `width` pixels across: a third as tall as it is wide, at least five.
    public static func umbrellaDome(width: Int) -> Int { Swift.max(5, width / 3) }

    /// A tiny snowman: two square blocks of snow, black square eyes, a carrot nose. About as tall as a creature's half.
    public static func snowman() -> Art {
        let white = FX.hex("#eef4fc"), eye = FX.hex("#000000"), carrot = FX.hex("#f08a24")
        var a = Art(w: 11, h: 15)
        for y in 0..<6 { for x in 3..<9 { a.set(x, y, white) } }       // the head, a square
        for y in 6..<15 { for x in 1..<10 { a.set(x, y, white) } }      // the body, a bigger square
        a.shapeUp(fill: white)
        a.set(5, 2, eye); a.set(7, 2, eye)
        a.set(8, 3, carrot); a.set(9, 3, carrot)
        for y in [9, 12] { a.set(5, y, FX.hex("#3a2a1e")) }             // two buttons
        return a
    }

    /// A snowball, four pixels square.
    public static func snowball() -> Art {
        let white = FX.hex("#f4f8ff")
        var a = Art(w: 4, h: 4)
        for i in a.pixels.indices { a.pixels[i] = white }
        a.shapeUp(fill: white)
        return a
    }

    /// A drop of water falling off a wet creature.
    public static func drip() -> Art {
        var a = Art(w: 1, h: 2)
        a.set(0, 0, FX.hex("#b4d4ff")); a.set(0, 1, FX.hex("#4f82d6"))
        return a
    }
}

extension Weather {
    /// Three gusts of wind, stepped streaks: the Wind row's picture.
    public static func gusts() -> Art {
        let c = FX.hex("#9fc2e0")
        var a = Art(w: 16, h: 11)
        for (y, x0, x1) in [(1, 2, 12), (5, 0, 15), (8, 4, 13)] {
            for yy in y...(y + 1) { for x in x0...x1 { a.set(x, yy, c) } }
            a.set(x1 - 1, y - 1, c); a.set(x1, y - 1, c)          // the curl at the tip, a step up
        }
        a.shapeUp(fill: c)
        return a
    }

    /// The sun, a square with four stubby rays: Clear's picture.
    public static func sun() -> Art {
        let c = FX.hex("#f6c63c")
        var a = Art(w: 14, h: 14)
        for y in 3..<11 { for x in 3..<11 { a.set(x, y, c) } }
        for k in 6..<8 { a.set(k, 0, c); a.set(k, 1, c); a.set(k, 12, c); a.set(k, 13, c); a.set(0, k, c); a.set(1, k, c); a.set(12, k, c); a.set(13, k, c) }
        a.shapeUp(fill: c)
        return a
    }

    /// Each weather's picture, and Clear's (`nil`): for a menu or a button.
    public static func icon(_ kind: Kind?) -> Art {
        switch kind {
        case .snow: snowman()
        case .rain: umbrella(width: 15, colour: umbrellaColours[2])
        case .wind: gusts()
        case .storm: umbrella(width: 15, colour: umbrellaColours[4], insideOut: true)
        case nil: sun()
        }
    }
}

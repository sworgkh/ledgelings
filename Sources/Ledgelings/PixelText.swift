import AppKit
import CoreText

/// Words drawn the way the creatures are: small, blocky letters with no
/// smoothing, a 1-pixel dark outline round them, on a flat plate with a light
/// line along its top and left and a shade line along its bottom and right.
/// For the ball games' scoreboard and their GOAL! and HOME RUN! The colony
/// draws the result scaled up with square pixels, like any sprite.
enum PixelText {
    struct Style {
        var ink: (UInt8, UInt8, UInt8)
        /// The plate behind the letters; nil for letters alone.
        var plate: (UInt8, UInt8, UInt8)?
        var size: CGFloat
    }

    /// The scoreboard: pale yellow on a dark plate.
    static let board = Style(ink: (250, 222, 110), plate: (46, 50, 74), size: 8)
    /// A cheer across the screen: big, bright, no plate.
    static let banner = Style(ink: (255, 214, 70), plate: nil, size: 13)

    /// `text` in `style`, and its size in pixels.
    static func image(_ text: String, _ style: Style) -> CGImage? {
        let font = NSFont(name: "Verdana-Bold", size: style.size) ?? NSFont.monospacedSystemFont(ofSize: style.size, weight: .bold)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white]))
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = Int(ceil(CTLineGetTypographicBounds(line, &ascent, &descent, nil)))
        let pad = style.plate == nil ? 1 : 4
        let w = width + pad * 2, h = Int(ceil(ascent + descent)) + pad * 2
        guard w > 2, h > 2 else { return nil }
        // The letters, hard-edged.
        var mask = [UInt8](repeating: 0, count: w * h)
        guard let ink = mask.withUnsafeMutableBytes({ buffer -> Bool? in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
            ctx.setShouldAntialias(false)
            ctx.setAllowsFontSmoothing(false)
            ctx.setShouldSmoothFonts(false)
            ctx.textPosition = CGPoint(x: CGFloat(pad), y: CGFloat(pad) + descent)
            CTLineDraw(line, ctx)
            return true
        }), ink else { return nil }
        // The context's first row in memory is its top row, as the pixels below are written.
        func lit(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < w && y < h && mask[y * w + x] > 127 }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        func put(_ x: Int, _ y: Int, _ c: (UInt8, UInt8, UInt8)) {
            let k = (y * w + x) * 4
            pixels[k] = c.0; pixels[k + 1] = c.1; pixels[k + 2] = c.2; pixels[k + 3] = 255
        }
        func mix(_ c: (UInt8, UInt8, UInt8), _ to: UInt8, _ share: Double) -> (UInt8, UInt8, UInt8) {
            func m(_ v: UInt8) -> UInt8 { UInt8(Double(v) + (Double(to) - Double(v)) * share) }
            return (m(c.0), m(c.1), m(c.2))
        }
        if let plate = style.plate {
            for y in 0..<h { for x in 0..<w {
                let edge = x == 0 || y == 0 || x == w - 1 || y == h - 1
                let colour = edge ? mix(plate, 0, 0.6) : (x == 1 || y == 1) ? mix(plate, 255, 0.25)
                    : (x == w - 2 || y == h - 2) ? mix(plate, 0, 0.25) : plate
                put(x, y, colour)
            } }
        }
        let outline = mix(style.ink, 0, 0.78)
        for y in 0..<h { for x in 0..<w where !lit(x, y) {
            if (-1...1).contains(where: { dy in (-1...1).contains { dx in lit(x + dx, y + dy) } }) { put(x, y, outline) }
        } }
        for y in 0..<h { for x in 0..<w where lit(x, y) {
            let top = !lit(x, y - 1) || !lit(x - 1, y), bottom = !lit(x, y + 1) || !lit(x + 1, y)
            put(x, y, top && !bottom ? mix(style.ink, 255, 0.3) : bottom && !top ? mix(style.ink, 0, 0.15) : style.ink)
        } }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

import AppKit
import LedgelingsCore

/// One monitor's water for one frame, in GLOBAL coordinates (`Colony+Dive`).
struct WaterSnapshot {
    struct Sprite {
        var image: CGImage?
        var centre: CGPoint
        var mirrored: Bool
    }
    struct Weed {
        var x: CGFloat
        var height: Int
        var phase: Double
    }
    /// The monitor's frame; the water fills it from the bottom up to `surface`.
    var pool: CGRect
    var surface: CGFloat
    /// How see-through: the setting, 0.1…0.7.
    var opacity: Double
    var time: Double
    /// Screen points per water pixel: the sea life's pixels are the creatures' size.
    var scale: CGFloat
    /// The sea sheet's cell.
    var cell: CGSize
    var critters: [Sprite]
    var bubbles: [Sprite]
    var weeds: [Weed]
    var coral: CGImage?
}

/// Paints the water as pixel art, a few hundred pixels wide, which its layer
/// shows magnified with square pixels: flat bands, no gradients. Two pictures:
/// the BACK one behind the creatures (the water, light rays from the surface,
/// caustics dancing on the floor, the seaweed and coral, the sea life), and the
/// FRONT one over them (a thin tint, so a diver looks under water, the wavy
/// surface line with its foam, and the bubbles rising).
enum WaterPainter {
    /// How many pixels of air over the surface the pictures keep, for the waves.
    static let headroom = 4

    // The water's colours: a deep band at the bottom, the water, the rays, the caustics' light, the foam.
    static let deep = (r: 18.0, g: 74.0, b: 128.0)
    static let water = (r: 40.0, g: 120.0, b: 182.0)
    static let ray = (r: 96.0, g: 170.0, b: 220.0)
    static let caustic = (r: 170.0, g: 226.0, b: 246.0)
    static let foam = (r: 236.0, g: 248.0, b: 252.0)
    static let surfaceLine = (r: 120.0, g: 196.0, b: 236.0)
    static let weedBody = (r: 70.0, g: 150.0, b: 70.0)
    static let weedLight = (r: 110.0, g: 186.0, b: 96.0)
    static let weedEdge = (r: 22.0, g: 52.0, b: 26.0)

    /// The size of the pictures in water pixels, and where they sit in global points (their frame).
    static func layout(_ w: WaterSnapshot) -> (width: Int, height: Int, frame: CGRect) {
        let s = max(1, w.scale)
        let width = Int((w.pool.width / s).rounded(.up))
        let deep = max(0, Int(((w.surface - w.pool.minY) / s).rounded()))
        let height = deep + headroom
        return (width, height, CGRect(x: w.pool.minX, y: w.pool.minY, width: CGFloat(width) * s, height: CGFloat(height) * s))
    }

    /// The surface's wave at column `x`, in pixels up (+) or down (-).
    static func wave(_ x: Int, _ t: Double) -> Int {
        Int((sin(Double(x) * 0.21 + t * 2.1) * 0.9 + sin(Double(x) * 0.07 - t * 1.3) * 0.8).rounded())
    }

    static func back(_ w: WaterSnapshot) -> CGImage? {
        let (width, height, _) = layout(w)
        guard width > 0, height > headroom else { return nil }
        let deepRows = height - headroom
        var px = [UInt32](repeating: 0, count: width * height)
        let a = w.opacity * 0.8, t = w.time
        func put(_ x: Int, _ y: Int, _ c: (r: Double, g: Double, b: Double), _ alpha: Double) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            // Premultiplied RGBA, row 0 at the TOP of the picture.
            let al = min(1, max(0, alpha))
            let r = UInt32(c.r * al), g = UInt32(c.g * al), b = UInt32(c.b * al), aa = UInt32(255 * al)
            px[(height - 1 - y) * width + x] = r | g << 8 | b << 16 | aa << 24
        }
        let deepBand = max(2, deepRows / 4)
        for y in 0..<deepRows {
            let fromTop = deepRows - 1 - y
            for x in 0..<width {
                // Under the wave's trough only: above it is air.
                if fromTop + wave(x, t) < 0 { continue }
                var colour = y < deepBand ? deep : water
                var alpha = a
                // Light rays: slanting bands from the surface, fading out in steps on the way down.
                let band = (Double(x) + Double(fromTop) * 0.45 + t * 2.5).truncatingRemainder(dividingBy: 46)
                if band < 5, fromTop < deepRows * 3 / 4 {
                    colour = ray
                    alpha = a * (fromTop < deepRows / 3 ? 1 : 0.8)
                }
                // Caustics: the moving net of light, bright on the floor and faint above.
                let c = sin(Double(x) * 0.42 + t * 1.3) + sin(Double(y) * 0.61 - t * 1.1 + Double(x) * 0.17)
                    + sin(Double(x + y) * 0.23 + t * 0.8)
                if y < 6 ? c > 1.9 : (y < deepRows / 2 && c > 2.55) {
                    colour = caustic
                    alpha = a * 1.25
                }
                put(x, y, colour, alpha)
            }
        }
        // Seaweed swaying on the floor: a two-pixel strand, outlined, bending more towards its tip.
        for weed in w.weeds {
            let base = Int(((weed.x - w.pool.minX) / max(1, w.scale)).rounded())
            let tall = min(weed.height, max(0, deepRows - 3))
            var last = base
            for j in 0..<tall {
                let lean = sin(weed.phase + t * 1.2 + Double(j) * 0.22) * Double(j) / Double(max(1, tall)) * 3.2
                let x = base + Int(lean.rounded())
                put(x - 1, j, weedEdge, 1); put(x + 2, j, weedEdge, 1)
                put(x, j, weedLight, 1); put(x + 1, j, weedBody, 1)
                if x != last { put(min(x, last) + 1, j, x > last ? weedLight : weedBody, 1) }
                last = x
            }
            put(last, tall, weedEdge, 1); put(last + 1, tall, weedEdge, 1)
        }
        guard let image = makeImage(&px, width, height) else { return nil }
        return draw(on: image, w, sprites: w.critters, coralEvery: 3)
    }

    static func front(_ w: WaterSnapshot) -> CGImage? {
        let (width, height, _) = layout(w)
        guard width > 0, height > headroom else { return nil }
        let deepRows = height - headroom
        var px = [UInt32](repeating: 0, count: width * height)
        let t = w.time
        func put(_ x: Int, _ y: Int, _ c: (r: Double, g: Double, b: Double), _ alpha: Double) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let al = min(1, max(0, alpha))
            px[(height - 1 - y) * width + x] = UInt32(c.r * al) | UInt32(c.g * al) << 8 | UInt32(c.b * al) << 16 | UInt32(255 * al) << 24
        }
        let tint = w.opacity * 0.28
        for x in 0..<width {
            let top = deepRows - 1 + wave(x, t)
            for y in 0..<max(0, top) { put(x, y, water, tint) }
            // The surface: a foam line on the crest, a light line under it.
            put(x, top, foam, 0.9)
            put(x, top - 1, surfaceLine, 0.75)
            // Foam flecks riding the crests.
            if (x + Int(t * 6)) % 17 == 0 { put(x, top + 1, foam, 0.8) }
        }
        guard let image = makeImage(&px, width, height) else { return nil }
        return draw(on: image, w, sprites: w.bubbles, coralEvery: 0)
    }

    private static func makeImage(_ px: inout [UInt32], _ width: Int, _ height: Int) -> CGImage? {
        let data = px.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// `sprites` (one sheet pixel to one water pixel) over `image`, and a coral clump at every `coralEvery`-th weed.
    private static func draw(on image: CGImage, _ w: WaterSnapshot, sprites: [WaterSnapshot.Sprite], coralEvery: Int) -> CGImage? {
        guard !sprites.isEmpty || coralEvery > 0,
              let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let s = max(1, w.scale), cw = w.cell.width, ch = w.cell.height
        if coralEvery > 0, let coral = w.coral {
            for (k, weed) in w.weeds.enumerated() where k % coralEvery == 1 {
                let x = ((weed.x - w.pool.minX) / s).rounded() + 14
                ctx.draw(coral, in: CGRect(x: x - cw / 2, y: -ch / 2 + 4, width: cw, height: ch))
            }
        }
        for sprite in sprites {
            guard let picture = sprite.image else { continue }
            let x = ((sprite.centre.x - w.pool.minX) / s).rounded(), y = ((sprite.centre.y - w.pool.minY) / s).rounded()
            ctx.saveGState()
            ctx.translateBy(x: x, y: y)
            if sprite.mirrored { ctx.scaleBy(x: -1, y: 1) }
            ctx.draw(picture, in: CGRect(x: -cw / 2, y: -ch / 2, width: cw, height: ch))
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }
}

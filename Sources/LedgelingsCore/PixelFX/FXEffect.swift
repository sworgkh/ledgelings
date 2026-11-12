// What an effect is, a live instance of one, the creature it is drawn around, and the 1-bit picture
// the overlay shows: pixelfx's `createFx`, `resolveOptions` and `composite`
// (https://github.com/patch-gg/pixelfx, MIT), with one change of ours. pixelfx composites light and
// translucent smoke over a backdrop; our creatures stand on the user's desktop, so what would be partly
// transparent is dithered to whole pixels instead (`FXComposite`), and nothing is ever half drawn.

import Foundation

/// An effect's fixed facts: its frame, where its origin sits in it, how long it plays.
public struct FXMeta: Sendable {
    public let id: String
    public let size: (w: Int, h: Int)
    public let origin: (x: Int, y: Int)
    public let duration: Double
    public let loop: Bool
    public let palette: [String]
    public let seed: Double
    public init(id: String, size: (Int, Int), origin: (Int, Int), duration: Double, loop: Bool, palette: [String], seed: Double) {
        self.id = id; self.size = size; self.origin = origin; self.duration = duration; self.loop = loop
        self.palette = palette; self.seed = seed
    }
}

/// The creature an effect is drawn around, in local space with its feet at (0, 0): its mask and own colours
/// (row by row, 0 where empty), the top-left of the mask, the top of its head and its chest.
public struct FXActor: Sendable {
    public let mask: FXMask
    public let pixels: [FXColor]
    public let x: Int, y: Int, w: Int, h: Int
    public let k: Int
    public let head: (Double, Double)
    public let chest: (Double, Double)
    /// Where its eyes are, when the body says so; nil to find them (`FXStatus.eyes`).
    public let eyes: [(Int, Int)]?
    /// A number unique to this mask, so what is worked out once per shape can be kept.
    public let key: Int

    /// From w × h colours (0 = empty): its feet at the middle of its bottom row, as pixelfx's runner placed ours.
    public init(w: Int, h: Int, pixels: [FXColor], eyes: [(Int, Int)]? = nil) {
        self.w = w; self.h = h; self.pixels = pixels
        mask = FXMask(w: w, h: h, data: pixels.map { $0 != 0 ? 1 : 0 })
        x = -(w / 2); y = -h; k = 2
        head = (0, Double(y))
        chest = (0, Double(y) + FX.round(Double(h) * 0.45))
        self.eyes = eyes
        var hasher = Hasher()
        hasher.combine(w); hasher.combine(h); hasher.combine(pixels)
        key = hasher.finalize()
    }

    /// From RGBA bytes (any alpha of 128 or more is a pixel), cut to the box that holds the body.
    public init?(rgba: [UInt8], width: Int, height: Int, box: (x: Int, y: Int, w: Int, h: Int)) {
        guard box.w > 0, box.h > 0 else { return nil }
        var px = [FXColor](repeating: 0, count: box.w * box.h)
        for yy in 0..<box.h {
            for xx in 0..<box.w {
                let sx = box.x + xx, sy = box.y + yy
                guard sx >= 0, sy >= 0, sx < width, sy < height else { continue }
                let i = (sy * width + sx) * 4
                if rgba[i + 3] > 128 { px[yy * box.w + xx] = FX.rgb(Double(rgba[i]), Double(rgba[i + 1]), Double(rgba[i + 2])) }
            }
        }
        self.init(w: box.w, h: box.h, pixels: px)
    }

    /// The box round every pixel of an RGBA picture, nil when it is empty.
    public static func box(rgba: [UInt8], width: Int, height: Int) -> (x: Int, y: Int, w: Int, h: Int)? {
        var x0 = width, y0 = height, x1 = -1, y1 = -1
        for y in 0..<height { for x in 0..<width where rgba[(y * width + x) * 4 + 3] > 128 {
            x0 = Swift.min(x0, x); x1 = Swift.max(x1, x); y0 = Swift.min(y0, y); y1 = Swift.max(y1, y)
        } }
        return x1 < 0 ? nil : (x0, y0, x1 - x0 + 1, y1 - y0 + 1)
    }
}

/// What an effect is given: where its origin is, which way it faces, its seed and palette, the creature.
public struct FXOptions {
    public var x = 0.0, y = 0.0
    public var flip = false
    public var seed: Double
    public var palette: [FXColor]
    /// How strong its light is.
    public var light = 1.0
    public var actor: FXActor
    public init(meta: FXMeta, actor: FXActor, seed: Double? = nil, palette: [String]? = nil) {
        self.seed = seed ?? meta.seed
        let own = FX.ramp(meta.palette)
        if let palette { self.palette = palette.count == own.count ? FX.ramp(palette) : FX.fit(FX.ramp(palette), own.count) }
        else { self.palette = own }
        self.actor = actor
    }
}

/// One effect's drawing code. A stateless effect draws from t alone; one that keeps state steps in `update`.
public protocol FXEffect: AnyObject {
    static var meta: FXMeta { get }
    init(_ o: FXOptions)
    /// One step of its simulation (called at 120 Hz or finer).
    func update(_ dt: Double)
    /// What goes behind the creature.
    func drawBack(_ p: Painter, _ t: Double)
    /// What goes in front of it.
    func draw(_ p: Painter, _ t: Double)
    /// How visible the creature itself should be at t: 0 while the effect draws the body itself or it has gone.
    func actorAlpha(_ t: Double) -> Double
}

extension FXEffect {
    public func update(_ dt: Double) {}
    public func drawBack(_ p: Painter, _ t: Double) {}
    public func actorAlpha(_ t: Double) -> Double { 1 }
}

/// An effect drawn over a backdrop of its own (the weather's sky haze), which it can leave out over the desktop.
public protocol FXBackdropped: AnyObject {
    var backdrop: Bool { get set }
}

/// A live effect: `createFx`'s clock, its stop-and-fade, and its draw.
public final class FXInstance {
    static let fadeTime = 0.3
    public let meta: FXMeta
    public let options: FXOptions
    let impl: FXEffect
    public private(set) var t = 0.0
    var stopAt = Double.infinity

    public init(_ type: FXEffect.Type, options: FXOptions) {
        meta = type.meta
        self.options = options
        impl = type.init(options)
    }

    public func update(_ dt: Double) {
        t += dt
        // simulations step at 120 Hz or finer whatever the caller's frame rate, so they look the same everywhere
        let n = Swift.max(1, Int(FX.ceil(dt * 120 - 1e-9)))
        for _ in 0..<n { impl.update(dt / Double(n)) }
    }

    /// Its time within the effect: wrapped for a loop, held at the end for a one-shot.
    public var localTime: Double { meta.loop ? FX.mod(t, meta.duration) : Swift.min(t, meta.duration) }

    /// nil draws both layers.
    public func draw(_ frame: FXFrame, _ layer: FXLayer?) {
        let p = frame.painter.reset()
        p.place(options.x, options.y, options.flip, 0)
        p.fade = stopAt == .infinity ? 1 : FX.clamp(1 - (t - stopAt) / Self.fadeTime)
        p.lightK = options.light
        let tt = localTime
        if layer != .front { p.layer = .back; impl.drawBack(p, tt) }
        if layer != .back { p.layer = .front; impl.draw(p, tt) }
    }

    public var actorAlpha: Double { impl.actorAlpha(localTime) }

    /// Leave out the effect's own backdrop, if it has one.
    public func dropBackdrop() { (impl as? FXBackdropped)?.backdrop = false }

    /// Let it end: loops fade out, one-shots are cut short.
    public func stop() { if stopAt == .infinity { stopAt = t } }
    public var stopping: Bool { stopAt != .infinity }
    public var done: Bool { t - stopAt >= Self.fadeTime || (!meta.loop && t >= meta.duration) }

    /// The whole picture at this moment: the back layer, the creature, the front layer, into `frame`
    /// (sized `meta.size`, cleared first). Returns whether the creature was drawn.
    @discardableResult public func render(into frame: FXFrame, drawActor: Bool = true) -> Bool {
        frame.clear()
        draw(frame, .back)
        let show = actorAlpha > 0.5
        if show && drawActor {
            let a = options.actor
            let OX = Int(options.x), OY = Int(options.y)
            for yy in 0..<a.h {
                for xx in 0..<a.w {
                    let c = a.pixels[yy * a.w + xx]
                    if c == 0 { continue }
                    let X = OX + a.x + xx, Y = OY + a.y + yy
                    if X >= 0 && Y >= 0 && X < frame.w && Y < frame.h { frame.color[Y * frame.w + X] = c }
                }
            }
        }
        draw(frame, .front)
        return show
    }
}

/// The frame's own painter, made once.
extension FXFrame {
    public var painter: Painter {
        if let p = ownPainter { return p }
        let p = Painter(self)
        ownPainter = p
        return p
    }
}

/// Colour and light turned into the RGBA bytes the overlay shows, every pixel fully there or fully not.
public enum FXComposite {
    /// pixelfx's composite over nothing, then: a pixel less than fully opaque is kept, whole, where its alpha
    /// beats the ordered-dither threshold of its cell, and only if it is at least `floor` opaque.
    public static func rgba(_ f: FXFrame, lightK: Double = 1, floor: Double = 0.25) -> [UInt8] {
        let n = f.w * f.h
        var out = [UInt8](repeating: 0, count: n * 4)
        for i in 0..<n {
            let c = f.color[i], l = f.light[i] & 0xffffff
            var r = Double(c & 255), g = Double((c >> 8) & 255), b = Double((c >> 16) & 255), a = Double(c >> 24)
            if l != 0 {
                let lr = Double(l & 255) * lightK, lg = Double((l >> 8) & 255) * lightK, lb = Double((l >> 16) & 255) * lightK
                if a < 255 {
                    let pa = a / 255, pr = r * pa + lr, pg = g * pa + lg, pb = b * pa + lb
                    let na = Swift.min(1, Swift.max(pa, Swift.max(lr, lg, lb) / 255))
                    if na > 0 { r = Swift.min(255, pr / na); g = Swift.min(255, pg / na); b = Swift.min(255, pb / na); a = na * 255 }
                } else {
                    r = Swift.min(255, r + lr); g = Swift.min(255, g + lg); b = Swift.min(255, b + lb)
                }
            }
            if a < 255 {
                let x = i % f.w, y = i / f.w, alpha = a / 255
                if alpha < floor || alpha <= Painter.bayer[((y & 3) << 2) | (x & 3)] { continue }
            }
            let j = i * 4
            out[j] = UInt8(r); out[j + 1] = UInt8(g); out[j + 2] = UInt8(b); out[j + 3] = 255
        }
        return out
    }
}

import CoreGraphics
import LedgelingsCore

/// One effect on show, drawn as two pixel pictures: what goes behind the creature's sprite, and what goes
/// in front of it. The creature itself stays the overlay's own sprite, walking as ever; the front picture
/// only carries the pixels the effect changed over it (a film of frost, a glow), so between the two the
/// screen shows exactly what pixelfx composites: back, creature, front (SPEC §7.19).
@MainActor
final class EffectPlayer {
    let instance: FXInstance
    /// The pixelfx effect, the style or moment it plays for.
    let name: String
    let style: Effects.Style?
    let moment: Effects.Moment?
    private let back: FXFrame
    private let front: FXFrame
    /// Where the creature's box sits in its sprite cell, so the pictures line up with the sprite.
    let box: (x: Int, y: Int, w: Int, h: Int)
    /// Wears off at this time on the colony's clock (a style), or nil: when it is done, or let go of.
    var until: Double?
    /// Played by hand (a preview, the film): it runs its time whatever the moment's state says.
    var byHand = false
    /// The creature stays hidden until this many seconds in: inside the egg until it hatches.
    var hiddenUntil: Double?

    init(_ type: FXEffect.Type, name: String, actor: FXActor, box: (x: Int, y: Int, w: Int, h: Int), seed: Double,
         style: Effects.Style? = nil, moment: Effects.Moment? = nil) {
        var o = FXOptions(meta: type.meta, actor: actor, seed: seed)
        o.x = Double(type.meta.origin.x)
        o.y = Double(type.meta.origin.y)
        instance = FXInstance(type, options: o)
        self.name = name
        self.style = style
        self.moment = moment
        self.box = box
        back = FXFrame(type.meta.size.w, type.meta.size.h)
        front = FXFrame(type.meta.size.w, type.meta.size.h)
    }

    var size: CGSize { CGSize(width: back.w, height: back.h) }
    var done: Bool { instance.done }

    /// The frame's top-left corner in the sprite cell's pixels (y down), where the pictures are drawn.
    var cellOrigin: CGPoint {
        let a = instance.options.actor, m = instance.meta
        return CGPoint(x: box.x + a.w / 2 - m.origin.x, y: box.y + a.h - m.origin.y)
    }

    /// Both pictures for now. `actor` is the creature as its sprite shows it this frame (the same box):
    /// it is drawn between the layers so the front's blends and light land on it, then left out of the
    /// front picture wherever the front did not change it.
    func pictures(actor: [FXColor]?) -> (back: CGImage?, front: CGImage?, hidesBody: Bool) {
        let shown = instance.actorAlpha > 0.5 && instance.t >= (hiddenUntil ?? 0)
        back.clear()
        instance.draw(back, .back)

        // The front draws over what the back left, with one light for both, as pixelfx's single frame does.
        front.color = back.color
        front.light = back.light
        let a = instance.options.actor, ox = Int(instance.options.x) + a.x, oy = Int(instance.options.y) + a.y
        if shown, let body = actor ?? Optional(a.pixels), body.count == a.w * a.h { stamp(body, a.w, a.h, ox, oy, into: front) }
        let before = front.color
        instance.draw(front, .front)
        var rgba = FXComposite.rgba(front)
        // Unchanged and unlit, a pixel is not the front's: the back picture or the sprite shows it.
        for i in 0..<(front.w * front.h) where front.color[i] == before[i] && front.light[i] == 0 { rgba[i * 4 + 3] = 0 }

        // The back's light is drawn with the front, over the sprite too.
        for i in back.light.indices { back.light[i] = 0 }
        return (Self.image(FXComposite.rgba(back), back.w, back.h), Self.image(rgba, front.w, front.h), !shown)
    }

    /// Everything in one picture, the creature as it stands included: for a picture of the effect.
    func still() -> CGImage? {
        instance.render(into: back)
        return Self.image(FXComposite.rgba(back), back.w, back.h)
    }

    /// Everything in one picture, no creature: the ambient particles.
    func whole() -> CGImage? {
        instance.render(into: back, drawActor: false)
        return Self.image(FXComposite.rgba(back), back.w, back.h)
    }

    private func stamp(_ px: [FXColor], _ w: Int, _ h: Int, _ ox: Int, _ oy: Int, into f: FXFrame) {
        for yy in 0..<h {
            for xx in 0..<w {
                let c = px[yy * w + xx]
                if c == 0 { continue }
                let X = ox + xx, Y = oy + yy
                if X >= 0 && Y >= 0 && X < f.w && Y < f.h { f.color[Y * f.w + X] = c }
            }
        }
    }

    // MARK: Pictures

    /// RGBA bytes as a picture, nil when nothing is drawn.
    static func image(_ rgba: [UInt8], _ w: Int, _ h: Int) -> CGImage? {
        guard rgba.contains(where: { $0 != 0 }) else { return nil }
        let data = Data(rgba) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// A picture's straight RGBA bytes.
    static func rgba(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let data = ctx.data else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        // Pixel art has 1-bit alpha: an opaque pixel is its own colour, premultiplied or not.
        return (0..<(w * h * 4)).map { i in px[i] }
    }
}

import Foundation

/// The creatures as the effects see them: each sprite frame's pixels, worked out once per picture.
@MainActor
final class EffectActors {
    private var bodies: [ObjectIdentifier: (image: CGImage, pixels: [FXColor])] = [:]
    private var actors: [ObjectIdentifier: (image: CGImage, actor: FXActor, box: (x: Int, y: Int, w: Int, h: Int))] = [:]

    /// The creature to shape an effect round, from its standing picture: its box in the cell, and its colours.
    func actor(standing image: CGImage) -> (actor: FXActor, box: (x: Int, y: Int, w: Int, h: Int))? {
        let id = ObjectIdentifier(image)
        if let made = actors[id] { return (made.actor, made.box) }
        let rgba = EffectPlayer.rgba(of: image)
        guard let box = FXActor.box(rgba: rgba, width: image.width, height: image.height),
              let actor = FXActor(rgba: rgba, width: image.width, height: image.height, box: box) else { return nil }
        if actors.count > 256 { actors.removeAll() }
        actors[id] = (image, actor, box)
        return (actor, box)
    }

    /// The pixels of one sprite frame inside `box`, as the effect draws the creature between its layers.
    func pixels(of image: CGImage, box: (x: Int, y: Int, w: Int, h: Int)) -> [FXColor] {
        let id = ObjectIdentifier(image)
        if let made = bodies[id], made.pixels.count == box.w * box.h { return made.pixels }
        let rgba = EffectPlayer.rgba(of: image)
        let px = FXActor(rgba: rgba, width: image.width, height: image.height, box: box)?.pixels ?? []
        if bodies.count > 1024 { bodies.removeAll() }
        bodies[id] = (image, px)
        return px
    }
}

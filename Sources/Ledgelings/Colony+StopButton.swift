import AppKit
import LedgelingsCore

/// The Stop button, drawn on the overlay while an activity runs (`Activities`):
/// in the top-right corner of the monitor the activity is on, below the menu
/// bar and clear of a score board. The only part of the overlay a click lands
/// on outside the creatures; the click stops the activity. Hovering it shows its
/// tag under it, drawn here: the system's tooltips open under the overlay.
extension Colony {
    /// Screen points per pixel of the button, as the score board's letters.
    static let stopButtonScale: CGFloat = 2

    /// The shortcut in words, or nil while it is off.
    var stopShortcutSpoken: String? {
        settings.stopActivityShortcutEnabled ? GlobalShortcut.spoken(settings.stopActivityShortcut) : nil
    }

    /// The button as it stands now: where (global points), on which overlay, and whether the
    /// pointer is on it. Nil while nothing runs or the button is switched off.
    func stopButton() -> StopButtonSnapshot? {
        guard settings.stopButtonShown, Activities.shared.isRunning, !overlays.isEmpty else { return nil }
        let label = StopButton.label(spokenShortcut: stopShortcutSpoken)
        if stopButtonImages?.label != label {
            stopButtonImages = (label, StopButtonPainter.button(label, hovered: false), StopButtonPainter.button(label, hovered: true),
                                StopButtonPainter.tag(StopButton.tag(spokenShortcut: stopShortcutSpoken)))
        }
        guard let images = stopButtonImages, let plain = images.plain else { return nil }
        let k = activityOverlay()
        let display = overlays[k].display
        let scale = Self.stopButtonScale
        let size = CGSize(width: CGFloat(plain.width) * scale, height: CGFloat(plain.height) * scale)
        let boards = playProps().compactMap { prop -> CGRect? in
            guard let s = prop.size else { return nil }
            let w = s.width * prop.scale, h = s.height * prop.scale
            return CGRect(x: prop.position.x - w / 2, y: prop.position.y - h / 2, width: w, height: h)
        }
        let frame = StopButton.frame(size: size, on: display.frame, topInset: display.topInset, avoiding: boards)
        let hovered = stopButtonHovered
        var tag: (image: CGImage, frame: CGRect)?
        if hovered, let t = images.tag {
            let w = CGFloat(t.width) * scale, h = CGFloat(t.height) * scale
            tag = (t, CGRect(x: frame.maxX - w, y: frame.minY - 6 - h, width: w, height: h))
        }
        return StopButtonSnapshot(overlay: k, image: hovered ? images.hovered : plain, frame: frame, tag: tag)
    }

    /// The overlay of the monitor the activity is on: the players' for a game or a surf,
    /// the water's for a dive (its first pool, when it covers every monitor), else the first.
    func activityOverlay() -> Int {
        var at: CGPoint?
        if let play, let first = play.players.first, creatures.indices.contains(first) { at = creatures[first].position }
        else if let pool = dive?.model.pools.first { at = CGPoint(x: pool.midX, y: pool.midY) }
        guard let at else { return 0 }
        return overlays.firstIndex { $0.display.frame.contains(at) } ?? 0
    }

    /// Whether `point` (global) is on the Stop button.
    func onStopButton(_ point: CGPoint) -> Bool { stopButton()?.frame.contains(point) == true }

    /// A click on the Stop button: whatever runs stops, as the shortcut does.
    func pressStopButton() {
        let stopped = Activities.shared.stopAll(why: "the Stop button")
        trace?("stop button pressed: \(stopped.isEmpty ? "nothing running" : stopped.map(\.rawValue).joined(separator: ", "))")
        stopButtonHovered = false
    }
}

/// The button for one frame, in global points.
struct StopButtonSnapshot {
    var overlay: Int
    var image: CGImage?
    var frame: CGRect
    var tag: (image: CGImage, frame: CGRect)?
}

/// The Stop button and its tag drawn in pixels, in the game's style: a flat plate,
/// a 1-pixel dark outline, a light line along the top and left, a shade line along
/// the bottom and right; the stop sign beside the words.
enum StopButtonPainter {
    typealias RGB = (UInt8, UInt8, UInt8)
    /// The plate: the score board's dark blue, a step lighter under the pointer.
    static let plate: RGB = (46, 50, 74)
    static let plateHovered: RGB = (72, 78, 112)
    static let ink: RGB = (250, 240, 214)
    static let signColours: [Swift.Character: RGB] = [
        "o": (70, 16, 20), "l": (238, 110, 100), "r": (204, 46, 40), "s": (150, 30, 28), "w": (255, 250, 240),
    ]

    static func button(_ label: String, hovered: Bool) -> CGImage? {
        guard let words = PixelText.image(label, PixelText.Style(ink: ink, plate: nil, size: 9)) else { return nil }
        let sign = StopButton.icon, signW = sign.map(\.count).max() ?? 0, signH = sign.count
        let pad = 4, gap = 4
        let w = pad + signW + gap + words.width + pad, h = max(signH, words.height) + pad * 2
        return paint(width: w, height: h, plate: hovered ? plateHovered : plate) { ctx in
            for (row, line) in sign.enumerated() {
                for (x, c) in line.enumerated() {
                    guard let colour = signColours[c] else { continue }
                    fill(ctx, x: pad + x, y: (h - signH) / 2 + row, h: h, colour)
                }
            }
            ctx.draw(words, in: CGRect(x: pad + signW + gap, y: (h - words.height) / 2, width: words.width, height: words.height))
        }
    }

    static func tag(_ text: String) -> CGImage? {
        PixelText.image(text, PixelText.Style(ink: ink, plate: plate, size: 9))
    }

    /// A plate `width` × `height` pixels, with `draw` on it; y counts down from the top in `fill`.
    private static func paint(width w: Int, height h: Int, plate: RGB, _ draw: (CGContext) -> Void) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        func mix(_ c: RGB, _ to: Double, _ share: Double) -> RGB {
            func m(_ v: UInt8) -> UInt8 { UInt8(Double(v) + (to - Double(v)) * share) }
            return (m(c.0), m(c.1), m(c.2))
        }
        for y in 0..<h { for x in 0..<w {
            let edge = x == 0 || y == 0 || x == w - 1 || y == h - 1
            let colour = edge ? mix(plate, 0, 0.6) : (x == 1 || y == 1) ? mix(plate, 255, 0.25)
                : (x == w - 2 || y == h - 2) ? mix(plate, 0, 0.25) : plate
            fill(ctx, x: x, y: y, h: h, colour)
        } }
        draw(ctx)
        return ctx.makeImage()
    }

    private static func fill(_ ctx: CGContext, x: Int, y: Int, h: Int, _ c: RGB) {
        ctx.setFillColor(CGColor(srgbRed: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: 1))
        ctx.fill(CGRect(x: x, y: h - 1 - y, width: 1, height: 1))
    }
}

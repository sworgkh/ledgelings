import AppKit
import LedgelingsCore
import QuartzCore

/// Everything needed to draw one creature for one frame, in GLOBAL coordinates.
struct CreatureSnapshot {
    var position: CGPoint
    var rotation: Double
    var isMirrored: Bool
    var image: CGImage?
    /// Screen points per sprite pixel, for this creature.
    var scale: CGFloat
    /// Seconds asleep, or nil when awake. Drives the floating Zs.
    var asleepFor: Double?
    /// Which way is "up" for this creature: away from its edge, into the screen.
    var inward: CGVector = CGVector(dx: 0, dy: 1)
    /// What it is saying right now, if anything.
    var bubble: String?
    /// How much of `bubble` is on show, 0...1: less while it is being said out loud.
    var bubbleShare: Double = 1
    /// The flower on its head, if it was given one.
    var hat: CGImage?
    /// Inside the house: draw nothing at all.
    var hidden = false
    /// 1 = full size; falls to 0 as it disappears into the doorway, rises from 0 as it comes out.
    var shrink: CGFloat = 1
    /// The paper plane's note, unfolded and held out in front while it is read.
    var letter: CGImage?
}

/// The paper plane and its dotted trail, in GLOBAL coordinates.
struct PlaneSnapshot {
    var image: CGImage?
    var position: CGPoint
    /// Where the nose points, radians. The sprite points right; heading left, it is flipped upright.
    var heading: Double
    var scale: CGFloat
    /// 0 once caught (only the trail is left), fading after a miss.
    var opacity: Float
    var trail: [(position: CGPoint, opacity: Float)]
    var puffSize: CGFloat
}

/// A reminder on its way: its plane (or nothing, once it has opened), and the letter.
struct ReminderSnapshot {
    var plane: PlaneSnapshot?
    var letter: LetterSnapshot?
}

/// The reminder's letter, open in the middle of the screen.
struct LetterSnapshot {
    /// Which delivery this is: a new one lays the letter out afresh.
    var id: Int
    var centre: CGPoint
    /// 1 = full size; less while it spreads out or folds away.
    var grow: CGFloat
    var opacity: Float
    var title: String
    /// The reminder itself, in the user's words.
    var text: String
    /// The thrower's note, in its own voice.
    var note: String
    var signature: String
    /// The thrower's face, beside its signature.
    var stamp: CGImage?
    var hint: String
}

/// The house, at whatever size it currently is, pinned by its bottom-right corner.
/// Drawn behind the creatures; at the doorway they shrink to nothing on top of it.
struct HouseSnapshot {
    var image: CGImage?
    var corner: CGPoint
    /// Screen points per sheet pixel, already multiplied by the grow/shrink factor.
    var scale: CGFloat
}

/// A flower on its way from one creature to another, in GLOBAL coordinates.
struct FlowerFlight {
    var image: CGImage?
    var position: CGPoint
    var rotation: Double
    var scale: CGFloat
}

/// One pixel star from a bump, already coloured and faded.
struct SparkSnapshot {
    var position: CGPoint
    var size: CGFloat
    var color: CGColor
    var opacity: Float
}

/// One monitor's glass, and a set of layers for EVERY creature -- not only the
/// ones on this monitor. A window cannot span two displays, so a creature
/// crossing a seam is drawn by both overlays, each clipping its own half.
@MainActor
final class ScreenOverlay {
    private static let zCount = 3
    private static let zCycle = 2.6        // seconds for one Z to rise and fade

    /// The monitor this overlay covers: a real one, or a stage the promo renders to.
    let display: Display
    /// The layer everything is drawn into: the window's view layer when hosted,
    /// a bare layer when rendering offscreen.
    let root: CALayer
    let view: OverlayView?
    private let window: OverlayWindow?
    private var creatures: [(body: CALayer, sprite: CALayer, zs: [CALayer], hat: CALayer, letter: CALayer)] = []
    /// The creatures' paper plane, and a reminder's: both can be in the air at once.
    private lazy var mailPlane = PlaneSprite(root: root, z: 4, layer: makeLayers().sprite)
    private lazy var reminderPlane = PlaneSprite(root: root, z: 6, layer: makeLayers().sprite)
    private var letter: (key: String, layer: CALayer)?
    /// The open letter's frame in global points, while this screen shows it.
    private(set) var letterFrame: CGRect?
    private lazy var flight: CALayer = {
        let layer = makeLayers().sprite
        layer.isHidden = true
        root.addSublayer(layer)
        return layer
    }()
    private var bubbles: [Int: (plate: CALayer, text: CATextLayer, for: String, shown: Int)] = [:]
    private var sparkLayers: [CALayer] = []
    private lazy var house: CALayer = {
        let layer = makeLayers().sprite
        layer.isHidden = true
        layer.zPosition = -1                       // behind the creatures
        layer.anchorPoint = CGPoint(x: 1, y: 0)    // grows and shrinks about its bottom-right corner
        root.addSublayer(layer)
        return layer
    }()
    private static let bubbleFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)

    /// The bubble's face for a run: heavier for bold, slanted for italic. SF Mono has
    /// true italics; a font without one is skewed instead.
    static func bubbleFace(bold: Bool, italic: Bool) -> NSFont {
        var font = NSFont.monospacedSystemFont(ofSize: 12, weight: bold ? .heavy : .semibold)
        guard italic else { return font }
        if let slanted = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.italic), size: 12),
           slanted.fontDescriptor.symbolicTraits.contains(.italic) {
            font = slanted
        } else if let skewed = NSFont(descriptor: font.fontDescriptor,
                                      textTransform: AffineTransform(m11: 1, m12: 0, m21: 0.22, m22: 1, tX: 0, tY: 0)) {
            font = skewed
        }
        return font
    }

    /// The line as the bubble shows it: the model's *marks* become italic and bold
    /// runs instead of asterisks.
    static func bubbleText(_ text: String) -> NSAttributedString {
        let whole = NSMutableAttributedString()
        for run in Banter.styled(text) {
            whole.append(NSAttributedString(string: run.text, attributes: [
                .font: bubbleFace(bold: run.bold, italic: run.italic), .foregroundColor: NSColor.white,
            ]))
        }
        return whole
    }
    private static let bubbleMaxWidth: CGFloat = 250
    private static let bubblePad: CGFloat = 8

    convenience init(screen: NSScreen) { self.init(display: Display(screen: screen), hosted: true) }

    /// `hosted`: put a click-through panel over the display. Otherwise the layers
    /// live on their own and someone else renders `root`, as the promo does.
    init(display: Display, hosted: Bool) {
        self.display = display
        if hosted {
            let window = OverlayWindow(frame: display.frame)
            let view = OverlayView(frame: CGRect(origin: .zero, size: display.frame.size))
            view.wantsLayer = true
            window.contentView = view
            window.orderFrontRegardless()
            self.window = window
            self.view = view
            root = view.layer!
        } else {
            window = nil
            view = nil
            let layer = CALayer()
            layer.bounds = CGRect(origin: .zero, size: display.frame.size)
            layer.anchorPoint = .zero
            layer.position = .zero
            root = layer
        }
    }

    func close() { window?.close() }

    /// Clickable only while there is something under the cursor worth clicking.
    func setClickable(_ clickable: Bool) {
        guard let window else { return }
        if window.ignoresMouseEvents == clickable { window.ignoresMouseEvents = !clickable }
    }

    /// The creature whose speech bubble is under `point`, if any.
    func bubbleIndex(at point: CGPoint) -> Int? {
        let origin = display.frame.origin
        return bubbles.first { $0.value.plate.frame.offsetBy(dx: origin.x, dy: origin.y).contains(point) }?.key
    }

    func render(_ snapshots: [CreatureSnapshot], z: CGImage?, cell: CGSize, zCell: CGSize,
                flowerCell: CGSize, flight inFlight: FlowerFlight? = nil, sparks: [SparkSnapshot] = [],
                house inHouse: HouseSnapshot? = nil, houseCell: CGSize = .zero,
                plane: PlaneSnapshot? = nil, planeCell: CGSize = .zero, reminder: ReminderSnapshot? = nil) {
        renderFlight(inFlight, flowerCell: flowerCell)
        mailPlane.render(plane, cell: planeCell, origin: display.frame.origin)
        reminderPlane.render(reminder?.plane, cell: planeCell, origin: display.frame.origin)
        renderLetter(reminder?.letter, cell: cell)
        renderSparks(sparks)
        renderHouse(inHouse, cell: houseCell)
        while creatures.count < snapshots.count { creatures.append(makeLayers()) }
        while creatures.count > snapshots.count {
            creatures.removeLast().body.removeFromSuperlayer()
            removeBubble(for: creatures.count)
        }

        let origin = display.frame.origin
        // A creature nowhere near this monitor costs it nothing: hidden layer, no
        // commit, so the window server has no reason to recomposite this screen.
        for (index, (layers, snap)) in zip(creatures, snapshots).enumerated() {
            let scale = snap.scale, bodyHeight = cell.height * scale
            let reach = max(cell.width, cell.height) * scale * 2.5
            let visible = display.frame.insetBy(dx: -reach, dy: -reach)
            let here = !snap.hidden && visible.contains(snap.position)
            if layers.body.isHidden == here { layers.body.isHidden = !here }
            guard here else { removeBubble(for: index); continue }
            let hatHeight = snap.hat == nil ? 0 : flowerCell.height * scale
            renderBubble(snap, index: index, bodyHalf: cell.width * scale / 2 + hatHeight)
            // The body layer carries position and the turn onto the edge; the
            // sprite inside it carries only the mirror, so the Zs never flip.
            layers.body.position = CGPoint(x: snap.position.x - origin.x, y: snap.position.y - origin.y)
            layers.body.transform = CATransform3DScale(CATransform3DMakeRotation(snap.rotation, 0, 0, 1), snap.shrink, snap.shrink, 1)
            layers.sprite.bounds = CGRect(x: 0, y: 0, width: cell.width * scale, height: bodyHeight)
            if (layers.sprite.contents as AnyObject?) !== snap.image { layers.sprite.contents = snap.image }
            layers.sprite.transform = CATransform3DMakeScale(snap.isMirrored ? -1 : 1, 1, 1)

            // The flower stands on the head: inside the body layer, so it turns
            // with the creature onto walls and the ceiling, but never mirrors.
            if let hat = snap.hat {
                layers.hat.isHidden = false
                layers.hat.contents = hat
                layers.hat.bounds = CGRect(x: 0, y: 0, width: flowerCell.width * scale, height: hatHeight)
                layers.hat.position = CGPoint(x: 0, y: bodyHeight / 2 + hatHeight / 2 - scale)
            } else if !layers.hat.isHidden {
                layers.hat.isHidden = true
            }

            // The open letter is held out in front, on the side it faces.
            if let letter = snap.letter {
                let size = CGSize(width: planeCell.width * scale, height: planeCell.height * scale)
                layers.letter.isHidden = false
                layers.letter.contents = letter
                layers.letter.bounds = CGRect(origin: .zero, size: size)
                layers.letter.position = CGPoint(x: (snap.isMirrored ? -1 : 1) * cell.width * scale * 0.42, y: -bodyHeight * 0.08)
            } else if !layers.letter.isHidden {
                layers.letter.isHidden = true
            }

            for (k, layer) in layers.zs.enumerated() {
                guard let asleep = snap.asleepFor else { if layer.opacity != 0 { layer.opacity = 0 }; continue }
                let clock = asleep / Self.zCycle - Double(k) / Double(Self.zCount)
                guard clock >= 0 else { if layer.opacity != 0 { layer.opacity = 0 }; continue }   // not launched yet
                let p = clock.truncatingRemainder(dividingBy: 1)
                let grow = 0.7 + 0.8 * p
                layer.contents = z
                layer.bounds = CGRect(x: 0, y: 0, width: zCell.width * scale, height: zCell.height * scale)
                layer.position = CGPoint(x: bodyHeight * (0.22 + 0.10 * sin(p * 2 * .pi) + 0.18 * p),
                                         y: bodyHeight * (0.30 + 0.75 * p))
                layer.opacity = Float(min(1, p * 5) * min(1, (1 - p) * 2.5))
                // Undo the body's turn so the letter stays upright on walls and ceilings.
                layer.transform = CATransform3DScale(CATransform3DMakeRotation(-snap.rotation, 0, 0, 1), grow, grow, 1)
            }
        }
    }

    /// Plain square layers, one per star; the pool grows to the biggest burst and stays.
    private func renderSparks(_ sparks: [SparkSnapshot]) {
        let origin = display.frame.origin
        while sparkLayers.count < sparks.count {
            let layer = CALayer()
            layer.actions = ["position": NSNull(), "bounds": NSNull(), "opacity": NSNull(), "hidden": NSNull(), "backgroundColor": NSNull()]
            layer.zPosition = 3
            root.addSublayer(layer)
            sparkLayers.append(layer)
        }
        for (layer, spark) in zip(sparkLayers, sparks) {
            layer.isHidden = false
            layer.bounds = CGRect(x: 0, y: 0, width: spark.size, height: spark.size)
            layer.position = CGPoint(x: spark.position.x - origin.x, y: spark.position.y - origin.y)
            layer.backgroundColor = spark.color
            layer.opacity = spark.opacity
        }
        for layer in sparkLayers.dropFirst(sparks.count) where !layer.isHidden { layer.isHidden = true }
    }

    // MARK: The reminder's letter

    /// Screen points per pixel of the letter's paper.
    private static let paperPixel: CGFloat = 3
    private static let letterPad: CGFloat = 30
    private static let letterTextWidth: CGFloat = 380
    static let ink = CGColor(srgbRed: 40 / 255, green: 34 / 255, blue: 58 / 255, alpha: 1)
    static let softInk = CGColor(srgbRed: 92 / 255, green: 86 / 255, blue: 120 / 255, alpha: 1)
    static let faintInk = CGColor(srgbRed: 150 / 255, green: 146 / 255, blue: 170 / 255, alpha: 1)

    /// Laid out once per letter, then only moved, grown and faded. Only the screen
    /// the letter opened on draws it.
    private func renderLetter(_ snap: LetterSnapshot?, cell: CGSize) {
        guard let snap, display.frame.contains(snap.centre) else {
            letter?.layer.removeFromSuperlayer(); letter = nil; letterFrame = nil
            return
        }
        let key = "\(snap.id)|\(snap.title)|\(snap.note)"
        if letter?.key != key {
            // Laid out in one go: no layer of it fades or slides in on its own.
            CATransaction.begin(); CATransaction.setDisableActions(true); defer { CATransaction.commit() }
            letter?.layer.removeFromSuperlayer()
            let made = makeLetter(snap, cell: cell)
            root.addSublayer(made)
            letter = (key, made)
        }
        guard let layer = letter?.layer else { return }
        let origin = display.frame.origin
        layer.position = CGPoint(x: (snap.centre.x - origin.x).rounded(), y: (snap.centre.y - origin.y).rounded())
        layer.transform = CATransform3DMakeScale(snap.grow, snap.grow, 1)
        layer.opacity = snap.opacity
        let size = layer.bounds.size
        letterFrame = CGRect(x: snap.centre.x - size.width / 2, y: snap.centre.y - size.height / 2, width: size.width, height: size.height)
    }

    private func textLayer(_ text: String, font: NSFont, color: CGColor, width: CGFloat, align: CATextLayerAlignmentMode = .left) -> CATextLayer {
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor(cgColor: color) ?? .black])
        let measured = attributed.boundingRect(with: CGSize(width: width, height: 2000), options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        let layer = CATextLayer()
        layer.actions = Self.noAnimations
        layer.string = attributed
        layer.isWrapped = true
        layer.alignmentMode = align
        layer.contentsScale = display.scale
        layer.bounds = CGRect(x: 0, y: 0, width: align == .left ? ceil(measured.width) + 2 : width, height: ceil(measured.height) + 2)
        return layer
    }

    /// The paper, in blocky's rules, sized to the words; the reminder big, the note
    /// under it, the signature and the thrower's face at the bottom.
    private func makeLetter(_ snap: LetterSnapshot, cell: CGSize) -> CALayer {
        let px = Self.paperPixel, pad = Self.letterPad, wide = Self.letterTextWidth
        let title = textLayer(snap.title, font: .monospacedSystemFont(ofSize: 11, weight: .bold), color: Self.faintInk, width: wide)
        let text = textLayer(snap.text, font: .monospacedSystemFont(ofSize: 24, weight: .heavy), color: Self.ink, width: wide)
        let note = textLayer(snap.note, font: .monospacedSystemFont(ofSize: 13, weight: .semibold), color: Self.softInk, width: wide)
        let signature = textLayer(snap.signature, font: .monospacedSystemFont(ofSize: 13, weight: .heavy), color: Self.ink, width: wide)
        let hint = textLayer(snap.hint, font: .monospacedSystemFont(ofSize: 10, weight: .semibold), color: Self.faintInk, width: wide)
        let stampSize = snap.stamp == nil ? CGSize.zero : CGSize(width: cell.width * 1.5, height: cell.height * 1.5)

        let inner = max(title.bounds.width, text.bounds.width, note.bounds.width, signature.bounds.width + stampSize.width + 8, 260)
        let width = ((inner + pad * 2) / px).rounded(.up) * px
        let footer = max(stampSize.height, signature.bounds.height)
        let body = title.bounds.height + 10 + text.bounds.height + 14 + note.bounds.height + 14 + footer + 4 + hint.bounds.height
        let height = ((body + pad * 2) / px).rounded(.up) * px

        let container = CALayer()
        container.actions = Self.noAnimations
        container.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        container.zPosition = 7                    // over everything, the reminder plane included
        let paper = CALayer()
        paper.actions = Self.noAnimations
        paper.magnificationFilter = .nearest
        paper.contents = Self.paperImage(width: Int(width / px), height: Int(height / px))
        paper.frame = container.bounds
        container.addSublayer(paper)

        // Top down, in a y-up layer.
        var y = height - pad
        func place(_ layer: CALayer, x: CGFloat? = nil, gap: CGFloat) {
            y -= layer.bounds.height
            layer.frame.origin = CGPoint(x: x ?? pad, y: y)
            container.addSublayer(layer)
            y -= gap
        }
        place(title, gap: 10)
        place(text, gap: 14)
        place(note, gap: 14)
        let footerTop = y
        if let image = snap.stamp {
            let stamp = CALayer()
            stamp.actions = Self.noAnimations
            stamp.magnificationFilter = .nearest
            stamp.contents = image
            stamp.frame = CGRect(x: width - pad - stampSize.width + 6, y: footerTop - stampSize.height, width: stampSize.width, height: stampSize.height)
            container.addSublayer(stamp)
        }
        let signatureRight = width - pad - (stampSize.width > 0 ? stampSize.width - 2 : 0)
        signature.frame.origin = CGPoint(x: signatureRight - signature.bounds.width, y: footerTop - footer / 2 - signature.bounds.height / 2)
        container.addSublayer(signature)
        y = footerTop - footer - 4
        place(hint, gap: 0)
        return container
    }

    private static let paperInk: [Reminders.Paper: (UInt8, UInt8, UInt8)] = [
        .rim: (40, 34, 58), .paper: (244, 241, 230), .light: (255, 255, 255),
        .shade: (196, 192, 206), .deepShade: (150, 146, 170), .crease: (228, 224, 212),
    ]

    /// `Reminders.paper` as an image, one image pixel per paper pixel.
    static func paperImage(width: Int, height: Int) -> CGImage? {
        let rows = Reminders.paper(width: width, height: height)
        let h = rows.count, w = rows.first?.count ?? 0
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for (y, row) in rows.enumerated() {
            for (x, ink) in row.enumerated() {
                guard let ink, let c = paperInk[ink] else { continue }
                let i = (y * w + x) * 4
                bytes[i] = c.0; bytes[i + 1] = c.1; bytes[i + 2] = c.2; bytes[i + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private func renderHouse(_ inHouse: HouseSnapshot?, cell: CGSize) {
        guard let inHouse, let image = inHouse.image, inHouse.scale > 0 else {
            if !house.isHidden { house.isHidden = true }
            return
        }
        let origin = display.frame.origin
        house.isHidden = false
        house.contents = image
        house.bounds = CGRect(x: 0, y: 0, width: cell.width * inHouse.scale, height: cell.height * inHouse.scale)
        house.position = CGPoint(x: inHouse.corner.x - origin.x, y: inHouse.corner.y - origin.y)
    }

    private func renderFlight(_ inFlight: FlowerFlight?, flowerCell: CGSize) {
        guard let inFlight, let image = inFlight.image else {
            if !flight.isHidden { flight.isHidden = true }
            return
        }
        let origin = display.frame.origin
        flight.isHidden = false
        flight.contents = image
        flight.bounds = CGRect(x: 0, y: 0, width: flowerCell.width * inFlight.scale, height: flowerCell.height * inFlight.scale)
        flight.position = CGPoint(x: inFlight.position.x - origin.x, y: inFlight.position.y - origin.y)
        flight.transform = CATransform3DMakeRotation(inFlight.rotation, 0, 0, 1)
    }

    // MARK: Speech

    private func renderBubble(_ snap: CreatureSnapshot, index: Int, bodyHalf: CGFloat) {
        guard let text = snap.bubble, !text.isEmpty else { removeBubble(for: index); return }
        let origin = display.frame.origin
        let entry: (plate: CALayer, text: CATextLayer, for: String, shown: Int)
        if var existing = bubbles[index], existing.for == text {
            let whole = Self.bubbleText(text)
            let shown = Self.visibleLength(of: whole, share: snap.bubbleShare)
            if shown != existing.shown {
                existing.text.string = Self.partly(whole, visible: shown)
                existing.text.displayIfNeeded()
                existing.shown = shown
                bubbles[index] = existing
            }
            entry = existing
        } else {
            removeBubble(for: index)
            entry = makeBubble(text, share: snap.bubbleShare)
            bubbles[index] = entry
        }
        // Float it off the creature's "head", then keep it on this screen.
        let size = entry.plate.bounds.size
        var centre = CGPoint(
            x: snap.position.x + snap.inward.dx * (bodyHalf + 10 + size.width / 2),
            y: snap.position.y + snap.inward.dy * (bodyHalf + 10 + size.height / 2)
        )
        let room = display.frame.insetBy(dx: size.width / 2 + 6, dy: size.height / 2 + 6)
        centre.x = min(max(centre.x, room.minX), room.maxX)
        centre.y = min(max(centre.y, room.minY), room.maxY)
        entry.plate.position = CGPoint(x: (centre.x - origin.x).rounded(), y: (centre.y - origin.y).rounded())
    }

    /// How many UTF-16 units of `whole` a share shows, never splitting a letter.
    static func visibleLength(of whole: NSAttributedString, share: Double) -> Int {
        let count = whole.length
        let cut = SpeechReveal.visible(share, of: count)
        guard cut > 0, cut < count else { return cut }
        return (whole.string as NSString).rangeOfComposedCharacterSequence(at: cut).location
    }

    /// The whole line, laid out as ever, with everything past `visible` drawn
    /// invisible: the bubble keeps its size while the text types in.
    static func partly(_ whole: NSAttributedString, visible: Int) -> NSAttributedString {
        guard visible < whole.length else { return whole }
        let copy = NSMutableAttributedString(attributedString: whole)
        copy.addAttribute(.foregroundColor, value: NSColor.clear, range: NSRange(location: visible, length: whole.length - visible))
        return copy
    }

    private func makeBubble(_ text: String, share: Double) -> (plate: CALayer, text: CATextLayer, for: String, shown: Int) {
        let pad = Self.bubblePad
        let attributed = Self.bubbleText(text)
        let shown = Self.visibleLength(of: attributed, share: share)
        let measured = attributed.boundingRect(
            with: CGSize(width: Self.bubbleMaxWidth, height: 400),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).size
        let textSize = CGSize(width: ceil(measured.width) + 2, height: ceil(measured.height) + 2)

        let plate = CALayer()
        plate.actions = Self.noAnimations
        plate.bounds = CGRect(x: 0, y: 0, width: textSize.width + pad * 2, height: textSize.height + pad * 2)
        plate.backgroundColor = CGColor(srgbRed: 43 / 255, green: 36 / 255, blue: 64 / 255, alpha: 0.96)
        plate.borderColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.35)
        plate.borderWidth = 1
        plate.cornerRadius = 6

        let label = CATextLayer()
        label.actions = Self.noAnimations
        label.string = Self.partly(attributed, visible: shown)
        label.isWrapped = true
        label.contentsScale = display.scale
        label.frame = CGRect(x: pad, y: pad, width: textSize.width, height: textSize.height)
        label.displayIfNeeded()               // rasterise now; an offscreen renderer would otherwise lag a frame or more
        plate.addSublayer(label)
        root.addSublayer(plate)
        return (plate, label, text, shown)
    }

    private func removeBubble(for index: Int) {
        bubbles.removeValue(forKey: index)?.plate.removeFromSuperlayer()
    }

    private func makeLayers() -> (body: CALayer, sprite: CALayer, zs: [CALayer], hat: CALayer, letter: CALayer) {
        func pixelLayer() -> CALayer {
            let layer = CALayer()
            layer.magnificationFilter = .nearest
            layer.minificationFilter = .nearest
            layer.contentsGravity = .resize
            layer.actions = Self.noAnimations
            return layer
        }
        let body = CALayer()
        body.actions = Self.noAnimations
        let sprite = pixelLayer()
        body.addSublayer(sprite)
        let zs = (0..<Self.zCount).map { _ in pixelLayer() }
        zs.forEach { $0.opacity = 0; body.addSublayer($0) }
        let hat = pixelLayer()
        hat.isHidden = true
        body.addSublayer(hat)
        let letter = pixelLayer()
        letter.isHidden = true
        letter.zPosition = 1
        body.addSublayer(letter)
        root.addSublayer(body)
        return (body, sprite, zs, hat, letter)
    }

    private static let noAnimations: [String: any CAAction] = [
        "position": NSNull(), "transform": NSNull(), "contents": NSNull(), "opacity": NSNull(), "bounds": NSNull(), "hidden": NSNull(),
    ]
}

/// One paper plane over everything, and its trail as plain square puffs, pooled like the stars.
@MainActor
private final class PlaneSprite {
    let layer: CALayer
    private var puffs: [CALayer] = []
    private let root: CALayer
    private let z: CGFloat

    init(root: CALayer, z: CGFloat, layer: CALayer) {
        self.root = root
        self.z = z
        self.layer = layer
        layer.isHidden = true
        layer.zPosition = z                        // over creatures and bubbles
        root.addSublayer(layer)
    }

    func render(_ plane: PlaneSnapshot?, cell: CGSize, origin: CGPoint) {
        let trail = plane?.trail ?? []
        while puffs.count < trail.count {
            let puff = CALayer()
            puff.actions = ["position": NSNull(), "bounds": NSNull(), "opacity": NSNull(), "hidden": NSNull(), "backgroundColor": NSNull()]
            puff.zPosition = z - 0.5
            puff.backgroundColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            root.addSublayer(puff)
            puffs.append(puff)
        }
        for (puff, dot) in zip(puffs, trail) {
            let size = plane?.puffSize ?? 2
            puff.isHidden = false
            puff.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            puff.position = CGPoint(x: (dot.position.x - origin.x).rounded(), y: (dot.position.y - origin.y).rounded())
            puff.opacity = dot.opacity
        }
        for puff in puffs.dropFirst(trail.count) where !puff.isHidden { puff.isHidden = true }

        guard let plane, let image = plane.image, plane.opacity > 0 else {
            if !layer.isHidden { layer.isHidden = true }
            return
        }
        layer.isHidden = false
        layer.contents = image
        layer.opacity = plane.opacity
        layer.bounds = CGRect(x: 0, y: 0, width: cell.width * plane.scale, height: cell.height * plane.scale)
        layer.position = CGPoint(x: plane.position.x - origin.x, y: plane.position.y - origin.y)
        // Heading left, flip it over so the wing stays on top.
        let upright: CGFloat = cos(plane.heading) < 0 ? -1 : 1
        layer.transform = CATransform3DScale(CATransform3DMakeRotation(plane.heading, 0, 0, 1), 1, upright, 1)
    }
}

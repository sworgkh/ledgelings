import AppKit
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
    /// The flower on its head, if it was given one.
    var hat: CGImage?
    /// Inside the house: draw nothing at all.
    var hidden = false
    /// 1 = full size; falls to 0 as it disappears into the doorway, rises from 0 as it comes out.
    var shrink: CGFloat = 1
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

    let screen: NSScreen
    let view: OverlayView
    private let window: OverlayWindow
    private var creatures: [(body: CALayer, sprite: CALayer, zs: [CALayer], hat: CALayer)] = []
    private lazy var flight: CALayer = {
        let layer = makeLayers().sprite
        layer.isHidden = true
        view.layer?.addSublayer(layer)
        return layer
    }()
    private var bubbles: [Int: (plate: CALayer, text: CATextLayer, for: String)] = [:]
    private var sparkLayers: [CALayer] = []
    private lazy var house: CALayer = {
        let layer = makeLayers().sprite
        layer.isHidden = true
        layer.zPosition = -1                       // behind the creatures
        layer.anchorPoint = CGPoint(x: 1, y: 0)    // grows and shrinks about its bottom-right corner
        view.layer?.addSublayer(layer)
        return layer
    }()
    private static let bubbleFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
    private static let bubbleMaxWidth: CGFloat = 250
    private static let bubblePad: CGFloat = 8

    init(screen: NSScreen) {
        self.screen = screen
        window = OverlayWindow(screen: screen)
        view = OverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        window.contentView = view
        window.orderFrontRegardless()
    }

    func close() { window.close() }

    /// Clickable only while there is something under the cursor worth clicking.
    func setClickable(_ clickable: Bool) {
        if window.ignoresMouseEvents == clickable { window.ignoresMouseEvents = !clickable }
    }

    /// The creature whose speech bubble is under `point`, if any.
    func bubbleIndex(at point: CGPoint) -> Int? {
        let origin = screen.frame.origin
        return bubbles.first { $0.value.plate.frame.offsetBy(dx: origin.x, dy: origin.y).contains(point) }?.key
    }

    func render(_ snapshots: [CreatureSnapshot], z: CGImage?, cell: CGSize, zCell: CGSize,
                flowerCell: CGSize, flight inFlight: FlowerFlight? = nil, sparks: [SparkSnapshot] = [],
                house inHouse: HouseSnapshot? = nil, houseCell: CGSize = .zero) {
        renderFlight(inFlight, flowerCell: flowerCell)
        renderSparks(sparks)
        renderHouse(inHouse, cell: houseCell)
        while creatures.count < snapshots.count { creatures.append(makeLayers()) }
        while creatures.count > snapshots.count {
            creatures.removeLast().body.removeFromSuperlayer()
            removeBubble(for: creatures.count)
        }

        let origin = screen.frame.origin
        // A creature nowhere near this monitor costs it nothing: hidden layer, no
        // commit, so the window server has no reason to recomposite this screen.
        for (index, (layers, snap)) in zip(creatures, snapshots).enumerated() {
            let scale = snap.scale, bodyHeight = cell.height * scale
            let reach = max(cell.width, cell.height) * scale * 2.5
            let visible = screen.frame.insetBy(dx: -reach, dy: -reach)
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
        let origin = screen.frame.origin
        while sparkLayers.count < sparks.count {
            let layer = CALayer()
            layer.actions = ["position": NSNull(), "bounds": NSNull(), "opacity": NSNull(), "hidden": NSNull(), "backgroundColor": NSNull()]
            layer.zPosition = 3
            view.layer?.addSublayer(layer)
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

    private func renderHouse(_ inHouse: HouseSnapshot?, cell: CGSize) {
        guard let inHouse, let image = inHouse.image, inHouse.scale > 0 else {
            if !house.isHidden { house.isHidden = true }
            return
        }
        let origin = screen.frame.origin
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
        let origin = screen.frame.origin
        flight.isHidden = false
        flight.contents = image
        flight.bounds = CGRect(x: 0, y: 0, width: flowerCell.width * inFlight.scale, height: flowerCell.height * inFlight.scale)
        flight.position = CGPoint(x: inFlight.position.x - origin.x, y: inFlight.position.y - origin.y)
        flight.transform = CATransform3DMakeRotation(inFlight.rotation, 0, 0, 1)
    }

    // MARK: Speech

    private func renderBubble(_ snap: CreatureSnapshot, index: Int, bodyHalf: CGFloat) {
        guard let text = snap.bubble, !text.isEmpty else { removeBubble(for: index); return }
        let origin = screen.frame.origin
        let entry: (plate: CALayer, text: CATextLayer, for: String)
        if let existing = bubbles[index], existing.for == text {
            entry = existing
        } else {
            removeBubble(for: index)
            entry = makeBubble(text)
            bubbles[index] = entry
        }
        // Float it off the creature's "head", then keep it on this screen.
        let size = entry.plate.bounds.size
        var centre = CGPoint(
            x: snap.position.x + snap.inward.dx * (bodyHalf + 10 + size.width / 2),
            y: snap.position.y + snap.inward.dy * (bodyHalf + 10 + size.height / 2)
        )
        let room = screen.frame.insetBy(dx: size.width / 2 + 6, dy: size.height / 2 + 6)
        centre.x = min(max(centre.x, room.minX), room.maxX)
        centre.y = min(max(centre.y, room.minY), room.maxY)
        entry.plate.position = CGPoint(x: (centre.x - origin.x).rounded(), y: (centre.y - origin.y).rounded())
    }

    private func makeBubble(_ text: String) -> (plate: CALayer, text: CATextLayer, for: String) {
        let pad = Self.bubblePad
        let attributed = NSAttributedString(string: text, attributes: [
            .font: Self.bubbleFont, .foregroundColor: NSColor.white,
        ])
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
        label.string = attributed
        label.isWrapped = true
        label.contentsScale = screen.backingScaleFactor
        label.frame = CGRect(x: pad, y: pad, width: textSize.width, height: textSize.height)
        plate.addSublayer(label)
        view.layer?.addSublayer(plate)
        return (plate, label, text)
    }

    private func removeBubble(for index: Int) {
        bubbles.removeValue(forKey: index)?.plate.removeFromSuperlayer()
    }

    private func makeLayers() -> (body: CALayer, sprite: CALayer, zs: [CALayer], hat: CALayer) {
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
        view.layer?.addSublayer(body)
        return (body, sprite, zs, hat)
    }

    private static let noAnimations: [String: any CAAction] = [
        "position": NSNull(), "transform": NSNull(), "contents": NSNull(), "opacity": NSNull(), "bounds": NSNull(), "hidden": NSNull(),
    ]
}

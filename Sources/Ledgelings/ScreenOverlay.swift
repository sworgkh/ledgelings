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
    private var creatures: [(body: CALayer, sprite: CALayer, zs: [CALayer])] = []

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

    func render(_ snapshots: [CreatureSnapshot], z: CGImage?, cell: CGSize, zCell: CGSize) {
        while creatures.count < snapshots.count { creatures.append(makeLayers()) }
        while creatures.count > snapshots.count { creatures.removeLast().body.removeFromSuperlayer() }

        let origin = screen.frame.origin
        // A creature nowhere near this monitor costs it nothing: hidden layer, no
        // commit, so the window server has no reason to recomposite this screen.
        for (layers, snap) in zip(creatures, snapshots) {
            let scale = snap.scale, bodyHeight = cell.height * scale
            let reach = max(cell.width, cell.height) * scale * 2.5
            let visible = screen.frame.insetBy(dx: -reach, dy: -reach)
            let here = visible.contains(snap.position)
            if layers.body.isHidden == here { layers.body.isHidden = !here }
            guard here else { continue }
            // The body layer carries position and the turn onto the edge; the
            // sprite inside it carries only the mirror, so the Zs never flip.
            layers.body.position = CGPoint(x: snap.position.x - origin.x, y: snap.position.y - origin.y)
            layers.body.transform = CATransform3DMakeRotation(snap.rotation, 0, 0, 1)
            layers.sprite.bounds = CGRect(x: 0, y: 0, width: cell.width * scale, height: bodyHeight)
            if (layers.sprite.contents as AnyObject?) !== snap.image { layers.sprite.contents = snap.image }
            layers.sprite.transform = CATransform3DMakeScale(snap.isMirrored ? -1 : 1, 1, 1)

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

    private func makeLayers() -> (body: CALayer, sprite: CALayer, zs: [CALayer]) {
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
        view.layer?.addSublayer(body)
        return (body, sprite, zs)
    }

    private static let noAnimations: [String: any CAAction] = [
        "position": NSNull(), "transform": NSNull(), "contents": NSNull(), "opacity": NSNull(), "bounds": NSNull(), "hidden": NSNull(),
    ]
}

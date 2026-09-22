import AppKit

/// The menu-bar icon: Blocky's idle pose, shrunk to 18 points and drawn as a
/// template, so the menu bar paints the body in its own text colour and the
/// eyes show through as holes.
enum StatusIcon {
    static let size: CGFloat = 18

    /// The sprite's 22×20 body, 3×6 eyes right of centre and 4×2 feet, scaled
    /// to whole points on an 18-point canvas (AppKit coordinates: y up).
    static let body = CGRect(x: 1, y: 3, width: 16, height: 14)
    static let eyes = [CGRect(x: 7, y: 10, width: 2, height: 4), CGRect(x: 11, y: 10, width: 2, height: 4)]
    static let feet = [CGRect(x: 3, y: 1, width: 3, height: 2), CGRect(x: 12, y: 1, width: 3, height: 2)]

    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            NSColor.black.setFill()
            body.fill()
            feet.forEach { $0.fill() }
            eyes.forEach { $0.fill(using: .destinationOut) }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Ledgelings"
        return image
    }
}

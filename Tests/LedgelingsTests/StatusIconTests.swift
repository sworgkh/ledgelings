import AppKit
import Testing
@testable import Ledgelings

/// The menu-bar icon: Blocky's face as a template image, eyes as holes.
@MainActor
@Suite struct StatusIconTests {
    /// Alpha at a point (y up, like the icon's own coordinates), drawing the icon at 1 point per pixel.
    func alpha(at x: Int, _ y: Int) -> UInt8 {
        // A template image is drawn through a tint; probe an untinted copy.
        let image = StatusIcon.image().copy() as! NSImage
        image.isTemplate = false
        let size = Int(image.size.width)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        // Bitmap rows count from the top; the icon's coordinates count from the bottom.
        return rep.colorAt(x: x, y: size - 1 - y).map { UInt8(($0.alphaComponent * 255).rounded()) } ?? 0
    }

    @Test func itIsAnEighteenPointTemplateWithABodyTwoEyeHolesAndFeet() {
        let image = StatusIcon.image()
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(alpha(at: 0, 17) == 0, "the corner outside the body is clear")
        #expect(alpha(at: 3, 15) == 255, "the body is solid")
        #expect(alpha(at: 8, 11) == 0 && alpha(at: 12, 11) == 0, "the eyes are holes")
        #expect(alpha(at: 10, 11) == 255, "with body between them")
        #expect(alpha(at: 4, 1) == 255 && alpha(at: 13, 1) == 255, "two feet")
        #expect(alpha(at: 9, 1) == 0, "and nothing between the feet")
    }
}

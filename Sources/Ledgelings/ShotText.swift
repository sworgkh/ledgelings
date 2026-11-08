import AppKit
import CoreText
import LedgelingsCore

/// How a text mark looks: its font on this Mac, its box, and the words drawn turned,
/// the same way on the frozen screens and in the finished picture. Lines start at the
/// box's left, with a margin all round wide enough for the outline.
@MainActor
enum ShotText {
    /// The fonts written by hand a Mac may have, the most like handwriting first.
    static let handNames = ["BradleyHandITCTT-Bold", "Noteworthy-Bold", "ChalkboardSE-Bold", "MarkerFelt-Wide"]
    static let handName: String? = handNames.first { NSFont(name: $0, size: 12) != nil }

    /// The fonts this Mac can offer, in the menu's order.
    static var fonts: [Shot.Font] { Shot.Font.allCases.filter { $0 != .hand || handName != nil } }

    static func nsFont(_ font: Shot.Font, size: CGFloat) -> NSFont {
        let bold = NSFont.systemFont(ofSize: size, weight: .bold)
        func design(_ d: NSFontDescriptor.SystemDesign) -> NSFont {
            bold.fontDescriptor.withDesign(d).flatMap { NSFont(descriptor: $0, size: size) } ?? bold
        }
        switch font {
        case .system: return bold
        case .rounded: return design(.rounded)
        case .mono: return NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        case .serif: return design(.serif)
        case .hand: return handName.flatMap { NSFont(name: $0, size: size) } ?? design(.rounded)
        }
    }

    /// The margin round the words, for the outline and a little air.
    static func margin(_ text: Shot.Text) -> CGFloat { (text.size * 0.18).rounded(.up) }

    private struct Layout {
        var lines: [CTLine]
        var widths: [CGFloat]
        var ascent: CGFloat
        var lineHeight: CGFloat
        var box: CGSize
    }

    private static func layout(_ text: Shot.Text, outline: Bool = false) -> Layout {
        let font = nsFont(text.font, size: text.size)
        let colour = ShotRenderer.colour(text.colour)
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(cgColor: colour) ?? .red]
        if outline {
            attributes[.strokeColor] = NSColor(cgColor: outlineColour(text.colour)) ?? .black
            attributes[.strokeWidth] = 26
        }
        let lines = text.string.components(separatedBy: "\n").map {
            CTLineCreateWithAttributedString(NSAttributedString(string: $0, attributes: attributes))
        }
        let widths = lines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }
        let ascent = font.ascender, lineHeight = (font.ascender - font.descender + font.leading).rounded(.up)
        let m = margin(text)
        // An empty line still has room for the caret and a letter or two.
        let width = max(widths.max() ?? 0, text.size * 0.6)
        return Layout(lines: lines, widths: widths, ascent: ascent, lineHeight: lineHeight,
                      box: CGSize(width: (width + 2 * m).rounded(.up), height: (CGFloat(lines.count) * lineHeight + 2 * m).rounded(.up)))
    }

    /// The box round the words, unturned, in the text's own units.
    static func measure(_ text: Shot.Text) -> CGSize { layout(text).box }

    /// Dark ink round a light colour, white round a dark one.
    static func outlineColour(_ colour: Int) -> CGColor {
        let c = Shot.palette[Shot.colourRange.contains(colour) ? colour : 0]
        let light = 0.2126 * Double(c.r) + 0.7152 * Double(c.g) + 0.0722 * Double(c.b) > 140
        return light ? ScreenOverlay.ink : CGColor(gray: 1, alpha: 1)
    }

    /// Draws it turned about its middle. `yDown`: the context counts y downwards, as the
    /// finished picture's does.
    static func draw(_ text: Shot.Text, in context: CGContext, yDown: Bool = false) {
        let plain = layout(text)
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: text.centre.x, y: text.centre.y)
        if yDown { context.scaleBy(x: 1, y: -1) }
        context.rotate(by: text.angle * .pi / 180)
        context.textMatrix = .identity
        context.setLineJoin(.miter)
        context.setMiterLimit(2)
        let m = margin(text), left = -plain.box.width / 2 + m, top = plain.box.height / 2 - m
        func lines(_ l: Layout) {
            for (i, line) in l.lines.enumerated() {
                context.textPosition = CGPoint(x: left, y: top - l.ascent - CGFloat(i) * l.lineHeight)
                CTLineDraw(line, context)
            }
        }
        if text.outline { lines(layout(text, outline: true)) }
        lines(plain)
    }

    /// The caret before character `caret`, from the box's middle, unturned, y up: its top and bottom.
    static func caret(_ text: Shot.Text, at caret: Int) -> (CGPoint, CGPoint) {
        let l = layout(text)
        let before = String(text.string.prefix(max(0, min(caret, text.string.count))))
        let row = before.filter { $0 == "\n" }.count
        let inLine = before.components(separatedBy: "\n").last ?? ""
        let x = row < l.lines.count ? CTLineGetOffsetForStringIndex(l.lines[row], inLine.utf16.count, nil) : 0
        let m = margin(text), left = -l.box.width / 2 + m, top = l.box.height / 2 - m - CGFloat(row) * l.lineHeight
        return (CGPoint(x: left + x, y: top), CGPoint(x: left + x, y: top - l.lineHeight))
    }
}

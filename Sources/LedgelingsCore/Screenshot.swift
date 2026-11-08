import Foundation

/// The screenshot tool (§7.12): what can be taken, how it is marked up, and how
/// the picture is put together, with no window and no screen. Points are the
/// platform's global screen points with y going UP (AppKit's), as the monitors'
/// frames are; a picture's pixels count from its top-left corner, y going DOWN.
public enum Shot {
    /// What the area is: a dragged rectangle, a freehand loop, the screen under
    /// the cursor, or every monitor stitched into one picture.
    public enum Mode: String, CaseIterable, Sendable {
        case rectangle, lasso, screen, all

        /// The letter that picks it on the toolbar.
        public var key: String {
            switch self {
            case .rectangle: "R"
            case .lasso: "L"
            case .screen: "W"
            case .all: "A"
            }
        }
    }

    /// What a drag draws once the area is chosen.
    public enum Tool: String, CaseIterable, Sendable {
        case box, arrow, highlight, blur, brush, text

        /// The key that picks it on the toolbar: the arrow is the → key.
        public var key: String {
            switch self {
            case .box: "B"
            case .arrow: "→"
            case .highlight: "H"
            case .blur: "X"
            case .brush: "F"
            case .text: "T"
            }
        }
    }

    /// The fonts a text can be in: the Mac's own four designs and one written by hand
    /// (left out where the Mac has no such font).
    public enum Font: String, CaseIterable, Sendable {
        case system, rounded, mono, serif, hand

        public var title: String {
            switch self {
            case .system: tr("System")
            case .rounded: tr("Rounded")
            case .mono: tr("Monospaced")
            case .serif: tr("Serif")
            case .hand: tr("Handwriting")
            }
        }

        /// The one after this among `fonts`, round to the first.
        public func next(in fonts: [Font]) -> Font {
            guard let i = fonts.firstIndex(of: self) else { return fonts.first ?? self }
            return fonts[(i + 1) % fonts.count]
        }
    }

    /// What the full-screen shortcut takes.
    public enum FullScope: String, CaseIterable, Sendable {
        case allScreens, screenUnderCursor
    }

    /// One colour of the game's palette, 0–255.
    public struct Colour: Equatable, Sendable {
        public let r, g, b: Int
        public init(_ r: Int, _ g: Int, _ b: Int) { self.r = r; self.g = g; self.b = b }
    }

    /// Keys 1–6 on the toolbar: red, yellow, green, blue, white, black, the flat
    /// colours of the creatures' sheets.
    public static let palette = [Colour(232, 59, 59), Colour(255, 205, 64), Colour(92, 196, 88),
                                 Colour(64, 132, 232), Colour(255, 255, 255), Colour(28, 24, 36)]
    public static let colourRange = 0...(palette.count - 1)
    /// Line thickness in points.
    public static let thicknessRange = 1...8
    public static let defaultThickness = 3
    public static let defaultFolder = "~/Desktop/Screenshots"
    /// The freehand blur's width: four times the line.
    public static func brushWidth(thickness: Int) -> CGFloat { CGFloat(thickness * 4) }
    /// A blur's square blocks, in points: big enough that words under it cannot be read back.
    public static let blurBlock: CGFloat = 12
    /// A drag shorter than this either way is a click, not an area.
    public static let minimumSide: CGFloat = 4
    /// The highlight's fill: the colour, see-through.
    public static let highlightOpacity = 0.35
    /// A text's size in points, and the steps the toolbar's smaller and bigger buttons take.
    public static let textSizeRange = 12...96
    public static let defaultTextSize = 24
    public static let textSizes = [12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 48, 56, 64, 72, 80, 96]
    /// The step a text turns by, with ⇧ while turning it by hand or with the turn buttons, in degrees.
    public static let snapRange = 5...90
    public static let defaultSnap = 15

    /// The next size up or down the steps from `size`, kept in range.
    public static func textSize(after size: Int, bigger: Bool) -> Int {
        let next = bigger ? textSizes.first { $0 > size } : textSizes.last { $0 < size }
        return next ?? (bigger ? textSizeRange.upperBound : textSizeRange.lowerBound)
    }

    /// An angle in degrees, -180 up to 180.
    public static func normalised(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 } else if d <= -180 { d += 360 }
        return d == -0 ? 0 : d
    }

    /// The nearest multiple of `step` degrees.
    public static func snap(_ degrees: Double, step: Int) -> Double {
        guard step > 0 else { return normalised(degrees) }
        return normalised((degrees / Double(step)).rounded() * Double(step))
    }

    // MARK: Monitors and areas

    /// One monitor: its frame in global points, and pixels per point.
    public struct Monitor: Equatable, Sendable {
        public var frame: CGRect
        public var scale: CGFloat
        public init(frame: CGRect, scale: CGFloat) { self.frame = frame; self.scale = scale }

        /// Its picture's size in pixels.
        public var pixelSize: CGSize { CGSize(width: (frame.width * scale).rounded(), height: (frame.height * scale).rounded()) }
    }

    /// The rectangle two corners make, whichever way it was dragged.
    public static func area(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// Big enough to be an area rather than a click.
    public static func isArea(_ rect: CGRect) -> Bool { rect.width >= minimumSide && rect.height >= minimumSide }

    /// The monitor under `point`, else the nearest one.
    public static func monitor(at point: CGPoint, in monitors: [Monitor]) -> Int? {
        if let i = monitors.firstIndex(where: { $0.frame.contains(point) }) { return i }
        return monitors.indices.min { distance(point, monitors[$0].frame) < distance(point, monitors[$1].frame) }
    }

    private static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }

    /// `rect` (global points) as whole pixels of `monitor`'s picture, cut to the monitor.
    public static func pixelRect(_ rect: CGRect, on monitor: Monitor) -> CGRect {
        let cut = rect.intersection(monitor.frame)
        guard !cut.isNull, !cut.isEmpty else { return .zero }
        let s = monitor.scale, f = monitor.frame
        let x0 = ((cut.minX - f.minX) * s).rounded(), x1 = ((cut.maxX - f.minX) * s).rounded()
        let y0 = ((f.maxY - cut.maxY) * s).rounded(), y1 = ((f.maxY - cut.minY) * s).rounded()
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Every monitor in one picture, each at its own pixel scale (nothing is
    /// resized): where each one's picture goes, and the whole size. They keep their
    /// arrangement: a monitor right of another starts right after it, one below
    /// starts right under it; with nothing before it, a monitor sits as far in as its
    /// offset in the arrangement at its own scale. A 1× monitor beside a 2× one is
    /// half as tall in the picture, and none ever overlaps another.
    public static func stitch(_ monitors: [Monitor]) -> (size: CGSize, places: [CGRect]) {
        guard !monitors.isEmpty else { return (.zero, []) }
        let union = monitors.map(\.frame).reduce(monitors[0].frame) { $0.union($1) }
        var xs = [CGFloat](repeating: 0, count: monitors.count), ys = xs
        // Left to right: each starts after every monitor wholly to its left.
        for i in monitors.indices.sorted(by: { monitors[$0].frame.minX < monitors[$1].frame.minX }) {
            let m = monitors[i]
            let after = monitors.indices.filter { $0 != i && monitors[$0].frame.maxX <= m.frame.minX }
            xs[i] = after.isEmpty ? ((m.frame.minX - union.minX) * m.scale).rounded()
                : after.map { xs[$0] + monitors[$0].pixelSize.width }.max()!
        }
        // Top to bottom: each starts under every monitor wholly above it.
        for i in monitors.indices.sorted(by: { monitors[$0].frame.maxY > monitors[$1].frame.maxY }) {
            let m = monitors[i]
            let under = monitors.indices.filter { $0 != i && monitors[$0].frame.minY >= m.frame.maxY }
            ys[i] = under.isEmpty ? ((union.maxY - m.frame.maxY) * m.scale).rounded()
                : under.map { ys[$0] + monitors[$0].pixelSize.height }.max()!
        }
        let places = monitors.indices.map { CGRect(origin: CGPoint(x: xs[$0], y: ys[$0]), size: monitors[$0].pixelSize) }
        let size = CGSize(width: places.map(\.maxX).max() ?? 0, height: places.map(\.maxY).max() ?? 0)
        return (size, places)
    }

    /// How a point of the screen lands in the finished picture.
    public struct Mapping: Sendable {
        /// The area taken, in global points, on one monitor of this scale.
        public static func area(_ rect: CGRect, scale: CGFloat) -> Mapping {
            Mapping(pieces: [(rect, CGPoint.zero, scale)])
        }

        /// Every monitor, stitched.
        public static func all(_ monitors: [Monitor]) -> Mapping {
            let places = stitch(monitors).places
            return Mapping(pieces: monitors.indices.map { (monitors[$0].frame, places[$0].origin, monitors[$0].scale) })
        }

        let pieces: [(frame: CGRect, origin: CGPoint, scale: CGFloat)]

        /// The piece a point belongs to: the one it is on, else the nearest.
        func piece(_ p: CGPoint) -> (frame: CGRect, origin: CGPoint, scale: CGFloat) {
            pieces.first { $0.frame.contains(p) } ?? pieces.min { distance(p, $0.frame) < distance(p, $1.frame) } ?? (.zero, .zero, 1)
        }

        /// Pixels per point where `p` is.
        public func scale(at p: CGPoint) -> CGFloat { piece(p).scale }

        public func pixel(_ p: CGPoint) -> CGPoint { pixel(p, in: piece(p)) }

        func pixel(_ p: CGPoint, in piece: (frame: CGRect, origin: CGPoint, scale: CGFloat)) -> CGPoint {
            CGPoint(x: piece.origin.x + (p.x - piece.frame.minX) * piece.scale, y: piece.origin.y + (piece.frame.maxY - p.y) * piece.scale)
        }

        /// A mark in the picture's pixels: all of it by the piece its first point is on, so a box across a seam stays a box.
        public func pixels(_ mark: Mark) -> Mark {
            let at = piece(mark.anchor)
            return mark.mapped({ pixel($0, in: at) }, scale: at.scale)
        }
    }

    // MARK: The lasso

    /// A freehand loop, drawn as the cursor moves; closed from its last point back to its first.
    public struct Lasso: Equatable, Sendable {
        public private(set) var points: [CGPoint] = []
        public init(points: [CGPoint] = []) { points.forEach { add($0) } }

        /// A point too near the last one adds nothing but weight.
        public mutating func add(_ p: CGPoint) {
            if let last = points.last, hypot(p.x - last.x, p.y - last.y) < 2 { return }
            points.append(p)
        }

        public var bounds: CGRect {
            guard let first = points.first else { return .null }
            return points.reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        }

        /// The area it encloses, in square points (the shoelace formula).
        public var area: CGFloat {
            guard points.count >= 3 else { return 0 }
            var twice: CGFloat = 0
            for i in points.indices {
                let a = points[i], b = points[(i + 1) % points.count]
                twice += a.x * b.y - b.x * a.y
            }
            return abs(twice) / 2
        }

        /// Enough of a loop to take: three points or more around at least a minimum square.
        public var isUsable: Bool { points.count >= 3 && area >= minimumSide * minimumSide && isArea(bounds) }
    }

    // MARK: Markup

    /// One thing drawn on the picture. Colours are palette indexes; lengths are in the mark's own units.
    public enum Mark: Equatable, Sendable {
        case box(CGRect, colour: Int, thickness: CGFloat)
        case arrow(from: CGPoint, to: CGPoint, colour: Int, thickness: CGFloat)
        case highlight(CGRect, colour: Int)
        /// Pixelated: square blocks, baked into the picture.
        case blur(CGRect)
        /// Pixelated along a stroke this wide.
        case brush([CGPoint], width: CGFloat)
        /// Words, typed in place: always drawn over every other mark, a blur included.
        case text(Text)

        /// Where it starts: what decides which monitor's scale it is drawn at.
        public var anchor: CGPoint {
            switch self {
            case .box(let r, _, _), .highlight(let r, _), .blur(let r): CGPoint(x: r.midX, y: r.midY)
            case .arrow(let from, _, _, _): from
            case .brush(let points, _): points.first ?? .zero
            case .text(let t): t.centre
            }
        }

        public var text: Text? { if case .text(let t) = self { t } else { nil } }

        /// The same mark with every point moved by `f` and every length times `scale`.
        public func mapped(_ f: (CGPoint) -> CGPoint, scale: CGFloat) -> Mark {
            func rect(_ r: CGRect) -> CGRect { area(f(CGPoint(x: r.minX, y: r.minY)), f(CGPoint(x: r.maxX, y: r.maxY))) }
            switch self {
            case .box(let r, let c, let t): return .box(rect(r), colour: c, thickness: t * scale)
            case .arrow(let a, let b, let c, let t): return .arrow(from: f(a), to: f(b), colour: c, thickness: t * scale)
            case .highlight(let r, let c): return .highlight(rect(r), colour: c)
            case .blur(let r): return .blur(rect(r))
            case .brush(let points, let w): return .brush(points.map(f), width: w * scale)
            case .text(var t):
                t.centre = f(t.centre)
                t.size *= scale
                return .text(t)
            }
        }

        /// Too small to keep: a click with a tool rather than a drag.
        public var isTiny: Bool {
            switch self {
            case .box(let r, _, _), .highlight(let r, _), .blur(let r): !isArea(r)
            case .arrow(let a, let b, _, _): hypot(b.x - a.x, b.y - a.y) < minimumSide * 2
            case .brush(let points, _): points.isEmpty
            case .text(let t): t.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }

    /// The order marks are drawn in: every other mark as it was made, then the texts, so a
    /// blur goes under a text and never over it.
    public static func drawingOrder(_ marks: [Mark]) -> [Mark] {
        marks.filter { $0.text == nil } + marks.filter { $0.text != nil }
    }

    /// Words on the picture: where their box's middle is, how big, in which font and
    /// colour, and turned how far. Its box's size is measured by the app (fonts are
    /// the Mac's); everything here takes it, in the text's own units.
    public struct Text: Equatable, Sendable {
        public var string: String
        /// The middle of its box, in the mark's own units (y up on the screen).
        public var centre: CGPoint
        /// Points on the screen; pixels once mapped into the picture.
        public var size: CGFloat
        public var font: Font
        /// Degrees, counter-clockwise as seen, -180 up to 180.
        public var angle: Double
        public var colour: Int
        /// A rim in a contrasting colour, so it reads on any background.
        public var outline: Bool

        public init(string: String, centre: CGPoint, size: CGFloat, font: Font, angle: Double = 0, colour: Int, outline: Bool = true) {
            self.string = string; self.centre = centre; self.size = size; self.font = font
            self.angle = angle; self.colour = colour; self.outline = outline
        }

        private var radians: Double { angle * .pi / 180 }

        /// A point given from the box's middle, unturned, y up, where it lands turned.
        public func global(_ local: CGPoint, yDown: Bool = false) -> CGPoint {
            let c = cos(radians), s = sin(radians)
            let dx = local.x * c - local.y * s, dy = local.x * s + local.y * c
            return CGPoint(x: centre.x + dx, y: yDown ? centre.y - dy : centre.y + dy)
        }

        /// Where `point` is from the box's middle, turned back, y up.
        public func local(_ point: CGPoint, yDown: Bool = false) -> CGPoint {
            let dx = point.x - centre.x, dy = yDown ? centre.y - point.y : point.y - centre.y
            let c = cos(radians), s = sin(radians)
            return CGPoint(x: dx * c + dy * s, y: -dx * s + dy * c)
        }

        /// The box's corners as seen: top-left, top-right, bottom-right, bottom-left.
        public func corners(_ box: CGSize, yDown: Bool = false) -> [CGPoint] {
            let w = box.width / 2, h = box.height / 2
            return [CGPoint(x: -w, y: h), CGPoint(x: w, y: h), CGPoint(x: w, y: -h), CGPoint(x: -w, y: -h)].map { global($0, yDown: yDown) }
        }

        /// The smallest upright rectangle holding the turned box.
        public func bounds(_ box: CGSize, yDown: Bool = false) -> CGRect {
            let ps = corners(box, yDown: yDown)
            let xs = ps.map(\.x), ys = ps.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }

        /// Inside the turned box, or within `slop` of it.
        public func contains(_ point: CGPoint, box: CGSize, slop: CGFloat = 0) -> Bool {
            let p = local(point)
            return abs(p.x) <= box.width / 2 + slop && abs(p.y) <= box.height / 2 + slop
        }

        /// The handle that turns it: `gap` above the middle of its top edge.
        public func turnHandle(_ box: CGSize, gap: CGFloat = 18) -> CGPoint { global(CGPoint(x: 0, y: box.height / 2 + gap)) }
        /// The handle that sizes it: its bottom-right corner.
        public func sizeHandle(_ box: CGSize) -> CGPoint { global(CGPoint(x: box.width / 2, y: -box.height / 2)) }

        /// Moved so its box's top-left corner stays where `old`'s was: a text grows to the
        /// right and down as it is typed, sized or given another font.
        public func keepingTopLeft(of old: Text, oldBox: CGSize, box: CGSize) -> Text {
            let corner = old.global(CGPoint(x: -oldBox.width / 2, y: oldBox.height / 2))
            var moved = self
            moved.centre = .zero
            let offset = moved.global(CGPoint(x: -box.width / 2, y: box.height / 2))
            moved.centre = CGPoint(x: corner.x - offset.x, y: corner.y - offset.y)
            return moved
        }

        /// The angle from the middle to `point`, in degrees counter-clockwise from the right.
        public func bearing(_ point: CGPoint) -> Double { atan2(point.y - centre.y, point.x - centre.x) * 180 / .pi }

        // Typing, with the caret counted in characters.

        public mutating func insert(_ typed: String, at caret: inout Int) {
            let at = string.index(string.startIndex, offsetBy: min(max(caret, 0), string.count))
            string.insert(contentsOf: typed, at: at)
            caret = min(max(caret, 0), string.count - typed.count) + typed.count
        }

        public mutating func deleteBackward(at caret: inout Int) {
            guard caret > 0, caret <= string.count else { return }
            string.remove(at: string.index(string.startIndex, offsetBy: caret - 1))
            caret -= 1
        }

        public mutating func deleteForward(at caret: Int) {
            guard caret >= 0, caret < string.count else { return }
            string.remove(at: string.index(string.startIndex, offsetBy: caret))
        }
    }

    /// Undo and redo for the marks: what they were before each change.
    public struct History: Equatable, Sendable {
        public private(set) var past: [[Mark]] = []
        public private(set) var future: [[Mark]] = []
        public init() {}

        public var canUndo: Bool { !past.isEmpty }
        public var canRedo: Bool { !future.isEmpty }

        /// A change was made: `before` is how the marks were. Redo is gone.
        public mutating func record(_ before: [Mark]) {
            past.append(before)
            future = []
        }

        /// The marks one change back, or nil with nothing to undo.
        public mutating func undo(_ now: [Mark]) -> [Mark]? {
            guard let last = past.popLast() else { return nil }
            future.append(now)
            return last
        }

        public mutating func redo(_ now: [Mark]) -> [Mark]? {
            guard let next = future.popLast() else { return nil }
            past.append(now)
            return next
        }
    }

    /// The arrow's head: its tip, then the two back corners. The shaft stops at their middle.
    public static func arrowHead(from a: CGPoint, to b: CGPoint, thickness: CGFloat) -> [CGPoint] {
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 0 else { return [b, b, b] }
        let ux = (b.x - a.x) / length, uy = (b.y - a.y) / length
        let head = min(max(thickness * 4, 10), length * 0.6), half = head * 0.6
        let back = CGPoint(x: b.x - ux * head, y: b.y - uy * head)
        return [b, CGPoint(x: back.x - uy * half, y: back.y + ux * half), CGPoint(x: back.x + uy * half, y: back.y - ux * half)]
    }

    /// The grid squares a rectangle blur covers (pixels): a grid from the picture's
    /// corner, each square cut to the rectangle and the picture.
    public static func blurCells(_ rect: CGRect, block: Int, size: CGSize) -> [CGRect] {
        let cut = rect.integral.intersection(CGRect(origin: .zero, size: size))
        guard !cut.isNull, !cut.isEmpty, block > 0 else { return [] }
        let b = CGFloat(block)
        var cells: [CGRect] = []
        var y = (cut.minY / b).rounded(.down) * b
        while y < cut.maxY {
            var x = (cut.minX / b).rounded(.down) * b
            while x < cut.maxX {
                let cell = CGRect(x: x, y: y, width: b, height: b).intersection(cut)
                if !cell.isEmpty { cells.append(cell) }
                x += b
            }
            y += b
        }
        return cells
    }

    /// The grid squares a freehand blur covers (pixels): each one whose middle is
    /// within half the width of the stroke, cut to the picture.
    public static func brushCells(_ stroke: [CGPoint], width: CGFloat, block: Int, size: CGSize) -> [CGRect] {
        guard let first = stroke.first, block > 0 else { return [] }
        let r = width / 2, b = CGFloat(block)
        let bounds = stroke.reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }.insetBy(dx: -r - b, dy: -r - b)
        let picture = CGRect(origin: .zero, size: size)
        let segments = stroke.count == 1 ? [(first, first)] : Array(zip(stroke, stroke.dropFirst()))
        var cells: [CGRect] = []
        var y = (max(bounds.minY, 0) / b).rounded(.down) * b
        while y < min(bounds.maxY, size.height) {
            var x = (max(bounds.minX, 0) / b).rounded(.down) * b
            while x < min(bounds.maxX, size.width) {
                let middle = CGPoint(x: x + b / 2, y: y + b / 2)
                if segments.contains(where: { distance(middle, $0.0, $0.1) <= r + b / 2 }) {
                    let cell = CGRect(x: x, y: y, width: b, height: b).intersection(picture)
                    if !cell.isEmpty { cells.append(cell) }
                }
                x += b
            }
            y += b
        }
        return cells
    }

    private static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy
        let t = length == 0 ? 0 : min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / length, 0), 1)
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// Paints each cell its average colour, in a picture of RGBA bytes, rows from the top.
    public static func pixelate(_ bytes: inout [UInt8], width: Int, height: Int, bytesPerRow: Int, cells: [CGRect]) {
        for cell in cells {
            let x0 = max(Int(cell.minX), 0), x1 = min(Int(cell.maxX), width)
            let y0 = max(Int(cell.minY), 0), y1 = min(Int(cell.maxY), height)
            guard x1 > x0, y1 > y0 else { continue }
            var sum = [Int](repeating: 0, count: 4)
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let at = y * bytesPerRow + x * 4
                    for k in 0..<4 { sum[k] += Int(bytes[at + k]) }
                }
            }
            let n = (x1 - x0) * (y1 - y0)
            let average = sum.map { UInt8(($0 + n / 2) / n) }
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let at = y * bytesPerRow + x * 4
                    for k in 0..<4 { bytes[at + k] = average[k] }
                }
            }
        }
    }

    // MARK: Saving

    /// "Screenshot 2026-10-18 14.03.22.png".
    public static func fileName(at date: Date, timeZone: TimeZone = .current) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = timeZone
        format.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Screenshot \(format.string(from: date)).png"
    }

    /// The name, with " (2)", " (3)"… before the extension while it is taken.
    public static func freeName(_ name: String, taken: (String) -> Bool) -> String {
        guard taken(name) else { return name }
        let stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var n = 2
        while taken("\(stem) (\(n)).\(ext)") { n += 1 }
        return "\(stem) (\(n)).\(ext)"
    }

    /// The folder as a path, `~` made the home folder; empty is the default one.
    public static func folderPath(_ folder: String, home: String = NSHomeDirectory()) -> String {
        let f = folder.trimmingCharacters(in: .whitespaces).isEmpty ? defaultFolder : folder
        return f == "~" ? home : f.hasPrefix("~/") ? home + f.dropFirst(1) : f
    }

    // MARK: The last rectangle

    /// A rectangle as it is saved: "x,y,w,h" in global points.
    public static func save(_ rect: CGRect) -> String {
        [rect.minX, rect.minY, rect.width, rect.height].map { String(format: "%.0f", $0) }.joined(separator: ",")
    }

    /// The last rectangle again, cut to the monitor it is mostly on; nil when there is
    /// none, it does not read, or no monitor it was on is attached now.
    public static func lastArea(_ saved: String, on monitors: [Monitor]) -> CGRect? {
        let n = saved.split(separator: ",").compactMap { Double($0) }
        guard n.count == 4 else { return nil }
        let rect = CGRect(x: n[0], y: n[1], width: n[2], height: n[3])
        guard isArea(rect) else { return nil }
        let best = monitors.map { $0.frame.intersection(rect) }.filter { !$0.isNull && isArea($0) }
            .max { $0.width * $0.height < $1.width * $1.height }
        return best
    }

    // MARK: On screen

    /// Where the toolbar goes: at the top of the screen under the cursor, centred on it, kept on the screen.
    public static func toolbarOrigin(cursorX: CGFloat, screen: CGRect, size: CGSize) -> CGPoint {
        let x = min(max(cursorX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
        return CGPoint(x: x.rounded(), y: (screen.maxY - size.height - 32).rounded())
    }

    /// The size label: "1280×720", in pixels.
    public static func sizeLabel(_ size: CGSize) -> String { "\(Int(size.width))×\(Int(size.height))" }

    /// The note after a shot: "Copied 1280×720", "Saved Screenshot ….png", or both.
    public static func toast(size: CGSize, copied: Bool, saved: String?) -> String {
        switch (copied, saved) {
        case (true, let name?): tr("Copied %@ and saved %@", sizeLabel(size), name)
        case (false, let name?): tr("Saved %@", name)
        default: tr("Copied %@", sizeLabel(size))
        }
    }
}

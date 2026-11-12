import CoreGraphics

/// Where the app's windows reopen after the owner moved them. A place is the
/// window's top-left corner in screen points (y up, as AppKit counts), saved
/// per window under `Window.rawValue`.
public enum WindowPlaces {
    /// Every window or sheet the app opens, and whether the owner can move it.
    public enum Window: String, CaseIterable, Sendable {
        case settings, relationships, snippets, actions, reminder
        case tools, translate, readAloud, clipPicker, chat
        /// The creatures' see-through layer over the screen: moving it would move the screen.
        case overlay
        /// The screenshot tool's frozen screens and its toolbar, laid over the screens they capture.
        case shotScreens, shotToolbar
        /// The clipboard's passing note and the paper flying into the text cursor: gone in a moment.
        case clipToast, clipGhost

        /// Dragged by its title bar, its background or its paper.
        public var movable: Bool {
            switch self {
            case .overlay, .shotScreens, .shotToolbar, .clipToast, .clipGhost: false
            default: true
            }
        }

        /// Its place is kept: every movable window.
        public var remembered: Bool { movable }
    }

    /// How much of the top edge must land on a screen for a saved place to count.
    public static let grip = CGSize(width: 40, height: 24)

    /// The frame for a window of `size` whose top-left was saved at `topLeft`, kept
    /// inside the screen its title strip lands on; nil when that strip is on no
    /// screen any more (the monitor is gone), so the window opens where it always did.
    public static func frame(topLeft: CGPoint, size: CGSize, screens: [CGRect]) -> CGRect? {
        let strip = CGRect(x: topLeft.x, y: topLeft.y - grip.height, width: min(size.width, grip.width * 3), height: grip.height)
        guard let screen = screens.first(where: { $0.intersection(strip).width >= min(grip.width, strip.width) && $0.contains(CGPoint(x: strip.midX, y: strip.midY)) })
        else { return nil }
        return clamped(CGRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height), into: screen)
    }

    /// `rect` moved, not shrunk, so as much of it as fits is inside `screen`, its top first.
    public static func clamped(_ rect: CGRect, into screen: CGRect) -> CGRect {
        var r = rect
        r.origin.x = min(max(r.minX, screen.minX), max(screen.minX, screen.maxX - r.width))
        r.origin.y = max(min(r.minY, screen.maxY - r.height), screen.minY)
        if r.maxY > screen.maxY { r.origin.y = screen.maxY - r.height }
        return r
    }

    /// A paper drawn inside a panel of `room` (top-left origin, y down) kept wholly inside it.
    public static func paper(_ paper: CGRect, inside room: CGSize) -> CGRect {
        var r = paper
        r.origin.x = min(max(r.minX, 0), max(0, room.width - r.width)).rounded()
        r.origin.y = min(max(r.minY, 0), max(0, room.height - r.height)).rounded()
        return r
    }
}

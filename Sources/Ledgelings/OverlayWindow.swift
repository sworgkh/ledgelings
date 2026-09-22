import AppKit

/// A transparent sheet of glass over one whole screen.
///
/// It is click-through by default. The colony flips `ignoresMouseEvents` off
/// only while the cursor is on a creature the user can act on, so a click
/// anywhere else always reaches whatever is underneath.
///
/// A non-activating panel, not a plain window: clicking a creature must not
/// pull focus away from the app the user is working in.
/// One monitor as the colony sees it: its frame in global points and its pixel scale.
struct Display: Equatable {
    var frame: CGRect
    var scale: CGFloat
    init(frame: CGRect, scale: CGFloat) { self.frame = frame; self.scale = scale }
    init(screen: NSScreen) { self.init(frame: screen.frame, scale: screen.backingScaleFactor) }
    static var attached: [Display] { NSScreen.screens.map(Display.init) }
}

final class OverlayWindow: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// What the user's hand did, in GLOBAL screen coordinates.
enum HandEvent {
    case down(CGPoint, shift: Bool)
    case dragged(CGPoint)
    case up(CGPoint)
    /// Right button, or Control held: the "other" click.
    case secondaryDown(CGPoint)
}

/// The overlay's content view. It only hears the mouse while the colony has
/// made its window clickable.
final class OverlayView: NSView {
    var onHand: ((HandEvent) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { onHand?(.secondaryDown(NSEvent.mouseLocation)); return }
        onHand?(.down(NSEvent.mouseLocation, shift: event.modifierFlags.contains(.shift)))
    }
    override func mouseDragged(with event: NSEvent) { onHand?(.dragged(NSEvent.mouseLocation)) }
    override func mouseUp(with event: NSEvent) { onHand?(.up(NSEvent.mouseLocation)) }
    override func rightMouseDown(with event: NSEvent) { onHand?(.secondaryDown(NSEvent.mouseLocation)) }
}

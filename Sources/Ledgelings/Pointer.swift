import AppKit

/// The real mouse pointer, for a creature that has grabbed it (`Colony+Revenge`).
/// Points are global AppKit points, like `NSEvent.mouseLocation`.
@MainActor
protocol PointerHold: AnyObject {
    /// Keep the pointer at `point` and start listening for the user's struggle.
    /// False when the pointer cannot be moved: the creature then only clings to it.
    func pin(at point: CGPoint) -> Bool
    /// Only listen for the user's moves and Escape, leaving the pointer free: the creature rides along.
    func follow()
    /// Put the pointer back on `point` after the user moved it.
    func hold(at point: CGPoint)
    /// Stop holding and listening.
    func release()
    /// The user moved the mouse, between frames; with the pointer's new place.
    var onMove: ((CGPoint) -> Void)? { get set }
    /// The user pressed Escape.
    var onEscape: (() -> Void)? { get set }
}

/// Holds the pointer by moving it back each time the user moves it
/// (`CGWarpMouseCursorPosition`), which needs no permission. Nothing is ever
/// detached: the mouse still drives the pointer between moves back, so if the app
/// stops for any reason, the pointer is simply free.
///
/// Escape is heard while Ledgelings is in front, and everywhere else only if the
/// app has the Accessibility permission (macOS gives other apps' keys to no one
/// else). Without it, shaking or the longest hold still let go. Nothing asks.
@MainActor
final class SystemPointer: PointerHold {
    var onMove: ((CGPoint) -> Void)?
    var onEscape: (() -> Void)?
    private var monitors: [Any] = []

    func pin(at point: CGPoint) -> Bool {
        guard Self.warp(to: point) else { return false }
        follow()
        return true
    }

    func follow() {
        release()
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.onMove?(NSEvent.mouseLocation) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            self?.onMove?(NSEvent.mouseLocation)
            return event
        }) { monitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let escape = event.keyCode == 53
            MainActor.assumeIsolated { if escape { self?.onEscape?() } }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.onEscape?()
            return nil
        }) { monitors.append(local) }
    }

    func hold(at point: CGPoint) { Self.warp(to: point) }

    func release() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    /// Moves the pointer. Quartz counts y down from the top of the main display;
    /// AppKit counts it up from the bottom.
    @discardableResult
    static func warp(to point: CGPoint) -> Bool {
        guard let main = NSScreen.screens.first else { return false }
        let ok = CGWarpMouseCursorPosition(CGPoint(x: point.x, y: main.frame.maxY - point.y)) == .success
        // A warp mutes the real mouse for a quarter second; this undoes that, so
        // the user's shaking is felt at once.
        CGAssociateMouseAndMouseCursorPosition(1)
        return ok
    }
}

import AppKit
import LedgelingsCore

/// `--drag-check`: opens every window that moves, on the real screen, drags it with
/// real mouse events, closes it, opens it again and checks it came back where it
/// was let go. Each step on stderr; exit 1 if any window stayed put or forgot its place.
/// It saves places in the shared preferences: back them up first (AGENTS.md). Needs Accessibility
/// (borrowed from the terminal when started from one), an unlocked screen, and
/// `LEDGELINGS_FAKE_TRANSLATE=1` with `brainProvider` = `script`, so no sheet waits on the keychain.
@MainActor
enum DragCheck {
    struct Target {
        let window: WindowPlaces.Window
        let open: () -> Void
        let close: () -> Void
        /// The window's top-left, and a spot to grab it by, in screen points (y up).
        let place: () -> (topLeft: CGPoint, grab: CGPoint)?
    }

    static let shift = CGSize(width: 90, height: -70)

    static func run(_ targets: [Target], settings: AppSettings) async -> Bool {
        // Without Accessibility the pressed mouse never reaches the screen and every window would look stuck.
        guard AXIsProcessTrusted() else {
            say("drag: this build may not press the mouse (Accessibility is off): grant it to the app or the terminal and run again")
            return false
        }
        let wasOn = settings.rememberWindowPlaces
        settings.rememberWindowPlaces = true
        defer { settings.rememberWindowPlaces = wasOn }
        var ok = true
        for t in targets {
            settings.windowPlaces[t.window.rawValue] = nil
            t.open()
            try? await Task.sleep(for: .seconds(1.5))
            guard let before = t.place() else { say("drag \(t.window.rawValue): did not open"); ok = false; t.close(); continue }
            await drag(from: before.grab, by: shift)
            try? await Task.sleep(for: .seconds(0.5))
            guard let after = t.place() else { say("drag \(t.window.rawValue): gone after the drag"); ok = false; continue }
            let moved = CGSize(width: after.topLeft.x - before.topLeft.x, height: after.topLeft.y - before.topLeft.y)
            let saved = settings.place(of: t.window)
            say("drag \(t.window.rawValue): top-left \(p(before.topLeft)) → \(p(after.topLeft)), moved \(Int(moved.width)), \(Int(moved.height)); saved \(saved.map(p) ?? "nothing")")
            let followed = abs(moved.width - shift.width) <= 2 && abs(moved.height - shift.height) <= 2
            if !followed || saved.map({ hypot($0.x - after.topLeft.x, $0.y - after.topLeft.y) > 1.5 }) ?? true {
                say("drag \(t.window.rawValue): FAILED, it did not follow the pointer or its place was not kept"); ok = false
            }
            t.close()
            try? await Task.sleep(for: .seconds(1))
            t.open()
            try? await Task.sleep(for: .seconds(1.5))
            let again = t.place()
            let back = again.map { hypot($0.topLeft.x - after.topLeft.x, $0.topLeft.y - after.topLeft.y) <= 1.5 } ?? false
            say("drag \(t.window.rawValue): reopened at \(again.map { p($0.topLeft) } ?? "nowhere")\(back ? ", where it was left" : ", NOT where it was left")")
            if !back { ok = false }
            t.close()
            try? await Task.sleep(for: .seconds(1))
        }
        say(ok ? "drag: every window moved and came back where it was left" : "drag: FAILED")
        return ok
    }

    /// A real press, a drag in steps and a release, as a hand would do it.
    static func drag(from start: CGPoint, by delta: CGSize) async {
        let height = NSScreen.screens.first?.frame.height ?? 0
        func cg(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: height - p.y) }
        let source = CGEventSource(stateID: .hidSystemState)
        func post(_ type: CGEventType, _ at: CGPoint) {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: cg(at), mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        post(.mouseMoved, start)
        try? await Task.sleep(for: .milliseconds(120))
        post(.leftMouseDown, start)
        try? await Task.sleep(for: .milliseconds(120))
        let steps = 12
        for i in 1...steps {
            let f = CGFloat(i) / CGFloat(steps)
            post(.leftMouseDragged, CGPoint(x: start.x + delta.width * f, y: start.y + delta.height * f))
            try? await Task.sleep(for: .milliseconds(25))
        }
        try? await Task.sleep(for: .milliseconds(120))
        post(.leftMouseUp, CGPoint(x: start.x + delta.width, y: start.y + delta.height))
    }

    /// A titled window by its title: grabbed by the middle of its title bar.
    static func titled(_ title: String) -> (topLeft: CGPoint, grab: CGPoint)? {
        guard let w = NSApp.windows.first(where: { $0.isVisible && $0.title == title }) else { return nil }
        return (CGPoint(x: w.frame.minX, y: w.frame.maxY), CGPoint(x: w.frame.midX, y: w.frame.maxY - 12))
    }

    /// A note window: grabbed by the paper's top margin.
    static func note() -> (topLeft: CGPoint, grab: CGPoint)? {
        guard let w = NSApp.windows.first(where: { $0.isVisible && $0 is NoteWindow }) else { return nil }
        return (CGPoint(x: w.frame.minX, y: w.frame.maxY), CGPoint(x: w.frame.midX, y: w.frame.maxY - 8))
    }

    /// A paper sheet in its panel: grabbed by the paper's top margin.
    static func paper(_ paper: CGRect) -> (topLeft: CGPoint, grab: CGPoint)? {
        guard let panel = NSApp.windows.first(where: { $0.isVisible && $0 is ClipPanel }) else { return nil }
        let top = CGPoint(x: panel.frame.minX + paper.minX, y: panel.frame.maxY - paper.minY)
        return (top, CGPoint(x: top.x + paper.width / 2, y: top.y - 6))
    }

    static func close(titled title: String) { NSApp.windows.first { $0.isVisible && $0.title == title }?.close() }

    private static func p(_ point: CGPoint) -> String { "(\(Int(point.x)), \(Int(point.y)))" }
    private static func say(_ line: String) { FileHandle.standardError.write(Data("\(line)\n".utf8)) }
}

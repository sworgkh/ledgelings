import AppKit
import LedgelingsCore
import SwiftUI

/// Puts a window back where the owner last dragged it, and keeps the place each
/// time they drag it again (`AppSettings.windowPlaces`, `WindowPlaces`).
@MainActor
enum WindowPlacer {
    private static var watching: [ObjectIdentifier: NSObjectProtocol] = [:]

    /// `window` at its saved place when there is one on a screen now; otherwise
    /// `otherwise` places it as before. Either way, a drag from now on is saved.
    static func place(_ window: NSWindow, as name: WindowPlaces.Window, settings: AppSettings, otherwise: () -> Void) {
        let screens = NSScreen.screens.map(\.visibleFrame)
        if let top = settings.place(of: name), let frame = WindowPlaces.frame(topLeft: top, size: window.frame.size, screens: screens) {
            window.setFrameOrigin(frame.origin)
        } else {
            otherwise()
        }
        watch(window, as: name, settings: settings)
    }

    /// Saves where `window` goes when the owner drags it. A move made by the app
    /// (a sheet folding away into a creature) happens with no button down and is not kept.
    static func watch(_ window: NSWindow, as name: WindowPlaces.Window, settings: AppSettings) {
        let id = ObjectIdentifier(window)
        guard watching[id] == nil else { return }
        watching[id] = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak window, weak settings] _ in
            MainActor.assumeIsolated {
                guard let window, let settings, NSEvent.pressedMouseButtons & 1 != 0 else { return }
                settings.moved(name, topLeft: CGPoint(x: window.frame.minX, y: window.frame.maxY))
            }
        }
        closing[id] = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { forget(id) }
        }
    }

    private static var closing: [ObjectIdentifier: NSObjectProtocol] = [:]

    /// Stops saving a window's moves: it is gone.
    private static func forget(_ id: ObjectIdentifier) {
        for token in [watching.removeValue(forKey: id), closing.removeValue(forKey: id)].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: Paper sheets

    /// A paper sheet (the Tools screen, Translate, Read aloud, the clipboard picker) is
    /// drawn inside a see-through panel over one screen's visible frame. Its saved
    /// place picks that screen and the paper's spot in it (top-left origin, y down);
    /// without one, `screen` and the centre, as before.
    static func paper(_ name: WindowPlaces.Window, size: CGSize, screen: NSScreen, settings: AppSettings) -> (screen: NSScreen, paper: CGRect) {
        if let top = settings.place(of: name),
           let frame = WindowPlaces.frame(topLeft: top, size: size, screens: NSScreen.screens.map(\.visibleFrame)),
           let home = NSScreen.screens.first(where: { $0.visibleFrame.contains(CGPoint(x: frame.midX, y: frame.maxY - 1)) }) {
            let room = home.visibleFrame
            let paper = CGRect(x: frame.minX - room.minX, y: room.maxY - frame.maxY, width: size.width, height: size.height).integral
            return (home, WindowPlaces.paper(paper, inside: room.size))
        }
        let room = screen.visibleFrame
        return (screen, CGRect(x: (room.width - size.width) / 2, y: (room.height - size.height) / 2, width: size.width, height: size.height).integral)
    }

    /// The owner let go of a paper sheet at `paper`, in the panel over `room`.
    static func paperMoved(_ name: WindowPlaces.Window, paper: CGRect, room: CGRect, settings: AppSettings) {
        settings.moved(name, topLeft: CGPoint(x: room.minX + paper.minX, y: room.maxY - paper.minY))
    }
}

/// The paper follows a drag that starts anywhere on it a control does not take, and
/// stays inside its panel. `moved` hears where it was let go.
struct PaperDrag: ViewModifier {
    @Binding var paper: CGRect
    /// The panel the paper is drawn in.
    let room: CGSize
    var enabled = true
    let moved: (CGRect) -> Void
    @State private var start: CGPoint?

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { drag in
                    guard enabled else { return }
                    let from = start ?? paper.origin
                    if start == nil { start = from }
                    let to = CGRect(origin: CGPoint(x: from.x + drag.translation.width, y: from.y + drag.translation.height), size: paper.size)
                    paper = WindowPlaces.paper(to, inside: room)
                }
                .onEnded { _ in
                    guard start != nil else { return }
                    start = nil
                    moved(paper)
                },
            including: enabled ? .all : .subviews)
    }
}

extension View {
    func paperDrag(_ paper: Binding<CGRect>, room: CGSize, enabled: Bool = true, moved: @escaping (CGRect) -> Void) -> some View {
        modifier(PaperDrag(paper: paper, room: room, enabled: enabled, moved: moved))
    }
}

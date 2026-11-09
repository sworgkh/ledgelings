import AppKit
import Combine
import LedgelingsCore

/// Everything big that runs on the screen for a while and must stop the moment
/// the owner needs the computer: a dive, a surf, a game. Each registers how to
/// tell it is running and how to stop it; Stop activity (⌃⌥⎋, the menu) calls
/// `stopAll()`, and so does a real key press or click while "Stop when I use
/// the computer" is on (`UseWatch`).
@MainActor
final class Activities {
    enum Kind: String, CaseIterable {
        case surf, dive, game
    }

    static let shared = Activities()

    private var entries: [(kind: Kind, isRunning: () -> Bool, stop: () -> Void)] = []
    /// `--shortcut`, the films: each stop, as it happens.
    var trace: ((String) -> Void)?

    /// `kind` is running while `isRunning` says so; `stop` clears it off the
    /// screen at once (no slow ending: within half a second everything is gone).
    /// Registering a kind again replaces it.
    func register(_ kind: Kind, isRunning: @escaping () -> Bool, stop: @escaping () -> Void) {
        entries.removeAll { $0.kind == kind }
        entries.append((kind, isRunning, stop))
    }

    func unregister(_ kind: Kind) { entries.removeAll { $0.kind == kind } }

    func isRunning(_ kind: Kind) -> Bool { entries.contains { $0.kind == kind && $0.isRunning() } }

    /// Whether anything at all is running.
    var isRunning: Bool { entries.contains { $0.isRunning() } }

    /// What is running now.
    var running: [Kind] { entries.filter { $0.isRunning() }.map(\.kind) }

    /// Stop everything that runs. Returns what was stopped.
    @discardableResult
    func stopAll(why: String = "stop activity") -> [Kind] {
        let stopped = running
        for entry in entries where entry.isRunning() { entry.stop() }
        if !stopped.isEmpty { trace?("activity stopped: \(stopped.map(\.rawValue).joined(separator: ", ")) (\(why))") }
        return stopped
    }
}

/// "Stop when I use the computer": while an activity runs, a real key press or
/// a click anywhere but on a creature stops it. Moving the mouse does not. It
/// asks the system how long ago the last key and click were, ten times a
/// second, which needs no permission; a click the creatures took themselves is
/// told apart by its time (`ownClick`).
@MainActor
final class UseWatch {
    private let settings: AppSettings
    private var timer: Timer?
    private var started: Date?
    /// When a creature (or anything else on the overlay) was last clicked; that click is no reason to stop.
    static var ownClick: Date = .distantPast
    var secondsSince: (CGEventType) -> Double = { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }

    init(settings: AppSettings) {
        self.settings = settings
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.check() } }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// It lives as long as the app.
    func stop() { timer?.invalidate(); timer = nil }

    func check(now: Date = Date()) {
        let activities = Activities.shared
        guard activities.isRunning else { started = nil; return }
        guard let since = started else { started = now; return }
        guard settings.stopOnUse else { return }
        let running = now.timeIntervalSince(since)
        let key = secondsSince(.keyDown)
        let click = min(secondsSince(.leftMouseDown), secondsSince(.rightMouseDown), secondsSince(.otherMouseDown))
        let ownClickAgo = now.timeIntervalSince(Self.ownClick)
        if UsePolicy.stops(runningFor: running, sinceKey: key, sinceClick: click, sinceOwnClick: ownClickAgo) {
            activities.stopAll(why: key < click ? "a key was pressed" : "a click outside the creatures")
            started = nil
        }
    }
}

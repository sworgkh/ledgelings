import AppKit
import Combine
import LedgelingsCore

/// Everything big that runs on the screen for a while and must stop the moment
/// the owner needs the computer: a dive, a surf, a game. Each registers how to
/// tell it is running and how to stop it; Stop activity (⌃⌥Q, the menu, the
/// Stop button in the top-right corner) calls `stopAll()`. Nothing else does: a
/// click or a key in another app goes on to that app and the activity runs on.
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

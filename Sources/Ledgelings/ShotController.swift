import AppKit
import Combine
import LedgelingsCore

/// The screenshot tool from the outside (§7.12): its three shortcuts and menu items
/// start a shot here; a finished picture goes to the clipboard and/or the folder as
/// the settings say, a toast says so, and a creature carries a tiny copy home.
@MainActor
final class ShotController {
    private let settings: AppSettings
    private let colony: () -> Colony?
    private(set) var session: ShotSession?
    /// Capturing right now: a second press waits for nothing.
    private var busy = false
    private var shortcuts: [GlobalShortcut] = []
    private var problems: [String: String] = [:]
    /// Every step, for `--shot-demo` and `--shortcut`.
    var trace: ((String) -> Void)?
    /// What a finished shot did, for `--shot-demo`.
    var finished: ((CGImage, Delivery) -> Void)?

    init(settings: AppSettings, colony: @escaping () -> Colony?) {
        self.settings = settings
        self.colony = colony
    }

    /// Takes the shortcuts from every app, following the settings.
    func takeShortcuts(pressed: @escaping (String) -> Void = { _ in }) {
        let on = settings.$shotEnabled
        func make(_ name: String, _ enabled: Published<Bool>.Publisher, _ shortcut: Published<Shortcut>.Publisher, _ action: @escaping () -> Void) -> GlobalShortcut {
            GlobalShortcut(settings: settings, enabled: on.combineLatest(enabled).map { $0 && $1 }, shortcut: shortcut,
                           problem: { [weak self] in self?.report(name, $0) }, pressed: { pressed(name); action() })
        }
        shortcuts = [
            make("capture", settings.$shotCaptureShortcutEnabled, settings.$shotCaptureShortcut) { [weak self] in self?.toggle() },
            make("full", settings.$shotFullShortcutEnabled, settings.$shotFullShortcut) { [weak self] in self?.fullScreen() },
            make("last", settings.$shotLastShortcutEnabled, settings.$shotLastShortcut) { [weak self] in self?.lastRectangle() },
        ]
    }

    private func report(_ which: String, _ problem: String) {
        problems[which] = problem
        let all = ["capture", "full", "last"].compactMap { problems[$0] }.filter { !$0.isEmpty }.joined(separator: " ")
        if settings.shotShortcutProblem != all { settings.shotShortcutProblem = all }
    }

    var isUp: Bool { session?.isUp == true }

    // MARK: Starting

    /// The toolbar shot; pressed again while it is up, it is let go.
    func toggle() {
        if let session, session.isUp { session.act(.cancel); return }
        withToolbar()
    }

    func withToolbar() {
        Task { @MainActor in
            guard let frames = await capture() else { return }
            let made = ShotSession(frames: frames, settings: settings) { [weak self] outcome in self?.ended(outcome) }
            made.trace = trace
            session = made
            made.start()
        }
    }

    /// The full screen straight to the output: every monitor in one picture, or the one under the cursor.
    func fullScreen() {
        Task { @MainActor in
            guard let frames = await capture() else { return }
            let area: ShotRenderer.Area
            if settings.shotFullScope == .allScreens, frames.count > 1 { area = .all } else {
                let m = Shot.monitor(at: NSEvent.mouseLocation, in: frames.map(\.monitor)) ?? 0
                area = .rect(frames[m].monitor.frame, monitor: m)
            }
            straight(frames, area)
        }
    }

    /// The last rectangle again, straight to the output; with none yet, the toolbar.
    func lastRectangle() {
        guard Shot.lastArea(settings.shotLastRect, on: Display.attached.map { Shot.Monitor(frame: $0.frame, scale: $0.scale) }) != nil else {
            trace?("no last rectangle yet: the toolbar")
            withToolbar()
            return
        }
        Task { @MainActor in
            guard let frames = await capture() else { return }
            let monitors = frames.map(\.monitor)
            guard let rect = Shot.lastArea(settings.shotLastRect, on: monitors),
                  let m = Shot.monitor(at: CGPoint(x: rect.midX, y: rect.midY), in: monitors) else { return }
            straight(frames, .rect(rect, monitor: m))
        }
    }

    private func straight(_ frames: [ShotFrame], _ area: ShotRenderer.Area) {
        guard let image = ShotRenderer.render(frames, area: area, marks: []) else { NSSound.beep(); return }
        let b = area.bounds(frames)
        deliver(image, area: area, action: .enter, spot: CGPoint(x: b.midX, y: b.maxY - 60), remember: false)
    }

    /// Every monitor's picture, the creatures hidden and left out when the setting says so.
    /// Nil, with a toast, when macOS refuses.
    private func capture() async -> [ShotFrame]? {
        guard !busy, !isUp else { return nil }
        busy = true
        defer { busy = false }
        let hide = settings.shotHideCreatures
        let leaving = hide ? colony()?.overlayWindowIDs ?? [] : []
        if hide { colony()?.hideForShot(true) }
        do {
            let frames = try await ShotCapture.capture(leaving: leaving)
            trace?("captured \(frames.count) screen\(frames.count == 1 ? "" : "s"): " + frames.map { "\($0.image.width)×\($0.image.height)" }.joined(separator: ", "))
            return frames
        } catch {
            if hide { colony()?.hideForShot(false) }
            trace?("capture failed: \(error)")
            ClipToast.show(String(describing: error), near: nil)
            if case ShotCapture.Failure.notAllowed = error { ShotCapture.askForPermission() }
            return nil
        }
    }

    // MARK: Finishing

    private func ended(_ outcome: ShotSession.Outcome) {
        let mode = session?.model.mode
        session = nil
        switch outcome {
        case .cancelled:
            colony()?.hideForShot(false)
        case .taken(let image, let area, let action, let spot):
            deliver(image, area: area, action: action, spot: spot, remember: mode == .rectangle)
        }
    }

    /// What became of a shot.
    struct Delivery {
        var copied: Bool
        var saved: URL?
        var problem: String?
    }

    /// `remember`: a rectangle dragged on the toolbar, which the last-rectangle shortcut takes again.
    private func deliver(_ image: CGImage, area: ShotRenderer.Area, action: ShotSession.Action, spot: CGPoint, remember: Bool) {
        if remember, case .rect(let r, _) = area { settings.shotLastRect = Shot.save(r) }
        let copy: Bool, save: Bool
        switch action {
        case .enter: copy = settings.shotCopy || !settings.shotSave; save = settings.shotSave
        case .copy: copy = true; save = false
        case .save: copy = settings.shotCopy; save = true
        }
        let done = Self.output(image, copy: copy, save: save, folder: settings.shotFolder)
        trace?("delivered: copied \(done.copied), saved \(done.saved?.path ?? "no")\(done.problem.map { ", \($0)" } ?? "")")
        colony()?.hideForShot(false)
        let size = CGSize(width: image.width, height: image.height)
        let note = done.problem ?? Shot.toast(size: size, copied: done.copied, saved: done.saved?.lastPathComponent)
        ClipToast.show(note, near: CGRect(x: spot.x - 60, y: spot.y - 70, width: 1, height: 1))
        if settings.shotCreatureBrings, let colony = colony() {
            colony.shotCarrierCome(to: spot, picture: ShotRenderer.thumbnail(image, size: colony.planeCell))
        }
        finished?(image, done)
    }

    /// The PNG onto the clipboard and/or into the folder (made if it is not there).
    static func output(_ image: CGImage, copy: Bool, save: Bool, folder: String, at date: Date = Date()) -> Delivery {
        guard let png = ShotRenderer.png(image) else { return Delivery(copied: false, saved: nil, problem: tr("The picture could not be made.")) }
        var done = Delivery(copied: false, saved: nil, problem: nil)
        if copy {
            let board = NSPasteboard.general
            board.clearContents()
            done.copied = board.setData(png, forType: .png)
        }
        if save {
            let dir = URL(fileURLWithPath: Shot.folderPath(folder), isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let name = Shot.freeName(Shot.fileName(at: date)) { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }
                let url = dir.appendingPathComponent(name)
                try png.write(to: url)
                done.saved = url
            } catch {
                done.problem = tr("Could not save to %@: %@", dir.path, error.localizedDescription)
            }
        }
        return done
    }
}

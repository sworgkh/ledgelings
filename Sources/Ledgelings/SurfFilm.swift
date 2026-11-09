import AppKit
import QuartzCore
import LedgelingsCore

/// Surfing filmed offscreen with three creatures of different species: the
/// tide coming in, the waves, rides, tricks and wipe-outs, every step printed
/// with its time, a still of each moment beside the film (`…-riding.png`,
/// `…-trick.png`, `…-wipeout.png`, `…-board.png`). On the third wave it presses
/// Stop activity, as the shortcut does, and checks the water, the boards and
/// the scoreboard are off the screen within half a second (`…-stopped.png`).
/// Exit 1 if not.
///
///     Ledgelings --surf-film build/surf.mp4
@MainActor
enum SurfFilm {
    static func run(output: URL) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-surf-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let name = "ledgelings-surf-film"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        settings.species = ["blocky", "frog", "robot"]
        settings.creatureCount = 3
        settings.minSize = 2.5; settings.maxSize = 2.5
        settings.brain = .script
        settings.planesEnabled = false
        settings.teaPartiesEnabled = false
        settings.dayMinutes = 30; settings.nightMinutes = 30
        settings.surfMinutes = 2; settings.surfWaves = 6
        let colony = try Colony(settings: settings, history: ChatHistory(directory: scratch.appendingPathComponent("chats")),
                                library: SpriteLibrary(directory: scratch.appendingPathComponent("sprites")),
                                spend: SpendLedger(directory: scratch),
                                bonds: BondBook(directory: scratch),
                                stage: Display(frame: CGRect(origin: .zero, size: Promo.size), scale: Promo.scale))
        colony.meetings = Meetings(gap: -1e6)
        colony.nextPlayAt = .infinity
        colony.playEveryWas = settings.playEveryMinutes
        var seen: [String] = []
        colony.trace = { line in
            guard line.hasPrefix("play") || line.hasPrefix("say") else { return }
            seen.append(line)
            FileHandle.standardError.write(Data(String(format: "surf %6.2f  %@\n", colony.elapsed, line).utf8))
        }
        let stage = Promo.Stage()
        // A window under the water, to show it stays readable through it.
        let window = CALayer()
        window.frame = CGRect(x: 80, y: -10, width: 760, height: 170)
        window.backgroundColor = NSColor(white: 0.96, alpha: 1).cgColor
        window.cornerRadius = 8
        for (k, line) in ["Quarterly notes, draft 3", "The water should never hide this text.",
                          "Clicks go through it to the window underneath.", "Line four of the document, still readable."].enumerated() {
            let text = CATextLayer()
            text.string = line
            text.fontSize = k == 0 ? 22 : 18
            text.foregroundColor = NSColor(white: 0.1, alpha: 1).cgColor
            text.contentsScale = Promo.scale
            text.frame = CGRect(x: 24, y: 128 - CGFloat(k) * 36, width: 720, height: 30)
            window.addSublayer(text)
        }
        stage.root.addSublayer(window)
        stage.root.addSublayer(colony.overlays[0].root)
        let recorder = try Promo.Recorder(url: output, layer: stage.canvas,
                                          size: CGSize(width: Promo.size.width * Promo.scale, height: Promo.size.height * Promo.scale), fps: Promo.fps)
        let stem = output.deletingPathExtension().lastPathComponent
        var stills: Set<String> = []
        func still(_ what: String) {
            guard !stills.contains(what), let image = recorder.lastFrame() else { return }
            stills.insert(what)
            let url = output.deletingLastPathComponent().appendingPathComponent("\(stem)-\(what).png")
            try? ShotRenderer.png(image)?.write(to: url)
            if what == "riding", let s = colony.play, let g = s.surf, let surfing = s.surfing, let water = colony.waterImage(g, surfing)?.image {
                try? ShotRenderer.png(water)?.write(to: output.deletingLastPathComponent().appendingPathComponent("\(stem)-water.png"))
            }
            FileHandle.standardError.write(Data(String(format: "surf %6.2f  still %@\n", colony.elapsed, url.lastPathComponent).utf8))
        }
        let away = CGPoint(x: -500, y: -500)
        let activities = Activities.shared
        activities.register(.surf, isRunning: { colony.play?.kind == .surf }, stop: { colony.stopSurf() })
        defer { activities.unregister(.surf) }
        var frame = 0, started = false, stoppedAt: Double?, cleared: Double?
        var pending: [(what: String, at: Double)] = []
        while frame < Promo.fps * 400 {
            let t = Double(frame) / Double(Promo.fps)
            if !started, t >= 1 {
                CATransaction.begin(); CATransaction.setDisableActions(true)
                started = colony.startPlay(.surf, by: 0, count: 3)
                CATransaction.commit()
                if !started { FileHandle.standardError.write(Data("surf: never started: \(colony.talkStatus)\n".utf8)); exit(1) }
            }
            let before = seen.count
            CATransaction.begin(); CATransaction.setDisableActions(true)
            colony.advance(dt: 1 / Double(Promo.fps), cursor: away, shift: true)
            CATransaction.commit()
            try await recorder.append(frame: frame, at: t)
            // A still a moment after each first: the ride under way, the trick in the air's end, the splash up.
            for line in seen[before...] {
                if line.contains("catches the wave") { pending.append(("riding", t + 1.2)) }
                if line.contains("lands a") { pending.append(("trick", t + 0.05)) }
                if line.contains("wipes out") { pending.append(("wipeout", t + 0.2)) }
                if line.contains("rides it out") { pending.append(("board", t + 0.1)) }
            }
            for p in pending where t >= p.at { still(p.what) }
            pending.removeAll { t >= $0.at }
            // Stop activity on the third wave, once a ride is going.
            if stoppedAt == nil, started, seen.contains(where: { $0.contains("wave 3 rolls") }),
               colony.play?.surf?.riders.contains(where: \.isRiding) == true {
                still("before-stop")
                let stopped = activities.stopAll()
                stoppedAt = colony.elapsed
                FileHandle.standardError.write(Data(String(format: "surf %6.2f  stop activity: %@\n", colony.elapsed, stopped.map(\.rawValue).joined(separator: ", ")).utf8))
            }
            if let at = stoppedAt, cleared == nil, colony.play == nil, colony.playProps().isEmpty {
                cleared = colony.elapsed - at
                FileHandle.standardError.write(Data(String(format: "surf %6.2f  cleared %.2f s after stop: no water, boards or board\n", colony.elapsed, cleared!).utf8))
            }
            if let at = stoppedAt, colony.elapsed - at > 0.6 { still("stopped") }
            if let at = stoppedAt, colony.elapsed - at > 3 { break }
            if started, stoppedAt == nil, colony.play == nil { break }
            frame += 1
        }
        try await recorder.finish()
        let ok = cleared.map { $0 <= 0.5 } ?? false
        print("surf film: \(frame) frames, \(seen.filter { $0.contains("catches") }.count) rides, \(seen.filter { $0.contains("lands a") }.count) tricks, "
              + "\(seen.filter { $0.contains("wipes out") }.count) wipe-outs; stop \(ok ? "cleared" : "did NOT clear") the screen → \(output.path)")
        if !ok { exit(1) }
    }
}

import AppKit
import QuartzCore
import LedgelingsCore

/// Moving house, filmed offscreen on two simulated monitors side by side (the
/// right one shorter): five creatures on both, then the choice goes to the right
/// monitor, then the left, then back to all, every step printed with its time.
///
///     Ledgelings --screens-film build/screens.mp4
@MainActor
enum ScreensFilm {
    static let left = Display(frame: CGRect(x: 0, y: 0, width: 512, height: 576), scale: Promo.scale, id: "film-left", name: "Left")
    static let right = Display(frame: CGRect(x: 512, y: 0, width: 512, height: 420), scale: Promo.scale, id: "film-right", name: "Right")

    static func run(output: URL) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-screens-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let name = "ledgelings-screens-film"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        settings.species = ["blocky", "robot", "frog", "ghost", "cat"]
        settings.creatureCount = 5
        settings.minSize = 2; settings.maxSize = 2.5
        settings.brain = .script
        settings.talkEnabled = false
        settings.planesEnabled = false
        settings.teaPartiesEnabled = false
        settings.playEnabled = false
        settings.dayMinutes = 30; settings.nightMinutes = 30
        let colony = try Colony(settings: settings, history: ChatHistory(directory: scratch.appendingPathComponent("chats")),
                                library: SpriteLibrary(directory: scratch.appendingPathComponent("sprites")),
                                spend: SpendLedger(directory: scratch), bonds: BondBook(directory: scratch),
                                stages: [left, right])
        colony.meetings = Meetings(gap: -1e6)
        colony.trace = { line in
            guard line.hasPrefix("move") || line.hasPrefix("screens") else { return }
            FileHandle.standardError.write(Data(String(format: "screens %6.2f  %@\n", colony.elapsed, line).utf8))
        }
        let stage = Promo.Stage()
        // Above the shorter monitor there is no screen: dark, as a desk is.
        let desk = CALayer()
        desk.frame = CGRect(x: right.frame.minX, y: right.frame.maxY, width: right.frame.width, height: Promo.size.height - right.frame.maxY)
        desk.backgroundColor = CGColor(srgbRed: 0.03, green: 0.03, blue: 0.05, alpha: 1)
        stage.root.addSublayer(desk)
        let seam = CALayer()
        seam.frame = CGRect(x: right.frame.minX - 1, y: 0, width: 2, height: Promo.size.height)
        seam.backgroundColor = CGColor(srgbRed: 0.03, green: 0.03, blue: 0.05, alpha: 1)
        stage.root.addSublayer(seam)
        for overlay in colony.overlays {
            overlay.root.position = overlay.display.frame.origin
            overlay.root.masksToBounds = true
            stage.root.addSublayer(overlay.root)
        }
        let recorder = try Promo.Recorder(url: output, layer: stage.canvas,
                                          size: CGSize(width: Promo.size.width * Promo.scale, height: Promo.size.height * Promo.scale), fps: Promo.fps)
        let away = CGPoint(x: -500, y: -500)
        // What happens when: live on the right, then the left, then everywhere again.
        var plan: [(at: Double, choose: Display?)] = [(3, right), (14, left), (25, nil)]
        var frame = 0
        func report() { for line in colony.describeScreens() { FileHandle.standardError.write(Data("screens \(line)\n".utf8)) } }
        report()
        while frame < Promo.fps * 34 {
            let t = Double(frame) / Double(Promo.fps)
            if let next = plan.first, t >= next.at {
                plan.removeFirst()
                CATransaction.begin(); CATransaction.setDisableActions(true)
                settings.liveOn(next.choose.map { HomeScreen.Monitor(id: $0.id, name: $0.name, frame: $0.frame) })
                colony.applySettings()
                CATransaction.commit()
            }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            colony.advance(dt: 1 / Double(Promo.fps), cursor: away, shift: true)
            CATransaction.commit()
            try await recorder.append(frame: frame, at: t)
            frame += 1
        }
        try await recorder.finish()
        report()
        let off = colony.creatures.filter { !colony.isHome($0.position, slack: 1) }.count
        print("screens film: \(frame) frames, \(off) creatures off the home screens at the end → \(output.path)")
    }
}

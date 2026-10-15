import AppKit
import QuartzCore
import LedgelingsCore

/// Every game played once (or just one), filmed offscreen with four creatures
/// of different species: tag, the rope, the parachute and basketball, one
/// after another, every step printed with its time. The first two are made
/// friends first, so they take turns at the hoop.
///
///     Ledgelings --play-film build/play.mp4 [tag|rope|parachute|basketball]
@MainActor
enum PlayFilm {
    static func run(output: URL, only: Plays.Kind?) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-play-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let name = "ledgelings-play-film"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        settings.species = ["blocky", "robot", "frog", "ghost"]
        settings.creatureCount = 4
        settings.minSize = 2.5; settings.maxSize = 2.5
        settings.brain = .script
        settings.planesEnabled = false
        settings.teaPartiesEnabled = false
        settings.dayMinutes = 30; settings.nightMinutes = 30
        let colony = try Colony(settings: settings, history: ChatHistory(directory: scratch.appendingPathComponent("chats")),
                                library: SpriteLibrary(directory: scratch.appendingPathComponent("sprites")),
                                spend: SpendLedger(directory: scratch),
                                bonds: BondBook(directory: scratch),
                                stage: Display(frame: CGRect(origin: .zero, size: Promo.size), scale: Promo.scale))
        colony.meetings = Meetings(gap: -1e6)
        colony.nextPlayAt = .infinity
        colony.playEveryWas = settings.playEveryMinutes
        // Old friends: a handful of talks behind them.
        let a = colony.character(forCreature: 0).name, b = colony.character(forCreature: 1).name
        colony.bonds.change { book in
            for k in 0..<8 { book.note(a, b, Bonds.Moment(time: Date(timeIntervalSinceNow: Double(-k) * 3600), kind: .talk, who: a, detail: "Hi.")) }
        }
        colony.trace = { line in
            guard line.hasPrefix("play") || line.hasPrefix("say") else { return }
            FileHandle.standardError.write(Data(String(format: "play %6.2f  %@\n", colony.elapsed, line).utf8))
        }
        let stage = Promo.Stage()
        stage.root.addSublayer(colony.overlays[0].root)
        let recorder = try Promo.Recorder(url: output, layer: stage.canvas,
                                          size: CGSize(width: Promo.size.width * Promo.scale, height: Promo.size.height * Promo.scale), fps: Promo.fps)
        let away = CGPoint(x: -500, y: -500)
        var queue = only.map { [$0] } ?? Plays.Kind.allCases
        var frame = 0, idleSince: Double?, startedAt: Double?
        var played: [String] = []
        while frame < Promo.fps * 300 {
            let t = Double(frame) / Double(Promo.fps)
            if colony.play == nil {
                if startedAt != nil { startedAt = nil; idleSince = t }
                // A beat between games, then the next.
                if let next = queue.first, t >= (idleSince ?? 1) + 1.5 {
                    // The friends play tag and basketball together; the others swing and jump.
                    let by: [Plays.Kind: Int] = [.tag: 0, .rope: 2, .parachute: 3, .basketball: 0]
                    // In a transaction of its own: a line said outside one would open an implicit
                    // transaction that holds back every frame after it.
                    CATransaction.begin(); CATransaction.setDisableActions(true)
                    let began = colony.startPlay(next, by: by[next])
                    CATransaction.commit()
                    if began {
                        queue.removeFirst(); played.append(next.rawValue); startedAt = t
                    } else if t - (idleSince ?? 0) > 20 {
                        FileHandle.standardError.write(Data("play: \(next.rawValue) never started: \(colony.talkStatus)\n".utf8))
                        queue.removeFirst()
                    }
                }
                if queue.isEmpty, let idle = idleSince, t >= idle + 2 { break }
            }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            colony.advance(dt: 1 / Double(Promo.fps), cursor: away, shift: true)
            CATransaction.commit()
            try await recorder.append(frame: frame, at: t)
            frame += 1
        }
        try await recorder.finish()
        let moments = colony.bonds.bond(a, b)?.tally[Bonds.Moment.Kind.play.rawValue] ?? 0
        print("play film: \(frame) frames, played \(played.joined(separator: ", ")); \(a) & \(b) have \(moments) games in their story → \(output.path)")
    }
}

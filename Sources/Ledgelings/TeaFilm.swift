import AppKit
import QuartzCore
import LedgelingsCore

/// A tea party on a clean wallpaper, written to an .mp4 frame by frame,
/// offscreen: the way to look at the table, the seating and the turns without
/// waiting for a lucky bump. Built-in lines unless told otherwise; a one-minute party.
///
///     Ledgelings --tea-film build/tea.mp4
@MainActor
enum TeaFilm {
    static func run(output: URL) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-tea-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let name = "ledgelings-tea-film"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        settings.creatureCount = 3
        settings.species = ["blocky", "cat", "robot"]
        settings.minSize = 2.5; settings.maxSize = 2.5
        settings.brain = .script
        // `LEDGELINGS_TEA_SERVER=http://127.0.0.1:1234`: the words from a local model server instead.
        if let server = ProcessInfo.processInfo.environment["LEDGELINGS_TEA_SERVER"] {
            settings.brain = .lmStudio
            settings.talkServer = server
            settings.talkModel = ProcessInfo.processInfo.environment["LEDGELINGS_TEA_MODEL"] ?? "local"
        }
        settings.planesEnabled = false
        settings.dayMinutes = 30; settings.nightMinutes = 30
        settings.teaPartyMinutes = 1
        settings.teaSipSeconds = 3
        settings.bubbleSeconds = 8
        let colony = try Colony(settings: settings, history: ChatHistory(directory: scratch.appendingPathComponent("chats")),
                                library: SpriteLibrary(directory: scratch.appendingPathComponent("sprites")),
                                spend: SpendLedger(directory: scratch),
                                stage: Display(frame: CGRect(origin: .zero, size: Promo.size), scale: Promo.scale))
        colony.meetings = Meetings(gap: -1e6)          // only the party, no other meetings
        // Blocky and the cat on the floor, walking toward each other; the robot up on the right wall.
        let world = colony.world(forSize: 2.5)
        colony.creatures[0] = Creature(world: world, spot: .init(loop: 0, t: 380), facingForwards: true)
        colony.creatures[1] = Creature(world: world, spot: .init(loop: 0, t: 520), facingForwards: false)
        colony.creatures[2] = Creature(world: world, spot: .init(loop: 0, t: world.loops[0].t(onSegment: 1, fraction: 0.5)))
        colony.trace = { line in
            guard !line.hasPrefix("cue") else { return }
            FileHandle.standardError.write(Data(String(format: "tea %6.2f  %@\n", colony.elapsed, line).utf8))
        }
        let stage = Promo.Stage()
        stage.root.addSublayer(colony.overlays[0].root)
        let recorder = try Promo.Recorder(url: output, layer: stage.canvas,
                                          size: CGSize(width: Promo.size.width * Promo.scale, height: Promo.size.height * Promo.scale), fps: Promo.fps)
        let away = CGPoint(x: -500, y: -500)
        var frame = 0, asked = false, over: Double?
        while frame < Promo.fps * 120 {
            let t = Double(frame) / Double(Promo.fps)
            if t >= 1, !asked { colony.teaNow(); asked = true }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            colony.advance(dt: 1 / Double(Promo.fps), cursor: away, shift: true)
            CATransaction.commit()
            try await recorder.append(frame: frame, at: t)
            frame += 1
            if asked, over == nil, colony.teaParty == nil, colony.teaInvite == nil { over = t }
            if let over, t >= over + 4 { break }
        }
        try await recorder.finish()
        print("tea film: \(frame) frames → \(output.path)")
    }
}

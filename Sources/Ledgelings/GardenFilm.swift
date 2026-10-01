import AppKit
import QuartzCore
import LedgelingsCore

/// Five of Blocky's kind, each handed a flower, filmed offscreen until every one
/// has planted it: the way to see who plants where without waiting for meetings.
///
///     Ledgelings --garden-film build/garden.mp4
@MainActor
enum GardenFilm {
    static func run(output: URL) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-garden-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let name = "ledgelings-garden-film"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        settings.creatureCount = 5
        settings.species = ["blocky"]
        settings.minSize = 2.5; settings.maxSize = 2.5
        settings.brain = .script
        settings.talkEnabled = false
        settings.planesEnabled = false
        settings.teaPartiesEnabled = false
        settings.followGiver = false
        settings.flowerMinutes = 1
        settings.dayMinutes = 30; settings.nightMinutes = 30
        let colony = try Colony(settings: settings, history: ChatHistory(directory: scratch.appendingPathComponent("chats")),
                                library: SpriteLibrary(directory: scratch.appendingPathComponent("sprites")),
                                spend: SpendLedger(directory: scratch),
                                stage: Display(frame: CGRect(origin: .zero, size: Promo.size), scale: Promo.scale))
        colony.meetings = Meetings(gap: -1e6)          // the flowers are handed out by hand
        colony.trace = { line in
            guard line.hasPrefix("plant") else { return }
            FileHandle.standardError.write(Data(String(format: "garden %6.2f  %@\n", colony.elapsed, line).utf8))
        }
        let stage = Promo.Stage()
        stage.root.addSublayer(colony.overlays[0].root)
        let recorder = try Promo.Recorder(url: output, layer: stage.canvas,
                                          size: CGSize(width: Promo.size.width * Promo.scale, height: Promo.size.height * Promo.scale), fps: Promo.fps)
        let away = CGPoint(x: -500, y: -500)
        var frame = 0, handed = 0, over: Double?
        while frame < Promo.fps * 90 {
            let t = Double(frame) / Double(Promo.fps)
            // One flower a second: creature k gets one from the next along.
            if handed < colony.creatures.count, t >= 1 + Double(handed),
               colony.gifts.give(Gifts.flowers[handed], from: (handed + 1) % colony.creatures.count, to: handed, at: colony.elapsed) {
                handed += 1
            }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            colony.advance(dt: 1 / Double(Promo.fps), cursor: away, shift: true)
            CATransaction.commit()
            try await recorder.append(frame: frame, at: t)
            frame += 1
            if handed == colony.creatures.count, over == nil, colony.gifts.flight == nil, colony.gifts.worn.isEmpty { over = t }
            if let over, t >= over + 3 { break }
        }
        try await recorder.finish()
        print("garden film: \(frame) frames, \(colony.garden.beds.count) planted → \(output.path)")
    }
}

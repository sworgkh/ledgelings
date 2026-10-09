import AppKit
import QuartzCore
import LedgelingsCore

/// One creature of every shipped species, filmed offscreen from nightfall until
/// each lies asleep in its own bed, then the first one's bed dragged up to the
/// ceiling: the way to see the beds, and who walks where, without waiting for night.
///
///     Ledgelings --bed-film build/beds.mp4
@MainActor
enum BedFilm {
    static func run(output: URL) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-beds-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let name = "ledgelings-bed-film"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        settings.species = SpriteLibrary.builtIn
        settings.creatureCount = SpriteLibrary.builtIn.count
        settings.minSize = 2.5; settings.maxSize = 2.5
        settings.brain = .script
        settings.planesEnabled = false
        settings.teaPartiesEnabled = false
        settings.dayMinutes = 30; settings.nightMinutes = 30
        let colony = try Colony(settings: settings, history: ChatHistory(directory: scratch.appendingPathComponent("chats")),
                                library: SpriteLibrary(directory: scratch.appendingPathComponent("sprites")),
                                spend: SpendLedger(directory: scratch),
                                stage: Display(frame: CGRect(origin: .zero, size: Promo.size), scale: Promo.scale))
        colony.meetings = Meetings(gap: -1e6)
        colony.trace = { line in
            guard line.hasPrefix("bed") else { return }
            FileHandle.standardError.write(Data(String(format: "beds %6.2f  %@\n", colony.elapsed, line).utf8))
        }
        let stage = Promo.Stage()
        stage.root.addSublayer(colony.overlays[0].root)
        let recorder = try Promo.Recorder(url: output, layer: stage.canvas,
                                          size: CGSize(width: Promo.size.width * Promo.scale, height: Promo.size.height * Promo.scale), fps: Promo.fps)
        let away = CGPoint(x: -500, y: -500)
        let ceiling = CGPoint(x: Promo.size.width / 2, y: Promo.size.height - 60)
        var frame = 0, asleepAt: Double?, drag: (from: CGPoint, start: Double)?, dropped: Double?
        while frame < Promo.fps * 120 {
            let t = Double(frame) / Double(Promo.fps)
            if t >= 1, !colony.isNight { colony.skipPhase() }
            if asleepAt == nil, colony.isNight, colony.creatures.allSatisfy(\.isSleeping), colony.bedTrips.isEmpty { asleepAt = t }
            // Three seconds after the last one is down, pick up the first one's bed and carry it to the ceiling.
            if let asleepAt, drag == nil, t >= asleepAt + 3, let bed = colony.bedSnapshots().first {
                let up = CGVector(dx: -sin(bed.rotation), dy: cos(bed.rotation))
                let half = colony.bedCell.width * bed.scale / 2 - 2
                let grip = CGPoint(x: bed.floor.x + up.dx * 2 + up.dy * half, y: bed.floor.y + up.dy * 2 - up.dx * half)
                colony.hand(.down(grip, shift: false))
                drag = (grip, t)
            }
            if let d = drag, dropped == nil {
                let p = min(1, (t - d.start) / 1.5)
                let at = CGPoint(x: d.from.x + (ceiling.x - d.from.x) * p, y: d.from.y + (ceiling.y - d.from.y) * p)
                colony.hand(.dragged(at))
                if p >= 1 { colony.hand(.up(at)); dropped = t }
            }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            colony.advance(dt: 1 / Double(Promo.fps), cursor: away, shift: true)
            CATransaction.commit()
            try await recorder.append(frame: frame, at: t)
            frame += 1
            if let dropped, t >= dropped + 4 { break }
        }
        try await recorder.finish()
        print("bed film: \(frame) frames, \(colony.bedSnapshots().count) beds out → \(output.path)")
    }
}

import AppKit
import QuartzCore
import LedgelingsCore

/// A reminder delivered on a clean wallpaper, written to an .mp4 frame by
/// frame, offscreen: the way to look at the plane, the zoom and the letter
/// without waiting for a real reminder. Built-in lines, no model.
///
///     Ledgelings --reminder-film build/reminder.mp4 ["Stretch your back"]
@MainActor
enum ReminderFilm {
    static func run(output: URL, text: String) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-reminder-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let name = "ledgelings-reminder-film"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        settings.creatureCount = 4
        settings.species = ["blocky", "cat", "ghost", "robot"]
        settings.minSize = 2.5; settings.maxSize = 2.5
        settings.brain = .script
        settings.planesEnabled = false
        settings.dayMinutes = 30; settings.nightMinutes = 30
        settings.reminderLetterSeconds = 4
        let colony = try Colony(settings: settings, history: ChatHistory(directory: scratch.appendingPathComponent("chats")),
                                library: SpriteLibrary(directory: scratch.appendingPathComponent("sprites")),
                                spend: SpendLedger(directory: scratch),
                                stage: Display(frame: CGRect(origin: .zero, size: Promo.size), scale: Promo.scale))
        colony.userIdleSeconds = { 0 }
        let stage = Promo.Stage()
        stage.root.addSublayer(colony.overlays[0].root)
        let recorder = try Promo.Recorder(url: output, layer: stage.canvas,
                                          size: CGSize(width: Promo.size.width * Promo.scale, height: Promo.size.height * Promo.scale), fps: Promo.fps)
        let away = CGPoint(x: -500, y: -500)
        var frame = 0, sent = false
        while frame < Promo.fps * 20 {
            let t = Double(frame) / Double(Promo.fps)
            if t >= 1, !sent { colony.deliverNow(Reminders.Reminder(text: text, time: colony.now())); sent = true }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            colony.advance(dt: 1 / Double(Promo.fps), cursor: away, shift: false)
            CATransaction.commit()
            try await recorder.append(frame: frame, at: t)
            frame += 1
            if sent, colony.delivery == nil { break }
        }
        try await recorder.finish()
        print("reminder film: \(frame) frames → \(output.path)")
    }
}

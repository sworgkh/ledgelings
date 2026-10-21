import AppKit
import QuartzCore
import LedgelingsCore

/// An invitation turning into a deed, filmed offscreen: the first creature
/// throws the second a paper plane inviting it to a game (soccer by default)
/// or to tea, the second writes back yes, and once the answer lands the game
/// starts and is played out. Built-in lines, so it needs no server and costs
/// nothing; every step printed with its time (`deed Blocky asks Unit 7: soccer
/// (letter)`, `deed Unit 7 accepts soccer from Blocky`, `play soccer result: 2-1…`),
/// then what the two remember of it.
///
///     Ledgelings --invite-film build/invite.mp4 [soccer|tag|basketball|baseball|tea]
@MainActor
enum InviteFilm {
    static func run(output: URL, offer: Deeds.Offer) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-invite-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let name = "ledgelings-invite-film"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        settings.species = ["blocky", "robot", "frog", "ghost"]
        settings.creatureCount = 4
        settings.minSize = 2.5; settings.maxSize = 2.5
        settings.brain = .script
        settings.planeMinutes = AppSettings.planeRange.upperBound
        settings.teaPartiesEnabled = offer == .tea
        settings.dayMinutes = 30; settings.nightMinutes = 30
        settings.soccerMinutes = 1; settings.soccerGoals = 2; settings.baseballInnings = 1
        let colony = try Colony(settings: settings, history: ChatHistory(directory: scratch.appendingPathComponent("chats")),
                                library: SpriteLibrary(directory: scratch.appendingPathComponent("sprites")),
                                spend: SpendLedger(directory: scratch),
                                bonds: BondBook(directory: scratch),
                                stage: Display(frame: CGRect(origin: .zero, size: Promo.size), scale: Promo.scale))
        colony.meetings = Meetings(gap: -1e6)
        colony.nextPlayAt = .infinity
        colony.playEveryWas = settings.playEveryMinutes
        colony.forcedOffer = offer
        colony.forcedAnswer = true
        let a = colony.character(forCreature: 0).name, b = colony.character(forCreature: 1).name
        colony.trace = { line in
            guard ["deed", "play", "say", "memory", "tea"].contains(where: line.hasPrefix) else { return }
            FileHandle.standardError.write(Data(String(format: "film %6.2f  %@\n", colony.elapsed, line).utf8))
        }
        let stage = Promo.Stage()
        stage.root.addSublayer(colony.overlays[0].root)
        let recorder = try Promo.Recorder(url: output, layer: stage.canvas,
                                          size: CGSize(width: Promo.size.width * Promo.scale, height: Promo.size.height * Promo.scale), fps: Promo.fps)
        let away = CGPoint(x: -500, y: -500)
        var frame = 0, thrown = false, startedAt: Double?, overAt: Double?
        while frame < Promo.fps * 400 {
            let t = Double(frame) / Double(Promo.fps)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            if !thrown, t >= 1, colony.canHandleMail(0), colony.canHandleMail(1) {
                colony.throwPlane(from: 0, to: 1, answering: nil)
                thrown = true
            }
            colony.advance(dt: 1 / Double(Promo.fps), cursor: away, shift: true)
            CATransaction.commit()
            try await recorder.append(frame: frame, at: t)
            frame += 1
            let going = colony.play != nil || colony.teaParty != nil
            if going, startedAt == nil { startedAt = t }
            if startedAt != nil, !going, overAt == nil { overAt = t }
            if let over = overAt, t >= over + 2 { break }
            // Nothing came of it: say so rather than film an empty screen for minutes.
            if thrown, startedAt == nil, colony.agreed.isEmpty, colony.invitations.isEmpty, colony.airmail == nil, colony.replyDue == nil, t > 30 { break }
        }
        try await recorder.finish()
        colony.memoryDump(only: a).filter { $0.contains(b) }.forEach { FileHandle.standardError.write(Data(("film " + $0 + "\n").utf8)) }
        print("invite film: \(frame) frames, \(a) invited \(b) to \(offer.tag): \(startedAt == nil ? "it never started" : "it was played") → \(output.path)")
        if startedAt == nil { throw CocoaError(.featureUnsupported) }
    }
}

import AppKit
import QuartzCore
import LedgelingsCore

/// A dive filmed offscreen with five creatures, three diving: the water
/// rising, the gear going on, the jumps and splashes, the sea life, a click
/// through the water into a window under it, the draining and the climb out
/// dripping; then a second dive, ended by Stop activity, and how long the screen
/// took to clear. Every step printed with its time, stills beside the film.
///
///     Ledgelings --dive-film build/dive.mp4
@MainActor
enum DiveFilm {
    static func run(output: URL) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-dive-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let name = "ledgelings-dive-film"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        settings.species = ["blocky", "robot", "frog", "ghost", "slime"]
        settings.creatureCount = 5
        settings.minSize = 2.5; settings.maxSize = 2.5
        settings.brain = .script
        settings.planesEnabled = false
        settings.teaPartiesEnabled = false
        settings.playEnabled = false
        settings.dayMinutes = 30; settings.nightMinutes = 30
        // A short dive, to see it through to the end.
        settings.diveMinutes = 0.5
        settings.diveDivers = 3
        let colony = try Colony(settings: settings, history: ChatHistory(directory: scratch.appendingPathComponent("chats")),
                                library: SpriteLibrary(directory: scratch.appendingPathComponent("sprites")),
                                spend: SpendLedger(directory: scratch),
                                bonds: BondBook(directory: scratch),
                                stage: Display(frame: CGRect(origin: .zero, size: Promo.size), scale: Promo.scale))
        colony.meetings = Meetings(gap: -1e6)
        colony.nextPlayAt = .infinity
        var t = 0.0
        func log(_ line: String) { FileHandle.standardError.write(Data(String(format: "film %6.2f  %@\n", t, line).utf8)) }
        colony.trace = { line in if line.hasPrefix("dive") || line.hasPrefix("say") { log(line) } }
        let activities = Activities.shared
        activities.register(.dive, isRunning: { colony.isDiving }, stop: { colony.stopDive() })
        activities.trace = { log($0) }

        let stage = Promo.Stage()
        // A window of another app, under the water: its button shows whether a click reached it.
        let window = CALayer(), button = CALayer(), label = CATextLayer()
        window.frame = CGRect(x: 360, y: 40, width: 300, height: 150)
        window.backgroundColor = CGColor(gray: 0.93, alpha: 1)
        window.cornerRadius = 8
        button.frame = CGRect(x: 90, y: 40, width: 120, height: 36)
        button.backgroundColor = CGColor(srgbRed: 0.25, green: 0.45, blue: 0.85, alpha: 1)
        button.cornerRadius = 6
        label.frame = CGRect(x: 10, y: 100, width: 280, height: 30)
        label.string = "Another app"
        label.fontSize = 16
        label.foregroundColor = CGColor(gray: 0.2, alpha: 1)
        label.contentsScale = Promo.scale
        window.addSublayer(button); window.addSublayer(label)
        stage.root.addSublayer(window)
        stage.root.addSublayer(colony.overlays[0].root)
        let recorder = try Promo.Recorder(url: output, layer: stage.canvas,
                                          size: CGSize(width: Promo.size.width * Promo.scale, height: Promo.size.height * Promo.scale), fps: Promo.fps)
        var stills: Set<String> = []
        func still(_ what: String) {
            guard !stills.contains(what), let image = recorder.lastFrame() else { return }
            stills.insert(what)
            let stem = output.deletingPathExtension().lastPathComponent
            let url = output.deletingLastPathComponent().appendingPathComponent("\(stem)-\(what).png")
            try? ShotRenderer.png(image)?.write(to: url)
            log("still \(url.lastPathComponent)")
        }

        let away = CGPoint(x: -500, y: -500), dt = 1 / Double(Promo.fps)
        enum Step { case before, first, between, second, stopped(at: Double), done }
        var step = Step.before, frame = 0, clicked = false, ok = true
        var secondAt = 0.0, failures: [String] = []
        while frame < Promo.fps * 90 {
            t = Double(frame) * dt
            CATransaction.begin(); CATransaction.setDisableActions(true)
            colony.advance(dt: dt, cursor: away, shift: false)
            switch step {
            case .before where t >= 1:
                log("Start a dive (Creature Actions)")
                if colony.startDive() { step = .first } else { failures.append("the dive did not start: \(colony.talkStatus)"); step = .done }
            case .first:
                guard let dive = colony.dive?.model else {
                    log("dive one is over; everyone out")
                    step = .between; secondAt = t + 4
                    break
                }
                if dive.phase == .rising, dive.level > 0.5 { still("rising") }
                if colony.dive?.splashes.isEmpty == false { still("splash") }
                if dive.phase == .on, let at = dive.filledAt, dive.time - at > 8 {
                    still("under")
                    let water = dive.water(0)
                    let height = water.height
                    if abs(height - Promo.size.height * CGFloat(settings.diveWaterShare)) > 1 {
                        failures.append("the water is \(Int(height)) points high, not a third")
                    }
                }
                // A click through the water, onto the other app's button.
                if !clicked, dive.phase == .on, let at = dive.filledAt, dive.time - at > 10 {
                    clicked = true
                    let point = CGPoint(x: window.frame.midX, y: window.frame.minY + 58)
                    let creatures = colony.takesClick(at: point, shift: false)
                    log(String(format: "click at (%.0f, %.0f) under the water: %@", point.x, point.y,
                               creatures ? "the creatures took it" : "through to the window below"))
                    if creatures { failures.append("the water took a click") } else {
                        button.backgroundColor = CGColor(srgbRed: 0.2, green: 0.7, blue: 0.35, alpha: 1)
                        label.string = "Another app: clicked"
                    }
                }
                if clicked, let at = dive.filledAt, dive.time - at > 10.3 { still("clicked") }
                if dive.phase == .draining { still("draining") }
            case .between:
                if !colony.dripping.isEmpty { still("out") }
                if t >= secondAt {
                    log("Start a dive again")
                    button.backgroundColor = CGColor(srgbRed: 0.25, green: 0.45, blue: 0.85, alpha: 1)
                    label.string = "Another app"
                    if colony.startDive() { step = .second; secondAt = t } else { failures.append("the second dive did not start"); step = .done }
                }
            case .second where t - secondAt >= 8:
                log("Stop activity (⌃⌥⎋)")
                activities.stopAll()
                step = .stopped(at: t)
            case .stopped(let at):
                let gone = !colony.overlays[0].hasWater && colony.dive == nil && !colony.creatures.contains(where: \.isPlaying)
                if gone {
                    log(String(format: "stop activity: water, fish and gear gone after %.2f s", t - at))
                    if t - at > 0.5 { failures.append("clearing took longer than half a second") }
                    still("stopped")
                    step = .done; secondAt = t
                } else if t - at > 0.5 {
                    failures.append("still on the screen half a second after Stop activity")
                    step = .done; secondAt = t
                }
            case .done where t - secondAt > 1.5:
                frame = .max - 1
            default: break
            }
            CATransaction.commit()
            if frame == .max - 1 { break }
            try await recorder.append(frame: frame, at: t)
            frame += 1
        }
        try await recorder.finish()
        let a = colony.character(forCreature: 0).name
        let dives = colony.bonds.book.bonds.values.compactMap { $0.tally[Bonds.Moment.Kind.dive.rawValue] }.reduce(0, +)
        for f in failures { FileHandle.standardError.write(Data("dive film: FAILED \(f)\n".utf8)); ok = false }
        print("dive film: \(dives) dive moments in the pairs' stories (\(a) and friends) → \(output.path)")
        if !ok { throw NSError(domain: "dive film", code: 1, userInfo: [NSLocalizedDescriptionKey: failures.joined(separator: "; ")]) }
    }
}

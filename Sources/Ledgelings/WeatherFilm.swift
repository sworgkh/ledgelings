import AppKit
import QuartzCore
import LedgelingsCore

/// Each weather filmed offscreen (SPEC §7.20) with four creatures, two of them standing close and one hanging
/// from the top edge, over a pretend window whose top the snow piles on. Every step is printed with its time
/// (`weather 1.00 weather snow starts`, `weather 31.00 snow pile bottom 6 px`, `weather 12.40 rain Blocky & Boo
/// share an umbrella`, `weather 24.10 rain Sprout umbrella full, falls`, `weather 8.20 wind gust pushes Sprout
/// 4 px`), and stills are written beside the film (`…-snow-window.png`, `…-snow-bottom.png`, `…-rain-shared.png`,
/// `…-rain-falling.png`, `…-wind.png`, `…-storm.png`). Exit 1 if a step that should happen did not.
///
///     Ledgelings --weather-film build/weather.mp4 [snow|rain|wind|storm]
@MainActor
enum WeatherFilm {
    static func run(output: URL, only: Weather.Kind?) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-weather-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let name = "ledgelings-weather-film"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        settings.species = ["blocky", "ghost", "robot", "sprout"]
        settings.creatureCount = 4
        settings.minSize = 1; settings.maxSize = 2
        settings.brain = .script
        settings.talkEnabled = true
        settings.planesEnabled = false
        settings.teaPartiesEnabled = false
        settings.playEnabled = false
        settings.deedsEnabled = false
        settings.dayMinutes = 600; settings.nightMinutes = 0
        settings.effectsAmbientEveryMinutes = 120
        settings.effectsReduceMotion = .off
        settings.weatherReduceMotion = .off
        settings.weatherMinutes = 1
        settings.bubbleSeconds = 3
        let colony = try Colony(settings: settings, history: ChatHistory(directory: scratch.appendingPathComponent("chats")),
                                library: SpriteLibrary(directory: scratch.appendingPathComponent("sprites")),
                                spend: SpendLedger(directory: scratch), bonds: BondBook(directory: scratch),
                                stage: Display(frame: CGRect(origin: .zero, size: Promo.size), scale: Promo.scale))
        colony.meetings = Meetings(gap: -1e6)
        colony.nextPlayAt = .infinity
        colony.elapsed = 1e4
        var t = 0.0
        func log(_ line: String) { FileHandle.standardError.write(Data(String(format: "weather %6.2f  %@\n", t, line).utf8)) }
        var seen: [String] = []
        colony.weather.trace = { line in seen.append(line); log(line) }
        // Nobody was left alone too long: the film's clock starts late.
        for i in colony.creatures.indices { colony.fx.metAt[i] = colony.elapsed + 1e5 }
        colony.fx.trace = { _ in }

        // The pretend window, drawn on the desktop under the creatures; the weather is told it is there.
        let stage = Promo.Stage()
        var window = CGRect(x: 300, y: 150, width: 420, height: 230)
        let pane = CALayer(), bar = CALayer()
        pane.backgroundColor = CGColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1)
        bar.backgroundColor = CGColor(srgbRed: 0.80, green: 0.81, blue: 0.85, alpha: 1)
        pane.addSublayer(bar)
        stage.root.addSublayer(pane)
        func placeWindow() {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            pane.frame = window
            bar.frame = CGRect(x: 0, y: window.height - 22, width: window.width, height: 22)
            CATransaction.commit()
            colony.weather.fakeWindows = [WeatherWatch.Window(id: 1, frame: window)]
        }
        placeWindow()
        stage.root.addSublayer(colony.overlays[0].root)
        let recorder = try Promo.Recorder(url: output, layer: stage.canvas,
                                          size: CGSize(width: Promo.size.width * Promo.scale, height: Promo.size.height * Promo.scale), fps: Promo.fps)
        let dt = 1 / Double(Promo.fps), away = CGPoint(x: -500, y: -500)

        let names = colony.creatures.indices.map { colony.character(forCreature: $0).name }
        guard let blocky = names.firstIndex(of: "Blocky"), let boo = names.firstIndex(of: "Boo"),
              let unit = names.firstIndex(of: "Unit 7"), let sprout = names.firstIndex(of: "Sprout") else {
            throw NSError(domain: "weather film", code: 1, userInfo: [NSLocalizedDescriptionKey: "not the four expected: \(names)"])
        }
        // Blocky and Boo are friends (snowballs fly between friends); Sprout is the light one.
        colony.bonds.change { $0.note("Blocky", "Boo", Bonds.Moment(time: Date(), kind: .talk, who: "Blocky", detail: "a chat")) }
        colony.sizes[blocky] = 2; colony.sizes[boo] = 2; colony.sizes[unit] = 2; colony.sizes[sprout] = 1
        func put(_ i: Int, floor: Bool, at fraction: CGFloat, still: Bool = true) {
            let world = colony.world(forSize: colony.sizes[i])
            guard let seg = world.segments.first(where: { world.loops[$0.loop].inward(ofSegment: $0.segment).dy > (floor ? 0.9 : -2) && (floor || world.loops[$0.loop].inward(ofSegment: $0.segment).dy < -0.9) })
            else { return }
            let tAt = world.loops[seg.loop].t(onSegment: seg.segment, fraction: floor ? fraction : 1 - fraction)
            colony.creatures[i] = Creature(world: world, spot: .init(loop: seg.loop, t: tAt), facingForwards: i % 2 == 0, config: colony.creatures[i].config)
            if still { colony.creatures[i].pause(for: 1e4) }
        }
        func layOut() {
            put(blocky, floor: true, at: 0.40)
            put(boo, floor: true, at: 0.43)
            put(unit, floor: true, at: 0.78, still: false)
            put(sprout, floor: false, at: 0.25)
        }

        let kinds = only.map { [$0] } ?? Weather.Kind.allCases
        var failures: [String] = []
        var stills: [(name: String, rect: CGRect, at: Double)] = []
        var frame = 0
        func film(_ seconds: Double, _ each: (Double) -> Void = { _ in }) async throws {
            let end = t + seconds
            while t < end {
                CATransaction.begin(); CATransaction.setDisableActions(true)
                each(t)
                colony.advance(dt: dt, cursor: away, shift: false)
                CATransaction.commit()
                try await recorder.append(frame: frame, at: t)
                if let k = stills.firstIndex(where: { $0.at <= t }), let whole = recorder.lastFrame() {
                    let s = stills.remove(at: k)
                    if let image = EffectsFilm.crop(whole, s.rect), let png = ShotRenderer.png(image) {
                        let url = output.deletingLastPathComponent().appendingPathComponent(output.deletingPathExtension().lastPathComponent + "-\(s.name).png")
                        try png.write(to: url)
                        log("still \(s.name) → \(url.lastPathComponent)")
                    }
                }
                frame += 1
                t = Double(frame) * dt
            }
        }
        // What the film does between frames goes in a transaction too: a line said outside one (the weather starting)
        // leaves the film's renderer blind to every layer made after it.
        func act(_ what: () -> Void) {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            what()
            CATransaction.commit()
        }
        func expect(_ words: String) { if !seen.contains(where: { $0.contains(words) }) { failures.append("never: \(words)") } }
        let floorY = CGFloat(0)

        for kind in kinds {
            act { colony.resetWeather() }
            layOut()
            seen = []
            try await film(0.5)
            act { colony.startWeather(kind) }
            switch kind {
            case .snow:
                // The snow comes thick for the film: piled by hand a little each frame on top of what falls.
                var reported = 0
                stills.append(("snow-window", CGRect(x: window.minX - 40, y: window.maxY - 90, width: window.width + 80, height: 150), t + 34))
                stills.append(("snow-bottom", CGRect(x: 220, y: floorY, width: 620, height: 200), t + 37.5))
                try await film(38) { now in
                    colony.weather.skies.first?.sky.fillBottom(by: 0.006)
                    colony.weather.skies.first?.sky.fillLedges(by: 0.004)
                    let deep = Int(colony.weather.skies.first?.sky.bottom.average ?? 0)
                    if deep > reported && deep % 2 == 0 {
                        reported = deep; log("snow pile bottom \(deep * 2) px")
                    }
                    if Int(now * 30) % 300 == 0, let top = colony.weather.skies.first?.sky.ledgePile(1) { log(String(format: "snow pile window top %.0f px", top.average * 2)) }
                }
                act { colony.throwSnowball(from: blocky, at: boo) }
                try await film(3)
                // The window moves: its snow falls off as a shower.
                window.origin.x += 140
                placeWindow()
                try await film(4)
                expect("snow falls off a window")
                expect("throws a snowball")
                expect("is hit")
                act { colony.clearWeather() }
                try await film(10)
                log(String(format: "snow pile bottom %.0f px after it eased off (melting)", (colony.weather.skies.first?.sky.bottom.average ?? 0) * 2))
                window.origin.x -= 140
                placeWindow()
            case .rain:
                stills.append(("rain-shared", CGRect(x: 280, y: floorY, width: 420, height: 170), t + 10))
                var fell = false
                try await film(32) { _ in
                    if !fell, case .tipping? = colony.weather.bowls[sprout]?.state {
                        fell = true
                        stills.append(("rain-falling", CGRect(x: 80, y: 200, width: 520, height: 376), t + 1.75))
                    }
                }
                expect("share an umbrella")
                expect("umbrella full, falls")
                expect("lands on the floor")
            case .wind:
                stills.append(("wind", CGRect(x: 150, y: floorY, width: 720, height: 220), t + 10.4))
                try await film(24)
                expect("wind gust")
                expect("pushes")
            case .storm:
                stills.append(("storm", CGRect(x: 280, y: floorY, width: 420, height: 170), t + 10.5))
                try await film(26)
                expect("share an umbrella")
                expect("wind gust")
            }
            expect("weather \(kind.name) starts")
            act { colony.clearWeather() }
            try await film(9)
            expect("eases off")
        }
        try await recorder.finish()
        if !failures.isEmpty { failures.forEach { log("FAILED: " + $0) }; exit(1) }
        print("weather film: \(kinds.map(\.name).joined(separator: ", ")) → \(output.path)")
    }
}

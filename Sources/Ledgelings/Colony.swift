import AppKit
import Combine
import LedgelingsCore
import QuartzCore

/// All the creatures, the monitors they live on, and the one clock that moves them.
@MainActor
final class Colony: NSObject {
    /// Cap on one simulation step, so a stalled display link cannot teleport anyone.
    private static let maxStep: Double = 1.0 / 10

    private let settings: AppSettings
    private let atlas: SpriteAtlas
    private let zFrames: SpriteAtlas.Frames
    private let zCell: CGSize

    /// A bigger body walks further from the screen edge, so each size has its
    /// own outline. Sizes come in half steps, so this stays a handful of entries.
    private var worlds: [Double: EdgeWorld] = [:]
    private var creatures: [Creature] = []
    /// Where each creature sits in the min...max size range, 0...1. Fixed at
    /// birth, so moving the sliders resizes everyone without reshuffling who is big.
    private var sizeShares: [Double] = []
    private var sizes: [Double] = []
    private var asleepFor: [Double] = []
    private var frames: [SpriteAtlas.Frames] = []
    private var frameCache: [RGB: SpriteAtlas.Frames] = [:]
    private var overlays: [ScreenOverlay] = []
    private var rng = SystemRandomNumberGenerator()

    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval?
    /// The creature in the user's hand, and where on its body it was grabbed.
    private var held: (index: Int, grab: CGVector)?
    private var watchers: Set<AnyCancellable> = []

    private(set) var clock: DayNight
    /// One line per talking creature, and when it stops showing.
    private var bubbles: [Int: (text: String, until: Double)] = [:]
    private var nextTalkAt: Double = 0
    private var talking = false
    /// The last thing that happened with the model, for the menu.
    private(set) var talkStatus = "not tried yet"
    private(set) var elapsed: Double = 0

    var isNight: Bool { clock.isNight(at: elapsed) }
    var secondsLeftInPhase: Double { clock.remaining(at: elapsed) }

    init(settings: AppSettings) throws {
        self.settings = settings
        atlas = try SpriteAtlas(named: "blocky")
        let zzz = try SpriteAtlas(named: "zzz")
        zFrames = zzz.frames()
        zCell = zzz.cellSize
        clock = DayNight(day: settings.dayMinutes * 60, night: settings.nightMinutes * 60)
        super.init()

        rebuildOverlays()
        applySettings()
        // `objectWillChange` fires BEFORE the value lands, so read it a turn later.
        settings.objectWillChange.receive(on: RunLoop.main)
            .sink { [weak self] in self?.applySettings() }
            .store(in: &watchers)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    // MARK: Commands

    func startleEveryone() {
        for i in creatures.indices { creatures[i].startle(using: &rng) }
    }

    /// Jump the clock to the next dusk or dawn.
    func skipPhase() { elapsed = clock.skippingToNextPhase(from: elapsed) }

    // MARK: Reacting to change

    private func applySettings() {
        clock = DayNight(day: settings.dayMinutes * 60, night: settings.nightMinutes * 60)
        nextTalkAt = min(nextTalkAt, elapsed + settings.talkEveryMinutes * 60)

        if let held, held.index >= settings.creatureCount { letGo() }
        while creatures.count > settings.creatureCount {
            creatures.removeLast(); asleepFor.removeLast(); sizeShares.removeLast(); sizes.removeLast()
        }
        while creatures.count < settings.creatureCount {
            let share = Double.random(in: 0...1, using: &rng), size = settings.size(forShare: share)
            creatures.append(spawn(size: size)); asleepFor.append(0); sizeShares.append(share); sizes.append(size)
        }
        for i in creatures.indices {
            let size = settings.size(forShare: sizeShares[i])
            guard size != sizes[i] else { continue }
            sizes[i] = size
            creatures[i].rehome(to: world(forSize: size))
            creatures[i].config.fleeRadius = fleeRadius(forSize: size)
        }

        frames = creatures.indices.map { index in
            let colour = settings.color(forCreature: index)
            if let cached = frameCache[colour] { return cached }
            let made = atlas.frames(body: colour)
            frameCache[colour] = made
            return made
        }
        render()
    }

    @objc private func screensChanged() {
        rebuildOverlays()
        worlds.removeAll()
        for i in creatures.indices { creatures[i].rehome(to: world(forSize: sizes[i])) }
        render()
    }

    private func world(forSize size: Double) -> EdgeWorld {
        if let made = worlds[size] { return made }
        let made = EdgeWorld(screens: NSScreen.screens.map(\.frame), inset: atlas.bodyHalfSize * CGFloat(size))
        worlds[size] = made
        return made
    }

    /// Measured from the creature's centre, so a big one needs a bigger bubble
    /// to feel equally skittish.
    private func fleeRadius(forSize size: Double) -> CGFloat {
        atlas.bodyHalfSize * CGFloat(size) + 68
    }

    private func rebuildOverlays() {
        link?.invalidate()
        overlays.forEach { $0.close() }
        overlays = NSScreen.screens.map(ScreenOverlay.init)
        overlays.forEach { $0.view.onHand = { [weak self] in self?.hand($0) } }
        letGo()
        lastTick = nil
        guard let first = overlays.first else { link = nil; return }
        let link = first.view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        setFrameRate(asleep: false)
    }

    private func spawn(size: Double) -> Creature {
        let world = world(forSize: size)
        let places = world.segments
        let place = places.randomElement(using: &rng)!
        let t = world.loops[place.loop].t(onSegment: place.segment, fraction: .random(in: 0.1...0.9, using: &rng))
        var config = Creature.Config()
        config.walkSpeed = .random(in: 38...72, using: &rng)      // no two walk in lockstep
        config.fleeRadius = fleeRadius(forSize: size)
        return Creature(world: world, spot: .init(loop: place.loop, t: t),
                        facingForwards: .random(using: &rng), config: config)
    }

    // MARK: Talk

    private static let edgeNames: [(Double, String)] = [(0, "the bottom edge"), (.pi / 2, "the right edge"),
                                                        (.pi, "the ceiling"), (3 * .pi / 2, "the left edge")]
    private func edgeName(_ c: Creature) -> String {
        Self.edgeNames.min {
            abs(Creature.shortestArc(from: c.rotation, to: $0.0)) < abs(Creature.shortestArc(from: c.rotation, to: $1.0))
        }!.1
    }

    private func describe(_ i: Int) -> String {
        let c = creatures[i], name = settings.character(forCreature: i).name
        if c.isHeld { return "\(name) is dangling from the user's cursor" }
        if c.isJumping { return "\(name) is mid-jump" }
        return "\(name) is \(c.isSleeping ? "asleep on" : "on") \(edgeName(c))"
    }

    /// One creature says a line to another; the other answers. Runs in the background.
    func talkNow() {
        guard creatures.count >= 2 else { talkStatus = "needs at least two creatures"; return }
        guard !talking else { return }
        guard let url = settings.talkServerURL else { talkStatus = "bad server address"; return }
        let awake = creatures.indices.filter { !creatures[$0].isSleeping && !creatures[$0].isJumping }
        guard let speaker = (awake.isEmpty ? Array(creatures.indices) : awake).randomElement(using: &rng) else { return }
        let me = creatures[speaker].position
        let listener = creatures.indices.filter { $0 != speaker }.min {
            hypot(creatures[$0].position.x - me.x, creatures[$0].position.y - me.y)
                < hypot(creatures[$1].position.x - me.x, creatures[$1].position.y - me.y)
        }!

        let a = settings.character(forCreature: speaker), b = settings.character(forCreature: listener)
        let situation = "It is \(isNight ? "night" : "day"). \(describe(speaker)). \(describe(listener))."
        var vars = ["speaker": a.name, "speakerPersona": a.persona, "listener": b.name,
                    "listenerPersona": b.persona, "situation": situation, "line": ""]
        let service = TalkService(baseURL: url, model: settings.talkModel)
        let system = settings.systemPrompt, linePrompt = settings.linePrompt, replyPrompt = settings.replyPrompt

        talking = true
        talkStatus = "asking \(settings.talkModel)…"
        Task { [weak self] in
            defer { self?.talking = false }
            do {
                try await service.checkModel()
                let first = Banter.cleanLine(
                    try await service.line(system: Banter.render(system, vars), user: Banter.render(linePrompt, vars)),
                    speaker: a.name)
                guard let self else { return }
                guard !first.isEmpty else { talkStatus = "the model sent an empty line"; return }
                say(first, from: speaker)
                talkStatus = "\(a.name): \(first)"

                // Swap seats for the answer.
                vars["speaker"] = b.name; vars["speakerPersona"] = b.persona
                vars["listener"] = a.name; vars["listenerPersona"] = a.persona; vars["line"] = first
                let reply = Banter.cleanLine(
                    try await service.line(system: Banter.render(system, vars), user: Banter.render(replyPrompt, vars)),
                    speaker: b.name)
                try await Task.sleep(for: .seconds(Self.showTime(first) * 0.6))
                guard !reply.isEmpty else { return }
                say(reply, from: listener)
                talkStatus = "\(b.name): \(reply)"
            } catch {
                self?.talkStatus = "\(error)"
                FileHandle.standardError.write(Data("Ledgelings talk: \(error)\n".utf8))
            }
        }
    }

    private static func showTime(_ text: String) -> Double {
        min(14, 3.5 + Double(text.split(separator: " ").count) * 0.45)
    }

    private func say(_ text: String, from index: Int) {
        guard creatures.indices.contains(index) else { return }
        bubbles[index] = (text, elapsed + Self.showTime(text))
        render()
    }

    // MARK: The user's hand

    /// The topmost creature whose body is under `point`.
    private func creature(at point: CGPoint) -> Int? {
        creatures.indices.reversed().first { i in
            let half = atlas.bodyHalfSize * CGFloat(sizes[i]) + 4      // a little forgiveness
            let p = creatures[i].position
            return abs(point.x - p.x) <= half && abs(point.y - p.y) <= half
        }
    }

    /// Shift-click naps or wakes. A plain press on a sleeper picks it up.
    private func hand(_ event: HandEvent) {
        switch event {
        case .down(let point, let shift):
            guard let i = creature(at: point) else { return }
            if shift {
                creatures[i].toggleNap(using: &rng)
            } else if creatures[i].pickUp() {
                let p = creatures[i].position
                held = (i, CGVector(dx: p.x - point.x, dy: p.y - point.y))
            }
        case .dragged(let point):
            guard let held else { return }
            creatures[held.index].drag(to: CGPoint(x: point.x + held.grab.dx, y: point.y + held.grab.dy))
        case .up:
            letGo()
        }
        render()      // follow the hand at the mouse's rate, not the display link's
    }

    private func letGo() {
        if let held, creatures.indices.contains(held.index) { creatures[held.index].drop() }
        held = nil
    }

    /// Make an overlay clickable only while the cursor is on something the user
    /// can act on: any sleeper, or any creature at all while Shift is down.
    private func updateClickability(cursor: CGPoint, shift: Bool) {
        let target = held != nil || creature(at: cursor).map { shift || creatures[$0].isSleeping } == true
        for overlay in overlays { overlay.setClickable(target && overlay.screen.frame.contains(cursor)) }
    }

    // MARK: The frame

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { lastTick = now }
        guard let last = lastTick else { return }
        let dt = min(now - last, Self.maxStep)
        elapsed += dt

        let night = isNight
        let cursor = NSEvent.mouseLocation          // global, and needs no permission
        // Holding Shift calms them: nobody flees, so you can get close enough to click.
        let shift = NSEvent.modifierFlags.contains(.shift)
        for i in creatures.indices {
            creatures[i].update(dt: dt, cursor: shift ? nil : cursor, isNight: night, using: &rng)
            asleepFor[i] = creatures[i].looksAsleep ? asleepFor[i] + dt : 0
        }
        updateClickability(cursor: cursor, shift: shift)

        for (i, bubble) in bubbles where bubble.until <= elapsed || i >= creatures.count { bubbles.removeValue(forKey: i) }
        if settings.talkEnabled, settings.talkEveryMinutes > 0, elapsed >= nextTalkAt {
            nextTalkAt = elapsed + settings.talkEveryMinutes * 60
            if elapsed > 1 { talkNow() }     // not on the very first tick
        }
        render()
        setFrameRate(asleep: held == nil && !creatures.isEmpty && creatures.allSatisfy(\.isSleeping))
    }

    /// A sleeping colony only breathes and floats Zs: 12 fps is plenty.
    private func setFrameRate(asleep: Bool) {
        let top: Float = asleep ? 12 : 30
        let wanted = CAFrameRateRange(minimum: min(10, top), maximum: top, preferred: top)
        if link?.preferredFrameRateRange != wanted { link?.preferredFrameRateRange = wanted }
    }

    private func render() {
        let snapshots = creatures.indices.map { i in
            let c = creatures[i]
            return CreatureSnapshot(
                position: c.position, rotation: c.rotation, isMirrored: c.isMirrored,
                image: frames[i].frame(animation: c.animation, time: c.animationTime, eyes: c.eyes),
                scale: CGFloat(sizes[i]),
                asleepFor: c.looksAsleep ? asleepFor[i] : nil,
                inward: c.isHeld ? CGVector(dx: 0, dy: 1) : c.loop.inward(ofSegment: c.segment),
                bubble: bubbles[i]?.text
            )
        }
        let z = zFrames.frame(animation: "float", time: 0)
        for overlay in overlays {
            overlay.render(snapshots, z: z, cell: atlas.cellSize, zCell: zCell)
        }
    }
}

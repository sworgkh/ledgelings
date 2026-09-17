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
                asleepFor: c.looksAsleep ? asleepFor[i] : nil
            )
        }
        let z = zFrames.frame(animation: "float", time: 0)
        for overlay in overlays {
            overlay.render(snapshots, z: z, cell: atlas.cellSize, zCell: zCell)
        }
    }
}

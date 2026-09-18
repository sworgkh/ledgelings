import AppKit
import Combine
import LedgelingsCore
import QuartzCore

/// All the creatures, the monitors they live on, and the one clock that moves them.
@MainActor
final class Colony: NSObject {
    /// Cap on one simulation step, so a stalled display link cannot teleport anyone.
    static let maxStep: Double = 1.0 / 10

    let settings: AppSettings
    /// Every conversation, written to disk as it ends.
    let history: ChatHistory
    let atlas: SpriteAtlas
    let zFrames: SpriteAtlas.Frames
    let zCell: CGSize
    let flowerFrames: SpriteAtlas.Frames
    let flowerCell: CGSize
    let houseFrames: SpriteAtlas.Frames
    let houseCell: CGSize

    /// A bigger body walks further from the screen edge, so each size has its
    /// own outline. Sizes come in half steps, so this stays a handful of entries.
    var worlds: [Double: EdgeWorld] = [:]
    var creatures: [Creature] = []
    /// Where each creature sits in the min...max size range, 0...1. Fixed at
    /// birth, so moving the sliders resizes everyone without reshuffling who is big.
    var sizeShares: [Double] = []
    var sizes: [Double] = []
    var asleepFor: [Double] = []
    var frames: [SpriteAtlas.Frames] = []
    var frameCache: [RGB: SpriteAtlas.Frames] = [:]
    var overlays: [ScreenOverlay] = []
    var rng = SystemRandomNumberGenerator()

    var link: CADisplayLink?
    var lastTick: CFTimeInterval?
    /// The creature in the user's hand, and where on its body it was grabbed.
    var held: (index: Int, grab: CGVector)?
    var watchers: Set<AnyCancellable> = []

    var clock: DayNight
    /// One line per talking creature, and when it stops showing.
    var bubbles: [Int: (text: String, until: Double)] = [:]
    /// Creatures in a running conversation: a bump or a poke involving them waits.
    var busy: Set<Int> = []
    /// Who has walked into whom, and how often.
    var meetings = Meetings()
    /// Flowers in the air and on heads.
    var gifts = Gifts()
    /// A Shift-press on a creature that has not moved yet: a poke if it lets go, a carry if it drags.
    var poke: (index: Int, at: CGPoint)?
    static let dragThreshold: CGFloat = 4
    /// Every pair stopped face to face right now. `releaseAt` is nil while the words are still coming.
    var chats: [Conversation] = []
    /// Pixel stars from the last bump, and the colours they wear.
    var sparks = Sparks()
    var sparkPalette: [CGColor] = []
    /// The house they hide in when asked to go away for a while.
    var hideout = Hideout()
    /// Creatures shrinking into the doorway, and creatures growing out of it, by when they started.
    var entering: [Int: Double] = [:]
    var leaving: [Int: Double] = [:]
    /// The last thing that happened with the model, for the menu.
    var talkStatus = "not tried yet"
    var elapsed: Double = 0

    var isNight: Bool { clock.isNight(at: elapsed) }
    var secondsLeftInPhase: Double { clock.remaining(at: elapsed) }

    init(settings: AppSettings, history: ChatHistory) throws {
        self.settings = settings
        self.history = history
        atlas = try SpriteAtlas(named: "blocky")
        let zzz = try SpriteAtlas(named: "zzz")
        zFrames = zzz.frames()
        zCell = zzz.cellSize
        let flowers = try SpriteAtlas(named: "flowers")
        flowerFrames = flowers.frames()
        flowerCell = flowers.cellSize
        let house = try SpriteAtlas(named: "house")
        houseFrames = house.frames()
        houseCell = house.cellSize
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

    func applySettings() {
        clock = DayNight(day: settings.dayMinutes * 60, night: settings.nightMinutes * 60)

        if let held, held.index >= settings.creatureCount { letGo() }
        while creatures.count > settings.creatureCount {
            creatures.removeLast(); asleepFor.removeLast(); sizeShares.removeLast(); sizes.removeLast()
        }
        gifts.forget(creaturesFrom: creatures.count)
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

    @objc func screensChanged() {
        rebuildOverlays()
        worlds.removeAll()
        for i in creatures.indices { creatures[i].rehome(to: world(forSize: sizes[i])) }
        render()
    }

    func world(forSize size: Double) -> EdgeWorld {
        if let made = worlds[size] { return made }
        let made = EdgeWorld(screens: NSScreen.screens.map(\.frame), inset: atlas.bodyHalfSize * CGFloat(size))
        worlds[size] = made
        return made
    }

    /// Measured from the creature's centre, so a big one needs a bigger bubble
    /// to feel equally skittish.
    func fleeRadius(forSize size: Double) -> CGFloat {
        atlas.bodyHalfSize * CGFloat(size) + 68
    }

    func rebuildOverlays() {
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

    func spawn(size: Double) -> Creature {
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

    // MARK: The frame

    @objc func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { lastTick = now }
        guard let last = lastTick else { return }
        let dt = min(now - last, Self.maxStep)
        elapsed += dt

        let night = isNight
        let cursor = NSEvent.mouseLocation          // global, and needs no permission
        // Holding Shift calms them: nobody flees, so you can get close enough to click.
        let shift = NSEvent.modifierFlags.contains(.shift)
        for i in creatures.indices where !hideout.isInside(i) {
            creatures[i].update(dt: dt, cursor: shift || hideout.isActive ? nil : cursor, isNight: night, using: &rng)
            asleepFor[i] = creatures[i].looksAsleep ? asleepFor[i] + dt : 0
        }
        updateHideout()
        updateClickability(cursor: cursor, shift: shift)

        for (i, bubble) in bubbles where bubble.until <= elapsed || i >= creatures.count { bubbles.removeValue(forKey: i) }
        gifts.update(at: elapsed, wearFor: settings.flowerMinutes * 60)
        sparks.update(dt: dt)
        releaseChatIfOver()
        for bump in meetings.update(parties(), at: elapsed) { bumped(bump) }
        render()
        setFrameRate(asleep: hideout.phase == .hidden || (held == nil && !creatures.isEmpty && creatures.allSatisfy(\.isSleeping)))
    }

    /// A sleeping colony only breathes and floats Zs: 12 fps is plenty.
    func setFrameRate(asleep: Bool) {
        let top: Float = asleep ? 12 : 30
        let wanted = CAFrameRateRange(minimum: min(10, top), maximum: top, preferred: top)
        if link?.preferredFrameRateRange != wanted { link?.preferredFrameRateRange = wanted }
    }

    func render() {
        let snapshots = creatures.indices.map { i in
            let c = creatures[i]
            let shrink = doorShrink(of: i)
            let inward = c.isHeld ? CGVector(dx: 0, dy: 1) : c.loop.inward(ofSegment: c.segment)
            // Shrinking, it keeps its feet on the floor: the centre sinks as the body gets smaller.
            let sink = atlas.bodyHalfSize * CGFloat(sizes[i]) * (1 - shrink)
            return CreatureSnapshot(
                position: CGPoint(x: c.position.x - inward.dx * sink, y: c.position.y - inward.dy * sink),
                rotation: c.rotation, isMirrored: c.isMirrored,
                image: frames[i].frame(animation: c.animation, time: c.animationTime, eyes: c.eyes),
                scale: CGFloat(sizes[i]),
                asleepFor: c.looksAsleep ? asleepFor[i] : nil,
                inward: c.isHeld ? CGVector(dx: 0, dy: 1) : c.loop.inward(ofSegment: c.segment),
                bubble: bubbles[i]?.text,
                hat: gifts.hat(of: i).flatMap { flowerFrames.frame(animation: $0, time: 0) },
                hidden: hideout.isInside(i),
                shrink: shrink
            )
        }
        let z = zFrames.frame(animation: "float", time: 0)
        let inFlight = flightSnapshot(), stars = sparkSnapshots(), home = houseSnapshot()
        for overlay in overlays {
            overlay.render(snapshots, z: z, cell: atlas.cellSize, zCell: zCell, flowerCell: flowerCell,
                           flight: inFlight, sparks: stars, house: home, houseCell: houseCell)
        }
    }
}

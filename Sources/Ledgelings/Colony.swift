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
    /// The built-in and imported creature sheets.
    let library: SpriteLibrary
    let spend: SpendLedger
    /// Who has lived beside whom, how they get on, and the story between them.
    let bonds: BondBook
    /// What the user asked to be reminded of, and when.
    let reminders: ReminderBook
    /// Pairs whose next plot is being written, by `Bonds.key`.
    var plotting: Set<String> = []
    /// Time together not yet added to the bonds; they are saved every half minute, not every frame.
    var togetherPending = 0.0
    /// The built-in sheet: every sheet shares its cell and body box, so it is the geometry for all.
    let atlas: SpriteAtlas
    let zFrames: SpriteAtlas.Frames
    let zCell: CGSize
    let flowerFrames: SpriteAtlas.Frames
    let flowerCell: CGSize
    let houseFrames: SpriteAtlas.Frames
    let houseCell: CGSize
    /// The paper plane, and the letter it opens into.
    let planeFrames: SpriteAtlas.Frames
    let planeCell: CGSize

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
    var frameCache: [String: SpriteAtlas.Frames] = [:]
    var overlays: [ScreenOverlay] = []
    var rng = SystemRandomNumberGenerator()
    /// The virtual display when rendering offscreen; nil when live on the monitors.
    let stage: Display?
    var displays: [Display] { stage.map { [$0] } ?? Display.attached }

    var link: CADisplayLink?
    var lastTick: CFTimeInterval?
    /// The creature in the user's hand, and where on its body it was grabbed.
    var held: (index: Int, grab: CGVector)?
    var watchers: Set<AnyCancellable> = []

    var clock: DayNight
    /// The user's wall clock, for what the creatures know of the day (`Almanac`); tests set it.
    var now: () -> Date = Date.init
    /// One line per talking creature: what it says, when it stops showing, and
    /// how much of it is on show while it is being said out loud.
    struct Bubble {
        var text: String
        var until: Double
        var reveal: SpeechReveal = .all
        /// Which `say` put it up, so a late word from the voice about an older line is ignored.
        var serial = 0
    }
    var bubbles: [Int: Bubble] = [:]
    var bubbleSerial = 0
    /// Lines being said out loud, by serial, and what waits for each to end.
    var voicedLines: Set<Int> = []
    var afterLine: [Int: [() -> Void]] = [:]
    /// Conversations being said out loud right now. There is one voice to go
    /// round, so out loud there is one conversation at a time.
    var voicedDialogues = 0
    /// `--converse`: every line and voice cue, as it happens.
    var trace: ((String) -> Void)?
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
    /// How often each creature has been chased or carried lately; too often and it complains.
    var annoyance = Annoyance()
    /// Creatures whose complaint the model is writing.
    var complaining: Set<Int> = []
    /// Pixel stars from the last bump, and the colours they wear.
    var sparks = Sparks()
    var sparkPalette: [CGColor] = []
    /// The house they hide in when asked to go away for a while.
    var hideout = Hideout()
    /// Creatures shrinking into the doorway, and creatures growing out of it, by when they started.
    var entering: [Int: Double] = [:]
    var leaving: [Int: Double] = [:]
    /// Lines from the built-in script still to be said, by when.
    var scheduled: [ScheduledLine] = []
    /// The script conversations used lately, oldest first, so the same one is not heard twice running.
    var recentLines: [Int] = []
    /// The paper plane in the air, or being read; one at a time.
    var airmail: Airmail?
    /// How many planes have gone up, so a late model answer finds the right one.
    var planeCount = 0
    /// Counts the time since the last plane, to know when the next is due.
    var post = Post(quietFor: 0)
    /// An answer owed once a letter has been read.
    var replyDue: ReplyDue?
    /// Creatures holding an open letter.
    var letters: [Int: Bool] = [:]
    /// The reminder on its way to the user, or open on the screen; one at a time.
    var delivery: Delivery?
    /// Reminders that came due while another was being delivered, oldest first.
    var deliveryQueue: [Reminders.Reminder] = []
    /// How many reminders have gone up, so a late model answer finds the right one.
    var deliveryCount = 0
    /// Reminders are looked at once a second, not every frame.
    var nextReminderCheck = 0.0
    /// Seconds since the user last touched the mouse or keyboard; an open letter waits for them.
    var userIdleSeconds: () -> Double = {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
    /// Reads every line out loud when voice is on. Nil offscreen (the promo).
    var voice: Voice? {
        didSet {
            voice?.cast = { [weak self] in self.map { c in c.creatures.indices.map { c.character(forCreature: $0).name } } ?? [] }
            voice?.describe = { [weak self] name in
                guard let c = self, let i = c.creatures.indices.first(where: { c.character(forCreature: $0).name == name }) else { return nil }
                return (c.character(forCreature: i).persona, c.kind(ofCreature: i))
            }
        }
    }
    /// The last thing that happened with the model, for the menu.
    var talkStatus = "not tried yet"
    var elapsed: Double = 0

    var isNight: Bool { clock.isNight(at: elapsed) }
    var secondsLeftInPhase: Double { clock.remaining(at: elapsed) }

    /// `stage`: draw for this one virtual display, offscreen, stepped by hand
    /// (the promo). Nil means the attached monitors, live.
    init(settings: AppSettings, history: ChatHistory, library: SpriteLibrary, spend: SpendLedger,
         bonds: BondBook? = nil, reminders: ReminderBook? = nil, stage: Display? = nil) throws {
        self.settings = settings
        self.history = history
        self.library = library
        self.spend = spend
        self.bonds = bonds ?? BondBook(directory: spend.ledger.directory)
        self.reminders = reminders ?? ReminderBook(directory: spend.ledger.directory)
        self.stage = stage
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
        let plane = try SpriteAtlas(named: "plane")
        planeFrames = plane.frames()
        planeCell = plane.cellSize
        clock = DayNight(day: settings.dayMinutes * 60, night: settings.nightMinutes * 60)
        super.init()

        rebuildOverlays()
        applySettings()
        // `objectWillChange` fires BEFORE the value lands, so read it a turn later.
        settings.objectWillChange.receive(on: RunLoop.main)
            .sink { [weak self] in self?.applySettings() }
            .store(in: &watchers)
        library.objectWillChange.receive(on: RunLoop.main)
            .sink { [weak self] in self?.frameCache.removeAll(); self?.applySettings() }
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
        settings.keepSpecies(among: library.species.map(\.name))
        history.remember(settings.lineMemory)

        if let held, held.index >= settings.creatureCount { letGo() }
        while creatures.count > settings.creatureCount {
            creatures.removeLast(); asleepFor.removeLast(); sizeShares.removeLast(); sizes.removeLast()
        }
        gifts.forget(creaturesFrom: creatures.count)
        annoyance.forget(creaturesFrom: creatures.count)
        annoyance.limit = settings.complainAfter
        annoyance.calmAfter = settings.complainCalmSeconds
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
            let name = settings.species(forCreature: index)
            let colour = library.bodyColour(of: name, slot: settings.color(forCreature: index))
            let key = "\(name) \(colour.hex)"
            if let cached = frameCache[key] { return cached }
            let made = (library.atlas(named: name) ?? atlas).frames(body: colour)
            frameCache[key] = made
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
        let made = EdgeWorld(screens: displays.map(\.frame), inset: atlas.bodyHalfSize * CGFloat(size))
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
        let hosted = stage == nil
        overlays = displays.map { ScreenOverlay(display: $0, hosted: hosted) }
        overlays.forEach { $0.view?.onHand = { [weak self] in self?.hand($0) } }
        letGo()
        lastTick = nil
        guard let view = overlays.first?.view else { link = nil; return }
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
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
        // Holding Shift calms them: nobody flees, so you can get close enough to click.
        advance(dt: min(now - last, Self.maxStep), cursor: NSEvent.mouseLocation, shift: NSEvent.modifierFlags.contains(.shift))
    }

    /// One step of the world: `dt` seconds with the cursor at `cursor` (global points).
    func advance(dt: Double, cursor: CGPoint, shift: Bool) {
        elapsed += dt
        let night = isNight
        for i in creatures.indices where !hideout.isInside(i) {
            if creatures[i].update(dt: dt, cursor: shift || hideout.isActive ? nil : cursor, isNight: night, using: &rng) {
                bothered(i)
            }
            asleepFor[i] = creatures[i].looksAsleep ? asleepFor[i] + dt : 0
        }
        updateHideout()
        updateClickability(cursor: cursor, shift: shift)

        for (i, bubble) in bubbles where bubble.until <= elapsed || i >= creatures.count {
            bubbles.removeValue(forKey: i)
            trace?("bubble #\(bubble.serial) gone")
            // A voiced line that gave up waiting for its sound still ends its turn.
            if voicedLines.contains(bubble.serial) { endLine(bubble.serial) }
        }
        gifts.update(at: elapsed, wearFor: settings.flowerMinutes * 60)
        if settings.followGiver { followGivers() }
        sparks.update(dt: dt)
        sayScheduledLines()
        releaseChatIfOver()
        for bump in meetings.update(parties(), at: elapsed) { bumped(bump) }
        updatePost(dt: dt)
        updateReminders(dt: dt)
        liveTogether(dt: dt)
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
            let shown = bubbles[i].map { $0.reveal.shown($0.text, at: elapsed) }
            return CreatureSnapshot(
                position: CGPoint(x: c.position.x - inward.dx * sink, y: c.position.y - inward.dy * sink),
                rotation: c.rotation, isMirrored: c.isMirrored,
                image: frames[i].frame(animation: c.animation, time: c.animationTime, eyes: c.eyes),
                scale: CGFloat(sizes[i]),
                asleepFor: c.looksAsleep ? asleepFor[i] : nil,
                inward: c.isHeld ? CGVector(dx: 0, dy: 1) : c.loop.inward(ofSegment: c.segment),
                bubble: shown?.text,
                bubbleShare: shown?.share ?? 1,
                hat: gifts.hat(of: i).flatMap { flowerFrames.frame(animation: $0, time: 0) },
                hidden: hideout.isInside(i),
                shrink: shrink,
                letter: letterImage(for: i)
            )
        }
        let z = zFrames.frame(animation: "float", time: 0)
        let inFlight = flightSnapshot(), stars = sparkSnapshots(), home = houseSnapshot(), plane = planeSnapshot()
        let reminder = reminderSnapshot()
        for overlay in overlays {
            overlay.render(snapshots, z: z, cell: atlas.cellSize, zCell: zCell, flowerCell: flowerCell,
                           flight: inFlight, sparks: stars, house: home, houseCell: houseCell,
                           plane: plane, planeCell: planeCell, reminder: reminder)
        }
    }
}

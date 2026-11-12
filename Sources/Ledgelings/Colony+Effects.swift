import AppKit
import LedgelingsCore

/// What the effects keep between frames (`Colony+Effects`).
@MainActor
final class EffectsState {
    var rules = Effects.Rules()
    /// The effect each creature is wearing or marking, by index: one at a time.
    var on: [Int: EffectPlayer] = [:]
    /// Effects standing on their own at a place: a creature that went in a poof.
    var loose: [(player: EffectPlayer, place: CGPoint, rotation: Double, scale: CGFloat, mirrored: Bool)] = []
    /// The season's particles or the fireflies along each home monitor's bottom edge, a tile at a time.
    var ambient: (moment: Effects.Moment, tiles: [EffectPlayer])?
    var ambientImages: [CGImage?] = []
    var ambientNextDraw = 0.0
    let actors = EffectActors()
    /// The colony's clock when each creature last met anyone: left alone too long, it may frost over.
    var metAt: [Int: Double] = [:]
    var typing = Effects.TypingWatch()
    var nextSample = 0.0
    var nextNowAndThen = 0.0
    /// The day the coins last dropped, so they drop once a day.
    var coinsDay = ""
    /// Meetings already ticked for, by their identifier.
    var meetingsTicked: Set<String> = []
    var seedCounter = 0.0
    /// Where each creature in the air took off from, to know a hard landing when it comes down.
    var airFrom: [Int: CGFloat] = [:]
    /// The Mac's calendar, once "Look at my calendar" is on.
    let meetings = MeetingWatch()
    /// The species the colony has had, so a new one is noticed when it joins; nil until the first look.
    var knownSpecies: Set<String>?
    /// Translate is waiting for its answer (`TranslateSheet` sets it).
    var translating = false
    /// `--effects-film` and `--effect`: every effect started, as it starts.
    var trace: ((String) -> Void)?
}

/// The effects the creatures wear and the moments they mark (SPEC §7.19): styles that come and go, moments
/// tied to the features, and the season's particles along the bottom edge. Every one passes `Effects.Rules`:
/// its switch, Reduce motion and its cooldown. The overlay stays click-through: effects are only drawn.
extension Colony {
    /// Effects drawn at this many frames a second at most: the screen's other frames show the last picture.
    static let effectsFPS = 30.0

    var reduceMotionFromSystem: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// The switches as they stand, read every frame (cheap) so a change applies at once.
    func refreshEffectSwitches() {
        let s = settings.effectSwitches(systemReduceMotion: reduceMotionFromSystem)
        if fx.rules.switches != s { fx.rules.switches = s }
        // Switched off: whatever it was showing goes.
        for (_, p) in fx.on where !p.byHand && (!(p.style.map(s.allows) ?? true) || !(p.moment.map(s.allows) ?? true)) { p.instance.stop() }
        if let a = fx.ambient, !s.allows(a.moment), a.tiles.first?.byHand != true { a.tiles.forEach { $0.instance.stop() } }
    }

    // MARK: Starting one

    /// A style goes on `i` for `effectStyleSeconds`, unless something else is showing on it.
    @discardableResult
    func wear(_ style: Effects.Style, on i: Int, byHand: Bool = false) -> Bool {
        guard creatures.indices.contains(i), !hideout.isInside(i) else { return false }
        if let now = fx.on[i], now.moment != nil, !now.done, !byHand { return false }
        guard let player = makePlayer(style.effect, on: i, style: style) else { return false }
        player.until = elapsed + settings.effectStyleSeconds
        player.byHand = byHand
        fx.on[i] = player
        fx.trace?(String(format: "fx %.2f %@ on %@", elapsed, style.name, character(forCreature: i).name))
        return true
    }

    /// Something that may put a style on `i` happened: the rules roll for it.
    func styleTrigger(_ trigger: Effects.Trigger, on i: Int) {
        guard creatures.indices.contains(i) else { return }
        guard let style = fx.rules.style(for: trigger, creature: i, now: elapsed, roll: Double.random(in: 0..<1, using: &rng)) else { return }
        wear(style, on: i)
    }

    /// A moment happened to `i`: its effect plays if the rules let it.
    func mark(_ moment: Effects.Moment, on i: Int) {
        guard creatures.indices.contains(i), !hideout.isInside(i) else { return }
        guard fx.rules.moment(moment, creature: i, now: elapsed) else { return }
        play(moment, on: i)
    }

    /// A moment's effect on `i` now, rules or not (the settings' preview).
    @discardableResult
    func play(_ moment: Effects.Moment, on i: Int, byHand: Bool = true) -> Bool {
        if moment.ambient { return startAmbient(moment, preview: true) }
        guard let player = makePlayer(moment.effect, on: i, moment: moment) else { return false }
        // The newcomer is inside the egg until it pops (pixelfx's egg-hatch pops at 1.98 s).
        if moment == .newArrival { player.hiddenUntil = 1.98 }
        if byHand && moment.held {
            // A loop shown by hand plays a while, a one-shot once.
            player.byHand = true
            player.until = elapsed + max(6, player.instance.meta.loop ? 6 : player.instance.meta.duration)
        }
        fx.on[i] = player
        fx.trace?(String(format: "fx %.2f moment %@ %@", elapsed, moment.rawValue, character(forCreature: i).name))
        return true
    }

    /// The settings' and the scripts' way in: a style's or a moment's name (or a pixelfx id) on creature
    /// `i`, or on someone on screen. False when there is nobody to show it on.
    @discardableResult
    func preview(_ name: String, on i: Int? = nil) -> Bool {
        let who = i ?? previewCreature()
        if let style = Effects.Style(rawValue: name) ?? Effects.Style.allCases.first(where: { $0.effect == name }) {
            guard let who else { return false }
            return wear(style, on: who, byHand: true)
        }
        if let moment = Effects.Moment(rawValue: name) ?? Effects.Moment.allCases.first(where: { $0.effect == name }) {
            if moment.ambient { return startAmbient(moment, preview: true) }
            guard let who else { return false }
            return play(moment, on: who)
        }
        return false
    }

    /// Someone awake, on screen and not in the house; anyone at all failing that.
    func previewCreature() -> Int? {
        let free = creatures.indices.filter { !hideout.isInside($0) && !creatures[$0].looksAsleep && fx.on[$0] == nil }
        return free.randomElement(using: &rng) ?? creatures.indices.first { !hideout.isInside($0) }
    }

    private func makePlayer(_ name: String, on i: Int, style: Effects.Style? = nil, moment: Effects.Moment? = nil) -> EffectPlayer? {
        guard let type = FXCatalog.all[name], let standing = frames[i].frame(animation: "idle", time: 0),
              let (actor, box) = fx.actors.actor(standing: standing) else { return nil }
        fx.seedCounter += 1
        return EffectPlayer(type, name: name, actor: actor, box: box, seed: 3 + fx.seedCounter, style: style, moment: moment)
    }

    // MARK: Every frame

    func updateEffects(dt: Double) {
        refreshEffectSwitches()
        for (i, p) in fx.on {
            guard creatures.indices.contains(i) else { fx.on.removeValue(forKey: i); continue }
            p.instance.update(dt)
            if let until = p.until, elapsed >= until { p.instance.stop() }
            if p.done { fx.on.removeValue(forKey: i) }
        }
        for k in fx.loose.indices.reversed() {
            fx.loose[k].player.instance.update(dt)
            if fx.loose[k].player.done { fx.loose.remove(at: k) }
        }
        updateHeldMoments()
        updateLandings()
        updateAmbient(dt: dt)
        updateNowAndThen()
    }

    /// Points dropped before a landing on the floor counts as hard: down from the menu bar or a window top.
    static let hardDrop: CGFloat = 240

    /// A jump or a drop that ends on the floor far below where it started: dust flies.
    private func updateLandings() {
        for i in creatures.indices {
            let c = creatures[i]
            switch c.animation {
            case "jump" where !c.isPlaying:
                if fx.airFrom[i] == nil { fx.airFrom[i] = c.position.y }
            case "land":
                if let from = fx.airFrom.removeValue(forKey: i), from - c.position.y > Self.hardDrop,
                   c.loop.inward(ofSegment: c.segment).dy > 0.9 { mark(.hardLanding, on: i) }
            default:
                if !c.isHeld { fx.airFrom.removeValue(forKey: i) }
            }
        }
    }

    /// Asleep, listening, translating: shown for as long as they last, played again when a one-shot ends.
    private func updateHeldMoments() {
        let s = fx.rules.switches
        for i in creatures.indices {
            let wanted: Effects.Moment? = {
                if dictationHelp?.index == i, case .listening = dictationHelp?.stage { return .listening }
                if fx.translating, clipHelp?.index == i, case .holding = clipHelp?.stage { return .translating }
                if creatures[i].looksAsleep && !hideout.isInside(i) { return .asleep }
                return nil
            }()
            let current = fx.on[i]
            if let held = current?.moment, held.held, held != wanted, current?.byHand != true { current?.instance.stop() }
            guard let wanted, s.allows(wanted) else { continue }
            if current?.moment == wanted && current?.instance.stopping == false { continue }
            // A one-shot moment or a style showing now finishes first; a stopping one gives way.
            if let current, current.byHand || (current.moment != wanted && !current.instance.stopping && current.moment?.held != true) { continue }
            play(wanted, on: i, byHand: false)
        }
    }

    /// The fireflies after dark, or the season's particles, for a while every so often.
    private func updateAmbient(dt: Double) {
        let want = Effects.ambient(at: now(), isNight: isNight, switches: fx.rules.switches)
        let out = Effects.ambientShowing(at: elapsed, seconds: settings.effectsAmbientSeconds, everyMinutes: settings.effectsAmbientEveryMinutes)
        if let a = fx.ambient {
            let byHand = a.tiles.first?.byHand == true
            if byHand, let until = a.tiles.first?.until, elapsed >= until { a.tiles.forEach { $0.instance.stop() } }
            if !byHand && (a.moment != want || !out) { a.tiles.forEach { $0.instance.stop() } }
            a.tiles.forEach { $0.instance.update(dt) }
            if a.tiles.allSatisfy(\.done) { fx.ambient = nil; fx.ambientImages = [] }
        } else if let want, out {
            startAmbient(want, preview: false)
        }
    }

    /// Tiles across every home monitor's bottom edge, each with its own seed.
    @discardableResult
    func startAmbient(_ moment: Effects.Moment, preview: Bool) -> Bool {
        guard let type = FXCatalog.all[moment.effect], let standing = frames.first?.frame(animation: "idle", time: 0),
              let (actor, box) = fx.actors.actor(standing: standing) else { return false }
        let tileWidth = CGFloat(type.meta.size.w) * Self.ambientScale
        let count = homeFrames.reduce(0) { $0 + Int(($1.width / tileWidth).rounded(.up)) }
        let tiles = (0..<max(1, count)).map { k -> EffectPlayer in
            let p = EffectPlayer(type, name: moment.effect, actor: actor, box: box, seed: 11 + Double(k) * 7, moment: moment)
            p.instance.dropBackdrop()
            if preview { p.until = elapsed + 6; p.byHand = true }
            return p
        }
        fx.ambient = (moment, tiles)
        fx.trace?(String(format: "fx %.2f moment %@ along the bottom, %d tiles", elapsed, moment.rawValue, tiles.count))
        return true
    }

    /// Screen points per pixel of the ambient particles.
    static let ambientScale: CGFloat = 2

    /// Winter frost and Halloween now and then; frost on whoever was left alone too long; a fast hour of typing.
    private func updateNowAndThen() {
        guard elapsed >= fx.nextNowAndThen else { return }
        let step = 30.0
        fx.nextNowAndThen = elapsed + step
        let today = now()
        let awake = creatures.indices.filter { !hideout.isInside($0) && !creatures[$0].looksAsleep && fx.on[$0] == nil }
        let chance = fx.rules.nowAndThenChance(step: step)
        if Effects.Season.of(today) == .winter, Double.random(in: 0..<1, using: &rng) < chance, let i = awake.randomElement(using: &rng) {
            styleTrigger(.winter, on: i)
        }
        if Effects.aroundHalloween(today), Double.random(in: 0..<1, using: &rng) < chance, let i = awake.randomElement(using: &rng) {
            styleTrigger(.halloween, on: i)
        }
        for i in awake {
            let met = fx.metAt[i] ?? 0
            if elapsed - met > settings.effectsAloneMinutes * 60 {
                fx.metAt[i] = elapsed
                styleTrigger(.leftAlone, on: i)
            }
        }
        // Keys typed: the system's own running count, which needs no permission.
        let keys = CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
        fx.typing.add(count: Double(keys), at: elapsed)
        if fx.typing.fast(threshold: Double(settings.effectsTypingKeys)), let i = awake.randomElement(using: &rng) {
            fx.typing.reset()
            styleTrigger(.fastTyping, on: i)
        }
        checkBudget(today)
        // A meeting in five minutes or less: the clock ticks on someone, once per meeting.
        if settings.effectsCalendar, MeetingWatch.allowed {
            for meeting in fx.meetings.startingSoon(at: today) where !fx.meetingsTicked.contains(meeting.id) {
                guard let i = awake.randomElement(using: &rng) else { break }
                fx.meetingsTicked.insert(meeting.id)
                fx.trace?("fx meeting soon: \(meeting.title)")
                mark(.clockTicking, on: i)
            }
        }
    }

    /// The day's spend past the budget drops the coins, once a day.
    private func checkBudget(_ today: Date) {
        let day = ChatLog.day(of: today)
        // The summary is today's as of the last call: a call made today, or nothing counts.
        guard fx.coinsDay != day, let last = spend.recent.first, Calendar.current.isDate(last.time, inSameDayAs: today) else { return }
        guard spend.summary.today.cost >= settings.effectsDailyBudget,
              let i = creatures.indices.filter({ !hideout.isInside($0) && fx.on[$0] == nil }).randomElement(using: &rng) else { return }
        fx.coinsDay = day
        mark(.moneySpent, on: i)
    }

    /// `i` met someone: it is not alone. A bump between friends may make one smitten; Boo spooks.
    func effectsMet(_ a: Int, _ b: Int, friends: Bool) {
        fx.metAt[a] = elapsed
        fx.metAt[b] = elapsed
        if friends { styleTrigger(.friendsMeet, on: Bool.random(using: &rng) ? a : b) }
        for (x, other) in [(a, b), (b, a)] where settings.species(forCreature: x) == "ghost" {
            _ = other
            styleTrigger(.booSpooks, on: x)
        }
    }

    /// Dictation, a translation or a screenshot just landed on the clipboard: a burst on `i`, the helper
    /// who brought it, or on anyone free.
    func effectsCopied(by i: Int? = nil) {
        let who = i ?? clipHelp?.index ?? creatures.indices.filter { !hideout.isInside($0) && fx.on[$0] == nil }.randomElement(using: &rng)
        if let who { mark(.copied, on: who) }
    }

    /// The settings changed: a species the colony never had before hatches from an egg.
    func effectsNoticeSpecies() {
        let now = Set(creatures.indices.map { settings.species(forCreature: $0) })
        defer { fx.knownSpecies = (fx.knownSpecies ?? []).union(now) }
        guard let known = fx.knownSpecies else { return }
        for i in creatures.indices where !known.contains(settings.species(forCreature: i)) {
            fx.knownSpecies?.insert(settings.species(forCreature: i))
            mark(.newArrival, on: i)
        }
    }

    /// A creature is about to go: a poof where it stood.
    func effectsPoof(_ i: Int) {
        guard creatures.indices.contains(i), !hideout.isInside(i), fx.rules.moment(.poof, creature: nil, now: elapsed),
              let player = makePlayer(Effects.Moment.poof.effect, on: i, moment: .poof) else { return }
        let c = creatures[i]
        fx.loose.append((player, drawnPosition(of: i), c.rotation, CGFloat(sizes[i]), c.isMirrored))
        fx.on.removeValue(forKey: i)
        fx.trace?(String(format: "fx %.2f moment poof %@", elapsed, character(forCreature: i).name))
    }

    /// Whether any effect is still on show.
    var effectsShowing: Bool { !fx.on.isEmpty || !fx.loose.isEmpty || fx.ambient != nil }

    // MARK: What the overlay draws

    /// The pictures for creature `i` this frame, and whether its own sprite is hidden under them.
    func effectSnapshot(of i: Int, image: CGImage?) -> CreatureEffect? {
        guard let p = fx.on[i] else { return nil }
        let body = image.map { fx.actors.pixels(of: $0, box: p.box) }
        let made = p.pictures(actor: body)
        return CreatureEffect(back: made.back, front: made.front, origin: p.cellOrigin, size: p.size, hidesBody: made.hidesBody,
                              hidesZs: p.moment == .asleep)
    }

    /// Effects standing on their own, in global points.
    func looseEffectSnapshots() -> [LooseEffect] {
        var out: [LooseEffect] = []
        for l in fx.loose {
            let made = l.player.pictures(actor: nil)
            out.append(LooseEffect(back: made.back, front: made.front, feet: l.place, origin: l.player.cellOrigin, size: l.player.size,
                                   cell: atlas.cellSize, scale: l.scale, rotation: l.rotation, mirrored: l.mirrored))
        }
        return out
    }

    /// The ambient tiles, each standing on a home monitor's bottom edge, side by side.
    func ambientSnapshots() -> [AmbientTile] {
        guard let a = fx.ambient else { return [] }
        // The particles drift at their own pace; fifteen pictures a second is plenty and costs half.
        if fx.ambientImages.count != a.tiles.count || elapsed >= fx.ambientNextDraw {
            fx.ambientNextDraw = elapsed + 1.0 / 15
            fx.ambientImages = a.tiles.map { $0.whole() }
        }
        var out: [AmbientTile] = []
        var k = 0
        for screen in homeFrames {
            var x = screen.minX
            while x < screen.maxX, k < a.tiles.count {
                let t = a.tiles[k]
                out.append(AmbientTile(image: fx.ambientImages[k], bottomLeft: CGPoint(x: x, y: screen.minY),
                                       size: CGSize(width: t.size.width * Self.ambientScale, height: t.size.height * Self.ambientScale)))
                x += t.size.width * Self.ambientScale
                k += 1
            }
        }
        return out
    }
}

/// An effect's two pictures on one creature: the frame's top-left in its sprite cell's pixels, its size in pixels.
struct CreatureEffect {
    var back: CGImage?
    var front: CGImage?
    var origin: CGPoint
    var size: CGSize
    /// The effect draws the body itself (frost), or the creature has gone (a blink): no sprite.
    var hidesBody: Bool
    /// The sleep effect's Zs replace the plain ones.
    var hidesZs: Bool
}

/// An effect at a place of its own, the creature it was drawn round gone.
struct LooseEffect {
    var back: CGImage?
    var front: CGImage?
    /// Where the creature's centre was, in global points, as `CreatureSnapshot.position`.
    var feet: CGPoint
    var origin: CGPoint
    var size: CGSize
    var cell: CGSize
    var scale: CGFloat
    var rotation: Double
    var mirrored: Bool
}

/// One tile of the ambient particles, its bottom-left corner on a monitor's bottom edge.
struct AmbientTile {
    var image: CGImage?
    var bottomLeft: CGPoint
    var size: CGSize
}

import AppKit
import LedgelingsCore

/// Scuba diving (`Dive`): started by hand only (Creature Actions, the Tools
/// screen, the menu), never on its own. Water rises over the bottom of the
/// screen, a few creatures gear up and jump in, swim among the sea life and come
/// up for air, and when the time is up the water drains and they climb out
/// dripping. Stop activity (`stopDive`) clears it all at once. The water is
/// drawn, not a window: clicks go through it to the apps below.
extension Colony {

    /// The dive going on, and what the colony keeps beside it.
    struct DiveSession {
        var model: Dive
        var serial: Int
        /// What the divers saw, for their memory.
        var saw: Set<Dive.Life> = []
        /// When a diver last said something: one line every few seconds at most.
        var lastLine = -100.0
        /// Splashes and ink puffs, where and when.
        var splashes: [(at: CGPoint, since: Double)] = []
        var inks: [(at: CGPoint, since: Double)] = []
        var started: Double
    }

    /// Seconds between two lines of the divers.
    static let diveLineGap = 6.0
    /// Seconds a diver drips once out.
    static let dripSeconds = 3.0
    static let splashSeconds = 0.6
    static let inkSeconds = 1.4

    var isDiving: Bool { dive != nil }

    // MARK: Starting and stopping

    /// Start a dive now. False when one is on, or nobody is free to dive.
    @discardableResult
    func startDive() -> Bool {
        guard dive == nil, !hideout.isActive else { return false }
        if play != nil { endPlay(completed: false) }
        let pools = divePools()
        func onPools(_ i: Int) -> Bool { pools.contains { $0.insetBy(dx: -1, dy: -1).contains(creatures[i].position) } }
        let free = creatures.indices.filter(freeToPlay).sorted { onPools($0) && !onPools($1) }
        let chosen = Array(free.prefix(settings.diveDivers))
        guard !chosen.isEmpty else { talkStatus = tr("nobody is free to dive"); return false }
        let scale = CGFloat(chosen.map { sizes[$0] }.reduce(0, +) / Double(chosen.count))
        var divers: [(index: Int, at: CGPoint, half: CGFloat)] = []
        for i in chosen where creatures[i].takeOff() {
            busy.insert(i)
            divers.append((i, creatures[i].position, atlas.bodyHalfSize * CGFloat(sizes[i])))
        }
        playCount += 1
        let model = Dive(pools: pools, share: settings.diveWaterShare, seconds: settings.diveMinutes * 60, scale: scale,
                         divers: divers, seaLife: settings.diveSeaLife, using: &rng)
        dive = DiveSession(model: model, serial: playCount, started: elapsed)
        trace?("dive starts: \(divers.map { character(forCreature: $0.index).name }.joined(separator: ", ")), water \(Int(settings.diveWaterShare * 100))% of \(pools.count) screen(s)")
        return true
    }

    /// The monitors the water covers: the creatures' home monitor (the one most of
    /// them are on), or every monitor.
    func divePools() -> [CGRect] {
        let frames = displays.map(\.frame)
        if settings.diveAllScreens || frames.count <= 1 { return frames.isEmpty ? homeFrames : frames }
        let home = homeFrames
        let candidates = home.isEmpty ? frames : home
        return [candidates.max { a, b in
            creatures.filter { a.contains($0.position) }.count < creatures.filter { b.contains($0.position) }.count
        } ?? candidates[0]]
    }

    /// Time is up early, slowly: the water drains and they climb out (the Actions sheet's tile again).
    func drainDive() {
        guard var s = dive else { return }
        s.model.drain()
        dive = s
    }

    /// Stop activity: everything goes at once, water, fish and gear, and the divers
    /// drop back onto their edges.
    func stopDive() {
        guard dive != nil else { return }
        endDive(completed: false)
        render()
    }

    private func endDive(completed: Bool) {
        guard let s = dive else { return }
        dive = nil
        let divers = s.model.divers.map(\.index).filter(creatures.indices.contains)
        for i in divers {
            if creatures[i].isPlaying { creatures[i].touchDown() }
            if completed { dripping[i] = elapsed + Self.dripSeconds }
        }
        busy.subtract(divers)
        // A dive they were in together, even one cut short, is in their memory.
        if s.model.filledAt != nil {
            let saw = Dive.memory(Array(s.saw))
            for (k, a) in divers.enumerated() { for b in divers.dropFirst(k + 1) { shared(a, b, .dive, detail: saw.isEmpty ? nil : saw) } }
        }
        if completed, let first = divers.first { diveLine("out", by: first, force: true) }
        nextPlayAt = elapsed + Plays.wait(everyMinutes: settings.playEveryMinutes, boost: settings.playBondBoost, closeness: 0, using: &rng)
        trace?("dive \(completed ? "over" : "stopped"), saw \(s.saw.map(\.rawValue).sorted().joined(separator: ", "))")
    }

    // MARK: Every frame

    func updateDive(dt: Double) {
        for (i, until) in dripping where until <= elapsed || !creatures.indices.contains(i) { dripping.removeValue(forKey: i) }
        guard var s = dive else { return }
        if hideout.isActive { return stopDive() }
        let events = s.model.update(dt: dt, using: &rng)
        s.splashes.removeAll { elapsed - $0.since > Self.splashSeconds }
        s.inks.removeAll { elapsed - $0.since > Self.inkSeconds }
        dive = s
        for event in events { diveEvent(event) }
        guard var now = dive else { return }
        for d in now.model.divers where creatures.indices.contains(d.index) {
            // Picked up mid-dive: that one is out of it.
            guard creatures[d.index].isPlaying else { continue }
            creatures[d.index].face(d.facingRight ? 1 : -1)
            creatures[d.index].carry(to: d.position, rotation: diverTilt(d), pose: diverPose(d))
        }
        if now.model.isOver { return endDive(completed: true) }
        now.model.divers.removeAll { !creatures.indices.contains($0.index) || !creatures[$0.index].isPlaying }
        dive = now
    }

    private func diverPose(_ d: Dive.Diver) -> String {
        switch d.state {
        case .gearing, .breathing: "idle"
        case .leaping: "jump"
        case .swimming: "walk"
        case .settling: "land"
        }
    }

    /// Nose up swimming up, down swimming down; level otherwise.
    private func diverTilt(_ d: Dive.Diver) -> Double {
        guard d.state == .swimming else { return 0 }
        let a = Double(atan2(d.velocity.dy, max(1, abs(d.velocity.dx))))
        let tilt = min(max(a, -0.5), 0.5)
        return d.facingRight ? tilt : -tilt
    }

    private func diveEvent(_ event: Dive.Event) {
        guard var s = dive else { return }
        switch event {
        case .splash(let at):
            s.splashes.append((at, elapsed))
            dive = s
            trace?("dive splash at (\(Int(at.x)), \(Int(at.y)))")
            // The first one in says so.
            if s.splashes.count == 1, let first = s.model.divers.first, s.model.time < Dive.riseSeconds + Dive.leapSeconds + 0.5 {
                diveLine("in", by: first.index, force: true)
            }
        case .filled:
            trace?("dive water up")
        case .sees(let i, let life):
            s.saw.insert(life)
            dive = s
            trace?("dive \(character(forCreature: i).name) sees \(life.rawValue)")
            diveLine("see", by: i, what: life)
        case .scattered(let i):
            s.saw.insert(.fishA)
            dive = s
            trace?("dive fish scatter from \(character(forCreature: i).name)")
            diveLine("fish", by: i)
        case .startled(let i):
            s.saw.insert(.octopus)
            if let octopus = s.model.critters.first(where: { $0.kind == .octopus }) { s.inks.append((octopus.position, elapsed)) }
            dive = s
            trace?("dive \(character(forCreature: i).name) startled by the octopus")
            diveLine("octopus", by: i, force: true)
        case .surfaced(let i):
            trace?("dive \(character(forCreature: i).name) up for air")
            diveLine("air", by: i)
        case .drained:
            trace?("dive water gone")
        }
    }

    /// Diver `i` says its line for `kind`, unless one was said just now (`force` says it anyway).
    private func diveLine(_ kind: String, by i: Int, what: Dive.Life? = nil, force: Bool = false) {
        guard settings.diveTalk, settings.talkEnabled, !voiceIsTaken, creatures.indices.contains(i) else { return }
        if let s = dive {
            guard force || elapsed - s.lastLine >= Self.diveLineGap else { return }
            dive?.lastLine = elapsed
        }
        let name = character(forCreature: i).name
        let text = Dive.line(by: name, kind, what: what, using: &rng)
        guard !text.isEmpty else { return }
        say(text, from: i, builtIn: true)
        history.record(ChatLog.Exchange(time: Date(), situation: tr("Scuba diving.") + " " + describe(i) + ".",
                                        provider: AppSettings.Brain.script.title, model: "",
                                        lines: [ChatLog.Line(speaker: name, text: text)], cost: nil, tokens: nil))
    }

    // MARK: Drawing

    /// The gear on each diver, the splashes, the ink, and the drops off those just out.
    func diveProps() -> [PropSnapshot] {
        var props: [PropSnapshot] = []
        func image(_ name: String, _ time: Double = 0) -> CGImage? { seaFrames.frame(animation: name, time: time) }
        if let s = dive {
            for d in s.model.divers where creatures.indices.contains(d.index) && creatures[d.index].isPlaying {
                let c = creatures[d.index], scale = CGFloat(sizes[d.index]), p = drawnPosition(of: d.index)
                // The gear goes on while the water comes up: it fades in.
                var shown: Float = 1
                if case .gearing(let until) = d.state { shown = Float(min(1, max(0, 1 - (until - s.model.time - 0.4) / 1.2))) }
                props.append(PropSnapshot(image: image("tank"), position: p, rotation: c.rotation, scale: scale, mirrored: c.isMirrored, opacity: shown))
                props.append(PropSnapshot(image: image("mask"), position: p, rotation: c.rotation, scale: scale, mirrored: c.isMirrored,
                                          opacity: shown, inFront: true))
            }
            let scale = s.model.scale
            for splash in s.splashes {
                let t = elapsed - splash.since
                props.append(PropSnapshot(image: image("splash", t), position: CGPoint(x: splash.at.x, y: splash.at.y + playCell.height * scale * 0.3),
                                          rotation: 0, scale: scale * 1.3, opacity: Float(1 - t / Self.splashSeconds * 0.6), inFront: true))
            }
            for ink in s.inks {
                let t = elapsed - ink.since
                props.append(PropSnapshot(image: image("ink"), position: CGPoint(x: ink.at.x, y: ink.at.y + CGFloat(t) * 12), rotation: 0,
                                          scale: scale * CGFloat(1 + t * 0.8), opacity: Float(max(0, 1 - t / Self.inkSeconds))))
            }
        }
        for (i, until) in dripping where creatures.indices.contains(i) {
            let left = until - elapsed, scale = CGFloat(sizes[i]), p = drawnPosition(of: i)
            for k in 0..<2 {
                let fall = (elapsed * 1.6 + Double(k) * 0.5).truncatingRemainder(dividingBy: 1)
                let side: CGFloat = k == 0 ? -0.5 : 0.45
                props.append(PropSnapshot(image: playFrames.frame(animation: "drop", time: 0),
                                          position: CGPoint(x: p.x + atlas.bodyHalfSize * scale * side, y: p.y - atlas.bodyHalfSize * scale * CGFloat(fall) * 0.9),
                                          rotation: 0, scale: scale, opacity: Float(min(1, left) * (1 - fall * 0.5)), inFront: true))
            }
        }
        return props
    }

    /// The water on each monitor it covers, with everything living in it.
    func waterSnapshots() -> [WaterSnapshot] {
        guard let s = dive else { return [] }
        let m = s.model
        return m.pools.indices.map { k in
            var critters: [WaterSnapshot.Sprite] = []
            for c in m.critters where c.pool == k {
                // Claws up, arms spread: frightened.
                let up = (c.kind == .crab || c.kind == .octopus) && c.scared > 0
                critters.append(.init(image: seaFrames.frame(animation: up ? c.kind.rawValue + "-up" : c.kind.rawValue, time: c.time),
                                      centre: c.position, mirrored: !c.facingRight))
            }
            let bubbles = m.bubbles.filter { m.pools[k].minX <= $0.position.x && $0.position.x <= m.pools[k].maxX }.map {
                WaterSnapshot.Sprite(image: seaFrames.frame(animation: "bubble-\($0.size)", time: 0), centre: $0.position, mirrored: false)
            }
            let weeds = m.weeds.filter { $0.pool == k }.map { WaterSnapshot.Weed(x: $0.x, height: $0.height, phase: $0.phase) }
            return WaterSnapshot(pool: m.pools[k], surface: m.surface(k), opacity: settings.diveWaterOpacity, time: m.time,
                                 scale: m.scale, cell: seaCell, critters: critters, bubbles: bubbles, weeds: weeds,
                                 coral: seaFrames.frame(animation: "coral", time: 0))
        }
    }
}

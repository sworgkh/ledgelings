import AppKit
import LedgelingsCore

/// Every character's own bed (`Beds`). Nodding off at nightfall, a creature
/// walks to its favourite place if the habit pulls it there and the place is
/// near enough along its edge, puts its bed down and sleeps on it; the bed goes
/// when it wakes. The user can drag a bed, sleeper and all, to a new place,
/// which is then the favourite. Dragging a bed is not a hunt: nobody is chased
/// or picked up, nobody complains.
extension Colony {
    /// Seconds a bed takes to come up under its sleeper, and to fade once it wakes.
    static let bedGrowTime = 0.35
    static let bedFadeTime = 0.4
    /// The share of nights a creature says something as it lays its bed down.
    static let bedLineChance = 0.3

    /// Which bed creature `i` sleeps in.
    func bedKind(of i: Int) -> Beds.Kind {
        let who = character(forCreature: i)
        return Beds.kind(name: who.name, persona: who.persona, kind: kind(ofCreature: i))
    }

    /// Every frame, after the creatures have moved: who just nodded off, who
    /// reached its bed, whose bed comes out and whose goes away.
    func updateBeds() {
        guard settings.bedsEnabled, !hideout.isActive else {
            for (i, _) in bedTrips where creatures.indices.contains(i) && creatures[i].isRunning && !hideout.isActive {
                if isNight { creatures[i].settle() } else { creatures[i].pause(for: 0.5) }
            }
            bedTrips.removeAll()
            bedCarry = nil
            for i in Array(bedSince.keys) { putBedAway(i) }
            wasAsleep = Set(creatures.indices.filter { creatures[$0].looksAsleep })
            return
        }
        for i in creatures.indices where !hideout.isInside(i) {
            if bedTrips[i] != nil { walkingToBed(i) }
            let c = creatures[i]
            let noddedOff = c.looksAsleep && !wasAsleep.contains(i)
            if c.looksAsleep { wasAsleep.insert(i) } else { wasAsleep.remove(i) }
            if noddedOff, c.isSleeping, !c.isHeld { nodOff(i) }
            if bedCarry == i, creatures[i].isSleeping, !creatures[i].isHeld { bedPutDown(i) }
            let lying = creatures[i].isSleeping && !creatures[i].isHeld
            if lying || bedCarry == i {
                if bedSince[i] == nil { bedSince[i] = elapsed }
            } else if bedSince[i] != nil {
                putBedAway(i)
            }
        }
        for (i, fade) in bedFades where fade.until <= elapsed { bedFades.removeValue(forKey: i) }
    }

    /// Creatures from `count` on are gone (fewer creatures in the settings).
    func forgetBeds(creaturesFrom count: Int) {
        bedTrips = bedTrips.filter { $0.key < count }
        bedSince = bedSince.filter { $0.key < count }
        bedFades = bedFades.filter { $0.key < count }
        wasAsleep = wasAsleep.filter { $0 < count }
        if let carry = bedCarry, carry >= count { bedCarry = nil }
    }

    // MARK: Nightfall

    /// Creature `i` has just fallen asleep on its edge. By night it may get up
    /// again and walk to its favourite place; a nap the user asked for is slept
    /// where it is, and teaches it nothing.
    private func nodOff(_ i: Int) {
        let c = creatures[i]
        guard isNight, !c.isNapping else { return }
        let name = character(forCreature: i).name
        if let spot = beds.spot(of: name) {
            if hypot(spot.point.x - c.position.x, spot.point.y - c.position.y) <= Beds.near {
                sleepWithRoom(i); return
            }
            let pull = Beds.pull(nights: spot.nights, strength: settings.bedPull / 100)
            if Double.random(in: 0..<1, using: &rng) < pull, let t = reach(spot.point, for: i) {
                goToBed(i, at: t, why: "favourite")
                return
            }
        } else {
            // The first night: off to a place its character likes, the way it picks where to plant a flower.
            for place in temper(of: i).likes {
                guard let t = target(place, for: i), let along = alongLoop(i, to: t), along <= settings.bedWalkDistance else { continue }
                goToBed(i, at: t, why: place.rawValue)
                return
            }
        }
        sleepWithRoom(i)
    }

    /// Lie down here, or a step aside when somebody's bed is already here.
    private func sleepWithRoom(_ i: Int) {
        let c = creatures[i], room = roomForBed(near: c.t, for: i), d = c.loop.wrap(room - c.t)
        if min(d, c.loop.length - d) < 1 { sleepHere(i) } else { goToBed(i, at: room, why: "room") }
    }

    /// Where on creature `i`'s own loop `point` is, if it is on that loop at all
    /// and no further along it than the Beds tab lets it walk.
    func reach(_ point: CGPoint, for i: Int) -> CGFloat? {
        let hit = creatures[i].loop.nearest(to: point)
        guard hit.distance <= Beds.near * 2, let along = alongLoop(i, to: hit.t), along <= settings.bedWalkDistance else { return nil }
        return hit.t
    }

    /// Points along creature `i`'s loop to `t`, the short way round.
    private func alongLoop(_ i: Int, to t: CGFloat) -> CGFloat? {
        let loop = creatures[i].loop, d = loop.wrap(t - creatures[i].t)
        return min(d, loop.length - d)
    }

    /// `t`, or the nearest place beside it with room for creature `i`'s bed:
    /// nobody sleeps on top of somebody else.
    func roomForBed(near t: CGFloat, for i: Int) -> CGFloat {
        let loop = creatures[i].loop, width = bedCell.width * CGFloat(sizes[i]) + 4
        let taken: [CGFloat] = creatures.indices.compactMap { j in
            guard j != i, creatures[j].spot.loop == creatures[i].spot.loop else { return nil }
            if let trip = bedTrips[j] { return trip }
            return bedSince[j] != nil ? creatures[j].t : nil
        }
        func free(_ c: CGFloat) -> Bool {
            taken.allSatisfy { let d = loop.wrap($0 - c); return min(d, loop.length - d) >= width }
        }
        for k in [0, 1, -1, 2, -2, 3, -3, 4, -4] {
            let c = loop.wrap(t + CGFloat(k) * width)
            if free(c) { return c }
        }
        return t
    }

    private func goToBed(_ i: Int, at target: CGFloat, why: String) {
        let t = roomForBed(near: target, for: i)
        creatures[i].run(to: t, pace: 1)
        bedTrips[i] = t
        wasAsleep.remove(i)
        trace?("bed \(character(forCreature: i).name) walks to \(bedKind(of: i).rawValue) (\(why))")
    }

    /// On the way: arrived, it lies down; stopped by something else (a chat,
    /// the house), it forgets about it and sleeps wherever night finds it next.
    private func walkingToBed(_ i: Int) {
        let c = creatures[i]
        guard !c.isRunning else { return }
        bedTrips[i] = nil
        guard c.hasArrived else { return }
        if isNight {
            creatures[i].settle()
            wasAsleep.insert(i)
            sleepHere(i)
        } else {
            creatures[i].pause(for: 0.5)      // morning came first: on with the day
        }
    }

    /// The night is spent here: the habit grows, or wears down.
    private func sleepHere(_ i: Int) {
        let name = character(forCreature: i).name
        beds.slept(name, at: creatures[i].position)
        let nights = beds.spot(of: name)?.nights ?? 0
        trace?("bed \(name) sleeps in \(bedKind(of: i).rawValue) \(onEdge(creatures[i])), \(nights) nights")
        if Double.random(in: 0..<1, using: &rng) < Self.bedLineChance {
            bedLine(Beds.settleLine(by: name, bed: bedKind(of: i), using: &rng), from: i)
        }
    }

    private func bedLine(_ line: String, from i: Int) {
        guard settings.bedTalk, settings.talkEnabled, bubbles[i] == nil, !busy.contains(i), !voiceIsTaken else { return }
        say(line, from: i, builtIn: true)
        history.record(ChatLog.Exchange(time: Date(), situation: [almanac, timeOfDay, "\(describe(i))."].filter { !$0.isEmpty }.joined(separator: " "),
                                        provider: AppSettings.Brain.script.title, model: "",
                                        lines: [ChatLog.Line(speaker: character(forCreature: i).name, text: line)]))
    }

    private func putBedAway(_ i: Int) {
        if let since = bedSince.removeValue(forKey: i), let shown = bedSnapshot(i, since: since) {
            bedFades[i] = (shown, elapsed + Self.bedFadeTime)
        }
    }

    // MARK: The user's hand

    /// The sleeper whose bed (not its body) is under `point`.
    func bed(at point: CGPoint) -> Int? {
        creatures.indices.reversed().first { i in
            guard bedSince[i] != nil, creatures[i].isSleeping, !creatures[i].isHeld, !hideout.isInside(i) else { return false }
            let (floor, up) = bedFloor(i), scale = CGFloat(sizes[i])
            let dx = point.x - floor.x, dy = point.y - floor.y
            let across = dx * up.dy - dy * up.dx, height = dx * up.dx + dy * up.dy
            let half = bedCell.width * scale / 2 + 3
            return abs(across) <= half && height >= -3 && height <= bedCell.height * scale + 3
        }
    }

    /// Pick the bed up with its sleeper on it; dropped, it lands on the nearest edge and stays there.
    func liftBed(_ i: Int, at point: CGPoint) {
        guard creatures[i].pickUp() else { return }
        let p = creatures[i].position
        held = (i, CGVector(dx: p.x - point.x, dy: p.y - point.y))
        bedCarry = i
        trace?("bed \(character(forCreature: i).name) lifted")
    }

    /// The carried bed has landed with its sleeper: this is the favourite place now.
    private func bedPutDown(_ i: Int) {
        bedCarry = nil
        let name = character(forCreature: i).name
        beds.moved(name, to: creatures[i].position)
        trace?("bed \(name) moved \(onEdge(creatures[i]))")
        bedLine(Beds.movedLine(by: name, bed: bedKind(of: i), using: &rng), from: i)
    }

    // MARK: Drawing

    /// Which way is up for creature `i`, from its turn: away from its edge.
    private func up(_ i: Int) -> CGVector {
        let r = creatures[i].rotation
        return CGVector(dx: -sin(r), dy: cos(r))
    }

    /// How far a sleeper lying in its bed is raised off its edge: to the top of the mattress.
    func bedLift(of i: Int) -> CGVector {
        guard creatures.indices.contains(i), bedSince[i] != nil, creatures[i].isSleeping, !creatures[i].isHeld else { return .zero }
        let grown = CGFloat(min(1, (elapsed - bedSince[i]!) / Self.bedGrowTime))
        let lift = CGFloat(bedKind(of: i).lift) * CGFloat(sizes[i]) * grown, u = up(i)
        return CGVector(dx: u.dx * lift, dy: u.dy * lift)
    }

    /// Where creature `i` is drawn: lifted onto its bed when lying in one.
    func drawnPosition(of i: Int) -> CGPoint {
        let p = creatures[i].position, lift = bedLift(of: i)
        return CGPoint(x: p.x + lift.dx, y: p.y + lift.dy)
    }

    /// The middle of the bed's foot, and which way is up: on the edge under a
    /// sleeper lying in it, hanging under the feet of one being carried.
    private func bedFloor(_ i: Int) -> (CGPoint, CGVector) {
        let u = up(i), p = creatures[i].position, scale = CGFloat(sizes[i])
        let lying = creatures[i].isSleeping && !creatures[i].isHeld
        let below = atlas.bodyHalfSize * scale + (lying ? 0 : CGFloat(bedKind(of: i).lift) * scale)
        return (CGPoint(x: p.x - u.dx * below, y: p.y - u.dy * below), u)
    }

    private func bedSnapshot(_ i: Int, since: Double) -> PlantedSnapshot? {
        guard creatures.indices.contains(i), sizes.indices.contains(i) else { return nil }
        let (floor, _) = bedFloor(i)
        return PlantedSnapshot(image: bedFrames.frame(animation: bedKind(of: i).rawValue, time: 0), floor: floor,
                               rotation: creatures[i].rotation, scale: CGFloat(sizes[i]),
                               grown: CGFloat(min(1, max(0.001, (elapsed - since) / Self.bedGrowTime))), opacity: 1)
    }

    func bedSnapshots() -> [PlantedSnapshot] {
        let out = bedSince.keys.sorted().compactMap { i in
            hideout.isInside(i) ? nil : bedSnapshot(i, since: bedSince[i]!)
        }
        let fading = bedFades.keys.sorted().compactMap { i -> PlantedSnapshot? in
            guard var shown = bedFades[i]?.snapshot, let until = bedFades[i]?.until else { return nil }
            shown.opacity = Float(max(0, min(1, (until - elapsed) / Self.bedFadeTime)))
            return shown
        }
        return out + fading
    }
}

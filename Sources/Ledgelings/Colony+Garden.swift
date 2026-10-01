import AppKit
import LedgelingsCore

/// A creature with a flower on its head plants it in the edge, when and where its
/// character likes (`Garden.temper`), and the flowers stand there a while.
extension Colony {
    /// Every frame: wilt what is past its time, then let each wearer at leisure
    /// decide whether this is the spot.
    func updateGarden() {
        garden.update(at: elapsed, most: settings.gardenSize)
        guard settings.plantFlowers, !hideout.isActive else { return }
        gardeners = []
        for wearer in gifts.worn.keys.sorted() where canPlant(wearer) {
            guard let share = gifts.worn(wearer, at: elapsed), let spot = plantingSpot(of: wearer) else { continue }
            let temper = temper(of: wearer), around = surroundings(of: wearer, at: spot.floor)
            guard share >= temper.keep else { continue }
            if Garden.wantsToPlant(temper, share: share, around: around),
               garden.hasRoom(at: spot.floor, scale: sizes[wearer]) {
                plant(wearer, at: spot, because: temper.likes.first { Garden.fits($0, around) })
                continue
            }
            // Done wearing it: it stops trailing its giver and goes looking for its place.
            gardeners.insert(wearer)
            if let favourite = temper.likes.first, let t = target(favourite, for: wearer) {
                creatures[wearer].head(toward: t, near: 4)
            }
        }
    }

    /// Where on its own loop the nearest spot of this kind is, for the places a
    /// creature can walk to: an edge facing the right way, a corner, a planted
    /// row. Nil for the rest (company, being alone, the time of day): those it
    /// comes across as it wanders. Nil too when it is already there.
    func target(_ place: Garden.Place, for i: Int) -> CGFloat? {
        let c = creatures[i], loop = c.loop
        let half = atlas.bodyHalfSize * CGFloat(sizes[i])
        /// Loop distance from the creature to `t`, the short way round.
        func away(_ t: CGFloat) -> CGFloat { let d = loop.wrap(t - c.t); return min(d, loop.length - d) }
        func edges(_ wanted: (CGVector) -> Bool) -> CGFloat? {
            let matching = (0..<loop.segmentCount).filter { wanted(loop.inward(ofSegment: $0)) && loop.length(ofSegment: $0) > 4 * half }
            guard !matching.contains(c.segment) else { return nil }
            return matching.map { loop.t(onSegment: $0, fraction: 0.5) }.min { away($0) < away($1) }
        }
        switch place {
        case .floor: return edges { $0.dy > 0.5 }
        case .ceiling: return edges { $0.dy < -0.5 }
        case .wall: return edges { abs($0.dx) > 0.5 }
        case .corner:
            // The nearer end of its own edge, far enough in for the flower to fit before the turn.
            let start = loop.t(onSegment: c.segment, fraction: 0), length = loop.length(ofSegment: c.segment)
            let inset = min(Garden.cornerReach / 2 + half, length / 2)
            let ends = [start + inset, start + length - inset]
            return ends.min { away($0) < away($1) }.flatMap { away($0) > Garden.cornerReach / 2 ? $0 : nil }
        case .row:
            let close = garden.beds.compactMap { bed -> CGFloat? in
                let hit = loop.nearest(to: bed.floor)
                return hit.distance <= half * 1.5 ? hit.t : nil
            }
            return close.min { away($0) < away($1) }.flatMap { away($0) > Garden.rowWithin / 2 ? $0 : nil }
        case .alone, .company, .night, .day: return nil
        }
    }

    /// How this creature's character plants, from its persona and its species' kind.
    func temper(of i: Int) -> Garden.Temper {
        Garden.temper(persona: character(forCreature: i).persona, kind: kind(ofCreature: i))
    }

    /// Not while it is talking, reading, carried, asleep, jumping or on its way home.
    private func canPlant(_ i: Int) -> Bool {
        creatures.indices.contains(i) && !busy.contains(i) && !expectsPlane(i) && letters[i] == nil
            && !hideout.isInside(i) && creatures[i].isAtLeisure && !creatures[i].looksAsleep
    }

    /// Where its flower would go: on the edge just in front of its feet, or just
    /// behind them when the edge turns in front of it.
    func plantingSpot(of i: Int) -> (floor: CGPoint, rotation: Double)? {
        let c = creatures[i], loop = c.loop, segment = c.segment
        let half = atlas.bodyHalfSize * CGFloat(sizes[i])
        let start = loop.t(onSegment: segment, fraction: 0), length = loop.length(ofSegment: segment)
        let along = c.loop.wrap(c.t - start)
        let reach = half + 6 * CGFloat(sizes[i])
        let ahead = along + c.direction * reach, behind = along - c.direction * reach
        let offset: CGFloat
        if (0...length).contains(ahead) { offset = ahead }
        else if (0...length).contains(behind) { offset = behind }
        else { return nil }
        let point = loop.point(at: start + offset), inward = loop.inward(ofSegment: segment)
        return (CGPoint(x: point.x - inward.dx * half, y: point.y - inward.dy * half), loop.rotation(ofSegment: segment))
    }

    func surroundings(of i: Int, at floor: CGPoint) -> Garden.Surroundings {
        let c = creatures[i], start = c.loop.t(onSegment: c.segment, fraction: 0)
        let along = c.loop.wrap(c.t - start)
        let others = creatures.indices.filter { $0 != i && !hideout.isInside($0) }
        let nearest = others.map { hypot(creatures[$0].position.x - c.position.x, creatures[$0].position.y - c.position.y) }.min()
        return Garden.Surroundings(inward: c.loop.inward(ofSegment: c.segment),
                                   toCorner: min(along, c.loop.length(ofSegment: c.segment) - along),
                                   toCreature: nearest ?? .infinity, toFlower: garden.distance(to: floor), isNight: isNight)
    }

    /// Take the flower off its head and put it in the ground. It stops a moment to do it.
    private func plant(_ i: Int, at spot: (floor: CGPoint, rotation: Double), because place: Garden.Place?) {
        guard let worn = gifts.takeOff(i) else { return }
        let name = character(forCreature: i).name
        garden.plant(worn.flower, at: spot.floor, rotation: spot.rotation, scale: sizes[i], by: name,
                     at: elapsed, lasts: settings.gardenMinutes * 60, most: settings.gardenSize)
        creatures[i].pause(for: 1.2)
        trace?("plant \(name) \(worn.flower) \(place?.rawValue ?? "anywhere")")
    }

    /// Pull up every planted flower at once (the menu, the Flowers tab). Returns how many went.
    @discardableResult
    func clearGarden() -> Int {
        let count = garden.beds.count
        garden.clear()
        render()
        trace?("garden cleared \(count)")
        return count
    }

    /// The monitors changed: a flower no longer standing on an edge goes.
    func replantAfterScreensChanged() {
        let outline = EdgeWorld(screens: displays.map(\.frame), inset: 0)
        garden.keep { bed in outline.loops.contains { $0.nearest(to: bed.floor).distance < 2 } }
    }

    func gardenSnapshots() -> [PlantedSnapshot] {
        garden.beds.map { bed in
            PlantedSnapshot(image: flowerFrames.frame(animation: bed.flower, time: 0), floor: bed.floor,
                            rotation: bed.rotation, scale: CGFloat(bed.scale),
                            grown: CGFloat(Garden.grown(bed, at: elapsed)),
                            // Fades over its last two seconds.
                            opacity: Float(min(1, max(0, (bed.until - elapsed) / 2))))
        }
    }
}

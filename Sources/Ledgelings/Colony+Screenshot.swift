import AppKit
import LedgelingsCore

/// The creature who brings a screenshot home (§7.12): once a shot is taken it hops
/// from its edge to where the toolbar stood, picks up a tiny picture of the shot
/// (a plane-sized pixel thumbnail held out in front, like a letter), hops back and
/// walks on holding it a moment longer. The creatures are hidden while the screens
/// are frozen, and left out of the picture.
extension Colony {
    struct ShotCarry {
        enum Stage {
            case going(ClipHelper.Leap)
            /// At the spot, picking the picture up.
            case picking(until: Double)
            case returning(ClipHelper.Leap)
            /// Home again, still holding it.
            case holding(until: Double)
        }
        var index: Int
        var stage: Stage
        var home: CGPoint
        var picture: CGImage?
    }

    /// The creatures' windows, for leaving them out of a shot.
    var overlayWindowIDs: Set<CGWindowID> { Set(overlays.compactMap(\.windowID)) }

    /// Out of sight while the screens are frozen, and back after.
    func hideForShot(_ hidden: Bool) { overlays.forEach { $0.setHidden(hidden) } }

    /// Sends a creature to `spot` (global points) for `picture`; false when nobody can come.
    @discardableResult
    func shotCarrierCome(to spot: CGPoint, picture: CGImage?) -> Bool {
        if let carry = shotCarry { shotCarrierLand(carry.index) }
        guard !hideout.isActive else { return false }
        let candidates = creatures.indices.map { i in
            let c = creatures[i]
            return ClipHelper.Candidate(name: character(forCreature: i).name, position: c.position, asleep: c.looksAsleep,
                                        free: !busy.contains(i) && held?.index != i && grab?.index != i && !isMoving(i)
                                            && !c.isPlaying && !c.isChatting && !c.isHeld && bubbles[i] == nil && clipHelp?.index != i)
        }
        guard let i = ClipHelper.choose(candidates, centre: spot, wanted: ""), creatures[i].takeOff(waking: true) else { return false }
        bedTrips.removeValue(forKey: i)
        gardeners.remove(i)
        busy.insert(i)
        let from = creatures[i].position
        // Just under the spot, so it is the toolbar's bottom edge it lands on.
        let to = CGPoint(x: spot.x, y: spot.y - atlas.bodyHalfSize * CGFloat(sizes[i]))
        let leap = ClipHelper.Leap(from: from, to: to, flight: ClipHelper.flight(distance: hypot(to.x - from.x, to.y - from.y), speed: 1))
        shotCarry = ShotCarry(index: i, stage: .going(leap), home: from, picture: picture)
        trace?(String(format: "shot %@ hops to (%.0f, %.0f) in %.2f s", character(forCreature: i).name, to.x, to.y, leap.duration))
        return true
    }

    /// The tiny picture creature `i` holds out, while it carries one home.
    func shotThumbnail(for i: Int) -> CGImage? {
        guard let carry = shotCarry, carry.index == i else { return nil }
        switch carry.stage {
        case .returning, .holding: return carry.picture
        default: return nil
        }
    }

    func updateShotCarry(dt: Double) {
        guard var carry = shotCarry else { return }
        let i = carry.index
        guard creatures.indices.contains(i) else { shotCarry = nil; busy.remove(i); return }
        let name = character(forCreature: i).name
        switch carry.stage {
        case .going(var leap):
            guard creatures[i].isPlaying else { shotCarrierLand(i); return }
            leap.update(dt: dt)
            creatures[i].carry(to: leap.position, rotation: leap.rotation, pose: leap.pose)
            carry.stage = leap.isDone ? .picking(until: elapsed + 0.25) : .going(leap)
            if leap.isDone { trace?("shot \(name) picks up the picture") }
        case .picking(let until):
            guard creatures[i].isPlaying else { shotCarrierLand(i); return }
            if elapsed >= until {
                let from = creatures[i].position
                let leap = ClipHelper.Leap(from: from, to: carry.home,
                                           flight: ClipHelper.flight(distance: hypot(carry.home.x - from.x, carry.home.y - from.y), speed: 1))
                carry.stage = .returning(leap)
                trace?("shot \(name) hops home with it")
            }
        case .returning(var leap):
            guard creatures[i].isPlaying else { shotCarrierLand(i); return }
            leap.update(dt: dt)
            creatures[i].carry(to: leap.position, rotation: leap.rotation, pose: leap.pose)
            if leap.isDone {
                busy.remove(i)
                creatures[i].touchDown()
                carry.stage = .holding(until: elapsed + 2)
                trace?(String(format: "shot %@ is back at (%.0f, %.0f)", name, creatures[i].position.x, creatures[i].position.y))
            } else {
                carry.stage = .returning(leap)
            }
        case .holding(let until):
            if elapsed >= until { shotCarry = nil; return }
        }
        shotCarry = carry
    }

    /// Cut short: onto the nearest edge, free again, the picture dropped.
    func shotCarrierLand(_ i: Int) {
        let flying: Bool = switch shotCarry?.stage { case .holding?: false; default: true }
        shotCarry = nil
        guard flying else { return }
        busy.remove(i)
        guard creatures.indices.contains(i) else { return }
        creatures[i].touchDown()
    }
}

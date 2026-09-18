import AppKit
import LedgelingsCore

/// "Hide them for a while": the house comes out on the main screen's floor,
/// everyone runs (or jumps) home, the house packs itself away, and when the
/// time is up it comes back and they walk out one by one.
extension Colony {
    /// The house is drawn at the largest creature's pixel scale, so its doorway
    /// (26 sheet px) takes a 22 px body with room to spare.
    var houseScale: CGFloat { CGFloat(settings.maxSize) }
    /// The doorway's middle, in sheet pixels from the cell's left edge:
    /// content box x (2) + DOOR_X (4) + DOOR_W / 2 (13). See spritetool/painters/house.py.
    static let doorMiddle: CGFloat = 19
    /// How close to the door, along the loop, counts as "in".
    static let doorReach: CGFloat = 6
    /// Seconds to shrink into the doorway, and to grow back out of it.
    static let doorTime = 0.35
    /// Farther than this along the loop, a creature jumps to the porch instead of running the whole way.
    static let runReach: CGFloat = 420
    /// The porch: this far left of the doorway, on the floor. Jumps land here, then it is a short run in.
    static let porchOffset: CGFloat = 150

    /// The house's own bottom-right corner sits on the primary screen's bottom-right
    /// corner, so growing and shrinking happen about that corner.
    var houseCorner: CGPoint {
        let frame = (NSScreen.screens.first ?? NSScreen.main)?.frame ?? CGRect(x: 0, y: 0, width: 1000, height: 600)
        // Two sheet px of margin sit right of the wall; let them hang off the screen.
        return CGPoint(x: frame.maxX + 2 * houseScale, y: frame.minY)
    }

    /// Where a creature should be to count as inside: the middle of the doorway, on the floor.
    var doorPoint: CGPoint {
        CGPoint(x: houseCorner.x - houseCell.width * houseScale + Self.doorMiddle * houseScale, y: houseCorner.y)
    }

    /// The nearest point of this creature's own loops to the doorway.
    func doorSpot(for i: Int) -> EdgeWorld.Spot { creatures[i].world.nearest(to: doorPoint) }

    func porchSpot(for i: Int) -> EdgeWorld.Spot {
        creatures[i].world.nearest(to: CGPoint(x: doorPoint.x - Self.porchOffset, y: doorPoint.y))
    }

    var isHiding: Bool { hideout.isActive }

    func hide(for seconds: Double) {
        guard !hideout.isActive, !creatures.isEmpty else { return }
        letGo()
        releaseChat()
        bubbles.removeAll()
        entering.removeAll()
        leaving.removeAll()
        hideout.hide(count: creatures.count, at: elapsed, for: seconds)
        render()
    }

    func bringThemBack() { hideout.recall(at: elapsed) }

    func updateHideout() {
        guard hideout.isActive else { return }
        for event in hideout.update(at: elapsed) {
            switch event {
            case .forceInside(let stragglers):
                for i in stragglers { hideout.entered(i, at: elapsed) }
            case .letOut(let i):
                guard creatures.indices.contains(i) else { continue }
                // Out through the door and away from the corner, so nobody walks straight behind the house.
                creatures[i].emerge(at: doorSpot(for: i), facing: -1, using: &rng)
                leaving[i] = elapsed
            }
        }
        if hideout.phase == .gathering {
            for (i, since) in entering where elapsed - since >= Self.doorTime {
                entering.removeValue(forKey: i)
                hideout.entered(i, at: elapsed)
            }
            for i in creatures.indices where !hideout.isInside(i) && entering[i] == nil { herd(i) }
        } else if !entering.isEmpty {
            entering.removeAll()          // recalled mid-shrink: pop back to full size and stay out
        }
        for (i, since) in leaving where elapsed - since >= Self.doorTime { leaving.removeValue(forKey: i) }
    }

    /// 1 = full size; on the way in it falls to 0, on the way out it rises from 0.
    func doorShrink(of i: Int) -> CGFloat {
        if let since = entering[i] { return CGFloat(max(0, 1 - (elapsed - since) / Self.doorTime)) }
        if let since = leaving[i] { return CGFloat(min(1, (elapsed - since) / Self.doorTime)) }
        return 1
    }

    /// Send one creature home: a short run in if it is near the door, otherwise a
    /// jump to the porch first (from anywhere: another monitor, the ceiling, far
    /// down the floor), then the run.
    private func herd(_ i: Int) {
        if held?.index == i { letGo() }
        guard !creatures[i].isJumping else { return }
        let door = doorSpot(for: i)
        let c = creatures[i]
        let along = c.spot.loop == door.loop ? min(c.loop.wrap(c.t - door.t), c.loop.wrap(door.t - c.t)) : .infinity
        if along <= Self.doorReach {
            entering[i] = elapsed         // at the door: shrink away, then it is inside
        } else if along > Self.runReach, !c.hasArrived {
            creatures[i].leap(to: porchSpot(for: i))
        } else if !c.isRunning {
            creatures[i].run(to: door.t)
        }
    }

    func houseSnapshot() -> HouseSnapshot? {
        guard hideout.isActive else { return nil }
        let grown = CGFloat(hideout.scale(at: elapsed))
        guard grown > 0 else { return nil }
        return HouseSnapshot(image: houseFrames.frame(animation: "house", time: 0),
                             corner: houseCorner, scale: houseScale * grown)
    }
}

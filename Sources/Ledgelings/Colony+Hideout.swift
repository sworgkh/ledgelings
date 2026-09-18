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

    /// The primary screen's bottom-right corner, flush with both edges.
    var housePoint: CGPoint {
        let frame = (NSScreen.screens.first ?? NSScreen.main)?.frame ?? CGRect(x: 0, y: 0, width: 1000, height: 600)
        let scale = houseScale
        // Two sheet px of margin sit right of the wall; let them hang off the screen.
        return CGPoint(x: frame.maxX + 2 * scale - houseCell.width * scale / 2, y: frame.minY + houseCell.height * scale / 2)
    }

    /// Where a creature should be to count as inside: the middle of the doorway, on the floor.
    var doorPoint: CGPoint {
        let home = housePoint
        return CGPoint(x: home.x - houseCell.width * houseScale / 2 + Self.doorMiddle * houseScale, y: home.y - houseCell.height * houseScale / 2)
    }

    /// The nearest point of this creature's own loops to the doorway.
    func doorSpot(for i: Int) -> EdgeWorld.Spot { creatures[i].world.nearest(to: doorPoint) }

    var isHiding: Bool { hideout.isActive }

    func hide(for seconds: Double) {
        guard !hideout.isActive, !creatures.isEmpty else { return }
        letGo()
        releaseChat()
        bubbles.removeAll()
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
            }
        }
        if hideout.phase == .gathering {
            for i in creatures.indices where !hideout.isInside(i) { herd(i) }
        }
    }

    /// Send one creature home: run along its loop if the door is on it, jump otherwise.
    private func herd(_ i: Int) {
        if held?.index == i { letGo() }
        guard !creatures[i].isJumping else { return }
        let door = doorSpot(for: i)
        let c = creatures[i]
        guard c.spot.loop == door.loop else { creatures[i].leap(to: door); return }
        let along = min(c.loop.wrap(c.t - door.t), c.loop.wrap(door.t - c.t))
        if along <= Self.doorReach || c.hasArrived {
            hideout.entered(i, at: elapsed)
        } else if !c.isRunning {
            creatures[i].run(to: door.t)
        }
    }

    func houseSnapshot() -> HouseSnapshot? {
        guard hideout.isActive else { return nil }
        let grown = CGFloat(hideout.scale(at: elapsed))
        guard grown > 0 else { return nil }
        return HouseSnapshot(image: houseFrames.frame(animation: "house", time: 0), position: housePoint,
                             scale: houseScale * grown)
    }
}

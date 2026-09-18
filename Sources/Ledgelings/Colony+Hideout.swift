import AppKit
import LedgelingsCore

/// "Hide them for a while": the house comes out on the main screen's floor,
/// everyone runs (or jumps) home, the house packs itself away, and when the
/// time is up it comes back and they walk out one by one.
extension Colony {
    /// Screen points per sheet pixel for the house, when fully grown.
    static let houseScale: CGFloat = 2.5
    /// How close to the door, along the loop, counts as "in".
    static let doorReach: CGFloat = 6

    /// On the floor of the first (primary) screen, a fifth of the way in.
    var housePoint: CGPoint {
        let frame = (NSScreen.screens.first ?? NSScreen.main)?.frame ?? CGRect(x: 0, y: 0, width: 1000, height: 600)
        return CGPoint(x: frame.minX + frame.width * 0.2, y: frame.minY + houseCell.height * Self.houseScale / 2)
    }

    /// The nearest point of this creature's own loops to the house.
    func doorSpot(for i: Int) -> EdgeWorld.Spot { creatures[i].world.nearest(to: housePoint) }

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
                creatures[i].emerge(at: doorSpot(for: i), facing: Bool.random(using: &rng) ? 1 : -1, using: &rng)
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
                             scale: Self.houseScale * grown)
    }
}

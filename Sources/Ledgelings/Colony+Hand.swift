import AppKit
import LedgelingsCore

/// The user's hand: clicks, pokes, drags and what the overlay lets through.
extension Colony {

    /// The topmost creature whose body is under `point`.
    func creature(at point: CGPoint) -> Int? {
        creatures.indices.reversed().first { i in
            guard !hideout.isInside(i) else { return false }
            let half = atlas.bodyHalfSize * CGFloat(sizes[i]) + 4      // a little forgiveness
            let p = creatures[i].position
            return abs(point.x - p.x) <= half && abs(point.y - p.y) <= half
        }
    }

    /// A plain press on a sleeper picks it up. A Shift-press is a poke if it lets
    /// go where it started, a carry if it moves. Right-click naps or wakes. A press
    /// on a speech bubble closes it.
    func hand(_ event: HandEvent) {
        switch event {
        case .down(let point, let shift):
            guard let i = creature(at: point) else {
                if let spoken = bubble(at: point) { bubbles.removeValue(forKey: spoken) }
                break
            }
            if shift {
                poke = (i, point)          // decided on release: a poke, or a drag
            } else if creatures[i].pickUp() {
                let p = creatures[i].position
                held = (i, CGVector(dx: p.x - point.x, dy: p.y - point.y))
            }
        case .dragged(let point):
            if let poke, hypot(point.x - poke.at.x, point.y - poke.at.y) >= Self.dragThreshold {
                self.poke = nil
                if creatures.indices.contains(poke.index), creatures[poke.index].pickUp(evenAwake: true) {
                    let p = creatures[poke.index].position
                    held = (poke.index, CGVector(dx: p.x - poke.at.x, dy: p.y - poke.at.y))
                }
            }
            guard let held else { return }
            creatures[held.index].drag(to: CGPoint(x: point.x + held.grab.dx, y: point.y + held.grab.dy))
        case .up:
            if let poke { self.poke = nil; talkNow(from: poke.index) }
            letGo()
        case .secondaryDown(let point):
            if let i = creature(at: point) { creatures[i].toggleNap(using: &rng) }
        }
        render()      // follow the hand at the mouse's rate, not the display link's
    }

    func letGo() {
        if let held, creatures.indices.contains(held.index) { creatures[held.index].drop() }
        held = nil
    }

    /// Make an overlay clickable only while the cursor is on something the user
    /// can act on: any sleeper, any creature at all while Shift is down, or a
    /// speech bubble. Shift is also how you get close enough to right-click one.
    func updateClickability(cursor: CGPoint, shift: Bool) {
        let target = held != nil || creature(at: cursor).map { shift || creatures[$0].isSleeping } == true
            || bubble(at: cursor) != nil
        for overlay in overlays { overlay.setClickable(target && overlay.screen.frame.contains(cursor)) }
    }
}

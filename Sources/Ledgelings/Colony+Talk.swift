import AppKit
import LedgelingsCore

/// The creatures' words: who speaks to whom, the prompt for the moment, the bubbles.
extension Colony {

    private static let edgeNames: [(Double, String)] = [(0, "the bottom edge"), (.pi / 2, "the right edge"),
                                                        (.pi, "the ceiling"), (3 * .pi / 2, "the left edge")]
    func edgeName(_ c: Creature) -> String {
        Self.edgeNames.min {
            abs(Creature.shortestArc(from: c.rotation, to: $0.0)) < abs(Creature.shortestArc(from: c.rotation, to: $1.0))
        }!.1
    }

    func describe(_ i: Int) -> String {
        let c = creatures[i], name = settings.character(forCreature: i).name
        if c.isHeld { return "\(name) is dangling from the user's cursor" }
        if c.isJumping { return "\(name) is mid-jump" }
        return "\(name) is \(c.isSleeping ? "asleep on" : "on") \(edgeName(c))"
    }

    /// "Make Someone Talk" from the menu, or a Shift-poke on `chosen`: the speaker
    /// says something to whoever is nearest.
    func talkNow(from chosen: Int? = nil) {
        guard creatures.count >= 2 else { talkStatus = "needs at least two creatures"; return }
        guard !talking else { return }
        let awake = creatures.indices.filter { !creatures[$0].isSleeping && !creatures[$0].isJumping }
        guard let speaker = chosen ?? (awake.isEmpty ? Array(creatures.indices) : awake).randomElement(using: &rng),
              creatures.indices.contains(speaker) else { return }
        let me = creatures[speaker].position
        let listener = creatures.indices.filter { $0 != speaker }.min {
            hypot(creatures[$0].position.x - me.x, creatures[$0].position.y - me.y)
                < hypot(creatures[$1].position.x - me.x, creatures[$1].position.y - me.y)
        }!
        hold(speaker, and: listener)
        if !talk(from: speaker, to: listener) { endChat(after: 1) }
    }
}

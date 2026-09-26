import AppKit
import LedgelingsCore

/// What happens when two creatures walk into each other: the stop, the stars,
/// the flower every third time, and letting them go again.
extension Colony {
    /// Two creatures stopped face to face. Several pairs can be talking at once.
    struct Conversation {
        var a: Int
        var b: Int
        var releaseAt: Double?
        func involves(_ i: Int) -> Bool { i == a || i == b }
    }

    func parties() -> [Meetings.Party] {
        creatures.indices.map { i in
            let c = creatures[i]
            return Meetings.Party(loop: c.spot.loop, segment: c.segment, position: c.position,
                                  halfSize: atlas.bodyHalfSize * CGFloat(sizes[i]),
                                  // A flower wearer trails its giver; letting it bump would be a
                                  // meeting every few seconds. It walks past everyone instead.
                                  canTalk: !hideout.isActive && !busy.contains(i) && !expectsPlane(i) && gifts.hat(of: i) == nil
                                      && !c.isJumping && !c.looksAsleep && !c.isHeld && !c.isChatting)
        }
    }

    /// Two creatures walked into each other. They chat about it, and every
    /// third time one of them brings a flower.
    func bumped(_ bump: Meetings.Bump) {
        let (giver, receiver) = Bool.random(using: &rng) ? (bump.a, bump.b) : (bump.b, bump.a)
        hold(bump.a, and: bump.b)
        let pa = creatures[bump.a].position, pb = creatures[bump.b].position
        sparkPalette = [CGColor.white, CGColor(red: 1, green: 0.82, blue: 0.24, alpha: 1),
                        star(settings.color(forCreature: bump.a)), star(settings.color(forCreature: bump.b))]
        sparks.burst(at: CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2),
                     inward: creatures[bump.a].loop.inward(ofSegment: creatures[bump.a].segment), using: &rng)
        var event = "They just walked into each other."
        var given: String?
        if bump.gift, let flower = Gifts.flowers.randomElement(using: &rng), gifts.give(flower, from: giver, to: receiver, at: elapsed) {
            let a = character(forCreature: giver).name, b = character(forCreature: receiver).name
            event = "\(a) just walked into \(b) and gave \(b) a \(flower)."
            given = flower
        }
        if !settings.talkEnabled || !talk(from: giver, to: receiver, because: event, flower: given) { endChat(giver, receiver, after: 2) }
    }

    private func star(_ rgb: RGB) -> CGColor {
        CGColor(red: CGFloat(rgb.r) / 255, green: CGFloat(rgb.g) / 255, blue: CGFloat(rgb.b) / 255, alpha: 1)
    }

    func sparkSnapshots() -> [SparkSnapshot] {
        let size = CGFloat(2 * (sizes.max() ?? 2))
        return sparks.alive.map { spark in
            SparkSnapshot(position: spark.position, size: size,
                          color: sparkPalette.isEmpty ? .white : sparkPalette[spark.tint % sparkPalette.count],
                          opacity: Float(spark.opacity))
        }
    }

    /// Both stop and turn to face each other, like two people who meet in the street.
    func hold(_ i: Int, and j: Int) {
        guard creatures.indices.contains(i), creatures.indices.contains(j), i != j else { return }
        creatures[i].meet(facing: facing(i, toward: j))
        creatures[j].meet(facing: facing(j, toward: i))
        chats.removeAll { $0.involves(i) || $0.involves(j) }
        chats.append(Conversation(a: i, b: j, releaseAt: nil))
    }

    /// +1 when `j` is further round the loop from `i`, -1 when behind; on another
    /// loop there is nothing to face, so keep the current heading.
    func facing(_ i: Int, toward j: Int) -> CGFloat {
        let a = creatures[i], b = creatures[j]
        guard a.spot.loop == b.spot.loop else { return a.direction }
        return a.loop.wrap(b.t - a.t) < a.loop.length / 2 ? 1 : -1
    }

    /// This pair's conversation is done, or never started: let them go in a moment.
    func endChat(_ i: Int, _ j: Int, after seconds: Double) {
        for k in chats.indices where chats[k].involves(i) && chats[k].involves(j) {
            chats[k].releaseAt = min(chats[k].releaseAt ?? .infinity, elapsed + seconds)
        }
    }

    /// Everyone walks on, now.
    func releaseChat() {
        for chat in chats { release(chat) }
        chats.removeAll()
    }

    private func release(_ chat: Conversation) {
        for i in [chat.a, chat.b] where creatures.indices.contains(i) { creatures[i].walkOn(using: &rng) }
    }

    /// Where a flower sits or lands: on the head, away from the edge.
    func head(of i: Int) -> CGPoint {
        let c = creatures[i], up = c.isHeld ? CGVector(dx: 0, dy: 1) : c.loop.inward(ofSegment: c.segment)
        let lift = (atlas.bodyHalfSize + flowerCell.height / 2) * CGFloat(sizes[i])
        return CGPoint(x: c.position.x + up.dx * lift, y: c.position.y + up.dy * lift)
    }

    /// Let a pair go once they have finished talking: the last line said and its
    /// bubble gone, so nobody walks off mid-sentence; or at once when one of them is
    /// no longer standing there. While either is still talking, their chat's own
    /// safety limit is kept topped up; once both are quiet it runs out as usual.
    func releaseChatIfOver() {
        let over = chats.filter { chat in
            let stillThere = [chat.a, chat.b].allSatisfy { creatures.indices.contains($0) && creatures[$0].isChatting }
            guard stillThere else { return true }
            if isTalking(chat) { return false }
            return chat.releaseAt.map { $0 <= elapsed } ?? false
        }
        for chat in chats where isTalking(chat) {
            for i in [chat.a, chat.b] where creatures.indices.contains(i) { creatures[i].keepChatting(for: Self.chatGrace) }
        }
        guard !over.isEmpty else { return }
        for chat in over { release(chat) }
        chats.removeAll { chat in over.contains { $0.a == chat.a && $0.b == chat.b } }
    }

    /// A line of theirs is still coming (a model is thinking, a scripted line is due)
    /// or still up in a bubble.
    private func isTalking(_ chat: Conversation) -> Bool {
        [chat.a, chat.b].contains { busy.contains($0) || bubbles[$0] != nil }
    }

    /// How long a pair stays put, once both have gone quiet, if nothing lets them go sooner.
    static let chatGrace = 5.0

    // MARK: Flowers and stars, as the overlay draws them

    func flightSnapshot() -> FlowerFlight? {
        guard let flight = gifts.flight, let p = gifts.flightProgress(at: elapsed),
              creatures.indices.contains(flight.from), creatures.indices.contains(flight.to) else { return nil }
        let from = head(of: flight.from), to = head(of: flight.to)
        let arc = sin(p * .pi) * 24
        let up = creatures[flight.to].loop.inward(ofSegment: creatures[flight.to].segment)
        return FlowerFlight(
            image: flowerFrames.frame(animation: flight.flower, time: 0),
            position: CGPoint(x: from.x + (to.x - from.x) * p + up.dx * arc, y: from.y + (to.y - from.y) * p + up.dy * arc),
            rotation: creatures[flight.to].rotation,
            scale: CGFloat(sizes[flight.to])
        )
    }

    /// Whoever wears a flower trails the one who gave it, stopping about a body
    /// apart. Not while either is talking, and not while they are going home.
    func followGivers() {
        guard !hideout.isActive else { return }
        for (wearer, hat) in gifts.worn where creatures.indices.contains(hat.from) && hat.from != wearer {
            guard creatures.indices.contains(wearer), !busy.contains(wearer), !busy.contains(hat.from) else { continue }
            let gap = (sizes[wearer] + sizes[hat.from]) / 2 + 16
            creatures[wearer].follow(creatures[hat.from], gap: gap)
        }
    }
}

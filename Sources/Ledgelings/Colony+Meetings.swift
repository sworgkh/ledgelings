import AppKit
import LedgelingsCore

/// What happens when two creatures walk into each other: the stop, the stars,
/// the flower every third time, and letting them go again.
extension Colony {

    func parties() -> [Meetings.Party] {
        creatures.indices.map { i in
            let c = creatures[i]
            return Meetings.Party(loop: c.spot.loop, segment: c.segment, position: c.position,
                                  halfSize: atlas.bodyHalfSize * CGFloat(sizes[i]),
                                  canTalk: !c.isJumping && !c.looksAsleep && !c.isHeld && !c.isChatting)
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
        if bump.gift, let flower = Gifts.flowers.randomElement(using: &rng), gifts.give(flower, from: giver, to: receiver, at: elapsed) {
            let a = settings.character(forCreature: giver).name, b = settings.character(forCreature: receiver).name
            event = "\(a) just walked into \(b) and gave \(b) a \(flower)."
        }
        if !settings.talkEnabled || !talk(from: giver, to: receiver, because: event) { endChat(after: 2) }
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
        chat = (i, j, nil)
    }

    /// +1 when `j` is further round the loop from `i`, -1 when behind; on another
    /// loop there is nothing to face, so keep the current heading.
    func facing(_ i: Int, toward j: Int) -> CGFloat {
        let a = creatures[i], b = creatures[j]
        guard a.spot.loop == b.spot.loop else { return a.direction }
        return a.loop.wrap(b.t - a.t) < a.loop.length / 2 ? 1 : -1
    }

    /// The conversation is done, or never started: let them go in a moment.
    func endChat(after seconds: Double) {
        guard var current = chat else { return }
        current.releaseAt = min(current.releaseAt ?? .infinity, elapsed + seconds)
        chat = current
    }

    func releaseChat() {
        guard let chat else { return }
        for i in [chat.a, chat.b] where creatures.indices.contains(i) { creatures[i].walkOn(using: &rng) }
        self.chat = nil
    }

    /// Where a flower sits or lands: on the head, away from the edge.
    func head(of i: Int) -> CGPoint {
        let c = creatures[i], up = c.isHeld ? CGVector(dx: 0, dy: 1) : c.loop.inward(ofSegment: c.segment)
        let lift = (atlas.bodyHalfSize + flowerCell.height / 2) * CGFloat(sizes[i])
        return CGPoint(x: c.position.x + up.dx * lift, y: c.position.y + up.dy * lift)
    }

    /// Let the pair go once the reply is out, or as soon as one of them is no longer standing there.
    func releaseChatIfOver() {
        guard let chat else { return }
        let stillThere = [chat.a, chat.b].allSatisfy { creatures.indices.contains($0) && creatures[$0].isChatting }
        if !stillThere || (chat.releaseAt.map { $0 <= elapsed } ?? false) { releaseChat() }
    }

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

    /// One creature says a line to another; the other answers. Runs in the background.
    /// Returns false when it could not even start, so the caller can release the pair.
    @discardableResult
    func talk(from speaker: Int, to listener: Int, because event: String? = nil) -> Bool {
        guard !talking, creatures.indices.contains(speaker), creatures.indices.contains(listener) else { return false }
        guard let service = settings.chatClient() else { talkStatus = settings.brainProblem; return false }
        let a = settings.character(forCreature: speaker), b = settings.character(forCreature: listener)
        var situation = "It is \(isNight ? "night" : "day"). \(describe(speaker)). \(describe(listener))."
        if let event { situation += " " + event }
        var vars = ["speaker": a.name, "speakerPersona": a.persona, "listener": b.name,
                    "listenerPersona": b.persona, "situation": situation, "line": ""]
        let system = settings.systemPrompt, linePrompt = settings.linePrompt, replyPrompt = settings.replyPrompt
        let bubbleSeconds = settings.bubbleSeconds

        talking = true
        talkStatus = "asking \(service.model) via \(service.provider.title)…"
        Task { [weak self] in
            defer { self?.talking = false; self?.endChat(after: 1.2) }
            do {
                try await service.checkModel()
                let first = Banter.cleanLine(
                    try await service.reply(system: Banter.render(system, vars), user: Banter.render(linePrompt, vars)),
                    speaker: a.name)
                guard let self else { return }
                guard !first.isEmpty else { talkStatus = "the model sent an empty line"; return }
                say(first, from: speaker)
                talkStatus = "\(a.name): \(first)"

                // Swap seats for the answer.
                vars["speaker"] = b.name; vars["speakerPersona"] = b.persona
                vars["listener"] = a.name; vars["listenerPersona"] = a.persona; vars["line"] = first
                let reply = Banter.cleanLine(
                    try await service.reply(system: Banter.render(system, vars), user: Banter.render(replyPrompt, vars)),
                    speaker: b.name)
                try await Task.sleep(for: .seconds(Banter.showTime(first, base: bubbleSeconds) * 0.6))
                guard !reply.isEmpty else { return }
                say(reply, from: listener)
                talkStatus = "\(b.name): \(reply)"
            } catch {
                self?.talkStatus = "\(error)"
                FileHandle.standardError.write(Data("Ledgelings talk: \(error)\n".utf8))
            }
        }
        return true
    }

    func say(_ text: String, from index: Int) {
        guard creatures.indices.contains(index) else { return }
        bubbles[index] = (text, elapsed + Banter.showTime(text, base: settings.bubbleSeconds))
        render()
    }

    /// The creature whose speech bubble is under `point`, on any monitor.
    func bubble(at point: CGPoint) -> Int? {
        overlays.lazy.compactMap { $0.bubbleIndex(at: point) }.first
    }
}

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
        guard !talking, !hideout.isActive else { return }
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
        let started = Date()
        var spoken: [ChatLog.Line] = []
        /// Whatever was actually said goes to the log, even a one-sided exchange.
        func keep() {
            guard !spoken.isEmpty else { return }
            history.record(ChatLog.Exchange(time: started, situation: situation, provider: service.provider.title,
                                            model: service.model, lines: spoken))
        }

        talking = true
        talkStatus = "asking \(service.model) via \(service.provider.title)…"
        Task { [weak self] in
            defer { self?.talking = false; self?.endChat(after: 1.2); keep() }
            do {
                try await service.checkModel()
                let first = Banter.cleanLine(
                    try await service.reply(system: Banter.render(system, vars), user: Banter.render(linePrompt, vars)),
                    speaker: a.name)
                guard let self else { return }
                guard !first.isEmpty else { talkStatus = "the model sent an empty line"; return }
                say(first, from: speaker)
                spoken.append(ChatLog.Line(speaker: a.name, text: first))
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
                spoken.append(ChatLog.Line(speaker: b.name, text: reply))
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

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

    /// Who creature `i` is: the k-th creature wearing its species takes the k-th
    /// character of that species' cast, wrapping round.
    func character(forCreature i: Int) -> Character {
        let species = settings.species(forCreature: i)
        let cast = settings.cast(of: species, fallback: library.cast(of: species))
        guard !cast.isEmpty else { return Character(name: "Ledgeling \(i + 1)", persona: "") }
        let k = (0..<i).filter { settings.species(forCreature: $0) == species }.count
        return cast[k % cast.count]
    }

    func kind(ofCreature i: Int) -> String { library.kind(of: settings.species(forCreature: i)) }

    func describe(_ i: Int) -> String {
        let c = creatures[i], name = character(forCreature: i).name
        if c.isHeld { return "\(name) is dangling from the user's cursor" }
        if c.isJumping { return "\(name) is mid-jump" }
        return "\(name) is \(c.isSleeping ? "asleep on" : "on") \(edgeName(c))"
    }

    /// "Make Someone Talk" from the menu, or a Shift-poke on `chosen`: the speaker
    /// says something to the nearest creature that is not already talking.
    func talkNow(from chosen: Int? = nil) {
        guard creatures.count >= 2 else { talkStatus = "needs at least two creatures"; return }
        guard !hideout.isActive else { return }
        let free = creatures.indices.filter { !busy.contains($0) }
        let awake = free.filter { !creatures[$0].isSleeping && !creatures[$0].isJumping }
        guard let speaker = chosen ?? (awake.isEmpty ? free : awake).randomElement(using: &rng),
              creatures.indices.contains(speaker), !busy.contains(speaker) else { talkStatus = "everyone is mid-conversation"; return }
        let me = creatures[speaker].position
        guard let listener = free.filter({ $0 != speaker }).min(by: {
            hypot(creatures[$0].position.x - me.x, creatures[$0].position.y - me.y)
                < hypot(creatures[$1].position.x - me.x, creatures[$1].position.y - me.y)
        }) else { talkStatus = "nobody free to listen"; return }
        hold(speaker, and: listener)
        if !talk(from: speaker, to: listener) { endChat(speaker, listener, after: 1) }
    }

    /// One creature says a line to another; the other answers. With a model, this
    /// runs in the background; other pairs can talk at the same time. Returns
    /// false when it could not even start, so the caller can release the pair.
    /// `flower`: the one just given, for a line about it.
    @discardableResult
    func talk(from speaker: Int, to listener: Int, because event: String? = nil, flower: String? = nil) -> Bool {
        guard creatures.indices.contains(speaker), creatures.indices.contains(listener), speaker != listener,
              !busy.contains(speaker), !busy.contains(listener) else { return false }
        let a = character(forCreature: speaker), b = character(forCreature: listener)
        var situation = "It is \(isNight ? "night" : "day"). \(describe(speaker)). \(describe(listener))."
        if let event { situation += " " + event }
        if settings.brain == .script {
            return recite(from: speaker, to: listener, flower: flower, situation: situation)
        }
        guard let service = settings.chatClient() else { talkStatus = settings.brainProblem; return false }
        let aKind = kind(ofCreature: speaker), bKind = kind(ofCreature: listener)
        var vars = ["speaker": a.name, "speakerKind": aKind, "speakerPersona": a.persona,
                    "listener": b.name, "listenerKind": bKind, "listenerPersona": b.persona,
                    "situation": situation, "line": ""]
        let system = settings.systemPrompt, linePrompt = settings.linePrompt, replyPrompt = settings.replyPrompt
        let bubbleSeconds = settings.bubbleSeconds
        let started = Date()
        var spoken: [ChatLog.Line] = []
        var used: [Spend.Usage] = []
        /// Whatever was actually said goes to the log, with what it cost, even a one-sided exchange.
        func keep() {
            guard !spoken.isEmpty else { return }
            let priced = used.compactMap(\.cost)
            history.record(ChatLog.Exchange(time: started, situation: situation, provider: service.provider.title,
                                            model: service.model, lines: spoken,
                                            cost: priced.isEmpty ? nil : priced.reduce(0, +),
                                            tokens: used.isEmpty ? nil : used.reduce(0) { $0 + $1.promptTokens + $1.completionTokens }))
        }
        /// Every call goes to the spend file, even one whose line turned out empty.
        func charge(_ answer: ChatClient.Answer) {
            guard var usage = answer.usage else { return }
            if service.provider == .lmStudio { usage.cost = 0 }                // a local model is free
            used.append(usage)
            spend.record(provider: service.provider, model: service.model, usage: usage)
        }

        busy.formUnion([speaker, listener])
        talkStatus = "asking \(service.model) via \(service.provider.title)…"
        Task { [weak self] in
            defer {
                self?.busy.subtract([speaker, listener])
                self?.endChat(speaker, listener, after: 1.2)
                keep()
            }
            do {
                try await service.checkModel()
                let opening = try await service.reply(system: Banter.render(system, vars), user: Banter.render(linePrompt, vars))
                guard let self else { return }
                charge(opening)
                let first = Banter.cleanLine(opening.text, speaker: a.name)
                guard !first.isEmpty else { talkStatus = "the model sent an empty line"; return }
                say(first, from: speaker)
                spoken.append(ChatLog.Line(speaker: a.name, text: first))
                talkStatus = "\(a.name): \(first)"

                // Swap seats for the answer.
                vars["speaker"] = b.name; vars["speakerKind"] = bKind; vars["speakerPersona"] = b.persona
                vars["listener"] = a.name; vars["listenerKind"] = aKind; vars["listenerPersona"] = a.persona
                vars["line"] = first
                let answer = try await service.reply(system: Banter.render(system, vars), user: Banter.render(replyPrompt, vars))
                charge(answer)
                let reply = Banter.cleanLine(answer.text, speaker: b.name)
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

    // MARK: The built-in lines

    /// A line from the script, waiting for its moment.
    struct ScheduledLine {
        var at: Double
        var speaker: Int
        var text: String
        /// The pair to let go once this, their last line, is out.
        var closes: (Int, Int)?
    }

    /// Say a conversation from the script: the first line now, each next one
    /// when the one before has been up a while. Written to the log up front.
    private func recite(from speaker: Int, to listener: Int, flower: String?, situation: String) -> Bool {
        let script: Script
        do { script = try Script.parse(settings.script) } catch { talkStatus = "the built-in lines: \(error)"; return false }
        var moment: Set<String> = [isNight ? "night" : "day"]
        if flower != nil { moment.insert("flower") }
        guard let chosen = script.pick(for: moment, avoiding: recentLines, using: &rng) else {
            talkStatus = "no built-in line fits right now"; return false
        }
        recentLines = Array((recentLines + [chosen]).suffix(max(1, script.conversations.count / 2)))
        let a = character(forCreature: speaker), b = character(forCreature: listener)
        let lines = script.conversations[chosen].lines.enumerated().map { i, line in
            let mine = i.isMultiple(of: 2)
            return (who: mine ? speaker : listener,
                    text: Script.fill(line, speaker: mine ? a.name : b.name, listener: mine ? b.name : a.name, flower: flower))
        }
        busy.formUnion([speaker, listener])
        var at = elapsed
        for (i, line) in lines.enumerated() {
            let last = i == lines.count - 1
            scheduled.append(ScheduledLine(at: at, speaker: line.who, text: line.text, closes: last ? (speaker, listener) : nil))
            at += Banter.showTime(line.text, base: settings.bubbleSeconds) * 0.6
        }
        sayScheduledLines()
        history.record(ChatLog.Exchange(time: Date(), situation: situation, provider: AppSettings.Brain.script.title, model: "",
                                        lines: lines.map { ChatLog.Line(speaker: character(forCreature: $0.who).name, text: $0.text) }))
        return true
    }

    /// Every frame: the scripted lines whose time has come.
    func sayScheduledLines() {
        let due = scheduled.filter { $0.at <= elapsed }
        guard !due.isEmpty else { return }
        scheduled.removeAll { $0.at <= elapsed }
        for line in due {
            if creatures.indices.contains(line.speaker) {
                say(line.text, from: line.speaker)
                talkStatus = "\(character(forCreature: line.speaker).name): \(line.text)"
            }
            if let (i, j) = line.closes {
                busy.subtract([i, j])
                endChat(i, j, after: 1.2)
            }
        }
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

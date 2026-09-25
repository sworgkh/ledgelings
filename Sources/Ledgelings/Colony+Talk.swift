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
        let free = creatures.indices.filter { !busy.contains($0) && !expectsPlane($0) }
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
        guard !voiceIsTaken else { talkStatus = "someone else is talking; out loud it is one conversation at a time"; return false }
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
        // How the two get on, and the story between them, from each one's side.
        let aSide = relationship(of: speaker, with: listener), bSide = relationship(of: listener, with: speaker)
        let plot = plotLabel(speaker, listener)
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
                                            tokens: used.isEmpty ? nil : used.reduce(0) { $0 + $1.promptTokens + $1.completionTokens },
                                            plot: plot))
        }
        /// Every call goes to the spend file, even one whose line turned out empty.
        func charge(_ answer: ChatClient.Answer) {
            guard var usage = answer.usage else { return }
            if service.provider == .lmStudio { usage.cost = 0 }                // a local model is free
            used.append(usage)
            spend.record(provider: service.provider, model: service.model, usage: usage, purpose: .talk)
        }

        busy.formUnion([speaker, listener])
        talkStatus = "asking \(service.model) via \(service.provider.title)…"
        let voiced = isVoiced
        if voiced { voicedDialogues += 1 }
        Task { [weak self] in
            defer {
                if voiced { self?.voicedDialogues -= 1 }
                self?.busy.subtract([speaker, listener])
                self?.endChat(speaker, listener, after: 1.2)
                keep()
                self?.talked(a.name, b.name, lines: spoken)
            }
            do {
                try await service.checkModel()
                let opening = try await service.reply(system: Bonds.withRelationship(system, vars, context: aSide),
                                                      user: Banter.render(linePrompt, vars))
                guard let self else { return }
                charge(opening)
                let first = Banter.cleanLine(opening.text, speaker: a.name)
                guard !first.isEmpty else { talkStatus = "the model sent an empty line"; return }
                let firstSaid = say(first, from: speaker)
                spoken.append(ChatLog.Line(speaker: a.name, text: first))
                talkStatus = "\(a.name): \(first)"

                // Swap seats for the answer.
                vars["speaker"] = b.name; vars["speakerKind"] = bKind; vars["speakerPersona"] = b.persona
                vars["listener"] = a.name; vars["listenerKind"] = aKind; vars["listenerPersona"] = a.persona
                vars["line"] = first
                let answer = try await service.reply(system: Bonds.withRelationship(system, vars, context: bSide),
                                                     user: Banter.render(replyPrompt, vars))
                charge(answer)
                let reply = Banter.cleanLine(answer.text, speaker: b.name)
                guard !reply.isEmpty else { await said(firstSaid); return }
                if isVoiced {
                    // Out loud, the answer comes a beat after the first line ends, its
                    // sound fetched meanwhile, not on the silent-bubble clock.
                    voice?.prefetch(reply, as: b.name)
                    await said(firstSaid)
                    try await Task.sleep(for: .seconds(turnPause))
                } else {
                    try await Task.sleep(for: .seconds(Banter.showTime(first, base: bubbleSeconds) * 0.6))
                }
                let replySaid = say(reply, from: listener)
                spoken.append(ChatLog.Line(speaker: b.name, text: reply))
                talkStatus = "\(b.name): \(reply)"
                await said(replySaid)          // the pair stays face to face until it is said
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
        history.record(ChatLog.Exchange(time: Date(), situation: situation, provider: AppSettings.Brain.script.title, model: "",
                                        lines: lines.map { ChatLog.Line(speaker: character(forCreature: $0.who).name, text: $0.text) }))
        if isVoiced {
            sayInTurns(lines) { [weak self] in
                self?.busy.subtract([speaker, listener])
                self?.endChat(speaker, listener, after: 1.2)
            }
            return true
        }
        var at = elapsed
        for (i, line) in lines.enumerated() {
            let last = i == lines.count - 1
            scheduled.append(ScheduledLine(at: at, speaker: line.who, text: line.text, closes: last ? (speaker, listener) : nil))
            at += Banter.showTime(line.text, base: settings.bubbleSeconds) * 0.6
        }
        sayScheduledLines()
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

    /// Put `text` up in creature `index`'s bubble. With voice on, the bubble
    /// shows dots until the sound is ready, then types the line out as it is said.
    /// Returns the line's serial, for `whenSaid`.
    @discardableResult
    func say(_ text: String, from index: Int) -> Int {
        guard creatures.indices.contains(index) else { return 0 }
        bubbleSerial += 1
        let serial = bubbleSerial
        bubbles[index] = Bubble(text: text, until: elapsed + Banter.showTime(text, base: settings.bubbleSeconds), serial: serial)
        let voiced = voice?.say(text, as: character(forCreature: index).name) { [weak self] cue in
            self?.heard(cue, bubble: serial, of: index)
        } ?? false
        if voiced {
            bubbles[index]?.reveal = .waiting(since: elapsed)
            bubbles[index]?.until = elapsed + Self.longestWaitForVoice
            voicedLines.insert(serial)
        }
        render()
        trace?("say #\(serial) \(character(forCreature: index).name)\(voiced ? " (voiced)" : ""): \(text)")
        return serial
    }

    /// Line `serial` is over: whatever waits for it goes on.
    func endLine(_ serial: Int) {
        voicedLines.remove(serial)
        afterLine.removeValue(forKey: serial)?.forEach { $0() }
    }

    // MARK: Taking turns out loud

    /// True when lines are being said out loud: the next line of a dialogue then
    /// waits for the one before to end, instead of the silent-bubble clock.
    var isVoiced: Bool { voice != nil && settings.voiceEnabled }

    /// Out loud, someone is mid-conversation: another pair meeting now only
    /// bumps, and a plane that lands waits to be read, rather than talking over them.
    var voiceIsTaken: Bool { isVoiced && voicedDialogues > 0 }

    /// Run `action` once line `serial` has been said (or will not be): at once for
    /// a line that is not being voiced or has already ended.
    func whenSaid(_ serial: Int, _ action: @escaping () -> Void) {
        if voicedLines.contains(serial) { afterLine[serial, default: []].append(action) } else { action() }
    }

    /// Suspend until line `serial` has been said.
    func said(_ serial: Int) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in whenSaid(serial) { done.resume() } }
    }

    /// The beat between one voiced line ending and the next starting.
    var turnPause: Double { settings.voiceTurnPause }

    /// Say `lines` one after another, each starting a beat after the one before
    /// has been said, the sound of each fetched ahead of its turn; then `done`.
    /// A line that cannot be voiced waits the silent-bubble time instead.
    func sayInTurns(_ lines: [(who: Int, text: String)], then done: @escaping () -> Void) {
        for line in lines.dropFirst() where creatures.indices.contains(line.who) {
            voice?.prefetch(line.text, as: character(forCreature: line.who).name)
        }
        voicedDialogues += 1
        sayTurn(lines[...]) { [weak self] in
            self?.voicedDialogues -= 1
            done()
        }
    }

    private func sayTurn(_ lines: ArraySlice<(who: Int, text: String)>, then done: @escaping () -> Void) {
        guard let line = lines.first else { done(); return }
        guard creatures.indices.contains(line.who) else { sayTurn(lines.dropFirst(), then: done); return }
        let serial = say(line.text, from: line.who)
        let voiced = voicedLines.contains(serial)
        let wait = voiced ? turnPause : Banter.showTime(line.text, base: settings.bubbleSeconds) * 0.6
        whenSaid(serial) { [weak self] in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                self?.sayTurn(lines.dropFirst(), then: done)
            }
        }
    }

    /// A bubble waiting on its sound gives up after this, even if the voice never says why.
    static let longestWaitForVoice = 45.0

    /// The voice's news about a bubble's line.
    func heard(_ cue: Voice.Cue, bubble serial: Int, of index: Int) {
        // Whatever waits for this line goes on even if its bubble was since replaced.
        if case .progress = cue {} else { trace?("cue #\(serial) \(cue)") }
        if cue == .done || cue == .dropped { endLine(serial) }
        guard var bubble = bubbles[index], bubble.serial == serial else { return }
        let showTime = Banter.showTime(bubble.text, base: settings.bubbleSeconds)
        switch cue {
        case .started(let duration?):
            bubble.reveal = .timed(start: elapsed, duration: duration)
            bubble.until = elapsed + max(showTime, duration + 2)
        case .started(nil):
            bubble.reveal = .spoken(0)
            bubble.until = elapsed + Self.longestWaitForVoice
        case .progress(let share):
            if case .spoken(let before) = bubble.reveal { bubble.reveal = .spoken(max(before, share)) }
        case .done:
            bubble.reveal = .all
            bubble.until = max(min(bubble.until, elapsed + showTime), elapsed + 2)
        case .dropped:
            bubble.reveal = .all
            bubble.until = elapsed + showTime
        }
        bubbles[index] = bubble
    }

    /// The creature whose speech bubble is under `point`, on any monitor.
    func bubble(at point: CGPoint) -> Int? {
        overlays.lazy.compactMap { $0.bubbleIndex(at: point) }.first
    }
}

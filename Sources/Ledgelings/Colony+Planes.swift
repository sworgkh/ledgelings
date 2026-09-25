import AppKit
import LedgelingsCore

/// Paper planes: after a long spell with no bumps, one creature folds a note
/// and throws it to another across the screen. The wind carries it about, a
/// dotted trail behind it; the catcher stops, reads the note out, then says
/// something to itself about it. Words come from `Letters`, or from the model.
extension Colony {
    /// One plane's life, from the throw to the last puff of its trail.
    struct Airmail {
        enum Phase {
            case flying
            /// Caught, but the model is still writing: the letter is in hand, unread.
            case waiting(since: Double)
            case reading(musingAt: Double, doneAt: Double, musingSaid: Bool)
            /// Missed: the catcher fell asleep or went home. The plane fades where it is.
            case dropped(since: Double)
            /// Read and put away; only the trail is still fading.
            case done
        }

        var id: Int
        var plane: PaperPlane
        var phase: Phase = .flying
        /// Written by the model while the plane flies; nil means use `Letters`.
        var note: String?
        var musing: String?
        var writing = false
        var provider = AppSettings.Brain.script.title
        var model = ""
        var cost: Double?
        var tokens: Int?
    }

    static let planeFade = 0.6
    static let planeGivesUpAfter = 30.0
    /// Longest the catcher holds an unread letter waiting for the model.
    static let modelWait = 8.0

    // MARK: Sending

    /// Throw a plane now, from anyone free to anyone free. False when nobody can.
    @discardableResult
    func sendPlane() -> Bool {
        guard airmail == nil else { talkStatus = "a paper plane is already in the air"; return false }
        guard !hideout.isActive else { return false }
        var free: [Int: CGPoint] = [:]
        for i in creatures.indices where canHandleMail(i) { free[i] = creatures[i].position }
        guard let (from, to) = Post.pickPair(free, using: &rng) else { talkStatus = "nobody free to throw or catch a plane"; return false }

        creatures[from].meet(facing: facing(from, toward: to), for: 0.9)       // a short stop for the throw
        let inward = creatures[from].loop.inward(ofSegment: creatures[from].segment)
        planeCount += 1
        airmail = Airmail(id: planeCount, plane: PaperPlane(from: from, to: to, start: head(of: from), inward: inward, target: head(of: to)))
        post.stir(at: elapsed)
        if settings.talkEnabled { writeWithModel(from: from, to: to, id: planeCount) }
        return true
    }

    /// A plane is on its way to `i`: it keeps out of conversations so it is free to catch it.
    func expectsPlane(_ i: Int) -> Bool {
        guard let mail = airmail, mail.plane.to == i, case .flying = mail.phase else { return false }
        return true
    }

    /// Awake, on an edge, not talking, not in the hand, not in the house.
    func canHandleMail(_ i: Int) -> Bool {
        let c = creatures[i]
        return !busy.contains(i) && !hideout.isInside(i) && !c.isJumping && !c.isHeld && !c.looksAsleep && !c.isChatting
    }

    /// With a model: the note as the sender, then the reader's thought about it,
    /// both while the plane is still in the air.
    private func writeWithModel(from: Int, to: Int, id: Int) {
        guard settings.brain != .script, let service = settings.chatClient() else { return }
        let a = character(forCreature: from), b = character(forCreature: to)
        let aKind = kind(ofCreature: from), bKind = kind(ofCreature: to)
        var vars = ["speaker": a.name, "speakerKind": aKind, "speakerPersona": a.persona,
                    "listener": b.name, "listenerKind": bKind, "listenerPersona": b.persona,
                    "situation": "", "line": ""]
        let system = settings.systemPrompt
        airmail?.writing = true
        airmail?.provider = service.provider.title
        airmail?.model = service.model
        talkStatus = "\(a.name) is writing a letter via \(service.model)…"
        var used: [Spend.Usage] = []
        /// Every call goes to the spend file, even one whose line turned out empty.
        func charge(_ answer: ChatClient.Answer) {
            guard var usage = answer.usage else { return }
            if service.provider == .lmStudio { usage.cost = 0 }
            used.append(usage)
            spend.record(provider: service.provider, model: service.model, usage: usage)
        }
        Task { [weak self] in
            var note: String?, musing: String?
            do {
                try await service.checkModel()
                let written = try await service.reply(system: Banter.render(system, vars), user: Banter.render(Letters.notePrompt, vars))
                charge(written)
                let line = Banter.cleanLine(written.text, speaker: a.name)
                if !line.isEmpty {
                    note = line
                    // Swap seats: now the reader thinks.
                    vars["speaker"] = b.name; vars["speakerKind"] = bKind; vars["speakerPersona"] = b.persona
                    vars["listener"] = a.name; vars["listenerKind"] = aKind; vars["listenerPersona"] = a.persona
                    vars["line"] = line
                    let thought = try await service.reply(system: Banter.render(system, vars), user: Banter.render(Letters.musingPrompt, vars))
                    charge(thought)
                    let said = Banter.cleanLine(thought.text, speaker: b.name)
                    if !said.isEmpty { musing = said }
                }
            } catch {
                self?.talkStatus = "\(error)"
                FileHandle.standardError.write(Data("Ledgelings letter: \(error)\n".utf8))
            }
            guard let self, airmail?.id == id else { return }
            airmail?.note = note
            airmail?.musing = musing
            airmail?.writing = false
            let priced = used.compactMap(\.cost)
            airmail?.cost = priced.isEmpty ? nil : priced.reduce(0, +)
            airmail?.tokens = used.isEmpty ? nil : used.reduce(0) { $0 + $1.promptTokens + $1.completionTokens }
        }
    }

    // MARK: Every frame

    func updatePost(dt: Double) {
        post.quietFor = settings.planesEnabled ? settings.planeMinutes * 60 : 0
        if airmail == nil, post.isDue(at: elapsed) {
            if isNight || hideout.isActive || !sendPlane() { post.retry(at: elapsed, in: 10) }
        }
        guard var mail = airmail else { return }
        let from = mail.plane.from, to = mail.plane.to
        guard creatures.indices.contains(from), creatures.indices.contains(to) else {
            letters.removeAll(); airmail = nil; busy.remove(to); return
        }

        switch mail.phase {
        case .flying:
            if hideout.isActive || hideout.isInside(to) { mail.phase = .dropped(since: elapsed); break }
            let target = head(of: to)
            mail.plane.fly(dt: dt, toward: target, wind: wind, time: elapsed)
            let reach = atlas.bodyHalfSize * CGFloat(sizes[to]) + 10
            if mail.plane.distance(to: target) <= reach {
                if canHandleMail(to) {
                    mail.phase = catchPlane(&mail)
                } else if creatures[to].looksAsleep {
                    mail.phase = .dropped(since: elapsed)
                }
            }
            if case .flying = mail.phase, mail.plane.age > Self.planeGivesUpAfter { mail.phase = .dropped(since: elapsed) }

        case .waiting(let since):
            mail.plane.fadeTrail(dt: dt)
            if !mail.writing || elapsed - since > Self.modelWait { mail.phase = startReading(&mail) }

        case .reading(let musingAt, let doneAt, let musingSaid):
            mail.plane.fadeTrail(dt: dt)
            if !musingSaid, elapsed >= musingAt {
                if settings.talkEnabled, let musing = mail.musing { say(musing, from: to) }
                mail.phase = .reading(musingAt: musingAt, doneAt: doneAt, musingSaid: true)
            } else if elapsed >= doneAt {
                letters.removeValue(forKey: to)
                busy.remove(to)
                creatures[to].walkOn(using: &rng)
                mail.phase = .done
            }

        case .dropped(let since):
            mail.plane.fadeTrail(dt: dt)
            if elapsed - since >= Self.planeFade, mail.plane.trail.isEmpty { airmail = nil; return }

        case .done:
            mail.plane.fadeTrail(dt: dt)
            if mail.plane.trail.isEmpty { airmail = nil; return }
        }
        airmail = mail
    }

    /// The catcher stops and holds the letter; it reads as soon as the words are there.
    private func catchPlane(_ mail: inout Airmail) -> Airmail.Phase {
        let to = mail.plane.to
        creatures[to].meet(facing: creatures[to].direction, for: 120)
        busy.insert(to)
        letters[to] = true
        return mail.writing ? .waiting(since: elapsed) : startReading(&mail)
    }

    /// The note is read out, the thought follows, and it all goes in the chat history.
    private func startReading(_ mail: inout Airmail) -> Airmail.Phase {
        let from = mail.plane.from, to = mail.plane.to
        let a = character(forCreature: from).name, b = character(forCreature: to).name
        let modelWrote = mail.note != nil
        let note = mail.note ?? Letters.note(by: a, to: b, using: &rng)
        let musing = mail.musing ?? Letters.musing(by: b, from: a, using: &rng)
        mail.note = note
        mail.musing = musing
        guard settings.talkEnabled else { return .reading(musingAt: elapsed, doneAt: elapsed + 3, musingSaid: true) }

        let read = Letters.reading(note, from: a)
        say(read, from: to)
        talkStatus = "\(b) got a paper plane from \(a)"
        let musingAt = elapsed + Banter.showTime(read, base: settings.bubbleSeconds) * 0.6
        let doneAt = musingAt + Banter.showTime(musing, base: settings.bubbleSeconds) * 0.6 + 1
        history.record(ChatLog.Exchange(
            time: Date(), situation: "\(a) sent \(b) a paper plane.",
            provider: modelWrote ? mail.provider : AppSettings.Brain.script.title, model: modelWrote ? mail.model : "",
            lines: [ChatLog.Line(speaker: a, text: note), ChatLog.Line(speaker: b, text: musing)],
            cost: mail.cost, tokens: mail.tokens))
        return .reading(musingAt: musingAt, doneAt: doneAt, musingSaid: false)
    }

    // MARK: Drawing

    func planeSnapshot() -> PlaneSnapshot? {
        guard let mail = airmail else { return nil }
        let to = mail.plane.to
        let scale = CGFloat(sizes.indices.contains(to) ? sizes[to] : 2)
        var opacity: Float = 0
        switch mail.phase {
        case .flying: opacity = 1
        case .dropped(let since): opacity = Float(max(0, 1 - (elapsed - since) / Self.planeFade))
        default: opacity = 0
        }
        let life = mail.plane.puffLife
        return PlaneSnapshot(
            image: planeFrames.frame(animation: "fly", time: 0),
            position: mail.plane.position, heading: mail.plane.heading, scale: scale, opacity: opacity,
            trail: mail.plane.trail.map { ($0.position, Float(max(0, 1 - $0.age / life)) * 0.8) },
            puffSize: max(2, (scale * 1.5).rounded()))
    }

    func letterImage(for i: Int) -> CGImage? {
        letters[i] == true ? planeFrames.frame(animation: "letter", time: 0) : nil
    }
}

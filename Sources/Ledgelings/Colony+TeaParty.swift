import AppKit
import LedgelingsCore

/// Tea parties: now and then a bump does not end in a word in passing. The two
/// step back, a little table with a teapot and two cups comes up between them,
/// and they sit and tell each other stories from their lives, one each in turn,
/// for a few minutes (`TeaParty`). One party at a time.
extension Colony {

    /// Seat `i` and `j`, who are already stopped face to face, at a table between
    /// them. False when there is no room: a table would stick round a corner.
    @discardableResult
    func startTea(_ i: Int, _ j: Int) -> Bool {
        guard teaParty == nil, creatures.indices.contains(i), creatures.indices.contains(j), i != j,
              creatures[i].isChatting, creatures[j].isChatting,
              creatures[i].spot.loop == creatures[j].spot.loop, creatures[i].segment == creatures[j].segment else { return false }
        let scale = CGFloat(sizes[i] + sizes[j]) / 2
        let half = teaCell.width / 2 * scale
        let pi = creatures[i].position, pj = creatures[j].position
        let between = CGPoint(x: (pi.x + pj.x) / 2, y: (pi.y + pj.y) / 2)
        var seats: [(Int, CGFloat)] = []
        for k in [i, j] {
            let c = creatures[k], loop = c.loop
            let middle = loop.point(at: loop.nearest(to: between).t)
            // Tucked in two sheet pixels, so the table's ends sit just under their bodies.
            let reach = half + atlas.bodyHalfSize * CGFloat(sizes[k]) - 2 * scale
            guard let seat = TeaParty.seat(on: loop, segment: c.segment, middle: middle, facing: c.direction, offset: reach) else { return false }
            seats.append((k, seat))
        }
        let c = creatures[i], middle = c.loop.point(at: c.loop.nearest(to: between).t)
        let up = c.loop.inward(ofSegment: c.segment), lift = atlas.bodyHalfSize * CGFloat(sizes[i])
        teaTable = (CGPoint(x: middle.x - up.dx * lift, y: middle.y - up.dy * lift), c.restingRotation, scale)
        for (k, seat) in seats { creatures[k].sit(at: seat, facing: creatures[k].direction) }
        teaCount += 1
        teaRoundEnds = nil
        teaParty = TeaParty(a: i, b: j, at: elapsed, length: settings.teaPartyMinutes * 60, pause: settings.teaSipSeconds)
        teaLines = []
        teaTold = []
        busy.formUnion([i, j])
        let a = character(forCreature: i).name, b = character(forCreature: j).name
        talkStatus = "\(a) and \(b) are having tea"
        trace?("tea: \(a) and \(b) sit down")
        return true
    }

    /// "Have a Tea Party": the closest two who share an edge sit down now; if
    /// nobody does, one jumps over to another and they sit down once it lands.
    func teaNow() {
        guard teaParty == nil, teaInvite == nil, !hideout.isActive else { return }
        let free = creatures.indices.filter { i in
            let c = creatures[i]
            return !busy.contains(i) && !expectsPlane(i) && !c.isJumping && !c.isHeld && !c.isChatting && !c.isSleeping
        }
        guard free.count >= 2 else { talkStatus = "needs two creatures who are awake and free"; return }
        func apart(_ i: Int, _ j: Int) -> CGFloat {
            hypot(creatures[i].position.x - creatures[j].position.x, creatures[i].position.y - creatures[j].position.y)
        }
        var pairs: [(Int, Int)] = []
        for i in free { for j in free where j > i { pairs.append((i, j)) } }
        let neighbours = pairs.filter { creatures[$0.0].spot.loop == creatures[$0.1].spot.loop && creatures[$0.0].segment == creatures[$0.1].segment }
        for (i, j) in neighbours.sorted(by: { apart($0.0, $0.1) < apart($1.0, $1.1) }) {
            hold(i, and: j)
            if startTea(i, j) { return }
            endChat(i, j, after: 0)
        }
        // Nobody shares an edge: the guest jumps to just in front of the host.
        guard let (host, guest) = pairs.min(by: { apart($0.0, $0.1) < apart($1.0, $1.1) }) else { return }
        let h = creatures[host]
        let along = h.loop.direction(ofSegment: h.segment), gap = teaCell.width * CGFloat(sizes[host] + sizes[guest]) / 2
        let landing = CGPoint(x: h.position.x + along.dx * h.direction * gap, y: h.position.y + along.dy * h.direction * gap)
        creatures[guest].leap(to: creatures[guest].world.nearest(to: landing))
        teaInvite = (host, guest, elapsed + 5)
        trace?("tea: \(character(forCreature: guest).name) jumps over to \(character(forCreature: host).name)")
    }

    /// Every frame: the invited guest landing, the party's own clock, and
    /// breaking it up when one of them is no longer sitting there.
    func updateTeaParty() {
        if let invite = teaInvite {
            let ok = creatures.indices.contains(invite.host) && creatures.indices.contains(invite.guest)
            if !ok || elapsed > invite.until {
                teaInvite = nil
                trace?("tea: the guest never landed beside the host")
            } else if creatures[invite.guest].hasArrived {
                teaInvite = nil
                let h = creatures[invite.host]
                // The host got caught up in something else meanwhile: the guest, left
                // waiting where it landed, just walks on.
                guard !busy.contains(invite.host), !h.isChatting, !h.isJumping, !h.isHeld, !h.looksAsleep else {
                    let g = creatures[invite.guest]
                    creatures[invite.guest].emerge(at: g.spot, facing: g.direction, using: &rng)
                    trace?("tea: the host is busy")
                    return
                }
                hold(invite.host, and: invite.guest)
                trace?("tea: \(character(forCreature: invite.guest).name) landed")
                // Landed round a corner from the host after all: a word instead.
                if !startTea(invite.host, invite.guest), !talk(from: invite.guest, to: invite.host) {
                    endChat(invite.host, invite.guest, after: 2)
                }
            }
        }
        guard let party = teaParty else { return }
        if let ends = teaRoundEnds, ends <= elapsed {
            teaRoundEnds = nil
            teaParty?.roundDone(at: elapsed)
        }
        let pair = [party.a, party.b]
        let sitting = pair.allSatisfy { creatures.indices.contains($0) && creatures[$0].isChatting }
        if party.isOn, !sitting { breakUpTea() }
        if teaParty?.phase == .seating, pair.allSatisfy({ creatures[$0].isSeated }) { teaParty?.seated(at: elapsed) }
        for event in teaParty?.update(at: elapsed) ?? [] {
            switch event {
            case .round(let teller, let listener): teaRound(teller: teller, listener: listener)
            case .finished:
                wrapUpTea()
                endChat(party.a, party.b, after: 0.5)
            }
        }
        if teaParty?.isOver == true { teaParty = nil; teaTable = nil }
    }

    /// End the party now: the table packs away, and the pair goes once quiet.
    func breakUpTea() {
        guard let party = teaParty, party.isOn else { return }
        teaParty?.end(at: elapsed)
        teaRoundEnds = nil
        // A scripted answer still to come goes unsaid: its speaker has left the table.
        scheduled.removeAll { party.involves($0.speaker) }
        wrapUpTea()
        endChat(party.a, party.b, after: 0.5)
        if teaParty?.isOver == true { teaParty = nil; teaTable = nil }
        trace?("tea: broken up")
    }

    /// The pair is free again, and the whole party counts as one conversation between them.
    private func wrapUpTea() {
        guard let party = teaParty else { return }
        busy.subtract([party.a, party.b])
        let lines = teaLines
        teaLines = []
        guard !lines.isEmpty, creatures.indices.contains(party.a), creatures.indices.contains(party.b) else { return }
        talked(character(forCreature: party.a).name, character(forCreature: party.b).name, lines: lines)
        trace?("tea: over after \(lines.count) lines")
    }

    /// The party this round belongs to is still going.
    private func teaGoesOn(_ count: Int) -> Bool { teaCount == count && teaParty?.isOn == true }

    private func teaSituation(_ teller: Int, _ listener: Int) -> String {
        let a = character(forCreature: teller).name, b = character(forCreature: listener).name
        var situation = "On the edge it is \(isNight ? "night" : "day"). \(a) and \(b) have put a little table out on "
            + "\(edgeName(creatures[teller])) and are sitting down to tea together."
        if !almanac.isEmpty { situation = almanac + " " + situation }
        return situation
    }

    /// One round: `teller` tells a story from its life, `listener` answers it.
    func teaRound(teller: Int, listener: Int) {
        guard settings.talkEnabled else { teaParty?.roundDone(at: elapsed); return }       // they only sip
        // Out loud there is one voice to go round: sip until the other conversation is over.
        guard !voiceIsTaken else { teaParty?.postpone(at: elapsed); return }
        guard settings.brain != .script, let service = settings.chatClient() else {
            builtInTeaRound(teller: teller, listener: listener); return
        }
        let count = teaCount
        let a = character(forCreature: teller), b = character(forCreature: listener)
        let aKind = kind(ofCreature: teller), bKind = kind(ofCreature: listener)
        let situation = teaSituation(teller, listener)
        var vars = ["speaker": a.name, "speakerKind": aKind, "speakerPersona": a.persona,
                    "listener": b.name, "listenerKind": bKind, "listenerPersona": b.persona,
                    "situation": situation, "party": Tea.transcript(teaLines), "line": ""]
        let aSide = relationship(of: teller, with: listener), bSide = relationship(of: listener, with: teller)
        let aLately = history.memory.recent(of: a.name), bLately = history.memory.recent(of: b.name)
        let plot = plotLabel(teller, listener)
        let started = Date()
        var spoken: [ChatLog.Line] = []
        var used: [Spend.Usage] = []
        func charge(_ answer: ChatClient.Answer) {
            guard var usage = answer.usage else { return }
            if service.provider == .lmStudio { usage.cost = 0 }                // a local model is free
            used.append(usage)
            spend.record(provider: service.provider, model: service.model, usage: usage, purpose: .teaParties)
        }
        /// Into the Chats tab with what it cost, whatever got said.
        func keep() {
            guard !spoken.isEmpty else { return }
            let priced = used.compactMap(\.cost)
            history.record(ChatLog.Exchange(time: started, situation: situation, provider: service.provider.title,
                                            model: service.model, lines: spoken,
                                            cost: priced.isEmpty ? nil : priced.reduce(0, +),
                                            tokens: used.isEmpty ? nil : used.reduce(0) { $0 + $1.promptTokens + $1.completionTokens },
                                            plot: plot))
        }
        talkStatus = "\(a.name) is telling \(b.name) a story via \(service.model)…"
        let voiced = isVoiced
        if voiced { voicedDialogues += 1 }
        Task { [weak self] in
            var fallBack = false
            defer {
                if voiced { self?.voicedDialogues -= 1 }
                keep()
                if let self, teaGoesOn(count) {
                    if fallBack { builtInTeaRound(teller: teller, listener: listener) } else { teaParty?.roundDone(at: elapsed) }
                }
            }
            do {
                try await service.checkModel()
                let opening = try await service.line(system: LineMemory.withRecent(Bonds.withRelationship(Tea.systemPrompt, vars, context: aSide), aLately),
                                                      user: Banter.render(Tea.storyPrompt, vars))
                guard let self else { return }
                charge(opening)
                guard teaGoesOn(count) else { return }
                var first = Banter.cleanLine(opening.text, speaker: a.name, cut: opening.cut)
                let firstBuiltIn = first.isEmpty
                if firstBuiltIn { first = Tea.story(by: a.name, avoiding: teaTold, using: &rng); teaTold.insert(first) }
                let firstSaid = say(first, from: teller, builtIn: firstBuiltIn)
                spoken.append(ChatLog.Line(speaker: a.name, text: first))
                teaLines.append(spoken[0])
                talkStatus = "\(a.name): \(first)"

                // Swap seats for the answer.
                vars["speaker"] = b.name; vars["speakerKind"] = bKind; vars["speakerPersona"] = b.persona
                vars["listener"] = a.name; vars["listenerKind"] = aKind; vars["listenerPersona"] = a.persona
                vars["line"] = first
                vars["party"] = Tea.transcript(teaLines)
                let answer = try await service.line(system: LineMemory.withRecent(Bonds.withRelationship(Tea.systemPrompt, vars, context: bSide), bLately),
                                                     user: Banter.render(Tea.replyPrompt, vars))
                charge(answer)
                var reply = Banter.cleanLine(answer.text, speaker: b.name, cut: answer.cut)
                let replyBuiltIn = reply.isEmpty
                if replyBuiltIn { reply = Tea.reply(by: b.name, to: a.name, using: &rng) }
                if isVoiced {
                    voice?.prefetch(reply, as: b.name, builtIn: replyBuiltIn)
                    await said(firstSaid)
                    try await Task.sleep(for: .seconds(turnPause))
                } else {
                    try await Task.sleep(for: .seconds(Banter.showTime(first, base: settings.bubbleSeconds) * 0.6))
                }
                guard teaGoesOn(count) else { return }
                let replySaid = say(reply, from: listener, builtIn: replyBuiltIn)
                spoken.append(ChatLog.Line(speaker: b.name, text: reply))
                teaLines.append(spoken[1])
                talkStatus = "\(b.name): \(reply)"
                await said(replySaid)
                // Silent, the answer stays up to be read before the next story starts.
                if !isVoiced { try await Task.sleep(for: .seconds(Banter.showTime(reply, base: settings.bubbleSeconds))) }
            } catch {
                self?.talkStatus = "\(error)"
                FileHandle.standardError.write(Data("Ledgelings tea: \(error)\n".utf8))
                // Nothing said yet: the built-in lines take this round instead.
                fallBack = spoken.isEmpty
            }
        }
    }

    /// A round from the built-in lines: a story this teller has not told at this party yet, and an answer.
    private func builtInTeaRound(teller: Int, listener: Int) {
        let count = teaCount
        let a = character(forCreature: teller).name, b = character(forCreature: listener).name
        let story = Tea.story(by: a, avoiding: teaTold, using: &rng)
        teaTold.insert(story)
        let reply = Tea.reply(by: b, to: a, using: &rng)
        let lines = [(who: teller, text: story, builtIn: true), (who: listener, text: reply, builtIn: true)]
        let spoken = [ChatLog.Line(speaker: a, text: story), ChatLog.Line(speaker: b, text: reply)]
        teaLines += spoken
        history.record(ChatLog.Exchange(time: Date(), situation: teaSituation(teller, listener),
                                        provider: AppSettings.Brain.script.title, model: "", lines: spoken))
        talkStatus = "\(a) is telling \(b) a story"
        if isVoiced {
            sayInTurns(lines) { [weak self] in
                guard let self, teaGoesOn(count) else { return }
                teaParty?.roundDone(at: elapsed)
            }
            return
        }
        // On the colony's clock, like the scripted talk: the answer when the story
        // has been up a while, the round over once the answer has been read.
        say(story, from: teller, builtIn: true)
        let answerAt = elapsed + Banter.showTime(story, base: settings.bubbleSeconds) * 0.6
        scheduled.append(ScheduledLine(at: answerAt, speaker: listener, text: reply))
        teaRoundEnds = answerAt + Banter.showTime(reply, base: settings.bubbleSeconds)
    }

    func teaTableSnapshot() -> TeaTableSnapshot? {
        guard let party = teaParty, let table = teaTable else { return nil }
        let grown = CGFloat(party.scale(at: elapsed))
        guard grown > 0 else { return nil }
        return TeaTableSnapshot(image: teaFrames.frame(animation: "steam", time: elapsed), floor: table.floor,
                                rotation: table.rotation, scale: table.scale * grown)
    }
}

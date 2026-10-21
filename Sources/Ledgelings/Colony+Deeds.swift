import AppKit
import LedgelingsCore

/// Deeds: what creatures say turns into what they do. A conversation or a
/// letter's prompt offers the deeds possible right now (`deedOptions`); the line
/// that comes back may carry a `DO:` tag (`Deeds.split`), which is checked and
/// taken (`took`). An invitation waits for its answer; a yes, or a deed of its
/// own, waits for both creatures to be free and is then done through the same
/// doors the rest of the app uses: `startPlay`, `startTea`, `gifts.give`,
/// `throwPlane`. Nothing here calls a model.
extension Colony {

    /// A deed agreed on, waiting for both to be free.
    struct AgreedDeed {
        var deed: Deeds.Deed
        /// Who does it, and with whom: for a game or tea, the one who asked leads.
        var by: Int
        var with: Int
        var until: Double
        /// Whose invitation it answers.
        var asked: String?
        /// The other has already leapt over, so the two can start.
        var leapt = false
    }

    var deedsOn: Bool { settings.deedsEnabled && settings.talkEnabled && !hideout.isActive }

    /// What creature `i` may do now with `j`. `letter`: it is writing to `j`, not
    /// standing face to face, so only invitations and a visit make sense.
    func deedOptions(_ i: Int, with j: Int, letter: Bool) -> Deeds.Options {
        var o = Deeds.Options()
        guard deedsOn, creatures.indices.contains(i), creatures.indices.contains(j), i != j else { return o }
        let a = name(i), b = name(j), now = elapsed, limits = settings.deedLimits
        func allowed(_ verb: String) -> Bool { deedLedger.refusal(verb, a, b, at: now, limits) == nil }
        o.answering = invitations.last { $0.from == b && $0.to == a }
        let asked = invitations.contains { Set([$0.from, $0.to]) == Set([a, b]) }
        if allowed("invite"), !asked {
            if settings.deedGames, settings.playEnabled, !isNight, play == nil {
                let due = ballGamesDue
                o.games = Deeds.invitable.filter { settings.enabledPlays.contains($0) && (!$0.isTeamGame || due.contains($0)) }
            }
            o.tea = settings.deedTea && settings.teaPartiesEnabled && teaParty == nil && teaInvite == nil
        }
        if letter {
            if settings.deedVisit, allowed("visit") { o.visit = [b] }
        } else {
            o.flower = settings.deedFlower && allowed("flower") && gifts.flight == nil && gifts.hat(of: j) == nil
            o.letter = settings.deedLetter && settings.planesEnabled && allowed("letter")
            o.follow = settings.deedFollow && allowed("follow")
            if settings.deedVisit, allowed("visit") {
                // The three nearest who are awake: a short list, a short prompt.
                let me = creatures[i].position
                o.visit = creatures.indices.filter { $0 != i && $0 != j && !creatures[$0].looksAsleep && !hideout.isInside($0) }
                    .sorted { hypot(creatures[$0].position.x - me.x, creatures[$0].position.y - me.y)
                        < hypot(creatures[$1].position.x - me.x, creatures[$1].position.y - me.y) }
                    .prefix(3).map(name)
            }
        }
        o.sleep = settings.deedSleep && isNight && !creatures[i].isSleeping && allowed("sleep")
        return o
    }

    /// What the prompt of `i`, speaking to `j`, says about deeds and notes; "" when nothing is offered.
    func deedPrompt(_ options: Deeds.Options, to j: Int) -> String {
        let notes = settings.memoryEnabled && settings.memoryNotes && settings.memoryFacts > 0
        var text = Deeds.prompt(options, notes: notes, listener: creatures.indices.contains(j) ? name(j) : "")
        // Only for the test flags: this time, the invitation is sure to come.
        if let offer = forcedOffer, options.answering == nil, check(.invite(offer), options) {
            text += " This time you do invite them: end with DO: invite \(offer.tag)."
        }
        return text
    }

    private func check(_ deed: Deeds.Deed, _ options: Deeds.Options) -> Bool { Deeds.check(deed, options) == nil }

    /// `relationship(of:with:)` with what the prompt says about deeds after it.
    func side(of i: Int, with j: Int, _ options: Deeds.Options) -> String {
        [relationship(of: i, with: j), deedPrompt(options, to: j)].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// What creature `i`'s line said it does, to `j`: a fact to remember, an
    /// invitation, an answer, a deed of its own. Anything not offered, or over
    /// the limits, is traced and left.
    func took(_ tagged: Deeds.Tagged, by i: Int, to j: Int, options: Deeds.Options, byLetter: Bool) {
        guard creatures.indices.contains(i), creatures.indices.contains(j) else { return }
        let a = name(i), b = name(j)
        if let note = tagged.note, settings.memoryEnabled, settings.memoryNotes {
            bonds.change { $0.remember(a, b, note, source: "note", keep: settings.memoryFacts) }
            trace?("memory \(Bonds.key(a, b)): \(a) notes \"\(note)\"")
        }
        if let unknown = tagged.unknown { trace?("deed ignored: \(a) \"\(unknown)\"") }
        guard let deed = tagged.deed else { return }
        if let refusal = Deeds.check(deed, options) ?? deedLedger.refusal(deed.verb, a, b, at: elapsed, settings.deedLimits) {
            trace?("deed refused: \(a) \(deed.tag): \(refusal.rawValue)")
            return
        }
        switch deed {
        case .invite(let offer):
            invitations.removeAll { $0.from == a && $0.to == b }
            invitations.append(Deeds.Invitation(from: a, to: b, offer: offer, at: elapsed, byLetter: byLetter))
            deedLedger.record("invite", a, b, at: elapsed)
            if forcedOffer == offer { forcedOffer = nil }
            trace?("deed \(a) asks \(b): \(offer.tag)\(byLetter ? " (letter)" : "")")
        case .accept, .decline:
            guard let k = invitations.lastIndex(where: { $0.from == b && $0.to == a }) else { return }
            let invitation = invitations.remove(at: k)
            if deed == .accept {
                trace?("deed \(a) accepts \(invitation.offer.tag) from \(b)")
                agree(.invite(invitation.offer), by: j, with: i, asked: b)
            } else {
                trace?("deed \(a) declines \(invitation.offer.tag) from \(b)")
                remember(a, b, tr("%1$@ said no to %2$@'s invitation: %3$@", a, b, invitation.offer.title), source: "deed")
            }
        default:
            agree(deed, by: i, with: j, asked: nil)
        }
    }

    private func agree(_ deed: Deeds.Deed, by i: Int, with j: Int, asked: String?) {
        agreed.append(AgreedDeed(deed: deed, by: i, with: j, until: elapsed + settings.deedWaitMinutes * 60, asked: asked))
    }

    /// A fact for the pair, when memory is kept.
    func remember(_ a: String, _ b: String, _ text: String, source: String) {
        guard settings.memoryEnabled else { return }
        bonds.change { $0.remember(a, b, text, source: source, keep: settings.memoryFacts) }
        trace?("memory \(Bonds.key(a, b)): \(text)")
    }

    // MARK: Every frame

    func updateDeeds() {
        let open = settings.inviteOpenMinutes * 60
        for invitation in invitations where elapsed - invitation.at > open {
            trace?("deed \(invitation.from)'s invitation to \(invitation.to) lapsed")
            if invitation.byLetter {
                remember(invitation.from, invitation.to,
                         tr("%1$@'s invitation (%2$@) got no answer from %3$@", invitation.from, invitation.offer.title, invitation.to), source: "deed")
            }
        }
        invitations.removeAll { elapsed - $0.at > open }
        if !agreed.isEmpty {
            var waiting: [AgreedDeed] = []
            for var d in agreed where creatures.indices.contains(d.by) && creatures.indices.contains(d.with) {
                if perform(&d) { continue }
                if elapsed > d.until {
                    trace?("deed \(d.deed.tag) by \(name(d.by)) lapsed: \(Deeds.Refusal.lapsed.rawValue)")
                    if case .invite(let offer) = d.deed {
                        remember(name(d.by), name(d.with),
                                 tr("%1$@ and %2$@ agreed on %3$@, but never got to it", name(d.by), name(d.with), offer.title), source: "deed")
                    }
                    continue
                }
                waiting.append(d)
            }
            agreed = waiting
        }
        steerVisitors()
    }

    /// Free for a deed: awake, on an edge, in nothing else.
    func freeForDeed(_ i: Int) -> Bool {
        guard creatures.indices.contains(i) else { return false }
        let c = creatures[i]
        return !busy.contains(i) && !expectsPlane(i) && !c.isJumping && !c.isHeld && !c.looksAsleep
            && !hideout.isInside(i) && letters[i] == nil && grab?.index != i && held?.index != i && !chats.contains { $0.involves(i) }
    }

    /// Do `d` if both are ready; true once it is done (or can never be).
    private func perform(_ d: inout AgreedDeed) -> Bool {
        let a = name(d.by), b = name(d.with)
        func done(_ verb: String) -> Bool {
            deedLedger.record(verb, a, b, at: elapsed)
            trace?("deed \(a) & \(b) start: \(d.deed.tag)")
            return true
        }
        switch d.deed {
        case .invite(.game(let kind)):
            guard settings.playEnabled, !isNight else { trace?("deed \(kind.rawValue) refused: no games now"); return true }
            guard play == nil, freeToPlay(d.by), freeToPlay(d.with) else { return false }
            if startPlay(kind, with: [d.by, d.with], asked: d.asked) { return done("play") }
            // Not on one outline, or no room here: the other comes over, and they try again.
            if !d.leapt {
                d.leapt = true
                bringOver(d.with, to: d.by)
            }
            return false
        case .invite(.tea):
            guard teaParty == nil, teaInvite == nil, freeForDeed(d.by), freeForDeed(d.with) else { return false }
            if creatures[d.by].spot.loop == creatures[d.with].spot.loop, creatures[d.by].segment == creatures[d.with].segment {
                hold(d.by, and: d.with)
                if startTea(d.by, d.with) { return done("tea") }
                endChat(d.by, d.with, after: 0)
            }
            bringOver(d.with, to: d.by)
            teaInvite = (d.by, d.with, elapsed + 5)
            return done("tea")
        case .flower:
            guard !busy.contains(d.by), gifts.flight == nil, let flower = Gifts.flowers.randomElement(using: &rng) else { return false }
            guard gifts.give(flower, from: d.by, to: d.with, at: elapsed) else { return false }
            shared(d.by, d.with, .flower, detail: flower)
            return done("flower")
        case .letter:
            guard airmail == nil, canHandleMail(d.by), canHandleMail(d.with) else { return false }
            throwPlane(from: d.by, to: d.with, answering: nil)
            return done("letter")
        case .visit(let host):
            guard let k = creatures.indices.first(where: { name($0).lowercased() == host.lowercased() }) else { return true }
            guard freeForDeed(d.by) else { return false }
            visiting[d.by] = (k, elapsed + 60)
            return done("visit")
        case .follow:
            guard freeForDeed(d.by) else { return false }
            following[d.by] = (d.with, elapsed + settings.followSeconds)
            return done("follow")
        case .sleep:
            guard !busy.contains(d.by) else { return false }
            if !creatures[d.by].isSleeping { creatures[d.by].toggleNap(using: &rng) }
            return done("sleep")
        case .accept, .decline:
            return true
        }
    }

    /// `guest` leaps to just in front of `host`.
    func bringOver(_ guest: Int, to host: Int) {
        let h = creatures[host]
        let along = h.loop.direction(ofSegment: h.segment), gap = atlas.bodyHalfSize * CGFloat(sizes[host] + sizes[guest]) * 1.5
        let landing = CGPoint(x: h.position.x + along.dx * h.direction * gap, y: h.position.y + along.dy * h.direction * gap)
        creatures[guest].leap(to: creatures[guest].world.nearest(to: landing))
        trace?("deed \(name(guest)) jumps over to \(name(host))")
    }

    /// Walking over to someone, and trailing someone, every frame.
    private func steerVisitors() {
        for (i, v) in visiting {
            guard creatures.indices.contains(i), creatures.indices.contains(v.host), elapsed < v.until, !busy.contains(i) else {
                visiting.removeValue(forKey: i); continue
            }
            if creatures[i].spot.loop != creatures[v.host].spot.loop {
                bringOver(i, to: v.host)
                visiting.removeValue(forKey: i)
            } else {
                // Walking up is enough: when the two touch, they meet as anyone does.
                creatures[i].head(toward: creatures[v.host].spot.t, near: atlas.bodyHalfSize * CGFloat(sizes[i] + sizes[v.host]))
            }
        }
        for (i, f) in following {
            guard creatures.indices.contains(i), creatures.indices.contains(f.leader), elapsed < f.until else {
                following.removeValue(forKey: i); continue
            }
            guard !busy.contains(i), !busy.contains(f.leader) else { continue }
            _ = creatures[i].follow(creatures[f.leader], gap: (sizes[i] + sizes[f.leader]) / 2 + 16)
        }
    }

    // MARK: Without a model

    /// A built-in invitation from `i` to `j`, if one is due: the share of letters and
    /// talks the owner set, to something offered (a rematch first). Nil otherwise.
    func builtInInvitation(_ i: Int, to j: Int, _ options: Deeds.Options) -> Deeds.Offer? {
        if let offer = forcedOffer, check(.invite(offer), options) { return offer }
        guard Double.random(in: 0..<100, using: &rng) < settings.builtInInviteShare else { return nil }
        let rematch = Bonds.lastLost(by: name(i), bonds.bond(name(i), name(j)))
        return Deeds.builtInOffer(options, rematch: rematch, using: &rng)
    }

    /// Whether the built-in answer of `i` to `j` is yes.
    func builtInYes(_ i: Int, to j: Int) -> Bool {
        if let forced = forcedAnswer { return forced }
        return Deeds.builtInYes(closeness: closeness(i, j), chance: settings.builtInAcceptChance, using: &rng)
    }
}

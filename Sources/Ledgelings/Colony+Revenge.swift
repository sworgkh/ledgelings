import AppKit
import LedgelingsCore

/// Revenge: chased or picked up too often in a short time, a creature jumps on the
/// cursor, rides along on it (or, with `revengePinsCursor`, holds it still) and tells
/// the user what it thinks of them. Shaking the mouse throws it off; Escape, or the
/// longest hold running out, lets go too.
extension Colony {

    /// The one creature holding the cursor.
    struct Grab {
        var index: Int
        /// On the colony's clock.
        var since: Double
        /// Where the cursor is held, and where it was last seen.
        var pin: CGPoint
        var last: CGPoint
        var shake: Revenge.Shake
        /// Whether the real pointer is held still; otherwise the creature clings and rides along.
        var pinned: Bool
        var serial: Int
        /// When it tells the user off again, on the colony's clock.
        var nextTaunt: Double
    }

    /// Creature `i` was just hunted. True when that was once too often and it grabbed the cursor.
    func takeRevenge(_ i: Int) -> Bool {
        guard settings.revengeEnabled, creatures.indices.contains(i) else { return false }
        guard revengeFuse.hunted(i, at: elapsed), canGrab(i) else { return false }
        grabCursor(i)
        return true
    }

    /// Not while the user holds the mouse button (a drag, a carry), not mid-conversation, not while they hide.
    private func canGrab(_ i: Int) -> Bool {
        grab == nil && held == nil && poke == nil && !mouseIsDown()
            && !busy.contains(i) && !complaining.contains(i) && !hideout.isActive && !hideout.isInside(i)
    }

    /// Where a creature hangs from the cursor: the arrow's tip in the top of its body.
    private func hang(_ i: Int, from cursor: CGPoint) -> CGPoint {
        let half = atlas.bodyHalfSize * CGFloat(sizes[i])
        return CGPoint(x: cursor.x + half * 0.2, y: cursor.y - half * 0.55)
    }

    func grabCursor(_ i: Int) {
        let cursor = pointerLocation()
        guard creatures[i].cling() else { return }
        let times = max(revengeFuse.recent(i, at: elapsed), 1)
        revengeFuse.grabbed(at: elapsed)
        annoyance.forgive(i)
        grabCount += 1
        let pinned = settings.revengePinsCursor && pointer?.pin(at: cursor) == true
        if !pinned { pointer?.follow() }
        pointer?.onMove = { [weak self] at in self?.struggle(to: at); self?.render() }
        pointer?.onEscape = { [weak self] in self?.letGoOfCursor(.escape) }
        grab = Grab(index: i, since: elapsed, pin: cursor, last: cursor,
                    shake: Revenge.Shake(needed: settings.revengeShakes, stroke: settings.revengeShakeStroke,
                                         window: settings.revengeShakeWindowSeconds),
                    pinned: pinned, serial: grabCount, nextTaunt: elapsed + max(settings.revengeTauntSeconds, 1))
        creatures[i].drag(to: hang(i, from: cursor))
        let name = character(forCreature: i).name
        trace?("grab \(name)\(pinned ? " (holding still)" : "")")
        shame(i, times: times, serial: grabCount)
    }

    /// Every frame of a grab: count the struggle, keep the cursor held, tell the user
    /// off now and then, and let go when it has been held long enough.
    func updateGrab(cursor: CGPoint) {
        guard let g = grab else { return }
        guard creatures.indices.contains(g.index), creatures[g.index].isHeld else { return letGoOfCursor(.escape) }
        if elapsed - g.since >= Revenge.longestHold(limit: settings.revengeHoldSeconds, pinned: g.pinned) {
            return letGoOfCursor(.tired)
        }
        struggle(to: cursor)
        taunt()
    }

    /// Riding along, it tells the user off again every `revengeTauntSeconds`, with
    /// its built-in lines (no further model calls), once the last bubble is gone.
    private func taunt() {
        guard var g = grab, settings.revengeTauntSeconds > 0, elapsed >= g.nextTaunt else { return }
        guard settings.talkEnabled, bubbles[g.index] == nil else { return }
        g.nextTaunt = elapsed + settings.revengeTauntSeconds
        grab = g
        let name = character(forCreature: g.index).name
        let n = hunts.numbers(of: name)
        let line = Revenge.line(by: name, today: max(n.today, 1), all: max(n.all, 1), mood: settings.cursorMood, using: &rng)
        say(line, from: g.index, builtIn: true)
        trace?("taunt \(name): \(line)")
    }

    /// The user moved the cursor to `point`: that is part of a shake, and a held
    /// cursor goes straight back. Enough of it, and the creature is thrown off.
    func struggle(to point: CGPoint) {
        guard var g = grab else { return }
        let dx = Double(point.x - g.last.x), dy = Double(point.y - g.last.y)
        let shaken = (dx != 0 || dy != 0) && g.shake.moved(dx: dx, dy: dy, at: elapsed)
        if g.pinned {
            if point != g.pin { pointer?.hold(at: g.pin) }
            g.last = g.pin
        } else {
            g.last = point
        }
        grab = g
        if shaken { return letGoOfCursor(.shaken) }
        // It wobbles harder the closer it is to coming loose.
        let wobble = CGFloat(g.shake.vigour(at: elapsed)) * 7 * CGFloat(sin(elapsed * 45))
        let at = hang(g.index, from: g.pinned ? g.pin : point)
        creatures[g.index].drag(to: CGPoint(x: at.x + wobble, y: at.y))
    }

    /// Let go of the cursor, if anyone has it. Shaken off, it tumbles down with a last word.
    func letGoOfCursor(_ why: Revenge.Release) {
        guard let g = grab else { return }
        grab = nil
        pointer?.release()
        pointer?.onMove = nil
        pointer?.onEscape = nil
        guard creatures.indices.contains(g.index) else { return }
        creatures[g.index].drop(tumbling: why == .shaken)
        let name = character(forCreature: g.index).name
        trace?("let go \(name): \(why.rawValue)")
        guard why == .shaken, settings.talkEnabled else { return }
        say(Revenge.lastWord(by: name, mood: settings.cursorMood, using: &rng), from: g.index, builtIn: true)
    }

    /// What it says while it holds the cursor: the model's line, or its own built-in one.
    private func shame(_ i: Int, times: Int, serial: Int) {
        guard settings.talkEnabled else { return }
        let me = character(forCreature: i)
        let n = hunts.numbers(of: me.name)
        let situation = [almanac, "\(describe(i)).",
                         tr("%@ has been chased or picked up by the user's cursor %d times in the last few minutes.", me.name, times),
                         huntSentence([i], always: true)]
            .filter { !$0.isEmpty }.joined(separator: " ")
        func builtIn() -> String {
            Revenge.line(by: me.name, today: max(n.today, 1), all: max(n.all, 1), mood: settings.cursorMood, using: &rng)
        }
        guard settings.brain != .script, let service = settings.chatClient() else {
            let line = builtIn()
            say(line, from: i, builtIn: true)
            record(line, by: me.name, situation: situation)
            return
        }
        let vars = ["speaker": me.name, "speakerKind": Banter.spoken(kind(ofCreature: i)), "speakerPersona": Banter.persona(me.persona),
                    "listener": tr("you"), "listenerKind": tr("the person at the computer"),
                    "listenerPersona": tr("The person whose screen you all live on."),
                    "situation": situation, "times": "\(times)"]
        let system = LineMemory.withRecent(Bonds.withRelationship(settings.systemPrompt, vars, context: ""),
                                           history.memory.recent(of: me.name))
        let user = Banter.render(Revenge.prompt, vars).trimmingCharacters(in: .whitespacesAndNewlines)
        Task { [weak self] in
            var line = "", cost: Double?, tokens: Int?
            do {
                try await service.checkModel()
                let answer = try await service.line(system: system, user: user)
                // Paid for, whatever comes back, and even if the grab is over by now.
                if var usage = answer.usage {
                    if service.provider == .lmStudio { usage.cost = 0 }
                    self?.spend.record(provider: service.provider, model: service.model, usage: usage, purpose: .revenge)
                    cost = usage.cost
                    tokens = usage.promptTokens + usage.completionTokens
                }
                line = Banter.cleanLine(answer.text, speaker: me.name, cut: answer.cut)
            } catch {
                self?.talkStatus = "\(error)"
                FileHandle.standardError.write(Data("Ledgelings revenge: \(error)\n".utf8))
            }
            guard let self, grab?.serial == serial, creatures.indices.contains(i), character(forCreature: i).name == me.name else { return }
            let modelWrote = !line.isEmpty
            if !modelWrote { line = builtIn() }
            say(line, from: i, builtIn: !modelWrote)
            record(line, by: me.name, situation: situation,
                   provider: modelWrote ? service.provider.title : nil, model: service.model, cost: cost, tokens: tokens)
        }
    }

    /// Into the Chats tab, with what it cost when a model wrote it.
    private func record(_ line: String, by name: String, situation: String,
                        provider: String? = nil, model: String = "", cost: Double? = nil, tokens: Int? = nil) {
        talkStatus = tr("%@ grabbed your cursor: “%@”", name, line)
        history.record(ChatLog.Exchange(time: Date(), situation: situation,
                                        provider: provider ?? AppSettings.Brain.script.title, model: provider == nil ? "" : model,
                                        lines: [ChatLog.Line(speaker: name, text: line)], cost: cost, tokens: tokens))
        trace?("revenge \(name): \(line)")
    }
}

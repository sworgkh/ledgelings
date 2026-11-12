import AppKit
import LedgelingsCore

/// Chat with the creatures (§7.18), from the colony's side: who can be written
/// to, who answers a message to everyone and in what order, each answer from
/// the brain model in the creature's persona and kind, its thinking dots, its
/// bubble and its voice, its turn to face the window, its cost (`.chat`) and its
/// place in the Chats tab; and each one's memory of the owner (`OwnerChatBook`).
extension Colony {

    /// Someone on screen the owner can write to.
    struct ChatTarget: Equatable {
        var name: String
        var portrait: CGImage?
    }

    /// What happens while they answer, for the window.
    enum ChatEvent {
        case thinking(String)
        case answer(String, text: String, cost: Double?)
        /// It had nothing to say (an empty answer, or trouble); the call, if any, was still paid for.
        case quiet(String, why: String)
        case trouble(String)
    }

    /// A stand-in for the model: (who, kind, what the owner wrote, what the ones before said) → the answer.
    typealias ChatFake = (_ name: String, _ message: String, _ earlier: [(name: String, text: String)]) -> String

    /// Everyone on screen, each name once, in the order they live.
    func chatTargets() -> [ChatTarget] {
        var seen = Set<String>()
        return creatures.indices.compactMap { i in
            let name = character(forCreature: i).name
            guard seen.insert(name).inserted else { return nil }
            return ChatTarget(name: name, portrait: frames[i].frame(animation: "idle", time: 0))
        }
    }

    func creatureIndex(named name: String) -> Int? {
        creatures.indices.first { character(forCreature: $0).name == name }
    }

    /// Answer the owner's `message`: `to` one name, or nil for everyone (up to
    /// `chatEveryone` of them, one after another, each hearing the ones before).
    /// Each faces `window` (global points) while it thinks and talks. Returns once
    /// the last has finished saying its answer.
    func answerOwner(_ message: String, to name: String?, window: CGPoint, fake: ChatFake? = nil,
                     event: @escaping (ChatEvent) -> Void) async {
        let service = fake == nil ? settings.chatClient() : nil
        guard fake != nil || service != nil else { event(.trouble(OwnerChat.noModel)); return }
        let everyone = name == nil
        let order: [String]
        if let name {
            order = creatureIndex(named: name) == nil ? [] : [name]
        } else {
            let candidates = chatTargets().compactMap { t in creatureIndex(named: t.name).map { OwnerChat.Candidate(name: t.name, asleep: creatures[$0].looksAsleep) } }
            order = OwnerChat.answerers(candidates, count: settings.chatEveryone, using: &rng)
        }
        guard !order.isEmpty else { event(.trouble(tr("Nobody is on screen to answer."))); return }
        trace?("chat \(everyone ? "everyone" : "to \(order[0])"): \"\(message)\", \(order.count == 1 ? "1 answers" : "\(order.count) answer in turn: \(order.joined(separator: ", "))")")
        let started = Date(), length = settings.chatLength
        var lines = [ChatLog.Line(speaker: tr("You"), text: message)]
        var used: [Spend.Usage] = []
        var earlier: [(name: String, text: String)] = []
        var situation = ""
        for (turn, who) in order.enumerated() {
            guard let i = creatureIndex(named: who) else { continue }
            if turn > 0 { try? await Task.sleep(for: .seconds(isVoiced ? turnPause : 0.6)) }
            let character = character(forCreature: i)
            situation = [almanac, timeOfDay, describe(i) + "."].filter { !$0.isEmpty }.joined(separator: " ")
            let memory = settings.chatRemember ? OwnerChat.memoryBlock(ownerChats?.memory(of: who)) : ""
            let values = OwnerChat.values(speaker: who, kind: kind(ofCreature: i), persona: character.persona, length: length, memory: memory,
                                          situation: situation, message: message, everyone: everyone, earlier: earlier)
            let prompt = OwnerChat.prompt(values)
            startChatTurn(i, facing: window)
            event(.thinking(who))
            trace?("chat \(who) is thinking, about \(Bonds.tokens(prompt.system + prompt.user)) tokens to send\(memory.isEmpty ? "" : ", memory \(Bonds.tokens(memory))")")
            let asked = Date()
            var text = "", cost: Double?
            if let fake {
                try? await Task.sleep(for: .seconds(0.8))
                text = OwnerChat.clean(fake(who, message, earlier), speaker: who, length: length)
            } else if let service {
                do {
                    let answer = try await service.reply(system: prompt.system, user: prompt.user, maxTokens: length.maxTokens, reasoning: "low")
                    if var usage = answer.usage {
                        if service.provider == .lmStudio { usage.cost = 0 }       // a local model is free
                        used.append(usage)
                        cost = usage.cost
                        spend.record(provider: service.provider, model: service.model, usage: usage, purpose: .chat)
                    }
                    text = OwnerChat.clean(answer.text, speaker: who, length: length, cut: answer.cut)
                    if text.isEmpty { trace?("chat \(who): the model sent nothing usable: \(answer.text.prefix(120).debugDescription)") }
                } catch {
                    endChatThinking(i)
                    trace?("chat \(who): \(error)")
                    event(.quiet(who, why: "\(error)"))
                    continue
                }
            }
            endChatThinking(i)
            guard creatures.indices.contains(i) else { continue }
            guard !text.isEmpty else { event(.quiet(who, why: tr("%@ had nothing to say.", who))); continue }
            trace?(String(format: "chat %@ answers after %.1f s%@: %@", who, Date().timeIntervalSince(asked),
                          cost.map { ", " + Spend.label($0) } ?? (fake != nil ? ", fake" : ", unpriced"), text))
            event(.answer(who, text: text, cost: cost))
            lines.append(ChatLog.Line(speaker: who, text: text))
            earlier.append((who, text))
            rememberChat(who, said: message, answer: text, everyone: everyone, kind: kind(ofCreature: i))
            await sayChatAnswer(text, from: i)
        }
        // The talk goes to the Chats tab, with what its calls cost; the voice's own cost is put beside it there.
        if lines.count > 1 || !used.isEmpty {
            let priced = used.compactMap(\.cost)
            history.record(ChatLog.Exchange(time: started, situation: tr("Chat with you.") + " " + situation,
                                            provider: service?.provider.title ?? tr("Stand-in answers"), model: service?.model ?? "",
                                            lines: lines, cost: priced.isEmpty ? nil : priced.reduce(0, +),
                                            tokens: used.isEmpty ? nil : used.reduce(0) { $0 + $1.promptTokens + $1.completionTokens }))
        }
        endChatTurns()
    }

    // MARK: On screen

    /// It stops, turns to the window and is left alone while it answers.
    func startChatTurn(_ i: Int, facing point: CGPoint) {
        guard creatures.indices.contains(i) else { return }
        if !busy.contains(i) { busy.insert(i); chatBusy.insert(i) }
        let c = creatures[i]
        if !c.isChatting, !c.isPlaying, !c.isHeld, !c.looksAsleep {
            let dir = c.loop.direction(ofSegment: c.segment)
            let along = dir.dx * (point.x - c.position.x) + dir.dy * (point.y - c.position.y)
            creatures[i].meet(facing: along >= 0 ? 1 : -1, for: 90)
            chatFacing.insert(i)
            trace?("chat \(character(forCreature: i).name) turns to the window, facing \(along >= 0 ? "+" : "-")")
        }
        chatThinking[i] = elapsed
    }

    func endChatThinking(_ i: Int) {
        guard chatThinking.removeValue(forKey: i) != nil else { return }
        if let b = bubbles[i], b.text.allSatisfy({ $0 == "•" }) { bubbles.removeValue(forKey: i) }
    }

    /// Everyone who answered walks on.
    func endChatTurns() {
        for i in chatFacing where creatures.indices.contains(i) && creatures[i].isChatting { creatures[i].walkOn(using: &rng) }
        busy.subtract(chatBusy)
        chatFacing.removeAll()
        chatBusy.removeAll()
        chatThinking.removeAll()
    }

    /// Every frame: one, two, three dots over whoever is writing an answer, never said.
    func updateOwnerChat() {
        for (i, since) in chatThinking where creatures.indices.contains(i) {
            guard settings.chatBubbles else { continue }
            let dots = String(repeating: "•", count: Int((elapsed - since) * 3) % 3 + 1)
            if bubbles[i]?.text != dots {
                bubbleSerial += 1
                bubbles[i] = Bubble(text: dots, until: elapsed + 1, serial: bubbleSerial)
            }
            if chatFacing.contains(i) { creatures[i].keepChatting(for: 30) }
        }
    }

    /// The answer in a bubble over it and in its voice, as the settings say; back once it is said.
    private func sayChatAnswer(_ text: String, from i: Int) async {
        guard creatures.indices.contains(i) else { return }
        let speak = settings.chatSpeak && isVoiced
        if chatFacing.contains(i) { creatures[i].keepChatting(for: 60) }
        if settings.chatBubbles {
            let serial = say(text, from: i, voiced: speak)
            if voicedLines.contains(serial) { await said(serial) } else { try? await Task.sleep(for: .seconds(Banter.showTime(text, base: settings.bubbleSeconds) * 0.5)) }
        } else if speak, let voice {
            let name = character(forCreature: i).name
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                var over = false
                let started = voice.say(text, as: name) { [weak self] cue in
                    if case .progress = cue {} else { self?.trace?("chat cue \(name) \(cue)") }
                    guard !over, cue == .done || cue == .dropped else { return }
                    over = true
                    done.resume()
                }
                if !started { over = true; done.resume() }
            }
        }
    }

    // MARK: Memory

    /// One exchange into `name`'s memory; what falls out of it is folded into its summary.
    private func rememberChat(_ name: String, said: String, answer: String, everyone: Bool, kind: String) {
        guard settings.chatRemember, let ownerChats else { return }
        let dropped = ownerChats.change {
            $0.remember(name, OwnerChat.Exchange(time: Date(), said: said, answer: answer, everyone: everyone), keep: settings.chatMemoryExchanges)
        }
        trace?("chat memory \(name): \(ownerChats.memory(of: name)?.exchanges.count ?? 0) kept\(dropped.isEmpty ? "" : ", \(dropped.count) to the summary")")
        if !dropped.isEmpty { summariseChat(name, dropped, kind: kind) }
    }

    /// The summary rewritten to take in `dropped`: one call, priced as `.chat`, whatever comes back.
    func summariseChat(_ name: String, _ dropped: [OwnerChat.Exchange], kind: String) {
        guard let ownerChats, let service = settings.chatClient() else { return }
        let prompt = OwnerChat.summaryPrompt(speaker: name, kind: kind, summary: ownerChats.memory(of: name)?.summary, dropped: dropped)
        Task { [weak self] in
            var cost: Double?, summary: String?
            do {
                let answer = try await service.reply(system: Bonds.diarySystemPrompts(), user: prompt, maxTokens: OwnerChat.summaryMaxTokens, reasoning: "low")
                if var usage = answer.usage {
                    if service.provider == .lmStudio { usage.cost = 0 }
                    cost = usage.cost
                    self?.spend.record(provider: service.provider, model: service.model, usage: usage, purpose: .chat)
                }
                summary = OwnerChat.cleanSummary(answer.text)
            } catch {
                FileHandle.standardError.write(Data("Ledgelings chat memory: \(error)\n".utf8))
            }
            ownerChats.change { $0.summarised(name, summary, cost: cost) }
            self?.trace?("chat memory \(name): summary \(summary ?? "-")")
        }
    }

    /// Each character's memory of the owner, for `--memory`.
    func ownerChatDump(only: String? = nil) -> [String] {
        guard let ownerChats else { return [] }
        var out: [String] = []
        for name in ownerChats.book.names where only.map({ name.lowercased().contains($0.lowercased()) }) ?? true {
            guard let memory = ownerChats.memory(of: name) else { continue }
            let key = tr("you") + " & " + name
            out.append("memory \(key): summary: \(memory.summary ?? "-")\(memory.summaryCost.map { " (" + Spend.label($0) + ")" } ?? "")")
            for e in memory.exchanges {
                out.append("memory \(key): \(OwnerChat.when(e.time))\(e.everyone ? " (to everyone)" : ""): \"\(e.said)\" → \"\(e.answer)\"")
            }
            let block = OwnerChat.memoryBlock(memory)
            out.append("memory \(key): \(name) remembers (\(Bonds.tokens(block)) tokens, \(memory.exchanges.count) of \(settings.chatMemoryExchanges) exchanges kept): \(block)")
        }
        return out
    }
}

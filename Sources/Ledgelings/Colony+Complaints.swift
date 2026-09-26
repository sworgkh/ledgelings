import AppKit
import LedgelingsCore

/// Complaints: chase a creature with the cursor, or pick it up, too many times
/// in a row and it turns round and tells you off, in its own voice.
extension Colony {

    /// Creature `i` was just chased off its edge by the cursor, or picked up.
    func bothered(_ i: Int) {
        guard settings.complainEnabled, creatures.indices.contains(i) else { return }
        guard annoyance.bothered(i, at: elapsed) else { return }
        complain(i)
    }

    /// Say the complaint. In the middle of a conversation it waits: the streak is
    /// kept, so the next chase complains instead.
    func complain(_ i: Int) {
        guard creatures.indices.contains(i), !busy.contains(i), !complaining.contains(i) else { return }
        let times = annoyance.streak(of: i, at: elapsed)
        annoyance.forgive(i)
        let me = character(forCreature: i)
        let situation = [almanac, "\(describe(i)).", "\(me.name) has been chased or picked up by the user's cursor \(times) times in a row."]
            .filter { !$0.isEmpty }.joined(separator: " ")
        guard settings.talkEnabled, settings.brain != .script, let service = settings.chatClient() else {
            let line = Complaints.line(by: me.name, times: times, using: &rng)
            say(line, from: i, builtIn: true)
            record(line, by: me.name, situation: situation)
            return
        }
        let vars = ["speaker": me.name, "speakerKind": kind(ofCreature: i), "speakerPersona": me.persona,
                    "listener": "you", "listenerKind": "the person at the computer",
                    "listenerPersona": "The person whose screen you all live on.",
                    "situation": situation, "times": "\(times)"]
        let system = LineMemory.withRecent(Bonds.withRelationship(settings.systemPrompt, vars, context: ""),
                                           history.memory.recent(of: me.name))
        let user = Banter.render(Complaints.prompt, vars).trimmingCharacters(in: .whitespacesAndNewlines)
        complaining.insert(i)
        talkStatus = "\(me.name) is complaining via \(service.model)…"
        Task { [weak self] in
            var line = "", cost: Double?, tokens: Int?
            do {
                try await service.checkModel()
                let answer = try await service.reply(system: system, user: user)
                // Paid for, whatever comes back.
                if var usage = answer.usage {
                    if service.provider == .lmStudio { usage.cost = 0 }
                    self?.spend.record(provider: service.provider, model: service.model, usage: usage, purpose: .complaints)
                    cost = usage.cost
                    tokens = usage.promptTokens + usage.completionTokens
                }
                line = Banter.cleanLine(answer.text, speaker: me.name)
            } catch {
                self?.talkStatus = "\(error)"
                FileHandle.standardError.write(Data("Ledgelings complaint: \(error)\n".utf8))
            }
            guard let self else { return }
            complaining.remove(i)
            // Gone, or talking by now: the moment has passed.
            guard creatures.indices.contains(i), character(forCreature: i).name == me.name, !busy.contains(i) else { return }
            let modelWrote = !line.isEmpty
            if !modelWrote { line = Complaints.line(by: me.name, times: times, using: &rng) }
            say(line, from: i, builtIn: !modelWrote)
            record(line, by: me.name, situation: situation,
                   provider: modelWrote ? service.provider.title : nil, model: service.model, cost: cost, tokens: tokens)
        }
    }

    /// Into the Chats tab, with what it cost when a model wrote it.
    private func record(_ line: String, by name: String, situation: String,
                        provider: String? = nil, model: String = "", cost: Double? = nil, tokens: Int? = nil) {
        talkStatus = "\(name) complained: \(line)"
        history.record(ChatLog.Exchange(time: Date(), situation: situation,
                                        provider: provider ?? AppSettings.Brain.script.title, model: provider == nil ? "" : model,
                                        lines: [ChatLog.Line(speaker: name, text: line)], cost: cost, tokens: tokens))
        trace?("complaint \(name): \(line)")
    }
}

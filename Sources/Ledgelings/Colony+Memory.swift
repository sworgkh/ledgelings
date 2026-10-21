import Foundation
import LedgelingsCore

/// Long-term memory, from the colony's side: the diary, one model call a pair
/// at the colony's nightfall that writes their memory down (`Bonds.Diary`),
/// priced as `.memory`; the seed, which reads the chat log of the last weeks
/// into each pair's memory once (`.memorySeed`); and the dump the
/// `--memory` flag prints.
extension Colony {

    /// Who `name` is, for a prompt: its kind and persona if it is on screen, else blanks.
    func who(_ name: String) -> (name: String, kind: String, persona: String) {
        guard let i = creatures.indices.first(where: { character(forCreature: $0).name == name }) else { return (name, "", "") }
        return (name, kind(ofCreature: i), character(forCreature: i).persona)
    }

    /// Every half minute: at the colony's nightfall, the pairs whose memory is
    /// due get their diary; the caps are kept to.
    func updateMemory() {
        guard elapsed >= nextMemoryCheck else { return }
        let first = nextMemoryCheck == 0
        nextMemoryCheck = elapsed + 30
        let night = isNight
        defer { wasNight = night }
        if first { bonds.change { $0.keepMemory(facts: settings.memoryFacts, days: settings.memoryDays) } }
        guard night, !wasNight, !first else { return }
        writeDiaries()
    }

    /// The diary for every pair due one, most new moments first, up to the night's cap.
    @discardableResult
    func writeDiaries(force: Bool = false) -> Int {
        guard settings.memoryEnabled, settings.diaryEnabled || force, settings.brain != .script, settings.chatClient() != nil else { return 0 }
        let due = bonds.book.diaryDue(every: force ? 0 : settings.diaryEveryHours * 3600)
            .filter { !writingMemory.contains(Bonds.key($0.names[0], $0.names[1])) }
            .prefix(force ? Int.max : settings.diaryPairsPerNight)
        for bond in due { writeDiary(bond.names[0], bond.names[1]) }
        if !due.isEmpty { bonds.change { $0.keepMemory(facts: settings.memoryFacts, days: settings.memoryDays) } }
        return due.count
    }

    /// What the two said today, their last few exchanges, for the diary.
    func todaysLines(_ a: String, _ b: String, limit: Int = 6) -> [ChatLog.Line] {
        let shared = history.exchanges(on: Bonds.dayKey(Date())).filter { e in
            e.lines.contains { $0.speaker == a } && e.lines.contains { $0.speaker == b }
        }
        return Array(shared.flatMap(\.lines).suffix(limit))
    }

    /// One pair's diary: one call in the background, recorded as `.memory` whatever comes back.
    func writeDiary(_ a: String, _ b: String, done: (() -> Void)? = nil) {
        let key = Bonds.key(a, b)
        guard let service = settings.chatClient(), let bond = bonds.bond(a, b), !writingMemory.contains(key) else { done?(); return }
        let values = Bonds.memoryValues(bond, a: who(bond.names[0]), b: who(bond.names[1]), lines: todaysLines(a, b),
                                        words: settings.storyWords, facts: settings.memoryFacts)
        let prompt = Banter.render(Bonds.diaryPrompts(), values)
        writingMemory.insert(key)
        trace?("memory \(key): writing the diary, \(Bonds.tokens(prompt)) tokens or so")
        Task { [weak self] in
            var cost: Double?, diary: Bonds.Diary?
            do {
                let answer = try await service.reply(system: Bonds.diarySystemPrompts(), user: prompt,
                                                     maxTokens: Bonds.diaryMaxTokens, reasoning: "low")
                if var usage = answer.usage {
                    if service.provider == .lmStudio { usage.cost = 0 }
                    cost = usage.cost
                    self?.spend.record(provider: service.provider, model: service.model, usage: usage, purpose: .memory)
                }
                diary = Bonds.parseDiary(answer.text)
                if diary == nil { FileHandle.standardError.write(Data("Ledgelings memory: nothing in \(answer.text.debugDescription)\n".utf8)) }
            } catch {
                FileHandle.standardError.write(Data("Ledgelings memory: \(error)\n".utf8))
            }
            guard let self else { return }
            writingMemory.remove(key)
            bonds.change { book in
                if let diary {
                    book.write(a, b, diary, source: "diary", words: settings.storyWords, keep: settings.memoryFacts, cost: cost)
                } else {
                    book.wroteMemory(a, b, at: Date(), cost: cost)
                }
            }
            if let diary {
                trace?("memory \(key): story: \(diary.story ?? "-")")
                for fact in diary.facts { trace?("memory \(key): fact: \(fact)") }
                for (day, line) in diary.days.sorted(by: { $0.key < $1.key }) { trace?("memory \(key): day \(day.isEmpty ? "today" : day): \(line)") }
            }
            done?()
        }
    }

    // MARK: The seed

    /// What the seed did, for the window and the flag.
    struct SeedReport {
        var pairs: [(key: String, exchanges: Int, days: Int, lines: Int, tokens: Int)] = []
        var tokens: Int { pairs.reduce(0) { $0 + $1.tokens } }
    }

    /// Every pair who spoke together in the chat log over the last `days` days,
    /// with how many conversations: at least `atLeast` of them.
    func seedPairs(days: Int, atLeast: Int = 3, now: Date = Date()) -> [(a: String, b: String, exchanges: [ChatLog.Exchange])] {
        let from = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let oldest = Bonds.dayKey(from)
        let exchanges = history.days().filter { $0 >= oldest }.flatMap { history.exchanges(on: $0) }.filter { $0.time >= from }
        var counts: [String: Int] = [:]
        for e in exchanges {
            let speakers = Array(Set(e.lines.map(\.speaker))).sorted()
            guard speakers.count >= 2 else { continue }
            for i in speakers.indices { for j in speakers.indices where j > i { counts[Bonds.key(speakers[i], speakers[j]), default: 0] += 1 } }
        }
        return counts.filter { $0.value >= atLeast }.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map { pair in
            let names = pair.key.components(separatedBy: " & ")
            return (names[0], names[1], exchanges)
        }
    }

    /// Read the last `settings.seedDays` days of the chat log into every pair's
    /// memory: their days counted, and with a model one call a pair for their
    /// story, facts and day lines. `dryRun`: print what would be sent and what it
    /// would cost, send nothing, change nothing. `bonds.json` is copied to
    /// `bonds.before-seed.json` first.
    func seedMemory(dryRun: Bool, log: @escaping (String) -> Void) async -> SeedReport {
        var report = SeedReport()
        let days = settings.seedDays, now = Date()
        let from = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        // A dry run never touches the key: no client, no keychain prompt.
        let service = dryRun || settings.brain == .script ? nil : settings.chatClient()
        if !dryRun {
            let backup = bonds.store.directory.appendingPathComponent("bonds.before-seed.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: bonds.file, to: backup)
            log("seed: bonds.json copied to \(backup.lastPathComponent)")
        }
        for pair in seedPairs(days: days, now: now) {
            let (a, b) = (pair.a, pair.b), key = Bonds.key(a, b)
            let digest = Bonds.seedDigest(pair.exchanges, a, b, from: from, to: now, lines: settings.seedLines)
            guard digest.exchanges > 0 else { continue }
            let bond = bonds.bond(a, b) ?? Bonds.Bond(names: [a, b].sorted())
            let values = Bonds.seedValues(bond, digest, a: who(bond.names[0]), b: who(bond.names[1]), days: days,
                                          words: settings.storyWords, facts: settings.memoryFacts)
            let prompt = Banter.render(Bonds.seedPrompts(), values)
            let tokens = Bonds.tokens(prompt)
            report.pairs.append((key, digest.exchanges, digest.days.count, digest.lines.count, tokens))
            log("seed \(key): \(digest.exchanges) conversations over \(digest.days.count) days, \(digest.lines.count) lines, about \(tokens) tokens to send")
            if dryRun {
                for k in digest.days.keys.sorted() { log("seed \(key): \(k): \(Bonds.tallied(digest.days[k] ?? [:]))") }
                for l in digest.lines.prefix(4) { log("seed \(key): [\(l.day)] \(l.line.speaker): \(l.line.text)") }
                continue
            }
            bonds.change { $0.seedDays(a, b, digest, at: now) }
            guard let service else { continue }
            do {
                let answer = try await service.reply(system: Bonds.diarySystemPrompts(), user: prompt,
                                                     maxTokens: Bonds.diaryMaxTokens * 2, reasoning: "low")
                var cost: Double?
                if var usage = answer.usage {
                    if service.provider == .lmStudio { usage.cost = 0 }
                    cost = usage.cost
                    spend.record(provider: service.provider, model: service.model, usage: usage, purpose: .memorySeed)
                }
                if let diary = Bonds.parseDiary(answer.text) {
                    bonds.change { $0.write(a, b, diary, source: "seed", at: now, words: settings.storyWords, keep: settings.memoryFacts, cost: cost) }
                    log("seed \(key): story: \(diary.story ?? "-")")
                    for fact in diary.facts { log("seed \(key): fact: \(fact)") }
                    log("seed \(key): \(diary.days.count) day lines, cost \(cost.map(Spend.label) ?? "unpriced")")
                } else {
                    bonds.change { $0.wroteMemory(a, b, at: now, cost: cost) }
                    log("seed \(key): the answer had nothing in it: \(answer.text.prefix(200).debugDescription)")
                }
            } catch {
                log("seed \(key): \(error)")
            }
        }
        if !dryRun { bonds.change { $0.keepMemory(facts: settings.memoryFacts, days: settings.memoryDays) } }
        log("seed: \(report.pairs.count) pairs, about \(report.tokens) tokens in all\(dryRun ? " (dry run: nothing sent, nothing changed)" : "")")
        return report
    }

    // MARK: The dump

    /// Each pair's memory as the owner and a prompt see it, for `--memory`.
    func memoryDump(only: String? = nil) -> [String] {
        var out: [String] = []
        for bond in bonds.book.closest where only.map({ bond.names.joined(separator: " & ").lowercased().contains($0.lowercased()) }) ?? true {
            let key = Bonds.key(bond.names[0], bond.names[1])
            out.append("memory \(key): bond: \(bond.summary ?? "-")")
            out.append("memory \(key): story: \(bond.chronicle ?? "-")")
            for fact in bond.facts { out.append("memory \(key): fact (\(fact.source), \(Bonds.day(fact.time))): \(fact.text)") }
            out.append("memory \(key): games: \(Bonds.recordLine(bond) ?? "-")")
            for day in bond.days.suffix(7) { out.append("memory \(key): day \(day.day): \(day.line ?? Bonds.dayLine(day))") }
            for (x, y) in [(bond.names[0], bond.names[1]), (bond.names[1], bond.names[0])] {
                let block = Bonds.memory(bond, speaker: x, other: y, budget: settings.memoryTokens)
                let all = Bonds.tokens(Bonds.memory(bond, speaker: x, other: y, budget: 100_000))
                out.append("memory \(key): \(x) remembers (\(Bonds.tokens(block)) of \(settings.memoryTokens) tokens; all of it \(all)): \(block)")
            }
        }
        return out
    }
}

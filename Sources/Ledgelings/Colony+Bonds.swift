import Foundation
import LedgelingsCore

/// Living together: every pair on screen adds up time side by side, and a pair
/// that has shared the screen long enough gets a small story from the model,
/// which colours their next few conversations (`Bonds`).
extension Colony {
    /// Time together is added to the bonds, and saved, this often.
    static let bondSaveEvery = 30.0

    /// Every frame: everyone on screen spent `dt` more with everyone else.
    func liveTogether(dt: Double) {
        togetherPending += dt
        guard togetherPending >= Self.bondSaveEvery else { return }
        let seconds = togetherPending
        togetherPending = 0
        let names = creatures.indices.map { character(forCreature: $0).name }
        bonds.change { $0.liveTogether(seconds, names: names) }
    }

    /// What goes into creature `i`'s prompt about `j`: the bond and the story
    /// running between them (with plots on), what they remember of each other and
    /// what `i` did today (with memory on), within the owner's token budget.
    /// Empty for strangers with nothing on.
    func relationship(of i: Int, with j: Int) -> String {
        let a = character(forCreature: i).name, b = character(forCreature: j).name
        var parts: [String] = []
        if settings.plotsEnabled { parts.append(Bonds.context(bonds.bond(a, b), speaker: a, other: b)) }
        if settings.memoryEnabled {
            parts.append(Bonds.memory(bonds.bond(a, b), speaker: a, other: b, budget: settings.memoryTokens))
            if settings.dayContextEnabled { parts.append(Bonds.daySoFar(of: a, in: bonds.book, items: settings.dayContextItems)) }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The story running between two creatures, for the chat log: "part 2 of 6: …".
    func plotLabel(_ i: Int, _ j: Int) -> String? {
        guard settings.plotsEnabled,
              let plot = bonds.bond(character(forCreature: i).name, character(forCreature: j).name)?.plot else { return nil }
        return tr("part %d of %d: %@", min(plot.told + 1, plot.length), plot.length, plot.text)
    }

    /// A conversation between `a` and `b` (names) ended: count it, and ask for
    /// their next story if they are due one. `kind`: `.tea` for a whole tea party.
    func talked(_ a: String, _ b: String, lines: [ChatLog.Line], as kind: Bonds.Moment.Kind = .talk) {
        guard !lines.isEmpty else { return }
        bonds.change { $0.talked(a, b, lines: lines, as: kind) }
        writePlotIfDue(a, b)
    }

    /// Something two creatures lived through together that is not a conversation
    /// (a flower, a paper plane, a cursor grab), for their storyline.
    func shared(_ i: Int, _ j: Int, _ kind: Bonds.Moment.Kind, detail: String? = nil,
                score: String? = nil, winners: [String]? = nil, asked: String? = nil) {
        guard creatures.indices.contains(i), creatures.indices.contains(j), i != j else { return }
        let a = character(forCreature: i).name, b = character(forCreature: j).name
        bonds.change { $0.note(a, b, Bonds.Moment(time: Date(), kind: kind, who: a, detail: detail, score: score, winners: winners, asked: asked)) }
    }

    /// The pair's past from before moments were kept, read from the chat log once.
    func seedStoryline(_ a: String, _ b: String) {
        guard bonds.bond(a, b)?.seeded == false else { return }
        let exchanges = history.days().reversed().flatMap { history.exchanges(on: $0) }
        bonds.change { $0.seed(a, b, from: exchanges) }
        trace?("story: \(Bonds.key(a, b)) seeded, \(bonds.bond(a, b)?.tally ?? [:])")
    }

    /// The pair's next story, ready for their next conversation: one model call
    /// in the background, recorded as `.plots` whatever comes back; with the
    /// built-in lines, a story from what they lived through, no call at all.
    /// `now`: ask even if they have not lived together long enough (`--plot`).
    func writePlotIfDue(_ a: String, _ b: String, now: Bool = false) {
        let key = Bonds.key(a, b)
        if now { bonds.change { $0.update(a, b) { $0.plot = nil; $0.lastAsked = nil } } }
        guard settings.plotsEnabled, !plotting.contains(key),
              bonds.book.needsPlot(a, b, after: now ? 0 : settings.plotAfterHours * 3600, now: Date()) else { return }
        let telling = settings.storyTelling
        if telling != nil { seedStoryline(a, b) }
        guard let bond = bonds.bond(a, b) else { return }
        let length = settings.plotLength
        if settings.brain == .script {
            let written = Bonds.builtInPlot(bond, using: &rng)
            bonds.change { $0.begin(a, b, written, length: length, at: Date(), keepsStory: telling != nil, words: telling?.words ?? Bonds.storyWords) }
            trace?("plot: \(key) · built in · plot: \(written.plot)")
            return
        }
        guard let service = settings.chatClient(),
              let i = creatures.indices.first(where: { character(forCreature: $0).name == a }),
              let j = creatures.indices.first(where: { character(forCreature: $0).name == b }) else { return }
        let values = Bonds.plotValues(bond, a: (a, kind(ofCreature: i), character(forCreature: i).persona),
                                      b: (b, kind(ofCreature: j), character(forCreature: j).persona), length: length,
                                      story: telling)
        let prompt = Banter.render(settings.plotPrompt, values)
        plotting.insert(key)
        trace?("plot: asking for \(key), \(prompt.count / 4) tokens or so")
        Task { [weak self] in
            var cost: Double?, written: Bonds.Written?
            do {
                // Room for a thinking model to think a little and still answer: at 160
                // tokens one spent them all thinking and sent nothing back.
                let answer = try await service.reply(system: Bonds.plotSystemPrompt, user: prompt,
                                                     maxTokens: Bonds.plotMaxTokens, reasoning: "low")
                if var usage = answer.usage {
                    if service.provider == .lmStudio { usage.cost = 0 }
                    cost = usage.cost
                    self?.spend.record(provider: service.provider, model: service.model, usage: usage, purpose: .plots)
                }
                written = Bonds.parse(answer.text)
                if written == nil { FileHandle.standardError.write(Data("Ledgelings plot: no PLOT line in \(answer.text.debugDescription)\n".utf8)) }
            } catch {
                FileHandle.standardError.write(Data("Ledgelings plot: \(error)\n".utf8))
            }
            guard let self else { return }
            plotting.remove(key)
            let now = Date()
            bonds.change { book in
                book.asked(a, b, at: now, cost: cost)
                if let written {
                    book.begin(a, b, written, length: length, at: now, keepsStory: telling != nil, words: telling?.words ?? Bonds.storyWords)
                }
            }
            if let written {
                talkStatus = tr("%@ and %@: %@", a, b, written.plot)

                trace?("plot: \(key) · bond: \(written.bond ?? "-") · plot: \(written.plot) · story: \(written.story ?? "(folded)")")
            }
        }
    }
}

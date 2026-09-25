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

    /// What goes into creature `i`'s prompt about `j`. Empty when plots are off,
    /// or the two have no bond or story yet.
    func relationship(of i: Int, with j: Int) -> String {
        guard settings.plotsEnabled else { return "" }
        let a = character(forCreature: i).name, b = character(forCreature: j).name
        return Bonds.context(bonds.bond(a, b), speaker: a, other: b)
    }

    /// The story running between two creatures, for the chat log: "part 2 of 6: …".
    func plotLabel(_ i: Int, _ j: Int) -> String? {
        guard settings.plotsEnabled,
              let plot = bonds.bond(character(forCreature: i).name, character(forCreature: j).name)?.plot else { return nil }
        return "part \(min(plot.told + 1, plot.length)) of \(plot.length): \(plot.text)"
    }

    /// A conversation between `a` and `b` (names) ended: count it, and ask for
    /// their next story if they are due one.
    func talked(_ a: String, _ b: String, lines: [ChatLog.Line]) {
        guard !lines.isEmpty else { return }
        bonds.change { $0.talked(a, b, lines: lines) }
        writePlotIfDue(a, b)
    }

    /// One model call, in the background, for the pair's next story; ready for
    /// their next conversation. Recorded as `.plots` whatever comes back.
    /// `now`: ask even if they have not lived together long enough (`--plot`).
    func writePlotIfDue(_ a: String, _ b: String, now: Bool = false) {
        let key = Bonds.key(a, b)
        if now { bonds.change { $0.update(a, b) { $0.plot = nil; $0.lastAsked = nil } } }
        guard settings.plotsEnabled, settings.brain != .script, !plotting.contains(key),
              bonds.book.needsPlot(a, b, after: now ? 0 : settings.plotAfterHours * 3600, now: Date()),
              let bond = bonds.bond(a, b), let service = settings.chatClient(),
              let i = creatures.indices.first(where: { character(forCreature: $0).name == a }),
              let j = creatures.indices.first(where: { character(forCreature: $0).name == b }) else { return }
        let length = settings.plotLength
        let values = Bonds.plotValues(bond, a: (a, kind(ofCreature: i), character(forCreature: i).persona),
                                      b: (b, kind(ofCreature: j), character(forCreature: j).persona), length: length)
        let prompt = Banter.render(settings.plotPrompt, values)
        plotting.insert(key)
        trace?("plot: asking for \(key)")
        Task { [weak self] in
            var cost: Double?, written: Bonds.Written?
            do {
                let answer = try await service.reply(system: Bonds.plotSystemPrompt, user: prompt, maxTokens: 160)
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
                if let written { book.begin(a, b, written, length: length, at: now) }
            }
            if let written {
                talkStatus = "\(a) and \(b): \(written.plot)"
                trace?("plot: \(key) · bond: \(written.bond ?? "-") · plot: \(written.plot)")
            }
        }
    }
}

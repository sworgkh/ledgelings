import AppKit
import LedgelingsCore

/// The cursor's hunts: every chase off an edge and every pick-up is counted per
/// character (`HuntBook`), and the creatures use their count. It rides in the
/// prompts they already send, says itself in built-in lines at a milestone or
/// now and then instead of a complaint, a tea story or a note, and in the
/// menace mood makes a much-hunted creature keep further from the cursor.
extension Colony {

    /// Creature `i` was just chased off its edge or picked up. True when it said
    /// something about its count, so nothing else talks over it.
    @discardableResult
    func hunted(_ i: Int) -> Bool {
        guard settings.huntCountEnabled, creatures.indices.contains(i) else { return false }
        let name = character(forCreature: i).name
        let n = hunts.count(name)
        beWary(i)
        trace?("hunt \(name): today \(n.today), week \(n.week), all \(n.all)")
        guard Hunts.isMilestone(n), canRemark(i, n) else { return false }
        let line = Hunts.line(by: name, n, mood: settings.cursorMood, using: &rng)
        say(line, from: i)
        history.record(ChatLog.Exchange(time: Date(), situation: huntSituation(i),
                                        provider: AppSettings.Brain.script.title, model: "",
                                        lines: [ChatLog.Line(speaker: name, text: line)]))
        return true
    }

    private func canRemark(_ i: Int, _ n: Hunts.Numbers) -> Bool {
        settings.huntTalkEnabled && settings.talkEnabled && Hunts.hasLine(n)
            && !busy.contains(i) && !complaining.contains(i) && bubbles[i] == nil && !voiceIsTaken
    }

    /// Today's count of everyone on screen, by name.
    private var huntsToday: [String: Int] {
        Dictionary(creatures.indices.map { i in
            let name = character(forCreature: i).name
            return (name, hunts.numbers(of: name).today)
        }, uniquingKeysWith: max)
    }

    /// Whether this moment brings the count up: the chance in the Chases tab.
    private func bringsItUp() -> Bool {
        settings.huntCountEnabled && settings.huntTalkEnabled
            && Double.random(in: 0..<100, using: &rng) < settings.huntTalkChance
    }

    /// What `indices` know of their counts, for `{situation}`; "" when counting or
    /// talking about it is off, or (unless `always`) this moment does not bring it up.
    func huntSentence(_ indices: [Int], always: Bool = false) -> String {
        guard settings.huntCountEnabled, settings.huntTalkEnabled, always || bringsItUp() else { return "" }
        let everyone = huntsToday
        return indices.filter(creatures.indices.contains).map { i in
            let name = character(forCreature: i).name
            return Hunts.sentence(for: name, hunts.numbers(of: name), everyone: everyone, mood: settings.cursorMood)
        }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// A built-in line about `i`'s count to say instead of the usual one, now and then.
    func huntLineInstead(_ i: Int) -> String? {
        guard creatures.indices.contains(i), bringsItUp() else { return nil }
        let name = character(forCreature: i).name, n = hunts.numbers(of: name)
        guard Hunts.hasLine(n) else { return nil }
        return Hunts.line(by: name, n, mood: settings.cursorMood, using: &rng)
    }

    /// For the Chats tab: the moment a creature spoke up about its count.
    private func huntSituation(_ i: Int) -> String {
        [almanac, "\(describe(i)).", huntSentence([i], always: true)].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// In the menace mood, hunted `huntWaryAfter` times today, it jumps away from further off.
    func beWary(_ i: Int) {
        guard creatures.indices.contains(i), sizes.indices.contains(i) else { return }
        let n = hunts.numbers(of: character(forCreature: i).name)
        let wary = settings.huntCountEnabled && settings.huntWary
            && Hunts.isWary(n, after: settings.huntWaryAfter, mood: settings.cursorMood)
        creatures[i].config.fleeRadius = fleeRadius(forSize: sizes[i]) * (wary ? CGFloat(Hunts.waryFactor) : 1)
    }
}

import Foundation
import LedgelingsCore

/// Plot twists, from the colony's side: every half minute the roster sees who is
/// on screen (`Gang.Roster.observe`); a newcomer's first meetings become moments
/// and facts of its pairs, a departure a fact for the leaver's closest friends;
/// and while the news is fresh, now and then a prompt carries it, or a built-in
/// line is about it. No call of its own: the news rides in prompts already sent.
extension Colony {

    /// Who is on screen now, by name, with their species' kind.
    var gangPresent: [String: String] {
        var present: [String: String] = [:]
        for i in creatures.indices { present[character(forCreature: i).name] = kind(ofCreature: i) }
        return present
    }

    /// The roster looks at who is on screen; each change it records is acted on.
    func observeGang(now: Date = Date()) {
        let present = gangPresent
        guard !present.isEmpty else { return }
        let known = Array(Set(bonds.book.bonds.values.flatMap(\.names)))
        var events: [Gang.Event] = []
        bonds.change { events = $0.gang.observe(present, now: now, known: known) }
        for event in events { happened(event) }
    }

    /// A change of the gang: traced, and remembered by the closest friends of a leaver or a returner.
    func happened(_ event: Gang.Event) {
        trace?("twist \(event.kind.rawValue) \(event.name)")
        guard settings.twistsEnabled, settings.memoryEnabled, event.kind != .joined, settings.twistDepartures else { return }
        let fact = event.kind == .left ? tr("%@ left the gang", event.name) : tr("%@ came back to the gang", event.name)
        for friend in closestFriends(of: event.name) {
            bonds.change { $0.remember(friend, event.name, fact, source: "gang", at: event.time, keep: settings.memoryFacts) }
            trace?("twist memory \(Bonds.key(friend, event.name)): \(fact)")
        }
    }

    /// The characters `name` spent the most time with, most first.
    func closestFriends(of name: String, count: Int = 3) -> [String] {
        bonds.book.closest.filter { $0.names.contains(name) && $0.together > 0 }
            .compactMap { $0.names.first { $0 != name } }
            .prefix(count).map { $0 }
    }

    /// The news still fresh, as the settings have it.
    var freshNews: [Gang.Event] {
        guard settings.twistsEnabled else { return [] }
        return bonds.book.gang.fresh(days: settings.twistDays, departures: settings.twistDepartures, now: Date())
    }

    /// Whether the conversation between `a` and `b` brings the news up: one roll a
    /// pair, kept for two minutes so both sides of it agree; the chance fades
    /// with the news's age. The events it is about, or none.
    func newsFor(_ a: String, _ b: String) -> [Gang.Event] {
        let events = freshNews
        guard !events.isEmpty else { return [] }
        let key = Bonds.key(a, b)
        if let roll = newsRolls[key], roll.until > elapsed { return roll.brings ? events : [] }
        let chance = forceNews ? 1 : Gang.chance(settings.twistChance / 100, events, days: settings.twistDays, now: Date())
        let brings = Double.random(in: 0..<1, using: &rng) < chance
        newsRolls[key] = (elapsed + 120, brings)
        return brings ? events : []
    }

    /// The news block for `a` talking to `b`, when this conversation brings it up; "" otherwise.
    func news(of a: String, with b: String) -> String {
        let events = newsFor(a, b)
        guard !events.isEmpty else { return "" }
        let text = Gang.news(events, speaker: a, book: bonds.book, now: Date())
        trace?("twist \(a) hears: \(text)")
        return text
    }

    /// The news for a story or a diary, told of the pair: always while fresh.
    var pairNews: String { Gang.news(freshNews, speaker: nil, now: Date()) }

    /// The first time a fresh newcomer and another share anything: a "first
    /// meeting" moment of their storyline, and a fact both remember. A pair that
    /// has shared anything before (a renamed character back to an old name) has met.
    func firstMeeting(_ a: String, _ b: String, at now: Date = Date()) {
        guard settings.twistsEnabled, a != b else { return }
        let fresh = bonds.book.gang.newcomers(days: settings.twistDays, now: now)
        guard let newcomer = [a, b].first(where: fresh.contains), (bonds.bond(a, b)?.tally.values.reduce(0, +) ?? 0) == 0 else { return }
        let other = newcomer == a ? b : a
        bonds.change { book in
            book.note(newcomer, other, Bonds.Moment(time: now, kind: .meet, who: newcomer))
            if settings.memoryEnabled {
                book.remember(newcomer, other, tr("%1$@ and %2$@ first met when %1$@ was new to the gang", newcomer, other),
                              source: "gang", at: now, keep: settings.memoryFacts)
            }
        }
        trace?("twist first meeting: \(newcomer) meets \(other)")
    }

    /// Built-in lines about the news, when this conversation brings it up: a
    /// newcomer or a returner talks about itself; otherwise each says its own
    /// line about whoever arrived, left or came back. Never gossip about the listener to its face.
    func builtInTwist(_ speaker: Int, to listener: Int) -> [(who: Int, text: String, builtIn: Bool)]? {
        let a = character(forCreature: speaker).name, b = character(forCreature: listener).name
        let events = newsFor(a, b).filter { $0.name != b }
        guard let event = events.last(where: { $0.name == a }) ?? events.last else { return nil }
        let first = Gang.line(about: event, by: a, using: &rng)
        trace?("twist built in: \(a) on \(event.kind.rawValue) \(event.name)")
        guard event.name != a else { return [(speaker, first, true)] }
        return [(speaker, first, true), (listener, Gang.line(about: event, by: b, using: &rng), true)]
    }

    /// `--twist join|leave|back <name>`: the event made by hand, as if it had just happened.
    func fakeTwist(_ kind: Gang.Event.Kind, _ name: String) {
        observeGang()
        let species = gangPresent[name] ?? bonds.book.gang.members[name]?.kind
        var event: Gang.Event?
        bonds.change { event = $0.gang.fake(kind, name, species: species, at: Date()) }
        if let event { happened(event) }
    }

    /// The roster and the news, for `--twist` and `--memory`.
    func gangDump() -> [String] {
        let gang = bonds.book.gang, now = Date()
        var out = gang.members.values.sorted { $0.name < $1.name }.map { m in
            let state = m.pending ? "arriving" : m.away.map { "away since \(Bonds.day($0))" } ?? "here"
            return "gang \(m.name): \(state), first seen \(Bonds.day(m.firstSeen)), last seen \(Bonds.day(m.lastSeen))"
        }
        for e in gang.events.suffix(10) { out.append("gang event \(e.kind.rawValue) \(e.name) \(Bonds.ago(e.time, now: now))") }
        let fresh = freshNews
        out.append("gang news (\(fresh.count) fresh, chance now \(Int((Gang.chance(settings.twistChance / 100, fresh, days: settings.twistDays, now: now) * 100).rounded()))%): \(Gang.news(fresh, speaker: nil, now: now))")
        return out
    }
}

import Foundation

/// Who is in the gang, and the plot twist when that changes.
///
/// The **roster** keeps every character who has ever been on screen, with when
/// it was first and last seen. When the gang changes it records an **event**: a
/// newcomer **joined** (a species switched on, the count raised, a sprite
/// imported, a new built-in from an update), someone **left** (its species off,
/// the count lowered, its sprite deleted) or someone who left **came back**.
/// A change counts once it has held for `settle` seconds, so dragging the count
/// up and down again is nobody's arrival. Sleeping, hiding in the house or
/// moving to another monitor keeps a character on screen: it has not left.
///
/// On the first look (the first launch with a roster) everyone on screen is
/// already known, and so is everyone the bonds remember: no twist about the
/// whole gang on day one.
///
/// For a few days after an event the others talk about it: the **news** block
/// rides in the prompts already sent (conversation, tea, letters, story,
/// diary), now and then, the chance fading as the news gets old. Nothing here
/// calls a model.
public enum Gang {

    /// A change of the gang counts once it has held this long.
    public static let settle: TimeInterval = 120
    /// Events kept, newest last; the news only ever uses the last few days of them.
    public static let eventsKept = 40

    public struct Member: Codable, Equatable, Sendable {
        public var name: String
        /// Its species' `kind`, as last seen.
        public var kind: String?
        public var firstSeen: Date
        public var lastSeen: Date
        /// Just arrived, not yet on screen for `settle`: not a member until then.
        public var pending = false
        /// Gone since, when it has left the gang.
        public var away: Date?
        /// Back on screen since, while a return is settling.
        public var backSince: Date?
        public init(name: String, kind: String?, firstSeen: Date, lastSeen: Date, pending: Bool = false, away: Date? = nil) {
            self.name = name; self.kind = kind; self.firstSeen = firstSeen; self.lastSeen = lastSeen
            self.pending = pending; self.away = away
        }
    }

    public struct Event: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, CaseIterable, Sendable { case joined, left, returned }
        public var kind: Kind
        public var name: String
        /// Its species' `kind`.
        public var species: String?
        public var time: Date
        /// For a return: when it had left.
        public var awaySince: Date?
        public init(kind: Kind, name: String, species: String? = nil, time: Date, awaySince: Date? = nil) {
            self.kind = kind; self.name = name; self.species = species; self.time = time; self.awaySince = awaySince
        }
    }

    public struct Roster: Codable, Equatable, Sendable {
        public var members: [String: Member] = [:]
        public var events: [Event] = []
        /// The first look, when everyone then on screen became known without a twist.
        public var started: Date?
        public init() {}

        /// The characters on screen now (name → its species' kind): who arrived,
        /// who left and who came back, once each change has held `settle` seconds.
        /// `known`: names the bonds remember, taken as old members on the first look.
        @discardableResult
        public mutating func observe(_ present: [String: String], now: Date, known: [String] = [],
                                     settle: TimeInterval = Gang.settle) -> [Event] {
            guard started != nil else {
                started = now
                for (name, kind) in present { members[name] = Member(name: name, kind: kind, firstSeen: now, lastSeen: now) }
                for name in known where present[name] == nil && members[name] == nil {
                    members[name] = Member(name: name, kind: nil, firstSeen: now, lastSeen: now, away: now)
                }
                return []
            }
            var out: [Event] = []
            for (name, kind) in present {
                guard var m = members[name] else {
                    members[name] = Member(name: name, kind: kind, firstSeen: now, lastSeen: now, pending: true)
                    if settle <= 0 { members[name]?.pending = false; out.append(Event(kind: .joined, name: name, species: kind, time: now)) }
                    continue
                }
                m.kind = kind
                if m.pending, now.timeIntervalSince(m.firstSeen) >= settle {
                    m.pending = false
                    out.append(Event(kind: .joined, name: name, species: kind, time: m.firstSeen))
                }
                if let away = m.away {
                    let since = m.backSince ?? now
                    m.backSince = since
                    if now.timeIntervalSince(since) >= settle {
                        out.append(Event(kind: .returned, name: name, species: kind, time: since, awaySince: away))
                        m.away = nil; m.backSince = nil
                    }
                }
                m.lastSeen = now
                members[name] = m
            }
            for (name, var m) in members where present[name] == nil {
                if m.pending { members.removeValue(forKey: name); continue }
                m.backSince = nil
                if m.away == nil, now.timeIntervalSince(m.lastSeen) >= settle {
                    m.away = m.lastSeen
                    out.append(Event(kind: .left, name: name, species: m.kind, time: m.lastSeen))
                }
                members[name] = m
            }
            out.sort { ($0.time, $0.name) < ($1.time, $1.name) }
            record(out)
            return out
        }

        /// An event made by hand (`--twist`), the member's state to match.
        @discardableResult
        public mutating func fake(_ kind: Event.Kind, _ name: String, species: String?, at now: Date) -> Event {
            if started == nil { started = now }
            var m = members[name] ?? Member(name: name, kind: species, firstSeen: now, lastSeen: now)
            let event: Event
            switch kind {
            case .joined:
                m.firstSeen = now; m.pending = false; m.away = nil
                event = Event(kind: .joined, name: name, species: species ?? m.kind, time: now)
            case .left:
                m.away = now; m.backSince = nil
                event = Event(kind: .left, name: name, species: species ?? m.kind, time: now)
            case .returned:
                let since = m.away ?? Calendar.current.date(byAdding: .day, value: -3, to: now) ?? now
                m.away = nil; m.backSince = nil
                event = Event(kind: .returned, name: name, species: species ?? m.kind, time: now, awaySince: since)
            }
            m.lastSeen = now
            members[name] = m
            record([event])
            return event
        }

        mutating func record(_ new: [Event]) {
            guard !new.isEmpty else { return }
            events = Array((events + new).suffix(Gang.eventsKept))
        }

        /// The news still fresh `now`: each character's newest event from the last
        /// `days` days, oldest first. `departures` false: leaving and coming back are left out.
        public func fresh(days: Int, departures: Bool = true, now: Date) -> [Event] {
            let window = Double(max(0, days)) * 86_400
            var newest: [String: Event] = [:]
            for e in events where now.timeIntervalSince(e.time) < window && e.time <= now.addingTimeInterval(60) {
                if let had = newest[e.name], had.time > e.time { continue }
                newest[e.name] = e
            }
            return newest.values
                .filter { departures || $0.kind == .joined }
                .sorted { ($0.time, $0.name) < ($1.time, $1.name) }
        }

        /// The newcomers still fresh: a joined event in the last `days` days, and here since.
        public func newcomers(days: Int, now: Date) -> Set<String> {
            Set(fresh(days: days, now: now).filter { $0.kind == .joined }.map(\.name))
        }

        public mutating func forgetNews() { events = [] }
    }

    // MARK: How often it comes up

    /// The chance this conversation brings the news up: `base` (0...1) while the
    /// newest event is new, fading to nothing once it is `days` days old.
    public static func chance(_ base: Double, _ events: [Event], days: Int, now: Date) -> Double {
        guard let newest = events.map(\.time).max(), days > 0 else { return 0 }
        let window = Double(days) * 86_400, age = max(0, now.timeIntervalSince(newest))
        guard age < window else { return 0 }
        return min(1, max(0, base)) * (1 - age / window)
    }

    // MARK: The news, for a prompt

    /// The news as `speaker` hears it (nil: told of the pair, for a story or a
    /// diary): who arrived, left or came back and when, with what the speaker
    /// remembers of a leaver or a returner. "" without fresh news.
    public static func news(_ events: [Event], speaker: String?, book: Bonds.Book? = nil, now: Date) -> String {
        guard !events.isEmpty else { return "" }
        var said: [String] = []
        for e in events {
            let when = Bonds.ago(e.time, now: now)
            let mine = speaker == e.name
            switch e.kind {
            case .joined:
                if mine {
                    said.append(tr("You are new here: you joined the gang %@, and everyone is still new to you; be shy, curious or show off, as you would.", when))
                } else if let species = e.species, !species.isEmpty {
                    said.append(tr("%@, %@, is new to the gang: arrived %@.", e.name, Banter.spoken(species), when))
                } else {
                    said.append(tr("%@ is new to the gang: arrived %@.", e.name, when))
                }
            case .left:
                said.append(tr("%1$@ has left the gang (%2$@); nobody has seen %1$@ since, or knows where to.", e.name, when))
            case .returned:
                let since = e.awaySince.map { Bonds.day($0) } ?? tr("a while")
                said.append(mine ? tr("You are back in the gang %@, after being away since %@; the others remember you.", when, since)
                                 : tr("%@ came back to the gang %@, after being away since %@.", e.name, when, since))
            }
            if !mine, let speaker, e.kind != .joined, let summary = book?.bond(speaker, e.name)?.summary {
                said.append(tr("You and %@: %@", e.name, summary))
            }
        }
        let close = speaker == nil
            ? tr("It may touch their story.")
            : tr("If it suits you, bring it up in your own way (a welcome, suspicion, gossip, missing someone, a rumour), in a word or two; never explain it.")
        return tr("News in the gang: %@", said.joined(separator: " ")) + " " + close
    }

    /// Put `news` after a rendered prompt, unless it is empty.
    public static func withNews(_ prompt: String, _ news: String) -> String {
        news.isEmpty ? prompt : prompt + "\n" + news
    }

    // MARK: Built-in lines

    /// A built-in line about `event`, said by `speaker` in its own voice: about
    /// someone new, someone gone, someone back, or (its own arrival or return)
    /// about itself. `{name}` is who it is about.
    public static func line(about event: Event, by speaker: String, using rng: inout some RandomNumberGenerator) -> String {
        let pool: [String]
        if event.name == speaker {
            pool = event.kind == .returned ? backSelfAnyone() : arrivalSets()[speaker].map { [$0] } ?? arrivalAnyone()
        } else {
            switch event.kind {
            case .joined: pool = newSets()[speaker].map { [$0] } ?? newAnyone()
            case .left: pool = goneSets()[speaker].map { [$0] } ?? goneAnyone()
            case .returned: pool = backSets()[speaker].map { [$0] } ?? backAnyone()
            }
        }
        return Banter.render(pool.randomElement(using: &rng) ?? "", ["name": event.name])
    }

    public static let newSets = Translated(english: englishNewLines, [.russian: russianNewLines])
    public static let newAnyone = Translated(english: englishNewAnyone, [.russian: russianNewAnyone])
    public static let goneSets = Translated(english: englishGoneLines, [.russian: russianGoneLines])
    public static let goneAnyone = Translated(english: englishGoneAnyone, [.russian: russianGoneAnyone])
    public static let backSets = Translated(english: englishBackLines, [.russian: russianBackLines])
    public static let backAnyone = Translated(english: englishBackAnyone, [.russian: russianBackAnyone])
    public static let arrivalSets = Translated(english: englishArrivalLines, [.russian: russianArrivalLines])
    public static let arrivalAnyone = Translated(english: englishArrivalAnyone, [.russian: russianArrivalAnyone])
    public static let backSelfAnyone = Translated(english: englishBackSelfAnyone, [.russian: russianBackSelfAnyone])
}

import Foundation

/// The effects the creatures wear and the moments they mark (SPEC §7.19): which style or moment plays
/// which pixelfx effect, when one may play again, which switches turn it off, and the seasons. The drawing
/// itself is `FXInstance` (`PixelFX/`); the colony asks `Effects.Rules` before starting one.
public enum Effects {
    /// A style a creature wears for a while, then takes off.
    public enum Style: String, CaseIterable, Codable, Sendable {
        case frost, smitten, charged, firedUp, haunted

        /// Its English name, untranslated, for the printed steps (`fx 3.20 Smitten on Boo`).
        public var name: String {
            switch self {
            case .frost: "Frost"
            case .smitten: "Smitten"
            case .charged: "Charged"
            case .firedUp: "Fired up"
            case .haunted: "Haunted"
            }
        }

        /// The pixelfx effect that draws it.
        public var effect: String {
            switch self {
            case .frost: "status/frozen"
            case .smitten: "status/charmed"
            case .charged: "lightning/electrified"
            case .firedUp: "status/burning"
            case .haunted: "status/cursed"
            }
        }
        public var title: String {
            switch self {
            case .frost: tr("Frost")
            case .smitten: tr("Smitten")
            case .charged: tr("Charged")
            case .firedUp: tr("Fired up")
            case .haunted: tr("Haunted")
            }
        }
        /// What it shows and when it plays, for its row.
        public var detail: String {
            switch self {
            case .frost: tr("Frost, icicles, a shiver: in winter now and then, or left alone too long")
            case .smitten: tr("A heart overhead, pink eyes: two friends meet, an invitation is accepted")
            case .charged: tr("Sparks and arcs: grabbing the cursor, or a fast hour of typing")
            case .firedUp: tr("Small flames and scorch marks: grumpy at the cursor, or losing a game")
            case .haunted: tr("Violet smoke, glowing eyes, a skull: around Halloween, or Boo spooking a friend")
            }
        }
        /// Busy enough that Reduce motion turns it off.
        public var busy: Bool { self == .charged || self == .firedUp }
        /// The settings key of its switch.
        public var key: String { "effectStyle." + rawValue }
    }

    /// The features a moment belongs to, which is how the settings page groups them.
    public enum Feature: String, CaseIterable, Sendable {
        case screens, movingAbout, cursorGrab, ballGames, bonds, spriteKit, creatures, garden, beds, night, seasons
        case reminders, calendar, dictation, translate, clipboard, costs

        public var title: String {
            switch self {
            case .screens: tr("Screens")
            case .movingAbout: tr("Moving about")
            case .cursorGrab: tr("Cursor grab")
            case .ballGames: tr("Ball games")
            case .bonds: tr("Bonds")
            case .spriteKit: tr("Sprite kit")
            case .creatures: tr("Creatures")
            case .garden: tr("Garden")
            case .beds: tr("Beds")
            case .night: tr("Night")
            case .seasons: tr("Seasons")
            case .reminders: tr("Reminders")
            case .calendar: tr("Calendar")
            case .dictation: tr("Dictation")
            case .translate: tr("Translate")
            case .clipboard: tr("Clipboard")
            case .costs: tr("Costs")
            }
        }
    }

    /// A moment in a feature the app already has, marked by an effect on the creature it happens to.
    public enum Moment: String, CaseIterable, Codable, Sendable {
        case leaveScreen, arriveScreen, hardLanding, dizzy, goal, friends, newArrival, poof, bloom, asleep
        case night, winter, autumn, spring, heyLook, clockTicking, listening, translating, copied, moneySpent

        public var feature: Feature {
            switch self {
            case .leaveScreen, .arriveScreen: .screens
            case .hardLanding: .movingAbout
            case .dizzy: .cursorGrab
            case .goal: .ballGames
            case .friends: .bonds
            case .newArrival: .spriteKit
            case .poof: .creatures
            case .bloom: .garden
            case .asleep: .beds
            case .night: .night
            case .winter, .autumn, .spring: .seasons
            case .heyLook: .reminders
            case .clockTicking: .calendar
            case .listening: .dictation
            case .translating: .translate
            case .copied: .clipboard
            case .moneySpent: .costs
            }
        }

        /// The pixelfx effect that marks it.
        public var effect: String {
            switch self {
            case .leaveScreen: "arcane/blink-out"
            case .arriveScreen: "arcane/blink-in"
            case .hardLanding: "impacts/heavy-landing"
            case .dizzy: "status/stunned"
            case .goal: "ui/confetti"
            case .friends: "ui/level-up"
            case .newArrival: "spawn/egg-hatch"
            case .poof: "spawn/poof"
            case .bloom: "nature/healing-bloom"
            case .asleep: "status/sleep"
            case .night: "weather/fireflies"
            case .winter: "weather/snow"
            case .autumn: "weather/falling-leaves"
            case .spring: "weather/cherry-blossoms"
            case .heyLook: "ui/exclamation"
            // The dial the owner picked from the pictures, ticking round; the magic circle is Translate's.
            case .clockTicking: "status/slowed"
            case .listening: "lightning/charge-up"
            case .translating: "arcane/magic-circle-cast"
            case .copied: "pickups/collect-burst"
            case .moneySpent: "spawn/coin-drop"
            }
        }

        public var title: String {
            switch self {
            case .leaveScreen: tr("Leaving a monitor")
            case .arriveScreen: tr("Arriving on a monitor")
            case .hardLanding: tr("A hard landing")
            case .dizzy: tr("Dizzy")
            case .goal: tr("Goal!")
            case .friends: tr("Friends for real")
            case .newArrival: tr("A new arrival")
            case .poof: tr("Poof, gone")
            case .bloom: tr("A flower comes up")
            case .asleep: tr("Fast asleep")
            case .night: tr("Night falls")
            case .winter: tr("Winter")
            case .autumn: tr("Autumn")
            case .spring: tr("Spring")
            case .heyLook: tr("Hey, look!")
            case .clockTicking: tr("Clock ticking")
            case .listening: tr("Listening")
            case .translating: tr("Translating")
            case .copied: tr("Copied!")
            case .moneySpent: tr("Money spent")
            }
        }
        /// When it plays and what it shows, for its row's tooltip.
        public var detail: String {
            switch self {
            case .leaveScreen: tr("It blinks out when it moves to another monitor")
            case .arriveScreen: tr("It blinks in on the monitor it moved to")
            case .hardLanding: tr("Dust flies when it drops from high up")
            case .dizzy: tr("Stars spin round its head after the cursor shakes it about")
            case .goal: tr("Confetti on a goal, a basket or a home run")
            case .friends: tr("A level-up when a friendship grows a stage")
            case .newArrival: tr("An egg hatches when a new species joins")
            case .poof: tr("A poof when a creature is removed")
            case .bloom: tr("Leaves and sparkles when a flower is planted")
            case .asleep: tr("Floating Zs and a nightcap, in place of the plain Zs")
            case .night: tr("Fireflies along the bottom of the screen after dark")
            case .winter: tr("Snow drifting down, December to February")
            case .autumn: tr("Leaves falling, September to November")
            case .spring: tr("Petals drifting, March to May")
            case .heyLook: tr("An exclamation mark when a reminder is due")
            case .clockTicking: tr("A ticking clock five minutes before a meeting in your calendar")
            case .listening: tr("Charging up while you dictate")
            case .translating: tr("A magic circle while a translation is on its way")
            case .copied: tr("A burst when something lands on the clipboard")
            case .moneySpent: tr("Coins drop when the day's spend passes your budget")
            }
        }

        /// Plays over the screen's bottom edge for a while rather than on one creature.
        public var ambient: Bool { self == .night || self == .winter || self == .autumn || self == .spring }
        /// Plays for as long as something lasts (asleep, listening, translating), not once.
        public var held: Bool { self == .asleep || self == .listening || self == .translating }
        /// Busy enough that Reduce motion turns it off.
        public var busy: Bool {
            switch self {
            case .leaveScreen, .arriveScreen, .goal, .friends, .newArrival, .poof, .night, .winter, .autumn, .spring,
                 .listening, .translating, .copied, .moneySpent: true
            case .hardLanding, .dizzy, .bloom, .asleep, .heyLook, .clockTicking: false
            }
        }
        /// The fewest seconds between two of it on one creature.
        public var cooldown: Double {
            switch self {
            case .leaveScreen, .arriveScreen: 5
            case .hardLanding: 45
            case .dizzy: 60
            case .goal: 6
            case .friends, .newArrival, .poof, .heyLook, .moneySpent: 0
            case .bloom: 20
            case .clockTicking: 120
            case .copied: 8
            case .asleep, .listening, .translating, .night, .winter, .autumn, .spring: 0
            }
        }
        /// The settings key of its switch.
        public var key: String { "effectMoment." + rawValue }
    }

    /// How often styles play on their own.
    public enum Frequency: String, CaseIterable, Codable, Sendable {
        case rarely, sometimes, often
        public var title: String {
            switch self {
            case .rarely: tr("Rarely")
            case .sometimes: tr("Sometimes")
            case .often: tr("Often")
            }
        }
        /// The chance a trigger (two friends meeting, a grab) puts a style on.
        public var chance: Double {
            switch self {
            case .rarely: 0.25
            case .sometimes: 0.5
            case .often: 1
            }
        }
        /// The fewest minutes before one creature wears the same style again.
        public var cooldownMinutes: Double {
            switch self {
            case .rarely: 30
            case .sometimes: 10
            case .often: 3
            }
        }
        /// About how many minutes apart a style comes now and then on its own (winter frost, Halloween).
        public var everyMinutes: Double {
            switch self {
            case .rarely: 60
            case .sometimes: 20
            case .often: 6
            }
        }
    }

    /// Reduce motion: as the system says, or always on, or always off.
    public enum ReduceMotion: String, CaseIterable, Codable, Sendable {
        case system, on, off
        public var title: String {
            switch self {
            case .system: tr("As the system")
            case .on: tr("On")
            case .off: tr("Off")
            }
        }
        public func isOn(system: Bool) -> Bool {
            switch self {
            case .system: system
            case .on: true
            case .off: false
            }
        }
    }

    /// What can put a style on a creature.
    public enum Trigger: String, CaseIterable, Sendable {
        case winter, leftAlone, friendsMeet, invitationAccepted, cursorGrab, fastTyping, grumpy, lostGame, halloween, booSpooks

        public var style: Style {
            switch self {
            case .winter, .leftAlone: .frost
            case .friendsMeet, .invitationAccepted: .smitten
            case .cursorGrab, .fastTyping: .charged
            case .grumpy, .lostGame: .firedUp
            case .halloween, .booSpooks: .haunted
            }
        }
        /// Comes on its own now and then (in season), rather than from something that happened.
        public var nowAndThen: Bool { self == .winter || self == .halloween }
    }

    // MARK: Friendship

    /// Moments shared at which a friendship grows a stage: friends, good friends, close, as close as can be.
    public static let friendshipStages = [Plays.friendsAt, 8, 14, Int(Plays.closeAt)]

    /// How far a pair's friendship has grown: 0 before they are friends, up to 4.
    public static func friendshipStage(_ bond: Bonds.Bond?) -> Int {
        guard let bond else { return 0 }
        let moments = Swift.max(bond.tally.values.reduce(0, +), bond.talks)
        return friendshipStages.filter { moments >= $0 }.count
    }

    // MARK: The seasons

    public enum Season: String, CaseIterable, Sendable {
        case winter, spring, summer, autumn

        /// Northern-hemisphere months: December to February is winter, across the new year.
        public static func of(_ date: Date, calendar: Calendar = .current) -> Season {
            switch calendar.component(.month, from: date) {
            case 12, 1, 2: .winter
            case 3, 4, 5: .spring
            case 6, 7, 8: .summer
            default: .autumn
            }
        }
        /// Its moment, if it has one: summer has none.
        public var moment: Moment? {
            switch self {
            case .winter: .winter
            case .spring: .spring
            case .autumn: .autumn
            case .summer: nil
            }
        }
    }

    /// The week round Halloween: 25 October to 1 November.
    public static func aroundHalloween(_ date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.month, .day], from: date)
        return (c.month == 10 && (c.day ?? 0) >= 25) || (c.month == 11 && c.day == 1)
    }

    // MARK: The switches

    /// Every switch at once, as the settings hold them.
    public struct Switches: Equatable, Sendable {
        public var enabled = true
        public var styles: Set<Style> = Set(Style.allCases)
        public var moments: Set<Moment> = Set(Moment.allCases)
        public var frequency: Frequency = .sometimes
        /// Reduce motion as it stands now, the system's setting already read.
        public var reduceMotion = false
        public init() {}

        public func allows(_ style: Style) -> Bool {
            enabled && styles.contains(style) && !(reduceMotion && style.busy)
        }
        public func allows(_ moment: Moment) -> Bool {
            enabled && moments.contains(moment) && !(reduceMotion && moment.busy)
        }
    }

    // MARK: When one may play

    /// Who last wore or marked what, and when, on the colony's clock (seconds).
    public struct Cooldowns: Sendable {
        var last: [String: Double] = [:]
        public init() {}

        static func key(_ what: String, _ creature: Int?) -> String { "\(what)#\(creature ?? -1)" }

        /// Whether `what` may play on `creature` at `now`, `every` seconds after the last; if so, it counts as played.
        public mutating func take(_ what: String, creature: Int?, now: Double, every: Double) -> Bool {
            let k = Self.key(what, creature)
            if let was = last[k], now - was < every { return false }
            last[k] = now
            return true
        }
        public func lastPlayed(_ what: String, creature: Int?) -> Double? { last[Self.key(what, creature)] }
        public mutating func forget(creaturesFrom count: Int) {
            last = last.filter { key, _ in Int(key.split(separator: "#").last ?? "") .map { $0 < count } ?? true }
        }
    }

    /// The rules in one place: what the switches allow, the chance of a style and the cooldowns.
    public struct Rules: Sendable {
        public var switches: Switches
        public var cooldowns = Cooldowns()
        public init(switches: Switches = Switches()) { self.switches = switches }

        /// A moment happened to `creature` (nil for the whole screen): whether its effect plays now.
        public mutating func moment(_ m: Moment, creature: Int?, now: Double) -> Bool {
            guard switches.allows(m) else { return false }
            return cooldowns.take(m.rawValue, creature: creature, now: now, every: m.cooldown)
        }

        /// Something that can put a style on `creature` happened; `roll` is a random number in 0..<1.
        /// The style it puts on, if any: switched on, past its cooldown, and lucky enough for the frequency.
        /// Things that come now and then on their own are rolled by `nowAndThen` and always take here.
        public mutating func style(for trigger: Trigger, creature: Int, now: Double, roll: Double) -> Style? {
            let style = trigger.style
            guard switches.allows(style) else { return nil }
            if !trigger.nowAndThen && roll >= switches.frequency.chance { return nil }
            let every = switches.frequency.cooldownMinutes * 60
            return cooldowns.take("style." + style.rawValue, creature: creature, now: now, every: every) ? style : nil
        }

        /// The chance per check that a now-and-then style comes, checked every `step` seconds, so it comes
        /// about every `Frequency.everyMinutes`.
        public func nowAndThenChance(step: Double) -> Double {
            1 - exp(-step / (switches.frequency.everyMinutes * 60))
        }
    }

    /// The ambient moment (fireflies or the season's particles) to show at `date`, or nil: fireflies after
    /// dark come before the season.
    public static func ambient(at date: Date, isNight: Bool, switches: Switches, calendar: Calendar = .current) -> Moment? {
        if isNight && switches.allows(.night) { return .night }
        if let m = Season.of(date, calendar: calendar).moment, switches.allows(m) { return m }
        return nil
    }

    /// Whether the ambient particles are out at `elapsed` seconds: for `seconds` out of every `everyMinutes`,
    /// the first time one whole wait after launch (not at every relaunch).
    public static func ambientShowing(at elapsed: Double, seconds: Double, everyMinutes: Double) -> Bool {
        let period = Swift.max(everyMinutes * 60, seconds)
        return elapsed >= period && elapsed.truncatingRemainder(dividingBy: period) < seconds
    }

    /// Which time out `elapsed` falls in, counting from 0: Stop ends one early and the next comes as ever.
    public static func ambientPeriod(at elapsed: Double, seconds: Double, everyMinutes: Double) -> Int {
        Int(elapsed / Swift.max(everyMinutes * 60, seconds))
    }

    /// Keys pressed in the last hour, from samples of the system's running count: fast typing is over `threshold`.
    public struct TypingWatch: Sendable {
        var samples: [(at: Double, count: Double)] = []
        public init() {}
        public mutating func add(count: Double, at now: Double) {
            samples.append((now, count))
            samples.removeAll { now - $0.at > 3600 }
        }
        /// Keys in the window the samples cover (an hour once there is one).
        public var keysInLastHour: Double {
            guard let first = samples.first, let last = samples.last else { return 0 }
            return Swift.max(0, last.count - first.count)
        }
        /// How long the samples go back.
        public var span: Double { (samples.last?.at ?? 0) - (samples.first?.at ?? 0) }
        /// A whole hour watched and more than `threshold` keys in it.
        public func fast(threshold: Double) -> Bool { span >= 3540 && keysInLastHour >= threshold }
        public mutating func reset() { samples.removeAll() }
    }
}

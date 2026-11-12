import CoreGraphics
import Foundation

/// Weather on a quiet screen (SPEC §7.20): snow that piles up, rain under umbrellas, wind that pushes. This is
/// the part with no screen in it: when the screen counts as quiet, which weather comes in which season, how a
/// spell of it comes and eases off, the snow piles, who shares an umbrella, the umbrella filling on the menu bar,
/// and what the wind does to a creature. The falling particles are `Weather.Sky`, drawn with the shared
/// `FXParticles`; the colony (`Colony+Weather`) puts it all on the screen.
public enum Weather {
    // MARK: The kinds

    public enum Kind: String, CaseIterable, Codable, Sendable {
        case snow, rain, wind, storm

        /// Its English name, untranslated, for the printed steps (`weather snow starts`).
        public var name: String { rawValue }

        public var title: String {
            switch self {
            case .snow: tr("Snow")
            case .rain: tr("Rain")
            case .wind: tr("Wind")
            case .storm: tr("Storm")
            }
        }
        /// What it does, for its row and its menu item's tooltip.
        public var detail: String {
            switch self {
            case .snow: tr("Flakes drift down and pile up on the bottom edge and the tops of windows; the creatures wade, shiver, build snowmen and throw snowballs")
            case .rain: tr("Rain with splashes and puddles; the creatures open umbrellas and huddle under one when they stand close")
            case .wind: tr("Gusts from one side blow leaves across; the creatures lean in, and a strong gust pushes the light ones")
            case .storm: tr("Rain and wind together: umbrellas turn inside out")
            }
        }
        public var snows: Bool { self == .snow }
        public var rains: Bool { self == .rain || self == .storm }
        public var blows: Bool { self == .wind || self == .storm }
    }

    /// How deep, how heavy, how strong.
    public enum Level: String, CaseIterable, Codable, Sendable {
        case low, medium, high
        public var title: String {
            switch self {
            case .low: tr("Low")
            case .medium: tr("Medium")
            case .high: tr("High")
            }
        }
        /// Times the medium amount.
        public var factor: Double {
            switch self {
            case .low: 0.5
            case .medium: 1
            case .high: 1.6
            }
        }
    }

    /// How often weather comes once the screen is quiet.
    public enum Frequency: String, CaseIterable, Codable, Sendable {
        case rarely, sometimes, often
        public var title: String {
            switch self {
            case .rarely: tr("Rarely")
            case .sometimes: tr("Sometimes")
            case .often: tr("Often")
            }
        }
        /// About how many quiet minutes go by between two spells.
        public var everyMinutes: Double {
            switch self {
            case .rarely: 60
            case .sometimes: 20
            case .often: 5
            }
        }
    }

    // MARK: The switches

    /// Every weather setting at once, as the settings hold them.
    public struct Switches: Equatable, Sendable {
        public var enabled = true
        public var snow = true
        public var rain = true
        public var wind = true
        public var quietMinutes = 5.0
        public var frequency: Frequency = .sometimes
        public var lastsMinutes = 3.0
        public var snowDepth: Level = .medium
        public var rainHeaviness: Level = .medium
        public var windStrength: Level = .medium
        /// Creatures closer than this (points, along the edge) share one umbrella; 0: everyone has its own.
        public var shareDistance = 40.0
        public var followSeason = true
        public var windowTops = true
        /// Reduce motion as it stands now, the system's setting already read: half the particles, no pushing.
        public var reduceMotion = false
        public init() {}

        /// Whether `kind` may come on its own: everything it needs is switched on (a storm needs rain and wind).
        public func allows(_ kind: Kind) -> Bool {
            guard enabled else { return false }
            switch kind {
            case .snow: return snow
            case .rain: return rain
            case .wind: return wind
            case .storm: return rain && wind
            }
        }
    }

    // MARK: When the screen is quiet

    /// What the Mac says about the screen now.
    public struct Screen: Equatable, Sendable {
        /// Seconds since a key was last pressed.
        public var keyIdle: Double
        /// Points the cursor travelled in the last `quietMinutes`.
        public var cursorTravel: Double
        /// An app fills a monitor, full screen (a film, a presentation).
        public var fullScreen = false
        /// An activity runs: a game, surfing, diving (`Activities`).
        public var activity = false
        /// A meeting: the calendar says one is on, or an app is using the microphone.
        public var meeting = false
        public init(keyIdle: Double, cursorTravel: Double, fullScreen: Bool = false, activity: Bool = false, meeting: Bool = false) {
            self.keyIdle = keyIdle
            self.cursorTravel = cursorTravel
            self.fullScreen = fullScreen
            self.activity = activity
            self.meeting = meeting
        }
    }

    /// The cursor may wander this many points in the quiet minutes and still count as left alone: a nudge of the
    /// mouse on the desk is not someone working.
    public static let cursorAllowance = 150.0

    /// Quiet: no key for `minutes`, the cursor barely moved in them, nothing full screen, no activity, no meeting.
    public static func isQuiet(_ s: Screen, minutes: Double) -> Bool {
        s.keyIdle >= minutes * 60 && s.cursorTravel <= cursorAllowance && !s.fullScreen && !s.activity && !s.meeting
    }

    /// Someone is back: a key in the last two seconds, or the cursor moved more than a nudge in them.
    public static func isBack(keyIdle: Double, recentTravel: Double) -> Bool { keyIdle < 2 || recentTravel > 60 }

    /// The cursor's path, sampled now and then: how far it went in a window of time.
    public struct CursorTrail: Sendable {
        var samples: [(at: Double, x: Double, y: Double)] = []
        public init() {}
        public mutating func add(_ p: CGPoint, at now: Double, keep seconds: Double) {
            samples.append((now, Double(p.x), Double(p.y)))
            samples.removeAll { now - $0.at > seconds }
        }
        /// Points travelled since `since`.
        public func travel(since: Double) -> Double {
            let recent = samples.filter { $0.at >= since }
            guard recent.count > 1 else { return 0 }
            return zip(recent, recent.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        }
        /// How long the trail goes back.
        public var span: Double { (samples.last?.at ?? 0) - (samples.first?.at ?? 0) }
        public mutating func reset() { samples.removeAll() }
    }

    // MARK: Which weather

    /// How likely each weather is in `season`: snow mostly in winter, rain any time, wind in autumn. With the
    /// season not followed, each allowed weather is as likely as any other.
    public static func weights(_ season: Effects.Season, switches: Switches) -> [Kind: Double] {
        let base: [Kind: Double]
        if !switches.followSeason {
            base = [.snow: 1, .rain: 1, .wind: 1, .storm: 1]
        } else {
            switch season {
            case .winter: base = [.snow: 6, .rain: 1, .wind: 1.5, .storm: 0.5]
            case .spring: base = [.snow: 0.3, .rain: 4, .wind: 1.5, .storm: 1]
            case .summer: base = [.snow: 0, .rain: 4, .wind: 1, .storm: 2]
            case .autumn: base = [.snow: 0.3, .rain: 3, .wind: 4, .storm: 2]
            }
        }
        return base.filter { switches.allows($0.key) && $0.value > 0 }
    }

    /// One weather drawn from the weights with `roll` in 0..<1, or nil when none is allowed.
    public static func pick(_ season: Effects.Season, switches: Switches, roll: Double) -> Kind? {
        let w = weights(season, switches: switches)
        let total = w.values.reduce(0, +)
        guard total > 0 else { return nil }
        var left = roll * total
        for kind in Kind.allCases {
            guard let v = w[kind] else { continue }
            if left < v { return kind }
            left -= v
        }
        return Kind.allCases.last { w[$0] != nil }
    }

    /// The chance per check, every `step` seconds of quiet, that weather comes: about once every `everyMinutes`.
    public static func chance(step: Double, frequency: Frequency) -> Double { 1 - exp(-step / (frequency.everyMinutes * 60)) }

    // MARK: A spell of weather

    /// One weather from its start to its end: it comes in over a few seconds, stays its time, and eases off.
    public struct Spell: Equatable, Sendable {
        public enum Phase: Equatable, Sendable { case coming, full, easing(since: Double) }
        public let kind: Kind
        public let lasts: Double
        public private(set) var age = 0.0
        public private(set) var phase: Phase = .coming
        /// Started by hand (the menu, Play now): the owner coming back does not end it.
        public let byHand: Bool
        /// Seconds to come in, and to ease off.
        public static let comeIn = 6.0, easeOff = 8.0

        public init(kind: Kind, lasts: Double, byHand: Bool = false) {
            self.kind = kind
            self.lasts = lasts
            self.byHand = byHand
        }

        public mutating func update(_ dt: Double) {
            age += dt
            if phase == .coming && age >= Self.comeIn { phase = .full }
            if case .easing = phase { return }
            if age >= lasts { ease() }
        }
        /// Ease off from now (time up, or someone came back): never all at once.
        public mutating func ease() {
            if case .easing = phase { return }
            phase = .easing(since: age)
        }
        public var isEasing: Bool { if case .easing = phase { true } else { false } }
        /// How much of it there is, 0...1: rising as it comes, falling as it eases.
        public var intensity: Double {
            let rise = Swift.min(1, age / Self.comeIn)
            if case .easing(let since) = phase { return rise * Swift.max(0, 1 - (age - since) / Self.easeOff) }
            return rise
        }
        /// Eased off all the way: no more falling (the snow on the ground melts on its own).
        public var isOver: Bool { isEasing && intensity <= 0 }
    }

    // MARK: Snow piles

    /// Snow lying along a surface (the bottom edge, a window's top): a height in art pixels per column, up to a cap.
    public struct Pile: Equatable, Sendable {
        public private(set) var heights: [Double]
        public var cap: Double
        public init(width: Int, cap: Double) {
            heights = Array(repeating: 0, count: Swift.max(0, width))
            self.cap = cap
        }
        public var width: Int { heights.count }
        public func height(at x: Int) -> Double { heights.indices.contains(x) ? heights[x] : 0 }
        public var deepest: Double { heights.max() ?? 0 }
        public var average: Double { heights.isEmpty ? 0 : heights.reduce(0, +) / Double(heights.count) }
        public var isEmpty: Bool { heights.allSatisfy { $0 <= 0.01 } }

        /// A flake landed at column `x`: a little more there, less either side, never past the cap; a column that
        /// stands too far above its neighbours slides onto them.
        public mutating func land(at x: Int, amount: Double = 0.5) {
            guard heights.indices.contains(x) else { return }
            add(x, amount)
            add(x - 1, amount / 2)
            add(x + 1, amount / 2)
            settle(around: x)
        }
        /// Snow everywhere at once, `amount` deep (a steady fall, the film's and the tests' way).
        public mutating func grow(by amount: Double) {
            for x in heights.indices { heights[x] = Swift.min(cap, heights[x] + amount) }
        }
        /// It melts: `amount` less everywhere, never below nothing.
        public mutating func melt(by amount: Double) {
            for x in heights.indices { heights[x] = Swift.max(0, heights[x] - amount) }
        }
        /// A foot stepped at `x`: a dent a pixel deep, two wide.
        public mutating func step(at x: Int) {
            for k in [x, x + 1] where heights.indices.contains(k) { heights[k] = Swift.max(0, heights[k] - 1) }
        }
        public mutating func clear() { for x in heights.indices { heights[x] = 0 } }

        private mutating func add(_ x: Int, _ a: Double) {
            guard heights.indices.contains(x) else { return }
            heights[x] = Swift.min(cap, heights[x] + a)
        }
        private mutating func settle(around x: Int) {
            // A few passes outward, so a heap slides down both sides rather than leaving a step further out.
            for _ in 0..<6 {
                var moved = false
                for k in Swift.max(0, x - 10)...Swift.min(heights.count - 1, x + 10) {
                    for n in [k - 1, k + 1] where heights.indices.contains(n) && heights[k] - heights[n] > 2 {
                        let slide = (heights[k] - heights[n] - 2) / 2 + 0.01
                        heights[k] -= slide
                        heights[n] += slide
                        moved = true
                    }
                }
                if !moved { break }
            }
        }
    }

    /// The tallest the bottom pile grows, in art pixels, and a window top's (half as tall: it is a narrow ledge).
    public static func bottomCap(_ depth: Level) -> Double { 8 * depth.factor }
    public static func windowCap(_ depth: Level) -> Double { 4 * depth.factor }
    /// Art pixels of snow a second, at full intensity, on top of what the flakes bring.
    public static func snowfall(_ depth: Level) -> Double { 0.05 * depth.factor }
    /// Art pixels melting a second once the snow has stopped: slowly.
    public static let meltRate = 0.03
    /// A creature in snow this deep (a share of the cap) walks this much slower: at most half its pace.
    public static func wading(depth: Double, cap: Double) -> Double {
        guard cap > 0 else { return 1 }
        return 1 - 0.5 * Swift.min(1, Swift.max(0, depth / cap))
    }

    // MARK: Umbrellas

    /// A creature where the rain can fall on it: which edge it stands on (creatures on different edges never
    /// share) and where along it, in points.
    public struct Standing: Equatable, Sendable {
        public var index: Int
        public var edge: Int
        public var along: Double
        public init(index: Int, edge: Int, along: Double) {
            self.index = index
            self.edge = edge
            self.along = along
        }
    }

    /// The most under one umbrella.
    public static let mostUnderOne = 3

    /// Who shares an umbrella: creatures on the same edge each within `distance` of the next, at most three to
    /// one; everyone else has its own. Each group is in order along its edge; the one in the middle holds it.
    public static func umbrellaGroups(_ standing: [Standing], distance: Double) -> [[Int]] {
        var groups: [[Int]] = []
        for edge in Set(standing.map(\.edge)).sorted() {
            let row = standing.filter { $0.edge == edge }.sorted { ($0.along, $0.index) < ($1.along, $1.index) }
            var current: [Standing] = []
            for s in row {
                if let last = current.last, distance > 0, s.along - last.along <= distance, current.count < mostUnderOne {
                    current.append(s)
                } else {
                    if !current.isEmpty { groups.append(current.map(\.index)) }
                    current = [s]
                }
            }
            if !current.isEmpty { groups.append(current.map(\.index)) }
        }
        return groups
    }
    /// The one holding a group's umbrella: the middle one.
    public static func holder(of group: [Int]) -> Int { group[group.count / 2] }
    /// An umbrella's canopy for `count` creatures under it, in the creatures' own pixels: a little wider than one
    /// body (22 pixels), and a body wider for each one more.
    public static func umbrellaWidth(for count: Int) -> Int { 27 + 22 * Swift.max(0, count - 1) }

    /// The umbrella of a creature hanging from the top edge: upside down, it is a bowl, and the rain fills it.
    public struct Bowl: Equatable, Sendable {
        public enum State: Equatable, Sendable { case holding, tipping(Double), fallen }
        public private(set) var water = 0.0
        public private(set) var state: State = .holding
        public init() {}
        /// Seconds of medium rain to fill it.
        public static let fillSeconds = 20.0
        /// Seconds it takes to tip over once full.
        public static let tipSeconds = 1.2

        public enum Event: Equatable, Sendable { case full, spills }

        /// Rain at `intensity` (0...1) with `heaviness`: it fills; full, it tips; tipped, it spills and falls.
        public mutating func update(_ dt: Double, intensity: Double, heaviness: Level) -> Event? {
            switch state {
            case .holding:
                water = Swift.min(1, water + dt * intensity * heaviness.factor / Self.fillSeconds)
                if water >= 1 { state = .tipping(0); return .full }
            case .tipping(let t):
                let n = t + dt
                if n >= Self.tipSeconds { state = .fallen; water = 0; return .spills }
                state = .tipping(n)
            case .fallen: break
            }
            return nil
        }
        /// How far it has tipped, 0...1.
        public var tip: Double {
            switch state {
            case .holding: 0
            case .tipping(let t): Swift.min(1, t / Self.tipSeconds)
            case .fallen: 1
            }
        }
    }

    /// Seconds a puddle takes to dry once the rain has stopped, at its deepest.
    public static let drySeconds = 90.0

    // MARK: Wind

    /// The wind of one spell: from the left (+1, blowing rightwards) or the right (-1), with gusts.
    public struct Wind: Equatable, Sendable {
        public let from: Double
        public let strength: Level
        /// Seconds between gusts, and how long one lasts.
        public static let gustEvery = 9.0, gustLasts = 2.5
        public init(fromLeft: Bool, strength: Level) {
            from = fromLeft ? 1 : -1
            self.strength = strength
        }
        /// How hard it blows at `time` seconds into the spell, 0...1: a steady breeze and a gust every so often.
        public func force(at time: Double) -> Double {
            let phase = time.truncatingRemainder(dividingBy: Self.gustEvery)
            let gust = phase < Self.gustLasts ? sin(.pi * phase / Self.gustLasts) : 0
            return 0.3 + 0.7 * gust * gust
        }
        /// A gust at its peak now (a strong gust pushes): within a quarter second of the middle of one.
        public func peaks(at time: Double, dt: Double) -> Bool {
            let mid = Self.gustLasts / 2
            let a = (time - dt).truncatingRemainder(dividingBy: Self.gustEvery), b = time.truncatingRemainder(dividingBy: Self.gustEvery)
            return a < mid && b >= mid
        }
        /// Sideways speed it gives the particles, in art pixels a second.
        public func drift(at time: Double, intensity: Double) -> Double { from * force(at: time) * 70 * strength.factor * intensity }
        /// How far the creatures lean into it, in radians.
        public func lean(at time: Double, intensity: Double) -> Double { -from * force(at: time) * 0.18 * strength.factor * intensity }
    }

    /// Times its pace a creature walks: slower into the wind, faster with it. `walking` is +1 rightwards.
    public static func windPace(walking: Double, wind: Wind, force: Double) -> Double {
        let f = force * wind.strength.factor
        return walking * wind.from > 0 ? 1 + 0.3 * f : 1 - 0.4 * Swift.min(1, f)
    }

    /// Points a gust at `force` pushes a creature of `size` (1 is an ordinary one) along the wind: the light
    /// ones a few points, the heavy ones hardly at all.
    public static func push(size: Double, force: Double, strength: Level) -> Double {
        guard size > 0 else { return 0 }
        let p = 6 * force * strength.factor / (size * size)
        return p < 0.75 ? 0 : p.rounded()
    }

    /// A gust this strong blows a creature of `size` off the top edge: a light one, in a strong wind.
    public static func blowsOff(size: Double, force: Double, strength: Level) -> Bool {
        force * strength.factor / size >= 1.25
    }

    /// Whether a gust turns an umbrella inside out: rain and wind together, a strong enough gust, and `roll`.
    public static func turnsInsideOut(force: Double, strength: Level, roll: Double) -> Bool {
        force * strength.factor >= 0.9 && roll < 0.4
    }
}

// MARK: Words

extension Weather {
    /// The kinds of line, as the tables name them.
    public static let lineKinds = ["snow", "cold", "snowman", "throw", "hit", "rain", "share", "soaked", "wind", "insideOut", "blown"]

    /// The line `name` says for `kind`; `friend` fills a snowball's or a shared umbrella's `{friend}`.
    public static func line(by name: String, _ kind: String, friend: String = "", using rng: inout some RandomNumberGenerator) -> String {
        let pool = lineSets()[name]?[kind] ?? anyoneSets()[kind] ?? []
        let line = pool.randomElement(using: &rng) ?? ""
        return CursorMood.current.adjust(line.replacingOccurrences(of: "{friend}", with: friend))
    }

    public static let lineSets = Translated(english: englishLines, [.russian: russianLines])
    public static let anyoneSets = Translated(english: englishAnyone, [.russian: russianAnyone])
}

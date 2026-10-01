import CoreGraphics
import Foundation

/// Flowers planted in the screen edge, and how each character decides where and
/// when to plant the one it was given.
///
/// A creature wearing a flower keeps it on its head for a while, then plants it
/// the first time it passes a spot it likes. What it likes is read from its
/// persona and its species' kind, the way `Casting` reads them for a voice:
/// Blocky ("the bottom edge is the only respectable edge") plants on the floor,
/// Pip ("loves the ceiling") on the top edge, Ruth ("keeps count") beside the
/// flowers already there, Dot ("fast") at once, Zed ("sleepy") at nightfall.
/// Rules, not understanding: a persona in words the rules do not know plants
/// wherever it is once it has worn the flower a little while.
public struct Garden: Sendable {
    /// A kind of spot a character can prefer.
    public enum Place: String, CaseIterable, Sendable {
        /// The bottom edge of a screen.
        case floor
        /// The top edge.
        case ceiling
        /// A left or right edge.
        case wall
        /// Close to where the edge turns.
        case corner
        /// Nobody else near.
        case alone
        /// Someone else close by.
        case company
        /// Next to a flower already planted, in a row.
        case row
        /// After dark.
        case night
        /// In daylight.
        case day

        /// Where, in words: "on the bottom edge".
        public var phrase: String {
            switch self {
            case .floor: "on the bottom edge"
            case .ceiling: "on the top edge"
            case .wall: "on a side edge"
            case .corner: "in a corner"
            case .alone: "where nobody is"
            case .company: "next to someone"
            case .row: "beside the flowers already planted"
            case .night: "after dark"
            case .day: "in daylight"
            }
        }
    }

    /// How one character goes about it: how much of the flower's time it wears
    /// it before thinking of planting, and the places it likes, best first.
    public struct Temper: Equatable, Sendable {
        public var keep: Double
        public var likes: [Place]
        public init(keep: Double, likes: [Place]) { self.keep = keep; self.likes = likes }
    }

    /// What is around a creature right now, for `Temper.fits`.
    public struct Surroundings: Sendable {
        /// Away from its edge, into the screen.
        public var inward: CGVector
        /// Points along the edge to the nearest turn.
        public var toCorner: CGFloat
        /// Points to the nearest other creature; infinity when alone on screen.
        public var toCreature: CGFloat
        /// Points to the nearest planted flower; infinity when none is planted.
        public var toFlower: CGFloat
        public var isNight: Bool
        public init(inward: CGVector, toCorner: CGFloat, toCreature: CGFloat, toFlower: CGFloat, isNight: Bool) {
            self.inward = inward; self.toCorner = toCorner; self.toCreature = toCreature
            self.toFlower = toFlower; self.isNight = isNight
        }
    }

    /// One flower in the ground.
    public struct Bed: Equatable, Sendable {
        public var flower: String
        /// The middle of its stem's foot, on the screen edge.
        public var floor: CGPoint
        /// The edge's turn, as a creature standing there has it.
        public var rotation: Double
        /// Screen points per sprite pixel: the planter's size.
        public var scale: Double
        /// Who planted it.
        public var planter: String
        public var planted: Double
        public var until: Double
    }

    /// Distances behind the places, in points.
    public static let cornerReach: CGFloat = 60
    public static let aloneBeyond: CGFloat = 320
    public static let companyWithin: CGFloat = 160
    public static let rowWithin: CGFloat = 90
    /// No flower goes closer than this to another, in sprite pixels times the size,
    /// so a row does not end up as one flower drawn on another.
    public static let spacing: CGFloat = 12
    /// Past this share of the flower's time on the head, any spot will do: it is
    /// planted wherever the wearer stands rather than left to wilt.
    public static let lastChance = 0.9
    /// Seconds a flower takes to come up out of the ground.
    public static let growTime = 0.5

    public private(set) var beds: [Bed] = []
    public init() {}

    // MARK: Character

    /// One rule: any of these word starts in the text, and the character likes this place.
    /// `strong` rules name a place outright ("bottom edge", "ceiling"); the rest are
    /// temperament (grumpy, cheerful). Named places come first.
    struct Rule {
        let words: [String]
        let place: Place
        var strong = false
    }

    static let rules: [Rule] = [
        Rule(words: ["bottom", "floor", "ground"], place: .floor, strong: true),
        Rule(words: ["ceiling", "top", "sky", "high"], place: .ceiling, strong: true),
        Rule(words: ["wall", "climb", "cling", "sideways"], place: .wall, strong: true),
        Rule(words: ["corner", "nook"], place: .corner, strong: true),
        Rule(words: ["garden", "row", "neat", "tidy"], place: .row, strong: true),
        Rule(words: ["night", "dark", "moon"], place: .night, strong: true),
        Rule(words: ["sun", "warm", "light", "daylight"], place: .day, strong: true),
        Rule(words: ["damp", "pond", "earth", "moss", "puddle", "dirt", "mud"], place: .floor),
        Rule(words: ["hover", "float", "fly", "cloud", "ghost"], place: .ceiling),
        Rule(words: ["stable", "stubborn", "precise", "literal", "anxi", "worr", "scared", "afraid", "stepped",
                     "sharp", "point"], place: .corner),
        Rule(words: ["aloof", "quiet", "shy", "deadpan", "grump", "gruff", "lonel", "wistful", "hates", "suspect"],
             place: .alone),
        Rule(words: ["cheer", "friend", "social", "gigg", "laugh", "playful", "sweet", "simple", "pleased", "loud"],
             place: .company),
        Rule(words: ["count", "organis", "organiz", "boss", "maintenance", "bolt", "differen", "change", "notice"],
             place: .row),
        Rule(words: ["sleep", "nap", "drows", "yawn", "bed", "scary", "spook", "haunt"], place: .night),
    ]

    /// Wears it a moment and plants it.
    static let hasty = ["fast", "quick", "hyper", "rush", "speed", "bounc", "excit", "enthus", "impatien"]
    /// Wants to wear it a good while first.
    static let fond = ["sweet", "ador", "wistful", "poet", "dream", "sentiment", "romantic", "proud"]
    /// Takes its time over everything.
    static let slow = ["slow", "patien", "calm", "old", "wise", "philosoph", "sleep"]

    /// How the character with this persona, of this kind, plants its flowers.
    public static func temper(persona: String, kind: String) -> Temper {
        let own = Casting.words(persona), theirs = Casting.words(kind)
        func first(_ stems: [String], in words: [String]) -> Int? {
            words.firstIndex { word in stems.contains { word.hasPrefix($0) } }
        }
        // Persona words outrank the species' kind; a named place outranks a temperament;
        // otherwise whichever the text says first.
        var ranked: [(place: Place, rank: Int)] = []
        for rule in rules {
            let rank: Int
            if let at = first(rule.words, in: own) { rank = (rule.strong ? 0 : 1_000) + at }
            else if let at = first(rule.words, in: theirs) { rank = (rule.strong ? 2_000 : 3_000) + at }
            else { continue }
            if let known = ranked.firstIndex(where: { $0.place == rule.place }) {
                ranked[known].rank = min(ranked[known].rank, rank)
            } else {
                ranked.append((rule.place, rank))
            }
        }
        let likes = ranked.sorted { $0.rank < $1.rank }.map(\.place)
        let keep: Double = first(hasty, in: own) != nil ? 0.05
            : first(fond, in: own) != nil ? 0.6
            : first(slow, in: own) != nil ? 0.45
            : 0.25
        return Temper(keep: keep, likes: Array(likes.prefix(3)))
    }

    /// The temper in a sentence, for the settings window: "After a good while, on the bottom edge or where nobody is."
    public static func describe(_ temper: Temper) -> String {
        let when = temper.keep < 0.1 ? "At once" : temper.keep < 0.3 ? "After a little while"
            : temper.keep < 0.5 ? "After a good while" : "After showing it off for most of its time"
        let places = temper.likes.map(\.phrase)
        guard !places.isEmpty else { return when + ", wherever it is." }
        let listed = places.count == 1 ? places[0]
            : places.dropLast().joined(separator: ", ") + " or " + places.last!
        return when + ", " + listed + "."
    }

    // MARK: Deciding

    /// Whether a character of this temper plants now: `share` is how far through
    /// its time on the head the flower is. Before `keep` it is still wearing it.
    /// For the first half of the time left until `lastChance` only its favourite
    /// place will do, after that any place it likes, and at the last chance anywhere.
    public static func wantsToPlant(_ temper: Temper, share: Double, around: Surroundings) -> Bool {
        guard share >= temper.keep else { return false }
        if share >= lastChance || temper.likes.isEmpty { return true }
        let picky = share < temper.keep + (lastChance - temper.keep) / 2
        let choices = picky ? Array(temper.likes.prefix(1)) : temper.likes
        return choices.contains { fits($0, around) }
    }

    public static func fits(_ place: Place, _ around: Surroundings) -> Bool {
        switch place {
        case .floor: around.inward.dy > 0.5
        case .ceiling: around.inward.dy < -0.5
        case .wall: abs(around.inward.dx) > 0.5
        case .corner: around.toCorner <= cornerReach
        case .alone: around.toCreature >= aloneBeyond
        case .company: around.toCreature <= companyWithin
        case .row: around.toFlower <= rowWithin
        case .night: around.isNight
        case .day: !around.isNight
        }
    }

    // MARK: The beds

    /// Whether there is room for a flower of this size at `floor`.
    public func hasRoom(at floor: CGPoint, scale: Double) -> Bool {
        distance(to: floor) >= Self.spacing * CGFloat(scale)
    }

    /// Points from `point` to the nearest planted flower; infinity with none planted.
    public func distance(to point: CGPoint) -> CGFloat {
        beds.map { hypot($0.floor.x - point.x, $0.floor.y - point.y) }.min() ?? .infinity
    }

    /// Plant a flower that stays `lasts` seconds. With `most` already in the
    /// ground, the oldest wilts to make room.
    public mutating func plant(_ flower: String, at floor: CGPoint, rotation: Double, scale: Double,
                               by planter: String, at time: Double, lasts: Double, most: Int) {
        beds.append(Bed(flower: flower, floor: floor, rotation: rotation, scale: scale, planter: planter,
                        planted: time, until: time + lasts))
        if beds.count > max(most, 0) { beds.removeFirst(beds.count - max(most, 0)) }
    }

    /// 0 as it is planted, 1 once it is fully up.
    public static func grown(_ bed: Bed, at time: Double) -> Double {
        min(1, max(0, (time - bed.planted) / growTime))
    }

    /// Wilt every flower past its time, and the oldest beyond `most`.
    public mutating func update(at time: Double, most: Int) {
        beds.removeAll { $0.until <= time }
        if beds.count > max(most, 0) { beds.removeFirst(beds.count - max(most, 0)) }
    }

    /// Keep only the flowers `keep` approves of (the monitors changed).
    public mutating func keep(where keep: (Bed) -> Bool) { beds = beds.filter(keep) }

    public mutating func clear() { beds.removeAll() }
}

import CoreGraphics
import Foundation

/// Every character's own little bed, and the place it likes to sleep.
///
/// When a creature nods off for the night it puts its bed down and sleeps on it.
/// Each character remembers one favourite place, kept by name in `beds.json`:
/// the first night it walks to a place its character likes (the bottom edge for
/// Blocky, the ceiling for Pip, as `Garden.temper` reads them), and each night
/// after that it is a little likelier to walk back there (`pull`). A night spent
/// somewhere else wears the habit down, and enough of them move it. A bed the
/// user drags somewhere while its owner sleeps makes that place the favourite.
public enum Beds {
    /// Which bed, by the name of its picture in the `beds` sheet.
    public enum Kind: String, CaseIterable, Codable, Sendable {
        case crate, hammock, quilt, pillow, matchbox, bed, box, catbed, cushion, lilypad, moss, puddle,
             cloud, leaf, blanket, log, grass, flowerpot, dock, toolbox, spacebar, sponge, teacup,
             bubblewrap, pincushion, books, sock

        /// Sheet pixels above the floor the sleeper's feet rest on: the top of the
        /// mattress. Kept in step with `LIFT` in `spritetool/painters/beds.py`.
        public var lift: Int {
            switch self {
            case .puddle: 2
            case .box, .grass: 3
            case .lilypad, .leaf, .dock: 4
            case .quilt, .matchbox, .moss: 5
            case .crate, .bed, .catbed, .cushion, .cloud, .blanket, .log, .bubblewrap, .sock: 6
            case .pillow, .toolbox, .sponge, .pincushion: 7
            case .hammock, .spacebar, .books: 8
            case .teacup: 9
            case .flowerpot: 10
            }
        }

        /// What it is, in words: "a cat basket".
        public var title: String {
            switch self {
            case .crate: tr("a wooden crate full of straw")
            case .hammock: tr("a striped hammock")
            case .quilt: tr("a patchwork quilt")
            case .pillow: tr("an enormous fluffy pillow")
            case .matchbox: tr("a matchbox")
            case .bed: tr("a neatly made little bed")
            case .box: tr("a cardboard box")
            case .catbed: tr("a round cat basket")
            case .cushion: tr("a royal red cushion")
            case .lilypad: tr("a lily pad")
            case .moss: tr("a mound of soft moss")
            case .puddle: tr("a puddle")
            case .cloud: tr("a little cloud")
            case .leaf: tr("a big autumn leaf")
            case .blanket: tr("a folded check blanket")
            case .log: tr("a slice of old log")
            case .grass: tr("a tuft of grass")
            case .flowerpot: tr("a flowerpot of good soil")
            case .dock: tr("a charging dock")
            case .toolbox: tr("a toolbox")
            case .spacebar: tr("a spacebar keycap")
            case .sponge: tr("a kitchen sponge")
            case .teacup: tr("a teacup on its saucer")
            case .bubblewrap: tr("a sheet of bubble wrap")
            case .pincushion: tr("a pincushion")
            case .books: tr("a stack of books")
            case .sock: tr("a striped sock")
            }
        }
    }

    /// The built-in characters' beds, chosen for each one's persona and kind.
    public static let builtIn: [String: Kind] = [
        // blocky's cast
        "Blocky": .crate, "Pip": .hammock, "Mortimer": .quilt, "Zed": .pillow, "Dot": .matchbox, "Ruth": .bed,
        // cat
        "Whiskers": .box, "Mittens": .catbed, "Sir Pounce": .cushion,
        // frog
        "Hopper": .lilypad, "Mossy": .moss, "Croak": .puddle,
        // ghost
        "Boo": .cloud, "Wisp": .leaf, "Sheet": .blanket,
        // mushroom
        "Morel": .log, "Puff": .grass, "Cap": .flowerpot,
        // robot
        "Unit 7": .dock, "Sprocket": .toolbox, "Glitch": .spacebar,
        // slime
        "Goop": .sponge, "Puddle": .teacup, "Blorp": .bubblewrap,
        // triangle
        "Spike": .pincushion, "Wedge": .books, "Delta": .sock,
    ]

    /// For a character nobody wrote a bed for: word starts in its persona, then
    /// its species' kind, the way `Casting` and `Garden` read them.
    static let rules: [(words: [String], kind: Kind)] = [
        (["cat", "kitten", "purr", "whisker"], .catbed),
        (["frog", "toad", "pond", "lily"], .lilypad),
        (["ghost", "spook", "haunt", "float", "hover", "cloud"], .cloud),
        (["mushroom", "fung", "moss", "damp", "earth"], .moss),
        (["robot", "machine", "android", "metal", "antenna", "bolt"], .dock),
        (["slime", "blob", "goo", "sticky", "wobbl"], .sponge),
        (["sleep", "nap", "drows", "yawn", "tired"], .pillow),
        (["old", "wise", "philosoph"], .quilt),
        (["tiny", "small", "little"], .matchbox),
        (["boss", "tidy", "neat", "organis", "organiz"], .bed),
    ]

    /// Whose bed is which: the built-in choice by name, else read from the words;
    /// a tuft of grass when nothing fits.
    public static func kind(name: String, persona: String, kind: String) -> Kind {
        if let known = builtIn[name] { return known }
        for text in [persona, kind] {
            let words = Casting.words(text)
            if let rule = rules.first(where: { rule in words.contains { word in rule.words.contains { word.hasPrefix($0) } } }) {
                return rule.kind
            }
        }
        return .grass
    }

    // MARK: The favourite place

    /// Where a character likes to sleep: a creature's centre on its edge, in
    /// global screen points, and how many nights the habit has behind it.
    public struct Spot: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var nights: Int
        public init(x: Double, y: Double, nights: Int) { self.x = x; self.y = y; self.nights = nights }
        public init(_ point: CGPoint, nights: Int) { self.init(x: point.x, y: point.y, nights: nights) }
        public var point: CGPoint { CGPoint(x: x, y: y) }
    }

    /// A habit stops growing here, so a few nights elsewhere can still move it.
    public static let mostNights = 12
    /// Dragged there by the user: the habit is at least this strong at once.
    public static let movedNights = 3
    /// Points: asleep this close to the favourite counts as asleep there.
    public static let near: CGFloat = 48

    /// The chance it walks back to its favourite at nightfall, after `nights`
    /// there: half a pull the first time, then most of it, then nearly all.
    public static func pull(nights: Int, strength: Double) -> Double {
        guard nights > 0 else { return 0 }
        return max(0, min(1, strength)) * (1 - pow(0.5, Double(nights)))
    }

    /// Every character's favourite place, by name.
    public struct Book: Codable, Equatable, Sendable {
        public var spots: [String: Spot] = [:]
        public init() {}

        /// `name` slept the night at `point`: there (within `near`), the habit
        /// grows; elsewhere it wears down, and once worn out this is the new
        /// favourite. The first night anywhere makes it the favourite.
        public mutating func slept(_ name: String, at point: CGPoint) {
            guard var spot = spots[name] else { spots[name] = Spot(point, nights: 1); return }
            if hypot(spot.x - point.x, spot.y - point.y) <= Beds.near {
                spot = Spot(point, nights: min(spot.nights + 1, Beds.mostNights))
            } else {
                spot.nights -= 1
                if spot.nights <= 0 { spot = Spot(point, nights: 1) }
            }
            spots[name] = spot
        }

        /// The user put `name`'s bed down at `point`: the favourite from now on.
        public mutating func moved(_ name: String, to point: CGPoint) {
            spots[name] = Spot(point, nights: max(spots[name]?.nights ?? 0, Beds.movedNights))
        }

        /// Forget one character's place, or everyone's.
        public mutating func forget(_ name: String? = nil) {
            if let name { spots[name] = nil } else { spots = [:] }
        }
    }

    /// `beds.json` beside the chats and the hunts.
    public struct Store: Sendable {
        public let directory: URL
        public init(directory: URL) { self.directory = directory }
        public var file: URL { directory.appendingPathComponent("beds.json") }

        public func load() -> Book {
            guard let data = try? Data(contentsOf: file) else { return Book() }
            return (try? JSONDecoder().decode(Book.self, from: data)) ?? Book()
        }

        public func save(_ book: Book) throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(book).write(to: file, options: .atomic)
        }
    }

    /// Where `point` is, in words, on these screens: "on the bottom edge", with
    /// the screen's number when there is more than one.
    public static func place(of point: CGPoint, screens: [CGRect]) -> String {
        guard !screens.isEmpty else { return "" }
        let world = EdgeWorld(screens: screens, inset: 0), spot = world.nearest(to: point)
        let loop = world.loops[spot.loop], inward = loop.inward(ofSegment: loop.segment(at: spot.t))
        let edge = inward.dy > 0.5 ? tr("on the bottom edge") : inward.dy < -0.5 ? tr("on the ceiling")
            : inward.dx > 0.5 ? tr("on the left edge") : tr("on the right edge")
        guard screens.count > 1 else { return edge }
        let screen = screens.indices.min { distance(point, screens[$0]) < distance(point, screens[$1]) }!
        return tr("%@ of screen %d", edge, screen + 1)
    }

    private static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }

    // MARK: Words

    /// A built-in line as it lays its bed down for the night, in its own voice.
    public static func settleLine(by name: String, bed: Kind, using rng: inout some RandomNumberGenerator) -> String {
        let pool = settleSets()[name] ?? settleAnyone()
        return Banter.render(pool.randomElement(using: &rng)!, ["bed": bed.title])
    }

    /// A built-in line, half asleep, when the user has just moved its bed.
    public static func movedLine(by name: String, bed: Kind, using rng: inout some RandomNumberGenerator) -> String {
        let pool = movedSets()[name] ?? movedAnyone()
        return Banter.render(pool.randomElement(using: &rng)!, ["bed": bed.title])
    }

    public static let settleSets = Translated(english: englishSettleLines, [.russian: russianSettleLines])
    public static let settleAnyone = Translated(english: englishSettleAnyone, [.russian: russianSettleAnyone])
    public static let movedSets = Translated(english: englishMovedLines, [.russian: russianMovedLines])
    public static let movedAnyone = Translated(english: englishMovedAnyone, [.russian: russianMovedAnyone])
}

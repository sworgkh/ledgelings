import Foundation

/// The creature who brings the clipboard picker: on the shortcut it leaps from
/// its edge to the paper's top-left corner, the sheet unfolds out of it, and it
/// holds that corner while the picker is open. Once something is chosen the
/// sheet collapses into the text cursor (or into the creature, when the cursor
/// is not known), and the creature leaps back to where it was.
///
/// Pure geometry and choice, so both apps leap the same way: who comes, where it
/// perches, how long the leap takes and where it is along the way.
public enum ClipHelper {
    /// A quick jump along an arc, after a short crouch.
    public struct Leap: Equatable, Sendable {
        /// Seconds it crouches before it springs: short, the picker is waiting.
        public static let crouch = 0.06

        public let from: CGPoint
        public let to: CGPoint
        /// Seconds in the air, crouch not counted.
        public let flight: Double
        /// How far the arc rises over the higher of its two ends.
        public let rise: CGFloat
        public private(set) var clock = 0.0

        public init(from: CGPoint, to: CGPoint, flight: Double) {
            self.from = from
            self.to = to
            self.flight = max(flight, 0.01)
            let distance = hypot(to.x - from.x, to.y - from.y)
            rise = min(max(distance * 0.2, 24), 160)
        }

        /// Crouch and flight together.
        public var duration: Double { Self.crouch + flight }
        public var isDone: Bool { clock >= duration }

        public mutating func update(dt: Double) { clock = min(clock + dt, duration) }

        /// Its share of the flight, 0 to 1.
        public var share: Double { min(max((clock - Self.crouch) / flight, 0), 1) }

        /// Straight between the ends, plus an arc that peaks halfway, `rise` over the higher end.
        public var position: CGPoint {
            let s = CGFloat(share)
            let x = from.x + (to.x - from.x) * s, y = from.y + (to.y - from.y) * s
            let top = max(from.y, to.y) + rise - (from.y + (to.y - from.y) * 0.5)
            return CGPoint(x: x, y: y + 4 * top * s * (1 - s))
        }

        /// Crouched, in the air, landed.
        public var pose: String { clock < Self.crouch ? "land" : isDone ? "idle" : "jump" }

        /// A flip on the way, the way it travels.
        public var rotation: Double {
            let way: Double = to.x >= from.x ? -1 : 1
            // Upright again once landed: a whole turn is no turn.
            return (way * 2 * .pi * share).truncatingRemainder(dividingBy: 2 * .pi)
        }
    }

    /// Seconds the sheet takes to unfold out of the creature, and to collapse, at speed 1.
    public static let unfoldSeconds = 0.14
    public static let collapseSeconds = 0.18

    /// Seconds in the air for a leap of `distance` points: about a quarter of a second
    /// across a laptop screen, never more than 0.4, divided by `speed`.
    public static func flight(distance: CGFloat, speed: Double) -> Double {
        min(max(0.14 + Double(distance) / 6000, 0.14), 0.4) / max(speed, 0.1)
    }

    /// One creature as the choice sees it.
    public struct Candidate: Equatable, Sendable {
        public var name: String
        public var position: CGPoint
        public var asleep: Bool
        /// Free: not busy with a game, a talk, a move, the hand or the house.
        public var free: Bool
        public init(name: String, position: CGPoint, asleep: Bool, free: Bool) {
            self.name = name; self.position = position; self.asleep = asleep; self.free = free
        }
    }

    /// Who comes: the one named `wanted` when it is free, else the free creature
    /// nearest `centre`, an awake one before a sleeper. Nil when nobody is free.
    public static func choose(_ candidates: [Candidate], centre: CGPoint, wanted: String) -> Int? {
        let free = candidates.indices.filter { candidates[$0].free }
        if !wanted.isEmpty, let named = free.first(where: { candidates[$0].name == wanted }) { return named }
        return free.min { a, b in
            let ca = candidates[a], cb = candidates[b]
            if ca.asleep != cb.asleep { return !ca.asleep }
            return hypot(ca.position.x - centre.x, ca.position.y - centre.y) < hypot(cb.position.x - centre.x, cb.position.y - centre.y)
        }
    }

    /// Where its centre goes to hold the paper by its top-left corner: its body over
    /// the corner, a little out and up, so the corner sits in its grip.
    public static func perch(paper: CGRect, half: CGFloat) -> CGPoint {
        CGPoint(x: paper.minX - half * 0.25, y: paper.maxY + half * 0.45)
    }

    // MARK: Lines

    /// What it says as the sheet unfolds, in its own voice: one short line each.
    public static let lineSets = Translated(english: englishLines, [.russian: russianLines])
    public static let anyoneLines = Translated(english: englishAnyone, [.russian: russianAnyone])

    public static func line(by name: String, using rng: inout some RandomNumberGenerator) -> String {
        (lineSets()[name] ?? anyoneLines()).randomElement(using: &rng) ?? ""
    }

    public static let englishAnyone = ["Here. Pick one.", "Got it right here."]

    public static let englishLines: [String: [String]] = [
        "Blocky": ["Fine. Pick one.", "Hold still, cursor."],
        "Pip": ["Ooh, which one?!", "Pick pick pick!"],
        "Mortimer": ["Choose wisely, youngster.", "Ah, the old papers."],
        "Zed": ["*yawn* ...pick one.", "Mm. Here. Sleepy."],
        "Dot": ["Already here. Go.", "Fastest paper ever."],
        "Ruth": ["Sorted, newest first.", "All counted. Pick."],
        "Whiskers": ["Not that I care. Pick.", "Hm. This one?"],
        "Mittens": ["Purr... warm papers.", "Mrrp. Pick a nice one."],
        "Sir Pounce": ["The hunt for words!", "Pounce on one!"],
        "Hopper": ["Longest jump ever!", "Boing! Got it!"],
        "Mossy": ["Still ponds keep all.", "Slowly. Pick one."],
        "Croak": ["Dry papers. Hurry.", "Grumble. Pick."],
        "Boo": ["BOO! ...pick one.", "Spooky papers!"],
        "Wisp": ["Words that drifted here.", "Old copies, like old monitors."],
        "Sheet": ["Technically, I'm floating.", "Paper on paper."],
        "Morel": ["Slowly... pick.", "Damp and quiet. Choose."],
        "Puff": ["Hee! Spores! Kidding. Pick.", "Ooh, so many!"],
        "Cap": ["In my day we wrote it down.", "In my day: carbon paper."],
        "Unit 7": ["Picker online. 100%.", "Items loaded. Select 1."],
        "Sprocket": ["Freshly oiled papers!", "All tightened. Pick."],
        "Glitch": ["Pick pick one.", "No viruses. Probably."],
        "Goop": ["Nice papers!", "Sticky! Pick one."],
        "Puddle": ["Careful, don't spill.", "Quick, before I dry."],
        "Blorp": ["Blorp! Papers!", "Shloop. Pick."],
        "Spike": ["Point at one.", "Sharp choice, please."],
        "Wedge": ["Steady. Pick.", "Not tipping. Choose."],
        "Delta": ["New since last time.", "Something changed. Pick."],
    ]
}

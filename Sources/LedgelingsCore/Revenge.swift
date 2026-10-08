import Foundation

/// Revenge: chase a creature with the cursor, or pick it up, too often in a short
/// time and it jumps on the cursor and hangs on to it, telling the user what it
/// thinks of them, until the user shakes it off. What it says follows the cursor
/// mood: a real telling-off in the bad mood, a gleeful turn of the game in the
/// good one, a deadpan remark in the neutral.
///
/// The pieces here are the ones with no screen in them: when it is due (`Fuse`),
/// when the cursor has been shaken hard enough (`Shake`), and the words.
public enum Revenge {

    /// Counts each creature's hunts over the last `window` seconds. The `after`th
    /// inside the window makes revenge due, unless the last grab was less than
    /// `cooldown` seconds ago. Times are the colony's clock.
    public struct Fuse: Sendable {
        public var after: Int
        public var window: Double
        public var cooldown: Double
        private var times: [Int: [Double]] = [:]
        /// When a creature last grabbed the cursor; nobody grabs again for `cooldown`.
        public private(set) var lastGrab = -Double.infinity

        public init(after: Int = 10, window: Double = 120, cooldown: Double = 600) {
            self.after = after
            self.window = window
            self.cooldown = cooldown
        }

        /// Creature `index` was chased or picked up at `time`. True when it has had enough and may grab.
        public mutating func hunted(_ index: Int, at time: Double) -> Bool {
            var list = (times[index] ?? []).filter { time - $0 <= window }
            list.append(time)
            times[index] = list
            return list.count >= after && time - lastGrab >= cooldown
        }

        /// Hunts of `index` inside the window, as of `time`.
        public func recent(_ index: Int, at time: Double) -> Int {
            (times[index] ?? []).filter { time - $0 <= window }.count
        }

        /// A creature grabbed the cursor at `time`: every count starts over, and the cooldown runs.
        public mutating func grabbed(at time: Double) {
            lastGrab = time
            times = [:]
        }

        /// Creatures from `count` on are gone.
        public mutating func forget(creaturesFrom count: Int) { times = times.filter { $0.key < count } }
    }

    /// Whether the user is shaking the cursor: strokes back and forth.
    /// A stroke counts once it has travelled `stroke` points one way; turning back
    /// after one is a reversal. `needed` reversals within `window` seconds, on either
    /// axis, shake the creature off. Slow drifting and small jitters never add up.
    public struct Shake: Sendable {
        public var needed: Int
        public var stroke: Double
        public var window: Double
        private struct Axis: Sendable { var sign = 0.0, travel = 0.0 }
        private var axes = [Axis(), Axis()]
        private var reversals: [Double] = []

        public init(needed: Int = 4, stroke: Double = 20, window: Double = 2) {
            self.needed = needed
            self.stroke = stroke
            self.window = window
        }

        /// The cursor tried to move by `dx`, `dy` points at `time`. True once it is shaken off.
        public mutating func moved(dx: Double, dy: Double, at time: Double) -> Bool {
            for (axis, d) in [(0, dx), (1, dy)] where d != 0 {
                let sign: Double = d > 0 ? 1 : -1
                if sign == axes[axis].sign {
                    axes[axis].travel += abs(d)
                } else {
                    if axes[axis].sign != 0, axes[axis].travel >= stroke { reversals.append(time) }
                    axes[axis] = Axis(sign: sign, travel: abs(d))
                }
            }
            reversals.removeAll { time - $0 > window }
            return reversals.count >= needed
        }

        /// How close to shaken off, 0...1, as of `time`: how hard the creature wobbles.
        public func vigour(at time: Double) -> Double {
            guard needed > 0 else { return 1 }
            return min(1, Double(reversals.filter { time - $0 <= window }.count) / Double(needed))
        }
    }

    /// Holding the pointer still with no limit set, a creature still lets go after this many seconds.
    public static let pinnedHoldCap = 10.0

    /// How long a grab may last: `limit` seconds, 0 for until shaken off; never past
    /// `pinnedHoldCap` when the pointer is held still.
    public static func longestHold(limit: Double, pinned: Bool) -> Double {
        let limit = limit > 0 ? limit : .infinity
        return pinned ? min(limit, pinnedHoldCap) : limit
    }

    /// Why a creature let go of the cursor.
    public enum Release: String, Sendable {
        /// Shaken off: it tumbles down and has a last word.
        case shaken
        /// Held as long as it may: it drops, done with the lesson.
        case tired
        /// The Escape key, or the app losing track of the screen (asleep, locked, changed, quitting).
        case escape
    }

    // MARK: Built-in lines

    /// What `name` says as it grabs the cursor, in its own voice, the current
    /// language and `mood`; `{today}` and `{all}` are its hunt count.
    public static func line(by name: String, today: Int, all: Int, mood: CursorMood = .current,
                            using rng: inout some RandomNumberGenerator) -> String {
        let pool = lineSets(for: mood)()[name] ?? anyones(for: mood)()
        return Banter.render(pool.randomElement(using: &rng)!, ["today": "\(today)", "all": "\(all)"])
    }

    /// What `name` says as it is shaken off.
    public static func lastWord(by name: String, mood: CursorMood = .current,
                                using rng: inout some RandomNumberGenerator) -> String {
        (lastWordSets(for: mood)()[name] ?? anyoneLastWords(for: mood)()).randomElement(using: &rng)!
    }

    public static func lineSets(for mood: CursorMood) -> Translated<[String: [String]]> {
        switch mood {
        case .good: Translated(english: englishGoodLines, [.russian: russianGoodLines])
        case .neutral: Translated(english: englishNeutralLines, [.russian: russianNeutralLines])
        case .bad: Translated(english: englishBadLines, [.russian: russianBadLines])
        }
    }

    public static func anyones(for mood: CursorMood) -> Translated<[String]> {
        switch mood {
        case .good: Translated(english: englishGoodAnyone, [.russian: russianGoodAnyone])
        case .neutral: Translated(english: englishNeutralAnyone, [.russian: russianNeutralAnyone])
        case .bad: Translated(english: englishBadAnyone, [.russian: russianBadAnyone])
        }
    }

    public static func lastWordSets(for mood: CursorMood) -> Translated<[String: [String]]> {
        switch mood {
        case .good: Translated(english: englishGoodLastWords, [.russian: russianGoodLastWords])
        case .neutral: Translated(english: englishNeutralLastWords, [.russian: russianNeutralLastWords])
        case .bad: Translated(english: englishBadLastWords, [.russian: russianBadLastWords])
        }
    }

    public static func anyoneLastWords(for mood: CursorMood) -> Translated<[String]> {
        switch mood {
        case .good: Translated(english: englishGoodAnyoneLastWords, [.russian: russianGoodAnyoneLastWords])
        case .neutral: Translated(english: englishNeutralAnyoneLastWords, [.russian: russianNeutralAnyoneLastWords])
        case .bad: Translated(english: englishBadAnyoneLastWords, [.russian: russianBadAnyoneLastWords])
        }
    }

    // MARK: For a model

    /// The model writes the line said while holding the cursor, in the current language and mood.
    public static var prompt: String { prompts(for: .current)() }
    public static func prompts(for mood: CursorMood) -> Translated<String> {
        switch mood {
        case .good: Translated(english: englishGoodPrompt, [.russian: russianGoodPrompt])
        case .neutral: Translated(english: englishNeutralPrompt, [.russian: russianNeutralPrompt])
        case .bad: Translated(english: englishBadPrompt, [.russian: russianBadPrompt])
        }
    }

    public static let englishBadPrompt = """
    {situation}
    The person whose screen you live on has chased you with the mouse cursor and picked you up far too often: \
    {times} times in the last few minutes. So you took revenge: you jumped on their cursor and are hanging on to it, \
    so they cannot use it until they shake you off. Say ONE line to them, shaming them for how they treat you, \
    in your own voice. At most 20 words. Output only the line: no quotes, no name.
    """

    public static let englishGoodPrompt = """
    {situation}
    The person whose screen you live on plays tag with you with the mouse cursor, and has chased you \
    {times} times in the last few minutes. So you turned the game round: you jumped on their cursor and are \
    clinging to it, gleefully, until they shake you off. Say ONE line to them, teasing and delighted, \
    in your own voice. At most 20 words. Output only the line: no quotes, no name.
    """

    public static let englishNeutralPrompt = """
    {situation}
    The person whose screen you live on has chased you with the mouse cursor and picked you up \
    {times} times in the last few minutes. So you grabbed their cursor and are holding on to it until they \
    shake you off. Say ONE line to them about it, deadpan and matter-of-fact, in your own voice. \
    At most 20 words. Output only the line: no quotes, no name.
    """
}

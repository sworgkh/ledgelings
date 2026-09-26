import Foundation

/// Things the user asked to be reminded of. When one comes due, a creature
/// folds it into a paper plane and throws it at the user: the plane flies to
/// the middle of the screen, grows as it comes at you, and opens into a letter.
///
/// A reminder keeps the time of its next delivery. A one-off is finished once
/// sent; a repeating one moves on to its next time after now, so a Mac that
/// slept through three mornings gets one letter, not three.
public enum Reminders {
    public enum Repeat: String, Codable, CaseIterable, Sendable {
        case once, daily, weekdays, weekly

        public var title: String {
            switch self {
            case .once: "Once"
            case .daily: "Every day"
            case .weekdays: "Every weekday"
            case .weekly: "Every week"
            }
        }
    }

    public struct Reminder: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        /// What to be reminded of, in the user's words: "Stretch", "Call mom".
        public var text: String
        /// When it is next delivered.
        public var time: Date
        public var repeats: Repeat
        /// When it was last delivered; a one-off with this set is finished.
        public var sentAt: Date?

        public init(id: UUID = UUID(), text: String, time: Date, repeats: Repeat = .once, sentAt: Date? = nil) {
            self.id = id; self.text = text; self.time = time; self.repeats = repeats; self.sentAt = sentAt
        }

        public var isFinished: Bool { repeats == .once && sentAt != nil }

        public func isDue(at now: Date) -> Bool { !isFinished && time <= now }

        /// The first time after `date` this reminder repeats at, keeping its hour
        /// and minute (and its weekday, weekly). Nil for a one-off.
        public func next(after date: Date, calendar: Calendar = .current) -> Date? {
            let clock = calendar.dateComponents([.hour, .minute], from: time)
            var match = DateComponents(hour: clock.hour, minute: clock.minute, second: 0)
            switch repeats {
            case .once: return nil
            case .daily: break
            case .weekly: match.weekday = calendar.component(.weekday, from: time)
            case .weekdays:
                var from = date
                for _ in 0..<8 {
                    guard let next = calendar.nextDate(after: from, matching: match, matchingPolicy: .nextTime) else { return nil }
                    let weekday = calendar.component(.weekday, from: next)
                    if weekday != 1, weekday != 7 { return next }       // Sunday is 1, Saturday 7
                    from = next
                }
                return nil
            }
            return calendar.nextDate(after: date, matching: match, matchingPolicy: .nextTime)
        }

        /// Delivered at `now`: a one-off is finished, a repeat moves to its next time after now.
        public mutating func markSent(at now: Date, calendar: Calendar = .current) {
            sentAt = now
            if let next = next(after: max(now, time), calendar: calendar) { time = next }
        }

        /// "Today 14:30", "Tomorrow 09:00", "Mon 3 Oct 18:00", plus the repeat.
        public func describe(now: Date, calendar: Calendar = .current) -> String {
            let when = Reminders.when(time, now: now, calendar: calendar)
            return repeats == .once ? when : "\(repeats.title), next \(when)"
        }
    }

    /// Every reminder the user set, finished ones included until cleared.
    public struct Book: Codable, Equatable, Sendable {
        public var reminders: [Reminder]
        public init(reminders: [Reminder] = []) { self.reminders = reminders }

        /// Waiting ones by time, then finished ones, the latest sent first.
        public var sorted: [Reminder] {
            reminders.filter { !$0.isFinished }.sorted { $0.time < $1.time }
                + reminders.filter(\.isFinished).sorted { ($0.sentAt ?? $0.time) > ($1.sentAt ?? $1.time) }
        }

        /// The ones due at `now`, the oldest first.
        public func due(at now: Date) -> [Reminder] {
            reminders.filter { $0.isDue(at: now) }.sorted { $0.time < $1.time }
        }

        /// The next one still to come.
        public var upcoming: Reminder? { reminders.filter { !$0.isFinished }.min { $0.time < $1.time } }

        public mutating func add(_ reminder: Reminder) { reminders.append(reminder) }
        public mutating func remove(_ id: UUID) { reminders.removeAll { $0.id == id } }
        public mutating func clearFinished() { reminders.removeAll(where: \.isFinished) }

        public mutating func markSent(_ id: UUID, at now: Date, calendar: Calendar = .current) {
            guard let i = reminders.firstIndex(where: { $0.id == id }) else { return }
            reminders[i].markSent(at: now, calendar: calendar)
        }
    }

    /// The book on disk: `reminders.json` in a folder, rewritten whole on each save.
    public struct Store: Sendable {
        public let directory: URL
        public init(directory: URL) { self.directory = directory }
        public var file: URL { directory.appendingPathComponent("reminders.json") }

        public func load() -> Book {
            guard let data = try? Data(contentsOf: file) else { return Book() }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return (try? decoder.decode(Book.self, from: data)) ?? Book()
        }

        public func save(_ book: Book) throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(book).write(to: file, options: .atomic)
        }
    }

    /// "Today 14:30", "Tomorrow 09:00", "Yesterday 18:00", else "Mon 3 Oct 18:00".
    public static func when(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let clock = DateFormatter()
        clock.calendar = calendar; clock.timeZone = calendar.timeZone
        clock.locale = Locale(identifier: "en_GB")
        clock.dateFormat = "HH:mm"
        let time = clock.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return "Today \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday \(time)" }
        clock.dateFormat = "EEE d MMM HH:mm"
        return clock.string(from: date)
    }

    // MARK: The letter

    /// One pixel of the letter's paper, in blocky's rules: a dark rim, flat
    /// paper, a light line top-left, a shade line bottom-right, a folded-down
    /// corner bottom-right, and the faint creases of a plane unfolded.
    public enum Paper: String, Sendable {
        case rim = "o", paper = "w", light = "L", shade = "s", deepShade = "S", crease = "c"
    }

    /// The corner fold, in pixels along each side.
    public static func cornerSize(width: Int, height: Int) -> Int { max(4, min(width, height) / 8) }

    /// The letter as rows of pixels, top row first; nil is transparent (the cut-off corner).
    public static func paper(width: Int, height: Int) -> [[Paper?]] {
        let w = max(width, 8), h = max(height, 8)
        let fold = cornerSize(width: w, height: h)
        var rows = Array(repeating: Array(repeating: Paper?.some(.paper), count: w), count: h)
        // Creases: the plane's centre fold, and the two wing folds a quarter in.
        for x in 2..<(w - 2) { rows[h / 2][x] = .crease }
        for y in 2..<(h - 2) { rows[y][w / 2] = .crease }
        for y in 0..<h {
            for x in 0..<w {
                let fromCorner = (w - 1 - x) + (h - 1 - y)         // 0 at the bottom-right pixel
                if fromCorner < fold - 1 { rows[y][x] = nil; continue }
                if fromCorner == fold - 1 { rows[y][x] = .rim; continue }  // the fold's diagonal edge
                if x == 0 || y == 0 || x == w - 1 || y == h - 1 { rows[y][x] = .rim; continue }
                if y == 1 || x == 1 { rows[y][x] = .light; continue }
                if y == h - 2 || x == w - 2 { rows[y][x] = .shade; continue }
            }
        }
        // The folded-down flap sits inside the corner: a stepped triangle in deep shade.
        for y in 0..<h {
            for x in 0..<w {
                let fromCorner = (w - 1 - x) + (h - 1 - y)
                let insideFlap = x >= w - fold && y >= h - fold && fromCorner >= fold
                if insideFlap { rows[y][x] = x == w - fold || y == h - fold ? .rim : .deepShade }
            }
        }
        return rows
    }

    // MARK: The note that comes with it

    /// What each built-in character writes above your reminder, in its own
    /// voice. `{reminder}` is what you asked to be reminded of. A character the
    /// user invented uses `anyone`.
    public static let anyone = [
        "It's time: {reminder}. You asked me to tell you, so I'm telling you.",
        "Knock knock. {reminder}. That's the whole joke. Go on.",
    ]

    public static let notes: [String: [String]] = [
        // blocky's cast
        "Blocky": ["Stop staring at the cursor. It's time: {reminder}. I have a list, and you're on it.",
                   "Official notice from the bottom edge: {reminder}. Now. Don't make me jump."],
        "Pip": ["It's time it's time it's TIME! {reminder}! I folded this upside down just for you!",
                "Guess what?! {reminder}! You can do it! I believe in you so much!"],
        "Mortimer": ["An old saying: the hour you set is the hour that sets you. {reminder}, young one.",
                     "*sighs* Time has come round again, as it does. {reminder}."],
        "Zed": ["*yawns* woke up just to tell you... {reminder}. Right. Back to sleep.",
                "Psst. {reminder}. I'd do it for you, but. Nap."],
        "Dot": ["Got here first, obviously. {reminder}. Try to keep up, boulder.",
                "Fastest plane on the screen, and it says: {reminder}. You're welcome."],
        "Ruth": ["By my count, it is now exactly time for: {reminder}. I checked twice.",
                 "Item one of one: {reminder}. Counted, folded, delivered. No jumping about it."],
        // cat
        "Whiskers": ["Not that I care, but... {reminder}. What are you doing, anyway?",
                     "I happened to notice the time. {reminder}. Don't thank me."],
        "Mittens": ["Purrr... sorry to wake you, warm one. {reminder}. Then come back to the sunny side.",
                    "Mrrrp. It's time for {reminder}. I kept the note warm for you."],
        "Sir Pounce": ["The hunt begins! Target sighted: {reminder}! Pounce on it NOW!",
                       "I have stalked the clock for hours and caught it: {reminder}!"],
        // frog
        "Hopper": ["I threw this ALL the way across the screen! {reminder}! Best throw ever!",
                   "RIBBIT! {reminder}! I'd jump over there and tell you, but. Plane was faster."],
        "Mossy": ["The pond waits for no frog. {reminder}.", "Slow ripples reach the shore at last: {reminder}."],
        "Croak": ["Too dry up here to shout, so I wrote it: {reminder}. Go.",
                  "Grumble. {reminder}. There. Happy?"],
        // ghost
        "Boo": ["BOO! ...did I scare you? No? Well, {reminder}!", "Boo boo boo! It's time: {reminder}! Spooky, right?"],
        "Wisp": ["Like a monitor I once knew, this moment will pass. Before it does: {reminder}.",
                 "The hour drifted by and whispered: {reminder}."],
        "Sheet": ["I floated this over. Technically, I didn't walk. {reminder}.",
                  "Reminder: {reminder}. That is all. I am, technically, a sheet."],
        // mushroom
        "Morel": ["Patience has its end, like the rain... {reminder}.", "Slowly, from the damp corner... it is time... {reminder}."],
        "Puff": ["Hee hee! {reminder}! Go before I spore everywhere!", "Eee! It's time! {reminder}! *puff*"],
        "Cap": ["In my day, we didn't need planes to remember things. {reminder}.",
                "In my day we wrote on bark. Anyway: {reminder}."],
        // robot
        "Unit 7": ["Scheduled task at 100% due: {reminder}. Delay recommended: 0 seconds.",
                   "Status: 1 reminder delivered. Content: {reminder}. Compliance expected: 100%."],
        "Sprocket": ["Maintenance window open! Item: {reminder}. I've oiled the plane for you!",
                     "Time to tighten up the schedule: {reminder}!"],
        "Glitch": ["Reminder reminder: {reminder}. The cursor did NOT send this.",
                   "It's time time for: {reminder}. Scanned for viruses. Clean."],
        // slime
        "Goop": ["Nice! Sticky! It's time: {reminder}!", "Hi hi! {reminder}! That's nice, right?"],
        "Puddle": ["Sorry, sorry, I hope this isn't too late — {reminder}. Please don't step on the plane.",
                   "Oh no, it's time. {reminder}. I'm drying out just thinking about it."],
        "Blorp": ["Blorp! {reminder}! Zoom!", "Splat. {reminder}. Blorp did good."],
        // triangle
        "Spike": ["Point is: {reminder}. Now.", "Let me be sharp about it: {reminder}."],
        "Wedge": ["I will not be tipped over on this one: {reminder}. No arguing.",
                  "It's decided and it stays decided: {reminder}."],
        "Delta": ["Something changed since last time: now it's time for {reminder}.",
                  "Difference noticed: the clock moved. {reminder}."],
    ]

    /// The note `writer` sends with `reminder`.
    public static func note(by writer: String, reminder: String, using rng: inout some RandomNumberGenerator) -> String {
        fill((notes[writer] ?? anyone).randomElement(using: &rng)!, reminder: reminder)
    }

    /// `{reminder}` filled in; mid-sentence ("Well, call mom!", "time for stretching")
    /// its first letter goes small, unless it reads like "I" or an acronym.
    public static func fill(_ line: String, reminder: String) -> String {
        guard let at = line.range(of: "{reminder}") else { return line }
        let before = line[..<at.lowerBound]
        let midSentence = before.hasSuffix(", ") || before.hasSuffix("for ")
        let words = reminder.split(separator: " ", maxSplits: 1)
        let first = words.first.map(String.init) ?? ""
        let shout = first == "I" || first.count > 1 && first == first.uppercased()
        let shown = midSentence && !shout ? reminder.prefix(1).lowercased() + reminder.dropFirst() : reminder
        return Banter.render(line, ["reminder": shown])
    }

    /// The model writes the note as the creature throwing the plane.
    public static let notePrompt = """
    {situation}
    The person whose screen you live on asked to be reminded, right now, of: "{reminder}". \
    You fold it into a paper plane and throw it to them. Write the note that goes with it: \
    one line in your own voice telling them it is time for it. \
    At most 20 words. Output only the note: no quotes, no signature.
    """
}

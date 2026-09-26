import Foundation

/// How often each creature has been pushed around by the user's cursor lately:
/// chased off its edge, or picked up. Past `limit` times in a row it complains.
/// A quiet spell of `calmAfter` seconds starts the count over, and so does
/// complaining: the next complaint needs a fresh streak.
public struct Annoyance: Sendable {
    public var limit: Int
    public var calmAfter: Double
    private var streaks: [Int: (count: Int, last: Double)] = [:]

    public init(limit: Int = 4, calmAfter: Double = 20) {
        self.limit = limit
        self.calmAfter = calmAfter
    }

    /// Creature `index` was pushed around at `time`. True once this streak is
    /// past the limit: it has had enough and should say so.
    public mutating func bothered(_ index: Int, at time: Double) -> Bool {
        var streak = streaks[index] ?? (0, -.infinity)
        if time - streak.last > calmAfter { streak.count = 0 }
        streak.count += 1
        streak.last = time
        streaks[index] = streak
        return streak.count > limit
    }

    /// Times in a row creature `index` has been pushed around, as of `time`.
    public func streak(of index: Int, at time: Double) -> Int {
        guard let streak = streaks[index], time - streak.last <= calmAfter else { return 0 }
        return streak.count
    }

    /// It has complained: the count starts over.
    public mutating func forgive(_ index: Int) { streaks[index] = nil }

    /// Creatures from `count` on are gone.
    public mutating func forget(creaturesFrom count: Int) { streaks = streaks.filter { $0.key < count } }
}

/// What a creature says to the user when the cursor has chased it or carried
/// it around once too often. Each built-in character complains in its own
/// voice; `{times}` is how many times in a row it has been bothered.
public enum Complaints {
    /// For a character the user invented.
    public static let anyone = [
        "Hey! That's {times} times in a row. Leave me alone!",
        "Stop it with the cursor. I mean it.",
        "Do you mind? Some of us live here.",
    ]

    public static let lines: [String: [String]] = [
        // blocky's cast
        "Blocky": ["{times} times. I have written every one of them down. Back off.",
                   "THIS is why I hate the cursor. Get it off my edge.",
                   "Again?! Point that thing somewhere else."],
        "Pip": ["Haha! Okay, okay, that was fun, but {times} times is a LOT!",
                "Wheee! ...wait, can I stay on the ceiling now? Please?",
                "You really like me, huh! Maybe a little less chasing?"],
        "Mortimer": ["*sighs* An old saying: the cursor that chases {times} times catches nothing.",
                     "My bones are too old for all this leaping, young one.",
                     "Patience is a virtue. Yours seems to be missing."],
        "Zed": ["I was *yawn* almost asleep. {times} times. Why.",
                "Can I just... nap somewhere the cursor isn't...",
                "Too tired for this. Stop. Please. Bed."],
        "Dot": ["{times} times and you STILL can't catch me, boulder.",
                "Faster than your cursor, obviously. Now quit it.",
                "Is that your top speed? Sad. Also: stop."],
        "Ruth": ["That is {times} times in a row. I am keeping count. Stop it.",
                 "Excessive jumping. I disapprove. Put the cursor away.",
                 "Rule one: no chasing. You have broken it {times} times."],
        // cat
        "Whiskers": ["Not that I care, but {times} times is rude. What do you want?",
                     "I'm ignoring you. Completely. ...Stop that.",
                     "Hmph. Chase a mouse instead. Oh wait."],
        "Mittens": ["Mrrrow... I was so warm and comfy. {times} times...",
                    "Purr-lease stop, I just found the sunny side.",
                    "Mrrp. Too much chasing. Pet me or let me be."],
        "Sir Pounce": ["The hunter is being HUNTED! {times} times! This is an outrage!",
                       "I pounce on others. Nobody pounces on Sir Pounce!",
                       "Retreat! Retreat! ...regroup, and then get revenge."],
        // frog
        "Hopper": ["Ha! {times} jumps! Best jumps ever! ...but my legs are tired now.",
                   "RIBBIT! Stop chasing me! I'll jump SO far away!",
                   "Okay, I jumped. A lot. You can stop now."],
        "Mossy": ["A frog chased {times} times finds no pond to rest in.",
                  "Still water, calm frog. Stir it again and I croak.",
                  "The pond is patient. I am not the pond."],
        "Croak": ["Grumble. {times} times. Too dry up here for all this jumping.",
                  "Stop it. I'm drying out every time I leap.",
                  "Leave me be. The edge is bad enough without you."],
        // ghost
        "Boo": ["Hey! I'M supposed to scare YOU! {times} times isn't fair!",
                "Boo! ...Boo? Why aren't you scared of me?!",
                "Stop chasing me, I'm the spooky one!"],
        "Wisp": ["Chased {times} times, like a memory that won't settle.",
                 "Let me drift in peace. Even ghosts need rest.",
                 "Please. I only wish to float here a while."],
        "Sheet": ["{times} times. I didn't run away, technically. I floated. Stop.",
                  "I am a sheet. Please do not fold me with your cursor.",
                  "That's harassment. Technically."],
        // mushroom
        "Morel": ["{times} times... a mushroom needs stillness... and damp...",
                  "Slow down... I cannot grow if you keep moving me...",
                  "Leave me... in my corner... please..."],
        "Puff": ["Eee! {times} times! Stop or I'll spore EVERYWHERE!",
                 "Hee hee- no, really, stop! *puff*",
                 "I'm gonna pop! Leave me alone!"],
        "Cap": ["In my day, nobody got chased {times} times by a cursor.",
                "In my day we had respect for our elders. And no cursors.",
                "Young people and their mice. Leave me be."],
        // robot
        "Unit 7": ["Warning: cursor contacts logged: {times}. Tolerance exceeded by 100%.",
                   "Error 418: annoyance at 97%. Please cease.",
                   "Evasive jumps logged: {times}. Requesting 0 more."],
        "Sprocket": ["{times} jumps in a row! My bolts are rattling loose!",
                     "Careful! You're scratching my paint!",
                     "I need maintenance after all that. Stop, please!"],
        "Glitch": ["The cursor cursor is chasing me. {times} times. VIRUS.",
                   "Stop stop stop. I'm running a scan on you.",
                   "Malware detected: your cursor. Keep it away away."],
        // slime
        "Goop": ["Not nice! Not sticky! {times} times is too many!",
                 "Hey! I'm getting all stretched! Stop!",
                 "Ow. Not nice. Leave me be, please?"],
        "Puddle": ["{times} times... please, I'm going to splash everywhere.",
                   "Oh no, oh no, please don't step on me!",
                   "Stop, I'm evaporating from all the stress!"],
        "Blorp": ["Blorp! {times}! Too much! Splat!",
                  "No! Blorp no like! Go away!",
                  "Zoom zoom STOP!"],
        // triangle
        "Spike": ["{times} times. I have a point, and it's: stop.",
                  "Keep poking and you'll find out how sharp I am.",
                  "Back off. Sharp edges."],
        "Wedge": ["{times} times and I'm still not tipping over. Give up.",
                  "You won't move me on this. Stop trying.",
                  "Stop. Pushing. Me. It won't work."],
        "Delta": ["The difference since last time: {times} jumps. Too many.",
                  "Something changed: I'm annoyed now.",
                  "Noticed: your cursor moved. At me. Again."],
    ]

    /// A complaint from `name`, bothered `times` times in a row.
    public static func line(by name: String, times: Int, using rng: inout some RandomNumberGenerator) -> String {
        Banter.render((lines[name] ?? anyone).randomElement(using: &rng)!, ["times": "\(times)"])
    }

    /// The model writes the complaint, in the creature's voice.
    public static let prompt = """
    {situation}
    The person whose screen you live on keeps chasing you with the mouse cursor and picking you up: \
    {times} times in a row now. You have had enough. Say ONE line to them, complaining, in your own voice. \
    At most 20 words. Output only the line: no quotes, no name.
    """
}

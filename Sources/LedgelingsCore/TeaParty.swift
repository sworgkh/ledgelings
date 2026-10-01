import CoreGraphics
import Foundation

/// A tea party: now and then two creatures who bump into each other do not
/// just trade a line and walk on. They step back, a little table with a teapot
/// and two cups comes up between them, and for a few minutes they sit and tell
/// each other stories from their lives, taking turns, a sip of quiet between
/// each. Then the table packs itself away and they go on their way.
///
/// seating → laying → tea → packing → over
///
/// The colony drives it: it says when both have reached their seats, runs each
/// **round** the party asks for (one tells a story, the other answers), says
/// when the round is over, and draws the table at `scale`.
public struct TeaParty: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// Both stepping back to their seats; no table yet.
        case seating
        /// The table grows up out of the edge.
        case laying
        /// Sitting and talking.
        case tea
        /// The table shrinks away; they are about to walk on.
        case packing
        case over
    }

    public enum Event: Equatable, Sendable {
        /// Time for a round: `teller` tells a story from its life, `listener` answers.
        case round(teller: Int, listener: Int)
        /// The table is gone: let the pair walk on.
        case finished
    }

    public var appearTime: Double = 0.4
    public var packTime: Double = 0.5
    /// Longest the table waits for someone still walking to its seat.
    public var seatingCap: Double = 4
    /// The first round waits this long after the table is up: the tea is poured.
    public var pourTime: Double = 1.5

    public let a: Int
    public let b: Int
    /// Seconds from the start the party lasts; a round under way is let finish.
    public let length: Double
    /// Seconds of quiet sipping between one round and the next.
    public let pause: Double
    public private(set) var phase: Phase = .seating
    /// Rounds told so far.
    public private(set) var rounds = 0
    public private(set) var inRound = false
    private let started: Double
    private var phaseStarted: Double
    private var nextRound: Double = .infinity

    public init(a: Int, b: Int, at time: Double, length: Double, pause: Double) {
        self.a = a; self.b = b
        self.length = max(0, length); self.pause = max(0, pause)
        started = time
        phaseStarted = time
    }

    public func involves(_ i: Int) -> Bool { i == a || i == b }
    public var isOver: Bool { phase == .over }
    /// Still on: not yet packing up.
    public var isOn: Bool { phase == .seating || phase == .laying || phase == .tea }
    public func endsAt() -> Double { started + length }

    /// Both are in their chairs.
    public mutating func seated(at time: Double) {
        guard phase == .seating else { return }
        enter(.laying, at: time)
    }

    /// The round asked for is over (said, or skipped): sip, then the next.
    public mutating func roundDone(at time: Double) {
        guard inRound else { return }
        inRound = false
        rounds += 1
        nextRound = time + pause
    }

    /// The round could not start yet (the one voice is taken): ask again in `seconds`.
    public mutating func postpone(at time: Double, for seconds: Double = 1) {
        guard inRound else { return }
        inRound = false
        nextRound = time + seconds
    }

    /// Break it up now: one of them was chased off, picked up, or sent home.
    public mutating func end(at time: Double) {
        switch phase {
        case .seating: enter(.over, at: time)
        case .laying, .tea: inRound = false; enter(.packing, at: time)
        case .packing, .over: break
        }
    }

    /// 0 = not there, 1 = full size.
    public func scale(at time: Double) -> Double {
        let since = time - phaseStarted
        switch phase {
        case .seating, .over: return 0
        case .laying: return min(1, max(0, since / appearTime))
        case .tea: return 1
        case .packing: return min(1, max(0, 1 - since / packTime))
        }
    }

    public mutating func update(at time: Double) -> [Event] {
        let since = time - phaseStarted
        switch phase {
        case .seating:
            if since >= seatingCap { enter(.laying, at: time) }
            return []
        case .laying:
            if since >= appearTime {
                enter(.tea, at: time)
                nextRound = time + pourTime
            }
            return []
        case .tea:
            guard !inRound else { return [] }
            if time >= endsAt() { enter(.packing, at: time); return [] }
            guard time >= nextRound else { return [] }
            inRound = true
            // They take turns telling: the first round is `a`'s.
            return rounds.isMultiple(of: 2) ? [.round(teller: a, listener: b)] : [.round(teller: b, listener: a)]
        case .packing:
            if since >= packTime { enter(.over, at: time); return [.finished] }
            return []
        case .over:
            return []
        }
    }

    private mutating func enter(_ next: Phase, at time: Double) {
        phase = next
        phaseStarted = time
    }

    // MARK: Where they sit

    /// Where on its own loop a creature sits for tea: `offset` points from
    /// `middle` (a point on this loop) along its segment, on the side away from
    /// the one it faces (`facing` +1 = toward growing t). Nil when that seat is
    /// past the end of the segment: no table round a corner.
    public static func seat(on loop: EdgeLoop, segment: Int, middle: CGPoint, facing: CGFloat, offset: CGFloat) -> CGFloat? {
        let along = loop.direction(ofSegment: segment)
        let back: CGFloat = facing < 0 ? 1 : -1
        let chair = CGPoint(x: middle.x + along.dx * back * offset, y: middle.y + along.dy * back * offset)
        let found = loop.nearest(to: chair)
        guard found.distance < 1, loop.segment(at: found.t) == segment else { return nil }
        return found.t
    }

    /// Should this bump be a tea party? `percent` of bumps are, 0...100.
    public static func wanted(percent: Double, using rng: inout some RandomNumberGenerator) -> Bool {
        percent > 0 && Double.random(in: 0..<100, using: &rng) < percent
    }
}

/// What they say over tea: stories from their lives, and what the other says back.
/// Each built-in character has its own, in its own voice; `anyone` is for a
/// character the user invented. `{other}` is the one across the table.
/// The Russian is in `TeaParty+Russian.swift`.
public enum Tea {
    public static var anyoneStories: [String] { anyoneStoryBooks() }
    public static var anyoneReplies: [String] { anyoneReplyBooks() }
    public static var stories: [String: [String]] { storyBooks() }
    public static var replies: [String: [String]] { replyBooks() }
    public static let anyoneStoryBooks = Translated(english: englishAnyoneStories)
    public static let anyoneReplyBooks = Translated(english: englishAnyoneReplies)
    public static let storyBooks = Translated(english: englishStories)
    public static let replyBooks = Translated(english: englishReplies)

    public static let englishAnyoneStories = [
        "I wasn't always on this edge, you know. I started out in a corner nobody visits.",
        "When I was small, I thought the screen went on forever. Then I found the first edge.",
        "Once I walked the whole way round without stopping. Nobody noticed. I still think about it.",
        "My secret? Every night I pick a pixel and make a wish on it.",
    ]
    public static let englishAnyoneReplies = [
        "Really? I never knew that about you, {other}.",
        "That's lovely. More tea?",
        "Funny, something like that happened to me once.",
    ]

    /// Four stories each: more than one character tells in a party of the default length.
    public static let englishStories: [String: [String]] = [
        // blocky's cast
        "Blocky": ["I was the first one here. Before the colours, before the cursor. Those were good days.",
                   "The cursor chased me into a corner once. I stared it down. It blinked first.",
                   "I only ever wanted one thing: the bottom edge, all to myself. Still waiting.",
                   "I had a friend once who liked the ceiling. We don't talk about him."],
        "Pip": ["I was born on the ceiling! Upside down! I thought everyone else was the wrong way up!",
                "Once I laughed so hard I fell off the top edge. Best day ever!",
                "My first word was 'wheee'. My second was also 'wheee'.",
                "I've never been sad, not once! Well, once. When the screen went dark. But it came back!"],
        "Mortimer": ["*sighs* In my youth I walked all four edges in one day. My knees remember it still.",
                     "I once met a wise old pixel. It said nothing. I have thought about it for years.",
                     "My father told me: the edge is long, but the tea is short. Drink up.",
                     "I have outlived three wallpapers. Each one taught me something. Mostly about blue."],
        "Zed": ["I was born asleep. Woke up at about... noon. Went back to bed.",
                "Once I stayed awake a whole day. Never again. *yawn*",
                "My dream? A bed the size of this whole screen... and nobody waking me...",
                "I fell asleep at my own birthday. It was a very good birthday. I think."],
        "Dot": ["I did the whole bottom edge in four seconds once. Nobody timed it. Trust me.",
                "Grew up the smallest. Learned to be the fastest. Obviously.",
                "I raced the cursor once. Beat it. It still won't admit it.",
                "Secret? I get dizzy on the corners. Tell no one, boulder."],
        "Ruth": ["I have kept a list of every jump on this screen since the day I arrived. 4,211 so far.",
                 "My mother ran a very tidy corner. I intend to do better.",
                 "Once, just once, I jumped. For no reason. I still haven't forgiven myself.",
                 "I organised the first walk-in-a-line. Nobody came. Rules are rules though."],
        // cat
        "Whiskers": ["Not that you asked, but I once had a sunny spot all to myself. For a whole afternoon.",
                     "I came from a wallpaper with a sofa on it. I miss the sofa. Slightly.",
                     "Somebody once petted me with the cursor. I allowed it. Once.",
                     "I don't have stories. ...Fine. I was scared of the dock for a week."],
        "Mittens": ["Mrrr... I was born in the warmest corner, right by the clock. Still dream of it.",
                    "Once I napped through a whole restart. Woke up somewhere new. Purr.",
                    "My mama said: always find the sunny side. I'm still looking, mrrp.",
                    "I had a ball of yarn once. It was just a pixel. I loved it anyway."],
        "Sir Pounce": ["I once stalked a notification for three whole minutes. It never saw me coming!",
                       "My greatest hunt: the cursor, at dawn. It escaped. We shall meet again.",
                       "I was knighted by a sleeping cat. It counts. It absolutely counts.",
                       "As a kitten I pounced on my own shadow. It won. I have trained since."],
        // frog
        "Hopper": ["I once jumped clean over a whole window! Well, a small one. Well, a tooltip.",
                   "Came out of an egg and jumped straight away! Haven't stopped since! Mostly!",
                   "My record jump? Nobody saw it. Very big though! HUGE!",
                   "I tried to jump to another monitor once. There wasn't one. Landed okay!"],
        "Mossy": ["A tadpole I was, in a pond of pure blue pixels. The pond remembers.",
                  "My grandmother said: the still pond sees the moon. I sat still for a year.",
                  "I once waited a whole season for one fly. It never came. The waiting was the point.",
                  "Before this edge, I lived under a leaf icon. Quiet times, damp times."],
        "Croak": ["I came from a swamp. A real one. Wet. Nothing like this dry old edge.",
                  "Had a lily pad once. Best thing I ever owned. Someone closed the window.",
                  "Never liked jumping. Got born a frog anyway. Typical.",
                  "Rained once, on the screen. Somebody's wallpaper. Happiest ten seconds of my life."],
        // ghost
        "Boo": ["I scared a cursor once! It went all spinny! Well, it was loading, but still!",
                "I've been a ghost since... always? I think I was born saying boo!",
                "My dream is to be a REALLY scary ghost. With chains. Little ones.",
                "One time somebody jumped when I said boo. Best day of my afterlife."],
        "Wisp": ["I remember a monitor, long gone now. It had the softest glow. I haunt its memory still.",
                 "Once I drifted too far and nearly faded into the wallpaper. Someone called me back.",
                 "I was a screensaver, you know. Before. Floating was all I knew.",
                 "There was a window I loved. It closed one night and never opened again."],
        "Sheet": ["I used to be an actual sheet. On a bed. Technically I still am, emotionally.",
                  "I have never walked in my life. I float. I want that on the record.",
                  "Someone tried to fold me once. I haven't trusted a corner since.",
                  "I was in a laundry basket before this. It was, technically, cosy."],
        // mushroom
        "Morel": ["I grew... in the dampest corner... slowly... over many screensavers...",
                  "My family is very big... all under the ground... connected... we still talk...",
                  "Once it was dark for three days... the best days of my life...",
                  "I waited a long time... to be picked... nobody came... I grew instead..."],
        "Puff": ["Once I got SO excited I spored all over a whole window! Hee hee! They had to close it!",
                 "I was the smallest mushroom in the patch! Now look at me! Still small! Hee!",
                 "My best friend was a dandelion. We puffed together. Then the wind came.",
                 "I've never been out in the rain! I want to! Just once! *puff*"],
        "Cap": ["In my day we grew in the dark and liked it. No wallpapers. No colours.",
                "In my day a mushroom stayed in one spot its whole life. Proud of it.",
                "I remember when this screen was only 800 wide. Everything was closer then.",
                "In my day we had respect. And moss. Mostly moss."],
        // robot
        "Unit 7": ["Activation date: unknown. First memory: this edge. Satisfaction: 71%.",
                   "Once I computed the length of every edge. Total: 4,096 points. I recalculate daily.",
                   "I had a firmware update once. I felt 3% different. I liked it.",
                   "Secret file, opened: I would like, one day, to feel the sun. Probability: low."],
        "Sprocket": ["I was built from spare parts! Three different robots! Every one of them was lovely!",
                     "My first memory is being tightened! Bliss!",
                     "Once I oiled a whole row of rivets in one go. Still proud of that!",
                     "I dream of a toolbox. A big one. With little drawers!"],
        "Glitch": ["I was booted up during a thunderstorm. That's why I repeat repeat myself.",
                   "Once I scanned the whole screen. Found one virus. It was the cursor. As expected.",
                   "I lost a whole afternoon to a memory leak. Don't remember remember it.",
                   "My maker said I was perfect. Then I said perfect perfect. He sighed."],
        // slime
        "Goop": ["I was a drop of goo once! Then I grew! Now I'm a big goo! Nice!",
                 "Found a sticky spot on the edge once. Stayed there a whole day. So nice.",
                 "Mum was a slime too. She said: stay sticky. So I do!",
                 "I got stuck on a corner once! Took ages! Was nice though!"],
        "Puddle": ["I once got SO close to a hot window. I lost nearly a whole drop. I still think about it.",
                   "When I was little, I was scared of the cursor. I still am. But I was then too.",
                   "I'm always worried I'll evaporate. My aunt did. Well, she became a cloud. It's fine. It's fine.",
                   "I got stepped on once. Just a little. By a flower. I forgave it."],
        "Blorp": ["Blorp! Born! Splat! Here!",
                  "Once: big jump! Splat! Best!",
                  "Me? Little drip. Now? BIG BLORP.",
                  "Mmm. Dream: puddle. Big puddle. Blorp."],
        // triangle
        "Spike": ["I was born pointy. Everybody said I'd soften. I didn't. Point proven.",
                  "I popped a speech bubble once. By accident. Mostly.",
                  "My one regret? That argument with a circle. It went round and round.",
                  "I learned early: if you have a point, stand on it."],
        "Wedge": ["Nobody has ever tipped me over. Not once. People have tried.",
                  "I was the base of a very tall pyramid, once. Held it all up. Nobody thanked me.",
                  "My father never changed his mind. Neither have I. It's a family thing.",
                  "Somebody tried to move me off this spot last year. I'm still here."],
        "Delta": ["The biggest change in my life? Arriving here. Everything since has been smaller.",
                  "I have noticed every pixel that moved since I arrived. Mostly the cursor's fault.",
                  "I was a different shape once. Slightly. One degree off. Nobody else saw.",
                  "When I was small, the screen was dimmer. Now it's 12% brighter. I notice."],
    ]

    /// Three answers each, for when the other has told a story.
    public static let englishReplies: [String: [String]] = [
        "Blocky": ["Hmph. Not bad, {other}. Better than most stories on this screen.",
                   "That's nothing. I once waited a whole day for the cursor to leave.",
                   "Sip your tea, {other}. We've all had it hard."],
        "Pip": ["Ooh! That's amazing, {other}! Tell me more! More more more!",
                "Haha, that's just like me! Well, not at all, but still!",
                "Aww! I love that! I love you! I love tea!"],
        "Mortimer": ["*sighs* Ah, {other}. That reminds me of my own youth, long ago.",
                     "A wise story. My grandfather had one like it. Only longer.",
                     "Hm. The edge teaches us all, in time. More tea?"],
        "Zed": ["Mm... that's nice, {other}... I dreamt something like that once...",
                "Sounds tiring... *sip*... I'd have napped through it.",
                "Wake me... when the next story is... *yawn*... oh, it's my turn?"],
        "Dot": ["Cute story, {other}. Took you long enough to tell it though.",
                "I'd have done that twice as fast. Just saying.",
                "Huh. Not bad, for a boulder."],
        "Ruth": ["Noted, {other}. I'll add it to my records.",
                 "That was very nearly in order. Well told.",
                 "Hm. That breaks at least two rules. I liked it anyway."],
        "Whiskers": ["Mm. Interesting. Not that I care. ...What happened next?",
                     "I suppose that's a story. I've heard worse, {other}.",
                     "Hmph. I would have done it better. Pour me more."],
        "Mittens": ["Purrr... that's so sweet, {other}. More tea, please.",
                    "Mrrp... you remind me of a warm afternoon.",
                    "Aww. I'd give you a nuzzle if the table wasn't in the way."],
        "Sir Pounce": ["A tale worthy of a hunter, {other}! I salute you!",
                       "Ha! Bold! Daring! Almost as good as my own hunts!",
                       "Magnificent! I shall pounce on that memory forever!"],
        "Hopper": ["Wow! That's a big one, {other}! Almost as big as my jumps!",
                   "Ha! I'd have jumped right over that! Probably!",
                   "Cool story! RIBBIT! My turn soon?"],
        "Mossy": ["Ah. The pond that listens hears everything, {other}.",
                  "A frog who hears such a story grows a little wiser. Thank you.",
                  "Still water runs deep. So do you, it seems."],
        "Croak": ["Hmph. At least it wasn't dry. Everything here is so dry.",
                  "Could be worse, {other}. You could be a frog on a screen.",
                  "Grumble. Fine. That was a good one. Don't tell anyone I said so."],
        "Boo": ["Ooooh! That's almost spooky, {other}! I love it!",
                "Boo! ...Sorry. That was a good story. I got excited.",
                "Wow! Can I tell that one to scare people?"],
        "Wisp": ["How beautiful, {other}. Like a light from a screen long gone.",
                 "I'll keep that story with me, wherever I drift.",
                 "Mm. Some memories float, some sink. That one floats."],
        "Sheet": ["Noted. Technically, that was a story. A good one.",
                  "Interesting, {other}. I'd nod, but I'm a sheet.",
                  "I had a similar experience. Technically. In a drawer."],
        "Morel": ["Mm... that story has deep roots... like mine...",
                  "Slowly... I understand you better now... {other}...",
                  "Damp... and true... I like that..."],
        "Puff": ["Eee! That's SO good, {other}! I'm gonna spore!",
                 "Hee hee! Tell it again! No, tell a new one! No, both!",
                 "*puff* Sorry! That happens when a story's good!"],
        "Cap": ["In my day we'd have called that a proper story, {other}.",
                "Not bad. In my day it'd have been longer. And wetter.",
                "Hm. You young ones have it easy. Still, well told."],
        "Unit 7": ["Story logged. Emotional impact: 64%. Thank you, {other}.",
                   "Processing... processing... that was nice.",
                   "Recorded to long-term memory. Tea level: 40%."],
        "Sprocket": ["Oh, what a story, {other}! It tightened my heart bolts!",
                     "Wonderful! Well oiled! Like a good gear!",
                     "I love it! Can I fix anything in it for you?"],
        "Glitch": ["Interesting interesting, {other}. No viruses detected in that story.",
                   "Saving saving to memory. Hope it doesn't leak.",
                   "I believe you. Unless the cursor put you up to it."],
        "Goop": ["Nice! Sticky story, {other}! Very nice!",
                 "Aww. That's so nice. Like goo.",
                 "Ooh! I like that one! Tell another!"],
        "Puddle": ["Oh no, that sounds so scary. But you're okay? You're okay.",
                   "That's lovely, {other}. Could you... pass the saucer? In case I spill.",
                   "I'd have been so worried! You're so brave!"],
        "Blorp": ["Blorp! Good story!", "Ooh! Wow! Splat!", "Mm! More! Blorp!"],
        "Spike": ["Sharp story, {other}. I'll allow it.",
                  "Okay, that one had a point. Unlike most.",
                  "Hm. Made your point. Well done."],
        "Wedge": ["Hm. I won't change my mind about you, {other}. But that was good.",
                  "Solid story. Like me.",
                  "Fine. I'll give you that one. Only that one."],
        "Delta": ["Interesting. I noticed a small change in you while you told that, {other}.",
                  "That changes things. Slightly. Noted.",
                  "The difference between you before that story and after: noticeable."],
    ]

    /// A story from `name`, one it has not told at this party when it has one left.
    public static func story(by name: String, avoiding told: Set<String>, using rng: inout some RandomNumberGenerator) -> String {
        let all = stories[name] ?? anyoneStories
        return (all.filter { !told.contains($0) }.randomElement(using: &rng) ?? all.randomElement(using: &rng))!
    }

    /// What `name` says back to `other`'s story.
    public static func reply(by name: String, to other: String, using rng: inout some RandomNumberGenerator) -> String {
        Banter.render((replies[name] ?? anyoneReplies).randomElement(using: &rng)!, ["other": other])
    }

    // MARK: With a model

    public static let placeholders = ["speaker", "speakerKind", "speakerPersona", "listener", "listenerKind", "listenerPersona",
                                      "situation", "party", "line", "relationship"]

    public static let systemPrompts = Translated(english: englishSystemPrompt)
    public static let storyPrompts = Translated(english: englishStoryPrompt)
    public static let replyPrompts = Translated(english: englishReplyPrompt)
    public static var systemPrompt: String { systemPrompts() }
    public static var storyPrompt: String { storyPrompts() }
    public static var replyPrompt: String { replyPrompts() }

    /// Who they are, and that this is tea, not banter: stories, not jabs.
    public static let englishSystemPrompt = """
    You are {speaker}, {speakerKind}, living on the edge of a computer screen. {speakerPersona}
    You are having a tea party with {listener}, {listenerKind}, at a tiny table on the edge. {listenerPersona}
    Over tea the two of you share stories from your lives. Speak in your own voice, true to who you are.
    Say ONE line, at most 25 words. Output only the line. No quotes, no name prefix, no explanation.
    """

    /// The teller's turn.
    public static let englishStoryPrompt = """
    Right now: {situation}
    Said at this tea party so far:
    {party}
    Tell {listener} one small story from your life that you have not told yet: where you come from, \
    a memory, a secret, a mistake, a dream.
    """

    /// The listener's answer to it.
    public static let englishReplyPrompt = """
    Right now: {situation}
    Said at this tea party so far:
    {party}
    {listener} just told you: "{line}"
    Answer in ONE line, in character: react to it, and give back a little piece of your own life.
    """

    /// The party so far, for `{party}`: the last `keep` lines, "Name: line".
    public static func transcript(_ lines: [ChatLog.Line], keep: Int = 8) -> String {
        lines.isEmpty ? tr("(nothing yet: the tea has just been poured)")
            : lines.suffix(keep).map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
    }
}

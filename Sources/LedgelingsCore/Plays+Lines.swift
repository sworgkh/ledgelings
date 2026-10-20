import Foundation

/// What they say as they play: a line as a game starts, in the voice of
/// whoever starts it, one for each game; and a line once it is over. Each
/// built-in character has its own; `anyone` is for a character the user made.
/// `{other}` is the one it plays tag with. The Russian is in `Plays+Russian.swift`.
extension Plays {

    /// The game in a few words, for a storyline: a stored `Plays.Kind` raw value.
    public static func name(of detail: String?) -> String {
        detail.flatMap(Kind.init(rawValue:))?.title ?? (detail ?? "")
    }

    public static let startSets = Translated(english: together(englishStartLines, englishBallStartLines),
                                             [.russian: together(russianStartLines, russianBallStartLines)])
    public static let startAnyone = Translated(english: englishStartAnyone.merging(englishBallStartAnyone) { a, _ in a },
                                               [.russian: russianStartAnyone.merging(russianBallStartAnyone) { a, _ in a }])

    /// Each character's lines for the first games and the ball games, in one table.
    static func together(_ a: [String: [String: String]], _ b: [String: [String: String]]) -> [String: [String: String]] {
        a.merging(b) { first, second in first.merging(second) { x, _ in x } }
    }
    public static let doneSets = Translated(english: englishDoneLines, [.russian: russianDoneLines])
    public static let doneAnyone = Translated(english: englishDoneAnyone, [.russian: russianDoneAnyone])

    /// The line `name` says as it starts `kind`; `other` is its partner at tag.
    public static func startLine(by name: String, _ kind: Kind, other: String) -> String {
        let line = startSets()[name]?[kind.rawValue] ?? startAnyone()[kind.rawValue] ?? ""
        return CursorMood.current.adjust(line.replacingOccurrences(of: "{other}", with: other))
    }

    /// The line `name` says once the game is over.
    public static func doneLine(by name: String, using rng: inout some RandomNumberGenerator) -> String {
        let pool = doneSets()[name] ?? doneAnyone()
        return CursorMood.current.adjust(pool.randomElement(using: &rng) ?? "")
    }

    public static let englishStartAnyone: [String: String] = [
        "tag": "Tag, {other}! You're it! Catch me if you can!",
        "rope": "Watch this: one rope, one ceiling, one hero.",
        "parachute": "Up to the top, and then... down, the slow way.",
        "basketball": "Hoop on the wall. Ball in hand. Let's see.",
    ]

    public static let englishDoneAnyone = [
        "Phew. That was fun. Again later?",
        "Out of breath, and very pleased with myself.",
    ]

    public static let englishStartLines: [String: [String: String]] = [
        // blocky's cast
        "Blocky": ["tag": "Fine. Tag, {other}, you're it. I'm not running fast. I'm running properly.",
                   "rope": "A rope. To the ceiling. I'll be back on the bottom edge in a second, where I belong.",
                   "parachute": "I'm going up only so I can come down. That is the only good reason to go up.",
                   "basketball": "A hoop. On a wall. Off the floor, at least the ball comes back down."],
        "Pip": ["tag": "{other}! Tag! Ha ha ha! You're it! Wheee!",
                "rope": "Rope! Ceiling! My two favourite things at once!",
                "parachute": "Up to the ceiling! And then I get to come down slowly! Best!",
                "basketball": "Basketball! I've never scored once! Today's the day! Ha!"],
        "Mortimer": ["tag": "*sighs* Very well, {other}. Chase me. Slowly, if you'd be so kind.",
                     "rope": "As my grandfather said: a rope is a staircase for the brave. He fell off one.",
                     "parachute": "One climbs the mountain only to float back down it. Such is life.",
                     "basketball": "The ball goes up. The ball comes down. Wisdom is knowing which comes first."],
        "Zed": ["tag": "Tag, {other}... you're it... wake me if you catch me...",
                "rope": "A hammock on a string... that swings... ooh, cosy...",
                "parachute": "Falling slowly... like falling asleep... but outside...",
                "basketball": "If I miss, I'll lie down. If I score, I'll also lie down."],
        "Dot": ["tag": "Tag, {other}! Catch me? With those legs? Ha!",
                "rope": "Rope swing. Fastest way across the screen. Watch, boulders.",
                "parachute": "Parachute? I'll still be first to the floor. Watch.",
                "basketball": "Three throws, three in. Count them, boulders."],
        "Ruth": ["tag": "Tag, {other}. Two minutes, clockwise only, no jumping. I mean it.",
                 "rope": "I disapprove of jumping. This is swinging. I have checked the rules.",
                 "parachute": "Parachute checked twice. Strings counted: four. Permission to fall: granted.",
                 "basketball": "Ten throws. I'll be keeping score. Somebody has to."],
        // cat
        "Whiskers": ["tag": "I'm not playing, {other}. I'm just leaving very quickly. You're it.",
                     "rope": "I don't care about the ceiling. I'm going up there anyway.",
                     "parachute": "I always land on my feet. I just want to do it slowly, for once.",
                     "basketball": "That ball. I don't want it. Watch me not want it into the hoop."],
        "Mittens": ["tag": "Mrrr... tag, {other}... chase me to the warm side...",
                    "rope": "A string! A big string! Purrrr... I must play with it...",
                    "parachute": "Floating down... like a feather... like a nap with wind...",
                    "basketball": "A ball to bat about... mrrp... into the little basket..."],
        "Sir Pounce": ["tag": "The hunt begins! {other}, you are it! Flee, noble prey!",
                       "rope": "Behold! The hunter takes to the vines!",
                       "parachute": "From the heights the hunter descends! Slowly! Majestically!",
                       "basketball": "I shall pounce upon the hoop! With a ball! Behold!"],
        // frog
        "Hopper": ["tag": "Tag, {other}! You'll never catch me! I'm the fastest hopper on any screen!",
                   "rope": "Watch me swing right across the screen! ...Well, most of it!",
                   "parachute": "Biggest jump ever! From the ceiling! I don't even need the parachute!",
                   "basketball": "Slam dunk! Watch me jump up there! ...I'll throw it. Same thing."],
        "Mossy": ["tag": "The pond chases the rain, {other}, and the rain chases the pond. You're it.",
                  "rope": "A reed bends but does not break. Let us see about a rope.",
                  "parachute": "A leaf falls slowly to the pond. So shall I.",
                  "basketball": "Throw a pebble at the pond and the pond throws ripples back."],
        "Croak": ["tag": "Fine, tag, {other}. Running. On this dry, dry edge. You're it.",
                  "rope": "A rope. Dry. Of course it is. Everything here is dry.",
                  "parachute": "Up I go. Down I come. Still no puddle at the bottom. Typical.",
                  "basketball": "A hoop with no water under it. What's the point. Fine."],
        // ghost
        "Boo": ["tag": "Boo! Tag, {other}! You're it! Boo!",
                "rope": "A spooky ghost on a spooky rope! Boo! ...wheee!",
                "parachute": "Ghosts float anyway, but the parachute is cute. Boo!",
                "basketball": "Boo! I'll scare the ball into the hoop!"],
        "Wisp": ["tag": "We played this on the old monitor, {other}. Catch me, as they did then.",
                 "rope": "Once I swung from the old taskbar. It's gone now. The rope remembers.",
                 "parachute": "Falling like the last leaf of the last wallpaper.",
                 "basketball": "There was a hoop on the old desktop. I never threw. I'll throw now."],
        "Sheet": ["tag": "Tag, {other}. Technically I'm gliding away from you.",
                  "rope": "Technically this isn't swinging. I'm a sheet on a rope. Laundry.",
                  "parachute": "A sheet with a parachute. That's two sheets. Technically.",
                  "basketball": "Technically I have no hands. Watch me throw anyway."],
        // mushroom
        "Morel": ["tag": "Tag... {other}... I'll be along... eventually...",
                  "rope": "Roots hang from the ceiling of a cave... so shall I...",
                  "parachute": "Spores ride the wind down... slowly... as shall I...",
                  "basketball": "A ball... into a basket... like a seed into soil..."],
        "Puff": ["tag": "Tag, {other}! Hee hee! Don't catch me or I'll spore!",
                 "rope": "Swinging! Hee! I might spore! I might!",
                 "parachute": "I'm a puffball with a parachute! Hee! Double puff!",
                 "basketball": "If I score I'm going to spore! Hee hee!"],
        "Cap": ["tag": "In my day, {other}, we played tag on the bottom edge only. You're it.",
                "rope": "In my day we climbed proper ropes. Hemp. Like this one, actually.",
                "parachute": "In my day we came down on a dandelion seed. This will do.",
                "basketball": "In my day the hoop was a walnut shell. Still never missed."],
        // robot
        "Unit 7": ["tag": "Tag protocol started. {other} status: it. My speed: 130 points per second.",
                   "rope": "Grapple angle: 40 degrees. Rope tension: adequate. Swinging in 3, 2, 1.",
                   "parachute": "Altitude: ceiling. Canopy: 1. Expected descent: 70 points per second.",
                   "basketball": "Trajectory computed. Probability of basket: 50%. Throwing."],
        "Sprocket": ["tag": "Tag, {other}! You're it! And after, I'll oil your knees!",
                     "rope": "Hook tight, rope sound, knot checked twice! Off I go!",
                     "parachute": "Strings tightened, canopy oiled! Wait, don't oil the canopy!",
                     "basketball": "I tightened the hoop bolts myself! Let's try them!"],
        "Glitch": ["tag": "Tag, {other}! You're it it! Unless the cursor is it. It might be.",
                   "rope": "Rope rope. Not a virus. I checked. Swinging.",
                   "parachute": "Jumping before the cursor can delete the ceiling ceiling.",
                   "basketball": "Ball in hoop. Not a virus. Throwing throwing."],
        // slime
        "Goop": ["tag": "Tag, {other}! Nice! You're it! Nice!",
                 "rope": "Rope! Sticky rope? No. Nice rope!",
                 "parachute": "Up. Then down slow. Nice!",
                 "basketball": "Ball! Hoop! Nice nice!"],
        "Puddle": ["tag": "Tag, {other}... you're it... please don't step on me when you catch me.",
                   "rope": "What if I drip off the rope? What if I evaporate up there? Okay. Going.",
                   "parachute": "Falling's not so bad if it's slow, right? Right? Slowly, please.",
                   "basketball": "What if the ball lands on me? It won't. It might. Throwing!"],
        "Blorp": ["tag": "Blorp! Tag, {other}! Boing boing!",
                  "rope": "Fwip! Whooosh! Blorp!",
                  "parachute": "Up up! Then... floooat. Pop!",
                  "basketball": "Ball! Fwoop! Swish? Swish!"],
        // triangle
        "Spike": ["tag": "Tag, {other}. You're it. Try not to touch the sharp end.",
                  "rope": "A rope, a hook, and a point to prove.",
                  "parachute": "Watch the canopy, everyone. Pointy things and parachutes, what could go wrong.",
                  "basketball": "Nothing but net. That's the point."],
        "Wedge": ["tag": "Tag, {other}. You're it. You won't knock me over, either.",
                  "rope": "I'll swing. But I land flat. Always flat.",
                  "parachute": "Steady descent. No wobbling. A wedge does not wobble.",
                  "basketball": "Stand square, throw straight. End of discussion."],
        "Delta": ["tag": "Tag, {other}. You're it. Let's see who's moved furthest by the end.",
                  "rope": "Start: floor. End: also floor, but further along. That's the change.",
                  "parachute": "Height now: ceiling. Height soon: floor. The difference is the fun.",
                  "basketball": "Last time the hoop was nowhere. Now it's there. Interesting."],
    ]

    public static let englishDoneLines: [String: [String]] = [
        // blocky's cast
        "Blocky": ["There. Back on the bottom edge. Where I belong.",
                   "That was acceptable. Don't tell anyone I said so."],
        "Pip": ["Again! Again! Ha ha! Let's do it again!",
                "Best game ever! Ha! I'm dizzy!"],
        "Mortimer": ["*puffs* At my age, one game is a whole afternoon.",
                     "A good game is like good tea: over too soon, and then you need a sit."],
        "Zed": ["That was nice... now I really need a nap...",
                "Wake me for the next one... or don't..."],
        "Dot": ["Too easy. Who's next, boulders?",
                "Did you see that? Of course you didn't. Too fast."],
        "Ruth": ["Game over. Rules: followed. Mostly.",
                 "Final score noted. I'll keep it on file."],
        // cat
        "Whiskers": ["I wasn't having fun. I was leaving quickly, on purpose.",
                     "Fine. That was fun. Why are you looking at me?"],
        "Mittens": ["Mrrr... all played out... time for the warm side...",
                    "Purrrr... that was lovely... nap now..."],
        "Sir Pounce": ["Victory! Or very nearly! The hunt was glorious!",
                       "The hunter rests. Briefly. Majestically."],
        // frog
        "Hopper": ["Did everyone see that? Biggest ever! Nobody saw. Okay!",
                   "I'm the best at that! Probably! Let's go again!"],
        "Mossy": ["The pond is still once the stone has sunk.",
                  "A frog that plays in the rain is never dry for long."],
        "Croak": ["Fine. That was fun. Still dry, though.",
                  "Out of breath, and no puddle to sit in. Typical."],
        // ghost
        "Boo": ["Boo! That was fun! Boo!",
                "Was I scary? I was scary. Boo!"],
        "Wisp": ["Just like the old days. The old days are gone. This was nice too.",
                 "Something to remember, when this screen is gone too."],
        "Sheet": ["Technically I didn't break a sweat. I can't.",
                  "Fun. Technically."],
        // mushroom
        "Morel": ["Good... now a long rest... in the shade...",
                  "That was... quick... for me..."],
        "Puff": ["Hee hee! I nearly spored! Nearly!",
                 "Again! Hee! Before I spore!"],
        "Cap": ["In my day that would have been called a fair game.",
                "Not bad. In my day we were better, mind you."],
        // robot
        "Unit 7": ["Game complete. Fun: 87%. Battery: 64%.",
                   "Play session logged. Recommend repeating within 24 hours."],
        "Sprocket": ["Everything still tight? Let me check your bolts!",
                     "Good game! Nothing came loose! Mostly!"],
        "Glitch": ["Done done. No viruses detected. Fun detected.",
                   "That was fun fun. The cursor didn't see. Good."],
        // slime
        "Goop": ["Nice! Fun! Nice!",
                 "Sticky now. Nice."],
        "Puddle": ["I didn't evaporate! I didn't! That was fun!",
                   "Phew. Still wet. Still here. Fun!"],
        "Blorp": ["Blorp! Whee! Pop!",
                  "Boing. Puff puff. Blorp!"],
        // triangle
        "Spike": ["Point made.",
                  "Nobody got poked. That's a win."],
        "Wedge": ["Still upright. Never in doubt.",
                  "Good game. Didn't tip once."],
        "Delta": ["Since the start: two of us out of breath. Big change.",
                  "Before: bored. After: not. Good difference."],
    ]

    // MARK: A line from the model

    /// One line as a game starts, when a model does the talking. The values are
    /// the speaker's (`{speaker}`, `{speakerKind}`, `{speakerPersona}`), the game
    /// (`{play}`), who else plays (`{others}`) and the moment (`{situation}`).
    public static let placeholders = ["speaker", "speakerKind", "speakerPersona", "play", "others", "situation"]

    public static let lineSystemPrompts = Translated(english: englishLineSystemPrompt, [.russian: russianLineSystemPrompt])
    public static var lineSystemPrompt: String { lineSystemPrompts() }
    public static let englishLineSystemPrompt = "You speak as one small character on a computer screen. Answer with one short line, nothing else."

    public static let linePrompts = Translated(english: englishLinePrompt, [.russian: russianLinePrompt])
    public static var linePrompt: String { linePrompts() }

    public static let englishLinePrompt = """
    You are {speaker}, {speakerKind}, one of the small creatures that live on the edges of a computer screen. \
    {speakerPersona}
    {situation}
    You are about to start {play}{others}. Say one short line as you start, at most 15 words, in your own voice. \
    Answer with the line only: no name, no quotes.
    """
}

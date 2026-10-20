import Foundation

/// What they say during soccer and baseball, in each character's own voice:
/// the start line for each (merged into `Plays.startSets`), and a line for the
/// big moments: a goal, a home run, an "oops" (a kick at the air, a dropped
/// catch, a strike-out) and wandering off in the middle of it. `anyone` is for a
/// character the user made. The Russian is in `Plays+BallRussian.swift`.
extension Plays {

    /// A moment in a ball game worth a line.
    public enum Moment: String, CaseIterable, Sendable {
        case goal, homeRun, oops, wander

        /// What just happened, for the model's prompt.
        public var happening: String {
            switch self {
            case .goal: tr("you have just scored a goal")
            case .homeRun: tr("you have just hit a home run, right off the top of the screen")
            case .oops: tr("you have just missed the ball in a silly way")
            case .wander: tr("you are wandering off in the middle of the game to look at something")
            }
        }

        /// Worth a line from the model, when one does the talking: the high points only.
        public var asksTheModel: Bool { self == .goal || self == .homeRun }
    }

    public static let cheerSets = Translated(english: englishCheerLines, [.russian: russianCheerLines])
    public static let cheerAnyone = Translated(english: englishCheerAnyone, [.russian: russianCheerAnyone])

    /// The line `name` says at `moment`.
    public static func cheerLine(by name: String, _ moment: Moment) -> String {
        CursorMood.current.adjust(cheerSets()[name]?[moment.rawValue] ?? cheerAnyone()[moment.rawValue] ?? "")
    }

    public static let englishBallStartAnyone: [String: String] = [
        "soccer": "A ball, a net, a long floor. Let's play!",
        "baseball": "Bases on the edges. Batter up!",
    ]

    public static let englishCheerAnyone: [String: String] = [
        "goal": "Goal! Did you see that?",
        "homeRun": "Home run! Right off the screen!",
        "oops": "Oops. That didn't go where I meant.",
        "wander": "Back in a moment, I just want to look at something.",
    ]

    public static let englishBallStartLines: [String: [String: String]] = [
        // blocky's cast
        "Blocky": ["soccer": "Soccer. On the floor. Finally a game that stays on the bottom edge.",
                   "baseball": "Baseball across every edge. Fine. I'll bat from the floor, like a sensible block."],
        "Pip": ["soccer": "Soccer! Pass to me! Pass to me! Ha ha!",
                "baseball": "Baseball! I'm going to hit it to the moon! Or the ceiling!"],
        "Mortimer": ["soccer": "*sighs* A ball and two nets. My grandfather played with one net and no ball.",
                     "baseball": "Baseball. In my youth we ran the bases uphill. Both ways."],
        "Zed": ["soccer": "Soccer... lots of running... I'll be the one lying in the goal...",
                "baseball": "Baseball... there's a lot of standing about... I like that bit..."],
        "Dot": ["soccer": "Soccer? Try to keep up, boulders. I'll be at the other end already.",
                "baseball": "Bases on every edge? I'll touch them all before you blink."],
        "Ruth": ["soccer": "Soccer. First to the goals in the settings. No hands. I'll be watching.",
                 "baseball": "Three strikes, two outs, bases in order. Rules are rules."],
        // cat
        "Whiskers": ["soccer": "I don't chase balls. I'm just walking toward the goal with it.",
                     "baseball": "Hit a ball, run round the edges. Fine. I was going that way."],
        "Mittens": ["soccer": "Mrrr... a ball to roll about... I'll play near the warm side...",
                    "baseball": "Purrr... a little white ball... I want to bat it..."],
        "Sir Pounce": ["soccer": "The hunt begins! The ball is my prey, the net its den!",
                       "baseball": "Behold! The hunter strikes the white bird from the sky!"],
        // frog
        "Hopper": ["soccer": "SOCCER! Watch me jump over everyone with the ball! Probably!",
                   "baseball": "I'll hop every base in one go! Biggest hops on the screen!"],
        "Mossy": ["soccer": "The ball rolls as the pond ripples: slowly, and back again.",
                  "baseball": "A ball hit far is a stone thrown in a pond. It comes down somewhere."],
        "Croak": ["soccer": "Soccer on a dry floor. Dust everywhere. Fine, kick it.",
                  "baseball": "Baseball. Running round dry edges in the sun. Lovely. Let's go."],
        // ghost
        "Boo": ["soccer": "Boo! Did I scare the ball? It's going in the net from fright!",
                "baseball": "Boo! I'll scare the ball right off the bat!"],
        "Wisp": ["soccer": "A ball on the floor of this screen... I played once on a screen long gone.",
                 "baseball": "Bases round the edges, like the corners of old monitors..."],
        "Sheet": ["soccer": "Soccer. I'll kick it. Technically with my hem.",
                  "baseball": "Baseball. I don't run. I hover between bases. Same rules apply."],
        // mushroom
        "Morel": ["soccer": "Soccer... slowly... the ball comes to those who wait in the right place.",
                  "baseball": "Baseball... patience at the plate... the good pitch always comes."],
        "Puff": ["soccer": "Hee hee! Soccer! If I score I'll release spores! Hee!",
                 "baseball": "Baseball! Hit it hard and... puff! Hee hee!"],
        "Cap": ["soccer": "In my day the nets had holes and we liked it. Kick off.",
                "baseball": "In my day we hit the ball with a twig. Give me that bat."],
        // robot
        "Unit 7": ["soccer": "Soccer protocol loaded. Pitch width: maximum. Goal probability: 34%.",
                   "baseball": "Baseball routine started. Bases: 3. Edges: 4. Strikes allowed: 2."],
        "Sprocket": ["soccer": "Soccer! Let me check the nets are tight first. Good. Kick off!",
                     "baseball": "Baseball! I oiled the bat. It'll swing like new."],
        "Glitch": ["soccer": "Soccer soccer. Watch out, the cursor might be a defender.",
                   "baseball": "Baseball ball. If the cursor pitches, I'm not swinging."],
        // slime
        "Goop": ["soccer": "Soccer! Nice! The ball might get sticky!",
                 "baseball": "Baseball! Nice! I'll stick to the bases!"],
        "Puddle": ["soccer": "Soccer? What if I get kicked? What if I splash? Okay. Okay. Let's play.",
                   "baseball": "Baseball... what if the ball lands on me? I'll stand very still. Okay."],
        "Blorp": ["soccer": "Blorp! Ball! Boing boing! Kick!",
                  "baseball": "Bat! Ball! THWACK! Blorp!"],
        // triangle
        "Spike": ["soccer": "Soccer. Pointy end goes forward. Try to keep up.",
                  "baseball": "Baseball. I'll make my point at the plate."],
        "Wedge": ["soccer": "Soccer. Nothing gets past a wedge. Nothing.",
                  "baseball": "Baseball. No pitch is going to tip me over."],
        "Delta": ["soccer": "Soccer: the score changes, the ball changes sides. I'll track the difference.",
                  "baseball": "Baseball: every hit changes who is where. I'll notice."],
    ]

    public static let englishCheerLines: [String: [String: String]] = [
        // blocky's cast
        "Blocky": ["goal": "Goal. Don't cheer. It went in because I kicked it properly.",
                   "homeRun": "Over the top and gone. Good. Nobody fetch it.",
                   "oops": "That was the edge's fault. The edge is crooked.",
                   "wander": "I'm not leaving. I'm checking the corner is still square."],
        "Pip": ["goal": "GOAL! GOAL! Did you see? A goal! Wheee!",
                "homeRun": "It flew right off the screen! Ha ha ha! Bye, ball!",
                "oops": "Whoops! My foot went one way and the ball went the other! Ha!",
                "wander": "Ooh, a shiny pixel! Back in a second!"],
        "Mortimer": ["goal": "*wheezes* There. Still got it, at my age.",
                     "homeRun": "Off it goes. As my grandfather said: let it go, it is not coming back.",
                     "oops": "My knees, I'm afraid, have retired from this sort of thing.",
                     "wander": "Excuse me. I must sit down somewhere for a moment."],
        "Zed": ["goal": "Oh... it went in... nice... can I lie down now...",
                "homeRun": "It's gone... over the top... I'll walk the bases... slowly...",
                "oops": "Missed... I was resting my eyes...",
                "wander": "Just going to... rest over there... a little..."],
        "Dot": ["goal": "Goal! Fastest feet on the screen. Told you, boulders.",
                "homeRun": "Home run! I'd have run it anyway. Faster than the ball.",
                "oops": "That didn't count. I was going too fast for it.",
                "wander": "Boring. I'll lap the screen and come back."],
        "Ruth": ["goal": "Goal, scored fairly, from inside the pitch. Noted.",
                 "homeRun": "Home run. Over the top is out of the field: entirely legal.",
                 "oops": "That was not a mistake. That was a procedural miss.",
                 "wander": "I'm checking the pitch markings. Carry on without me."],
        // cat
        "Whiskers": ["goal": "It went in. I meant that. I always mean it.",
                     "homeRun": "I didn't watch where it went. Not interesting. ...Where did it go?",
                     "oops": "I let it pass. On purpose.",
                     "wander": "I'll be over here. Not because of you."],
        "Mittens": ["goal": "Mrrrow! It rolled into the little net! Purrr...",
                    "homeRun": "Mrrp! It flew away like a bird... purrr...",
                    "oops": "Mew... my paw was too slow...",
                    "wander": "Mrrr... there's a warm spot over there..."],
        "Sir Pounce": ["goal": "The prey is caught! Into the net! Victory to the hunter!",
                       "homeRun": "It escapes into the heavens! Even prey must fly sometimes!",
                       "oops": "A feint! The hunter was merely testing the prey!",
                       "wander": "The hunter senses other prey! Hold the game!"],
        // frog
        "Hopper": ["goal": "GOAL! Did you see that jump? Okay, there was no jump. GOAL!",
                   "homeRun": "HOME RUN! Higher than I've ever jumped! Which is very high!",
                   "oops": "I meant to jump over it. I just... didn't.",
                   "wander": "Hang on, I'm going to practise a jump over there!"],
        "Mossy": ["goal": "The pond is patient. And so the ball went in.",
                  "homeRun": "Over the top, like a frog leaving the pond. It will find another.",
                  "oops": "A lily pad does not chase the fly. Neither, it seems, do I.",
                  "wander": "I'm going to look for something damp. It won't take long."],
        "Croak": ["goal": "Goal. Still too dry. But goal.",
                  "homeRun": "Gone over the top. Good. Somewhere damper, I hope.",
                  "oops": "This edge is too dry to kick on. That's why.",
                  "wander": "I'm off to find a damp corner. Don't wait."],
        // ghost
        "Boo": ["goal": "BOO! Goal! The keeper was too scared to move!",
                "homeRun": "BOO! The ball was so scared it flew off the screen!",
                "oops": "Boo... the ball wasn't scared at all...",
                "wander": "I'm going to go and haunt that corner. Boo."],
        "Wisp": ["goal": "It drifts into the net, like a memory into place.",
                 "homeRun": "Up and out, past the top... where the old monitors went...",
                 "oops": "It slipped by me, like time.",
                 "wander": "I'll float over there a while... the light is like it used to be."],
        "Sheet": ["goal": "Goal. Technically I nudged it. It counts.",
                  "homeRun": "Home run. The ball is now technically outside.",
                  "oops": "I missed. Technically I was never there.",
                  "wander": "I'm going over there. Technically floating."],
        // mushroom
        "Morel": ["goal": "It went in... the way roots find water. Quietly.",
                  "homeRun": "Up and away... like spores on the wind.",
                  "oops": "Too slow... but slow is how we grow.",
                  "wander": "I'll stand in that damp corner a while. Don't mind me."],
        "Puff": ["goal": "Hee hee! GOAL! Spores everywhere! Sorry! Hee!",
                 "homeRun": "Puff! Hee hee! It flew off like a spore!",
                 "oops": "Hee... missed... puff...",
                 "wander": "Hee hee, I'm going to giggle in the corner for a bit!"],
        "Cap": ["goal": "In my day that would have been a goal too. Still is.",
                "homeRun": "In my day the screen had no top. That one's gone for good.",
                "oops": "In my day the ball stood still for you.",
                "wander": "In my day we took a little rest mid-game. I still do."],
        // robot
        "Unit 7": ["goal": "Goal confirmed. Score updated. Celebration level: 100%.",
                   "homeRun": "Home run. Ball altitude: off screen. Tracking lost. Excellent.",
                   "oops": "Error. Ball not found at expected coordinates.",
                   "wander": "Running a diagnostic over there. Estimated time: 6 seconds."],
        "Sprocket": ["goal": "Goal! The net held! Well-maintained nets, those.",
                     "homeRun": "Home run! That bat needs no tightening at all!",
                     "oops": "My left foot needs a tune-up. I'll see to it later.",
                     "wander": "Hold on, a loose bolt over there! Back in a jiffy!"],
        "Glitch": ["goal": "Goal goal! That was not a virus. That was skill.",
                   "homeRun": "Home run run! Out of the screen, away from the virus!",
                   "oops": "Missed missed. The cursor did it. Probably.",
                   "wander": "Scanning that corner corner for viruses. Back soon."],
        // slime
        "Goop": ["goal": "Goal! Nice! Very nice!",
                 "homeRun": "Home run! So nice! Bye bye, ball!",
                 "oops": "Oops! Sticky foot!",
                 "wander": "Ooh, a nice spot over there!"],
        "Puddle": ["goal": "A goal? And no evaporating? A goal!",
                   "homeRun": "It went off the screen! Is that allowed? It's allowed? Oh good.",
                   "oops": "Oh no, oh no, missed it, sorry, I'm drying out...",
                   "wander": "I need a moment in the shade. Just a moment."],
        "Blorp": ["goal": "SPLOOSH! In! Blorp blorp!",
                  "homeRun": "THWACK! Wheeeee! Gone! Blorp!",
                  "oops": "Whiff. Blorp.",
                  "wander": "Bloop bloop... over there..."],
        // triangle
        "Spike": ["goal": "Goal. Point made.",
                  "homeRun": "Home run. Sharp, wasn't it?",
                  "oops": "That miss was the pitch's fault. Point taken.",
                  "wander": "I've made my point here. Off to make it there."],
        "Wedge": ["goal": "Goal. I said I wouldn't budge from the plan.",
                  "homeRun": "Home run. Steady stance. Never tipped.",
                  "oops": "I did not slip. I adjusted my angle.",
                  "wander": "I'm standing over there now. It's my decision."],
        "Delta": ["goal": "Goal. Difference: plus one.",
                  "homeRun": "Home run. The ball's position changed by a whole screen.",
                  "oops": "Note: the ball moved, I didn't. Large difference.",
                  "wander": "Something moved over there. Must check."],
    ]

    // MARK: A line from the model

    /// One line at a big moment (`{moment}`, `Moment.happening`) of `{play}`, with the score (`{score}`).
    public static let cheerPlaceholders = ["speaker", "speakerKind", "speakerPersona", "play", "moment", "score", "situation"]

    public static let cheerPrompts = Translated(english: englishCheerPrompt, [.russian: russianCheerPrompt])
    public static var cheerPrompt: String { cheerPrompts() }

    public static let englishCheerPrompt = """
    You are {speaker}, {speakerKind}, one of the small creatures that live on the edges of a computer screen. \
    {speakerPersona}
    {situation}
    You are playing {play}, and {moment}. The score: {score}. Say one short line about it, at most 12 words, \
    in your own voice: proud, silly or surprised, as you would be. Answer with the line only: no name, no quotes.
    """
}

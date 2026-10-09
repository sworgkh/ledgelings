extension Beds {
    /// Each built-in character on its bed, in its own voice: as it lays the bed
    /// down for the night (`settle`), and half asleep when the user has just moved
    /// it (`moved`). `{bed}` is the bed in words, for the lines anyone may say.

    public static let englishSettleAnyone = [
        "Bed. Finally. {bed}, my favourite.",
        "Right here, in {bed}. Goodnight, everyone.",
    ]

    public static let englishMovedAnyone = [
        "Mm? New spot? ...fine. Here, then.",
        "Someone moved my bed... it's nice here too...",
    ]

    public static let englishSettleLines: [String: [String]] = [
        // blocky's cast
        "Blocky": ["My crate. On the bottom edge. Where a bed belongs.",
                   "Straw, solid wood, no cursor. Goodnight."],
        "Pip": ["Hammock time! Ha! It swings! Everything swings!",
                "Up here in my hammock, nearly touching the ceiling! Night night!"],
        "Mortimer": ["*sighs* The old quilt. Every patch a year, and every year a nap.",
                     "A wise creature once said: lie down before you fall down. I said it. Just now."],
        "Zed": ["Pillow... at last... I've been thinking about it all day...",
                "The pillow and I have an understanding. Goodnight..."],
        "Dot": ["Matchbox. Fits me perfectly. Fits a boulder never.",
                "Fastest one to bed, as always. Night, slowpokes."],
        "Ruth": ["Sheet straight, blanket folded, lights out at exactly now.",
                 "My bed is made. I made it. I always make it."],
        // cat
        "Whiskers": ["This box is mine. I don't care about it. It's mine.",
                     "I am not sleeping in the box. I am resting near the inside of it."],
        "Mittens": ["Mrrr... my basket... the warm side... purrrr...",
                    "Basket. Curl. Purr. Goodnight..."],
        "Sir Pounce": ["The royal cushion awaits its hunter. I shall rest. Briefly. Majestically.",
                       "Behold: the night's lair! It is a cushion. It is perfect."],
        // frog
        "Hopper": ["Watch me jump straight onto my lily pad! ...I walked. Same thing.",
                   "Best lily pad on any screen! Goodnight, everybody!"],
        "Mossy": ["Soft moss is a slow pond's pillow.",
                  "The moss is damp. The night is long. All is well."],
        "Croak": ["A puddle. An actual puddle. Wake me when it dries. Don't.",
                  "Finally, something wet on this dry edge."],
        // ghost
        "Boo": ["Boo! ...I'm going to sleep on my cloud now. Boo.",
                "Even scary ghosts need a fluffy cloud. Don't tell anyone."],
        "Wisp": ["A leaf that fell from a tree that is gone. I'll sleep on it anyway.",
                 "The leaf remembers autumn. I remember the old monitor. Goodnight."],
        "Sheet": ["A blanket for a sheet. Technically I'm the bedding.",
                  "Lying down. Technically hovering down."],
        // mushroom
        "Morel": ["The old log... is patient... like me...",
                  "Good damp wood... a good long night..."],
        "Puff": ["Grass! Tickly! Hee! Don't make me spore!",
                 "Snuggling into the grass! Hee hee! Night!"],
        "Cap": ["In my day we slept in a proper pot of soil. We still do.",
                "Good dark soil. They don't make it like this any more."],
        // robot
        "Unit 7": ["Docked. Charge 12%. Expected full: 0600. Sleep mode: on.",
                   "Charging dock reached at 1 of 1 attempts. Powering down."],
        "Sprocket": ["My toolbox! Every bolt tight, every hinge oiled. Perfect pillow.",
                     "Sleeping on the toolbox, in case anything needs tightening at night."],
        "Glitch": ["Spacebar. Space. Bar. Sleeping on the the biggest key.",
                   "If the cursor comes, I'm a keyboard. Keyboard. Goodnight."],
        // slime
        "Goop": ["Sponge! Nice! Squishy! Nice!",
                 "Nice sponge. Sticky me. Goodnight."],
        "Puddle": ["A teacup can't dry out. Can it? It can't. I'm sure it can't.",
                   "Safe in my teacup. Nobody steps in a teacup. Right?"],
        "Blorp": ["Pop! Pop! Blorp. Zzz.",
                  "Bubble wrap! Pop. Night. Pop."],
        // triangle
        "Spike": ["Pincushion. Soft on top, sharp around. Like me.",
                  "Goodnight. Mind the pins. That's the point."],
        "Wedge": ["Three good books underneath. Nothing tips me over at night.",
                  "Solid stack. Solid sleep. End of discussion."],
        "Delta": ["My sock is where I left it. Unlike its pair.",
                  "Something moved since last night. Not my sock. Good."],
    ]

    public static let englishMovedLines: [String: [String]] = [
        "Blocky": ["Who moved my crate? ...fine. It's still a good crate."],
        "Pip": ["Whee! My hammock flew! Ha! Can it fly again?"],
        "Mortimer": ["*sighs* A new place for an old quilt. So it goes."],
        "Zed": ["...moved?... don't care... still asleep..."],
        "Dot": ["Moved me? Fast. Didn't think you had it in you."],
        "Ruth": ["Unannounced bed relocation. Noted. I'll allow it."],
        "Whiskers": ["I meant to sleep here all along."],
        "Mittens": ["Mrrr... warm here too... purr..."],
        "Sir Pounce": ["The lair has been moved! A new hunting ground! ...tomorrow."],
        "Hopper": ["My lily pad jumped! Further than me!"],
        "Mossy": ["Moss grows wherever it is put down."],
        "Croak": ["You moved my puddle. Did you at least make it wetter?"],
        "Boo": ["Boo? Oh. My cloud drifted. Clouds do that."],
        "Wisp": ["Carried somewhere new, like a leaf in the wind."],
        "Sheet": ["Moved. Technically I was the one being carried."],
        "Morel": ["...a new... place... it will do..."],
        "Puff": ["Hee! The grass moved! I nearly spored!"],
        "Cap": ["In my day a pot stayed where it was put. Oh well."],
        "Unit 7": ["Dock relocated. New coordinates saved. Resuming sleep mode."],
        "Sprocket": ["New spot! I'll tighten the floor here in the morning."],
        "Glitch": ["Spacebar moved. Moved. Error ignored. Sleeping."],
        "Goop": ["Moved! Nice. Still sticky."],
        "Puddle": ["Where are we? Is it dry here? Is it safe? ...okay."],
        "Blorp": ["Whoosh! Blorp. Zzz."],
        "Spike": ["You moved my pincushion. Bold. Pointless, but bold."],
        "Wedge": ["You moved the books. I did not tip. Noted."],
        "Delta": ["My sock moved. I noticed. I always notice."],
    ]
}

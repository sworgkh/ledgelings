extension Complaints {
    /// The good and neutral cursor moods' versions of a complaint (`CursorMood`):
    /// past the limit a creature still speaks up, in its own voice, but in the
    /// good mood it is a playmate teasing back after a game of tag, and in the
    /// neutral one a passing remark, neither pleased nor annoyed. The bad mood's
    /// lines are the originals in `Complaints.swift`.
    public static let englishGoodAnyone = [
        "Ha! That's {times} times, and you still haven't caught me!",
        "Tag! You're it! Again, again!",
    ]

    public static let englishNeutralAnyone = [
        "{times} hops in a row. Oh well.",
        "Moved again. That's how it goes.",
    ]

    public static let englishGoodLines: [String: [String]] = [
        // blocky's cast
        "Blocky": ["{times} times and you still haven't caught me. Not that I'm counting. I am.",
                   "Fine. That was almost fun. Tell anyone and I'll deny it."],
        "Pip": ["Again! Again! That's {times}! Tag, you're it!",
                "Wheee! Best game ever! Chase me to the ceiling!"],
        "Mortimer": ["*chuckles* {times} times. In my youth I'd have led you a merrier dance.",
                     "Ah, a game of tag. My knees object, but my heart is young."],
        "Zed": ["{times} times... fine, *yawn*, you win this round. Nap first, rematch later.",
                "Tag is fun... sleepy fun... can we play lying down..."],
        "Dot": ["{times} tries and still not even close. Again, slowpoke!",
                "Too fast for you! Come on, one more lap!"],
        "Ruth": ["Score: me {times}, you nought. Best of fifty?",
                 "Rule two of tag: I win. You may try again."],
        // cat
        "Whiskers": ["{times} times. I let you chase me. That's how a cat says it likes you.",
                     "Fine, it's a game. I'm only playing because I want to."],
        "Mittens": ["Mrrrow! {times} times! Again, then a nap, then again!",
                    "Purr... a chase and then a cuddle? Yes please."],
        "Sir Pounce": ["{times} pounces dodged! The hunter salutes a worthy foe!",
                       "Ha! None catch Sir Pounce! Try again, brave hunter!"],
        // frog
        "Hopper": ["{times} jumps! New record! Again, again, again!",
                   "RIBBIT! Chase me higher! I can jump all the way across!"],
        "Mossy": ["{times} ripples on the pond. A pleasant game, friend.",
                  "The frog who plays tag never grows old. Again, if you like."],
        "Croak": ["{times}. Fine. It was fun. Don't let it go to your head.",
                  "Grumble. That was... not terrible. Once more, then water."],
        // ghost
        "Boo": ["Boo! {times} times and you never caught me! Spooky AND fast!",
                "Hee hee! My turn to chase you next!"],
        "Wisp": ["{times} times we drifted round each other. Almost a dance.",
                 "How lovely, to be chased by someone who only wants to play."],
        "Sheet": ["{times} times. Technically I won every one of them.",
                  "Technically, this is the best game on the screen."],
        // mushroom
        "Morel": ["{times}... chases... slow fun... the best kind...",
                  "Again... but slower... mushrooms like... slow games..."],
        "Puff": ["Eee! {times} times! I'm so happy I could spore!",
                 "Hee hee! Again! *puff* *puff*"],
        "Cap": ["In my day we played tag too. {times} rounds! You'd have done well.",
                "Young people and their games. ...All right, one more."],
        // robot
        "Unit 7": ["Game log: {times} successful evasions. Enjoyment: 97%.",
                   "Tag protocol active. Score: Unit 7 leading. Continue?"],
        "Sprocket": ["{times} jumps! My gears are spinning with joy!",
                     "Whee! Fully oiled and ready for another round!"],
        "Glitch": ["{times} times! The cursor cursor is fun fun. Again again.",
                   "Scan complete: this is a game. Playing playing."],
        // slime
        "Goop": ["Wheee! {times} times! Sticky fun!",
                 "Again! I'll bounce extra high!"],
        "Puddle": ["{times} times and I didn't even splash! Was I good? Can we go again?",
                   "Oh! Oh! That was fun! Only a little scary!"],
        "Blorp": ["Blorp! {times}! Fun! Again!",
                  "Zoom zoom! Blorp win!"],
        // triangle
        "Spike": ["{times} times, and I'm still the sharpest at tag. Point made.",
                  "You'll need a sharper aim than that. Again."],
        "Wedge": ["{times} tries and I'm still on my spot. Good game. Try again.",
                  "You won't tag me. But I like that you keep trying."],
        "Delta": ["Change logged: {times} chases. Mood: improved. Again.",
                  "Interesting: being chased is fun now. Noted."],
    ]

    public static let englishNeutralLines: [String: [String]] = [
        // blocky's cast
        "Blocky": ["{times} times. Noted. Back to my edge.",
                   "There it goes again. Moving on."],
        "Pip": ["Ooh, {times} hops in a row! Okay! Back to the ceiling!",
                "Hop! That's just how it goes sometimes!"],
        "Mortimer": ["{times} times. The world moves, and so do I. Slowly.",
                     "*sighs* Hop, hop. Such is life on an edge."],
        "Zed": ["{times} hops... okay... *yawn*... where was I...",
                "Moved again... fine... still sleepy..."],
        "Dot": ["{times} hops. Barely noticed. Too fast to care.",
                "Hop. Done. Next."],
        "Ruth": ["That is {times} hops in a row. Recorded. No further comment.",
                 "Counted: {times}. Carrying on."],
        // cat
        "Whiskers": ["{times} times. Whatever. I wasn't sitting there anyway.",
                     "Hmph. Moved. Doesn't matter."],
        "Mittens": ["Mrrp. {times} times. I'll find another warm spot.",
                    "Mrrow... moved again. Fine. More sun over here."],
        "Sir Pounce": ["{times} retreats. Strategic ones, naturally.",
                       "A small hop for a cat. Nothing more."],
        // frog
        "Hopper": ["{times} hops! Hops are hops!",
                   "Ribbit. Hopped. Nice."],
        "Mossy": ["{times} ripples. The pond does not mind.",
                  "Water moves. Frogs move. It is so."],
        "Croak": ["{times}. Hmph. Whatever.",
                  "Moved again. Still dry. Same as ever."],
        // ghost
        "Boo": ["{times} times! Huh. Ghosts drift, I guess!",
                "Whoosh! Moved. Anyway!"],
        "Wisp": ["{times} times I drifted. Drifting is what I do.",
                 "Here, then there. It's all the same to me."],
        "Sheet": ["{times} times. Technically, I just floated somewhere else.",
                  "Technically, this is fine."],
        // mushroom
        "Morel": ["{times}... moved... it's all... soil...",
                  "Somewhere else... is also... damp enough..."],
        "Puff": ["{times} hops! Okay! *puff*",
                 "Hee, moved again. Whatever!"],
        "Cap": ["{times} times. In my day we moved too. It's what edges are for.",
                "Hm. Moved again. Such is the way of things."],
        // robot
        "Unit 7": ["Relocations logged: {times}. Status: normal.",
                   "Position changed. No action required."],
        "Sprocket": ["{times} jumps! Gears still fine!",
                     "Moved. Everything still tight. Carry on!"],
        "Glitch": ["Relocated relocated: {times} times. No virus found.",
                   "Moved moved. Nothing to report report."],
        // slime
        "Goop": ["{times} bounces! Okay!",
                 "Boing. Moved. Still sticky."],
        "Puddle": ["{times} times... oh. Well. I'm still here.",
                   "Moved again. Didn't spill. That's good."],
        "Blorp": ["Blorp. {times}. Okay.",
                  "Zoom. Blorp fine."],
        // triangle
        "Spike": ["{times} times. Doesn't change my angle.",
                  "Moved. Still sharp."],
        "Wedge": ["{times} times. I'll settle back where I was.",
                  "Moved a bit. I'll be back on my spot."],
        "Delta": ["Change since last time: {times} hops. Nothing else.",
                  "Noticed: I moved. That's all."],
    ]

    public static let englishGoodPrompt = """
    {situation}
    The person whose screen you live on keeps chasing you with the mouse cursor and picking you up: \
    {times} times in a row now. To you it is a game of tag, and you love it. Say ONE line to them, playful and teasing, in your own voice. \
    At most 20 words. Output only the line: no quotes, no name.
    """

    public static let englishNeutralPrompt = """
    {situation}
    The person whose screen you live on has moved you about with the mouse cursor and picked you up: \
    {times} times in a row now. It means nothing to you: it just happens. Say ONE line to them about it, \
    a passing remark in your own voice, neither pleased nor annoyed. \
    At most 20 words. Output only the line: no quotes, no name.
    """
}

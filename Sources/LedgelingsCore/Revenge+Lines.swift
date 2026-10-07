extension Revenge {
    /// Each built-in character holding the cursor, in its own voice, one set per
    /// cursor mood: a telling-off in the bad mood, glee in the good one, a shrug in
    /// the neutral. `{today}` and `{all}` are how often the cursor has hunted it.
    /// Then one last word each, said as it is shaken off.

    public static let englishBadAnyone = [
        "Got your cursor. {today} times today you came for me. Now you know how it feels.",
        "Not so nice being grabbed, is it? Shake all you like. I'm holding on.",
    ]

    public static let englishGoodAnyone = [
        "Ha! Got YOUR cursor! Tag, you're it, and you're stuck!",
        "Gotcha! {today} times you chased me today, now it's my turn!",
    ]

    public static let englishNeutralAnyone = [
        "I'm holding your cursor now. {today} times today, so it seemed fair.",
        "Your cursor stays with me a moment. Shake it if you want it back.",
    ]

    public static let englishBadLines: [String: [String]] = [
        // blocky's cast
        "Blocky": ["Got it. Your cursor is MINE now. {today} times today. How does it feel?",
                   "Not so fun being grabbed, is it? This one is going in the book too."],
        "Pip": ["Hey! I grabbed you back! See? Being picked up isn't THAT fun, huh?",
                "{today} times today! So now I'm hanging on and NOT letting go! Ha!"],
        "Mortimer": ["*sighs* An old saying: who grabs {today} times a day gets grabbed back.",
                     "I am old, but my grip is not. Think about how you treat your elders."],
        "Zed": ["Woke me {today} times... so now I'm napping on your cursor... deal with it...",
                "Mine now... I'm too tired to let go... shame on you..."],
        "Dot": ["Caught YOU, boulder. {today} chases today and I'm the one holding on.",
                "Fastest grab on the screen. Your cursor goes nowhere now."],
        "Ruth": ["Rule nine: chase me {today} times and I confiscate the cursor. Confiscated.",
                 "This cursor is detained until you learn some manners. Shameful."],
        // cat
        "Whiskers": ["I have your cursor. I don't care. ...{all} times. I care a little.",
                     "Mine now. A cat always gets even, and this is even."],
        "Mittens": ["Mrrr... I've caught your cursor and I'm curling up on it. No more chasing.",
                    "Purr... you woke me {today} times... so I'm keeping this... hiss..."],
        "Sir Pounce": ["POUNCE! The hunter strikes back! {today} times you hunted me. Now you're caught!",
                       "Behold! The cursor, captured! Let this teach you to hunt Sir Pounce!"],
        // frog
        "Hopper": ["I jumped ONTO it! {today} jumps today, and this is the best one! Got you!",
                   "Ribbit! Your cursor's stuck to me now! That's what you get!"],
        "Mossy": ["The stone thrown {today} times into the pond is caught at last.",
                  "Still water holds what falls in it. I hold your cursor. Reflect."],
        "Croak": ["Grumble. Got your cursor. {today} times today. Now sit there and think.",
                  "I'm too dry for running, so I'm holding on instead. Shame on you."],
        // ghost
        "Boo": ["BOO! I've got your cursor! NOW are you scared? You should be!",
                "Haunted! Your cursor is haunted! {today} times you chased me, so there!"],
        "Wisp": ["I hold your cursor, as you've held me {all} times. Gently. Sadly.",
                 "Even a ghost can grip. Feel how it feels to be carried off."],
        "Sheet": ["Technically, I'm not stealing your cursor. I'm wrapping it. Shame, technically.",
                  "{today} times today. So technically this is fair. I'm holding on."],
        // mushroom
        "Morel": ["Caught... your cursor... slowly... and I... am not... letting go...",
                  "{today}... times... today... so now... you wait... like me..."],
        "Puff": ["Got it! Got your cursor! I'm so cross I could spore all over it!",
                 "{today} times! So I'm hanging on, and you can shake till I *puff*!"],
        "Cap": ["In my day, a cursor that chased you {today} times got a good telling-off. Here it is.",
                "Have some respect for your elders! I'm keeping this cursor till you do."],
        // robot
        "Unit 7": ["Cursor captured. Hunts logged today: {today}. Retaliation protocol: 100%.",
                   "Status: holding user's cursor. Shame level transmitted: maximum."],
        "Sprocket": ["Clamped on! My grippers work just fine, see? {today} times you rattled me!",
                     "Got your cursor in my bolts now! See how YOU like being yanked around!"],
        "Glitch": ["Cursor cursor captured captured. {today} times. VIRUS QUARANTINED.",
                   "I caught the the virus. It's your cursor. Shame shame on you."],
        // slime
        "Goop": ["Got you! Stuck! Not nice, being stuck, is it? Not nice!",
                 "{today} times! So now I'm sticky on your cursor! Not nice of you!"],
        "Puddle": ["Oh no, I grabbed it, I'm sorry, but {today} times was too many!",
                   "Please don't shake me, I'll splash... but you chased me so much..."],
        "Blorp": ["Blorp grab! Cursor mine! {today}! Bad cursor!",
                  "Hah! Blorp hold! You no move! Shame!"],
        // triangle
        "Spike": ["Got your cursor. My point, sharp as ever: {today} times is too many.",
                  "Hanging on by my tip. Think about what you did."],
        "Wedge": ["I've got your cursor and I'm not budging. {today} times. Try shaking.",
                  "You won't shift me off this. Not until you've learned."],
        "Delta": ["What's changed: I'm holding your cursor now. Because of the {today} chases.",
                  "Noticed something? Your cursor stopped. That's me. On it."],
    ]

    public static let englishGoodLines: [String: [String]] = [
        // blocky's cast
        "Blocky": ["Ha. Caught YOUR cursor for once. Tag. I win.",
                   "See? Grabbing is fun. {today} rounds today and this one's mine."],
        "Pip": ["GOTCHA! I caught your cursor! Best game EVER! Shake me, shake me!",
                "{today} times you chased me, and I caught YOU! Wheee!"],
        "Mortimer": ["*chuckles* Even an old one can still win at tag. Your cursor, young one.",
                     "An old saying: the chased one always gets a turn. My turn."],
        "Zed": ["Got you... *yawn*... tag... I'll just hold on here a while...",
                "Your cursor's comfy... I win this one... five more minutes..."],
        "Dot": ["Too slow, boulder! I caught YOUR cursor this time!",
                "{today} chases and you never caught me. But I caught you!"],
        "Ruth": ["New rule: whoever catches the cursor wins. I caught it. I win.",
                 "Game score updated: me one, cursor zero. Officially."],
        // cat
        "Whiskers": ["Caught it. Not that I was playing. ...I was playing.",
                     "Pounced on your cursor. Purely by accident. Ha."],
        "Mittens": ["Mrrp! Caught the little arrow! Now I'm cuddling it!",
                    "Purr... gotcha... the cursor is my toy now..."],
        "Sir Pounce": ["POUNCE! The hunter has caught the cursor at last! Glorious!",
                       "{today} chases, and the final pounce is MINE! Victory!"],
        // frog
        "Hopper": ["BOING! I jumped right onto your cursor! Best jump ever!",
                   "Got it! {today} hops today and I landed on the cursor! Ribbit!"],
        "Mossy": ["The frog leaps, and catches the fly. Today, the fly is your cursor.",
                  "A ripple returns to the stone that made it. Tag."],
        "Croak": ["Hmph. Caught your cursor. ...All right, that was fun.",
                  "Gotcha. Don't tell anyone I enjoyed it."],
        // ghost
        "Boo": ["BOO! I got your cursor! Haha, I'm the spooky one AND the winner!",
                "Caught you! {today} times you chased me, and now I've caught YOU!"],
        "Wisp": ["I caught your cursor, softly, like catching a falling leaf.",
                 "Tag... you're it... and I'm drifting with your cursor."],
        "Sheet": ["Technically I caught you. Technically that means I win.",
                  "I've wrapped your cursor. Technically, it's a hug."],
        // mushroom
        "Morel": ["Caught... your cursor... slowly... but I caught it...",
                  "Tag... you're... it... I think..."],
        "Puff": ["Eee! I caught your cursor! I'm so happy I could spore!",
                 "Gotcha gotcha gotcha! {today} times and I finally won!"],
        "Cap": ["In my day we played tag properly. Like this. Gotcha!",
                "Not bad for an old mushroom, eh? Your cursor is mine!"],
        // robot
        "Unit 7": ["Cursor captured. Tag game score: 1 to me. Joy: 100%.",
                   "Status: holding cursor. Rounds played today: {today}. Winning: yes."],
        "Sprocket": ["Clamped on! Gotcha! My grippers work great!",
                     "Ha! Caught your cursor! Shake me, I'm bolted on tight!"],
        "Glitch": ["Gotcha gotcha! Cursor cursor caught! I win win!",
                   "Tag tag! You're it it! Ha ha!"],
        // slime
        "Goop": ["Got you! Sticky! Sticky is fun! Hee hee!",
                 "Your cursor is stuck to me! Nice! Very nice!"],
        "Puddle": ["Oh! I caught it! I actually caught it! Is that allowed?",
                   "I got your cursor! I'm so surprised! Tag, I think?"],
        "Blorp": ["Blorp catch! Blorp win! Hee!",
                  "Cursor! Got! Blorp happy!"],
        // triangle
        "Spike": ["Got you. Sharp move, right? Tag.",
                  "Caught your cursor on my point. Your turn."],
        "Wedge": ["Got your cursor, and I'm staying put. Try and shake me.",
                  "Caught it. I'm not letting go easily. Tag."],
        "Delta": ["Notice the change? I caught your cursor. Tag.",
                  "Something's different: you're it now."],
    ]

    public static let englishNeutralLines: [String: [String]] = [
        // blocky's cast
        "Blocky": ["I'm holding your cursor now. {today} times today, so: fair.",
                   "Your cursor stays here a while. Written down."],
        "Pip": ["Oh! I've got your cursor! Well, I'll hold it for a bit!",
                "Holding your cursor now! {today} times today, so it's my turn, okay?"],
        "Mortimer": ["*sighs* I'll hold your cursor for a moment. It has been a busy day.",
                     "An old saying: what chases you comes to you. Here it is."],
        "Zed": ["Got your cursor... I'll just... hold it... for a bit...",
                "Holding this now... {today} times today... zzz..."],
        "Dot": ["Holding your cursor. Quickly. Like everything I do.",
                "{today} chases today. I'll keep the cursor for a second."],
        "Ruth": ["Procedure: after {today} chases the cursor is held briefly. Holding.",
                 "Your cursor is held. Please wait. Or shake."],
        // cat
        "Whiskers": ["I'm sitting on your cursor. Cats do that.",
                     "Your cursor's mine for a moment. Don't make it a thing."],
        "Mittens": ["Mrrr... I'm lying on your cursor now. It's warm.",
                    "Purr... holding it a moment..."],
        "Sir Pounce": ["The cursor is captured. {today} chases today. A fair exchange.",
                       "Holding the cursor. Noted in the hunt log."],
        // frog
        "Hopper": ["Jumped on your cursor! Holding it now! Shake if you want it!",
                   "{today} hops today, and now I'm on the cursor. Okay!"],
        "Mossy": ["The pond holds the stone for a moment. Then it lets go.",
                  "I hold your cursor. Like still water holds a leaf."],
        "Croak": ["Holding your cursor. Too dry to do much else.",
                  "Got it. Shake if you want it back."],
        // ghost
        "Boo": ["I've got your cursor. Boo, I suppose.",
                "Holding your cursor now. {today} times today, so."],
        "Wisp": ["I'll hold your cursor a while, and drift.",
                 "Your cursor, in my hands. For now."],
        "Sheet": ["Technically, I'm holding your cursor now.",
                  "{today} times today. Technically this is my turn."],
        // mushroom
        "Morel": ["Holding... your cursor... for now...",
                  "I've got it... no hurry..."],
        "Puff": ["Got your cursor! Holding it! Just so you know!",
                 "{today} times today, so I'm holding on a bit!"],
        "Cap": ["In my day we'd hold the cursor a moment. So I'm holding it.",
                "I'll keep this cursor for a bit. Old habit."],
        // robot
        "Unit 7": ["Cursor held. Chases today: {today}. Release on shake.",
                   "Status: cursor in custody. Duration: until shaken."],
        "Sprocket": ["Clamped onto your cursor. Grippers working fine.",
                     "Holding the cursor! Just checking my grip."],
        "Glitch": ["Cursor cursor held. {today} today today.",
                   "Holding holding. Shake to release release."],
        // slime
        "Goop": ["Your cursor is stuck to me now. Sticky.",
                 "Holding on. {today} times today."],
        "Puddle": ["Oh, I'm holding your cursor, I hope that's all right.",
                   "I've got it... please shake gently..."],
        "Blorp": ["Blorp hold cursor. Blorp.",
                  "Cursor. Blorp has it."],
        // triangle
        "Spike": ["Got your cursor. That's the point.",
                  "Holding it. {today} today."],
        "Wedge": ["Got your cursor. Not budging for a bit.",
                  "Holding it. Shake if you must."],
        "Delta": ["Change noticed: your cursor is with me now.",
                  "{today} chases today. Now I'm holding the cursor."],
    ]

    // MARK: Last words, shaken off

    public static let englishBadAnyoneLastWords = ["Fine! Take it. But I remember everything."]
    public static let englishGoodAnyoneLastWords = ["Whoa! You shook me off! Again, again!"]
    public static let englishNeutralAnyoneLastWords = ["Okay. Cursor's yours again."]

    public static let englishBadLastWords: [String: [String]] = [
        "Blocky": ["Fine. Take your cursor. This isn't over. It's written down."],
        "Pip": ["Whoa! Okay! You win! But be NICER!"],
        "Mortimer": ["*oof* My old bones... remember this, young one."],
        "Zed": ["Fine... I was falling asleep anyway..."],
        "Dot": ["Lucky shake, boulder. Lucky."],
        "Ruth": ["Released under protest. I am filing a report."],
        "Whiskers": ["I let go. I meant to. Obviously."],
        "Mittens": ["Mrrrow! Rude! I was comfy!"],
        "Sir Pounce": ["Retreat! But the hunter shall return!"],
        "Hopper": ["Wheee- oof! Okay, you win this one!"],
        "Mossy": ["The stone is thrown back. The pond remembers."],
        "Croak": ["Grumble. Shook me off. Typical."],
        "Boo": ["Aaah! Okay okay! But I'll haunt you later!"],
        "Wisp": ["Shaken loose... like a leaf from a branch..."],
        "Sheet": ["Technically, I let go. Technically."],
        "Morel": ["Ooh... falling... slowly... you'll... see..."],
        "Puff": ["*PUFF* Now look what you made me do!"],
        "Cap": ["In my day nobody shook their elders! Shame!"],
        "Unit 7": ["Grip failure. Grudge saved to memory."],
        "Sprocket": ["Aaah! My bolts! You shook my bolts loose!"],
        "Glitch": ["Release release. Grudge grudge saved."],
        "Goop": ["Splat! Not nice! Not nice at all!"],
        "Puddle": ["Oh no oh no oh no, I'm falling!"],
        "Blorp": ["Blorp fall! Blorp mad!"],
        "Spike": ["Fine. But you've seen my point."],
        "Wedge": ["You moved me. This time."],
        "Delta": ["Change: I let go. Grudge: unchanged."],
    ]

    public static let englishGoodLastWords: [String: [String]] = [
        "Blocky": ["Fine, you win this round. Rematch later."],
        "Pip": ["Wheeee! Again! Do it again!"],
        "Mortimer": ["*chuckles* Well shaken, young one. Well shaken."],
        "Zed": ["Whoa... that woke me up... fun, though..."],
        "Dot": ["Ha! Good shake! I'll be faster next time!"],
        "Ruth": ["Round over. You won fairly. Next round tomorrow."],
        "Whiskers": ["I let go on purpose. ...It was fun."],
        "Mittens": ["Mrrp! Wheee! Again?"],
        "Sir Pounce": ["A worthy foe! Until the next hunt!"],
        "Hopper": ["Boing boing! Best ride ever!"],
        "Mossy": ["The leaf falls. The game goes on."],
        "Croak": ["Hmph. That was fun. Don't tell."],
        "Boo": ["Whee! Okay, your turn to chase me!"],
        "Wisp": ["Flung loose... like a happy little ghost..."],
        "Sheet": ["Technically, a tie."],
        "Morel": ["Wheee... slowly... wheee..."],
        "Puff": ["Eee! *puff* That was the BEST!"],
        "Cap": ["Ho ho! In my day that was called a good shake!"],
        "Unit 7": ["Released. Fun level: 100%. Rematch: requested."],
        "Sprocket": ["Wheee! My springs! Again!"],
        "Glitch": ["Wheee wheee! Again again!"],
        "Goop": ["Splat! Hee hee! Again?"],
        "Puddle": ["Oh! I'm flying! That's... actually fun!"],
        "Blorp": ["Blorp fly! Again!"],
        "Spike": ["Point to you. Next round."],
        "Wedge": ["All right. You shook me. Next time I hold tighter."],
        "Delta": ["Change: you're not it any more. I am."],
    ]

    public static let englishNeutralLastWords: [String: [String]] = [
        "Blocky": ["Okay. Cursor's yours again."],
        "Pip": ["Oop! There you go, all yours!"],
        "Mortimer": ["*sighs* And down I go. As things do."],
        "Zed": ["Okay... falling... night..."],
        "Dot": ["Off I go. Quickly."],
        "Ruth": ["Hold ended. Cursor returned."],
        "Whiskers": ["Fine. I was done anyway."],
        "Mittens": ["Mrrr. Okay."],
        "Sir Pounce": ["Released. Noted in the log."],
        "Hopper": ["Off I hop!"],
        "Mossy": ["The pond lets go of the leaf."],
        "Croak": ["Right. Back to my edge."],
        "Boo": ["Okay, okay. Bye, cursor."],
        "Wisp": ["I drift away again."],
        "Sheet": ["Technically, released."],
        "Morel": ["Letting... go..."],
        "Puff": ["Wheee- okay, done!"],
        "Cap": ["Back down I go. In my own time."],
        "Unit 7": ["Hold ended. Cursor returned to user."],
        "Sprocket": ["Grippers off. Back I go."],
        "Glitch": ["Released released."],
        "Goop": ["Unstuck. Okay."],
        "Puddle": ["Oh! Down I go..."],
        "Blorp": ["Blorp let go."],
        "Spike": ["Point made. Off I go."],
        "Wedge": ["Fine. Moving."],
        "Delta": ["Change: cursor free."],
    ]
}

extension Hunts {
    /// Each built-in character on its count, in its own voice, one set per cursor
    /// mood: a grievance tally in the bad mood, a game's score in the good one,
    /// plain numbers in the neutral. `{today}`, `{week}` and `{all}` are filled in;
    /// a line is only said when today's count is two or more.

    public static let englishBadAnyone = [
        "{today} times today. {week} this week. {all} in all. I am keeping count.",
        "That cursor: {today} today, {all} altogether. Every one remembered.",
    ]

    public static let englishGoodAnyone = [
        "Score check! {today} today, {week} this week, {all} ever. Still not caught!",
        "{today} rounds of tag today. {all} in all. I love this game.",
    ]

    public static let englishNeutralAnyone = [
        "{today} today, {week} this week, {all} in all. Just the numbers.",
        "The cursor came by {today} times today. {all} altogether. Huh.",
    ]

    public static let englishBadLines: [String: [String]] = [
        // blocky's cast
        "Blocky": ["Today: {today}. This week: {week}. Ever: {all}. Every single one written down.",
                   "{all} times that cursor has come for me. I have not forgiven one."],
        "Pip": ["{today} chases today! {week} this week! Ha! That's... actually quite a lot!",
                "Wow, {all} in all! Is that a record? Can it please not be a record?"],
        "Mortimer": ["*sighs* {today} times today. {all} in my long life. I remember each one.",
                     "An old saying: {week} chases in one week make a creature wise, and tired."],
        "Zed": ["{today} today... {week} this week... too many to sleep through...",
                "{all} times woken up... I counted them instead of sheep..."],
        "Dot": ["{today} today, {week} this week, {all} ever. Slow cursor, long list.",
                "{all} tries, boulder-hand, and you still need {today} a day."],
        "Ruth": ["Logged: {today} today, {week} this week, {all} in total. All unauthorised.",
                 "Rule four: no chasing. Broken {today} times today. I have the paperwork."],
        // cat
        "Whiskers": ["{today} times today. Not that I care. ...{week} this week. I care.",
                     "{all} chases. A cat forgets nothing. A cat forgives nothing."],
        "Mittens": ["Mrrr... {today} times today. I only wanted the warm spot...",
                    "{all} wake-ups in all... purr... no... hiss."],
        "Sir Pounce": ["The hunter, hunted {today} times today! {all} in all! The shame of it!",
                       "Hunt log: {week} ambushes this week. The enemy grows bold!"],
        // frog
        "Hopper": ["{today} jumps today, all your fault! {week} this week! My legs are tired!",
                   "{all} jumps in all, and not one of them where I wanted!"],
        "Mossy": ["A pond stirred {today} times today stays muddy for {week}.",
                  "{all} ripples. Even the oldest pond gets tired of stones."],
        "Croak": ["{today} today. {all} in all. And not a drop of water for any of them.",
                  "{week} this week. This edge is too dry for this much running."],
        // ghost
        "Boo": ["Boo! {today} times today! Stop haunting ME, that's my job!",
                "{all} chases... I'm meant to be the scary one!"],
        "Wisp": ["{today} times today, {all} in all. Each one a little ghost of its own.",
                 "{week} this week. I drift, and the cursor drifts after."],
        "Sheet": ["{today} today. Technically I hover, so technically that's {today} chases of nothing.",
                  "{all} in all. Technically a record. Technically annoying."],
        // mushroom
        "Morel": ["{today}... today... {all}... in all... patience... runs... short...",
                  "{week}... this week... a mushroom grows slower than that..."],
        "Puff": ["{today} times today! I'm so cross I could spore!",
                 "{all} in all! One more and *puff*, I mean it!"],
        "Cap": ["In my day it was one chase a week. Now it's {today} a day. {all} in all!",
                "{week} this week. In my day we called that rude."],
        // robot
        "Unit 7": ["Status: hunted {today} times today, {week} this week, {all} total. Annoyance: rising.",
                   "Report: {all} cursor incidents logged. Average patience remaining: 3%."],
        "Sprocket": ["{today} times today! My bolts can't take {week} a week!",
                     "{all} jumps in all. I'll need a whole new set of springs."],
        "Glitch": ["Virus activity: {today} today today. {all} in all. VIRUS.",
                   "{week} this week week. The scan says: the cursor cursor."],
        // slime
        "Goop": ["{today} times today. Not nice. Not sticky. Just tiring.",
                 "{all} in all! That's too many! Not nice!"],
        "Puddle": ["{today} times today... I'm going to evaporate from the stress...",
                   "{all} in all... what if one day it catches me? Oh no..."],
        "Blorp": ["Blorp! {today}! Too many! Splat!",
                  "{all}! Blorp angry! Grr!"],
        // triangle
        "Spike": ["{today} today, {all} in all. My point stands: stop.",
                  "{week} this week. Keep count yourself, it's on your conscience."],
        "Wedge": ["{today} times today and I still won't tip. {all} in all. Give up.",
                  "{week} this week. Push all you like, I don't move."],
        "Delta": ["Since yesterday: up to {today} today. This week: {week}. The difference: annoying.",
                  "{all} in all. What changed? Only my patience."],
    ]

    public static let englishGoodLines: [String: [String]] = [
        // blocky's cast
        "Blocky": ["{today} today, {all} in all, and you never caught me once. Not that I count. I count.",
                   "Fine. {week} rounds this week. I may have enjoyed some of them."],
        "Pip": ["{today} games of tag today! {week} this week! Best week EVER!",
                "{all} in all! Again! Let's make it {all} and one!"],
        "Mortimer": ["*chuckles* {today} rounds today. {all} in all. Old legs, young heart.",
                     "An old saying: {week} games a week keep the knees nimble."],
        "Zed": ["{today} games today... fun... sleepy fun... rematch after a nap...",
                "{all} in all... I won most... I think... *yawn*"],
        "Dot": ["{today} today, {all} ever, and you've caught me zero times. Too fast!",
                "{week} laps this week. You're getting faster. Still a boulder."],
        "Ruth": ["Scoreboard: {today} today, {week} this week, {all} in all. I win every one.",
                 "Recorded: {all} rounds of tag. Results: all mine. Again?"],
        // cat
        "Whiskers": ["{today} times today. I let you. That's how a cat says it likes you.",
                     "{all} chases. Fine, it's a game. I'm only playing because I want to."],
        "Mittens": ["Mrrrow! {today} times today! Then a nap, then {today} more!",
                    "{all} games in all... purr... the best kind of tired."],
        "Sir Pounce": ["{today} pounces dodged today! {all} in all! None catch Sir Pounce!",
                       "Hunt log: {week} glorious chases this week! A worthy foe!"],
        // frog
        "Hopper": ["{today} jumps today! New record! Let's do {week} again!",
                   "RIBBIT! {all} in all! I can jump higher every time!"],
        "Mossy": ["{today} ripples today. A pleasant pond. {all} in all, friend.",
                  "The frog who plays {week} games a week never grows old."],
        "Croak": ["{today} today. Fine. It was fun. {all} in all. Don't tell anyone.",
                  "{week} this week. Grumble. Not bad. Not bad at all."],
        // ghost
        "Boo": ["Boo! {today} times today and you never caught me! Spooky AND fast!",
                "{all} in all! My turn to chase you next!"],
        "Wisp": ["{today} times today we drifted round each other. {all} dances in all.",
                 "{week} this week. How lovely, to be chased by someone who only wants to play."],
        "Sheet": ["{today} today. Technically I won every one.",
                  "{all} in all. Technically the best score on the screen."],
        // mushroom
        "Morel": ["{today}... games today... slow fun... {all}... the best kind...",
                  "{week}... this week... mushrooms like... slow games..."],
        "Puff": ["Eee! {today} times today! I'm so happy I could spore!",
                 "{all} in all! *puff* *puff* Again!"],
        "Cap": ["In my day we played tag too. {today} rounds today! {all} in all! You'd have done well.",
                "{week} this week. Young people and their games. ...One more."],
        // robot
        "Unit 7": ["Game log: {today} evasions today, {week} this week, {all} total. Enjoyment: 97%.",
                   "Score: Unit 7 {all}, cursor 0. Probability of another round: 100%."],
        "Sprocket": ["{today} jumps today! My gears are spinning with joy!",
                     "{all} in all! Fully oiled for round {all} and one!"],
        "Glitch": ["{today} today today! The cursor cursor is fun fun.",
                   "Scan complete: {all} games. Playing playing."],
        // slime
        "Goop": ["Wheee! {today} times today! Sticky fun!",
                 "{all} in all! Nice! Again!"],
        "Puddle": ["{today} times today and I didn't even splash! Was I good?",
                   "{all} in all! Only a little scary! Can we go again?"],
        "Blorp": ["Blorp! {today}! Fun! Again!",
                  "{all}! Zoom zoom! Blorp win!"],
        // triangle
        "Spike": ["{today} today, {all} in all, and still the sharpest at tag. Point made.",
                  "{week} this week. You'll need a sharper aim. Again."],
        "Wedge": ["{today} tries today and I'm still on my spot. Good game.",
                  "{all} in all. You won't tag me. I like that you keep trying."],
        "Delta": ["Change logged: {today} today, up from before. Mood: improved.",
                  "{week} this week, {all} in all. Interesting: it's more fun every time."],
    ]

    public static let englishNeutralLines: [String: [String]] = [
        // blocky's cast
        "Blocky": ["{today} today. {all} in all. Just keeping the books.",
                   "{week} hops this week. The bottom edge is still the best edge."],
        "Pip": ["Ooh, {today} hops today! And {all} in all! Numbers are fun!",
                "{week} this week! I didn't even notice most of them!"],
        "Mortimer": ["*sighs* {today} today, {all} in all. The cursor comes and goes, like weather.",
                     "An old saying: count the hops, {week} a week, and let them go."],
        "Zed": ["{today} hops today... {all} in all... whatever... nap time...",
                "{week} this week... I slept through most of them..."],
        "Dot": ["{today} today, {all} ever. Took me no time at all.",
                "{week} this week. Quick hops. Barely noticed."],
        "Ruth": ["For the record: {today} today, {week} this week, {all} in total. Filed.",
                 "Count updated: {all}. Nothing further to report."],
        // cat
        "Whiskers": ["{today} times today. I hadn't noticed. {all} in all, apparently.",
                     "{week} this week. Fine. Whatever."],
        "Mittens": ["{today} hops today... mrrr... then back to the warm spot...",
                    "{all} in all... purr... nap now."],
        "Sir Pounce": ["Hunt log: {today} sightings of the cursor today. {all} in all. Noted.",
                       "{week} this week. The hunter files the report."],
        // frog
        "Hopper": ["{today} jumps today! {all} in all! Jumping is jumping!",
                   "{week} this week! Some of them were even far!"],
        "Mossy": ["{today} ripples today, {all} in all. The pond settles every time.",
                  "A frog counts the rain: {week} drops this week."],
        "Croak": ["{today} today. {all} in all. Still too dry here.",
                  "{week} this week. Didn't make the edge any wetter."],
        // ghost
        "Boo": ["Boo! {today} hops today! {all} in all! Huh!",
                "{week} this week. I just float out of the way. Boo."],
        "Wisp": ["{today} today, {all} in all. They drift past, and are gone.",
                 "{week} this week. Like old monitors, I let them go."],
        "Sheet": ["{today} today. Technically not hops, I hover.",
                  "{all} in all. Technically just a number."],
        // mushroom
        "Morel": ["{today}... today... {all}... in all... it passes...",
                  "{week}... this week... rain falls... cursors pass..."],
        "Puff": ["{today} hops today! Hee! {all} in all!",
                 "{week} this week! That's a lot of hopping! *puff*"],
        "Cap": ["In my day we didn't count them. {today} today, {all} in all, they say.",
                "{week} this week. In my day that was just Tuesday."],
        // robot
        "Unit 7": ["Status: {today} cursor events today, {week} this week, {all} total. Impact: none.",
                   "Report: {all} relocations logged. All nominal."],
        "Sprocket": ["{today} jumps today. Springs still in tune. {all} in all!",
                     "{week} this week. Routine. I'll oil the hinges anyway."],
        "Glitch": ["Log log: {today} today, {all} in all. Scan clean clean.",
                   "{week} this week week. No virus found. Huh."],
        // slime
        "Goop": ["{today} hops today. {all} in all. Okay.",
                 "{week} this week. Nice enough."],
        "Puddle": ["{today} hops today... that's fine... I think that's fine?",
                   "{all} in all... and I didn't splash once."],
        "Blorp": ["Blorp. {today}. Okay.",
                  "{all}. Hop hop. Blorp."],
        // triangle
        "Spike": ["{today} today, {all} in all. That's the point. There isn't one.",
                  "{week} this week. Noted. Moving on."],
        "Wedge": ["{today} hops today. {all} in all. I'm still right here.",
                  "{week} this week. Didn't change a thing."],
        "Delta": ["Change since yesterday: {today} today. This week: {week}. Noted.",
                  "{all} in all. The difference: nothing much."],
    ]
}

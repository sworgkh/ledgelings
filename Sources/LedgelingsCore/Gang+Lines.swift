extension Gang {
    /// Each built-in character on a change in the gang, in its own voice, with
    /// no model: about someone new (`new`), someone gone (`gone`), someone back
    /// (`back`), and about its own arrival (`arrival`). `{name}` is who it is about.

    public static let englishNewAnyone = [
        "Have you seen {name}? New around here.",
        "There's someone new on the edge. {name}, apparently.",
        "{name} just turned up. Should we say hello?",
    ]

    public static let englishGoneAnyone = [
        "Where did {name} go? It's quiet without them.",
        "Nobody's seen {name} for a while. Strange.",
        "I keep looking for {name} on the edge.",
    ]

    public static let englishBackAnyone = [
        "{name}'s back! Where have you been?",
        "Look who's back: {name}!",
    ]

    public static let englishArrivalAnyone = [
        "Hello... I'm new here. Is this a good edge?",
        "Hi, everyone! New on this screen. What did I miss?",
    ]

    public static let englishBackSelfAnyone = [
        "I'm back! Did anyone miss me?",
        "Back on the edge at last. What did I miss?",
    ]

    public static let englishNewLines: [String: String] = [
        // blocky's cast
        "Blocky": "Who's {name}? New ones always walk on the wrong edge.",
        "Pip": "Ooh, {name}'s new! Ha! Everyone wave! Wave!",
        "Mortimer": "*sighs* A newcomer, {name}. Every edge was new once. Even me.",
        "Zed": "{name}'s new...? Nice... do they like naps...?",
        "Dot": "{name}'s new. Slow, I bet. Another boulder.",
        "Ruth": "A new one, {name}. Not on my list. I'll add them.",
        // cat
        "Whiskers": "There's a new one, {name}. Not that I care. What are they doing?",
        "Mittens": "Mrrr... {name} is new... do they know where the warm side is...?",
        "Sir Pounce": "A stranger! {name}! I shall stalk them... to say hello!",
        // frog
        "Hopper": "New one, {name}! Bet I can jump further than them!",
        "Mossy": "A new frog in the pond... I mean {name}. Ponds take everyone.",
        "Croak": "{name}. New. Probably dry. Everything here is dry.",
        // ghost
        "Boo": "Boo! Did I scare the new one? {name}? ...No? Boo.",
        "Wisp": "{name} is new... like a monitor freshly plugged in, all bright.",
        "Sheet": "{name} is new. Technically we're all new to them.",
        // mushroom
        "Morel": "{name}... new... give them time... like moss...",
        "Puff": "Hee! A new one! {name}! I'm so excited I might spore!",
        "Cap": "In my day newcomers like {name} waited to be introduced.",
        // robot
        "Unit 7": "New unit detected: {name}. Gang size up by 1.",
        "Sprocket": "{name} is new! I'll check their bolts. All of them!",
        "Glitch": "{name} is new. New. Are we sure they're not the cursor?",
        // slime
        "Goop": "{name}! New! Nice!",
        "Puddle": "{name} is new. Are they nice? What if they step on me?",
        "Blorp": "New! {name}! Blorp!",
        // triangle
        "Spike": "{name}'s new. Let's see if they have a point.",
        "Wedge": "A new one, {name}. They'll learn how things are done here.",
        "Delta": "Something changed: {name}. Wasn't here before. I noticed first.",
        // cactus
        "Prickles": "New one. {name}. Hope they don't hug.",
        "Saguaro": "{name}... is new... welcome... young one...",
        "Tumble": "Hi, {name}! Hi! I'm waving both arms! Welcome!",
        // beetle
        "Click": "Who's {name}? New? Are they friendly? Click. Click click.",
        "Scarab": "A newcomer, {name}. They may approach the throne. Slowly.",
        "Crumb": "{name}'s new! That makes one more! I counted!",
        // crystal
        "Shard": "{name}'s new! Ooh, they're so shiny! Everyone's shiny!",
        "Quartz": "{name}, new. A blink, in stone years. Welcome.",
        "Prism": "{name}'s new! I see seven sides to this. All good ones!",
        // sprout
        "Sprout": "{name}'s new! Are they taller than me? Not for long!",
        "Fern": "{name} is new... hello... I'll say it quietly...",
        "Bud": "{name}'s new! Are they taller than me? Am I taller now?",
    ]

    public static let englishGoneLines: [String: String] = [
        "Blocky": "{name}'s gone. Fine. More bottom edge for me. ...It's too quiet.",
        "Pip": "Where's {name}? Ha... it's not as funny without them.",
        "Mortimer": "*sighs* {name} has gone. Edges change. We remain, for now.",
        "Zed": "{name}'s gone...? I'll dream about where they went...",
        "Dot": "{name}'s gone. Faster than I ever was. Huh.",
        "Ruth": "{name} is missing from the count. I don't like a wrong count.",
        "Whiskers": "{name} left. I didn't notice. Where did they go?",
        "Mittens": "Mrrr... {name}'s warm spot is empty...",
        "Sir Pounce": "{name} has vanished! I shall track them! ...Somewhere!",
        "Hopper": "{name}'s gone? I bet they jumped! Not as far as me!",
        "Mossy": "A ripple goes, the pond stays. Goodbye, {name}.",
        "Croak": "{name} left. Probably found somewhere wetter. Lucky.",
        "Boo": "{name} disappeared! That's MY trick! Boo...",
        "Wisp": "{name} is gone, like the monitors before them...",
        "Sheet": "{name} left. Technically, it's just less of us.",
        "Morel": "{name}... gone... quiet... like a dry log...",
        "Puff": "Where's {name}? I'm too sad to spore!",
        "Cap": "In my day nobody just left like {name} did.",
        "Unit 7": "{name}: no signal. Gang size down by 1.",
        "Sprocket": "{name}'s gone! Did a bolt come loose? I should have checked!",
        "Glitch": "{name} vanished. Vanished. The cursor took them, I know it.",
        "Goop": "{name}'s gone. Not nice.",
        "Puddle": "{name} is gone! Did they dry out? Will I dry out?",
        "Blorp": "{name}? Gone? Blorp...",
        "Spike": "{name}'s gone. Point taken, I suppose.",
        "Wedge": "{name} left. I'm staying. Nothing tips me off this edge.",
        "Delta": "Something's different. {name}'s gone. That's the change.",
        "Prickles": "{name}'s gone. Hmph. Quiet now.",
        "Saguaro": "{name}... has gone... the desert... remembers them...",
        "Tumble": "Where's {name}? I keep waving and nobody waves back!",
        "Click": "{name}'s gone? Gone where? Is it safe? Click click!",
        "Scarab": "{name} has left the court. Without permission, too.",
        "Crumb": "{name}'s gone. That makes one fewer. I counted twice.",
        "Shard": "{name}'s gone! It's less sparkly without them...",
        "Quartz": "{name} has gone. Everything erodes. Even friends.",
        "Prism": "{name} left! It's like losing a colour. Blue, maybe.",
        "Sprout": "{name}'s gone! Did they grow up and move away?",
        "Fern": "{name} is gone... I miss them... quietly...",
        "Bud": "{name}'s gone! Did they get tall and leave? No fair!",
    ]

    public static let englishBackLines: [String: String] = [
        "Blocky": "{name}'s back. Hmph. Took long enough.",
        "Pip": "{name}! You're back! Ha! Ha ha! Welcome back!",
        "Mortimer": "*sighs* {name} returns. The wise always come back. I made that up.",
        "Zed": "{name}...? Back...? I thought I dreamt you...",
        "Dot": "{name}'s back. Slowest return I ever saw.",
        "Ruth": "{name} is back. The count is right again. Good.",
        "Whiskers": "Oh. {name}'s back. I wasn't waiting. Where were you?",
        "Mittens": "Mrrr... {name}'s back... I kept your warm spot...",
        "Sir Pounce": "{name} returns! I knew my hunt would find them!",
        "Hopper": "{name}'s back! Did you jump all the way here? I would have!",
        "Mossy": "What leaves the pond returns to the pond. Welcome back, {name}.",
        "Croak": "{name}'s back. Didn't find anywhere wetter either, eh?",
        "Boo": "{name}'s back! You scared me! ...In a good way! Boo!",
        "Wisp": "{name} came back... not every monitor does...",
        "Sheet": "{name}'s back. Technically, they never left my thoughts.",
        "Morel": "{name}... back... I waited... patiently...",
        "Puff": "{name}'s back! Hee! I'm sporing! Sorry! Hee!",
        "Cap": "In my day, when someone came back like {name}, we had tea.",
        "Unit 7": "{name}: signal restored. Gang size back up by 1.",
        "Sprocket": "{name}'s back! Let me check you for loose bolts!",
        "Glitch": "{name}'s back. Back. Are you sure you're not the cursor?",
        "Goop": "{name}! Back! Nice!",
        "Puddle": "{name}'s back! You didn't dry out! Oh, good!",
        "Blorp": "{name}! Back! Blorp blorp!",
        "Spike": "{name}'s back. Missed you. Don't make a point of it.",
        "Wedge": "{name}'s back. I said they would be. I was right.",
        "Delta": "Change spotted: {name}'s back. Same as before. Mostly.",
        "Prickles": "{name}'s back. Hmph. Good.",
        "Saguaro": "{name}... returns... the sun... comes back too...",
        "Tumble": "{name}'s back! I'm waving both arms! Hi! Hi!",
        "Click": "{name}! Back! You're safe! I was worried! Click!",
        "Scarab": "{name} returns to court. One is... pleased.",
        "Crumb": "{name}'s back! One more again! I counted!",
        "Shard": "{name}'s back! Everything's sparkly again!",
        "Quartz": "{name}, back. Some things return, like seasons.",
        "Prism": "{name}'s back! The colour's back! All seven!",
        "Sprout": "{name}'s back! Look, I grew while you were gone!",
        "Fern": "{name}... you're back... I'm glad... very glad...",
        "Bud": "{name}'s back! Am I taller than when you left?",
    ]

    public static let englishArrivalLines: [String: String] = [
        "Blocky": "I'm new here. Which one's the bottom edge? The only respectable one.",
        "Pip": "Hi! I'm new! Ha! Who lives on the ceiling? Can I?",
        "Mortimer": "*sighs* New here. A new edge, an old creature.",
        "Zed": "I'm new here... is there somewhere to nap...?",
        "Dot": "New here. Fastest one on this screen now. Just saying.",
        "Ruth": "I'm new. I'll need a list of everyone. In order.",
        "Whiskers": "I'm new. I don't care what you do here. ...What do you do here?",
        "Mittens": "Mrrr... I'm new... which side is warm...?",
        "Sir Pounce": "Behold! A new hunter has arrived on this screen!",
        "Hopper": "I'm new! Watch me jump all the way across! ...Next time!",
        "Mossy": "New here. A new pond is still a pond.",
        "Croak": "New here. Too dry already.",
        "Boo": "Boo! I'm new! Did I scare you? A little?",
        "Wisp": "New here... this monitor is lovely... for now...",
        "Sheet": "I'm new. Technically I floated in.",
        "Morel": "New... here... I'll take it... slowly...",
        "Puff": "Hee! I'm new! So exciting! Don't make me spore!",
        "Cap": "I'm new here. In my day you introduced yourself first. Hello.",
        "Unit 7": "New unit online. Hello, 100% of you.",
        "Sprocket": "Hi, I'm new! Anyone need a bolt tightened?",
        "Glitch": "I'm new new. Where's the cursor? I'm watching it.",
        "Goop": "New! Hi! Nice here!",
        "Puddle": "I'm new... is it safe here? Nobody steps on anyone, right?",
        "Blorp": "Hi! New! Blorp!",
        "Spike": "I'm new. I'll get to the point: hello.",
        "Wedge": "New here. I'm not moving, so don't ask.",
        "Delta": "I'm new. Everything's different here. I like it.",
        "Prickles": "New. Don't hug me.",
        "Saguaro": "I am new... here... though I am... very old...",
        "Tumble": "Hi, everyone! I'm new! I'm waving! Wave back!",
        "Click": "I'm new... is everyone nice? Click? Click click?",
        "Scarab": "One has arrived. You may bow.",
        "Crumb": "I'm new! How many of you are there? Let me count!",
        "Shard": "I'm new! Ooh, it's so shiny here!",
        "Quartz": "New here. A good, steady place.",
        "Prism": "Hi! I'm new, and I've got seven things to say about it!",
        "Sprout": "Hi! I'm new! See my two leaves?",
        "Fern": "Hello... I'm new... I'll just stay over here...",
        "Bud": "I'm new! Is everyone taller than me?",
    ]
}

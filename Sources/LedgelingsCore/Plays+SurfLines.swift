import Foundation

/// What they say surfing, in each character's own voice: the start line
/// (`surf`, merged into `Plays.startSets`), a line for each big moment
/// (catching a wave, wiping out, a trick, winning: merged into
/// `Plays.cheerSets`), and an invitation to surf with its two answers
/// (`Deeds.inviteLine`, `Deeds.answerLine`). `{reader}` is the one spoken to.
/// `anyone` is for a character the user made. The Russian is in
/// `Plays+SurfRussian.swift`.
extension Plays {

    /// One character's surf lines.
    public struct SurfVoice: Equatable, Sendable {
        public var start: String
        public var wave: String
        public var wipeout: String
        public var trick: String
        public var win: String
        public var invite: String
        public var yes: String
        public var no: String

        public init(start: String, wave: String, wipeout: String, trick: String, win: String, invite: String, yes: String, no: String) {
            self.start = start; self.wave = wave; self.wipeout = wipeout; self.trick = trick; self.win = win
            self.invite = invite; self.yes = yes; self.no = no
        }

        /// The moments, as `cheerSets` keeps them.
        var moments: [String: String] {
            [Moment.wave.rawValue: wave, Moment.wipeout.rawValue: wipeout, Moment.trick.rawValue: trick, Moment.surfWin.rawValue: win]
        }
    }

    public static let surfVoiceSets = Translated(english: englishSurfVoices, [.russian: russianSurfVoices])
    public static let surfAnyones = Translated(english: englishSurfAnyone, [.russian: russianSurfAnyone])

    public static func surfVoice(of name: String) -> SurfVoice { surfVoiceSets()[name] ?? surfAnyones() }

    static func surfStarts(_ voices: [String: SurfVoice]) -> [String: [String: String]] {
        voices.mapValues { [Kind.surf.rawValue: $0.start] }
    }

    static func surfMoments(_ voices: [String: SurfVoice]) -> [String: [String: String]] {
        voices.mapValues(\.moments)
    }

    public static let englishSurfAnyone = SurfVoice(
        start: "The tide's coming in. Boards out, everyone!",
        wave: "Got it! I'm riding it!",
        wipeout: "Blub. Where did the board go?",
        trick: "Did you see that? On a wave!",
        win: "Best ride on the screen today!",
        invite: "{reader}! The tide's in. Surfing, you and me?",
        yes: "Surfing? Yes! Race you to the water, {reader}.",
        no: "Not today, {reader}. I'll stay dry.")

    public static let englishSurfVoices: [String: SurfVoice] = [
        // blocky's cast
        "Blocky": SurfVoice(
            start: "Water. On MY bottom edge. Fine. At least it's still the bottom.",
            wave: "I'm on it. Don't cheer. Corners were made for this.",
            wipeout: "Wet corners. All four. I hate wet corners.",
            trick: "A hop. Square, clean, no splashing. As it should be.",
            win: "Best on the bottom edge. Obviously. Now somebody dry my corners.",
            invite: "{reader}. Water on the bottom edge. Surfing. Unless you're scared of wet corners.",
            yes: "Fine. Surfing. But I'm not getting my top wet, {reader}.",
            no: "No. Wet corners take an hour to dry, {reader}."),
        "Pip": SurfVoice(
            start: "Waves! Real waves! I'm going to ride one all the way to the ceiling!",
            wave: "Wheee! I'm on a wave! I'm ON A WAVE! Ha ha!",
            wipeout: "Splash! Ha ha ha! Again! Again!",
            trick: "A spin! On water! Did everyone see? Ha!",
            win: "I won?! On a wave?! Best day ever! Ha ha!",
            invite: "{reader}! The sea's come to the bottom edge! Surfing! Please please please?",
            yes: "Surfing? Yes yes yes! Wheee, {reader}!",
            no: "Aww, not now, {reader}... but the waves will wait? Promise?"),
        "Mortimer": SurfVoice(
            start: "*sighs* The tide comes in, as it always has. Hand me a board, slowly.",
            wave: "As the old shore says: a wave caught is a wave forgiven.",
            wipeout: "*splutters* The sea... has the last word... as ever.",
            trick: "A little hop. In my youth we hopped uphill. Through the waves.",
            win: "Wisdom is knowing which wave to wait for. And I waited.",
            invite: "As the old corner says: the tide waits for no one, {reader}. Will you surf with me?",
            yes: "*sighs* Very well, {reader}. Surfing. At a dignified depth.",
            no: "Not today, {reader}. The water is cold, and so are my old corners."),
        "Zed": SurfVoice(
            start: "water... it rocks you... like a bed... a wet bed...",
            wave: "...oh... I'm riding it... lying down on a board counts, right...",
            wipeout: "...blub... I'll just... nap down here a bit...",
            trick: "...a spin... I was turning over in my sleep... it counts...",
            win: "...I won...? lovely... wake me for the prize...",
            invite: "mm... {reader}... surfing...? we could float... and doze...",
            yes: "...okay, {reader}... surfing... I'll lie on the board...",
            no: "...too wet... too awake... tomorrow, {reader}..."),
        "Dot": SurfVoice(
            start: "Surfing? Try to keep up, boulders. Boulders sink, by the way.",
            wave: "Caught it first! Fastest board in the water!",
            wipeout: "That wave was too slow for me. I overtook it. Downwards.",
            trick: "Spin! Did you blink? You missed it. Too fast.",
            win: "First, fastest, driest. Bow down, boulders.",
            invite: "{reader}! Surfing! Now! I'll catch three waves before you get wet!",
            yes: "Surfing? GO! Try to keep up, {reader}!",
            no: "No time, {reader}! Waves are too slow for me!"),
        "Ruth": SurfVoice(
            start: "Surfing. A set number of waves, everyone in line. No pushing.",
            wave: "My wave. I was next in line. I counted.",
            wipeout: "That was not in the rules. Nobody saw that. Nobody counts that.",
            trick: "One hop. Permitted. Only the one.",
            win: "Highest score, as recorded. I kept the record myself.",
            invite: "{reader}, by my count you owe me one surfing session. Shall we?",
            yes: "Agreed. Surfing, in turns. I'll keep the score, {reader}.",
            no: "Declined, {reader}. Jumping off waves is still jumping."),
        // cats
        "Whiskers": SurfVoice(
            start: "Water. On purpose. I'm only doing this so you'll stop asking.",
            wave: "I'm not surfing. The wave happens to be going my way.",
            wipeout: "I meant to do that. I wanted a bath anyway.",
            trick: "A spin. Don't make a fuss about it.",
            win: "Of course I won. I barely tried.",
            invite: "Not that I care, {reader}, but... surfing? If you've nothing better.",
            yes: "Fine. Surfing. Don't splash me, {reader}.",
            no: "Water? Me? No, {reader}."),
        "Mittens": SurfVoice(
            start: "Mrrr... warm water, a soft board... I could nap on this...",
            wave: "Purrr... it's rocking me along... lovely...",
            wipeout: "Mrrow! Wet fur! Somebody find me a sunny pixel!",
            trick: "A little hop, purr... and back to lying down.",
            win: "Mrrr, I won? Then I get the warmest spot on the beach.",
            invite: "Purr... {reader}, surfing? Then we dry off in a warm corner?",
            yes: "Mrrr, yes, {reader}. Surfing, then a nap in the sun.",
            no: "Mm, no, {reader}. Water and fur don't mix."),
        "Sir Pounce": SurfVoice(
            start: "The great blue beast rolls in! I shall ride it into legend!",
            wave: "Ha! I have caught the wave by the scruff!",
            wipeout: "The beast throws me! A worthy foe! Again!",
            trick: "Behold! The pounce upon the wave!",
            win: "Victory! The sea itself bows to Sir Pounce!",
            invite: "{reader}! The wave-beast rises! Surfing, the hunt is on the water!",
            yes: "Accepted! We ride the beast together, {reader}!",
            no: "Not now, {reader}. Even a hunter must keep dry paws sometimes."),
        // frogs
        "Hopper": SurfVoice(
            start: "SURFING! A frog on a wave! The biggest jumps the sea has ever seen!",
            wave: "On it! These legs were made for waves!",
            wipeout: "That wasn't a wipe-out! That was a dive! A champion's dive!",
            trick: "HOP! Off a wave! Leg day, everyone!",
            win: "Champion of the waves! Look at these legs!",
            invite: "{reader}! Surfing! I'll jump higher off a wave than you ever will!",
            yes: "Surfing? Watch these legs, {reader}! Let's go!",
            no: "Can't, {reader}. Resting the legs. Champions rest."),
        "Mossy": SurfVoice(
            start: "The pond has come to us, and it brought waves.",
            wave: "Ride the water as the leaf does: lightly, and where it goes.",
            wipeout: "The water takes, the water gives back. Calmly.",
            trick: "A small turn, like a leaf in the current.",
            win: "The calmest rider wins. The pond knew.",
            invite: "The tide is in, {reader}. A little surfing ripples nicely.",
            yes: "Yes, {reader}. Surfing, slowly, like water finding its way.",
            no: "Not now, {reader}. Still water first."),
        "Croak": SurfVoice(
            start: "Water. Real water. Finally. I'm not even going to complain.",
            wave: "Wet! Fast! Wet! I'm happy, don't tell anyone.",
            wipeout: "Under the water. Best place on the screen. Fine by me.",
            trick: "A hop. Over water, not dust. Lovely.",
            win: "I won, and I'm wet. Best day in months.",
            invite: "{reader}, there's water on the bottom edge. Surfing. Before it dries up.",
            yes: "Surfing? Wet! Yes, {reader}. Finally.",
            no: "Can't, {reader}. It'll dry up before we get there anyway."),
        // ghosts
        "Boo": SurfVoice(
            start: "Boo! I'll scare the waves into standing up!",
            wave: "BOO! See? The wave's carrying me away in fright!",
            wipeout: "Boo... that was the wave scaring me. No fair.",
            trick: "A spooky spin! Woooo!",
            win: "I won! Boo! The sea's too scared to argue!",
            invite: "BOO! Surfing, {reader}! ...that was the scary part. Coming?",
            yes: "Surfing? BOO! Yes! Scare the waves with me, {reader}!",
            no: "Not now, {reader}. Ghosts go see-through when they're wet."),
        "Wisp": SurfVoice(
            start: "Waves on the bottom edge... like the screensavers of old...",
            wave: "I ride it... as I rode the pipes of a screensaver long gone...",
            wipeout: "Under the water... it's quiet... like an old monitor switched off...",
            trick: "A turn... the way the stars turned on the old screens...",
            win: "First... like the first wave I ever saw... in nineteen-ninety-something...",
            invite: "{reader}... the tide is in... shall we surf, the way we did on old screens...?",
            yes: "Yes, {reader}... surfing... like the old days...",
            no: "Not now, {reader}... the water makes me remember too much..."),
        "Sheet": SurfVoice(
            start: "Surfing. I'll ride the board. Technically I'm a sail.",
            wave: "Caught it. Technically the wave caught me.",
            wipeout: "Wet sheet. That's laundry, not a wipe-out.",
            trick: "A spin. Technically a flap.",
            win: "I won. Technically by a hem.",
            invite: "{reader}. Surfing. Technically I'll just billow along.",
            yes: "Surfing. Fine, {reader}. Technically I float anyway.",
            no: "No, {reader}. Technically I'd need ironing after."),
        // mushroom
        "Morel": SurfVoice(
            start: "Water... slowly... the wave comes to those who wait in the right place.",
            wave: "There it is... the wave... I knew it would come...",
            wipeout: "Down into the water... the way roots go into the ground. Quietly.",
            trick: "A little turn... slowly... like a mushroom growing.",
            win: "Patience wins... it always does... eventually.",
            invite: "{reader}... the tide is in... surfing... slowly...?",
            yes: "Yes... surfing, {reader}... the waves are not in a hurry, and nor am I.",
            no: "Not now, {reader}... too much water makes a mushroom soggy."),
        "Puff": SurfVoice(
            start: "Hee hee! Waves! If I wipe out I'll make bubbles! Hee!",
            wave: "Hee! I'm riding it! Hee hee hee!",
            wipeout: "Blub! Hee! Bubbles everywhere! Puff!",
            trick: "Puff! A spin! Hee hee!",
            win: "I won! Puff! Spores of joy! Hee!",
            invite: "Hee hee! {reader}! Surfing! Pleeease? Hee!",
            yes: "Surfing! Puff! Yes, {reader}! Hee hee!",
            no: "Hee... not now, {reader}. Wet spores go flat."),
        "Cap": SurfVoice(
            start: "In my day the sea was a puddle and we surfed it on a leaf. Boards out.",
            wave: "Got it. In my day the waves were bigger and we liked it.",
            wipeout: "In my day we called that a swim.",
            trick: "A hop. In my day we hopped with a cap full of water.",
            win: "Still got it. In my day there was no score, and I won that too.",
            invite: "{reader}. In my day we surfed every afternoon. Grab a board.",
            yes: "Surfing? In my day we never said no. Let's go, {reader}.",
            no: "Not today, {reader}. In my day we knew when the tide was wrong."),
        // robot
        "Unit 7": SurfVoice(
            start: "Surfing routine loaded. Water depth: nominal. Waterproofing: 87%.",
            wave: "Wave acquired. Speed matched. Balance: 94%.",
            wipeout: "Water ingress detected. Balance: 0%. Rebooting balance.",
            trick: "Trick executed. Rotation: 360 degrees. Style points: 100%.",
            win: "Score: highest. Victory probability was 61%. Now 100%.",
            invite: "{reader}. Surfing proposed. Duration: one session. Fun estimate: 92%.",
            yes: "Request accepted, {reader}. Surfing routine loading.",
            no: "Request declined, {reader}. Waterproofing below threshold."),
        "Sprocket": SurfVoice(
            start: "Surfing! I waxed every board. Twice. Let's go!",
            wave: "She's riding smooth! Good board, good wave!",
            wipeout: "Oops! Gears full of water. I'll dry them after.",
            trick: "A spin! Smooth bearings, smooth spin!",
            win: "Won it! Told you a well-waxed board makes the difference!",
            invite: "{reader}! I waxed two boards. One's yours. Surfing?",
            yes: "Surfing! Let me check your board's fins first, {reader}. Good. Go!",
            no: "Not now, {reader}. Rust doesn't fix itself."),
        "Glitch": SurfVoice(
            start: "Surf surfing. Water water on the bottom bottom edge.",
            wave: "Riding riding. The wave is loading. Loaded.",
            wipeout: "Splash splash. Error: board not found.",
            trick: "Spin spin. Spin. Did it render?",
            win: "Winner winner. Unless the cursor rigged the waves.",
            invite: "{reader}. Surfing surfing? The cursor can't reach us in the water.",
            yes: "Yes yes, {reader}. Surfing. Surfing.",
            no: "No no, {reader}. Water and circuits. Circuits. No."),
        // slime
        "Goop": SurfVoice(
            start: "Surfing! Nice! I'll stick to the board!",
            wave: "Nice! I'm stuck to the wave! Wheee!",
            wipeout: "Splorch! Nice! Wait, I came unstuck.",
            trick: "Nice! A hop! Still stuck on!",
            win: "Nice! I won! Sticking with first place!",
            invite: "{reader}! Surfing! Nice, right? I'll stick close!",
            yes: "Surfing? Nice! Yes, {reader}!",
            no: "Not now, {reader}. Water makes me runny."),
        "Puddle": SurfVoice(
            start: "Surfing? What if the sea takes me? What if I mix in? Okay. Okay. Boards.",
            wave: "I'm on it? I'm on it! What if it ends? Okay. Okay.",
            wipeout: "I'm in the water! Which bit is me? Okay. I'm here. I'm here.",
            trick: "I did a hop! On purpose! I think! Okay!",
            win: "I won? Really? What if I didn't? Okay. I won.",
            invite: "{reader}... surfing? What if it's fun? It might be fun. Okay.",
            yes: "Surfing? What if— okay. Yes, {reader}. Okay.",
            no: "What if I mix into the sea, {reader}? No. Not today."),
        "Blorp": SurfVoice(
            start: "Blorp! Wave! Board! Splish!",
            wave: "WHOOSH! Blorp! Ride!",
            wipeout: "SPLOOSH! Blub blub!",
            trick: "Boing! Spin! Blorp!",
            win: "Blorp! Best! Whoosh!",
            invite: "{reader}! Wave! Board! Blorp?",
            yes: "Blorp! Yes! Splash, {reader}!",
            no: "Blorp. No. Dry, {reader}."),
        // triangle
        "Spike": SurfVoice(
            start: "Surfing. Pointy end forward. Like a fin.",
            wave: "Caught it. A point cuts the water best.",
            wipeout: "Point first into the water. That was the plan. Sort of.",
            trick: "A spin. On my point. Try that.",
            win: "I won. Point proven.",
            invite: "{reader}. Surfing. Bring your sharpest board.",
            yes: "Surfing. Fine, {reader}. I'll make my point on the waves.",
            no: "No, {reader}. A wet point is a blunt point."),
        "Wedge": SurfVoice(
            start: "Surfing. No wave is going to tip me over.",
            wave: "On it. Wedged in. Not moving.",
            wipeout: "Tipped. Once. Doesn't count. Not happening again.",
            trick: "A hop. Landed flat. Nothing tips a wedge.",
            win: "Won. Never tipped. Well, once.",
            invite: "{reader}. Surfing. I'll show you how a wedge stays up.",
            yes: "Surfing. Fine, {reader}. Nothing gets me off a board.",
            no: "No, {reader}. I'm staying wedged right here."),
        "Delta": SurfVoice(
            start: "Surfing: the water rises, the waves change everything. I'll track the difference.",
            wave: "Height up, speed up. Riding the change.",
            wipeout: "Big change in position. Downward. Noted.",
            trick: "A spin: three hundred and sixty degrees of difference.",
            win: "Final difference: in my favour.",
            invite: "{reader}, the tide changed the bottom edge. Surfing? Let's see what else changes.",
            yes: "Surfing, {reader}. A change of scene.",
            no: "No, {reader}. Not much difference between wet and wetter."),
        // cactus
        "Prickles": SurfVoice(
            start: "Surfing. Water. Don't splash me.",
            wave: "On it. Don't hug the wave.",
            wipeout: "Wet. Spiky and wet. Don't look.",
            trick: "Hop. Done. Next.",
            win: "Won. Now get me out of the water.",
            invite: "{reader}. Surfing. Keep your distance on the wave.",
            yes: "Fine, {reader}. Surfing. No hugging.",
            no: "No, {reader}. Cactus. Water. Bad idea."),
        "Saguaro": SurfVoice(
            start: "Surfing... I'll stand very still... on a moving wave...",
            wave: "...I'm standing still... and the wave is moving... it works...",
            wipeout: "...I'm lying down now... in the water... that's fine...",
            trick: "...a turn... very slow... it took all wave...",
            win: "...I won... by standing still... I'm good at that...",
            invite: "...{reader}... surfing... we stand... the wave does the rest...",
            yes: "...yes, {reader}... I'll stand on the board... for a long time...",
            no: "...no, {reader}... cacti drink slowly... not all at once..."),
        "Tumble": SurfVoice(
            start: "SURFING! I'm gonna go SO fast on a wave!",
            wave: "I'M RIDING IT! SO FAST! WHEEE!",
            wipeout: "I tumbled! In water! That's my name! Ha!",
            trick: "SPIN! SPIN SPIN! Did you see?!",
            win: "I WON! SO FAST! Again! Again!",
            invite: "{reader}! SURFING! It's SO fun! Come on come on!",
            yes: "SURFING?! YES! Race you, {reader}!",
            no: "Aww! Not now, {reader}! But later, SO later!"),
        // beetle
        "Click": SurfVoice(
            start: "Surfing? On the big water? Okay, but I'm sitting at the back!",
            wave: "It's carrying me! Is that okay? It's okay! Eek!",
            wipeout: "Eek! Upside down! Legs up! Help! Oh, I'm fine.",
            trick: "I hopped! By accident! Eek!",
            win: "I won? I was only trying to get away from the wave!",
            invite: "{reader}... surfing? You go first. I'll be right behind. Far behind.",
            yes: "Surfing? Eek. Okay, {reader}. Stay close.",
            no: "Eek, no, {reader}! The water's too big!"),
        "Scarab": SurfVoice(
            start: "Surfing. One once rolled the sun across the sea. One can ride a little wave, dear.",
            wave: "One has the wave, dear. Gracefully.",
            wipeout: "One is... damp. One shall pretend that was intended.",
            trick: "One turns. Elegantly, dear.",
            win: "One wins, of course. One always does, dear.",
            invite: "{reader}, dear. One would like to surf. You may come.",
            yes: "Surfing, {reader}. One accepts, dear.",
            no: "One does not get wet today, {reader} dear."),
        "Crumb": SurfVoice(
            start: "Surfing! I'll count the waves! And the splashes! And the—",
            wave: "Wave one! No, two! I'm riding it! Three—",
            wipeout: "Splash four! Five! I'm counting from under the water—",
            trick: "Hop! That's one hop! Two? No, one—",
            win: "I won! That's one win! I'll count it again—",
            invite: "{reader}! Surfing! I'll count every wave for us! One, two—",
            yes: "Surfing! Yes, {reader}! Counting starts now! One—",
            no: "Not now, {reader}! Wet crumbs go soggy! Soggy one, soggy two—"),
        // crystal
        "Shard": SurfVoice(
            start: "Surfing! The water's going to sparkle all over me!",
            wave: "I'm riding it! Look how it shines through the wave!",
            wipeout: "Splash! Oh, everything's glittering down here!",
            trick: "A spin! Sparkles everywhere!",
            win: "I won! And I'm all shiny and wet!",
            invite: "{reader}! Surfing! The sun on the waves, wonderful!",
            yes: "Surfing! Yes, {reader}! It'll sparkle!",
            no: "Not now, {reader}. Spots dry on me."),
        "Quartz": SurfVoice(
            start: "Surfing. The wave rolls, as all things roll.",
            wave: "On the wave. Steady, like a stone in a river.",
            wipeout: "A stone sinks. It also comes up again.",
            trick: "A hop. Even stones skip.",
            win: "The steady one wins. As stones do.",
            invite: "{reader}. Surfing. Stones skip, and so shall we.",
            yes: "Surfing, {reader}. Steadily.",
            no: "No, {reader}. A stone sinks."),
        "Prism": SurfVoice(
            start: "Surfing! Everyone watch me! Seven colours on one wave!",
            wave: "On it! Look at the light through the water! Look at ME!",
            wipeout: "That splash made a rainbow! On purpose! Mostly!",
            trick: "Spin! A rainbow spin! Applause, please!",
            win: "I won! Of course! Rainbows for everyone!",
            invite: "{reader}! Surfing! Come watch me shine on the waves!",
            yes: "Surfing! Yes, {reader}! I'll make rainbows!",
            no: "Not now, {reader}. My colours need the sun, not the sea."),
        // sprout
        "Sprout": SurfVoice(
            start: "Surfing! When I'm big I'll ride waves as tall as trees!",
            wave: "I'm riding it! I'm a big surfer now!",
            wipeout: "Splash! That's okay! Water helps me grow!",
            trick: "I did a hop! A big-surfer hop!",
            win: "I won! When I'm big I'll win every day!",
            invite: "{reader}! Surfing! I'm big enough now, I promise!",
            yes: "Surfing! Yes, {reader}! I'll be the biggest surfer!",
            no: "Not now, {reader}. Too much water and I'll grow too fast."),
        "Fern": SurfVoice(
            start: "Surfing... um... I'll paddle at the back... quietly...",
            wave: "Oh... I caught one... um... sorry, was that yours?",
            wipeout: "Um... I fell in... it's okay... don't look...",
            trick: "Um... a tiny hop... it was very small...",
            win: "I won? Um... are you sure? Oh... thank you...",
            invite: "Um... {reader}... surfing? Only if you want... quietly...",
            yes: "Um... yes, {reader}... surfing... I'll try my best...",
            no: "Um... not now, {reader}... sorry... maybe later..."),
        "Bud": SurfVoice(
            start: "Surfing! Watch me! I'll catch the first wave! Watch!",
            wave: "Watch me! I'm on it! Watch watch!",
            wipeout: "Splash! Did you watch? Watch me get back on!",
            trick: "A spin! Did you see? Watch again!",
            win: "I won! Did you watch? I won!",
            invite: "{reader}! Surfing! Watch me ride a wave! Come on!",
            yes: "Surfing! Yes, {reader}! Watch me!",
            no: "Not now, {reader}! But watch me later!"),
    ]
}

extension Plays.Surf {
    /// The board each built-in character paddles out on (`board-0` to `board-44`
    /// on the play sheet): every one its own. A character the user made gets one
    /// by its name.
    public static let boards: [String: Int] = [
        "Blocky": 7, "Pip": 2, "Mortimer": 17, "Zed": 13, "Dot": 5, "Ruth": 19,
        "Whiskers": 8, "Mittens": 23, "Sir Pounce": 0,
        "Hopper": 3, "Mossy": 15, "Croak": 30,
        "Boo": 26, "Wisp": 22, "Sheet": 35,
        "Morel": 16, "Puff": 32, "Cap": 9,
        "Unit 7": 24, "Sprocket": 34, "Glitch": 40,
        "Goop": 12, "Puddle": 10, "Blorp": 39,
        "Spike": 18, "Wedge": 25, "Delta": 42,
        "Prickles": 21, "Saguaro": 33, "Tumble": 11,
        "Click": 20, "Scarab": 29, "Crumb": 44,
        "Shard": 1, "Quartz": 6, "Prism": 4,
        "Sprout": 36, "Fern": 28, "Bud": 38,
    ]
    public static let boardCount = 45

    /// The board `name` surfs on, from 0 to `boardCount - 1`.
    public static func board(of name: String) -> Int {
        if let made = boards[name] { return made }
        // A stable hash: the same character keeps its board between launches.
        let sum = name.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
        return Int(sum % UInt32(boardCount))
    }
}

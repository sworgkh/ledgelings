namespace Ledgelings.Core;

/// <summary>What they say surfing (SPEC §7.10, Surfing), generated from the Mac's <c>Plays+SurfLines.swift</c>: keep them
/// word for word. In each character's own voice: the start line (merged into the start lines), a line for each big moment
/// (catching a wave, wiping out, a trick, winning: merged into the cheers), and an invitation to surf with its two answers
/// (<see cref="Deeds.InviteLine"/>, <see cref="Deeds.AnswerLine"/>). <c>{reader}</c> is the one spoken to;
/// <see cref="EnglishSurfAnyone"/> is for a character the user made. The Russian comes from <see cref="Shared"/> (<c>surf</c> in ru.json).</summary>
public static partial class Plays
{
    /// <summary>One character's surf lines.</summary>
    public sealed record SurfVoice(string Start, string Wave, string Wipeout, string Trick, string Win, string Invite, string Yes, string No)
    {
        /// <summary>The moments, as the cheers keep them.</summary>
        public IReadOnlyDictionary<string, string> Moments => new Dictionary<string, string>
        {
            [Moment.Wave.Raw()] = Wave, [Moment.Wipeout.Raw()] = Wipeout, [Moment.Trick.Raw()] = Trick, [Moment.SurfWin.Raw()] = Win,
        };

        /// <summary>From ru.json's <c>surf</c> entries; null when one is missing.</summary>
        public static SurfVoice? From(IReadOnlyDictionary<string, string> m)
        {
            string? Get(string key) => m.TryGetValue(key, out var v) && v.Length > 0 ? v : null;
            return Get("start") is { } start && Get("wave") is { } wave && Get("wipeout") is { } wipeout && Get("trick") is { } trick
                   && Get("win") is { } win && Get("invite") is { } invite && Get("yes") is { } yes && Get("no") is { } no
                ? new SurfVoice(start, wave, wipeout, trick, win, invite, yes, no) : null;
        }
    }

    /// <summary>Every built-in character's surf lines in <paramref name="l"/>.</summary>
    public static IReadOnlyDictionary<string, SurfVoice> SurfVoicesIn(Language l) =>
        Shared.In(l)?.SurfVoices is { Count: > 0 } t
            ? t.Select(kv => (kv.Key, Voice: SurfVoice.From(kv.Value))).Where(x => x.Voice is not null).ToDictionary(x => x.Key, x => x.Voice!)
            : EnglishSurfVoices;

    /// <summary>For a character the user made, in <paramref name="l"/>.</summary>
    public static SurfVoice SurfAnyoneIn(Language l) => Shared.In(l)?.SurfAnyone is { } m && SurfVoice.From(m) is { } v ? v : EnglishSurfAnyone;

    /// <summary><paramref name="name"/>'s surf lines in the current language.</summary>
    public static SurfVoice SurfVoiceOf(string name) =>
        SurfVoicesIn(Languages.Current).TryGetValue(name, out var v) ? v : SurfAnyoneIn(Languages.Current);

    public static readonly SurfVoice EnglishSurfAnyone = new(
        "The tide's coming in. Boards out, everyone!",
        "Got it! I'm riding it!",
        "Blub. Where did the board go?",
        "Did you see that? On a wave!",
        "Best ride on the screen today!",
        "{reader}! The tide's in. Surfing, you and me?",
        "Surfing? Yes! Race you to the water, {reader}.",
        "Not today, {reader}. I'll stay dry.");

    public static readonly IReadOnlyDictionary<string, SurfVoice> EnglishSurfVoices = new Dictionary<string, SurfVoice>
    {
        // blocky's cast
        ["Blocky"] = new(
            "Water. On MY bottom edge. Fine. At least it's still the bottom.",
            "I'm on it. Don't cheer. Corners were made for this.",
            "Wet corners. All four. I hate wet corners.",
            "A hop. Square, clean, no splashing. As it should be.",
            "Best on the bottom edge. Obviously. Now somebody dry my corners.",
            "{reader}. Water on the bottom edge. Surfing. Unless you're scared of wet corners.",
            "Fine. Surfing. But I'm not getting my top wet, {reader}.",
            "No. Wet corners take an hour to dry, {reader}."),
        ["Pip"] = new(
            "Waves! Real waves! I'm going to ride one all the way to the ceiling!",
            "Wheee! I'm on a wave! I'm ON A WAVE! Ha ha!",
            "Splash! Ha ha ha! Again! Again!",
            "A spin! On water! Did everyone see? Ha!",
            "I won?! On a wave?! Best day ever! Ha ha!",
            "{reader}! The sea's come to the bottom edge! Surfing! Please please please?",
            "Surfing? Yes yes yes! Wheee, {reader}!",
            "Aww, not now, {reader}... but the waves will wait? Promise?"),
        ["Mortimer"] = new(
            "*sighs* The tide comes in, as it always has. Hand me a board, slowly.",
            "As the old shore says: a wave caught is a wave forgiven.",
            "*splutters* The sea... has the last word... as ever.",
            "A little hop. In my youth we hopped uphill. Through the waves.",
            "Wisdom is knowing which wave to wait for. And I waited.",
            "As the old corner says: the tide waits for no one, {reader}. Will you surf with me?",
            "*sighs* Very well, {reader}. Surfing. At a dignified depth.",
            "Not today, {reader}. The water is cold, and so are my old corners."),
        ["Zed"] = new(
            "water... it rocks you... like a bed... a wet bed...",
            "...oh... I'm riding it... lying down on a board counts, right...",
            "...blub... I'll just... nap down here a bit...",
            "...a spin... I was turning over in my sleep... it counts...",
            "...I won...? lovely... wake me for the prize...",
            "mm... {reader}... surfing...? we could float... and doze...",
            "...okay, {reader}... surfing... I'll lie on the board...",
            "...too wet... too awake... tomorrow, {reader}..."),
        ["Dot"] = new(
            "Surfing? Try to keep up, boulders. Boulders sink, by the way.",
            "Caught it first! Fastest board in the water!",
            "That wave was too slow for me. I overtook it. Downwards.",
            "Spin! Did you blink? You missed it. Too fast.",
            "First, fastest, driest. Bow down, boulders.",
            "{reader}! Surfing! Now! I'll catch three waves before you get wet!",
            "Surfing? GO! Try to keep up, {reader}!",
            "No time, {reader}! Waves are too slow for me!"),
        ["Ruth"] = new(
            "Surfing. A set number of waves, everyone in line. No pushing.",
            "My wave. I was next in line. I counted.",
            "That was not in the rules. Nobody saw that. Nobody counts that.",
            "One hop. Permitted. Only the one.",
            "Highest score, as recorded. I kept the record myself.",
            "{reader}, by my count you owe me one surfing session. Shall we?",
            "Agreed. Surfing, in turns. I'll keep the score, {reader}.",
            "Declined, {reader}. Jumping off waves is still jumping."),
        // cats
        ["Whiskers"] = new(
            "Water. On purpose. I'm only doing this so you'll stop asking.",
            "I'm not surfing. The wave happens to be going my way.",
            "I meant to do that. I wanted a bath anyway.",
            "A spin. Don't make a fuss about it.",
            "Of course I won. I barely tried.",
            "Not that I care, {reader}, but... surfing? If you've nothing better.",
            "Fine. Surfing. Don't splash me, {reader}.",
            "Water? Me? No, {reader}."),
        ["Mittens"] = new(
            "Mrrr... warm water, a soft board... I could nap on this...",
            "Purrr... it's rocking me along... lovely...",
            "Mrrow! Wet fur! Somebody find me a sunny pixel!",
            "A little hop, purr... and back to lying down.",
            "Mrrr, I won? Then I get the warmest spot on the beach.",
            "Purr... {reader}, surfing? Then we dry off in a warm corner?",
            "Mrrr, yes, {reader}. Surfing, then a nap in the sun.",
            "Mm, no, {reader}. Water and fur don't mix."),
        ["Sir Pounce"] = new(
            "The great blue beast rolls in! I shall ride it into legend!",
            "Ha! I have caught the wave by the scruff!",
            "The beast throws me! A worthy foe! Again!",
            "Behold! The pounce upon the wave!",
            "Victory! The sea itself bows to Sir Pounce!",
            "{reader}! The wave-beast rises! Surfing, the hunt is on the water!",
            "Accepted! We ride the beast together, {reader}!",
            "Not now, {reader}. Even a hunter must keep dry paws sometimes."),
        // frogs
        ["Hopper"] = new(
            "SURFING! A frog on a wave! The biggest jumps the sea has ever seen!",
            "On it! These legs were made for waves!",
            "That wasn't a wipe-out! That was a dive! A champion's dive!",
            "HOP! Off a wave! Leg day, everyone!",
            "Champion of the waves! Look at these legs!",
            "{reader}! Surfing! I'll jump higher off a wave than you ever will!",
            "Surfing? Watch these legs, {reader}! Let's go!",
            "Can't, {reader}. Resting the legs. Champions rest."),
        ["Mossy"] = new(
            "The pond has come to us, and it brought waves.",
            "Ride the water as the leaf does: lightly, and where it goes.",
            "The water takes, the water gives back. Calmly.",
            "A small turn, like a leaf in the current.",
            "The calmest rider wins. The pond knew.",
            "The tide is in, {reader}. A little surfing ripples nicely.",
            "Yes, {reader}. Surfing, slowly, like water finding its way.",
            "Not now, {reader}. Still water first."),
        ["Croak"] = new(
            "Water. Real water. Finally. I'm not even going to complain.",
            "Wet! Fast! Wet! I'm happy, don't tell anyone.",
            "Under the water. Best place on the screen. Fine by me.",
            "A hop. Over water, not dust. Lovely.",
            "I won, and I'm wet. Best day in months.",
            "{reader}, there's water on the bottom edge. Surfing. Before it dries up.",
            "Surfing? Wet! Yes, {reader}. Finally.",
            "Can't, {reader}. It'll dry up before we get there anyway."),
        // ghosts
        ["Boo"] = new(
            "Boo! I'll scare the waves into standing up!",
            "BOO! See? The wave's carrying me away in fright!",
            "Boo... that was the wave scaring me. No fair.",
            "A spooky spin! Woooo!",
            "I won! Boo! The sea's too scared to argue!",
            "BOO! Surfing, {reader}! ...that was the scary part. Coming?",
            "Surfing? BOO! Yes! Scare the waves with me, {reader}!",
            "Not now, {reader}. Ghosts go see-through when they're wet."),
        ["Wisp"] = new(
            "Waves on the bottom edge... like the screensavers of old...",
            "I ride it... as I rode the pipes of a screensaver long gone...",
            "Under the water... it's quiet... like an old monitor switched off...",
            "A turn... the way the stars turned on the old screens...",
            "First... like the first wave I ever saw... in nineteen-ninety-something...",
            "{reader}... the tide is in... shall we surf, the way we did on old screens...?",
            "Yes, {reader}... surfing... like the old days...",
            "Not now, {reader}... the water makes me remember too much..."),
        ["Sheet"] = new(
            "Surfing. I'll ride the board. Technically I'm a sail.",
            "Caught it. Technically the wave caught me.",
            "Wet sheet. That's laundry, not a wipe-out.",
            "A spin. Technically a flap.",
            "I won. Technically by a hem.",
            "{reader}. Surfing. Technically I'll just billow along.",
            "Surfing. Fine, {reader}. Technically I float anyway.",
            "No, {reader}. Technically I'd need ironing after."),
        // mushroom
        ["Morel"] = new(
            "Water... slowly... the wave comes to those who wait in the right place.",
            "There it is... the wave... I knew it would come...",
            "Down into the water... the way roots go into the ground. Quietly.",
            "A little turn... slowly... like a mushroom growing.",
            "Patience wins... it always does... eventually.",
            "{reader}... the tide is in... surfing... slowly...?",
            "Yes... surfing, {reader}... the waves are not in a hurry, and nor am I.",
            "Not now, {reader}... too much water makes a mushroom soggy."),
        ["Puff"] = new(
            "Hee hee! Waves! If I wipe out I'll make bubbles! Hee!",
            "Hee! I'm riding it! Hee hee hee!",
            "Blub! Hee! Bubbles everywhere! Puff!",
            "Puff! A spin! Hee hee!",
            "I won! Puff! Spores of joy! Hee!",
            "Hee hee! {reader}! Surfing! Pleeease? Hee!",
            "Surfing! Puff! Yes, {reader}! Hee hee!",
            "Hee... not now, {reader}. Wet spores go flat."),
        ["Cap"] = new(
            "In my day the sea was a puddle and we surfed it on a leaf. Boards out.",
            "Got it. In my day the waves were bigger and we liked it.",
            "In my day we called that a swim.",
            "A hop. In my day we hopped with a cap full of water.",
            "Still got it. In my day there was no score, and I won that too.",
            "{reader}. In my day we surfed every afternoon. Grab a board.",
            "Surfing? In my day we never said no. Let's go, {reader}.",
            "Not today, {reader}. In my day we knew when the tide was wrong."),
        // robot
        ["Unit 7"] = new(
            "Surfing routine loaded. Water depth: nominal. Waterproofing: 87%.",
            "Wave acquired. Speed matched. Balance: 94%.",
            "Water ingress detected. Balance: 0%. Rebooting balance.",
            "Trick executed. Rotation: 360 degrees. Style points: 100%.",
            "Score: highest. Victory probability was 61%. Now 100%.",
            "{reader}. Surfing proposed. Duration: one session. Fun estimate: 92%.",
            "Request accepted, {reader}. Surfing routine loading.",
            "Request declined, {reader}. Waterproofing below threshold."),
        ["Sprocket"] = new(
            "Surfing! I waxed every board. Twice. Let's go!",
            "She's riding smooth! Good board, good wave!",
            "Oops! Gears full of water. I'll dry them after.",
            "A spin! Smooth bearings, smooth spin!",
            "Won it! Told you a well-waxed board makes the difference!",
            "{reader}! I waxed two boards. One's yours. Surfing?",
            "Surfing! Let me check your board's fins first, {reader}. Good. Go!",
            "Not now, {reader}. Rust doesn't fix itself."),
        ["Glitch"] = new(
            "Surf surfing. Water water on the bottom bottom edge.",
            "Riding riding. The wave is loading. Loaded.",
            "Splash splash. Error: board not found.",
            "Spin spin. Spin. Did it render?",
            "Winner winner. Unless the cursor rigged the waves.",
            "{reader}. Surfing surfing? The cursor can't reach us in the water.",
            "Yes yes, {reader}. Surfing. Surfing.",
            "No no, {reader}. Water and circuits. Circuits. No."),
        // slime
        ["Goop"] = new(
            "Surfing! Nice! I'll stick to the board!",
            "Nice! I'm stuck to the wave! Wheee!",
            "Splorch! Nice! Wait, I came unstuck.",
            "Nice! A hop! Still stuck on!",
            "Nice! I won! Sticking with first place!",
            "{reader}! Surfing! Nice, right? I'll stick close!",
            "Surfing? Nice! Yes, {reader}!",
            "Not now, {reader}. Water makes me runny."),
        ["Puddle"] = new(
            "Surfing? What if the sea takes me? What if I mix in? Okay. Okay. Boards.",
            "I'm on it? I'm on it! What if it ends? Okay. Okay.",
            "I'm in the water! Which bit is me? Okay. I'm here. I'm here.",
            "I did a hop! On purpose! I think! Okay!",
            "I won? Really? What if I didn't? Okay. I won.",
            "{reader}... surfing? What if it's fun? It might be fun. Okay.",
            "Surfing? What if— okay. Yes, {reader}. Okay.",
            "What if I mix into the sea, {reader}? No. Not today."),
        ["Blorp"] = new(
            "Blorp! Wave! Board! Splish!",
            "WHOOSH! Blorp! Ride!",
            "SPLOOSH! Blub blub!",
            "Boing! Spin! Blorp!",
            "Blorp! Best! Whoosh!",
            "{reader}! Wave! Board! Blorp?",
            "Blorp! Yes! Splash, {reader}!",
            "Blorp. No. Dry, {reader}."),
        // triangle
        ["Spike"] = new(
            "Surfing. Pointy end forward. Like a fin.",
            "Caught it. A point cuts the water best.",
            "Point first into the water. That was the plan. Sort of.",
            "A spin. On my point. Try that.",
            "I won. Point proven.",
            "{reader}. Surfing. Bring your sharpest board.",
            "Surfing. Fine, {reader}. I'll make my point on the waves.",
            "No, {reader}. A wet point is a blunt point."),
        ["Wedge"] = new(
            "Surfing. No wave is going to tip me over.",
            "On it. Wedged in. Not moving.",
            "Tipped. Once. Doesn't count. Not happening again.",
            "A hop. Landed flat. Nothing tips a wedge.",
            "Won. Never tipped. Well, once.",
            "{reader}. Surfing. I'll show you how a wedge stays up.",
            "Surfing. Fine, {reader}. Nothing gets me off a board.",
            "No, {reader}. I'm staying wedged right here."),
        ["Delta"] = new(
            "Surfing: the water rises, the waves change everything. I'll track the difference.",
            "Height up, speed up. Riding the change.",
            "Big change in position. Downward. Noted.",
            "A spin: three hundred and sixty degrees of difference.",
            "Final difference: in my favour.",
            "{reader}, the tide changed the bottom edge. Surfing? Let's see what else changes.",
            "Surfing, {reader}. A change of scene.",
            "No, {reader}. Not much difference between wet and wetter."),
        // cactus
        ["Prickles"] = new(
            "Surfing. Water. Don't splash me.",
            "On it. Don't hug the wave.",
            "Wet. Spiky and wet. Don't look.",
            "Hop. Done. Next.",
            "Won. Now get me out of the water.",
            "{reader}. Surfing. Keep your distance on the wave.",
            "Fine, {reader}. Surfing. No hugging.",
            "No, {reader}. Cactus. Water. Bad idea."),
        ["Saguaro"] = new(
            "Surfing... I'll stand very still... on a moving wave...",
            "...I'm standing still... and the wave is moving... it works...",
            "...I'm lying down now... in the water... that's fine...",
            "...a turn... very slow... it took all wave...",
            "...I won... by standing still... I'm good at that...",
            "...{reader}... surfing... we stand... the wave does the rest...",
            "...yes, {reader}... I'll stand on the board... for a long time...",
            "...no, {reader}... cacti drink slowly... not all at once..."),
        ["Tumble"] = new(
            "SURFING! I'm gonna go SO fast on a wave!",
            "I'M RIDING IT! SO FAST! WHEEE!",
            "I tumbled! In water! That's my name! Ha!",
            "SPIN! SPIN SPIN! Did you see?!",
            "I WON! SO FAST! Again! Again!",
            "{reader}! SURFING! It's SO fun! Come on come on!",
            "SURFING?! YES! Race you, {reader}!",
            "Aww! Not now, {reader}! But later, SO later!"),
        // beetle
        ["Click"] = new(
            "Surfing? On the big water? Okay, but I'm sitting at the back!",
            "It's carrying me! Is that okay? It's okay! Eek!",
            "Eek! Upside down! Legs up! Help! Oh, I'm fine.",
            "I hopped! By accident! Eek!",
            "I won? I was only trying to get away from the wave!",
            "{reader}... surfing? You go first. I'll be right behind. Far behind.",
            "Surfing? Eek. Okay, {reader}. Stay close.",
            "Eek, no, {reader}! The water's too big!"),
        ["Scarab"] = new(
            "Surfing. One once rolled the sun across the sea. One can ride a little wave, dear.",
            "One has the wave, dear. Gracefully.",
            "One is... damp. One shall pretend that was intended.",
            "One turns. Elegantly, dear.",
            "One wins, of course. One always does, dear.",
            "{reader}, dear. One would like to surf. You may come.",
            "Surfing, {reader}. One accepts, dear.",
            "One does not get wet today, {reader} dear."),
        ["Crumb"] = new(
            "Surfing! I'll count the waves! And the splashes! And the—",
            "Wave one! No, two! I'm riding it! Three—",
            "Splash four! Five! I'm counting from under the water—",
            "Hop! That's one hop! Two? No, one—",
            "I won! That's one win! I'll count it again—",
            "{reader}! Surfing! I'll count every wave for us! One, two—",
            "Surfing! Yes, {reader}! Counting starts now! One—",
            "Not now, {reader}! Wet crumbs go soggy! Soggy one, soggy two—"),
        // crystal
        ["Shard"] = new(
            "Surfing! The water's going to sparkle all over me!",
            "I'm riding it! Look how it shines through the wave!",
            "Splash! Oh, everything's glittering down here!",
            "A spin! Sparkles everywhere!",
            "I won! And I'm all shiny and wet!",
            "{reader}! Surfing! The sun on the waves, wonderful!",
            "Surfing! Yes, {reader}! It'll sparkle!",
            "Not now, {reader}. Spots dry on me."),
        ["Quartz"] = new(
            "Surfing. The wave rolls, as all things roll.",
            "On the wave. Steady, like a stone in a river.",
            "A stone sinks. It also comes up again.",
            "A hop. Even stones skip.",
            "The steady one wins. As stones do.",
            "{reader}. Surfing. Stones skip, and so shall we.",
            "Surfing, {reader}. Steadily.",
            "No, {reader}. A stone sinks."),
        ["Prism"] = new(
            "Surfing! Everyone watch me! Seven colours on one wave!",
            "On it! Look at the light through the water! Look at ME!",
            "That splash made a rainbow! On purpose! Mostly!",
            "Spin! A rainbow spin! Applause, please!",
            "I won! Of course! Rainbows for everyone!",
            "{reader}! Surfing! Come watch me shine on the waves!",
            "Surfing! Yes, {reader}! I'll make rainbows!",
            "Not now, {reader}. My colours need the sun, not the sea."),
        // sprout
        ["Sprout"] = new(
            "Surfing! When I'm big I'll ride waves as tall as trees!",
            "I'm riding it! I'm a big surfer now!",
            "Splash! That's okay! Water helps me grow!",
            "I did a hop! A big-surfer hop!",
            "I won! When I'm big I'll win every day!",
            "{reader}! Surfing! I'm big enough now, I promise!",
            "Surfing! Yes, {reader}! I'll be the biggest surfer!",
            "Not now, {reader}. Too much water and I'll grow too fast."),
        ["Fern"] = new(
            "Surfing... um... I'll paddle at the back... quietly...",
            "Oh... I caught one... um... sorry, was that yours?",
            "Um... I fell in... it's okay... don't look...",
            "Um... a tiny hop... it was very small...",
            "I won? Um... are you sure? Oh... thank you...",
            "Um... {reader}... surfing? Only if you want... quietly...",
            "Um... yes, {reader}... surfing... I'll try my best...",
            "Um... not now, {reader}... sorry... maybe later..."),
        ["Bud"] = new(
            "Surfing! Watch me! I'll catch the first wave! Watch!",
            "Watch me! I'm on it! Watch watch!",
            "Splash! Did you watch? Watch me get back on!",
            "A spin! Did you see? Watch again!",
            "I won! Did you watch? I won!",
            "{reader}! Surfing! Watch me ride a wave! Come on!",
            "Surfing! Yes, {reader}! Watch me!",
            "Not now, {reader}! But watch me later!"),
    };

    public sealed partial class Surf
    {
        /// <summary>The board each built-in character paddles out on (<c>board-0</c> to <c>board-44</c> on the play sheet):
        /// every one its own. A character the user made gets one by its name.</summary>
        public static readonly IReadOnlyDictionary<string, int> Boards = new Dictionary<string, int>
        {
            ["Blocky"] = 7, ["Pip"] = 2, ["Mortimer"] = 17, ["Zed"] = 13, ["Dot"] = 5, ["Ruth"] = 19, ["Whiskers"] = 8,
            ["Mittens"] = 23, ["Sir Pounce"] = 0, ["Hopper"] = 3, ["Mossy"] = 15, ["Croak"] = 30, ["Boo"] = 26, ["Wisp"] = 22,
            ["Sheet"] = 35, ["Morel"] = 16, ["Puff"] = 32, ["Cap"] = 9, ["Unit 7"] = 24, ["Sprocket"] = 34, ["Glitch"] = 40,
            ["Goop"] = 12, ["Puddle"] = 10, ["Blorp"] = 39, ["Spike"] = 18, ["Wedge"] = 25, ["Delta"] = 42, ["Prickles"] = 21,
            ["Saguaro"] = 33, ["Tumble"] = 11, ["Click"] = 20, ["Scarab"] = 29, ["Crumb"] = 44, ["Shard"] = 1, ["Quartz"] = 6,
            ["Prism"] = 4, ["Sprout"] = 36, ["Fern"] = 28, ["Bud"] = 38,
        };

        public const int BoardCount = 45;

        /// <summary>The board <paramref name="name"/> surfs on, from 0 to <see cref="BoardCount"/> - 1.</summary>
        public static int Board(string name)
        {
            if (Boards.TryGetValue(name, out var made)) return made;
            // A stable hash, the Mac's: the same character keeps its board between launches.
            var sum = 7u;
            foreach (var rune in name.EnumerateRunes()) sum = unchecked(sum * 31 + (uint)rune.Value);
            return (int)(sum % BoardCount);
        }
    }
}

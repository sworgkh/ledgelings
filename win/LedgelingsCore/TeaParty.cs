namespace Ledgelings.Core;

/// <summary>
/// A tea party: now and then two creatures who bump into each other do not
/// just trade a line and walk on. They step back, a little table with a teapot
/// and two cups comes up between them, and for a few minutes they sit and tell
/// each other stories from their lives, taking turns, a sip of quiet between
/// each. Then the table packs itself away and they go on their way.
///
/// seating → laying → tea → packing → over
///
/// The colony drives it: it says when both have reached their seats, runs each
/// <b>round</b> the party asks for (one tells a story, the other answers), says
/// when the round is over, and draws the table at <see cref="Scale"/>.
/// </summary>
public sealed class TeaParty
{
    public enum Phase
    {
        /// <summary>Both stepping back to their seats; no table yet.</summary>
        Seating,
        /// <summary>The table grows up out of the edge.</summary>
        Laying,
        /// <summary>Sitting and talking.</summary>
        Tea,
        /// <summary>The table shrinks away; they are about to walk on.</summary>
        Packing,
        Over,
    }

    public abstract record Event
    {
        /// <summary>Time for a round: <c>Teller</c> tells a story from its life, <c>Listener</c> answers.</summary>
        public sealed record Round(int Teller, int Listener) : Event;
        /// <summary>The table is gone: let the pair walk on.</summary>
        public sealed record Finished : Event;
    }

    public double AppearTime { get; set; } = 0.4;
    public double PackTime { get; set; } = 0.5;
    /// <summary>Longest the table waits for someone still walking to its seat.</summary>
    public double SeatingCap { get; set; } = 4;
    /// <summary>The first round waits this long after the table is up: the tea is poured.</summary>
    public double PourTime { get; set; } = 1.5;

    public int A { get; }
    public int B { get; }
    /// <summary>Seconds from the start the party lasts; a round under way is let finish.</summary>
    public double Length { get; }
    /// <summary>Seconds of quiet sipping between one round and the next.</summary>
    public double Pause { get; }
    public Phase CurrentPhase { get; private set; } = Phase.Seating;
    /// <summary>Rounds told so far.</summary>
    public int Rounds { get; private set; }
    public bool InRound { get; private set; }
    private readonly double started;
    private double phaseStarted;
    private double nextRound = double.PositiveInfinity;

    public TeaParty(int a, int b, double time, double length, double pause)
    {
        A = a; B = b;
        Length = Math.Max(0, length); Pause = Math.Max(0, pause);
        started = time;
        phaseStarted = time;
    }

    public bool Involves(int i) => i == A || i == B;
    public bool IsOver => CurrentPhase == Phase.Over;
    /// <summary>Still on: not yet packing up.</summary>
    public bool IsOn => CurrentPhase is Phase.Seating or Phase.Laying or Phase.Tea;
    public double EndsAt => started + Length;

    /// <summary>Both are in their chairs.</summary>
    public void Seated(double time)
    {
        if (CurrentPhase != Phase.Seating) return;
        Enter(Phase.Laying, time);
    }

    /// <summary>The round asked for is over (said, or skipped): sip, then the next.</summary>
    public void RoundDone(double time)
    {
        if (!InRound) return;
        InRound = false;
        Rounds += 1;
        nextRound = time + Pause;
    }

    /// <summary>The round could not start yet (the one voice is taken): ask again in <paramref name="seconds"/>.</summary>
    public void Postpone(double time, double seconds = 1)
    {
        if (!InRound) return;
        InRound = false;
        nextRound = time + seconds;
    }

    /// <summary>Break it up now: one of them was chased off, picked up, or sent home.</summary>
    public void End(double time)
    {
        switch (CurrentPhase)
        {
            case Phase.Seating: Enter(Phase.Over, time); break;
            case Phase.Laying or Phase.Tea: InRound = false; Enter(Phase.Packing, time); break;
        }
    }

    /// <summary>0 = not there, 1 = full size.</summary>
    public double Scale(double time)
    {
        var since = time - phaseStarted;
        return CurrentPhase switch
        {
            Phase.Laying => Math.Min(1, Math.Max(0, since / AppearTime)),
            Phase.Tea => 1,
            Phase.Packing => Math.Min(1, Math.Max(0, 1 - since / PackTime)),
            _ => 0,
        };
    }

    public List<Event> Update(double time)
    {
        var since = time - phaseStarted;
        switch (CurrentPhase)
        {
            case Phase.Seating:
                if (since >= SeatingCap) Enter(Phase.Laying, time);
                return new();
            case Phase.Laying:
                if (since >= AppearTime)
                {
                    Enter(Phase.Tea, time);
                    nextRound = time + PourTime;
                }
                return new();
            case Phase.Tea:
                if (InRound) return new();
                if (time >= EndsAt) { Enter(Phase.Packing, time); return new(); }
                if (time < nextRound) return new();
                InRound = true;
                // They take turns telling: the first round is A's.
                return new() { Rounds % 2 == 0 ? new Event.Round(A, B) : new Event.Round(B, A) };
            case Phase.Packing:
                if (since >= PackTime) { Enter(Phase.Over, time); return new() { new Event.Finished() }; }
                return new();
            default:
                return new();
        }
    }

    private void Enter(Phase next, double time)
    {
        CurrentPhase = next;
        phaseStarted = time;
    }

    // MARK: Where they sit

    /// <summary>Where on its own loop a creature sits for tea: <paramref name="offset"/> points from
    /// <paramref name="middle"/> (a point on this loop) along its segment, on the side away from
    /// the one it faces (<paramref name="facing"/> +1 = toward growing t). Null when that seat is
    /// past the end of the segment: no table round a corner.</summary>
    public static double? Seat(EdgeLoop loop, int segment, Pt middle, double facing, double offset)
    {
        var along = loop.Direction(segment);
        double back = facing < 0 ? 1 : -1;
        var chair = new Pt(middle.X + along.Dx * back * offset, middle.Y + along.Dy * back * offset);
        var found = loop.Nearest(chair);
        if (found.Distance >= 1 || loop.Segment(found.T) != segment) return null;
        return found.T;
    }

    /// <summary>Should this bump be a tea party? <paramref name="percent"/> of bumps are, 0...100.</summary>
    public static bool Wanted(double percent, Random rng) => percent > 0 && rng.NextDouble() * 100 < percent;
}

/// <summary>What they say over tea: stories from their lives, and what the other says back.
/// Each built-in character has its own, in its own voice; <c>Anyone…</c> is for a
/// character the user invented. <c>{other}</c> is the one across the table.</summary>
public static class Tea
{
    /// <summary>The current language's, character by character; English where it has none.</summary>
    public static IReadOnlyList<string> AnyoneStories => Translated.List(Shared.Current?.TeaAnyoneStories, EnglishAnyoneStories);
    public static IReadOnlyList<string> AnyoneReplies => Translated.List(Shared.Current?.TeaAnyoneReplies, EnglishAnyoneReplies);
    public static IReadOnlyDictionary<string, string[]> Stories => Translated.Lists(Shared.Current?.TeaStories, EnglishStories, l => l);
    public static IReadOnlyDictionary<string, string[]> Replies => Translated.Lists(Shared.Current?.TeaReplies, EnglishReplies, l => l);

    public static readonly IReadOnlyList<string> EnglishAnyoneStories = new[]
    {
        "I wasn't always on this edge, you know. I started out in a corner nobody visits.",
        "When I was small, I thought the screen went on forever. Then I found the first edge.",
        "Once I walked the whole way round without stopping. Nobody noticed. I still think about it.",
        "My secret? Every night I pick a pixel and make a wish on it.",
    };
    public static readonly IReadOnlyList<string> EnglishAnyoneReplies = new[]
    {
        "Really? I never knew that about you, {other}.",
        "That's lovely. More tea?",
        "Funny, something like that happened to me once.",
    };

    /// <summary>Four stories each: more than one character tells in a party of the default length.</summary>
    public static readonly IReadOnlyDictionary<string, string[]> EnglishStories = new Dictionary<string, string[]>
    {
        // blocky's cast
        ["Blocky"] = new[] { "I was the first one here. Before the colours, before the cursor. Those were good days.",
            "The cursor chased me into a corner once. I stared it down. It blinked first.",
            "I only ever wanted one thing: the bottom edge, all to myself. Still waiting.",
            "I had a friend once who liked the ceiling. We don't talk about him." },
        ["Pip"] = new[] { "I was born on the ceiling! Upside down! I thought everyone else was the wrong way up!",
            "Once I laughed so hard I fell off the top edge. Best day ever!",
            "My first word was 'wheee'. My second was also 'wheee'.",
            "I've never been sad, not once! Well, once. When the screen went dark. But it came back!" },
        ["Mortimer"] = new[] { "*sighs* In my youth I walked all four edges in one day. My knees remember it still.",
            "I once met a wise old pixel. It said nothing. I have thought about it for years.",
            "My father told me: the edge is long, but the tea is short. Drink up.",
            "I have outlived three wallpapers. Each one taught me something. Mostly about blue." },
        ["Zed"] = new[] { "I was born asleep. Woke up at about... noon. Went back to bed.",
            "Once I stayed awake a whole day. Never again. *yawn*",
            "My dream? A bed the size of this whole screen... and nobody waking me...",
            "I fell asleep at my own birthday. It was a very good birthday. I think." },
        ["Dot"] = new[] { "I did the whole bottom edge in four seconds once. Nobody timed it. Trust me.",
            "Grew up the smallest. Learned to be the fastest. Obviously.",
            "I raced the cursor once. Beat it. It still won't admit it.",
            "Secret? I get dizzy on the corners. Tell no one, boulder." },
        ["Ruth"] = new[] { "I have kept a list of every jump on this screen since the day I arrived. 4,211 so far.",
            "My mother ran a very tidy corner. I intend to do better.",
            "Once, just once, I jumped. For no reason. I still haven't forgiven myself.",
            "I organised the first walk-in-a-line. Nobody came. Rules are rules though." },
        // cat
        ["Whiskers"] = new[] { "Not that you asked, but I once had a sunny spot all to myself. For a whole afternoon.",
            "I came from a wallpaper with a sofa on it. I miss the sofa. Slightly.",
            "Somebody once petted me with the cursor. I allowed it. Once.",
            "I don't have stories. ...Fine. I was scared of the dock for a week." },
        ["Mittens"] = new[] { "Mrrr... I was born in the warmest corner, right by the clock. Still dream of it.",
            "Once I napped through a whole restart. Woke up somewhere new. Purr.",
            "My mama said: always find the sunny side. I'm still looking, mrrp.",
            "I had a ball of yarn once. It was just a pixel. I loved it anyway." },
        ["Sir Pounce"] = new[] { "I once stalked a notification for three whole minutes. It never saw me coming!",
            "My greatest hunt: the cursor, at dawn. It escaped. We shall meet again.",
            "I was knighted by a sleeping cat. It counts. It absolutely counts.",
            "As a kitten I pounced on my own shadow. It won. I have trained since." },
        // frog
        ["Hopper"] = new[] { "I once jumped clean over a whole window! Well, a small one. Well, a tooltip.",
            "Came out of an egg and jumped straight away! Haven't stopped since! Mostly!",
            "My record jump? Nobody saw it. Very big though! HUGE!",
            "I tried to jump to another monitor once. There wasn't one. Landed okay!" },
        ["Mossy"] = new[] { "A tadpole I was, in a pond of pure blue pixels. The pond remembers.",
            "My grandmother said: the still pond sees the moon. I sat still for a year.",
            "I once waited a whole season for one fly. It never came. The waiting was the point.",
            "Before this edge, I lived under a leaf icon. Quiet times, damp times." },
        ["Croak"] = new[] { "I came from a swamp. A real one. Wet. Nothing like this dry old edge.",
            "Had a lily pad once. Best thing I ever owned. Someone closed the window.",
            "Never liked jumping. Got born a frog anyway. Typical.",
            "Rained once, on the screen. Somebody's wallpaper. Happiest ten seconds of my life." },
        // ghost
        ["Boo"] = new[] { "I scared a cursor once! It went all spinny! Well, it was loading, but still!",
            "I've been a ghost since... always? I think I was born saying boo!",
            "My dream is to be a REALLY scary ghost. With chains. Little ones.",
            "One time somebody jumped when I said boo. Best day of my afterlife." },
        ["Wisp"] = new[] { "I remember a monitor, long gone now. It had the softest glow. I haunt its memory still.",
            "Once I drifted too far and nearly faded into the wallpaper. Someone called me back.",
            "I was a screensaver, you know. Before. Floating was all I knew.",
            "There was a window I loved. It closed one night and never opened again." },
        ["Sheet"] = new[] { "I used to be an actual sheet. On a bed. Technically I still am, emotionally.",
            "I have never walked in my life. I float. I want that on the record.",
            "Someone tried to fold me once. I haven't trusted a corner since.",
            "I was in a laundry basket before this. It was, technically, cosy." },
        // mushroom
        ["Morel"] = new[] { "I grew... in the dampest corner... slowly... over many screensavers...",
            "My family is very big... all under the ground... connected... we still talk...",
            "Once it was dark for three days... the best days of my life...",
            "I waited a long time... to be picked... nobody came... I grew instead..." },
        ["Puff"] = new[] { "Once I got SO excited I spored all over a whole window! Hee hee! They had to close it!",
            "I was the smallest mushroom in the patch! Now look at me! Still small! Hee!",
            "My best friend was a dandelion. We puffed together. Then the wind came.",
            "I've never been out in the rain! I want to! Just once! *puff*" },
        ["Cap"] = new[] { "In my day we grew in the dark and liked it. No wallpapers. No colours.",
            "In my day a mushroom stayed in one spot its whole life. Proud of it.",
            "I remember when this screen was only 800 wide. Everything was closer then.",
            "In my day we had respect. And moss. Mostly moss." },
        // robot
        ["Unit 7"] = new[] { "Activation date: unknown. First memory: this edge. Satisfaction: 71%.",
            "Once I computed the length of every edge. Total: 4,096 points. I recalculate daily.",
            "I had a firmware update once. I felt 3% different. I liked it.",
            "Secret file, opened: I would like, one day, to feel the sun. Probability: low." },
        ["Sprocket"] = new[] { "I was built from spare parts! Three different robots! Every one of them was lovely!",
            "My first memory is being tightened! Bliss!",
            "Once I oiled a whole row of rivets in one go. Still proud of that!",
            "I dream of a toolbox. A big one. With little drawers!" },
        ["Glitch"] = new[] { "I was booted up during a thunderstorm. That's why I repeat repeat myself.",
            "Once I scanned the whole screen. Found one virus. It was the cursor. As expected.",
            "I lost a whole afternoon to a memory leak. Don't remember remember it.",
            "My maker said I was perfect. Then I said perfect perfect. He sighed." },
        // slime
        ["Goop"] = new[] { "I was a drop of goo once! Then I grew! Now I'm a big goo! Nice!",
            "Found a sticky spot on the edge once. Stayed there a whole day. So nice.",
            "Mum was a slime too. She said: stay sticky. So I do!",
            "I got stuck on a corner once! Took ages! Was nice though!" },
        ["Puddle"] = new[] { "I once got SO close to a hot window. I lost nearly a whole drop. I still think about it.",
            "When I was little, I was scared of the cursor. I still am. But I was then too.",
            "I'm always worried I'll evaporate. My aunt did. Well, she became a cloud. It's fine. It's fine.",
            "I got stepped on once. Just a little. By a flower. I forgave it." },
        ["Blorp"] = new[] { "Blorp! Born! Splat! Here!",
            "Once: big jump! Splat! Best!",
            "Me? Little drip. Now? BIG BLORP.",
            "Mmm. Dream: puddle. Big puddle. Blorp." },
        // triangle
        ["Spike"] = new[] { "I was born pointy. Everybody said I'd soften. I didn't. Point proven.",
            "I popped a speech bubble once. By accident. Mostly.",
            "My one regret? That argument with a circle. It went round and round.",
            "I learned early: if you have a point, stand on it." },
        ["Wedge"] = new[] { "Nobody has ever tipped me over. Not once. People have tried.",
            "I was the base of a very tall pyramid, once. Held it all up. Nobody thanked me.",
            "My father never changed his mind. Neither have I. It's a family thing.",
            "Somebody tried to move me off this spot last year. I'm still here." },
        ["Delta"] = new[] { "The biggest change in my life? Arriving here. Everything since has been smaller.",
            "I have noticed every pixel that moved since I arrived. Mostly the cursor's fault.",
            "I was a different shape once. Slightly. One degree off. Nobody else saw.",
            "When I was small, the screen was dimmer. Now it's 12% brighter. I notice." },
    };

    public static readonly IReadOnlyDictionary<string, string[]> EnglishReplies = new Dictionary<string, string[]>
    {
        ["Blocky"] = new[] { "Hmph. Not bad, {other}. Better than most stories on this screen.",
            "That's nothing. I once waited a whole day for the cursor to leave.",
            "Sip your tea, {other}. We've all had it hard." },
        ["Pip"] = new[] { "Ooh! That's amazing, {other}! Tell me more! More more more!",
            "Haha, that's just like me! Well, not at all, but still!",
            "Aww! I love that! I love you! I love tea!" },
        ["Mortimer"] = new[] { "*sighs* Ah, {other}. That reminds me of my own youth, long ago.",
            "A wise story. My grandfather had one like it. Only longer.",
            "Hm. The edge teaches us all, in time. More tea?" },
        ["Zed"] = new[] { "Mm... that's nice, {other}... I dreamt something like that once...",
            "Sounds tiring... *sip*... I'd have napped through it.",
            "Wake me... when the next story is... *yawn*... oh, it's my turn?" },
        ["Dot"] = new[] { "Cute story, {other}. Took you long enough to tell it though.",
            "I'd have done that twice as fast. Just saying.",
            "Huh. Not bad, for a boulder." },
        ["Ruth"] = new[] { "Noted, {other}. I'll add it to my records.",
            "That was very nearly in order. Well told.",
            "Hm. That breaks at least two rules. I liked it anyway." },
        ["Whiskers"] = new[] { "Mm. Interesting. Not that I care. ...What happened next?",
            "I suppose that's a story. I've heard worse, {other}.",
            "Hmph. I would have done it better. Pour me more." },
        ["Mittens"] = new[] { "Purrr... that's so sweet, {other}. More tea, please.",
            "Mrrp... you remind me of a warm afternoon.",
            "Aww. I'd give you a nuzzle if the table wasn't in the way." },
        ["Sir Pounce"] = new[] { "A tale worthy of a hunter, {other}! I salute you!",
            "Ha! Bold! Daring! Almost as good as my own hunts!",
            "Magnificent! I shall pounce on that memory forever!" },
        ["Hopper"] = new[] { "Wow! That's a big one, {other}! Almost as big as my jumps!",
            "Ha! I'd have jumped right over that! Probably!",
            "Cool story! RIBBIT! My turn soon?" },
        ["Mossy"] = new[] { "Ah. The pond that listens hears everything, {other}.",
            "A frog who hears such a story grows a little wiser. Thank you.",
            "Still water runs deep. So do you, it seems." },
        ["Croak"] = new[] { "Hmph. At least it wasn't dry. Everything here is so dry.",
            "Could be worse, {other}. You could be a frog on a screen.",
            "Grumble. Fine. That was a good one. Don't tell anyone I said so." },
        ["Boo"] = new[] { "Ooooh! That's almost spooky, {other}! I love it!",
            "Boo! ...Sorry. That was a good story. I got excited.",
            "Wow! Can I tell that one to scare people?" },
        ["Wisp"] = new[] { "How beautiful, {other}. Like a light from a screen long gone.",
            "I'll keep that story with me, wherever I drift.",
            "Mm. Some memories float, some sink. That one floats." },
        ["Sheet"] = new[] { "Noted. Technically, that was a story. A good one.",
            "Interesting, {other}. I'd nod, but I'm a sheet.",
            "I had a similar experience. Technically. In a drawer." },
        ["Morel"] = new[] { "Mm... that story has deep roots... like mine...",
            "Slowly... I understand you better now... {other}...",
            "Damp... and true... I like that..." },
        ["Puff"] = new[] { "Eee! That's SO good, {other}! I'm gonna spore!",
            "Hee hee! Tell it again! No, tell a new one! No, both!",
            "*puff* Sorry! That happens when a story's good!" },
        ["Cap"] = new[] { "In my day we'd have called that a proper story, {other}.",
            "Not bad. In my day it'd have been longer. And wetter.",
            "Hm. You young ones have it easy. Still, well told." },
        ["Unit 7"] = new[] { "Story logged. Emotional impact: 64%. Thank you, {other}.",
            "Processing... processing... that was nice.",
            "Recorded to long-term memory. Tea level: 40%." },
        ["Sprocket"] = new[] { "Oh, what a story, {other}! It tightened my heart bolts!",
            "Wonderful! Well oiled! Like a good gear!",
            "I love it! Can I fix anything in it for you?" },
        ["Glitch"] = new[] { "Interesting interesting, {other}. No viruses detected in that story.",
            "Saving saving to memory. Hope it doesn't leak.",
            "I believe you. Unless the cursor put you up to it." },
        ["Goop"] = new[] { "Nice! Sticky story, {other}! Very nice!",
            "Aww. That's so nice. Like goo.",
            "Ooh! I like that one! Tell another!" },
        ["Puddle"] = new[] { "Oh no, that sounds so scary. But you're okay? You're okay.",
            "That's lovely, {other}. Could you... pass the saucer? In case I spill.",
            "I'd have been so worried! You're so brave!" },
        ["Blorp"] = new[] { "Blorp! Good story!", "Ooh! Wow! Splat!", "Mm! More! Blorp!" },
        ["Spike"] = new[] { "Sharp story, {other}. I'll allow it.",
            "Okay, that one had a point. Unlike most.",
            "Hm. Made your point. Well done." },
        ["Wedge"] = new[] { "Hm. I won't change my mind about you, {other}. But that was good.",
            "Solid story. Like me.",
            "Fine. I'll give you that one. Only that one." },
        ["Delta"] = new[] { "Interesting. I noticed a small change in you while you told that, {other}.",
            "That changes things. Slightly. Noted.",
            "The difference between you before that story and after: noticeable." },
    };

    /// <summary>A story from <paramref name="name"/>, one it has not told at this party when it has one left.</summary>
    public static string Story(string name, IReadOnlySet<string> told, Random rng)
    {
        IReadOnlyList<string> all = Stories.TryGetValue(name, out var own) ? own : AnyoneStories;
        var fresh = all.Where(s => !told.Contains(s)).ToList();
        return fresh.Count > 0 ? rng.Pick(fresh) : rng.Pick(all);
    }

    /// <summary>What <paramref name="name"/> says back to <paramref name="other"/>'s story.</summary>
    public static string Reply(string name, string other, Random rng)
    {
        IReadOnlyList<string> lines = Replies.TryGetValue(name, out var own) ? own : AnyoneReplies;
        return Banter.Render(rng.Pick(lines), new Dictionary<string, string> { ["other"] = other });
    }

    // MARK: With a model

    public static readonly IReadOnlyList<string> Placeholders = new[]
    {
        "speaker", "speakerKind", "speakerPersona", "listener", "listenerKind", "listenerPersona",
        "situation", "party", "line", "relationship",
    };

    /// <summary>Who they are, and that this is tea, not banter: stories, not jabs.</summary>
    public static string SystemPrompt => Shared.Prompt("teaSystem", EnglishSystemPrompt);
    public static string StoryPrompt => Shared.Prompt("teaStory", EnglishStoryPrompt);
    public static string ReplyPrompt => Shared.Prompt("teaReply", EnglishReplyPrompt);

    public const string EnglishSystemPrompt =
        "You are {speaker}, {speakerKind}, living on the edge of a computer screen. {speakerPersona}\n" +
        "You are having a tea party with {listener}, {listenerKind}, at a tiny table on the edge. {listenerPersona}\n" +
        "Over tea the two of you share stories from your lives. Speak in your own voice, true to who you are.\n" +
        "Say ONE line, at most 25 words. Output only the line. No quotes, no name prefix, no explanation.";

    /// <summary>The teller's turn.</summary>
    public const string EnglishStoryPrompt =
        "Right now: {situation}\n" +
        "Said at this tea party so far:\n" +
        "{party}\n" +
        "Tell {listener} one small story from your life that you have not told yet: where you come from, " +
        "a memory, a secret, a mistake, a dream.";

    /// <summary>The listener's answer to it.</summary>
    public const string EnglishReplyPrompt =
        "Right now: {situation}\n" +
        "Said at this tea party so far:\n" +
        "{party}\n" +
        "{listener} just told you: \"{line}\"\n" +
        "Answer in ONE line, in character: react to it, and give back a little piece of your own life.";

    /// <summary>The party so far, for <c>{party}</c>: the last <paramref name="keep"/> lines, "Name: line".</summary>
    public static string Transcript(IReadOnlyList<ChatLog.Line> lines, int keep = 8) =>
        lines.Count == 0 ? L10n.Tr("(nothing yet: the tea has just been poured)")
            : string.Join("\n", lines.TakeLast(keep).Select(l => $"{l.Speaker}: {l.Text}"));
}

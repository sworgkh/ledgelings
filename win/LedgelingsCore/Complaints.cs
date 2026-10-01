namespace Ledgelings.Core;

/// <summary>How often each creature has been pushed around by the user's cursor lately:
/// chased off its edge, or picked up. Past <see cref="Limit"/> times in a row it complains.
/// A quiet spell of <see cref="CalmAfter"/> seconds starts the count over, and so does
/// complaining: the next complaint needs a fresh streak.</summary>
public sealed class Annoyance
{
    public int Limit { get; set; }
    public double CalmAfter { get; set; }
    private Dictionary<int, (int Count, double Last)> streaks = new();

    public Annoyance(int limit = 4, double calmAfter = 20)
    {
        Limit = limit;
        CalmAfter = calmAfter;
    }

    /// <summary>Creature <paramref name="index"/> was pushed around at <paramref name="time"/>. True once this streak is
    /// past the limit: it has had enough and should say so.</summary>
    public bool Bothered(int index, double time)
    {
        var streak = streaks.TryGetValue(index, out var s) ? s : (Count: 0, Last: double.NegativeInfinity);
        if (time - streak.Last > CalmAfter) streak.Count = 0;
        streak.Count += 1;
        streak.Last = time;
        streaks[index] = streak;
        return streak.Count > Limit;
    }

    /// <summary>Times in a row creature <paramref name="index"/> has been pushed around, as of <paramref name="time"/>.</summary>
    public int Streak(int index, double time) =>
        streaks.TryGetValue(index, out var s) && time - s.Last <= CalmAfter ? s.Count : 0;

    /// <summary>It has complained: the count starts over.</summary>
    public void Forgive(int index) => streaks.Remove(index);

    /// <summary>Creatures from <paramref name="count"/> on are gone.</summary>
    public void Forget(int count) => streaks = streaks.Where(kv => kv.Key < count).ToDictionary(kv => kv.Key, kv => kv.Value);
}

/// <summary>What a creature says to the user when the cursor has chased it or carried
/// it around once too often. Each built-in character complains in its own
/// voice; <c>{times}</c> is how many times in a row it has been bothered.</summary>
public static class Complaints
{
    /// <summary>For a character the user invented.</summary>
    public static readonly IReadOnlyList<string> Anyone = new[]
    {
        "Hey! That's {times} times in a row. Leave me alone!",
        "Stop it with the cursor. I mean it.",
        "Do you mind? Some of us live here.",
    };

    public static readonly IReadOnlyDictionary<string, string[]> Lines = new Dictionary<string, string[]>
    {
        // blocky's cast
        ["Blocky"] = new[] { "{times} times. I have written every one of them down. Back off.",
            "THIS is why I hate the cursor. Get it off my edge.",
            "Again?! Point that thing somewhere else." },
        ["Pip"] = new[] { "Haha! Okay, okay, that was fun, but {times} times is a LOT!",
            "Wheee! ...wait, can I stay on the ceiling now? Please?",
            "You really like me, huh! Maybe a little less chasing?" },
        ["Mortimer"] = new[] { "*sighs* An old saying: the cursor that chases {times} times catches nothing.",
            "My bones are too old for all this leaping, young one.",
            "Patience is a virtue. Yours seems to be missing." },
        ["Zed"] = new[] { "I was *yawn* almost asleep. {times} times. Why.",
            "Can I just... nap somewhere the cursor isn't...",
            "Too tired for this. Stop. Please. Bed." },
        ["Dot"] = new[] { "{times} times and you STILL can't catch me, boulder.",
            "Faster than your cursor, obviously. Now quit it.",
            "Is that your top speed? Sad. Also: stop." },
        ["Ruth"] = new[] { "That is {times} times in a row. I am keeping count. Stop it.",
            "Excessive jumping. I disapprove. Put the cursor away.",
            "Rule one: no chasing. You have broken it {times} times." },
        // cat
        ["Whiskers"] = new[] { "Not that I care, but {times} times is rude. What do you want?",
            "I'm ignoring you. Completely. ...Stop that.",
            "Hmph. Chase a mouse instead. Oh wait." },
        ["Mittens"] = new[] { "Mrrrow... I was so warm and comfy. {times} times...",
            "Purr-lease stop, I just found the sunny side.",
            "Mrrp. Too much chasing. Pet me or let me be." },
        ["Sir Pounce"] = new[] { "The hunter is being HUNTED! {times} times! This is an outrage!",
            "I pounce on others. Nobody pounces on Sir Pounce!",
            "Retreat! Retreat! ...regroup, and then get revenge." },
        // frog
        ["Hopper"] = new[] { "Ha! {times} jumps! Best jumps ever! ...but my legs are tired now.",
            "RIBBIT! Stop chasing me! I'll jump SO far away!",
            "Okay, I jumped. A lot. You can stop now." },
        ["Mossy"] = new[] { "A frog chased {times} times finds no pond to rest in.",
            "Still water, calm frog. Stir it again and I croak.",
            "The pond is patient. I am not the pond." },
        ["Croak"] = new[] { "Grumble. {times} times. Too dry up here for all this jumping.",
            "Stop it. I'm drying out every time I leap.",
            "Leave me be. The edge is bad enough without you." },
        // ghost
        ["Boo"] = new[] { "Hey! I'M supposed to scare YOU! {times} times isn't fair!",
            "Boo! ...Boo? Why aren't you scared of me?!",
            "Stop chasing me, I'm the spooky one!" },
        ["Wisp"] = new[] { "Chased {times} times, like a memory that won't settle.",
            "Let me drift in peace. Even ghosts need rest.",
            "Please. I only wish to float here a while." },
        ["Sheet"] = new[] { "{times} times. I didn't run away, technically. I floated. Stop.",
            "I am a sheet. Please do not fold me with your cursor.",
            "That's harassment. Technically." },
        // mushroom
        ["Morel"] = new[] { "{times} times... a mushroom needs stillness... and damp...",
            "Slow down... I cannot grow if you keep moving me...",
            "Leave me... in my corner... please..." },
        ["Puff"] = new[] { "Eee! {times} times! Stop or I'll spore EVERYWHERE!",
            "Hee hee- no, really, stop! *puff*",
            "I'm gonna pop! Leave me alone!" },
        ["Cap"] = new[] { "In my day, nobody got chased {times} times by a cursor.",
            "In my day we had respect for our elders. And no cursors.",
            "Young people and their mice. Leave me be." },
        // robot
        ["Unit 7"] = new[] { "Warning: cursor contacts logged: {times}. Tolerance exceeded by 100%.",
            "Error 418: annoyance at 97%. Please cease.",
            "Evasive jumps logged: {times}. Requesting 0 more." },
        ["Sprocket"] = new[] { "{times} jumps in a row! My bolts are rattling loose!",
            "Careful! You're scratching my paint!",
            "I need maintenance after all that. Stop, please!" },
        ["Glitch"] = new[] { "The cursor cursor is chasing me. {times} times. VIRUS.",
            "Stop stop stop. I'm running a scan on you.",
            "Malware detected: your cursor. Keep it away away." },
        // slime
        ["Goop"] = new[] { "Not nice! Not sticky! {times} times is too many!",
            "Hey! I'm getting all stretched! Stop!",
            "Ow. Not nice. Leave me be, please?" },
        ["Puddle"] = new[] { "{times} times... please, I'm going to splash everywhere.",
            "Oh no, oh no, please don't step on me!",
            "Stop, I'm evaporating from all the stress!" },
        ["Blorp"] = new[] { "Blorp! {times}! Too much! Splat!",
            "No! Blorp no like! Go away!",
            "Zoom zoom STOP!" },
        // triangle
        ["Spike"] = new[] { "{times} times. I have a point, and it's: stop.",
            "Keep poking and you'll find out how sharp I am.",
            "Back off. Sharp edges." },
        ["Wedge"] = new[] { "{times} times and I'm still not tipping over. Give up.",
            "You won't move me on this. Stop trying.",
            "Stop. Pushing. Me. It won't work." },
        ["Delta"] = new[] { "The difference since last time: {times} jumps. Too many.",
            "Something changed: I'm annoyed now.",
            "Noticed: your cursor moved. At me. Again." },    };

    /// <summary>A complaint from <paramref name="name"/>, bothered <paramref name="times"/> times in a row.</summary>
    public static string Line(string name, int times, Random rng)
    {
        IReadOnlyList<string> lines = Lines.TryGetValue(name, out var own) ? own : Anyone;
        return Banter.Render(rng.Pick(lines), new Dictionary<string, string> { ["times"] = times.ToString() });
    }

    /// <summary>The model writes the complaint, in the creature's voice.</summary>
    public const string Prompt =
        "{situation}\n" +
        "The person whose screen you live on keeps chasing you with the mouse cursor and picking you up: " +
        "{times} times in a row now. You have had enough. Say ONE line to them, complaining, in your own voice. " +
        "At most 20 words. Output only the line: no quotes, no name.";
}

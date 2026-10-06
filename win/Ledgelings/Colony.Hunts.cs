using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The cursor's hunts (SPEC §4.7.2): every chase off an edge and every pick-up is counted per
/// character (<see cref="HuntBook"/>), and the creatures use their count. It rides in the prompts they
/// already send, says itself in built-in lines at a milestone or now and then instead of a complaint,
/// a tea story or a note, and in the menace mood makes a much-hunted creature keep further from the cursor.</summary>
public sealed partial class Colony
{
    private HuntBook? huntBook;
    /// <summary>How often the cursor has hunted each character: today, this week, in all.</summary>
    public HuntBook Hunts => huntBook ??= new HuntBook(Spend.Ledger.Directory);

    /// <summary>Creature <paramref name="i"/> was just chased off its edge or picked up. True when it said
    /// something about its count, so nothing else talks over it.</summary>
    private bool Hunted(int i)
    {
        if (!Settings.HuntCountEnabled || i < 0 || i >= creatures.Count) return false;
        var name = CharacterFor(i).Name;
        var n = Hunts.Count(name);
        BeWary(i);
        if (!Core.Hunts.IsMilestone(n) || !CanRemark(i, n)) return false;
        var line = Core.Hunts.Line(name, n, Settings.CursorMood, rng);
        Say(line, i);
        History.Record(new ChatLog.Exchange
        {
            Time = DateTimeOffset.Now, Situation = HuntSituation(i),
            Provider = AppSettings.BrainTitle(BrainKind.Script), Model = "",
            Lines = new List<ChatLog.Line> { new(name, line) },
        });
        return true;
    }

    private bool CanRemark(int i, Core.Hunts.Numbers n) =>
        Settings.HuntTalkEnabled && Settings.TalkEnabled && Core.Hunts.HasLine(n)
        && !busy.Contains(i) && !complaining.Contains(i) && !bubbles.ContainsKey(i) && !VoiceIsTakenNow;

    /// <summary>Today's count of everyone on screen, by name.</summary>
    private Dictionary<string, int> HuntsToday()
    {
        var today = new Dictionary<string, int>();
        for (int i = 0; i < creatures.Count; i++)
        {
            var name = CharacterFor(i).Name;
            today[name] = Math.Max(today.GetValueOrDefault(name), Hunts.NumbersOf(name).Today);
        }
        return today;
    }

    /// <summary>Whether this moment brings the count up: the chance in the Chases tab.</summary>
    private bool BringsItUp() =>
        Settings.HuntCountEnabled && Settings.HuntTalkEnabled && rng.NextDouble() * 100 < Settings.HuntTalkChance;

    /// <summary>What <paramref name="indices"/> know of their counts, for <c>{situation}</c>; "" when counting or talking
    /// about it is off, or (unless <paramref name="always"/>) this moment does not bring it up.</summary>
    public string HuntSentence(IEnumerable<int> indices, bool always = false)
    {
        if (!Settings.HuntCountEnabled || !Settings.HuntTalkEnabled || !(always || BringsItUp())) return "";
        var everyone = HuntsToday();
        return string.Join(" ", indices.Where(i => i >= 0 && i < creatures.Count)
            .Select(i => CharacterFor(i).Name)
            .Select(name => Core.Hunts.Sentence(name, Hunts.NumbersOf(name), everyone, Settings.CursorMood))
            .Where(s => s.Length > 0));
    }

    /// <summary>A built-in line about <paramref name="i"/>'s count to say instead of the usual one, now and then.</summary>
    public string? HuntLineInstead(int i)
    {
        if (i < 0 || i >= creatures.Count || !BringsItUp()) return null;
        var name = CharacterFor(i).Name;
        var n = Hunts.NumbersOf(name);
        return Core.Hunts.HasLine(n) ? Core.Hunts.Line(name, n, Settings.CursorMood, rng) : null;
    }

    /// <summary>For the Chats tab: the moment a creature spoke up about its count.</summary>
    private string HuntSituation(int i) =>
        string.Join(" ", new[] { AlmanacSentence, Describe(i) + ".", HuntSentence(new[] { i }, always: true) }.Where(s => s.Length > 0));

    /// <summary>In the menace mood, hunted <see cref="AppSettings.HuntWaryAfter"/> times today, it jumps away from further off.</summary>
    private void BeWary(int i)
    {
        if (i < 0 || i >= creatures.Count || i >= sizes.Count) return;
        var n = Hunts.NumbersOf(CharacterFor(i).Name);
        var wary = Settings.HuntCountEnabled && Settings.HuntWary && Core.Hunts.IsWary(n, Settings.HuntWaryAfter, Settings.CursorMood);
        creatures[i].Settings.FleeRadius = FleeRadius(sizes[i]) * (wary ? Core.Hunts.WaryFactor : 1);
    }

    /// <summary>Size, mood and the Chases tab all set how far off a creature jumps.</summary>
    partial void ApplyWariness()
    {
        for (int i = 0; i < creatures.Count; i++) BeWary(i);
    }

    /// <summary>The flee radius as it stands, for tests.</summary>
    public double FleeRadiusOf(int i) => creatures[i].Settings.FleeRadius;
}

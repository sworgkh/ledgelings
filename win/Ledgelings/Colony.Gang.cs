using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Plot twists, from the colony's side (SPEC §6.5.2.4), the Mac's <c>Colony+Gang</c>: every half minute
/// the roster sees who is on screen; a newcomer's first meetings become moments and facts of its pairs, a
/// departure a fact for the leaver's closest friends; and while the news is fresh, now and then a prompt
/// carries it, or a built-in line is about it. No call of its own: the news rides in prompts already sent.</summary>
public sealed partial class Colony
{
    /// <summary>Whether each pair's conversation brings up the gang's news, until when.</summary>
    internal readonly Dictionary<string, (double Until, bool Brings)> newsRolls = new();
    /// <summary>Every conversation brings the news up while it is fresh (tests).</summary>
    internal bool ForceNews { get; set; }

    /// <summary>Who is on screen now, by name, with their species' kind.</summary>
    internal Dictionary<string, string> GangPresent()
    {
        var present = new Dictionary<string, string>();
        for (int i = 0; i < creatures.Count; i++) present[CharacterFor(i).Name] = KindOf(i);
        return present;
    }

    /// <summary>The roster looks at who is on screen; each change it records is acted on.</summary>
    internal void ObserveGang(DateTimeOffset? at = null)
    {
        var present = GangPresent();
        if (present.Count == 0) return;
        var now = at ?? DateTimeOffset.Now;
        var known = Bonds.Book.Bonds.Values.SelectMany(b => b.Names).Distinct().ToList();
        var events = new List<Gang.Event>();
        Bonds.Change(book => events = book.Gang.Observe(present, now, known));
        foreach (var e in events) Happened(e);
    }

    /// <summary>A change of the gang: traced, and remembered by the closest friends of a leaver or a returner.</summary>
    private void Happened(Gang.Event e)
    {
        Trace?.Invoke($"twist {e.Kind} {e.Name}");
        if (!Settings.TwistsEnabled || !Settings.MemoryEnabled || !Settings.TwistDepartures || e.Kind == Gang.EventKind.Joined) return;
        var fact = e.Kind == Gang.EventKind.Left ? L10n.Tr("%@ left the gang", e.Name) : L10n.Tr("%@ came back to the gang", e.Name);
        foreach (var friend in ClosestFriends(e.Name))
        {
            Bonds.Change(book => book.Remember(friend, e.Name, fact, "gang", Settings.MemoryFacts, e.Time));
            Trace?.Invoke($"twist memory {Core.Bonds.Key(friend, e.Name)}: {fact}");
        }
    }

    /// <summary>The characters <paramref name="name"/> spent the most time with, most first.</summary>
    private List<string> ClosestFriends(string name, int count = 3) =>
        Bonds.Book.Closest.Where(b => b.Names.Contains(name) && b.Together > 0)
            .Select(b => b.Names.FirstOrDefault(n => n != name)).OfType<string>().Take(count).ToList();

    /// <summary>The news still fresh, as the settings have it.</summary>
    internal List<Gang.Event> FreshNews =>
        Settings.TwistsEnabled ? Bonds.Book.Gang.Fresh(Settings.TwistDays, DateTimeOffset.Now, Settings.TwistDepartures) : new();

    /// <summary>Whether the conversation between <paramref name="a"/> and <paramref name="b"/> brings the news up: one
    /// roll a pair, kept for two minutes so both sides of it agree; the chance fades with the news's age.</summary>
    private List<Gang.Event> NewsFor(string a, string b)
    {
        var events = FreshNews;
        if (events.Count == 0) return events;
        var key = Core.Bonds.Key(a, b);
        if (newsRolls.TryGetValue(key, out var roll) && roll.Until > Elapsed) return roll.Brings ? events : new();
        var chance = ForceNews ? 1 : Gang.Chance(Settings.TwistChance / 100, events, Settings.TwistDays, DateTimeOffset.Now);
        var brings = rng.NextDouble() < chance;
        newsRolls[key] = (Elapsed + 120, brings);
        return brings ? events : new();
    }

    /// <summary>The news block for <paramref name="a"/> talking to <paramref name="b"/>, when this conversation brings it up.</summary>
    private string News(string a, string b)
    {
        var events = NewsFor(a, b);
        if (events.Count == 0) return "";
        var text = Gang.News(events, a, Bonds.Book, DateTimeOffset.Now);
        Trace?.Invoke($"twist {a} hears: {text}");
        return text;
    }

    /// <summary>The news for a story or a diary, told of the pair: always while fresh.</summary>
    private string PairNews => Gang.News(FreshNews, null, null, DateTimeOffset.Now);

    /// <summary>The first time a fresh newcomer and another share anything: a "first meeting" moment of their
    /// storyline, and a fact both remember. A pair that has shared anything before has met.</summary>
    private void FirstMeeting(string a, string b)
    {
        if (!Settings.TwistsEnabled || a == b) return;
        var now = DateTimeOffset.Now;
        var fresh = Bonds.Book.Gang.Newcomers(Settings.TwistDays, now);
        var newcomer = new[] { a, b }.FirstOrDefault(fresh.Contains);
        if (newcomer is null || (Bonds.Bond(a, b)?.Tally.Values.Sum() ?? 0) > 0) return;
        var other = newcomer == a ? b : a;
        Bonds.Change(book =>
        {
            book.Note(newcomer, other, new Core.Bonds.Moment(now, Core.Bonds.MomentKind.Meet, newcomer));
            if (Settings.MemoryEnabled)
                book.Remember(newcomer, other, L10n.Tr("%1$@ and %2$@ first met when %1$@ was new to the gang", newcomer, other),
                              "gang", Settings.MemoryFacts, now);
        });
        Trace?.Invoke($"twist first meeting: {newcomer} meets {other}");
    }

    /// <summary>Built-in lines about the news, when this conversation brings it up: a newcomer or a returner talks
    /// about itself; otherwise each says its own line about whoever arrived, left or came back. Never gossip
    /// about the listener to its face.</summary>
    private List<(int Who, string Text, bool BuiltIn)>? BuiltInTwist(int speaker, int listener)
    {
        string a = CharacterFor(speaker).Name, b = CharacterFor(listener).Name;
        var events = NewsFor(a, b).Where(e => e.Name != b).ToList();
        var e = events.LastOrDefault(x => x.Name == a) ?? events.LastOrDefault();
        if (e is null) return null;
        Trace?.Invoke($"twist built in: {a} on {e.Kind} {e.Name}");
        var lines = new List<(int Who, string Text, bool BuiltIn)> { (speaker, Gang.Line(e, a, rng), true) };
        if (e.Name != a) lines.Add((listener, Gang.Line(e, b, rng), true));
        return lines;
    }

    /// <summary>An event made by hand, as if it had just happened (tests).</summary>
    internal void FakeTwist(string kind, string name)
    {
        ObserveGang();
        var species = GangPresent().TryGetValue(name, out var k) ? k : Bonds.Book.Gang.Members.TryGetValue(name, out var m) ? m.Kind : null;
        Gang.Event? e = null;
        Bonds.Change(book => e = book.Gang.Fake(kind, name, species, DateTimeOffset.Now));
        if (e is not null) Happened(e);
    }
}

namespace Ledgelings.Core.Tests;

/// <summary>The gang's roster: who is new, who left, who came back, nothing on the first look, and a sleeper is no
/// departure; the news and how often it comes up; every character's lines about it (SPEC §6.5.2.4). The Mac's GangTests.</summary>
public class GangTests
{
    private static readonly DateTimeOffset T0 = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);
    private static readonly Dictionary<string, string> Kinds = new() { ["Blocky"] = "a blocky creature", ["Boo"] = "a little ghost", ["Pip"] = "a blocky creature" };

    private static Dictionary<string, string> Present(params string[] names) =>
        names.ToDictionary(n => n, n => Kinds.TryGetValue(n, out var k) ? k : "a creature");

    [Fact]
    public void TheFirstLookKnowsEveryoneOnScreenAndEveryoneTheBondsRemember()
    {
        var r = new Gang.Roster();
        Assert.Empty(r.Observe(Present("Blocky", "Boo"), T0, new[] { "Blocky", "Mossy" }));
        Assert.Equal(T0, r.Started);
        Assert.Equal(3, r.Members.Count);
        Assert.Equal(T0, r.Members["Mossy"].Away);
        r.Observe(Present("Blocky", "Boo", "Mossy"), T0.AddSeconds(30));
        var back = r.Observe(Present("Blocky", "Boo", "Mossy"), T0.AddSeconds(200));
        Assert.Equal(Gang.EventKind.Returned, Assert.Single(back).Kind);
    }

    [Fact]
    public void ANewcomerCountsOnceItHasStayedAndAFlickerIsNobody()
    {
        var r = new Gang.Roster();
        r.Observe(Present("Blocky", "Boo"), T0);
        Assert.Empty(r.Observe(Present("Blocky", "Boo", "Pip"), T0.AddSeconds(30)));
        Assert.Empty(r.Observe(Present("Blocky", "Boo"), T0.AddSeconds(60)));
        Assert.False(r.Members.ContainsKey("Pip"));
        r.Observe(Present("Blocky", "Boo", "Pip"), T0.AddSeconds(100));
        Assert.Empty(r.Observe(Present("Blocky", "Boo", "Pip"), T0.AddSeconds(160)));
        var joined = Assert.Single(r.Observe(Present("Blocky", "Boo", "Pip"), T0.AddSeconds(230)));
        Assert.Equal(new Gang.Event(Gang.EventKind.Joined, "Pip", "a blocky creature", T0.AddSeconds(100)), joined);
        Assert.Empty(r.Observe(Present("Blocky", "Boo", "Pip"), T0.AddSeconds(300)));
    }

    [Fact]
    public void SomeoneGoneForTwoMinutesHasLeftAndComesBackWithItsPast()
    {
        var r = new Gang.Roster();
        r.Observe(Present("Blocky", "Boo", "Pip"), T0);
        Assert.Empty(r.Observe(Present("Blocky", "Pip"), T0.AddSeconds(60)));
        Assert.Equal(new Gang.Event(Gang.EventKind.Left, "Boo", "a little ghost", T0), Assert.Single(r.Observe(Present("Blocky", "Pip"), T0.AddSeconds(130))));
        Assert.Empty(r.Observe(Present("Blocky", "Pip"), T0.AddSeconds(400)));
        var day = T0.AddDays(1);
        Assert.Empty(r.Observe(Present("Blocky", "Pip", "Boo"), day));
        Assert.Equal(new Gang.Event(Gang.EventKind.Returned, "Boo", "a little ghost", day, T0),
                     Assert.Single(r.Observe(Present("Blocky", "Pip", "Boo"), day.AddSeconds(120))));
        Assert.Null(r.Members["Boo"].Away);
    }

    [Fact]
    public void SleepingHidingOrMovingMonitorIsNotLeaving()
    {
        var r = new Gang.Roster();
        r.Observe(Present("Blocky", "Boo"), T0);
        for (var minute = 1; minute <= 600; minute++) Assert.Empty(r.Observe(Present("Blocky", "Boo"), T0.AddSeconds(minute * 30)));
        Assert.Empty(r.Observe(Present("Blocky", "Boo"), T0.AddDays(3)));
    }

    [Fact]
    public void TheNewsIsFreshForTheDaysSetAndDeparturesCanBeLeftOut()
    {
        var r = new Gang.Roster();
        r.Observe(Present("Blocky", "Boo"), T0);
        r.Fake(Gang.EventKind.Joined, "Pip", "a blocky creature", T0);
        r.Fake(Gang.EventKind.Left, "Boo", "a little ghost", T0.AddSeconds(60));
        Assert.Equal(new[] { "Pip", "Boo" }, r.Fresh(3, T0.AddDays(1)).Select(e => e.Name));
        Assert.Equal(new[] { "Pip" }, r.Fresh(3, T0.AddDays(1), departures: false).Select(e => e.Name));
        Assert.Empty(r.Fresh(3, T0.AddDays(3).AddSeconds(120)));
        Assert.Equal(2, r.Fresh(7, T0.AddDays(3).AddSeconds(120)).Count);
        r.Fake(Gang.EventKind.Returned, "Boo", null, T0.AddSeconds(3600));
        Assert.Equal(new[] { Gang.EventKind.Joined, Gang.EventKind.Returned }, r.Fresh(3, T0.AddSeconds(7200)).Select(e => e.Kind));
        Assert.Equal(new HashSet<string> { "Pip" }, r.Newcomers(3, T0.AddSeconds(7200)));
        r.ForgetNews();
        Assert.Empty(r.Fresh(3, T0.AddSeconds(7200)));
        Assert.Equal(3, r.Members.Count);
    }

    [Fact]
    public void TheChanceFadesOverTheDays()
    {
        var e = new List<Gang.Event> { new(Gang.EventKind.Joined, "Pip", null, T0) };
        Assert.Equal(0.4, Gang.Chance(0.4, e, 4, T0));
        Assert.Equal(0.2, Gang.Chance(0.4, e, 4, T0.AddDays(2)), 9);
        Assert.Equal(0, Gang.Chance(0.4, e, 4, T0.AddDays(4)));
        Assert.Equal(0, Gang.Chance(0.4, new List<Gang.Event>(), 4, T0));
    }

    [Fact]
    public void TheNewsIsToldFromEachSide()
    {
        var joined = new Gang.Event(Gang.EventKind.Joined, "Pip", "a blocky creature", T0);
        var left = new Gang.Event(Gang.EventKind.Left, "Boo", "a little ghost", T0);
        var book = new Bonds.Book();
        book.Update("Blocky", "Boo", b => b.Summary = "rivals for the bottom edge");
        var blocky = Gang.News(new[] { joined, left }, "Blocky", book, T0);
        Assert.StartsWith("News in the gang: Pip, a blocky creature, is new to the gang: arrived today.", blocky);
        Assert.Contains("Boo has left the gang (today); nobody has seen Boo since", blocky);
        Assert.Contains("You and Boo: rivals for the bottom edge", blocky);
        Assert.Contains("You are new here: you joined the gang today", Gang.News(new[] { joined }, "Pip", null, T0));
        Assert.EndsWith("It may touch their story.", Gang.News(new[] { joined }, null, null, T0));
        Assert.Equal("", Gang.News(Array.Empty<Gang.Event>(), "Blocky", null, T0));
        Assert.Equal("prompt\nnews", Gang.WithNews("prompt", "news"));
    }

    [Fact]
    public void EveryCharacterHasItsOwnLineInEveryTableInBothLanguages()
    {
        var names = BedsTests.ShippedNames().ToHashSet();
        foreach (var language in new[] { Language.English, Language.Russian })
        {
            foreach (var (label, table) in new (string, Func<Shared, Dictionary<string, string>>, IReadOnlyDictionary<string, string>)[]
                     { ("new", s => s.GangNew, Gang.EnglishNewLines), ("gone", s => s.GangGone, Gang.EnglishGoneLines),
                       ("back", s => s.GangBack, Gang.EnglishBackLines), ("arrival", s => s.GangArrival, Gang.EnglishArrivalLines) }
                     .Select(t => (t.Item1, Gang.LinesIn(language, t.Item2, t.Item3))))
            {
                Assert.True(names.SetEquals(table.Keys), $"{label} {language}");
                Assert.All(table, kv => Assert.Equal(label != "arrival", kv.Value.Contains("{name}")));
                Assert.Equal(table.Count, table.Values.Distinct().Count());
            }
        }
        var russian = Shared.In(Language.Russian)!;
        Assert.Equal(39, russian.GangNew.Count);
        Assert.NotEqual(Gang.EnglishNewLines["Blocky"], russian.GangNew["Blocky"]);
        Assert.NotEmpty(russian.GangBackSelfAnyone);
    }

    [Fact]
    public void ALineIsAboutWhoeverItIsAboutInTheSpeakersVoice()
    {
        var rng = new Random(7);
        var pip = new Gang.Event(Gang.EventKind.Joined, "Pip", null, T0);
        Assert.Equal("New unit detected: Pip. Gang size up by 1.", Gang.Line(pip, "Unit 7", rng));
        Assert.Equal(Gang.EnglishArrivalLines["Pip"], Gang.Line(pip, "Pip", rng));
        Assert.Contains(Gang.Line(pip, "Somebody Imported", rng), Gang.EnglishNewAnyone.Select(l => l.Replace("{name}", "Pip")));
        Assert.Equal("Boo: no signal. Gang size down by 1.", Gang.Line(new Gang.Event(Gang.EventKind.Left, "Boo", null, T0), "Unit 7", rng));
        Assert.Contains(Gang.Line(new Gang.Event(Gang.EventKind.Returned, "Boo", null, T0, T0.AddDays(-1)), "Boo", rng), Gang.EnglishBackSelfAnyone);
    }

    [Fact]
    public void AFirstMeetingIsAMomentOfTheirStoryline()
    {
        var book = new Bonds.Book();
        book.Note("Pip", "Blocky", new Bonds.Moment(T0, Bonds.MomentKind.Meet, "Pip"));
        var bond = book.Bond("Pip", "Blocky")!;
        Assert.Equal(1, bond.Tally["meet"]);
        Assert.Equal("Pip, new to the gang, met Blocky for the first time", Bonds.Describe(bond.Moments[0], bond.Names));
        Assert.Equal("1 first meeting", Bonds.Tallied(bond.Tally));
        Assert.Contains("Pip", Bonds.BuiltInPlot(bond, T0, new Random(1)).Plot);
    }

    [Fact]
    public void TheRosterIsKeptInBondsJsonInTheMacsShapeAndAnOldFileStillLoads()
    {
        var dir = Path.Combine(Path.GetTempPath(), "ledgelings-gang-" + Guid.NewGuid());
        try
        {
            var store = new Bonds.Store(dir);
            Directory.CreateDirectory(dir);
            File.WriteAllText(store.File, """{"bonds":{"Blocky & Boo":{"names":["Blocky","Boo"],"together":60}}}""");
            var book = store.Load();
            Assert.Single(book.Bonds);
            Assert.Null(book.Gang.Started);
            book.Gang.Observe(Present("Blocky", "Boo"), T0);
            book.Gang.Fake(Gang.EventKind.Joined, "Pip", "a blocky creature", T0.AddSeconds(60));
            store.Save(book);
            var json = File.ReadAllText(store.File);
            Assert.Contains("\"gang\"", json);
            Assert.Contains("\"firstSeen\"", json);
            Assert.Contains("\"kind\": \"joined\"", json);
            Assert.Equal(book.Gang, store.Load().Gang);
        }
        finally { Directory.Delete(dir, true); }
    }
}

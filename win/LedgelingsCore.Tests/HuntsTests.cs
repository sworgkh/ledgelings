namespace Ledgelings.Core.Tests;

/// <summary>The cursor's hunts (SPEC §4.7.2): counted per character by the user's calendar day and week,
/// kept on disk, reset, and known to the creatures in every mood and language. The Mac's HuntsTests.</summary>
public class HuntsTests
{
    private static readonly TimeZoneInfo Zone = TimeZoneInfo.FindSystemTimeZoneById(OperatingSystem.IsWindows() ? "Israel Standard Time" : "Asia/Jerusalem");
    /// <summary>Monday-first, like most of Europe; tests that need Sunday-first say so.</summary>
    private static Hunts.Clock Clock(DayOfWeek first = DayOfWeek.Monday) => new(Zone, first);

    /// <summary>2026-10-06 is a Tuesday.</summary>
    private static DateTimeOffset At(int day, int hour, int minute = 0, int month = 10)
    {
        var local = new DateTime(2026, month, day, hour, minute, 0, DateTimeKind.Unspecified);
        return new DateTimeOffset(local, Zone.GetUtcOffset(local));
    }

    [Fact]
    public void ItCountsTodayYesterdayTheWeekAndInAll()
    {
        var c = Clock();
        var book = new Hunts.Book();
        for (var k = 0; k < 4; k++) book.Count("Blocky", At(4, 12), c);      // Sunday: last week
        for (var k = 0; k < 2; k++) book.Count("Blocky", At(5, 9), c);       // Monday
        for (var k = 0; k < 3; k++) book.Count("Blocky", At(6, 10), c);      // Tuesday
        book.Count("Zed", At(6, 11), c);
        var n = book.NumbersOf("Blocky", At(6, 18), c);
        Assert.Equal(new Hunts.Numbers(Today: 3, Yesterday: 2, Week: 5, All: 9, BestBefore: 4, DaysBeforeToday: 1), n);
        var total = book.Total(At(6, 18), c);
        Assert.Equal((4, 6, 10), (total.Today, total.Week, total.All));
        Assert.Equal(new Hunts.Numbers(), book.NumbersOf("Nobody", At(6, 18), c));
    }

    [Fact]
    public void ANewDayStartsAtTheUsersMidnight()
    {
        var c = Clock();
        var book = new Hunts.Book();
        book.Count("Pip", At(6, 23, 59), c);
        book.Count("Pip", At(7, 0, 1), c);
        var n = book.NumbersOf("Pip", At(7, 0, 2), c);
        Assert.Equal((1, 1, 2, 2), (n.Today, n.Yesterday, n.Week, n.All));
        var next = book.NumbersOf("Pip", At(8, 12), c);
        Assert.Equal((0, 1, 2), (next.Today, next.Yesterday, next.Week));
    }

    [Fact]
    public void TheWeekStartsWhereTheCultureStartsIt()
    {
        var book = new Hunts.Book();
        book.Count("Dot", At(4, 12), Clock(DayOfWeek.Sunday));
        Assert.Equal(1, book.NumbersOf("Dot", At(6, 12), Clock(DayOfWeek.Sunday)).Week);      // a Sunday-first week holds the 4th
        Assert.Equal(0, book.NumbersOf("Dot", At(6, 12), Clock(DayOfWeek.Monday)).Week);      // a Monday-first week started on the 5th
        Assert.Equal(0, book.NumbersOf("Dot", At(12, 9), Clock()).Week);
        Assert.Equal(1, book.NumbersOf("Dot", At(12, 9), Clock()).All);
    }

    [Fact]
    public void OldDaysAreLetGoButTheCountInAllStays()
    {
        var book = new Hunts.Book();
        var start = At(1, 12, month: 1);
        for (var d = 0; d < 200; d++) book.Count("Ruth", start.AddDays(d), Clock());
        Assert.True(book.Tallies["Ruth"].Days.Count <= Hunts.DaysKept + 1);
        Assert.Equal(200, book.Tallies["Ruth"].All);
    }

    [Fact]
    public void ItSurvivesARelaunchAndResets()
    {
        var dir = Path.Combine(Path.GetTempPath(), "ledgelings-hunts-" + Guid.NewGuid());
        try
        {
            var book = new Hunts.Book();
            book.Count("Blocky", At(6, 12), Clock()); book.Count("Blocky", At(6, 12), Clock()); book.Count("Pip", At(6, 12), Clock());
            new Hunts.Store(dir).Save(book);
            Assert.Contains("\"tallies\"", File.ReadAllText(Path.Combine(dir, "hunts.json")));      // the Mac's keys
            var loaded = new Hunts.Store(dir).Load();
            Assert.Equal(2, loaded.NumbersOf("Blocky", At(6, 13), Clock()).Today);
            Assert.NotNull(loaded.Since);
            loaded.Reset("Blocky");
            Assert.False(loaded.Tallies.ContainsKey("Blocky"));
            Assert.Equal(1, loaded.Tallies["Pip"].All);
            Assert.NotNull(loaded.Since);
            loaded.Reset();
            Assert.Empty(loaded.Tallies);
            Assert.Null(loaded.Since);      // reset all forgets since when, too
            Assert.Empty(new Hunts.Store(Path.Combine(dir, "none")).Load().Tallies);
        }
        finally { if (Directory.Exists(dir)) Directory.Delete(dir, true); }
    }

    [Fact]
    public void MilestonesRecordsAndWariness()
    {
        Assert.True(Hunts.IsMilestone(new(Today: 10, All: 40)));
        Assert.True(Hunts.IsMilestone(new(Today: 3, All: 100)));
        Assert.True(Hunts.IsMilestone(new(Today: 8, All: 60, BestBefore: 7)));      // the first hunt past the best day
        Assert.False(Hunts.IsMilestone(new(Today: 9, All: 60, BestBefore: 7)));
        Assert.False(Hunts.IsMilestone(new(Today: 4, All: 60, BestBefore: 3)));     // a best day of three is no record
        Assert.False(Hunts.IsMilestone(new(Today: 11, All: 61)));
        Assert.True(Hunts.IsWary(new(Today: 20), 20, CursorMood.Bad));
        Assert.False(Hunts.IsWary(new(Today: 19), 20, CursorMood.Bad));
        Assert.False(Hunts.IsWary(new(Today: 50), 20, CursorMood.Good));             // a playmate is not wary
        Assert.False(Hunts.IsWary(new(Today: 50), 20, CursorMood.Neutral));
        Assert.False(Hunts.HasLine(new(Today: 1, All: 50)));
        Assert.True(Hunts.HasLine(new(Today: 2, All: 2)));
    }

    [Fact]
    public void ThePromptCarriesTheNumbersAndTheMood()
    {
        var n = new Hunts.Numbers(Today: 7, Yesterday: 3, Week: 10, All: 412, BestBefore: 6, DaysBeforeToday: 1);
        Languages.With(Language.English, () =>
        {
            var bad = Hunts.Sentence("Blocky", n, new Dictionary<string, int> { ["Blocky"] = 7, ["Zed"] = 2 }, CursorMood.Bad);
            Assert.Equal("Today the user's cursor has chased or picked up Blocky 7 times (yesterday 3 times), 10 times this week and 412 times in all. "
                + "That is more than yesterday already. Earlier days this week averaged 3. It is Blocky's most hunted day on record. "
                + "Blocky is the most hunted of everyone on screen today. Blocky keeps it as a tally of grievances. "
                + "Blocky may bring the numbers up, or compare them, if it fits.", bad);
            Assert.Contains("proudly", Hunts.Sentence("Blocky", n, null, CursorMood.Good));
            Assert.Contains("matter-of-fact", Hunts.Sentence("Blocky", n, null, CursorMood.Neutral));
            Assert.DoesNotContain("most hunted of everyone", Hunts.Sentence("Blocky", n, new Dictionary<string, int> { ["Blocky"] = 7, ["Zed"] = 9 }, CursorMood.Bad));
            Assert.Contains("quiet so far", Hunts.Sentence("Blocky", new(Yesterday: 2, Week: 2, All: 5), null, CursorMood.Bad));
            Assert.Equal("", Hunts.Sentence("Blocky", new(), null, CursorMood.Bad));
            Assert.Contains("1 time (yesterday 0 times)", Hunts.Sentence("Blocky", new(Today: 1, All: 1), null, CursorMood.Bad));
        });
        Languages.With(Language.Russian, () =>
        {
            var ru = Hunts.Sentence("Blocky", n, null, CursorMood.Bad);
            Assert.Contains("сегодня 7 раз", ru);
            Assert.Contains("вчера 3 раза", ru);
            Assert.Contains("всего 412 раз", ru);
            Assert.Contains("обидам", ru);
            Assert.Contains("гордится", Hunts.Sentence("Blocky", n, null, CursorMood.Good));
        });
    }

    [Fact]
    public void EveryCharacterSaysItsCountInEveryMoodAndLanguage()
    {
        var shipped = Complaints.EnglishLines.Keys.ToHashSet();
        var allowed = new HashSet<string> { "today", "week", "all" };
        foreach (var mood in CursorMoods.All)
            foreach (var l in Languages.All)
            {
                var sets = Hunts.LinesIn(mood, l);
                Assert.True(shipped.SetEquals(sets.Keys), $"{mood} {l.Code()}");
                Assert.NotEmpty(Hunts.AnyoneIn(mood, l));
                foreach (var line in sets.Values.SelectMany(x => x).Concat(Hunts.AnyoneIn(mood, l)))
                {
                    var used = System.Text.RegularExpressions.Regex.Matches(line, @"\{(\w+)\}").Select(m => m.Groups[1].Value).ToHashSet();
                    Assert.True(used.Count > 0 && used.IsSubsetOf(allowed), $"{mood} {l.Code()}: {line}");
                }
                if (l != Language.English)
                    foreach (var name in shipped)
                    {
                        Assert.NotEqual(Hunts.LinesIn(mood, Language.English)[name], sets[name]);      // its own text, from ru.json
                        Assert.Equal(Hunts.LinesIn(mood, Language.English)[name].Length, sets[name].Length);
                    }
            }
    }

    [Fact]
    public void ALineIsSaidWithTheNumbersFilledIn()
    {
        var rng = new Random(7);
        var n = new Hunts.Numbers(Today: 7, Week: 31, All: 412);
        foreach (var mood in CursorMoods.All)
            foreach (var name in new[] { "Unit 7", "Somebody New" })
            {
                var line = Languages.With(Language.English, () => Hunts.Line(name, n, mood, rng));
                Assert.DoesNotContain("{", line);
                Assert.True(line.Contains("7") || line.Contains("31") || line.Contains("412"), line);
            }
    }
}

using System.Text.Json;

namespace Ledgelings.Core.Tests;

/// <summary>A pair's long-term memory (SPEC §6.5.2.3): facts, days, the games record, the block a prompt
/// carries within its budget, a creature's day so far, the diary's answer, and
/// the seed's digest of the chat log. The Mac's MemoryTests.</summary>
public class MemoryTests
{
    private static readonly string Root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../.."));
    private static readonly DateTimeOffset Day = DateTimeOffset.FromUnixTimeSeconds(1_760_950_800);     // 20 Oct 2025, 09:00 UTC

    private static Bonds.Moment Game(Plays.Kind kind, DateTimeOffset time, string[]? winners, string? score, string? asked = null, string who = "Blocky") =>
        new(time, Bonds.MomentKind.Play, who, kind.Raw(), score, winners, asked);

    [Fact]
    public void GamesCountTheirWinnerAndTheirDay()
    {
        Languages.With(Language.English, () =>
        {
            var book = new Bonds.Book();
            book.Note("Blocky", "Boo", Game(Plays.Kind.Soccer, Day, new[] { "Boo" }, "2-3", asked: "Boo"));
            book.Note("Blocky", "Boo", Game(Plays.Kind.Soccer, Day.AddSeconds(600), new[] { "Boo", "Blocky" }, "4-1"));
            book.Note("Blocky", "Boo", Game(Plays.Kind.Basketball, Day.AddSeconds(900), Array.Empty<string>(), "1-1"));
            book.Note("Blocky", "Boo", Game(Plays.Kind.Rope, Day.AddSeconds(950), null, null));
            var bond = book.Bond("Blocky", "Boo")!;
            Assert.Equal(new Dictionary<string, int> { ["soccer|Boo"] = 1, ["basketball|="] = 1 }, bond.Record);    // teammates who win together beat nobody
            Assert.Equal("Basketball: 1 draw; Soccer: Boo 1", Bonds.RecordLine(bond));
            Assert.True(bond.Days.Count == 1 && bond.Days[0].Day == Bonds.DayKey(Day));
            Assert.Equal(new Dictionary<string, int> { ["play"] = 4 }, bond.Days[0].Counts);
            Assert.Equal("Soccer: won by Boo, 2-3; Boo asked for it", bond.Days[0].Games[0]);
            Assert.True(Bonds.LastLost("Blocky", bond) == Plays.Kind.Soccer && Bonds.LastLost("Boo", bond) is null);
            Assert.EndsWith("(won by Boo, 2-3; Boo asked for it)", Bonds.Describe(bond.Moments[0], bond.Names));
        });
    }

    [Fact]
    public void FactsAreDatedDeduplicatedAndCapped()
    {
        var book = new Bonds.Book();
        var texts = new[] { "Boo owes Blocky a sunflower", "boo owes blocky a sunflower", "They share the cache at six", "Blocky guards the garden" };
        for (int k = 0; k < texts.Length; k++) book.Remember("Blocky", "Boo", texts[k], "note", keep: 2, at: Day.AddSeconds(k));
        Assert.Equal(new[] { "They share the cache at six", "Blocky guards the garden" }, book.Bond("Blocky", "Boo")!.Facts.Select(f => f.Text));
        book.Remember("Blocky", "Boo", "anything", "note", keep: 0);
        Assert.Empty(book.Bond("Blocky", "Boo")!.Facts);                                  // 0 keeps none
    }

    [Fact]
    public void TheMemoryBlockStaysWithinItsBudgetAndDropsTheStoryFirst()
    {
        Languages.With(Language.English, () =>
        {
            var book = new Bonds.Book();
            book.Note("Blocky", "Boo", Game(Plays.Kind.Soccer, Day, new[] { "Boo" }, "2-3"));
            book.Remember("Blocky", "Boo", "Boo owes Blocky a sunflower", "note", keep: 5, at: Day);
            book.Update("Blocky", "Boo", b => b.Chronicle = "They met on the bottom edge. They argued about the garden. They made up over tea. They guard the garden together now.");
            var bond = book.Bond("Blocky", "Boo")!;
            var full = Bonds.Memory(bond, "Blocky", "Boo", 400, Day);
            Assert.True(full.Contains("You and Boo first met on") && full.Contains("Your story so far: They met"), full);
            Assert.True(full.Contains("Games between you: Soccer: Boo 1.") && full.Contains("You remember: Boo owes Blocky a sunflower (20 Oct)."), full);
            Assert.EndsWith("Today together: 1 game; Soccer: won by Boo, 2-3.", full);
            Assert.True(full.IndexOf("Your story", StringComparison.Ordinal) < full.IndexOf("Today", StringComparison.Ordinal), "the story first, today last");
            foreach (var budget in new[] { 10, 30, 60, 90 })
            {
                var cut = Bonds.Memory(bond, "Blocky", "Boo", budget, Day);
                Assert.True(Bonds.Tokens(cut) <= budget, $"{budget}: {cut}");
            }
            var small = Bonds.Memory(bond, "Blocky", "Boo", 30, Day);
            Assert.True(small.Contains("Today together") && !small.Contains("Your story"), "today stays, the story goes");
            Assert.Empty(Bonds.Memory(bond, "Blocky", "Boo", 0, Day));
            // Never half a sentence of their story, and one full stop after a fact.
            for (int budget = 30; budget <= 120; budget++)
            {
                var cut = Bonds.Memory(bond, "Blocky", "Boo", budget, Day);
                Assert.True(!cut.Contains('…') && !cut.Contains(".."), $"{budget}: {cut}");
                var story = cut.IndexOf("Your story so far: ", StringComparison.Ordinal);
                if (story >= 0) Assert.True(cut[(story + "Your story so far: ".Length)..].StartsWith("They", StringComparison.Ordinal), $"starts on a whole sentence: {cut}");
            }
            var dotted = new Bonds.Book();
            dotted.Remember("A", "B", "A owes B a poppy.", "seed", keep: 5);
            Assert.Equal("You remember: A owes B a poppy.", Bonds.Memory(dotted.Bond("A", "B"), "A", "B", 100));
            Assert.Empty(Bonds.Memory(null, "Blocky", "Boo", 150));
        });
    }

    [Fact]
    public void ACreaturesDayIsToldFromItsSideAndAGameOnce()
    {
        Languages.With(Language.English, () =>
        {
            var book = new Bonds.Book();
            var soccer = Game(Plays.Kind.Soccer, Day, new[] { "Boo", "Zed" }, "2-3");
            book.Note("Blocky", "Boo", soccer);
            book.Note("Blocky", "Zed", soccer);
            book.Note("Blocky", "Boo", new Bonds.Moment(Day.AddSeconds(600), Bonds.MomentKind.Flower, "Boo", "poppy"));
            book.Note("Blocky", "Zed", new Bonds.Moment(Day.AddSeconds(900), Bonds.MomentKind.Talk, "Zed", "Hi"));
            book.Note("Blocky", "Zed", new Bonds.Moment(Day.AddSeconds(-86_400), Bonds.MomentKind.Tea, "Zed"));
            var told = Bonds.DaySoFar("Blocky", book, 4, Day.AddSeconds(1000));
            Assert.StartsWith("Your day so far: got a poppy from Boo at ", told);
            Assert.True(told.Contains("played a game of soccer with ") && told.Contains("Boo") && told.Contains("Zed") && told.Contains("(won by Boo, Zed, 2-3)"), told);
            Assert.True(!told.Contains("tea") && !told.Contains("Hi"), "yesterday's tea and the talks are left out");
            Assert.Equal(2, told.Split("a game of soccer").Length);                       // once, not once per pair
            Assert.Empty(Bonds.DaySoFar("Blocky", book, 0, Day));
        });
    }

    [Fact]
    public void TheDiaryIsReadAndWrittenIn()
    {
        const string raw = "<think>hmm</think>\n" +
                           "**STORY:** Since 22 Oct they guard the garden together.\n" +
                           "FACT: Boo owes Blocky a sunflower (19 Oct)\n" +
                           "FACT: They meet at the cache at six · Blocky screams if the cursor comes\n" +
                           "DAY: 2025-10-20: soccer, lost 2-3, made up over tea\n" +
                           "DAY: a quiet day";
        var diary = Bonds.ParseDiary(raw);
        Assert.NotNull(diary);
        Assert.Equal("Since 22 Oct they guard the garden together.", diary.Story);
        Assert.Equal(new[] { "Boo owes Blocky a sunflower (19 Oct)", "They meet at the cache at six", "Blocky screams if the cursor comes" }, diary.Facts);
        Assert.Equal(new Dictionary<string, string> { ["2025-10-20"] = "soccer, lost 2-3, made up over tea", [""] = "a quiet day" }, diary.Days);
        Assert.Null(Bonds.ParseDiary("No idea."));
        var book = new Bonds.Book();
        book.Note("Blocky", "Boo", new Bonds.Moment(Day, Bonds.MomentKind.Talk, "Boo", "Hi"));
        book.Write("Blocky", "Boo", diary, "diary", words: 5, keep: 2, cost: 0.001, at: Day.AddSeconds(86_400));
        var bond = book.Bond("Blocky", "Boo")!;
        Assert.True(bond.Chronicle == "Since 22 Oct they guard…" || bond.Chronicle!.Split(' ').Length <= 6, bond.Chronicle);
        Assert.Equal(new[] { "They meet at the cache at six", "Blocky screams if the cursor comes" }, bond.Facts.Select(f => f.Text));
        Assert.Equal(new[] { "2025-10-20", "2025-10-21" }, bond.Days.Select(d => d.Day));
        Assert.Equal("soccer, lost 2-3, made up over tea", bond.Days[0].Line);
        Assert.Equal(new Dictionary<string, int> { ["talk"] = 1 }, bond.Days[0].Counts);    // counts stay
        Assert.True(bond.DiaryAt == Day.AddSeconds(86_400) && bond.MemoryCost == 0.001);
        Assert.Empty(book.DiaryDue(3600, Day.AddSeconds(90_000)));                         // nothing new since
    }

    [Fact]
    public void TheDiaryIsDueForPairsWithSomethingNew()
    {
        var book = new Bonds.Book();
        book.Note("A", "B", new Bonds.Moment(Day, Bonds.MomentKind.Talk, "A"));
        book.Note("C", "D", new Bonds.Moment(Day, Bonds.MomentKind.Talk, "C"));
        book.Note("C", "D", new Bonds.Moment(Day, Bonds.MomentKind.Tea, "D"));
        Assert.Equal(new[] { "C & D", "A & B" }, book.DiaryDue(3600, Day).Select(b => string.Join(" & ", b.Names)));    // most new first
        book.WroteMemory("C", "D", Day, null);
        book.Note("C", "D", new Bonds.Moment(Day.AddSeconds(60), Bonds.MomentKind.Talk, "C"));
        Assert.Equal(new[] { "A & B" }, book.DiaryDue(3600, Day.AddSeconds(120)).Select(b => string.Join(" & ", b.Names)));    // written too lately
        Assert.Equal(2, book.DiaryDue(3600, Day.AddSeconds(4000)).Count);
    }

    [Fact]
    public void TheCapsAreKept()
    {
        var book = new Bonds.Book();
        for (int k = 0; k < 10; k++) book.Note("A", "B", new Bonds.Moment(Day.AddSeconds(-k * 86_400), Bonds.MomentKind.Talk, "A"));
        for (int k = 0; k < 6; k++) book.Remember("A", "B", $"fact {k}", "note", keep: 10);
        book.KeepMemory(3, 4, Day);
        var bond = book.Bond("A", "B")!;
        Assert.Equal(new[] { "fact 3", "fact 4", "fact 5" }, bond.Facts.Select(f => f.Text));
        Assert.Equal(5, bond.Days.Count);
        book.KeepMemory(0, 0, Day);
        Assert.True(book.Bond("A", "B")!.Days.Count == 0 && book.Bond("A", "B")!.Facts.Count == 0);
    }

    [Fact]
    public void AnOldBondsFileStillLoads()
    {
        const string old = """{"bonds":{"A & B":{"names":["A","B"],"together":60,"moments":[{"time":"2025-10-20T09:00:00Z","kind":"play","who":"A","detail":"tag"}]}}}""";
        var dir = Path.Combine(Path.GetTempPath(), "ledgelings-memory-" + Guid.NewGuid());
        Directory.CreateDirectory(dir);
        try
        {
            File.WriteAllText(Path.Combine(dir, "bonds.json"), old);
            var book = new Bonds.Store(dir).Load();
            var bond = book.Bond("A", "B");
            Assert.NotNull(bond);
            Assert.True(bond.Facts.Count == 0 && bond.Days.Count == 0 && bond.Record.Count == 0 && bond.DiaryAt is null);
            Assert.True(bond.Moments[0].Winners is null && bond.Moments[0].Score is null);
            // Windows only: what it writes the Mac reads, under the Mac's names.
            book.Note("A", "B", Game(Plays.Kind.Soccer, Day, new[] { "A" }, "3-1", asked: "B"));
            book.Remember("A", "B", "A owes B a poppy", "note", keep: 5, at: Day);
            new Bonds.Store(dir).Save(book);
            var json = JsonDocument.Parse(File.ReadAllText(Path.Combine(dir, "bonds.json"))).RootElement.GetProperty("bonds").GetProperty("A & B");
            Assert.True(json.TryGetProperty("facts", out _) && json.TryGetProperty("days", out _) && json.TryGetProperty("record", out _));
            var game = json.GetProperty("moments")[1];
            Assert.True(game.GetProperty("score").GetString() == "3-1" && game.GetProperty("winners")[0].GetString() == "A" && game.GetProperty("asked").GetString() == "B");
            Assert.Equal(book, new Bonds.Store(dir).Load());
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public void TheSeedDigestCountsDaysAndPicksLinesSpreadAcrossThem()
    {
        static ChatLog.Exchange E(double hours, string situation, params (string, string)[] lines) => new()
        {
            Time = Day.AddHours(hours), Situation = situation, Provider = "p", Model = "m",
            Lines = lines.Select(l => new ChatLog.Line(l.Item1, l.Item2)).ToList(),
        };
        var log = new[]
        {
            E(0, "Blocky sent Boo a paper plane.", ("Blocky", "The cache at six."), ("Boo", "Fine.")),
            E(1, "Blocky and Boo have put a little table out on the ceiling and are sitting down to tea together.", ("Blocky", "Once…"), ("Boo", "Ha!")),
            E(1.1, "Blocky and Boo have put a little table out on the ceiling and are sitting down to tea together.", ("Boo", "And I…"), ("Blocky", "No.")),
            E(2, "Boo just walked into Blocky and gave Blocky a poppy.", ("Boo", "Here."), ("Blocky", "Hm.")),
            E(3, "They just walked into each other.", ("Boo", "Boo!"), ("Blocky", "Move.")),
            E(24, "Boo отправляет Blocky бумажный самолётик.", ("Boo", "Тайник цел."), ("Blocky", "Ладно.")),
            E(25, "They just walked into each other.", ("Zed", "zzz"), ("Blocky", "Shh.")),
            E(-500, "They just walked into each other.", ("Boo", "Old."), ("Blocky", "Old.")),
        };
        var digest = Bonds.Digest(log, "Blocky", "Boo", Day.AddHours(-1), Day.AddHours(48), 6);
        Assert.Equal(6, digest.Exchanges);
        Assert.Equal(new Dictionary<string, int> { ["plane"] = 1, ["tea"] = 1, ["flower"] = 1, ["talk"] = 1 }, digest.Days[Bonds.DayKey(Day)]);    // two rounds, one tea party
        Assert.Equal(new Dictionary<string, int> { ["plane"] = 1 }, digest.Days[Bonds.DayKey(Day.AddDays(1))]);
        Assert.True(digest.Lines.Count == 5 && digest.Lines[0].Line.Text == "The cache at six." && digest.Lines[^1].Line.Text == "Ладно.");
        Assert.DoesNotContain(digest.Lines, l => l.Line.Text is "zzz" or "Old.");
        var values = Languages.With(Language.English, () => Bonds.SeedValues(new Bonds.Bond(new[] { "Blocky", "Boo" }), digest, ("Blocky", "a box", "grumpy"),
                                                                          ("Boo", "a ghost", "spooky"), 14, 80, 5));
        Assert.True(values["digest"].Contains("1 paper plane") && !values["lines"].Contains("walked into"), "situations are never sent");
        var book = new Bonds.Book();
        book.SeedDays("Blocky", "Boo", digest, Day);
        book.SeedDays("Blocky", "Boo", digest, Day);
        Assert.Equal(new Dictionary<string, int> { ["plane"] = 1, ["tea"] = 1, ["flower"] = 1, ["talk"] = 1 }, book.Bond("Blocky", "Boo")!.Days[0].Counts);    // a second seed counts nothing twice
    }

    [Fact]
    public void TheMemoryPurposesLandInTheirOwnRows()
    {
        var records = new[]
        {
            new Spend.Record(Day, "OpenRouter", "m", new Spend.Usage(900, 250, 0.0002), Spend.Purpose.Memory),
            new Spend.Record(Day, "OpenRouter", "m", new Spend.Usage(2500, 600, 0.0006), Spend.Purpose.MemorySeed),
        };
        var s = Spend.Summarise(records, Day);
        Languages.With(Language.English, () => Assert.Equal(new[] { "Memory: reading the past", "Long-term memory" }, s.ByPurpose.Select(p => p.Purpose)));
    }

    // Windows only: the prompts are the Mac's, word for word, and the Russian has every placeholder.

    [Fact]
    public void TheDiaryAndSeedPromptsAreTheMacs()
    {
        var swift = File.ReadAllText(Path.Combine(Root, "Sources/LedgelingsCore/Bonds+Memory.swift"));
        Assert.Equal(Bonds.EnglishDiaryPrompt, DeedsTests.SwiftLiteral(swift, "englishDiaryPrompt"));
        Assert.Equal(Bonds.EnglishSeedPrompt, DeedsTests.SwiftLiteral(swift, "englishSeedPrompt"));
        Assert.Contains("\"" + Bonds.EnglishDiarySystemPrompt + "\"", swift);
        foreach (var p in Bonds.DiaryPlaceholders)
        {
            var english = Bonds.EnglishDiaryPrompt + Bonds.EnglishSeedPrompt;
            var russian = Shared.PromptIn(Language.Russian, "diary", "") + Shared.PromptIn(Language.Russian, "seed", "");
            Assert.True(english.Contains("{" + p + "}") == russian.Contains("{" + p + "}"), p);
        }
        Assert.NotEqual(Bonds.EnglishDiarySystemPrompt, Shared.PromptIn(Language.Russian, "diarySystem", Bonds.EnglishDiarySystemPrompt));
    }
}

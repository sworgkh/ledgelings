namespace Ledgelings.Core.Tests;

/// <summary>Living together: time side by side, a story once it has been long enough,
/// and the few words of it that go into each one's prompt.</summary>
public class BondsTests
{
    static readonly DateTimeOffset Now = DateTimeOffset.FromUnixTimeSeconds(1_790_000_000);

    [Fact]
    public void EveryPairOnScreenAddsUpTimeTogetherOnce()
    {
        var book = new Bonds.Book();
        book.LiveTogether(60, new[] { "Blocky", "Pip", "Dot", "Pip" });
        book.LiveTogether(30, new[] { "Pip", "Blocky" });
        Assert.True(book.Bonds.Count == 3, "three names, three pairs; a name twice is one character");
        Assert.Equal(90, book.Bond("Pip", "Blocky")!.Together);
        Assert.True(Equals(book.Bond("Blocky", "Pip"), book.Bond("Pip", "Blocky")), "a pair is the same pair either way round");
        Assert.Equal(60, book.Bond("Dot", "Pip")!.Together);
        book.LiveTogether(60, new[] { "Blocky" });
        Assert.True(book.Bond("Blocky", "Pip")!.Together == 90, "alone is not together");
    }

    [Fact]
    public void APairIsDueAStoryOnlyAfterLivingTogetherLongEnough()
    {
        var book = new Bonds.Book();
        Assert.False(book.NeedsPlot("Blocky", "Pip", 3600, Now), "strangers");
        book.LiveTogether(3599, new[] { "Blocky", "Pip" });
        Assert.False(book.NeedsPlot("Blocky", "Pip", 3600, Now));
        book.LiveTogether(1, new[] { "Blocky", "Pip" });
        Assert.True(book.NeedsPlot("Blocky", "Pip", 3600, Now));
        book.Asked("Blocky", "Pip", Now, 0.0002);
        Assert.False(book.NeedsPlot("Blocky", "Pip", 3600, Now.AddSeconds(60)), "a failed ask waits before the next");
        Assert.True(book.NeedsPlot("Blocky", "Pip", 3600, Now.AddSeconds(Bonds.RetryAfter)));
        book.Begin("Blocky", "Pip", new Bonds.Written("Rivals", "A feud"), 3, Now);
        Assert.False(book.NeedsPlot("Blocky", "Pip", 0, Now.AddSeconds(1e6)), "one story at a time");
        Assert.Equal(0.0002, book.Bond("Blocky", "Pip")!.Cost);
    }

    [Fact]
    public void AStoryIsToldOverItsConversationsThenMakesRoomForTheNext()
    {
        var book = new Bonds.Book();
        book.LiveTogether(7200, new[] { "Blocky", "Pip" });
        book.Begin("Pip", "Blocky", new Bonds.Written("Grudging friends.", "Pip hides Blocky's favourite pixel."), 2, Now);
        var line = new[] { new ChatLog.Line("Pip", "Hi!"), new ChatLog.Line("Blocky", "No.") };
        book.Talked("Blocky", "Pip", line);
        Assert.Equal(1, book.Bond("Blocky", "Pip")!.Plot!.Told);
        book.Talked("Blocky", "Pip", Array.Empty<ChatLog.Line>());
        Assert.True(book.Bond("Blocky", "Pip")!.Plot!.Told == 1, "a conversation where nothing was said does not count");
        book.Talked("Blocky", "Pip", line.Concat(line).Concat(line).ToList());
        var bond = book.Bond("Blocky", "Pip")!;
        Assert.True(bond.Plot is null && bond.LastPlot == "Pip hides Blocky's favourite pixel.");
        Assert.True(bond.Summary == "Grudging friends.", "the bond outlives the story");
        Assert.True(bond.Talks == 2 && bond.Plots == 1);
        Assert.True(bond.Recent.Count == Bonds.RecentLines, "only the last few lines are kept for the next story");
        Assert.True(book.NeedsPlot("Blocky", "Pip", 3600, Now));
    }

    [Fact]
    public void TheModelsAnswerIsReadFromItsTwoLabelledLines()
    {
        Assert.Equal(new Bonds.Written("Old rivals, secretly fond.", "Blocky owes Pip a favour and hates it."),
            Bonds.Parse("BOND: Old rivals, secretly fond.\nPLOT: Blocky owes Pip a favour and hates it."));
        Assert.Equal(new Bonds.Written("Wary.", "A secret map of the ceiling."),
            Bonds.Parse("<think>hmm</think>\n**Bond:** \"Wary.\"\n- **PLOT:** *A secret map of the ceiling.*"));      // marks, quotes and hidden reasoning are cleaned off
        Assert.Equal(new Bonds.Written(null, "Just a plot."), Bonds.Parse("PLOT: Just a plot."));
        Assert.Null(Bonds.Parse("BOND: No story here."));
        Assert.Null(Bonds.Parse(""));
    }

    [Fact]
    public void EachSideHearsTheBondAndWhichPartOfTheStoryThisIs()
    {
        var bond = new Bonds.Bond(new[] { "Blocky", "Pip" });
        Assert.True(Bonds.Context(bond, "Blocky", "Pip") == "", "no bond, no story: nothing to add");
        Assert.Equal("", Bonds.Context(null, "Blocky", "Pip"));
        bond.Together = 3 * 86400 + 5;
        bond.Summary = "Rivals.";
        bond.Plot = new Bonds.Plot("A feud over the corner.", 3, 1, Now);
        var heard = Bonds.Context(bond, "Blocky", "Pip");
        Assert.StartsWith("You and Pip have shared this screen for 3 days.", heard);
        Assert.True(heard.Contains("How you get on: Rivals.") && heard.Contains("(part 2 of 3): A feud over the corner."));
        bond.Plot = bond.Plot with { Told = 2 };
        Assert.Contains("last part", Bonds.Context(bond, "Pip", "Blocky"));
        Assert.True(heard.Split(' ').Length < 60, "a few dozen words, not a history");
    }

    [Fact]
    public void TheStoryGoesWhereThePromptSaysOrAtTheEnd()
    {
        var values = new Dictionary<string, string> { ["speaker"] = "Blocky" };
        Assert.Equal("I am Blocky.\nRivals.", Bonds.WithRelationship("I am {speaker}.", values, "Rivals."));
        Assert.Equal("I am Blocky. Rivals. Go.", Bonds.WithRelationship("I am {speaker}. {relationship} Go.", values, "Rivals."));
        Assert.True(Bonds.WithRelationship("I am {speaker}.", values, "") == "I am Blocky.", "strangers get the prompt as it was");
    }

    [Fact]
    public void ThePlotPromptIsFilledForThePair()
    {
        var bond = new Bonds.Bond(new[] { "Blocky", "Pip" }) { Together = 7200, Recent = new() { new("Pip", "Hi!") } };
        var values = Bonds.PlotValues(bond, ("Blocky", "a small square creature", "Grumpy."), ("Pip", "a small square creature", "Cheerful."), 6);
        var prompt = Banter.Render(Bonds.DefaultPlotPrompt, values);
        Assert.True(prompt.Contains("shared it for 2 hours") && prompt.Contains("Blocky, a small square creature: Grumpy.")
            && prompt.Contains("Pip: Hi!") && prompt.Contains("next 6 conversations") && prompt.Contains("this is their first"));
        Assert.True(!prompt.Contains('{'), "every placeholder filled");
    }

    [Fact]
    public void DurationsReadLikePeopleSayThem()
    {
        Assert.Equal("a moment", Bonds.Duration(20));
        Assert.Equal("1 minute", Bonds.Duration(60));
        Assert.Equal("45 minutes", Bonds.Duration(45 * 60));
        Assert.Equal("5 hours", Bonds.Duration(3600 * 5));
        Assert.Equal("2 days", Bonds.Duration(86400 * 2 + 10));
    }

    [Fact]
    public void TheBookSurvivesTheDisk()
    {
        var dir = Path.Combine(Path.GetTempPath(), "bonds-" + Guid.NewGuid().ToString("N"));
        try
        {
            var store = new Bonds.Store(dir);
            Assert.True(store.Load().Equals(new Bonds.Book()), "no file, no bonds");
            var book = new Bonds.Book();
            book.LiveTogether(5000, new[] { "Blocky", "Pip" });
            book.Begin("Blocky", "Pip", new Bonds.Written("Rivals.", "A feud."), 4, Now);
            store.Save(book);
            Assert.Equal(book, store.Load());
            File.WriteAllText(store.File, "not json");
            Assert.True(store.Load().Equals(new Bonds.Book()), "a damaged file starts over rather than failing");
        }
        finally { try { Directory.Delete(dir, true); } catch (IOException) { } }
    }

    [Fact]
    public void TheMacsBondsFileReads()
    {
        // As the macOS app writes it: JSONEncoder, ISO-8601 dates, sorted keys, optionals left out.
        var json = """
        {
          "bonds" : {
            "Blocky & Pip" : {
              "lastAsked" : "2026-09-26T08:00:00Z",
              "names" : [ "Blocky", "Pip" ],
              "plot" : { "length" : 6, "started" : "2026-09-26T08:00:00Z", "text" : "A feud.", "told" : 1 },
              "plots" : 1,
              "recent" : [ { "speaker" : "Pip", "text" : "Hi!" } ],
              "summary" : "Rivals.",
              "talks" : 3,
              "together" : 5000.5
            }
          }
        }
        """;
        var dir = Path.Combine(Path.GetTempPath(), "bonds-" + Guid.NewGuid().ToString("N"));
        try
        {
            var store = new Bonds.Store(dir);
            Directory.CreateDirectory(dir);
            File.WriteAllText(store.File, json);
            var bond = store.Load().Bond("Pip", "Blocky")!;
            Assert.True(bond.Together == 5000.5 && bond.Talks == 3 && bond.Plot!.Told == 1 && bond.Recent[0].Text == "Hi!");
            Assert.Equal(DateTimeOffset.Parse("2026-09-26T08:00:00Z"), bond.LastAsked);
            Assert.Null(bond.Cost);
        }
        finally { try { Directory.Delete(dir, true); } catch (IOException) { } }
    }

    [Fact]
    public void StoriesAreTheirOwnLineInTheCosts()
    {
        var r = new Spend.Record(Now, "OpenRouter", "m", new Spend.Usage(250, 50, 0.0003), Spend.Purpose.Plots);
        var s = Spend.Summarise(new[] { r }, Now);
        Assert.Equal(new[] { "Relationship plots" }, s.ByPurpose.Select(p => p.Purpose));
        Assert.Equal(1, s.ByPurpose[0].Total.Calls);
    }
}

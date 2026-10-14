namespace Ledgelings.Core.Tests;

/// <summary>A pair's storyline, as the Mac's StorylineTests: every moment they share is kept,
/// folded into their story so far with each new story, and sent with the next one in a few hundred tokens.</summary>
public class StorylineTests
{
    static readonly DateTimeOffset Now = DateTimeOffset.FromUnixTimeSeconds(1_790_000_000);
    static DateTimeOffset At(double daysAgo) => Now.AddDays(-daysAgo);
    static ChatLog.Line L(string who, string text) => new(who, text);

    /// <summary>Blocky and Pip after a week: talks, a tea party, a flower, a plane, a grab.</summary>
    static Bonds.Book Week()
    {
        var book = new Bonds.Book();
        book.LiveTogether(7200, new[] { "Blocky", "Pip" });
        book.Talked("Blocky", "Pip", new[] { L("Blocky", "The cursor again."), L("Pip", "Hi!") }, at: At(7));
        book.Talked("Blocky", "Pip", new[] { L("Pip", "Tea? I baked a pixel.") }, Bonds.MomentKind.Tea, At(5));
        book.Note("Pip", "Blocky", new Bonds.Moment(At(3), Bonds.MomentKind.Flower, "Pip", "poppy"));
        book.Note("Blocky", "Pip", new Bonds.Moment(At(2), Bonds.MomentKind.Plane, "Blocky", "Stop waving."));
        book.Note("Pip", "Blocky", new Bonds.Moment(At(1), Bonds.MomentKind.Grab, "Pip"));
        return book;
    }

    static string Prompt(Bonds.Bond bond) => Banter.Render(Bonds.EnglishPlotPrompt,
        Bonds.PlotValues(bond, ("Blocky", "a robot", "Grumpy."), ("Pip", "a blob", "Cheerful."), 6, new Bonds.Telling(), Now));

    [Fact]
    public void EveryMomentTheyShareIsKeptAndCounted()
    {
        var bond = Week().Bond("Pip", "Blocky")!;
        Assert.Equal(new[] { "talk", "tea", "flower", "plane", "grab" }, bond.Moments.Select(m => m.Kind));
        Assert.True(bond.Tally.Values.All(n => n == 1) && bond.Tally.Count == 5);
        Assert.True(bond.Met == At(7) && bond.Talks == 2);
        var book = Week();
        for (int i = 0; i < 50; i++) book.Note("Blocky", "Pip", new Bonds.Moment(Now, Bonds.MomentKind.Talk, "Pip", $"{i}"));
        Assert.True(book.Bond("Blocky", "Pip")!.Moments.Count == Bonds.MomentsKept, "a few kept between stories");
        Assert.True(book.Bond("Blocky", "Pip")!.Tally["talk"] == 51, "but every one counted");
        book.Note("Pip", "Pip", new Bonds.Moment(Now, Bonds.MomentKind.Talk, "Pip"));
        Assert.True(book.Bond("Pip", "Pip") is null, "nobody shares a moment with themself");
    }

    [Fact]
    public void ANewStoryFoldsTheMomentsIntoTheirStorySoFar()
    {
        var book = Week();
        book.Begin("Blocky", "Pip", new Bonds.Written("Wary.", "A feud."), 3, Now);
        var bond = book.Bond("Blocky", "Pip")!;
        var story = bond.Chronicle ?? "";
        Assert.True(bond.Moments.Count == 0, "folded in, so the next story starts afresh");
        Assert.True(story.Contains("Pip gave Blocky a poppy") && story.Contains("tea party") && story.Contains("paper plane")
            && story.Contains("grabbed the cursor"), story);
        Assert.True(!story.Contains("today") && !story.Contains("yesterday"), "dates, which do not go stale");
        Assert.True(story.Split(' ').Length <= Bonds.StoryWords);
    }

    [Fact]
    public void TheModelsRewriteIsTheirStorySoFarAndTheNextStorySeesIt()
    {
        var book = Week();
        book.Begin("Blocky", "Pip", new Bonds.Written("Wary.", "A feud.", "They met over the cursor; Pip gave Blocky a poppy."), 2, Now);
        book.Talked("Blocky", "Pip", new[] { L("Pip", "Sorry about the feud.") }, at: Now);
        book.Talked("Blocky", "Pip", new[] { L("Blocky", "Hmph.") }, at: Now);
        var bond = book.Bond("Blocky", "Pip")!;
        Assert.True(bond.Plot is null && bond.LastPlot == "A feud.");
        var prompt = Prompt(bond);
        Assert.True(prompt.Contains("Their story so far:") && prompt.Contains("Pip gave Blocky a poppy"), "continuity: the last chapter is in the next");
        Assert.True(prompt.Contains("Their last story: A feud.") && prompt.Contains("Sorry about the feud.") && prompt.Contains("STORY:"));
        Assert.True(prompt.Contains("all told: 3 talks, 1 tea party, 1 flower, 1 paper plane, 1 cursor grab"), prompt);
        Assert.True(!prompt.Contains('{'), "every placeholder filled");
        book.Begin("Blocky", "Pip", new Bonds.Written(null, "Making up."), 2, Now);
        var next = book.Bond("Blocky", "Pip")!.Chronicle ?? "";
        Assert.True(next.StartsWith("They met over the cursor") && next.Contains("2 talks in all")
            && next.Contains("\"Hmph.\" Then this story played out: A feud."), next);
    }

    [Fact]
    public void ThePromptStaysSmallHoweverLongTheFriendship()
    {
        var book = Week();
        var lng = string.Concat(Enumerable.Repeat("word ", 60));
        for (int i = 0; i < 200; i++)
        {
            book.Talked("Blocky", "Pip", new[] { L(i % 2 == 0 ? "Pip" : "Blocky", lng) }, at: At((200 - i) / 10.0));
            if (i % 6 == 0)
            {
                book.Begin("Blocky", "Pip", new Bonds.Written("Fine.", lng, lng + lng + lng), 6, Now);
                book.Update("Blocky", "Pip", b => b.Plot = null);
            }
        }
        var bond = book.Bond("Blocky", "Pip")!;
        var tokens = Prompt(bond).Length / 4;
        Assert.True(tokens < 900, $"about {tokens} tokens");
        Assert.True((bond.Chronicle ?? "").Split(' ').Length <= Bonds.StoryWords);
        Assert.True(Prompt(new Bonds.Bond(new[] { "Blocky", "Pip" })).Length / 4 < 450, "a new pair's prompt");
    }

    [Fact]
    public void MomentsBeyondThoseShownAreFoldedNotLost()
    {
        var told = Bonds.History(Week().Bond("Blocky", "Pip")!, new Bonds.Telling(80, 2), Now);
        Assert.True(told.Since.Split('\n').Length == 2 && told.Since.Contains("paper plane") && told.Since.Contains("cursor"));
        Assert.True(told.Story.Contains("poppy") && told.Story.Contains("tea party"), "the three older ones are in the story so far");
    }

    [Fact]
    public void WithoutAModelTheStoryGrowsFromWhatTheyLivedThrough()
    {
        var rng = new Random(7);
        var bond = Week().Bond("Blocky", "Pip")!;
        for (int i = 0; i < 10; i++)
        {
            var written = Bonds.BuiltInPlot(bond, Now, rng);
            Assert.True(written.Plot.Contains("poppy") && written.Plot.Contains("3 days ago"), written.Plot);
            Assert.True(written.Bond?.Contains("1 tea party") == true && written.Story is null);
        }
        bond.Summary = "Grudging friends.";
        Assert.True(Bonds.BuiltInPlot(bond, Now, rng).Bond == "Grudging friends.", "a written bond line stays");
        var talkOnly = new Bonds.Bond(new[] { "Blocky", "Pip" });
        talkOnly.Moments.Add(new Bonds.Moment(At(1), Bonds.MomentKind.Talk, "Pip", "Nice ceiling."));
        talkOnly.Tally["talk"] = 1;
        Assert.Contains("yesterday", Bonds.BuiltInPlot(talkOnly, Now, rng).Plot);
        Assert.False(string.IsNullOrEmpty(Bonds.BuiltInPlot(new Bonds.Bond(new[] { "Blocky", "Pip" }), Now, rng).Plot), "strangers get a story too");
    }

    [Fact]
    public void TheModelsStoryLineIsRead()
    {
        Assert.Equal(new Bonds.Written("Wary.", "A feud.", "They met on 3 Oct. Pip gave Blocky a poppy."),
            Bonds.Parse("BOND: Wary.\nPLOT: A feud.\n**STORY:** They met on 3 Oct. Pip gave Blocky a poppy."));
        Assert.Null(Bonds.Parse("PLOT: A feud.")!.Story);
    }

    [Fact]
    public void ALongStoryIsTrimmedFromItsOldestSentences()
    {
        Assert.Equal("Four five. Six seven.", Bonds.Trimmed("One two three. Four five. Six seven.", 4));
        Assert.Equal("One two three…", Bonds.Trimmed("One two three four five six", 3));
        Assert.Equal("Pip said: \"Tea? I baked a pixel.\" Then a feud.", Bonds.Trimmed("Old news here. Pip said: \"Tea? I baked a pixel.\" Then a feud.", 10));
    }

    [Fact]
    public void AnOldPairsPastIsReadFromTheChatLogOnce()
    {
        var book = new Bonds.Book();
        book.LiveTogether(7200, new[] { "Blocky", "Pip" });
        book.Talked("Blocky", "Pip", new[] { L("Pip", "Live.") }, at: At(1));
        ChatLog.Exchange E(double daysAgo, params string[] who) => new()
        {
            Time = At(daysAgo), Situation = "", Provider = "", Model = "", Lines = who.Select(w => L(w, $"Line of {w}.")).ToList(),
        };
        var log = new[] { E(30, "Blocky", "Pip"), E(20, "Pip", "Blocky"), E(10, "Blocky", "Zed"), E(15, "Blocky"), E(1, "Pip", "Blocky") };
        book.Seed("Pip", "Blocky", log);
        var bond = book.Bond("Blocky", "Pip")!;
        Assert.True(bond.Seeded && bond.Tally["talk"] == 3, "two from the log, one live; the live one not counted twice");
        Assert.True(bond.Met == At(30) && bond.Moments[0].Who == "Blocky" && bond.Moments.Count == 3);
        book.Seed("Pip", "Blocky", log);
        Assert.True(book.Bond("Blocky", "Pip")!.Tally["talk"] == 3, "only once");
    }

    [Fact]
    public void AStoryCanBeStartedOverForOnePairOrAll()
    {
        var book = Week();
        book.LiveTogether(100, new[] { "Blocky", "Zed" });
        book.Begin("Blocky", "Pip", new Bonds.Written("Wary.", "A feud."), 3, Now);
        book.ResetStory(Bonds.Key("Pip", "Blocky"));
        var bond = book.Bond("Blocky", "Pip")!;
        Assert.True(bond.Chronicle is null && bond.Moments.Count == 0 && bond.Tally.Count == 0 && bond.Plot is null && bond.Summary is null);
        Assert.True(bond.Together == 7200 && bond.Seeded, "their time stays, and the log is not read back in");
        book.Note("Blocky", "Zed", new Bonds.Moment(Now, Bonds.MomentKind.Talk, "Zed"));
        book.ResetAllStories();
        Assert.True(book.Bond("Blocky", "Zed")!.Moments.Count == 0 && book.Bonds.Count == 2);
    }

    [Fact]
    public void TheStorylineSurvivesARelaunchAndTheMacsFileLoads()
    {
        var dir = Path.Combine(Path.GetTempPath(), "story-" + Guid.NewGuid());
        try
        {
            var store = new Bonds.Store(dir);
            var book = Week();
            book.Begin("Blocky", "Pip", new Bonds.Written("Wary.", "A feud.", "They met."), 3, Now);
            book.Note("Blocky", "Pip", new Bonds.Moment(Now, Bonds.MomentKind.Plane, "Pip", "Hello."));
            store.Save(book);
            Assert.Equal(book, store.Load());
            // As the Mac writes it, and a file from before storylines.
            File.WriteAllText(store.File, """
                {"bonds": {"Blocky & Pip": {"names": ["Blocky", "Pip"], "together": 60, "talks": 2, "plots": 0, "recent": [],
                 "moments": [{"time": "2026-10-14T09:00:00Z", "kind": "flower", "who": "Pip", "detail": "poppy"}],
                 "tally": {"flower": 1}, "met": "2026-10-14T09:00:00Z", "seeded": true, "chronicle": "They met."},
                 "Blocky & Zed": {"names": ["Blocky", "Zed"], "together": 5, "talks": 0, "plots": 0, "recent": []}}}
                """);
            var loaded = store.Load();
            var mac = loaded.Bond("Blocky", "Pip")!;
            Assert.True(mac.Moments[0].Kind == "flower" && mac.Moments[0].Detail == "poppy" && mac.Tally["flower"] == 1 && mac.Seeded && mac.Chronicle == "They met.");
            var old = loaded.Bond("Blocky", "Zed")!;
            Assert.True(old.Moments.Count == 0 && !old.Seeded && old.Chronicle is null);
        }
        finally { if (Directory.Exists(dir)) Directory.Delete(dir, true); }
    }

    [Fact]
    public void TheStorylineIsToldInRussian()
    {
        Languages.With(Language.Russian, () =>
        {
            var bond = Week().Bond("Blocky", "Pip")!;
            var told = Bonds.History(bond, new Bonds.Telling(), Now);
            Assert.True(told.Story.Contains("Знакомы с") && told.Since.Contains("подарок от Pip для Blocky"), told.Story + "\n" + told.Since);
            Assert.Contains("3 дня назад", Bonds.BuiltInPlot(bond, Now, new Random(1)).Plot);
            Assert.True(Bonds.PlotPromptIn(Language.Russian).Contains("STORY:") && Bonds.PlotPromptIn(Language.Russian).Contains("{story}"));
            return 0;
        });
    }

    [Fact]
    public void AnUneditedPromptFromBeforeStorylinesIsKnown()
    {
        Assert.Contains(Bonds.EnglishPlotPromptV1, Bonds.EarlierPlotPrompts);
        Assert.Contains(Bonds.RussianPlotPromptV1, Bonds.EarlierPlotPrompts);
        Assert.DoesNotContain(Bonds.EnglishPlotPrompt, Bonds.EarlierPlotPrompts);
    }
}

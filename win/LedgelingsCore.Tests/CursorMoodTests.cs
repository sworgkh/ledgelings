namespace Ledgelings.Core.Tests;

/// <summary>The cursor mood (SPEC §6.1.2): what the creatures make of the cursor, in the
/// prompts, the built-in lines and the complaints, in every language. The Mac's CursorMoodTests.</summary>
public class CursorMoodTests
{
    private static bool AboutCursor(string text)
    {
        var lower = text.ToLowerInvariant();
        return new[] { "cursor", "arrow", "pointer", "курсор", "стрелк" }.Any(lower.Contains);
    }

    /// <summary>Every shipped line or conversation a creature can say in <paramref name="l"/>, as first written.</summary>
    private static List<string> Shipped(Language l) => Languages.With(l, () => CursorMoods.With(CursorMood.Bad, () =>
    {
        var all = Script.Parse(Script.BuiltInTextIn(l)).Conversations.Select(c => string.Join("\n", c.Lines)).ToList();
        foreach (var v in Letters.Voices.Values.Append(Letters.Anyone)) all.AddRange(v.Notes.Concat(v.Musings).Concat(v.Replies));
        all.AddRange(Tea.Stories.Values.SelectMany(x => x).Concat(Tea.Replies.Values.SelectMany(x => x)).Concat(Tea.AnyoneStories).Concat(Tea.AnyoneReplies));
        all.AddRange(Reminders.Notes.Values.SelectMany(x => x).Concat(Reminders.Anyone));
        return all;
    }));

    [Fact]
    public void EveryShippedLineAboutTheCursorHasAVersionForEachMood()
    {
        foreach (var l in Languages.All)
        {
            var rewrites = CursorMoods.Rewrites(l);
            var fine = CursorMoods.FitsEveryMood(l);
            var aboutCursor = Shipped(l).Where(AboutCursor).ToHashSet();
            Assert.NotEmpty(rewrites);
            foreach (var text in aboutCursor) Assert.True(rewrites.ContainsKey(text) || fine.Contains(text), $"{l.Code()}: no good or neutral version of \"{text}\"");
            foreach (var key in rewrites.Keys) Assert.True(aboutCursor.Contains(key), $"{l.Code()}: rewrite of a line that does not ship: \"{key}\"");
            foreach (var key in fine) Assert.True(aboutCursor.Contains(key), $"{l.Code()}: \"{key}\" does not ship");
        }
    }

    [Fact]
    public void ARewrittenConversationKeepsItsLines()
    {
        foreach (var l in Languages.All)
            foreach (var (text, r) in CursorMoods.Rewrites(l))
                foreach (var version in new[] { r.Good, r.Neutral })
                {
                    Assert.Equal(text.Split('\n').Length, version.Split('\n').Length);
                    foreach (var slot in new[] { "{reader}", "{reminder}", "{flower}", "{other}" })
                        if (text.Contains(slot)) Assert.Contains(slot, version);
                }
    }

    [Fact]
    public void EachMoodSaysItsOwnLinesAndBadSaysTheOriginals()
    {
        const string original = "The cursor chased me into a corner once. I stared it down. It blinked first.";
        var rate = new[] { "Rate the cursor out of ten.", "Minus four.", "Generous." };
        Languages.With(Language.English, () =>
        {
            CursorMoods.With(CursorMood.Bad, () =>
            {
                Assert.Contains(original, Tea.Stories["Blocky"]);
                Assert.Equal(rate, CursorMoods.Current.Adjust(rate));
            });
            CursorMoods.With(CursorMood.Good, () =>
            {
                Assert.DoesNotContain(original, Tea.Stories["Blocky"]);
                Assert.StartsWith("Eleven", CursorMoods.Current.Adjust(rate)[1]);
                Assert.Contains("The cursor is a friend friend. Click. Click. It likes it.", Letters.Voices["Glitch"].Notes);
                Assert.StartsWith("Stop playing with the cursor", Reminders.Notes["Blocky"][0]);
            });
            CursorMoods.With(CursorMood.Neutral, () => Assert.Equal("Five. It's a cursor.", CursorMoods.Current.Adjust(rate)[1]));
        });
        foreach (var m in CursorMoods.All) Assert.Equal("I hate the cursor, says me.", m.Adjust("I hate the cursor, says me."));
        Languages.With(Language.Russian, () => CursorMoods.With(CursorMood.Good, () =>
            Assert.Contains(Tea.Stories["Blocky"], s => s.Contains("осалил"))));
    }

    [Fact]
    public void AModelHearsTheMoodThroughThePersona()
    {
        var blocky = Banter.DefaultCharacters.First(c => c.Name == "Blocky").Persona;
        Languages.With(Language.English, () =>
        {
            CursorMoods.With(CursorMood.Bad, () => Assert.Equal(blocky, Banter.Persona(blocky)));
            CursorMoods.With(CursorMood.Good, () =>
            {
                var said = Banter.Persona(blocky);
                Assert.Contains("Secretly loves racing the mouse cursor", said);
                Assert.Contains("game of tag", said);
                Assert.EndsWith(CursorMoods.EnglishGoodNote, Banter.Persona("A user's own creature."));
            });
            CursorMoods.With(CursorMood.Neutral, () => Assert.StartsWith("Grumpy and proud. Thinks the bottom edge", Banter.Persona(blocky)));
        });
        Languages.With(Language.Russian, () => CursorMoods.With(CursorMood.Good, () =>
        {
            var said = Banter.Persona(blocky);
            Assert.Contains("Втайне обожает", said);
            Assert.Contains("догонялки", said);
        }));
    }

    [Fact]
    public void ComplaintsBecomeATeaseOrARemark()
    {
        var everyone = Complaints.EnglishLines.Keys.ToHashSet();
        foreach (var l in Languages.All)
            foreach (var m in CursorMoods.All)
                Languages.With(l, () =>
                {
                    var sets = Complaints.LinesFor(m);
                    Assert.True(everyone.SetEquals(sets.Keys), $"{m} {l.Code()}");
                    foreach (var (name, lines) in sets) Assert.True(lines.Length >= 2 && lines.Any(x => x.Contains("{times}")), $"{m} {l.Code()} {name}");
                    Assert.NotEmpty(Complaints.AnyoneFor(m));
                    Assert.Contains("{times}", Complaints.PromptFor(m));
                });
        Languages.With(Language.Russian, () =>
        {
            Assert.Contains("догонялки", Complaints.PromptFor(CursorMood.Good));
            Assert.Contains("Ещё", Complaints.LinesFor(CursorMood.Good)["Pip"][0]);
        });
        Languages.With(Language.English, () => CursorMoods.With(CursorMood.Good, () =>
        {
            Assert.Equal(Complaints.EnglishGoodPrompt, Complaints.Prompt);
            var line = Complaints.Line("Pip", 5, new Random(1));
            Assert.Contains(line, Complaints.EnglishGoodLines["Pip"].Select(x => x.Replace("{times}", "5")));
        }));
    }

    [Fact]
    public void ThePromptForWritingMoreLinesSaysTheMood()
    {
        CursorMoods.With(CursorMood.Good, () =>
        {
            Languages.With(Language.English, () => Assert.Contains("play tag with the mouse cursor", Script.AgentPrompt(Banter.DefaultCharacters)));
            Languages.With(Language.Russian, () => Assert.Contains("играют с курсором мыши в догонялки", Script.AgentPrompt(Array.Empty<Character>())));
        });
        CursorMoods.With(CursorMood.Bad, () => Languages.With(Language.English, () =>
            Assert.Contains("flee the mouse cursor", Script.AgentPrompt(Array.Empty<Character>()))));
    }

    [Fact]
    public void MoodsAreStoredByTheMacsNames()
    {
        Assert.Equal(new[] { "good", "neutral", "bad" }, CursorMoods.All.Select(m => m.Code()));
        Assert.Null(CursorMoods.FromCode("grumpy"));
    }
}

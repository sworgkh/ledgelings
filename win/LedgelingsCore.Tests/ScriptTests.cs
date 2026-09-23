namespace Ledgelings.Core.Tests;

/// <summary>The built-in lines: a text file of conversations that needs no model.</summary>
public class ScriptTests
{
    private const string Sample = """
        # A comment, and a blank line between conversations.

        Nice edge you've got there, {listener}.
        It was nicer before you turned up.

        [flower]
        Here. I found a {flower} under the cursor.
        Is it... ticking?
        No. Probably.

        [night, flower]
        A {flower}, at this hour?
        Flowers don't sleep either.

        [night]
        Can't sleep.
        """;

    private static HashSet<string> Moment(params string[] tags) => new(tags);

    [Fact]
    public void ParsesBlocksTagsAndComments()
    {
        var script = Script.Parse(Sample);
        Assert.Equal(4, script.Conversations.Count);
        Assert.Empty(script.Conversations[0].Tags);
        Assert.Equal(new[] { "Nice edge you've got there, {listener}.", "It was nicer before you turned up." }, script.Conversations[0].Lines);
        Assert.True(script.Conversations[1].Tags.SetEquals(new[] { "flower" }) && script.Conversations[1].Lines.Count == 3);
        Assert.True(script.Conversations[2].Tags.SetEquals(new[] { "night", "flower" }));
        Assert.True(script.Conversations[3].Tags.SetEquals(new[] { "night" }));
        Assert.Equal(new[] { "Can't sleep." }, script.Conversations[3].Lines);
    }

    [Fact]
    public void RefusesWhatItCannotUseAndSaysWhere()
    {
        static Script.ParseException? Problem(string text)
        {
            try { Script.Parse(text); return null; } catch (Script.ParseException e) { return e; }
        }
        Assert.Equal("no conversations", Problem("")?.Problem);
        Assert.Equal("no conversations", Problem("# only a comment\n\n")?.Problem);
        var unknown = Problem("Hello.\nHi.\n\n[loud]\nWhat?");
        Assert.True(unknown?.Line == 4 && unknown.Problem.Contains("loud"));
        var bare = Problem("[night]\n\nHello.\nHi.");
        Assert.True(bare?.Line == 1 && bare.Problem.Contains("needs at least one line"));
        var late = Problem("Hello.\n[night]\nHi.");
        Assert.True(late?.Line == 2 && late.Problem.Contains("first line"));
    }

    [Fact]
    public void TheTextFormComesBackTheSame()
    {
        var script = Script.Parse(Sample);
        Assert.Equal(script, Script.Parse(script.Text()));
    }

    [Fact]
    public void PicksTheMostSpecificConversationForTheMoment()
    {
        var script = Script.Parse(Sample);
        var rng = new Random();
        for (int i = 0; i < 20; i++)
        {
            Assert.Equal(0, script.Pick(Moment("day"), Array.Empty<int>(), rng));      // by day, without a flower, only the untagged one fits
            Assert.Equal(1, script.Pick(Moment("day", "flower"), Array.Empty<int>(), rng));
            Assert.Equal(2, script.Pick(Moment("night", "flower"), Array.Empty<int>(), rng));
            Assert.Equal(3, script.Pick(Moment("night"), Array.Empty<int>(), rng));
        }
        Assert.Null(new Script(Array.Empty<Script.Conversation>()).Pick(Moment("day"), Array.Empty<int>(), rng));
    }

    [Fact]
    public void AvoidsRecentOnesUntilThereIsNothingElse()
    {
        var script = Script.Parse("One.\n\nTwo.\n\nThree.");
        var rng = new Random();
        for (int i = 0; i < 20; i++) Assert.Equal(2, script.Pick(Moment("day"), new[] { 0, 1 }, rng));
        var picks = Enumerable.Range(0, 40).Select(_ => script.Pick(Moment("day"), new[] { 0, 1, 2 }, rng)).ToHashSet();
        Assert.True(picks.SetEquals(new int?[] { 0, 1, 2 }), "everyone recent: anyone will do");
    }

    [Fact]
    public void FillsInWhoIsTalkingAndWhatWasGiven()
    {
        Assert.Equal("Hey Zed, Pip here. Take this tulip.", Script.Fill("Hey {listener}, {speaker} here. Take this {flower}.", "Pip", "Zed", "tulip"));
        Assert.Equal("A flower for you.", Script.Fill("A {flower} for you.", "Pip", "Zed", null));
    }

    [Fact]
    public void TheBuiltInScriptIsBigCleanAndCoversTheMoments()
    {
        var script = Script.Parse(Script.BuiltInText);
        Assert.True(script.Conversations.Count >= 60);
        Assert.True(script.Conversations.Count(c => c.Tags.SetEquals(new[] { "flower" })) >= 10);
        Assert.True(script.Conversations.Count(c => c.Tags.SetEquals(new[] { "night" })) >= 6);
        Assert.True(script.Conversations.Count(c => c.Tags.Count == 0) >= 40);
        foreach (var c in script.Conversations)
        {
            Assert.True(c.Lines.Count is >= 2 and <= 4, string.Join(" / ", c.Lines));
            foreach (var line in c.Lines)
            {
                Assert.True(line.Length <= 120, line);
                Assert.DoesNotContain("{", Script.Fill(line, "x", "y", "z"));
            }
        }
    }

    [Fact]
    public void TheAgentPromptTeachesTheFormatAndNamesTheCast()
    {
        var prompt = Script.AgentPrompt(new[] { new Character("Blocky", "Grumpy."), new Character("Pip", "Cheerful.") }, 30);
        Assert.Contains("30", prompt);
        Assert.True(prompt.Contains("Blocky") && prompt.Contains("Grumpy.") && prompt.Contains("Pip"));
        Assert.True(prompt.Contains("{speaker}") && prompt.Contains("{listener}") && prompt.Contains("{flower}"));
        Assert.True(prompt.Contains("[flower]") && prompt.Contains("[night]"));
        Assert.Contains("blank line", prompt);
    }
}

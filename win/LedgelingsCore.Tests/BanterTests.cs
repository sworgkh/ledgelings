namespace Ledgelings.Core.Tests;

public class BanterTests
{
    [Fact]
    public void RendersPlaceholdersAndLeavesUnknownOnesAlone()
    {
        var output = Banter.Render("Hi {listener}, I am {speaker}. {nope}",
            new Dictionary<string, string> { ["speaker"] = "Blocky", ["listener"] = "Pip" });
        Assert.Equal("Hi Pip, I am Blocky. {nope}", output);
    }

    [Fact]
    public void DefaultPromptsUseOnlyKnownPlaceholders()
    {
        foreach (var template in new[] { Banter.DefaultSystemPrompt, Banter.DefaultLinePrompt, Banter.DefaultReplyPrompt })
        {
            var filled = Banter.Render(template, Banter.Placeholders.ToDictionary(p => p, _ => "x"));
            Assert.False(filled.Contains('{'), template);
        }
    }

    [Fact]
    public void CleansWhatASmallModelTendsToSend()
    {
        Assert.Equal("Pip, you're a beige disappointment.", Banter.CleanLine("\"Pip, you're a beige disappointment.\"", "Blocky"));
        Assert.Equal("Get off my edge.", Banter.CleanLine("Blocky: Get off my edge.\nSecond line", "Blocky"));
        Assert.Equal("Fine.", Banter.CleanLine("<think>hmm\nhmm</think>\n\n*Fine.*", "Blocky"));
        Assert.Equal("", Banter.CleanLine("   \n  ", "Blocky"));
    }

    [Fact]
    public void CapsRunawayLines()
    {
        var longLine = string.Concat(Enumerable.Repeat("ha ", 100));
        var output = Banter.CleanLine(longLine, "Pip", maxLength: 30);
        Assert.True(output.Length <= 31 && output.EndsWith("…"));
    }
}

public class BubbleTimeTests
{
    [Fact]
    public void ATypicalLineStaysAboutTheBaseTime()
    {
        var eight = "one two three four five six seven eight";
        Assert.True(Math.Abs(Banter.ShowTime(eight, 14) - 14.2) < 0.01);
    }

    [Fact]
    public void LongerLinesStayLongerButNeverPastTwiceTheBase()
    {
        var longLine = string.Join(" ", Enumerable.Repeat("word", 60));
        Assert.Equal(28, Banter.ShowTime(longLine, 14));
        Assert.True(Banter.ShowTime("hi", 14) < Banter.ShowTime("hi there friend", 14));
    }

    [Fact]
    public void TheDefaultBaseIsFourteenSeconds()
    {
        Assert.Equal(14, Banter.DefaultBubbleSeconds);
    }

    [Fact]
    public void StarsAndUnderscoresBecomeItalicAndDoubleStarsBold()
    {
        Assert.Equal(new[] { new Banter.StyledRun("Ah, the bottom edge... "), new Banter.StyledRun("sighs", Italic: true), new Banter.StyledRun(" ...where pride settles.") },
            Banter.Styled("Ah, the bottom edge... *sighs* ...where pride settles."));
        Assert.Equal(new[] { new Banter.StyledRun("You almost knocked me off the "), new Banter.StyledRun("good", Italic: true), new Banter.StyledRun(" edge!") },
            Banter.Styled("You almost knocked me off the *good* edge!"));
        Assert.Equal(new[] { new Banter.StyledRun("This is "), new Banter.StyledRun("important", Bold: true), new Banter.StyledRun(", "), new Banter.StyledRun("really", Italic: true), new Banter.StyledRun(" important.") },
            Banter.Styled("This is **important**, _really_ important."));
        Assert.Equal(new[] { new Banter.StyledRun("loud", Bold: true, Italic: true) }, Banter.Styled("***loud***"));
    }

    [Fact]
    public void LoneOrOddMarksStayAsTheyAre()
    {
        Assert.Equal(new[] { new Banter.StyledRun("2 * 3 = 6") }, Banter.Styled("2 * 3 = 6"));
        Assert.Equal(new[] { new Banter.StyledRun("*sigh without an end") }, Banter.Styled("*sigh without an end"));
        Assert.Equal(new[] { new Banter.StyledRun("snake_case_name here") }, Banter.Styled("snake_case_name here"));
        Assert.Equal(new[] { new Banter.StyledRun("a ** b") }, Banter.Styled("a ** b"));
        Assert.Empty(Banter.Styled(""));
    }

    [Fact]
    public void StyledTextCollapsesTheDoubleSpacesModelsLeaveAfterAMark()
    {
        Assert.Equal(new[] { new Banter.StyledRun("Sigh.", Italic: true), new Banter.StyledRun(" The abyss, eh?") }, Banter.Styled("*Sigh.*  The abyss, eh?"));
        Assert.Equal("Sigh. The abyss, eh?", Banter.Plain("*Sigh.*  The **abyss**, eh?"));
    }
}

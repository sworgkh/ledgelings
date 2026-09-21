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
}

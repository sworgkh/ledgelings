namespace Ledgelings.Core.Tests;

/// <summary>Characters say something new until they have run through what they know.</summary>
public class LineMemoryTests
{
    [Fact]
    public void RemembersTheLastLinesOfEachCharacter()
    {
        var memory = new LineMemory(2);
        memory.Remember("One.", "Blocky");
        memory.Remember("Two.", "Blocky");
        memory.Remember("Three.", "Blocky");
        memory.Remember("Hi!", "Pip");
        Assert.Equal(new[] { "Two.", "Three." }, memory.Recent("Blocky"));
        Assert.Equal(new[] { "Hi!" }, memory.Recent("Pip"));
        Assert.Empty(memory.Recent("Zed"));
        memory.Remember("two", "Blocky");
        Assert.True(memory.Recent("Blocky").SequenceEqual(new[] { "Three.", "two" }), "the same line again moves to the end, not twice");
    }

    [Fact]
    public void PicksALineNotSaidLatelyThenTheOneSaidLongestAgo()
    {
        var memory = new LineMemory(10);
        var rng = new Random();
        var lines = new[] { "A paper plane.", "Paper beats cursor.", "Fine. A reply." };
        memory.Remember("A paper plane.", "Blocky");
        memory.Remember("Paper beats cursor!", "Blocky");
        for (int i = 0; i < 20; i++) Assert.Equal(2, memory.Pick(lines, "Blocky", rng));
        memory.Remember("Fine. A reply.", "Blocky");
        for (int i = 0; i < 20; i++) Assert.True(memory.Pick(lines, "Blocky", rng) == 0, "all said: the oldest comes back");
        Assert.NotNull(memory.Pick(lines, "Pip", rng));
        Assert.Null(memory.Pick(Array.Empty<string>(), "Pip", rng));
    }

    // aRoundOfLettersNeverRepeatsALine (Letters.musing) belongs with the paper planes' Letters port.

    [Fact]
    public void OffRemembersNothing()
    {
        var memory = new LineMemory(0);
        memory.Remember("Hello.", "Pip");
        Assert.Empty(memory.Recent("Pip"));
        Assert.Equal("System.", LineMemory.WithRecent("System.", Array.Empty<string>()));
    }

    [Fact]
    public void TellsTheModelWhatItSaidLately()
    {
        var prompt = LineMemory.WithRecent("You are Blocky.", new[] { "Watch where you're going.", "The bottom edge is respectable." });
        Assert.StartsWith("You are Blocky.\n", prompt);
        Assert.Contains("- Watch where you're going.\n- The bottom edge is respectable.", prompt);
        Assert.Contains("do not repeat", prompt);
    }

    [Fact]
    public void LearnsFromAnExchangeAndTrims()
    {
        var memory = new LineMemory(3);
        memory.Remember(new ChatLog.Exchange { Time = DateTimeOffset.Now, Lines = new() { new("Blocky", "Hm."), new("Pip", "Ha!") } });
        Assert.Equal(new[] { "Ha!" }, memory.Recent("Pip"));
        memory.Trim(0);
        Assert.Empty(memory.Recent("Blocky"));
    }
}

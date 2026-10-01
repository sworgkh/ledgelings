namespace Ledgelings.Core.Tests;

public class ComplaintsTests
{
    [Fact]
    public void TheFifthBotherInARowGetsAComplaintAndTheCountStartsOver()
    {
        var a = new Annoyance(limit: 4, calmAfter: 20);
        var first = Enumerable.Range(1, 4).Select(t => a.Bothered(0, t)).ToList();
        Assert.Equal(new[] { false, false, false, false }, first);      // four in a row it puts up with
        Assert.Equal(4, a.Streak(0, 4));
        var fifth = a.Bothered(0, 5);
        Assert.True(fifth, "the fifth is one too many");
        Assert.Equal(5, a.Streak(0, 5));
        a.Forgive(0);
        var sixth = a.Bothered(0, 6);
        Assert.False(sixth, "after complaining it needs a fresh streak");
        Assert.Equal(1, a.Streak(0, 6));
    }

    [Fact]
    public void AQuietSpellStartsTheCountOverAndEachCreatureCountsAlone()
    {
        var a = new Annoyance(limit: 2, calmAfter: 10);
        a.Bothered(0, 0); a.Bothered(0, 5);
        var later = a.Bothered(0, 16);
        Assert.False(later, "11 s of peace: this is the first again");
        Assert.Equal(1, a.Streak(0, 16));
        Assert.Equal(0, a.Streak(0, 30));      // calm by now
        a.Bothered(1, 16);
        Assert.Equal(1, a.Streak(1, 16));
        a.Forget(1);
        Assert.True(a.Streak(1, 16) == 0 && a.Streak(0, 16) == 1);
    }

    [Fact]
    public void EveryBuiltInCharacterComplainsInItsOwnWords()
    {
        var everyone = Banter.DefaultCharacters.Select(c => c.Name).Concat(Letters.Voices.Keys).ToHashSet();
        var rng = new Random();
        foreach (var name in everyone)
        {
            Assert.True(Complaints.Lines.TryGetValue(name, out var lines) && lines.Length >= 3, $"{name} has its own complaints");
            Assert.True(lines!.Any(l => l.Contains("{times}")), $"{name} counts at least once");
            Assert.DoesNotContain("{", Complaints.Line(name, 5, rng));
        }
        Assert.True(Complaints.Lines.Keys.All(everyone.Contains), "no lines for a character that does not exist");
        Assert.Contains(Complaints.Anyone, l => l.Contains("{times}"));
        Assert.True(Complaints.Prompt.Contains("{situation}") && Complaints.Prompt.Contains("{times}"));
    }

    [Fact]
    public void UpdateSaysWhenTheCursorMadeItJump()
    {
        var world = new EdgeWorld(new[] { new Rect(0, 0, 1020, 620) }, 10);
        var c = new Creature(world, new EdgeWorld.Spot(0, 300));
        var rng = new Random(3);
        var far = c.Update(1.0 / 30, new Pt(-500, -500), false, rng);
        Assert.False(far, "cursor far away");
        var near = c.Update(1.0 / 30, c.Position, false, rng);
        Assert.True(near && c.IsJumping, "cursor on it: it jumps");
        var again = c.Update(1.0 / 30, c.Position, false, rng);
        Assert.False(again, "already in the air: once per jump");
    }

    [Fact]
    public void ComplaintsAreTheirOwnLineInTheCosts()
    {
        var usage = new Spend.Usage(120, 20, 0.0001);
        var records = new[] { new Spend.Record(DateTimeOffset.Now, "OpenRouter", "m", usage, Spend.Purpose.Complaints) };
        Assert.Equal(new[] { "Complaints" }, Spend.Summarise(records, DateTimeOffset.Now).ByPurpose.Select(p => p.Purpose));
    }
}

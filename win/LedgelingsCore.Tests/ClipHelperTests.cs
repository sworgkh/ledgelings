namespace Ledgelings.Core.Tests;

/// <summary>SPEC §7.11.1: who brings the clipboard picker, where it holds the paper, and its leap.</summary>
public class ClipHelperTests
{
    private static ClipHelper.Candidate C(string name, double x, double y, bool asleep, bool free) => new(name, new Pt(x, y), asleep, free);

    [Fact]
    public void TheNamedOneComesWhenFreeElseTheNearestAwakeOne()
    {
        var centre = new Pt(500, 400);
        var all = new[] { C("Blocky", 0, 0, false, true), C("Zed", 480, 400, true, true), C("Pip", 900, 400, false, true), C("Dot", 500, 390, false, false) };
        Assert.Equal(2, ClipHelper.Choose(all, centre, ""));
        Assert.Equal(0, ClipHelper.Choose(all, centre, "Blocky"));
        Assert.Equal(2, ClipHelper.Choose(all, centre, "Dot"));
        Assert.Equal(0, ClipHelper.Choose(new[] { all[1] }, centre, ""));
        Assert.Null(ClipHelper.Choose(new[] { all[3] }, centre, ""));
    }

    [Fact]
    public void ItPerchesOverThePapersTopLeftCorner()
    {
        var paper = new Rect(100, 200, 600, 484);
        var p = ClipHelper.Perch(paper, 20);
        Assert.True(p.X < paper.MinX && p.X > paper.MinX - 20);
        Assert.True(p.Y > paper.MaxY && p.Y < paper.MaxY + 20);
    }

    [Fact]
    public void ALeapCrouchesArcsAndLands()
    {
        var leap = new ClipHelper.Leap(new Pt(0, 0), new Pt(400, 300), 0.2);
        Assert.Equal("land", leap.Pose);
        Assert.Equal(new Pt(0, 0), leap.Position);
        leap.Update(ClipHelper.Leap.Crouch + 0.1);
        Assert.Equal("jump", leap.Pose);
        Assert.True(leap.Rotation < -3 && leap.Rotation > -3.3);
        Assert.True(Math.Abs(leap.Position.X - 200) < 0.01);
        Assert.True(leap.Position.Y > 300);
        leap.Update(1);
        Assert.True(leap.IsDone);
        Assert.Equal("idle", leap.Pose);
        Assert.Equal(new Pt(400, 300), leap.Position);
        Assert.Equal(0, leap.Rotation);
    }

    [Fact]
    public void ALeapIsQuickAndFollowsTheSpeed()
    {
        Assert.Equal(0.14, ClipHelper.Flight(0, 1), 9);
        Assert.True(ClipHelper.Flight(1440, 1) < 0.4);
        Assert.Equal(0.4, ClipHelper.Flight(99_999, 1), 9);
        Assert.Equal(ClipHelper.Flight(600, 1) / 2, ClipHelper.Flight(600, 2), 9);
    }

    [Fact]
    public void EveryCharacterHasItsLinesInEveryLanguage()
    {
        foreach (var l in Languages.All)
        {
            foreach (var name in BedsTests.ShippedNames())
                Assert.True(ClipHelper.LinesIn(l).TryGetValue(name, out var lines) && lines.Count == 2, $"{name} {l}");
            Assert.NotEmpty(ClipHelper.AnyoneIn(l));
        }
        Assert.Equal("Хм. Вот эту?", ClipHelper.LinesIn(Language.Russian)["Whiskers"][1]);
        Assert.Contains(Languages.With(Language.English, () => ClipHelper.Line("Stranger", new Random(1))), ClipHelper.EnglishAnyone);
    }
}

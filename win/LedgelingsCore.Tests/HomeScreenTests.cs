namespace Ledgelings.Core.Tests;

/// <summary>Which monitors the colony lives on, and the spring off a monitor it leaves (SPEC §2.4). The Mac's HomeScreenTests.</summary>
public class HomeScreenTests
{
    private static readonly HomeScreen.Monitor Left = new(@"\\?\DISPLAY#DEL4085#1", "DELL U2415 (1)", new Rect(-1920, 0, 1920, 1200));
    private static readonly HomeScreen.Monitor Laptop = new(@"\\?\DISPLAY#BOE0A1C#2", "Built-in display", new Rect(0, 0, 1728, 1117));

    [Fact]
    public void AllIsEveryMonitorAndAChosenOneIsJustThatOne()
    {
        Assert.Equal(new[] { Left, Laptop }, HomeScreen.Home(HomeScreen.All, new[] { Left, Laptop }));
        Assert.Equal(new[] { Laptop }, HomeScreen.Home(Laptop.Id, new[] { Left, Laptop }));
        Assert.False(HomeScreen.IsAway(Laptop.Id, new[] { Left, Laptop }));
        Assert.False(HomeScreen.IsAway(HomeScreen.All, new[] { Left }));
    }

    [Fact]
    public void AnUnpluggedChoiceMeansEveryMonitorLeftUntilItIsBack()
    {
        Assert.Equal(new[] { Left }, HomeScreen.Home(Laptop.Id, new[] { Left }));
        Assert.True(HomeScreen.IsAway(Laptop.Id, new[] { Left }));
        Assert.Equal(new[] { Laptop }, HomeScreen.Home(Laptop.Id, new[] { Laptop, Left }));
    }

    [Fact]
    public void HomeIsInsideAHomeMonitorWithAsMuchSlackAsAsked()
    {
        var home = new[] { Laptop.Frame };
        Assert.True(HomeScreen.IsHome(new Pt(10, 10), home, 0));
        Assert.False(HomeScreen.IsHome(new Pt(-10, 10), home, 0));
        Assert.True(HomeScreen.IsHome(new Pt(-10, 10), home, 12));
    }

    [Fact]
    public void TheHopCrouchesThenSpringsOutThroughTheTopTurningOnceRound()
    {
        var hop = new HomeScreen.Hop(new Pt(100, 20), 0, 1300, 1);
        hop.Update(0.1);
        Assert.Equal(new Pt(100, 20), hop.Position);
        Assert.Equal("land", hop.Pose);
        double last = hop.Position.Y;
        int steps = 0;
        while (!hop.IsGone && steps < 1000)
        {
            hop.Update(1.0 / 30); steps++;
            Assert.True(hop.Position.Y >= last, "still going up when it leaves the screen");
            last = hop.Position.Y;
        }
        Assert.True(hop.IsGone && hop.Position.Y >= 1300);
        Assert.Equal("jump", hop.Pose);
        Assert.True(Math.Abs(Math.Abs(hop.Rotation) - HomeScreen.Hop.Spin) < 0.3, "one turn by the time it is gone");
        Assert.InRange(hop.FlightTime, 0.3, 2);
    }

    [Fact]
    public void ASleeperCanBeWokenToTakeOffAGameCannot()
    {
        var world = new EdgeWorld(new[] { new Rect(0, 0, 800, 600) }, 20);
        var c = new Creature(world, new EdgeWorld.Spot(0, 100));
        c.Settle();
        Assert.True(c.LooksAsleep);
        Assert.False(c.TakeOff(), "a game never wakes anyone");
        Assert.True(c.TakeOff(waking: true));
        Assert.True(c.IsPlaying && !c.LooksAsleep);
    }
}

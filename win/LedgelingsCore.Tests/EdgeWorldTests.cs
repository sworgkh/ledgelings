namespace Ledgelings.Core.Tests;

public class EdgeLoopTests
{
    readonly EdgeLoop loop = new(new Rect(10, 10, 1000, 600));

    [Fact]
    public void RunsCounterClockwiseFromTheBottomLeftCorner()
    {
        Assert.Equal(3200, loop.Length);
        Assert.Equal(new Pt(510, 10), loop.Point(500));
        Assert.Equal(new Pt(1010, 310), loop.Point(1300));
        Assert.Equal(new Pt(510, 610), loop.Point(2100));
        Assert.Equal(new Pt(10, 310), loop.Point(2900));
    }

    [Fact]
    public void SegmentsChangeExactlyAtCorners()
    {
        Assert.Equal(0, loop.Segment(999));
        Assert.Equal(1, loop.Segment(1000));
        Assert.Equal(2, loop.Segment(1600));
        Assert.Equal(3, loop.Segment(2600));
    }

    [Fact]
    public void WrapsInBothDirections()
    {
        Assert.Equal(50, loop.Wrap(3250));
        Assert.Equal(3150, loop.Wrap(-50));
        Assert.Equal(loop.Point(2900), loop.Point(-300));
    }

    [Fact]
    public void RotationStandsTheCreatureOnEachEdgeFacingInwards()
    {
        Assert.Equal(0, loop.Rotation(0));                                  // floor
        Assert.True(Math.Abs(loop.Rotation(1) - Math.PI / 2) < 1e-9);       // right wall
        Assert.True(Math.Abs(loop.Rotation(2) - Math.PI) < 1e-9);           // ceiling
        Assert.True(Math.Abs(loop.Rotation(3) - 3 * Math.PI / 2) < 1e-9);   // left wall
        Assert.Equal(new Vec(0, 1), loop.Inward(0));
        Assert.Equal(new Vec(-1, 0), loop.Inward(1));
    }

    [Fact]
    public void FindsTheNearestPointOnTheLoop()
    {
        var hit = loop.Nearest(new Pt(400, 30));
        Assert.Equal(390, hit.T);
        Assert.Equal(20, hit.Distance);
    }
}

public class EdgeWorldTests
{
    [Fact]
    public void OneScreenIsItsRectPulledInByTheInset()
    {
        var world = new EdgeWorld(new[] { new Rect(0, 0, 1020, 620) }, 10);
        Assert.Equal(new[] { new EdgeLoop(new Rect(10, 10, 1000, 600)) }, world.Loops);
    }

    [Fact]
    public void TwoEqualScreensSideBySideBecomeOneLoopWithNoSeam()
    {
        var world = new EdgeWorld(new[] { new Rect(0, 0, 1000, 600), new Rect(1000, 0, 1000, 600) }, 10);
        Assert.Equal(new[] { new EdgeLoop(new Rect(10, 10, 1980, 580)) }, world.Loops);
    }

    /// <summary>A tall screen on the left, a short one on the right, floors level:
    /// <code>
    ///     +------+
    ///     |      +------+
    ///     |      :      |
    ///     +------+------+
    /// </code></summary>
    [Fact]
    public void AShorterNeighbourMakesAnOutsideCornerToWalkRound()
    {
        var world = new EdgeWorld(new[] { new Rect(0, 0, 1000, 800), new Rect(1000, 0, 600, 500) }, 10);
        Assert.Single(world.Loops);
        Assert.Equal(new[]
        {
            new Pt(10, 10), new Pt(1590, 10), new Pt(1590, 490),
            new Pt(990, 490),      // under the short screen's ceiling, reaching the tall one...
            new Pt(990, 790),      // ...then up the tall screen's wall
            new Pt(10, 790),
        }, world.Loops[0].Vertices);
    }

    [Fact]
    public void NegativeCoordinatesWorkBecauseSecondaryScreensHaveThem()
    {
        var world = new EdgeWorld(new[] { new Rect(0, 0, 1000, 600), new Rect(-800, -200, 800, 600) }, 10);
        Assert.Single(world.Loops);
        Assert.Equal(8, world.Loops[0].Vertices.Count);
        Assert.Equal(new Pt(-790, -190), world.Loops[0].Vertices[0]);
    }

    [Fact]
    public void ScreensTouchingOnlyAtACornerStaySeparateLoops()
    {
        var world = new EdgeWorld(new[] { new Rect(0, 0, 1000, 600), new Rect(1000, 600, 1000, 600) }, 10);
        Assert.Equal(2, world.Loops.Count);
    }

    [Fact]
    public void NearestPicksTheRightLoop()
    {
        var world = new EdgeWorld(new[] { new Rect(0, 0, 1000, 600), new Rect(1000, 600, 1000, 600) }, 10);
        Assert.Equal(1, world.Nearest(new Pt(1500, 1195)).Loop);
        Assert.Equal(0, world.Nearest(new Pt(500, 0)).Loop);
    }

    [Fact]
    public void AnAbsurdInsetStillLeavesALoop()
    {
        var world = new EdgeWorld(new[] { new Rect(0, 0, 40, 40) }, 500);
        Assert.True(world.Loops[0].Length > 0);
    }
}

public class DayNightTests
{
    readonly DayNight clock = new(180, 300);

    [Fact]
    public void ThreeMinutesOfDayThenFiveOfNightForever()
    {
        Assert.False(clock.IsNight(0));
        Assert.False(clock.IsNight(179));
        Assert.True(clock.IsNight(180));
        Assert.True(clock.IsNight(479));
        Assert.False(clock.IsNight(480));
        Assert.True(clock.IsNight(480 + 200));
    }

    [Fact]
    public void SkippingLandsAtTheStartOfTheOtherHalf()
    {
        Assert.Equal(180, clock.SkippingToNextPhase(50));
        Assert.Equal(480, clock.SkippingToNextPhase(200));
        Assert.Equal(280, clock.Remaining(200));
    }

    [Fact]
    public void AZeroLengthNightMeansTheyNeverSleep()
    {
        Assert.False(new DayNight(60, 0).IsNight(59.9));
        Assert.False(new DayNight(60, 0).IsNight(60));
    }
}

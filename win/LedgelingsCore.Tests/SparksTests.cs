namespace Ledgelings.Core.Tests;

/// <summary>The little burst of pixel stars when two creatures bump.</summary>
public class SparksTests
{
    [Fact]
    public void ABurstThrowsStarsUpAndTheyFallBackAndDie()
    {
        var rng = new Random(7);
        var sparks = new Sparks();
        sparks.Burst(new Pt(100, 10), new Vec(0, 1), 8, rng);
        Assert.Equal(8, sparks.Alive.Count);
        sparks.Update(0.1);
        Assert.True(sparks.Alive.All(s => s.Position.Y > 10), "all thrown into the screen at first");
        for (int i = 0; i < 20; i++) sparks.Update(0.05);
        Assert.True(sparks.Alive.Count == 0, "gone after about a second");
    }

    [Fact]
    public void StarsFadeAsTheyAge()
    {
        var rng = new Random(8);
        var sparks = new Sparks(life: 1);
        sparks.Burst(Pt.Zero, new Vec(0, 1), 3, rng);
        sparks.Update(0.2);
        var early = sparks.Alive.Select(s => s.Opacity).ToList();
        sparks.Update(0.6);
        var late = sparks.Alive.Select(s => s.Opacity).ToList();
        Assert.True(early.Zip(late).All(p => p.First > p.Second));
        Assert.True(late.All(o => o > 0 && o < 0.5));
    }

    [Fact]
    public void GravityPullsThemBackTowardTheEdgeTheyCameFrom()
    {
        var rng = new Random(9);
        var sparks = new Sparks(life: 5);
        sparks.Burst(Pt.Zero, new Vec(-1, 0), 4, rng);   // a right-hand wall: "up" is leftwards
        sparks.Update(0.1);
        var before = sparks.Alive.Select(s => s.Velocity.Dx).ToList();
        sparks.Update(0.5);
        var after = sparks.Alive.Select(s => s.Velocity.Dx).ToList();
        Assert.True(before.Zip(after).All(p => p.Second > p.First), "each star's leftward speed shrinks");
    }
}

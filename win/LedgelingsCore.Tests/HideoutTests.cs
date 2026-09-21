namespace Ledgelings.Core.Tests;

/// <summary>The little house: appears, swallows everyone, packs itself away, and lets them out later.</summary>
public class HideoutTests
{
    [Fact]
    public void TheWholeCycleFromHideToWelcomeBack()
    {
        var h = new Hideout();
        Assert.True(!h.IsActive && h.Scale(0) == 0);
        h.Hide(3, 100, 60);
        Assert.True(h.IsActive && h.CurrentPhase == Hideout.Phase.Appearing);
        Assert.True(Math.Abs(h.Scale(100.2) - 0.5) < 1e-9);
        Assert.True(h.Update(100.4).Count == 0 && h.CurrentPhase == Hideout.Phase.Gathering);
        Assert.Equal(1, h.Scale(101));
        h.Entered(0, 101); h.Entered(1, 102);
        Assert.True(h.CurrentPhase == Hideout.Phase.Gathering && h.IsInside(1) && !h.IsInside(2));
        h.Entered(2, 103);
        Assert.Equal(Hideout.Phase.Shrinking, h.CurrentPhase);
        Assert.True(Math.Abs(h.Scale(103.25) - 0.5) < 1e-9);
        _ = h.Update(103.5);
        Assert.True(h.CurrentPhase == Hideout.Phase.Hidden && h.Scale(120) == 0);
        Assert.Equal(40, h.Remaining(120));
        _ = h.Update(159);
        Assert.Equal(Hideout.Phase.Hidden, h.CurrentPhase);
        _ = h.Update(160);
        Assert.Equal(Hideout.Phase.Growing, h.CurrentPhase);
        _ = h.Update(160.4);
        Assert.Equal(Hideout.Phase.Releasing, h.CurrentPhase);
        var letOut = new List<int>();
        // stride(from: 160.4, through: 163.0, by: 0.1)
        for (int k = 0; 160.4 + k * 0.1 <= 163.0 + 1e-9; k++)
        {
            var t = 160.4 + k * 0.1;
            foreach (var e in h.Update(t)) if (e is Hideout.Event.LetOut(var i)) letOut.Add(i);
        }
        Assert.Equal(new[] { 0, 1, 2 }, letOut);
        Assert.True(h.CurrentPhase == Hideout.Phase.Vanishing || h.CurrentPhase == Hideout.Phase.Away);
        _ = h.Update(164);
        Assert.True(h.CurrentPhase == Hideout.Phase.Away && !h.IsActive && h.Scale(164) == 0);
    }

    [Fact]
    public void StragglersAreForcedInsideWhenTheGatheringTakesTooLong()
    {
        var h = new Hideout();
        h.Hide(2, 0, 600);
        _ = h.Update(0.4);
        h.Entered(0, 1);
        var events = h.Update(0.4 + h.GatherCap);
        Assert.Contains(new Hideout.Event.ForceInside(new[] { 1 }), events);
        h.Entered(1, 26);
        Assert.Equal(Hideout.Phase.Shrinking, h.CurrentPhase);
    }

    [Fact]
    public void BringingThemBackEarlyOpensTheHouseNow()
    {
        var h = new Hideout();
        h.Hide(1, 0, 3600);
        _ = h.Update(0.4); h.Entered(0, 1); _ = h.Update(1.5);
        Assert.Equal(Hideout.Phase.Hidden, h.CurrentPhase);
        h.Recall(10);
        Assert.Equal(Hideout.Phase.Growing, h.CurrentPhase);
        Assert.Equal(0, h.Remaining(10));
    }

    [Fact]
    public void RecallingDuringTheGatheringJustLetsThemStay()
    {
        var h = new Hideout();
        h.Hide(2, 0, 3600);
        _ = h.Update(0.4); h.Entered(0, 1);
        h.Recall(2);
        Assert.Equal(Hideout.Phase.Releasing, h.CurrentPhase);
        var events = h.Update(2);
        Assert.Contains(new Hideout.Event.LetOut(0), events);
    }

    [Fact]
    public void HidingAgainWhileActiveIsIgnored()
    {
        var h = new Hideout();
        h.Hide(2, 0, 60);
        h.Hide(5, 1, 5);
        Assert.True(h.Count == 2 && h.Remaining(1) == 59 + 0.4 + 0.5 || h.Remaining(1) == 59);
    }
}

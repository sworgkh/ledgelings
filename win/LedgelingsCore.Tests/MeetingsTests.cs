namespace Ledgelings.Core.Tests;

public class MeetingsTests
{
    /// <summary>Two creatures of body half-size 10 on the bottom edge, <paramref name="gap"/> points apart.</summary>
    static List<Meetings.Party> Pair(double gap, (int, int)? segment = null, (int, int)? loop = null, (bool, bool)? canTalk = null)
    {
        var seg = segment ?? (0, 0);
        var lp = loop ?? (0, 0);
        var talk = canTalk ?? (true, true);
        return new List<Meetings.Party>
        {
            new(lp.Item1, seg.Item1, new Pt(100, 10), 10, talk.Item1),
            new(lp.Item2, seg.Item2, new Pt(120 + gap, 10), 10, talk.Item2),
        };
    }

    [Fact]
    public void WalkingIntoEachOtherBumpsOnceNotEveryFrame()
    {
        var meetings = new Meetings();
        Assert.Empty(meetings.Update(Pair(40), 0));
        var bumps = meetings.Update(Pair(4), 1);
        Assert.Equal(new[] { new Meetings.Bump(0, 1, 1, false) }, bumps);
        Assert.Empty(meetings.Update(Pair(2), 1.1));
        Assert.Empty(meetings.Update(Pair(0), 1.2));
    }

    [Fact]
    public void OnlyCreaturesOnTheSameEdgeOfTheSameMonitorBump()
    {
        var meetings = new Meetings();
        Assert.Empty(meetings.Update(Pair(0, segment: (0, 1)), 1));
        Assert.Empty(meetings.Update(Pair(0, loop: (0, 1)), 2));
    }

    [Fact]
    public void ASleeperOrJumperDoesNotBump()
    {
        var meetings = new Meetings();
        Assert.Empty(meetings.Update(Pair(0, canTalk: (true, false)), 1));
    }

    [Fact]
    public void APairWaitsOutTheCooldownBeforeBumpingAgain()
    {
        var meetings = new Meetings(cooldown: 60);
        Assert.Single(meetings.Update(Pair(0), 0));
        Assert.Empty(meetings.Update(Pair(100), 10));
        Assert.Empty(meetings.Update(Pair(0), 20));          // too soon
        Assert.Empty(meetings.Update(Pair(100), 30));
        Assert.Single(meetings.Update(Pair(0), 61));         // cooldown over
    }

    [Fact]
    public void TheThirdBumpIsAGiftAndTheCountStartsOver()
    {
        var meetings = new Meetings(cooldown: 0, giftEvery: 3);
        var seen = new List<Meetings.Bump>();
        for (int i = 0; i < 4; i++)
        {
            var t = (double)(i * 10);
            seen.AddRange(meetings.Update(Pair(0), t));
            Assert.Empty(meetings.Update(Pair(100), t + 5));
        }
        Assert.Equal(new[] { 1, 2, 3, 1 }, seen.Select(b => b.Count));
        Assert.Equal(new[] { false, false, true, false }, seen.Select(b => b.Gift));
    }

    [Fact]
    public void ThreeOnOneEdgeReportEveryTouchingPair()
    {
        var meetings = new Meetings();
        var three = Pair(0);
        three.Add(new Meetings.Party(0, 0, new Pt(140, 10), 10, true));
        var bumps = meetings.Update(three, 1);
        Assert.Equal(new[] { new[] { 0, 1 }, new[] { 1, 2 } }, bumps.Select(b => new[] { b.A, b.B }));
    }
}

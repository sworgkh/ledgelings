namespace Ledgelings.Core.Tests;

/// <summary>Flowers in flight and flowers on heads.</summary>
public class GiftsTests
{
    [Fact]
    public void AGiftFliesThenSitsOnTheHeadThenWilts()
    {
        var gifts = new Gifts(flightTime: 0.5);
        var given = gifts.Give("poppy", 0, 1, 10);
        Assert.True(given);
        Assert.Null(gifts.Hat(1));
        Assert.Equal(0.5, gifts.FlightProgress(10.25));
        gifts.Update(10.4, 60);
        Assert.True(gifts.CurrentFlight != null && gifts.Hat(1) == null);
        gifts.Update(10.5, 60);
        Assert.Null(gifts.CurrentFlight);
        Assert.Equal("poppy", gifts.Hat(1));
        gifts.Update(70.4, 60);
        Assert.Equal("poppy", gifts.Hat(1));
        gifts.Update(70.5, 60);
        Assert.Null(gifts.Hat(1));
    }

    [Fact]
    public void OnlyOneFlowerFliesAtATime()
    {
        var gifts = new Gifts();
        var first = gifts.Give("rose", 0, 1, 0);
        var second = gifts.Give("lily", 2, 3, 0.1);
        Assert.True(first && !second);
        Assert.Equal("rose", gifts.CurrentFlight?.Flower);
    }

    [Fact]
    public void CreaturesThatNoLongerExistLoseTheirFlowers()
    {
        var gifts = new Gifts(flightTime: 0);
        gifts.Give("daisy", 0, 4, 0);
        gifts.Update(0, 60);
        gifts.Give("tulip", 1, 5, 1);
        gifts.Forget(3);
        Assert.Null(gifts.Hat(4));
        Assert.Null(gifts.CurrentFlight);
    }

    [Fact]
    public void EveryFlowerHasAName()
    {
        Assert.Equal(10, Gifts.Flowers.Count);
        Assert.Equal(10, Gifts.Flowers.ToHashSet().Count);
    }
}

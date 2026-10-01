using static Ledgelings.Core.Garden;

namespace Ledgelings.Core.Tests;

/// <summary>Where and when each character plants its flower, and the flowers in the ground.</summary>
public class GardenTests
{
    static Temper TemperOf(string name)
    {
        var c = Banter.DefaultCharacters.First(c => c.Name == name);
        return Garden.TemperOf(c.Persona, Banter.DefaultKind);
    }

    static Surroundings Around(bool floor = true, double corner = 500, double creature = 200,
                               double flower = double.PositiveInfinity, bool night = false) =>
        new(floor ? new Vec(0, 1) : new Vec(0, -1), corner, creature, flower, night);

    [Fact]
    public void TheBuiltInCastEachHaveTheirOwnWay()
    {
        Assert.Equal(new[] { Place.Floor, Place.Alone }, TemperOf("Blocky").Likes);      // the bottom edge is the only respectable edge; grumpy
        Assert.Equal(new[] { Place.Ceiling, Place.Company }, TemperOf("Pip").Likes);     // loves the ceiling; cheerful
        Assert.Equal(Place.Row, TemperOf("Ruth").Likes[0]);                              // keeps count
        Assert.Equal(Place.Night, TemperOf("Zed").Likes[0]);                             // would rather be napping
        Assert.True(TemperOf("Dot").Keep < 0.1, "fast: plants at once");
        Assert.Empty(TemperOf("Dot").Likes);                                             // and anywhere
        Assert.True(TemperOf("Mortimer").Keep > TemperOf("Pip").Keep, "old and slow: wears it a while");
        Assert.True(TemperOf("Blocky").Keep > TemperOf("Mortimer").Keep, "proud: shows it off longest");
    }

    [Fact]
    public void EveryShippedCharacterLikesSomewhere()
    {
        var shipped = new Dictionary<string, string>
        {
            ["Whiskers"] = "Aloof. Pretends not to care, then asks what you are doing.",
            ["Morel"] = "Quiet and earthy. Speaks slowly about damp places and patience.",
            ["Puddle"] = "Anxious. Worried about drying out, evaporating, or being stepped on.",
            ["Unit 7"] = "Literal and precise. Reports its own status in numbers.",
            ["Sprocket"] = "Enthusiastic about maintenance. Offers to tighten everyone's bolts.",
        };
        Assert.Equal(Place.Alone, Garden.TemperOf(shipped["Whiskers"], "a cat").Likes[0]);
        Assert.Equal(new[] { "alone", "floor" },
            Garden.TemperOf(shipped["Morel"], "a mushroom").Likes.Select(Key).OrderBy(k => k, StringComparer.Ordinal));
        Assert.Equal(Place.Corner, Garden.TemperOf(shipped["Puddle"], "a slime").Likes[0]);
        Assert.Equal(Place.Corner, Garden.TemperOf(shipped["Unit 7"], "a robot").Likes[0]);
        var sprocket = Garden.TemperOf(shipped["Sprocket"], "a robot");
        Assert.True(sprocket.Likes[0] == Place.Row && sprocket.Keep < 0.1);
    }

    [Fact]
    public void SpeciesPlantByTheirKindWhenThePersonaSaysNothing()
    {
        var ghost = Garden.TemperOf("Says boo a lot.", "a little round ghost, hovering just above the edge");
        Assert.Equal(new[] { Place.Ceiling }, ghost.Likes);
        var nobody = Garden.TemperOf("Curious and new here.", "a small pixel creature");
        Assert.Empty(nobody.Likes);
        Assert.Equal(0.25, nobody.Keep);
    }

    [Fact]
    public void ThePersonaOutranksTheKind()
    {
        var t = Garden.TemperOf("Loves the ceiling.", "a frog that sits in the pond");
        Assert.Equal(new[] { Place.Ceiling, Place.Floor }, t.Likes);
    }

    [Fact]
    public void ItWearsTheFlowerBeforeItPlantsIt()
    {
        var blocky = TemperOf("Blocky");
        Assert.False(WantsToPlant(blocky, blocky.Keep - 0.01, Around()));
        Assert.True(WantsToPlant(blocky, blocky.Keep, Around()));
    }

    [Fact]
    public void ItWaitsForAPlaceItLikesThenMakesDo()
    {
        var blocky = TemperOf("Blocky");
        var ceilingNearSomeone = Around(floor: false, creature: 50);
        Assert.False(WantsToPlant(blocky, blocky.Keep, ceilingNearSomeone));
        Assert.False(WantsToPlant(blocky, 0.89, ceilingNearSomeone));
        Assert.True(WantsToPlant(blocky, LastChance, ceilingNearSomeone), "rather than let it wilt");
    }

    [Fact]
    public void AtFirstOnlyTheFavouriteWillDoThenAnySecondChoice()
    {
        var blocky = TemperOf("Blocky");
        var ceilingAlone = Around(floor: false, creature: 1_000);
        Assert.False(WantsToPlant(blocky, blocky.Keep, ceilingAlone), "only the floor, at first");
        Assert.True(WantsToPlant(blocky, 0.8, ceilingAlone), "later, alone will do");
    }

    [Fact]
    public void PlacesFit()
    {
        Assert.True(Fits(Place.Floor, Around()));
        Assert.True(Fits(Place.Ceiling, Around(floor: false)));
        Assert.True(Fits(Place.Wall, new Surroundings(new Vec(-1, 0), 500, 500, double.PositiveInfinity, false)));
        Assert.True(Fits(Place.Corner, Around(corner: 30)) && !Fits(Place.Corner, Around(corner: 300)));
        Assert.True(Fits(Place.Alone, Around(creature: double.PositiveInfinity)) && !Fits(Place.Alone, Around(creature: 100)));
        Assert.True(Fits(Place.Company, Around(creature: 100)));
        Assert.True(Fits(Place.Row, Around(flower: 40)) && !Fits(Place.Row, Around()), "a row needs a first flower");
        Assert.True(Fits(Place.Night, Around(night: true)) && Fits(Place.Day, Around()));
    }

    [Fact]
    public void FlowersStayTheirTimeAndTheOldestMakesRoom()
    {
        var garden = new Garden();
        var flowers = new[] { "poppy", "tulip", "daisy" };
        for (int i = 0; i < flowers.Length; i++)
            garden.Plant(flowers[i], new Pt(i * 100, 0), 0, 2, "Blocky", i, 60, 2);
        Assert.Equal(new[] { "tulip", "daisy" }, garden.Beds.Select(b => b.Flower));
        garden.Update(61.5, 2);
        Assert.Equal(new[] { "daisy" }, garden.Beds.Select(b => b.Flower));
        garden.Update(62, 2);
        Assert.Empty(garden.Beds);
    }

    [Fact]
    public void FewerAllowedWiltsTheOldest()
    {
        var garden = new Garden();
        for (int i = 0; i < 4; i++) garden.Plant("rose", new Pt(i * 100, 0), 0, 2, "Ruth", i, 600, 10);
        garden.Update(5, 1);
        Assert.Equal(new[] { 3.0 }, garden.Beds.Select(b => b.Planted));
    }

    [Fact]
    public void AFlowerNeedsRoom()
    {
        var garden = new Garden();
        garden.Plant("rose", Pt.Zero, 0, 2, "Ruth", 0, 60, 10);
        Assert.False(garden.HasRoom(new Pt(20, 0), 2));
        Assert.True(garden.HasRoom(new Pt(30, 0), 2));
        Assert.Equal(50, garden.DistanceTo(new Pt(30, 40)));
    }

    [Fact]
    public void ItComesUpOutOfTheGround()
    {
        var garden = new Garden();
        garden.Plant("lily", Pt.Zero, 0, 2, "Zed", 10, 60, 10);
        Assert.Equal(0, Grown(garden.Beds[0], 10));
        Assert.Equal(0.5, Grown(garden.Beds[0], 10 + GrowTime / 2));
        Assert.Equal(1, Grown(garden.Beds[0], 20));
    }

    [Fact]
    public void AHatCanBeTakenOffToPlant()
    {
        var gifts = new Gifts(flightTime: 0.5);
        gifts.Give("daisy", 0, 1, 0);
        gifts.Update(0.5, 100);
        Assert.Equal(0.5, gifts.WornShare(1, 50.5));
        Assert.Equal("daisy", gifts.TakeOff(1)?.Flower);
        Assert.True(gifts.Hat(1) == null && gifts.WornShare(1, 51) == null);
    }

    [Fact]
    public void ATemperReadsAsASentence()
    {
        Assert.Equal("After showing it off for most of its time, on the bottom edge or where nobody is.", Describe(TemperOf("Blocky")));
        Assert.Equal("At once, wherever it is.", Describe(TemperOf("Dot")));
        Assert.Equal("After a little while, beside the flowers already planted, in a corner or after dark.",
            Describe(new Temper(0.25, new[] { Place.Row, Place.Corner, Place.Night })));
    }
}

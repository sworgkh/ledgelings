namespace Ledgelings.Core.Tests;

/// <summary>Weather on a quiet screen (SPEC §7.20): the quiet rule, the seasons, a spell easing off, the snow piles, the
/// umbrellas, the bowl on the top edge, the wind, the switches, the props and the lines. The Mac's WeatherTests.</summary>
public class WeatherTests
{
    static readonly Weather.Screen Quiet = new(600, 20);

    // MARK: Quiet

    [Fact]
    public void QuietNeedsEveryConditionAtOnce()
    {
        Assert.True(Weather.IsQuiet(Quiet, 5));
        Assert.False(Weather.IsQuiet(Quiet with { KeyIdle = 200 }, 5));
        Assert.False(Weather.IsQuiet(Quiet with { CursorTravel = 400 }, 5));
        Assert.True(Weather.IsQuiet(Quiet with { CursorTravel = Weather.CursorAllowance }, 5));
        Assert.False(Weather.IsQuiet(Quiet with { FullScreen = true }, 5));
        Assert.False(Weather.IsQuiet(Quiet with { Activity = true }, 5));
        Assert.False(Weather.IsQuiet(Quiet with { Meeting = true }, 5));
        Assert.False(Weather.IsQuiet(Quiet, 15));
    }

    [Fact]
    public void ComingBackIsAKeyOrMoreThanANudge()
    {
        Assert.True(Weather.IsBack(0.5, 0));
        Assert.True(Weather.IsBack(100, 200));
        Assert.False(Weather.IsBack(100, 10));
    }

    [Fact]
    public void TheCursorTrailAddsUpWhereItWent()
    {
        var trail = new Weather.CursorTrail();
        trail.Add(new Pt(0, 0), 0, 60);
        trail.Add(new Pt(30, 40), 1, 60);
        trail.Add(new Pt(30, 40), 2, 60);
        Assert.Equal(50, trail.Travel(0));
        Assert.Equal(0, trail.Travel(1.5));
        trail.Add(new Pt(0, 0), 100, 60);
        Assert.Equal(0, trail.Span);
    }

    // MARK: Seasons

    [Fact]
    public void TheSeasonWeighsWhichWeatherComes()
    {
        var s = new Weather.Switches();
        var winter = Weather.Weights(Effects.Season.Winter, s);
        var summer = Weather.Weights(Effects.Season.Summer, s);
        var autumn = Weather.Weights(Effects.Season.Autumn, s);
        Assert.True(winter[Weather.Kind.Snow] > winter[Weather.Kind.Rain] && winter[Weather.Kind.Snow] > winter[Weather.Kind.Wind]);
        Assert.False(summer.ContainsKey(Weather.Kind.Snow));
        Assert.True(autumn[Weather.Kind.Wind] > autumn[Weather.Kind.Rain] && autumn[Weather.Kind.Wind] > autumn[Weather.Kind.Snow]);
        foreach (var season in Enum.GetValues<Effects.Season>()) Assert.True(Weather.Weights(season, s).ContainsKey(Weather.Kind.Rain));
        var counts = new Dictionary<Weather.Kind, int>();
        for (int k = 0; k < 1000; k++) { var p = Weather.Pick(Effects.Season.Winter, s, k / 1000.0)!.Value; counts[p] = counts.GetValueOrDefault(p) + 1; }
        Assert.True(counts[Weather.Kind.Snow] > 600);
        Assert.Equal(1, Weather.Weights(Effects.Season.Summer, s with { FollowSeason = false })[Weather.Kind.Snow]);
    }

    [Fact]
    public void AWeatherSwitchedOffNeverComes()
    {
        var s = new Weather.Switches { Snow = false };
        Assert.False(Weather.Weights(Effects.Season.Winter, s).ContainsKey(Weather.Kind.Snow));
        s = s with { Rain = false };
        Assert.False(Weather.Weights(Effects.Season.Winter, s).ContainsKey(Weather.Kind.Storm));
        s = s with { Wind = false };
        Assert.Null(Weather.Pick(Effects.Season.Winter, s, 0.3));
        Assert.Null(Weather.Pick(Effects.Season.Autumn, new Weather.Switches { Enabled = false }, 0.3));
        Assert.True(Weather.Chance(10, Weather.Frequency.Often) > Weather.Chance(10, Weather.Frequency.Rarely));
    }

    // MARK: A spell

    [Fact]
    public void ASpellComesInStaysAndEasesOffSlowly()
    {
        var spell = new Weather.Spell(Weather.Kind.Snow, 60);
        spell.Update(3);
        Assert.InRange(spell.Intensity, 0.4, 0.6);
        spell.Update(10);
        Assert.True(spell.Intensity == 1 && !spell.IsEasing);
        spell.Ease();
        spell.Update(0.1);
        Assert.True(spell.Intensity > 0.9 && spell.IsEasing && !spell.IsOver);
        spell.Update(Weather.Spell.EaseOff / 2);
        Assert.InRange(spell.Intensity, 0.3, 0.7);
        spell.Update(Weather.Spell.EaseOff);
        Assert.True(spell.IsOver);
        var timed = new Weather.Spell(Weather.Kind.Rain, 30);
        timed.Update(31);
        Assert.True(timed.IsEasing);
    }

    // MARK: Snow piles

    [Fact]
    public void ThePileGrowsToItsCapAndMelts()
    {
        var pile = new Weather.Pile(40, Weather.BottomCap(Weather.Level.Medium));
        for (int i = 0; i < 1000; i++) pile.Grow(0.1);
        Assert.Equal(Weather.BottomCap(Weather.Level.Medium), pile.Deepest);
        Assert.Equal(pile.Cap, pile.Average, 9);
        for (int x = 0; x < 40; x++) pile.Land(x, 3);
        Assert.True(pile.Deepest <= pile.Cap);
        pile.Melt(2);
        Assert.Equal(pile.Cap - 2, pile.Deepest, 9);
        pile.Melt(100);
        Assert.True(pile.IsEmpty);
        Assert.True(Weather.BottomCap(Weather.Level.Low) < Weather.BottomCap(Weather.Level.Medium) && Weather.BottomCap(Weather.Level.Medium) < Weather.BottomCap(Weather.Level.High));
        Assert.True(Weather.WindowCap(Weather.Level.Medium) < Weather.BottomCap(Weather.Level.Medium));
    }

    [Fact]
    public void FlakesHeapUpAndSlideOffASteepColumn()
    {
        var pile = new Weather.Pile(9, 20);
        for (int i = 0; i < 20; i++) pile.Land(4, 1);
        Assert.True(pile.Height(4) > pile.Height(0));
        for (int x = 1; x < 9; x++) Assert.True(Math.Abs(pile.Height(x) - pile.Height(x - 1)) <= 2.5);
    }

    [Fact]
    public void AFootprintIsADent()
    {
        var pile = new Weather.Pile(10, 8);
        pile.Grow(6);
        pile.Step(4);
        Assert.True(pile.Height(4) == 5 && pile.Height(5) == 5 && pile.Height(3) == 6);
    }

    [Fact]
    public void WadingInDeepSnowIsSlower()
    {
        Assert.Equal(1, Weather.Wading(0, 8));
        Assert.Equal(0.5, Weather.Wading(8, 8));
        Assert.Equal(0.75, Weather.Wading(4, 8));
    }

    static void Step(Weather.Sky sky, double dt, Weather.Kind? kind, double intensity, Weather.Level heaviness = Weather.Level.Medium, bool windowTops = true, bool reduced = false) =>
        sky.Update(dt, kind, intensity, 0, heaviness, Weather.Level.Medium, windowTops, reduced);

    [Fact]
    public void TheSkyPilesSnowOnTheBottomAndOnWindowTopsAndDropsIt()
    {
        var sky = new Weather.Sky(120, 80, Weather.Level.Medium, 3);
        sky.SetLedges(new Dictionary<int, Weather.Ledge> { [7] = new(20, 40, Enumerable.Repeat(true, 60).ToArray()) }, Weather.Level.Medium);
        for (int i = 0; i < 30 * 120; i++) Step(sky, 1.0 / 30, Weather.Kind.Snow, 1);
        Assert.True(sky.Bottom.Average > 4);
        Assert.True((sky.LedgePile(7)?.Average ?? 0) > 2);
        Assert.True(sky.Bottom.Deepest <= Weather.BottomCap(Weather.Level.Medium));
        var flakes = 0;
        sky.OnShower = (_, n) => flakes = n;
        sky.SetLedges(new Dictionary<int, Weather.Ledge> { [7] = new(50, 40, Enumerable.Repeat(true, 60).ToArray()) }, Weather.Level.Medium);
        Assert.True(flakes > 20);
        Assert.Equal(0, sky.LedgePile(7)?.Average ?? 1);
        sky.FillLedges(3);
        Step(sky, 0.1, Weather.Kind.Snow, 1, windowTops: false);
        Assert.True(sky.LedgePile(7)?.IsEmpty);
        var before = sky.Bottom.Average;
        Step(sky, 10, null, 0);
        Assert.True(sky.Bottom.Average < before && sky.Bottom.Average > before - 1);
        for (int i = 0; i < 100; i++) Step(sky, 10, null, 0);
        Assert.True(sky.Bottom.IsEmpty);
    }

    [Fact]
    public void RainMakesPuddlesThatDry()
    {
        var sky = new Weather.Sky(100, 60, Weather.Level.Medium, 5);
        for (int i = 0; i < 30 * 60; i++) Step(sky, 1.0 / 30, Weather.Kind.Rain, 1, Weather.Level.High);
        Assert.True(sky.Wet.Max() > 0.5);
        Assert.True(sky.Bottom.IsEmpty);
        Step(sky, Weather.DrySeconds + 1, null, 0, Weather.Level.High);
        Assert.Equal(0, sky.Wet.Max());
    }

    [Fact]
    public void ReduceMotionHalvesTheParticles()
    {
        int Count(bool reduced)
        {
            var sky = new Weather.Sky(200, 400, Weather.Level.Medium, 9);
            for (int i = 0; i < 60; i++) Step(sky, 1.0 / 30, Weather.Kind.Snow, 1, reduced: reduced);
            return sky.Particles.Count;
        }
        int full = Count(false), half = Count(true);
        Assert.True(half < full * 2 / 3 && half > full / 3);
    }

    // MARK: Umbrellas

    [Fact]
    public void WhoSharesAnUmbrella()
    {
        var one = new[] { new Weather.Standing(0, 0, 100) };
        Assert.Equal(new[] { new[] { 0 } }, Weather.UmbrellaGroups(one, 40).Select(g => g.ToArray()));
        var two = one.Append(new Weather.Standing(1, 0, 130)).ToArray();
        Assert.Equal(new[] { new[] { 0, 1 } }, Weather.UmbrellaGroups(two, 40).Select(g => g.ToArray()));
        var three = two.Append(new Weather.Standing(2, 0, 400)).ToArray();
        Assert.Equal(new[] { new[] { 0, 1 }, new[] { 2 } }, Weather.UmbrellaGroups(three, 40).Select(g => g.ToArray()));
        Assert.Equal(new[] { new[] { 0 }, new[] { 1 } }, Weather.UmbrellaGroups(two, 0).Select(g => g.ToArray()));
        var walls = new[] { new Weather.Standing(0, 0, 100), new Weather.Standing(1, 1, 105) };
        Assert.Equal(new[] { new[] { 0 }, new[] { 1 } }, Weather.UmbrellaGroups(walls, 40).Select(g => g.ToArray()));
        var crowd = Enumerable.Range(0, 5).Select(i => new Weather.Standing(i, 0, i * 10));
        Assert.Equal(new[] { 3, 2 }, Weather.UmbrellaGroups(crowd, 40).Select(g => g.Count));
        Assert.Equal(5, Weather.Holder(new[] { 4, 5, 6 }));
        Assert.True(Weather.UmbrellaWidth(2) > Weather.UmbrellaWidth(1));
    }

    [Fact]
    public void TheBowlOnTheTopEdgeFillsTipsAndFalls()
    {
        var bowl = new Weather.Bowl();
        var events = new List<Weather.Bowl.Event>();
        var t = 0.0;
        while (t < 60)
        {
            if (bowl.Update(0.1, 1, Weather.Level.Medium) is { } e) events.Add(e);
            t += 0.1;
            if (bowl.Now == Weather.Bowl.State.Fallen) break;
        }
        Assert.Equal(new[] { Weather.Bowl.Event.Full, Weather.Bowl.Event.Spills }, events);
        Assert.True(t >= Weather.Bowl.FillSeconds && t < Weather.Bowl.FillSeconds + Weather.Bowl.TipSeconds + 1);
        Assert.True(bowl.Tip == 1 && bowl.Water == 0);
        var heavy = new Weather.Bowl();
        var light = new Weather.Bowl();
        heavy.Update(5, 1, Weather.Level.High);
        light.Update(5, 1, Weather.Level.Low);
        Assert.True(heavy.Water > light.Water);
    }

    // MARK: Wind

    [Fact]
    public void TheWindPushesTheLightOnesAndSlowsThoseWalkingIntoIt()
    {
        var wind = new Weather.Wind(true, Weather.Level.Medium);
        Assert.True(wind.Force(Weather.Wind.GustLasts / 2) > 0.99);
        Assert.True(wind.Force(Weather.Wind.GustEvery - 1) < 0.31);
        Assert.True(wind.Peaks(Weather.Wind.GustLasts / 2 + 0.01, 0.03));
        Assert.False(wind.Peaks(4, 0.03));
        Assert.True(Weather.Push(1, 1, Weather.Level.Medium) >= 4);
        Assert.True(Weather.Push(2.5, 1, Weather.Level.Medium) <= 1);
        Assert.True(Weather.Push(1, 1, Weather.Level.High) > Weather.Push(1, 1, Weather.Level.Low));
        Assert.True(Weather.WindPace(1, wind, 1) > 1);
        Assert.True(Weather.WindPace(-1, wind, 1) < 1);
        Assert.True(Weather.BlowsOff(0.7, 1, Weather.Level.Medium));
        Assert.False(Weather.BlowsOff(2, 1, Weather.Level.Medium));
        Assert.True(Weather.TurnsInsideOut(1, Weather.Level.Medium, 0.1));
        Assert.False(Weather.TurnsInsideOut(0.4, Weather.Level.Medium, 0.1));
        Assert.True(wind.Lean(1.25, 1) < 0);
    }

    [Fact]
    public void AGustShovesACreatureAlongItsEdgeOnly()
    {
        var world = new EdgeWorld(new[] { new Rect(0, 0, 800, 600) }, 10);
        var c = new Creature(world, new EdgeWorld.Spot(0, 300));
        c.Pause(100);
        var x = c.Position.X;
        c.Shove(4);
        Assert.Equal(x + 4, c.Position.X, 9);
        c.Shove(-10_000);
        Assert.Equal(0, c.Loop.Segment(c.T));
    }

    // MARK: Props and lines

    [Fact]
    public void ThePropsAreDrawnInBlockysStyle()
    {
        foreach (var art in new[] { Weather.Umbrella(27, Weather.UmbrellaColours[0]), Weather.Umbrella(49, Weather.UmbrellaColours[1], insideOut: true),
                                    Weather.Snowman(), Weather.Snowball(), Weather.Gusts(), Weather.Sun() })
        {
            Assert.Contains(art.Pixels, p => p != 0);
            var rgba = art.Rgba;
            for (int i = 3; i < rgba.Length; i += 4) Assert.True(rgba[i] == 0 || rgba[i] == 255);
        }
        var u = Weather.Umbrella(27, Weather.UmbrellaColours[0]);
        Assert.Equal(1, u.W % 2);
        Assert.NotEqual(0u, u.At(u.W / 2, u.H - 2));
        Assert.Equal(Weather.UmbrellaColour("Blocky"), Weather.UmbrellaColour("Blocky"));
    }

    static readonly string[] Cast = { "Blocky", "Pip", "Mortimer", "Zed", "Dot", "Ruth", "Whiskers", "Mittens", "Sir Pounce", "Hopper", "Mossy", "Croak",
                                      "Boo", "Wisp", "Sheet", "Morel", "Puff", "Cap", "Unit 7", "Sprocket", "Glitch", "Goop", "Puddle", "Blorp",
                                      "Spike", "Wedge", "Delta", "Prickles", "Saguaro", "Tumble", "Click", "Scarab", "Crumb", "Shard", "Quartz", "Prism",
                                      "Sprout", "Fern", "Bud" };

    [Fact]
    public void EveryCharacterHasItsOwnWeatherLinesInEveryLanguage()
    {
        foreach (var l in new[] { Language.English, Language.Russian })
        {
            var table = Weather.LinesIn(l);
            Assert.Equal(Cast.OrderBy(n => n), table.Keys.OrderBy(n => n));
            var all = table.Append(new KeyValuePair<string, IReadOnlyDictionary<string, IReadOnlyList<string>>>("anyone", Weather.AnyoneIn(l)));
            foreach (var (name, lines) in all)
            {
                foreach (var kind in Weather.LineKinds) Assert.True(lines.TryGetValue(kind, out var pool) && pool.Count > 0, $"{l} {name} has no {kind} line");
                foreach (var kind in new[] { "throw", "hit", "share" })
                    foreach (var line in lines[kind]) Assert.Equal(2, line.Split("{friend}").Length);
            }
        }
        Assert.NotEqual(Weather.LinesIn(Language.English)["Zed"]["snow"], Weather.LinesIn(Language.Russian)["Zed"]["snow"]);    // from ru.json
        var rng = new Random(4);
        var line2 = Weather.Line("Blocky", "throw", "Boo", rng);
        Assert.True(line2.Contains("Boo") && !line2.Contains("{friend}"));
        Assert.NotEmpty(Weather.Line("Someone New", "rain", "", rng));
        Languages.With(Language.Russian, () =>
            Assert.Matches("[а-яА-Я]", Weather.Line("Unit 7", "snow", "", new Random(4))));
    }
}

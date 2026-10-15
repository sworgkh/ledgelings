namespace Ledgelings.Core.Tests;

/// <summary>The games (SPEC §7.10): who plays and how often, tag's touches, the rope's swing, the parachute's
/// fall, the ball's flight, the creature off its edge, and the words. The Mac's PlaysTests.</summary>
public class PlaysTests
{
    private static readonly Rect Screen = new(0, 0, 1440, 900);
    private const double Inset = 25;
    private static readonly string Root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../.."));
    private readonly EdgeWorld world = new(new[] { Screen }, Inset);

    // Who plays, and when

    [Fact]
    public void ClosenessCountsTheMomentsTheyShared()
    {
        Assert.Equal(0, Plays.Closeness(null));
        var bond = new Bonds.Bond(new[] { "Blocky", "Pip" });
        Assert.Equal(0, Plays.Closeness(bond));
        bond.Tally = new() { ["talk"] = 6, ["tea"] = 4 };
        Assert.Equal(0.5, Plays.Closeness(bond));
        bond.Tally = new() { ["talk"] = 40 };
        Assert.Equal(1, Plays.Closeness(bond));                                       // no closer than close
        bond.Tally = new();
        bond.Talks = 5;
        Assert.Equal(0.25, Plays.Closeness(bond));                                    // before storylines, their talks count
    }

    [Fact]
    public void FriendsWaitLessForTheNextGame()
    {
        var rng = new Random(1);
        for (int i = 0; i < 50; i++)
        {
            var strangers = Plays.Wait(5, 100, 0, rng);
            Assert.InRange(strangers, 5 * 60 * 0.6, 5 * 60 * 1.4);
            var friends = Plays.Wait(5, 100, 1, rng);
            Assert.InRange(friends, 5 * 60 * 0.3, 5 * 60 * 0.7);                     // at 100 % the best of friends wait half as long
            Assert.True(Plays.Wait(5, 0, 1, rng) >= 5 * 60 * 0.6);
        }
    }

    [Fact]
    public void StrangersPlayAloneAndFriendsMostlyTogether()
    {
        var rng = new Random(7);
        var all = Plays.AllKinds.ToHashSet();
        for (int i = 0; i < 100; i++)
        {
            var chosen = Plays.Choose(0, new[] { (1, 0.1), (2, 0.0) }, all, rng);
            Assert.True(chosen is { } c && c.Players.SequenceEqual(new[] { 0 }) && c.Kind.CanSolo());   // a stranger never plays tag
        }
        int together = 0;
        for (int i = 0; i < 400; i++)
        {
            var chosen = Plays.Choose(0, new[] { (1, 1.0), (2, 0.5) }, all, rng)!.Value;
            if (chosen.Players.Length != 2) continue;
            together++;
            Assert.Equal(new[] { 0, 1 }, chosen.Players);                            // with its closest friend
            Assert.True(chosen.Kind.CanPair());
        }
        Assert.True(Math.Abs(together / 400.0 - Plays.PairChance(1)) < 0.08, $"{together}");
        Assert.Null(Plays.Choose(0, Array.Empty<(int, double)>(), new HashSet<Plays.Kind> { Plays.Kind.Tag }, rng));   // tag alone is no game
        Assert.Equal(Plays.Kind.Tag, Plays.Choose(0, new[] { (1, 1.0) }, new HashSet<Plays.Kind> { Plays.Kind.Tag }, rng)?.Kind);
        Assert.Null(Plays.Choose(0, new[] { (1, 1.0) }, new HashSet<Plays.Kind>(), rng));
    }

    // Tag

    [Fact]
    public void TagSwapsWhoIsItOnATouchAndEndsOutOfBreath()
    {
        var tag = new Plays.Tag(3, 8, 20);
        Assert.True(tag.It == 3 && tag.Runner == 8 && tag.ItIsCounting);
        Assert.Null(tag.Near(0, 50));                                                 // not before the go
        var events = new List<Plays.Tag.Event>();
        for (int i = 0; i < 12; i++) events.AddRange(tag.Update(0.1));
        Assert.Equal(new Plays.Tag.Event[] { new Plays.Tag.Event.Go() }, events);
        Assert.Equal(new Plays.Tag.Event.Tagged(3, 8), tag.Near(40, 50));
        Assert.True(tag.It == 8 && tag.Runner == 3 && tag.ItIsCounting);              // the new one counts first
        Assert.Null(tag.Near(0, 50));                                                 // no tagging back while counting
        for (int i = 0; i < 11; i++) tag.Update(0.1);
        Assert.False(tag.ItIsCounting);
        Assert.Null(tag.Near(60, 50));                                                // too far to touch
        Assert.Equal(new Plays.Tag.Event.Tagged(8, 3), tag.Near(10, 50));
        events.Clear();
        for (int i = 0; i < 300; i++) events.AddRange(tag.Update(0.1));
        Assert.Equal(new Plays.Tag.Event[] { new Plays.Tag.Event.Puffing(), new Plays.Tag.Event.Over() }, events);
        Assert.True(tag.Touches == 2 && tag.CurrentPhase == Plays.Tag.Phase.Over);
    }

    // The rope

    [Fact]
    public void TheRopeSwingsClearOfTheFloorAndLandsBackOnIt()
    {
        var floor = world.Floor(new Pt(300, 100))!.Value;
        var ceiling = world.Ceiling(new Pt(300, 100))!.Value;
        Assert.True(floor.Y == Inset && ceiling.Y == Screen.Height - Inset);
        var start = new Pt(300, floor.Y);
        var top = Screen.Height;
        var rope = Plays.Rope.Plan(start, top, floor.From, floor.To, 1, 60)!;
        Assert.True(rope.Way == 1 && rope.Anchor.Y == top && rope.Anchor.X > start.X);
        var events = new List<Plays.Rope.Event>();
        double lowest = double.PositiveInfinity, t = 0;
        while (rope.CurrentPhase != Plays.Rope.Phase.Landed && t < 20)
        {
            events.AddRange(rope.Update(1.0 / 30));
            t += 1.0 / 30;
            if (rope.CurrentPhase == Plays.Rope.Phase.Swing) lowest = Math.Min(lowest, rope.Position.Y);
            if (rope.CurrentPhase is Plays.Rope.Phase.Swing or Plays.Rope.Phase.Reel)
                Assert.True(rope.Position.DistanceTo(rope.Anchor) <= rope.FiredLength + 0.5);
        }
        Assert.Equal(new[] { Plays.Rope.Event.Fired, Plays.Rope.Event.Hooked, Plays.Rope.Event.Swinging, Plays.Rope.Event.LetGo, Plays.Rope.Event.Landed }, events);
        Assert.True(lowest >= floor.Y + 60 - 2, $"never scrapes the floor at the bottom of the swing: {lowest}");
        Assert.True(rope.Position.Y == floor.Y && rope.Rotation == 0);
        Assert.True(rope.Position.X > rope.Anchor.X, "let go past the hook, and flew on");
        Assert.True(floor.Covers(rope.Position.X));
    }

    [Fact]
    public void NoRopeUnderALowCeilingAndTheOtherWayWhenThereIsNoRoom()
    {
        var floor = world.Floor(new Pt(300, 100))!.Value;
        Assert.Null(Plays.Rope.Plan(new Pt(300, 25), 120, floor.From, floor.To, 1, 60));
        var rope = Plays.Rope.Plan(new Pt(floor.To - 40, floor.Y), 900, floor.From, floor.To, 1, 60)!;
        Assert.Equal(-1, rope.Way);
    }

    // The parachute

    [Fact]
    public void TheParachuteOpensFloatsDownAtItsSpeedAndPacksAway()
    {
        var top = new Pt(700, 875);
        var chute = new Plays.Chute(top, 25, 25, 1415, 70);
        var events = new List<Plays.Chute.Event>();
        var floating = new List<(double T, double Y)>();
        double t = 0;
        while (chute.CurrentPhase != Plays.Chute.Phase.Packed && t < 60)
        {
            events.AddRange(chute.Update(1.0 / 30));
            t += 1.0 / 30;
            if (chute.CurrentPhase == Plays.Chute.Phase.Float) floating.Add((t, chute.Position.Y));
            Assert.True(Math.Abs(chute.Position.X - top.X) <= Plays.Chute.Sway + 0.01);
        }
        Assert.Equal(new[] { Plays.Chute.Event.Jumped, Plays.Chute.Event.Opened, Plays.Chute.Event.Landed, Plays.Chute.Event.Packed }, events);
        var speed = (floating[0].Y - floating[^1].Y) / (floating[^1].T - floating[0].T);
        Assert.True(Math.Abs(speed - 70) < 3, $"comes down at its speed: {speed}");
        Assert.True(chute.Position.Y == 25 && chute.Canopy == 0 && chute.Rotation == 0);
        Assert.InRange(t, 8, 14);                                                     // about ten seconds down a laptop screen
    }

    // Basketball

    [Fact]
    public void TheHoopHangsOnItsWallAndATrueThrowGoesIn()
    {
        var hoop = new Plays.Hoop(1440, 1, 0, 180, 2);
        Assert.True(hoop.RimX == 1440 - 15 * 2 && hoop.RimHalf == 18 && hoop.RimY == 180);
        Assert.Equal(1392, hoop.Front.X);
        var mirrored = new Plays.Hoop(0, -1, 0, 180, 2);
        Assert.True(mirrored.RimX == 30 && mirrored.Front.X == 48);
        foreach (var (h, from) in new[] { (hoop, new Pt(1100, 60)), (mirrored, new Pt(340, 60)) })
            foreach (var apex in new[] { 50.0, 100, 150 })
            {
                var v = Plays.Ball.Aim(from, h, apex);
                var ball = new Plays.Ball(from, v, 10, 0.6, h, 0, 0, 1440);
                var events = new List<Plays.Ball.Event>();
                for (int i = 0; i < 300; i++) events.AddRange(ball.Step(1.0 / 30));
                Assert.True(events.Contains(Plays.Ball.Event.Scored), $"apex {apex}: {string.Join(",", events)}");
                Assert.True(ball.Resting, "comes to rest on the floor");
                Assert.Equal(10, ball.Position.Y);
            }
    }

    [Fact]
    public void AShortThrowMissesAndADeadBallDoesNotBounce()
    {
        var hoop = new Plays.Hoop(1440, 1, 0, 180, 2);
        var from = new Pt(1100, 60);
        var v = Plays.Ball.Aim(from, hoop, 100);
        var ball = new Plays.Ball(from, v with { Dx = v.Dx * 0.7 }, 12, 0.6, hoop, 0, 0, 1440);
        var events = new List<Plays.Ball.Event>();
        for (int i = 0; i < 300; i++) events.AddRange(ball.Step(1.0 / 30));
        Assert.True(!events.Contains(Plays.Ball.Event.Scored) && !ball.Scored);
        var dead = new Plays.Ball(new Pt(700, 300), Vec.Zero, 12, 0, hoop, 0, 0, 1440);
        for (int i = 0; i < 60; i++) dead.Step(1.0 / 30);
        Assert.True(dead.Resting && dead.Position.Y == 12);
        var lively = new Plays.Ball(new Pt(700, 300), Vec.Zero, 12, 0.8, hoop, 0, 0, 1440);
        double highest = 0;
        bool landed = false;
        for (int i = 0; i < 60; i++)
        {
            lively.Step(1.0 / 30);
            if (lively.Position.Y <= 13) landed = true;
            else if (landed) highest = Math.Max(highest, lively.Position.Y);
        }
        Assert.True(highest > 100, "a bouncy ball comes back up");
    }

    // The edges

    [Fact]
    public void FloorsCeilingsAndTheWallsAtAFloorsEnds()
    {
        var floor = world.Floor(new Pt(700, 400))!.Value;
        Assert.True(floor.From == 25 && floor.To == 1415);
        var walls = world.Walls(floor);
        Assert.True(walls.Select(w => w.Side).ToHashSet().SetEquals(new[] { -1.0, 1 }) && walls.All(w => w.Height == 850));
        Assert.Single(world.Ceilings);
        // Two monitors side by side, the right one lower: the step between them is a wall seen from
        // the lower floor, and a drop (no wall) seen from the upper one.
        var two = new EdgeWorld(new[] { new Rect(0, 0, 1000, 800), new Rect(1000, -200, 800, 600) }, 20);
        var lower = two.Floor(new Pt(1400, 0))!.Value;
        Assert.Equal(-180, lower.Y);
        Assert.Equal(new[] { 1.0, -1 }, two.Walls(lower).Select(w => w.Side));
        Assert.Equal(200, two.Walls(lower)[^1].Height);
        var upper = two.Floor(new Pt(500, 300))!.Value;
        Assert.Equal(new[] { -1.0 }, two.Walls(upper).Select(w => w.Side));
        Assert.Equal(380, two.Ceiling(new Pt(1400, 0))?.Y);
    }

    // The creature

    [Fact]
    public void APlayerIsCarriedIgnoresTheCursorAndComesBackDown()
    {
        var rng = new Random(3);
        var c = new Creature(world, new EdgeWorld.Spot(0, 300));
        Assert.True(c.TakeOff() && c.IsPlaying && !c.IsAtLeisure);
        c.Carry(new Pt(400, 400), 0.5, "jump");
        Assert.True(c.Position == new Pt(400, 400) && c.Rotation == 0.5 && c.Animation == "jump");
        var fled = c.Update(0.1, new Pt(400, 400), false, rng);
        Assert.True(!fled && c.IsPlaying, "the cursor does not startle a player");
        Assert.False(c.PickUp(evenAwake: true), "nor can it be picked up mid-game");
        c.Startle(rng);
        Assert.True(c.IsPlaying);
        c.TouchDown();
        Assert.True(c.IsJumping, "dropped back to the nearest edge");
        for (int i = 0; i < 40; i++) c.Update(0.05, null, false, rng);
        Assert.True(!c.IsPlaying && !c.IsJumping);
        // Standing on the edge already, it just stands a moment.
        var standing = new Creature(world, new EdgeWorld.Spot(0, 300));
        standing.TakeOff();
        standing.TouchDown(2);
        Assert.Equal(new Creature.Mode.Idle(2), standing.CurrentMode);
        var asleep = new Creature(world, new EdgeWorld.Spot(0, 300));
        asleep.Settle();
        Assert.False(asleep.TakeOff(), "a sleeper does not play");
    }

    [Fact]
    public void RunningCanBeSteeredEveryFrameWithoutLosingItsStride()
    {
        var rng = new Random(4);
        var c = new Creature(world, new EdgeWorld.Spot(0, 300));
        c.Run(900, 2);
        c.Update(0.2, null, false, rng);
        var stride = c.AnimationTime;
        c.Run(950, 2);
        Assert.True(c.IsRunning && c.AnimationTime == stride);
        c.StandStill(3);
        Assert.Equal(new Creature.Mode.Idle(3), c.CurrentMode);
    }

    // Words

    /// <summary>Every character of every shipped species, and Blocky's built-in cast.</summary>
    private static List<string> Shipped()
    {
        var names = Banter.DefaultCharacters.Select(c => c.Name).ToList();
        foreach (var file in Directory.GetFiles(Path.Combine(Root, "Sources/Ledgelings/Resources/sprites"), "*.json"))
        {
            using var doc = System.Text.Json.JsonDocument.Parse(File.ReadAllText(file));
            if (doc.RootElement.TryGetProperty("cast", out var cast))
                names.AddRange(cast.EnumerateArray().Select(c => c.GetProperty("name").GetString()!));
        }
        return names;
    }

    [Fact]
    public void EveryCharacterHasALineForEveryGameAndTwoForTheEndInEveryLanguage()
    {
        var swift = File.ReadAllText(Path.Combine(Root, "Sources/LedgelingsCore/Plays+Lines.swift"));
        var names = Shipped();
        Assert.Equal(27, names.Count);
        foreach (var language in Languages.All)
        {
            var start = Plays.StartLinesIn(language);
            var done = Plays.DoneLinesIn(language);
            foreach (var name in names)
            {
                foreach (var kind in Plays.AllKinds) Assert.False(string.IsNullOrEmpty(start[name][kind.Raw()]), $"{name} {kind} {language}");
                Assert.Equal(2, done[name].Length);
                if (language == Language.English)
                    foreach (var line in start[name].Values.Concat(done[name])) Assert.Contains("\"" + line + "\"", swift);    // word for word
            }
            foreach (var kind in Plays.AllKinds) Assert.True(Plays.StartAnyoneIn(language).ContainsKey(kind.Raw()));
            // {other} only where English has it, and in every tag line: it names the one who is "it".
            foreach (var (name, lines) in start)
                foreach (var (kind, line) in lines)
                {
                    var english = Plays.EnglishStartLines[name][kind];
                    Assert.True(line.Contains("{other}") == english.Contains("{other}"), $"{name} {kind} {language}");
                    Assert.True(kind != "tag" || line.Contains("{other}"), $"{name} {language}");
                }
        }
        Assert.NotEqual(Plays.DoneLinesIn(Language.English)["Zed"], Plays.DoneLinesIn(Language.Russian)["Zed"]);   // from ru.json
        Languages.With(Language.English, () =>
        {
            Assert.Contains("Zed!", Plays.StartLine("Pip", Plays.Kind.Tag, "Zed"));
            Assert.Equal(Plays.EnglishStartAnyone["rope"], Plays.StartLine("Nobody Made", Plays.Kind.Rope, ""));
            Assert.Contains(Plays.DoneLine("Nobody Made", new Random(5)), Plays.EnglishDoneAnyone);
        });
        foreach (var p in Plays.Placeholders.Where(p => p != "others"))
        {
            Assert.Contains("{" + p + "}", Plays.EnglishLinePrompt);
            Assert.Contains("{" + p + "}", Shared.PromptIn(Language.Russian, "play", ""));
        }
        Assert.NotEqual(Plays.EnglishLineSystemPrompt, Shared.PromptIn(Language.Russian, "playSystem", Plays.EnglishLineSystemPrompt));
    }

    [Fact]
    public void AGameIsAMomentOfTheirStory()
    {
        var book = new Bonds.Book();
        var now = DateTime.UtcNow;
        book.Note("Blocky", "Pip", new Bonds.Moment(now, Bonds.MomentKind.Play, "Pip", "tag"));
        var bond = book.Bond("Blocky", "Pip")!;
        Assert.Equal(1, bond.Tally["play"]);
        Languages.With(Language.English, () =>
        {
            Assert.Equal("Pip and Blocky played: a game of catch me if you can", Bonds.Describe(bond.Moments[0], bond.Names));
            Assert.Equal("1 game", Bonds.Tallied(bond.Tally));
            var plot = Bonds.BuiltInPlot(bond, now, new Random(6)).Plot;
            Assert.Contains("a game of catch me if you can", plot);                  // the next story grows from it
        });
    }

    [Fact]
    public void WhatTheModelsLinesCostIsCountedUnderPlays()
    {
        var records = new[] { new Spend.Record(DateTime.UtcNow, "OpenRouter", "m", new Spend.Usage(120, 20, 0.0004), Spend.Purpose.Plays) };
        var s = Spend.Summarise(records, DateTime.UtcNow);
        Languages.With(Language.English, () => Assert.Equal(0.0004, s.ByPurpose.First(p => p.Purpose == "Plays").Total.Cost));
    }
}

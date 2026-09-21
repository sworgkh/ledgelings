namespace Ledgelings.Core.Tests;

/// <summary>Seeds for the parameterised tests: every integer from <c>from</c> to <c>to</c> inclusive.</summary>
public static class Seeds
{
    public static IEnumerable<object[]> Range(int from, int to) =>
        Enumerable.Range(from, to - from + 1).Select(i => new object[] { i });
}

public class CreatureTests
{
    readonly EdgeWorld world = new(new[] { new Rect(0, 0, 1020, 620) }, 10);
    EdgeLoop Loop => world.Loops[0];
    Creature CreatureAt(double t) => new(world, new EdgeWorld.Spot(0, t));

    static void Run(Creature creature, double seconds, Random rng, Pt? cursor = null, bool night = false, Action<Creature>? each = null)
    {
        for (int i = 0; i < (int)(seconds * 30); i++)
        {
            creature.Update(1.0 / 30, cursor, night, rng);
            each?.Invoke(creature);
        }
    }

    [Fact]
    public void WalksAlongTheEdgeAtItsSpeed()
    {
        var rng = new Random(1);
        var c = CreatureAt(100);
        Run(c, 1, rng);
        Assert.True(Math.Abs(c.T - (100 + c.Settings.WalkSpeed)) < 0.01);
        Assert.Equal(10, c.Position.Y);
        Assert.Equal("walk", c.Animation);
    }

    [Fact]
    public void TurnsTheCornerOntoTheNextSide()
    {
        var rng = new Random(1);
        var c = CreatureAt(990);
        Run(c, 1.5, rng);
        Assert.Equal(1, c.Segment);
        Assert.Equal(1010, c.Position.X);
        Assert.True(Math.Abs(c.Rotation - Math.PI / 2) < 0.0001);
    }

    [Fact]
    public void BlinksOnItsOwnAndReopens()
    {
        var rng = new Random(7);
        var c = CreatureAt(100);
        var seen = new HashSet<Eyes>();
        Run(c, 12, rng, each: x => seen.Add(x.Eyes));
        Assert.True(seen.SetEquals(new[] { Eyes.Open, Eyes.Half, Eyes.Closed }));
    }

    [Fact]
    public void ADistantCursorIsIgnored()
    {
        var rng = new Random(3);
        var c = CreatureAt(100);
        Run(c, 2, rng, cursor: new Pt(500, 400), each: x => Assert.False(x.IsJumping));
    }

    [Theory]
    [MemberData(nameof(Seeds.Range), 1, 40, MemberType = typeof(Seeds))]
    public void ANearCursorMakesItJumpToADifferentSide(int seed)
    {
        var rng = new Random(seed);
        var c = CreatureAt(seed * 79);
        var before = c.Segment;
        c.Update(1.0 / 30, c.Position, false, rng);
        Assert.True(c.IsJumping);
        Assert.Equal("jump", c.Animation);
        Run(c, 1.2, rng);
        Assert.False(c.IsJumping);
        Assert.NotEqual(before, c.Segment);
        Assert.Equal(Loop.Point(c.T), c.Position);
        Assert.True(Math.Abs(Creature.ShortestArc(c.Rotation, c.RestingRotation)) < 0.0001);
    }

    [Fact]
    public void SquashesOnLandingThenWalksAgain()
    {
        var rng = new Random(5);
        var c = CreatureAt(100);
        c.Startle(rng);
        var animations = new List<string>();
        Run(c, 1.5, rng, each: x => { if (animations.Count == 0 || animations[^1] != x.Animation) animations.Add(x.Animation); });
        Assert.Equal(new[] { "jump", "land", "walk" }, animations);
    }

    [Fact]
    public void StaysInsideTheScreenWhileJumping()
    {
        var rng = new Random(11);
        var c = CreatureAt(100);
        for (int i = 0; i < 25; i++)
        {
            c.Startle(rng);
            Run(c, 1.2, rng, each: x => Assert.True(new Rect(9.5, 9.5, 1001, 601).Contains(x.Position)));
        }
    }

    [Fact]
    public void IsNotCatchableMidAir()
    {
        var rng = new Random(2);
        var c = CreatureAt(100);
        c.Startle(rng);
        var first = Assert.IsType<Creature.Mode.Jumping>(c.CurrentMode);
        c.Update(1.0 / 30, c.Position, false, rng);
        var second = Assert.IsType<Creature.Mode.Jumping>(c.CurrentMode);
        Assert.Equal(first.Jump.To, second.Jump.To);
    }

    [Fact]
    public void SurvivesAMonitorBeingUnplugged()
    {
        var rng = new Random(9);
        var two = new EdgeWorld(new[] { new Rect(0, 0, 1000, 600), new Rect(1000, 0, 1000, 600) }, 10);
        var c = new Creature(two, two.Nearest(new Pt(1700, 10)));
        c.Startle(rng);
        var one = new EdgeWorld(new[] { new Rect(0, 0, 1000, 600) }, 10);
        c.Rehome(one);
        Assert.False(c.IsJumping);
        Assert.Equal(one.Point(c.Spot), c.Position);
        Assert.True(new Rect(10, 10, 980, 580).Contains(c.Position) || c.Position.X == 990);
    }

    [Fact]
    public void WalksFromOneMonitorOntoTheNext()
    {
        var rng = new Random(4);
        var two = new EdgeWorld(new[] { new Rect(0, 0, 1000, 600), new Rect(1000, 0, 1000, 600) }, 10);
        var c = new Creature(two, two.Nearest(new Pt(980, 10)));
        c.Settings.WalkSpell = (100, 100);
        c.Rehome(two);
        Run(c, 2, rng);
        Assert.True(c.Position.X > 1000);          // crossed the seam without noticing it
        Assert.Equal(10, c.Position.Y);
    }

    [Theory]
    [MemberData(nameof(Seeds.Range), 1, 20, MemberType = typeof(Seeds))]
    public void JumpsCanLandOnAnotherMonitor(int seed)
    {
        var rng = new Random(seed);
        var apart = new EdgeWorld(new[] { new Rect(0, 0, 1000, 600), new Rect(1000, 600, 1000, 600) }, 10);
        var c = new Creature(apart);
        var visited = new HashSet<int>();
        for (int i = 0; i < 12; i++)
        {
            c.Startle(rng);
            Run(c, 1.2, rng);
            visited.Add(c.Spot.Loop);
        }
        Assert.True(visited.SetEquals(new[] { 0, 1 }));
    }

    [Fact]
    public void FallsAsleepAtNightWithItsEyesShut()
    {
        var rng = new Random(6);
        var c = CreatureAt(100);
        Run(c, 8, rng, night: true);
        Assert.True(c.IsSleeping);
        Assert.Equal("sleep", c.Animation);
        var where = c.Position;
        Run(c, 20, rng, night: true, each: x => Assert.Equal(Eyes.Closed, x.Eyes));
        Assert.Equal(where, c.Position);
    }

    [Fact]
    public void WakesUpWhenDayBreaks()
    {
        var rng = new Random(6);
        var c = CreatureAt(100);
        Run(c, 8, rng, night: true);
        Run(c, 4, rng, night: false);
        Assert.False(c.IsSleeping);
        Assert.True(c.Animation == "walk" || c.Animation == "idle");
    }

    [Fact]
    public void ASleeperIgnoresTheCursorSoItCanBePickedUp()
    {
        var rng = new Random(8);
        var c = CreatureAt(100);
        Run(c, 8, rng, night: true);
        Run(c, 2, rng, cursor: c.Position, night: true, each: x => Assert.True(x.IsSleeping));
    }

    [Fact]
    public void ShiftClickPutsItToSleepInBroadDaylightAndItStaysAsleep()
    {
        var rng = new Random(8);
        var c = CreatureAt(100);
        c.ToggleNap(rng);
        Assert.True(c.IsSleeping && c.IsNapping);
        Run(c, 30, rng, night: false, each: x => Assert.True(x.IsSleeping));
    }

    [Fact]
    public void ShiftClickingASleeperWakesIt()
    {
        var rng = new Random(8);
        var c = CreatureAt(100);
        c.ToggleNap(rng);
        c.ToggleNap(rng);
        Assert.True(!c.IsSleeping && !c.IsNapping);
        Assert.Equal("walk", c.Animation);
    }

    [Fact]
    public void TheNextDawnEndsANap()
    {
        var rng = new Random(8);
        var c = CreatureAt(100);
        c.ToggleNap(rng);
        Run(c, 3, rng, night: true);
        Run(c, 5, rng, night: false);
        Assert.False(c.IsSleeping);
    }

    [Fact]
    public void AnAwakeCreatureCannotBePickedUp()
    {
        var c = CreatureAt(100);
        var picked = c.PickUp();
        Assert.False(picked);
        Assert.False(c.IsHeld);
    }

    [Fact]
    public void ASleeperCanBeCarriedAndDropsToTheNearestEdgeStillAsleep()
    {
        var rng = new Random(8);
        var c = CreatureAt(100);
        c.ToggleNap(rng);
        var picked = c.PickUp();
        Assert.True(picked);
        c.Drag(new Pt(700, 560));              // near the ceiling, mid-air
        Run(c, 1, rng, cursor: c.Position, each: held =>
        {
            Assert.True(held.IsHeld);
            Assert.Equal(new Pt(700, 560), held.Position);
            Assert.Equal(Eyes.Closed, held.Eyes);
        });
        c.Drop();
        Run(c, 1.5, rng, each: falling =>
        {
            Assert.True(falling.LooksAsleep);
            Assert.Equal(Eyes.Closed, falling.Eyes);
        });
        Assert.True(c.IsSleeping && !c.IsHeld);
        Assert.Equal(new Pt(700, 610), c.Position);   // straight up onto the ceiling
        Assert.True(Math.Abs(c.Rotation - Math.PI) < 0.0001);
        Run(c, 10, rng, night: false, each: x => Assert.True(x.IsSleeping));   // still a nap
    }

    [Fact]
    public void ACarriedSleeperCanBeDroppedOnAnotherMonitor()
    {
        var rng = new Random(8);
        var two = new EdgeWorld(new[] { new Rect(0, 0, 1000, 600), new Rect(1000, 0, 1000, 600) }, 10);
        var c = new Creature(two, two.Nearest(new Pt(200, 10)));
        c.ToggleNap(rng);
        c.PickUp();
        c.Drag(new Pt(1960, 300));
        c.Drop();
        Run(c, 1.5, rng);
        Assert.Equal(new Pt(1990, 300), c.Position);
        Assert.True(c.IsSleeping);
    }

    [Fact]
    public void ShortestArcGoesTheShortWayRound()
    {
        Assert.True(Math.Abs(Creature.ShortestArc(3 * Math.PI / 2, 0) - Math.PI / 2) < 1e-9);
        Assert.True(Math.Abs(Creature.ShortestArc(0, 3 * Math.PI / 2) + Math.PI / 2) < 1e-9);
    }
}

public class MeetingBehaviourTests
{
    readonly EdgeWorld world = new(new[] { new Rect(0, 0, 1020, 620) }, 10);
    Creature CreatureAt(double t) => new(world, new EdgeWorld.Spot(0, t));

    static void Run(Creature creature, double seconds, Random rng, Pt? cursor = null)
    {
        for (int i = 0; i < (int)(seconds * 30); i++) creature.Update(1.0 / 30, cursor, false, rng);
    }

    [Fact]
    public void MeetingStopsItFacingTheOtherAndWalkingOnRestoresItsCourse()
    {
        var rng = new Random(3);
        var c = CreatureAt(200);
        Assert.Equal(1, c.Direction);
        c.Meet(-1);
        var stood = c.Position;
        Assert.True(c.IsChatting);
        Assert.True(c.IsMirrored, "turned round to face the one behind it");
        Assert.True(c.Animation == "land", "a little squash on impact");
        Run(c, 1, rng);
        Assert.Equal(stood, c.Position);
        Assert.Equal("idle", c.Animation);
        c.WalkOn(rng);
        Assert.False(c.IsChatting);
        Assert.True(c.Direction == 1, "back on its old course, not the way it turned to chat");
        Run(c, 1, rng);
        Assert.NotEqual(stood, c.Position);
    }

    [Fact]
    public void AChatEndsOnItsOwnAfterItsTimeLimit()
    {
        var rng = new Random(4);
        var c = CreatureAt(200);
        c.Meet(1, 2);
        Run(c, 1.5, rng);
        Assert.True(c.IsChatting);
        Run(c, 1, rng);
        Assert.False(c.IsChatting);
    }

    [Fact]
    public void TheCursorStillStartlesAChatterAway()
    {
        var rng = new Random(5);
        var c = CreatureAt(200);
        c.Meet(1);
        Run(c, 0.2, rng, cursor: c.Position);
        Assert.True(c.IsJumping);
        Assert.False(c.IsChatting);
    }

    [Fact]
    public void ASleeperOrJumperCannotBePulledIntoAChat()
    {
        var rng = new Random(6);
        var c = CreatureAt(200);
        c.ToggleNap(rng);
        c.Meet(1);
        Assert.True(c.IsSleeping && !c.IsChatting);
    }
}

public class CarryingAwakeTests
{
    readonly EdgeWorld world = new(new[] { new Rect(0, 0, 1020, 620) }, 10);
    Creature CreatureAt(double t) => new(world, new EdgeWorld.Spot(0, t));

    static void Run(Creature creature, double seconds, Random rng, Pt? cursor = null)
    {
        for (int i = 0; i < (int)(seconds * 30); i++) creature.Update(1.0 / 30, cursor, false, rng);
    }

    [Fact]
    public void AnAwakeCreatureCanBeCarriedWhenAllowedAndLandsAwake()
    {
        var rng = new Random(11);
        var c = CreatureAt(100);
        var refused = c.PickUp();
        Assert.False(refused);
        var taken = c.PickUp(evenAwake: true);
        Assert.True(taken);
        Assert.True(c.IsHeld && !c.LooksAsleep && !c.IsSleeping);
        Assert.True(c.Animation == "idle", "it does not pretend to sleep in your hand");
        c.Drag(new Pt(500, 300));
        c.Drop();
        Run(c, 2, rng);
        Assert.True(!c.IsSleeping && !c.IsJumping);
        Assert.True(c.Animation == "walk" || c.Animation == "idle");
    }

    [Fact]
    public void ACarriedSleeperStillLandsAsleep()
    {
        var rng = new Random(12);
        var c = CreatureAt(100);
        c.ToggleNap(rng);
        var taken = c.PickUp(evenAwake: true);
        Assert.True(taken);
        Assert.True(c.LooksAsleep);
        c.Drag(new Pt(500, 300));
        c.Drop();
        Run(c, 2, rng);
        Assert.True(c.IsSleeping);
    }

    [Fact]
    public void ACarriedAwakeCreatureIsNotStartledByTheCursorOnIt()
    {
        var rng = new Random(13);
        var c = CreatureAt(100);
        c.PickUp(evenAwake: true);
        Run(c, 0.5, rng, cursor: c.Position);
        Assert.True(c.IsHeld);
    }
}

public class GoingHomeTests
{
    readonly EdgeWorld world = new(new[] { new Rect(0, 0, 1020, 620) }, 10);
    EdgeLoop Loop => world.Loops[0];
    Creature CreatureAt(double t) => new(world, new EdgeWorld.Spot(0, t));

    static void Run(Creature creature, double seconds, Random rng, bool night = false)
    {
        for (int i = 0; i < (int)(seconds * 30); i++) creature.Update(1.0 / 30, null, night, rng);
    }

    [Fact]
    public void RunsHomeTheShortWayRoundAtTwoAndAHalfTimesWalkingSpeed()
    {
        var rng = new Random(21);
        var c = CreatureAt(100);
        c.Run(60);                              // just behind it: turn round
        Assert.True(c.IsRunning && c.Direction == -1);
        Run(c, 0.2, rng);
        Assert.True(Math.Abs((100 - c.T) - 55 * 2.5 * 0.2) < 1);
        Run(c, 1, rng);
        Assert.True(c.HasArrived && c.T == 60);
        Assert.Equal("idle", c.Animation);
    }

    [Fact]
    public void RunningWrapsAroundTheLoopEndIfThatIsShorter()
    {
        var rng = new Random(22);
        var c = CreatureAt(5);
        c.Run(Loop.Length - 5);                 // 10 units back across the seam, not a lap forward
        Assert.Equal(-1, c.Direction);
        Run(c, 0.5, rng);
        Assert.True(c.HasArrived);
    }

    [Fact]
    public void ASleeperWakesToRunAndNightDoesNotStopIt()
    {
        var rng = new Random(23);
        var c = CreatureAt(100);
        c.ToggleNap(rng);
        c.Run(300);
        Assert.True(c.IsRunning && !c.IsSleeping);
        Run(c, 1, rng, night: true);
        Assert.True(c.IsRunning || c.HasArrived);
        Assert.False(c.IsSleeping);
    }

    [Fact]
    public void LeapsStraightToAGivenSpotAndLandsThere()
    {
        var rng = new Random(24);
        var c = CreatureAt(100);
        var door = new EdgeWorld.Spot(0, 1500);
        c.Leap(door);
        Assert.True(c.IsJumping);
        Run(c, 1.5, rng);
        Assert.False(c.IsJumping);
        Assert.True(Math.Abs(c.T - 1500) < 0.001);
    }

    [Fact]
    public void EmergingPutsItAtTheDoorWalkingTheGivenWay()
    {
        var rng = new Random(25);
        var c = CreatureAt(100);
        c.Emerge(new EdgeWorld.Spot(0, 400), -1, rng);
        Assert.True(c.T == 400 && c.Direction == -1 && c.Animation == "walk" && !c.HasArrived);
        Run(c, 0.5, rng);
        Assert.True(c.T < 400);
    }
}

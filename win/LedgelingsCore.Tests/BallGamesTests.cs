namespace Ledgelings.Core.Tests;

/// <summary>Soccer and baseball (SPEC §7.10, Ball games): who plays on which side, where the pitch and the bases
/// go, goals, throw-ins, home runs, and whole games played to the end. The Mac's BallGamesTests; the random
/// numbers differ, so the assertions are about behaviour.</summary>
public class BallGamesTests
{
    private static readonly Rect Screen = new(0, 0, 1440, 900);
    private const double Inset = 25;
    private readonly EdgeWorld world = new(new[] { Screen }, Inset);
    /// <summary>Two monitors: a wide one, raised, and a narrower, taller one to its right whose floor is lower.</summary>
    private static readonly EdgeWorld Stepped = new(new[] { new Rect(0, 300, 1600, 900), new Rect(1600, 0, 800, 1300) }, 25);

    // Who plays, on which side

    [Fact]
    public void TheLineupFollowsHowManyThereAre()
    {
        Assert.True(Plays.SoccerLineup(1) == Plays.Lineup.Solo && Plays.SoccerLineup(2) == Plays.Lineup.Duel);
        Assert.Equal(Plays.Lineup.Keeper, Plays.SoccerLineup(3));                 // three play one goal
        Assert.True(Plays.SoccerLineup(4) == Plays.Lineup.Teams && Plays.SoccerLineup(7) == Plays.Lineup.Teams);
        Assert.True(Plays.BaseballLineup(1) == Plays.Lineup.Solo && Plays.BaseballLineup(2) == Plays.Lineup.Duel);
        Assert.True(Plays.BaseballLineup(3) == Plays.Lineup.Rotation && Plays.BaseballLineup(5) == Plays.Lineup.Rotation);
        Assert.Equal(Plays.Lineup.Teams, Plays.BaseballLineup(6));
    }

    [Fact]
    public void BestFriendsEndUpOnTheSameSide()
    {
        // 0 & 3 are best friends, so are 1 & 2: the split keeps both pairs together.
        static double Close(int a, int b) => (Math.Min(a, b), Math.Max(a, b)) is (0, 3) or (1, 2) ? 1 : 0.05;
        var four = Plays.Split(new[] { 0, 1, 2, 3 }, Close);
        Assert.True(four[0].ToHashSet().SetEquals(new[] { 0, 3 }) && four[1].ToHashSet().SetEquals(new[] { 1, 2 }));
        var six = Plays.Split(new[] { 0, 1, 2, 3, 4, 5 }, Close);
        Assert.True(six[0].Length == 3 && six[1].Length == 3, "even sides");
        Assert.True(six.Any(s => s.Contains(0) && s.Contains(3)) && six.Any(s => s.Contains(1) && s.Contains(2)));
        var five = Plays.Split(new[] { 0, 1, 2, 3, 4 }, Close);
        Assert.True(five[0].Length == 3 && five[1].Length == 2 && five[0].Contains(0), "the starter's side the bigger");
        // From six a side has a keeper: the one with fewest friends there.
        Assert.Equal(4, Plays.Keeper(new[] { 0, 3, 4 }, Close));
    }

    [Fact]
    public void FriendsJoinFirstUpToTheMost()
    {
        var crowd = new List<(int Index, double Closeness)> { (1, 0.1), (2, 0.9), (3, 0.5), (4, 0) };
        Assert.Equal(new[] { 0, 2, 3 }, Plays.Joining(0, crowd, 3));
        Assert.Equal(new[] { 0 }, Plays.Joining(0, crowd, 1));                   // alone
        var rng = new Random(2);
        var picked = new HashSet<Plays.Kind>();
        var most = new Dictionary<Plays.Kind, int> { [Plays.Kind.Soccer] = 4, [Plays.Kind.Baseball] = 2 };
        for (int n = 0; n < 200; n++)
        {
            if (Plays.ChooseTeamGame(0, crowd, Plays.AllKinds.ToHashSet(), most, rng) is not { } game) continue;
            picked.Add(game.Kind);
            Assert.Equal(game.Kind == Plays.Kind.Soccer ? 4 : 2, game.Players.Length);
        }
        Assert.True(picked.SetEquals(new[] { Plays.Kind.Soccer, Plays.Kind.Baseball }));
        Assert.Null(Plays.ChooseTeamGame(0, crowd, new HashSet<Plays.Kind> { Plays.Kind.Tag, Plays.Kind.Rope }, new Dictionary<Plays.Kind, int>(), rng));
        Assert.True(Plays.TeamChance(0) < Plays.TeamChance(4), "a crowd plays together more");
        // The old games never pick a team game for one or two.
        for (int n = 0; n < 100; n++)
        {
            var game = Plays.Choose(0, new List<(int, double)> { (1, 1) }, Plays.AllKinds.ToHashSet(), rng);
            Assert.True(game is { } g && !g.Kind.IsTeamGame());
        }
    }

    // Soccer

    [Fact]
    public void ThePitchIsTheWidestFloor()
    {
        // A wide monitor standing higher than a narrower one beside it: the wide one's floor wins.
        var pitch = Plays.Pitch.Choose(Stepped, 25)!;
        Assert.True(pitch.FloorY == 300 && pitch.From == 0 && pitch.To == 1600, $"{pitch}");
        Assert.True(pitch.WallLeft && !pitch.WallRight, "the floor steps down onto the next monitor: no wall, the ball falls off");
        var one = Plays.Pitch.Choose(world, Inset)!;
        Assert.True(one.From == 0 && one.To == 1440 && one.WallLeft && one.WallRight);
        var tiny = new EdgeWorld(new[] { new Rect(0, 0, 250, 400) }, 25);
        Assert.Null(Plays.Pitch.Choose(tiny, 25));                                // too short to play on
    }

    private (Plays.Soccer, Random) Match(int[] ids, int[][]? teams = null, HashSet<int>? keepers = null, int goals = 3,
                                         double length = 120, EdgeWorld? w = null, int seed = 1)
    {
        var rng = new Random(seed);
        var pitch = Plays.Pitch.Choose(w ?? world, Inset)!;
        var s = new Plays.Soccer(ids, teams, keepers ?? new HashSet<int>(), ids.ToDictionary(i => i, _ => 25.0), null, pitch, 2.5,
                                 goals, length, rng);
        return (s, rng);
    }

    private static List<Plays.Soccer.Event> Play(Plays.Soccer s, Random rng, double seconds = 400)
    {
        var events = new List<Plays.Soccer.Event>();
        for (double t = 0; !s.IsFinished && t < seconds; t += 1.0 / 60) events.AddRange(s.Update(1.0 / 60, rng));
        return events;
    }

    [Fact]
    public void EachCountHasItsGoals()
    {
        Assert.Single(Match(new[] { 0 }).Item1.Goals);                            // one alone shoots at one goal
        Assert.Equal(Plays.Soccer.Phase.Juggling, Match(new[] { 0 }).Item1.CurrentPhase);   // and starts with keepy-uppy
        var duel = Match(new[] { 0, 1 }).Item1;
        Assert.True(duel.Goals.Count == 2 && duel.Players.Select(p => p.Team).ToHashSet().SetEquals(new[] { 0, 1 }));
        var three = Match(new[] { 0, 1, 2 }).Item1;
        Assert.Single(three.Goals);
        Assert.Equal(new[] { 2 }, three.Players.Where(p => p.IsKeeper).Select(p => p.Index));   // one goal, one keeper, two attackers
        var four = Match(new[] { 0, 1, 2, 3 }, new[] { new[] { 0, 3 }, new[] { 1, 2 } }).Item1;
        Assert.True(four.Goals.Count == 2 && !four.Players.Any(p => p.IsKeeper), "no keepers under six");
        var six = Match(new[] { 0, 1, 2, 3, 4, 5 }, new[] { new[] { 0, 1, 2 }, new[] { 3, 4, 5 } }, new HashSet<int> { 2, 5 }).Item1;
        Assert.True(six.Players.Where(p => p.IsKeeper).Select(p => p.Index).ToHashSet().SetEquals(new[] { 2, 5 }));
        Assert.True(six.PlayerOf(2)?.Team == 0 && six.PlayerOf(5)?.Team == 1);
    }

    [Fact]
    public void AMatchIsPlayedToTheEnd()
    {
        foreach (var (ids, seed) in new[] { (new[] { 0 }, 1), (new[] { 0, 1 }, 2), (new[] { 0, 1, 2 }, 3), (new[] { 0, 1, 2, 3, 4 }, 4) })
        {
            var teams = ids.Length >= 4 ? Plays.Split(ids, (_, _) => 0) : null;
            var (s, rng) = Match(ids, teams, goals: 2, length: 90, seed: seed);
            var events = Play(s, rng);
            Assert.True(s.IsFinished, $"{ids.Length} players: the match ends");
            Assert.Contains(events, e => e is Plays.Soccer.Event.Over);
            var goals = events.Count(e => e is Plays.Soccer.Event.Goal);
            Assert.Equal(s.GoalsBy.Values.Sum(), goals);                           // every goal counted
            Assert.True(goals >= 1 || s.Clock >= 90, $"{ids.Length} players: a goal, or the time ran out ({s.Clock})");
            if (ids.Length == 1) Assert.Contains(events, e => e is Plays.Soccer.Event.Touches);   // keepy-uppy first
            if (ids.Length == 3 && goals > 0) Assert.Contains(events, e => e is Plays.Soccer.Event.KeeperNow);   // the keeper changes after a goal
            foreach (var p in s.Players) Assert.True(s.Pitch.Covers(p.X), "nobody leaves the pitch");
        }
    }

    [Fact]
    public void AGoalIsScoredOnlyUnderTheBar()
    {
        var (s, rng) = Match(new[] { 0, 1 }, goals: 3);
        s.CurrentPhase = Plays.Soccer.Phase.Play;
        var right = s.Goals.First(g => g.Side > 0);
        // Low, into the right goal: team 0 (who attacks right) scores, the scorer credited.
        s.LastTouch = 0;
        s.TheBall.Position = new Pt(right.X - 6, s.Pitch.FloorY + s.TheBall.Radius + 4);
        s.TheBall.Velocity = new Vec(600, 0);
        var events = s.Update(0.05, rng);
        Assert.Contains(new Plays.Soccer.Event.Goal(0, "0 1 : 0 1"), events);
        Assert.True(s.TeamGoals.SequenceEqual(new[] { 1, 0 }) && s.GoalsBy[0] == 1 && s.CurrentPhase == Plays.Soccer.Phase.Goal);
        Assert.Equal("Blocky 1 : 0 Zed", s.Board(i => new[] { "Blocky", "Zed" }[i]));
        // Over the bar: no goal.
        var (high, rng2) = Match(new[] { 0, 1 }, goals: 3);
        high.CurrentPhase = Plays.Soccer.Phase.Play;
        high.LastTouch = 0;
        high.TheBall.Position = new Pt(right.X - 6, high.Pitch.FloorY + right.Height + 30);
        high.TheBall.Velocity = new Vec(600, 0);
        high.Update(0.05, rng2);
        Assert.Equal(new[] { 0, 0 }, high.TeamGoals);
    }

    [Fact]
    public void OffTheEndWithNoWallItIsBroughtBackWithAThrowIn()
    {
        var (s, rng) = Match(new[] { 0, 1 }, w: Stepped);
        s.CurrentPhase = Plays.Soccer.Phase.Play;
        s.LastTouch = 1;
        // Over the bar at the right, where the floor just ends.
        s.TheBall.Position = new Pt(s.Pitch.To - 8, s.Pitch.FloorY + 200);
        s.TheBall.Velocity = new Vec(500, 0);
        var events = new List<Plays.Soccer.Event>();
        for (int n = 0; n < 600; n++)
        {
            events.AddRange(s.Update(1.0 / 60, rng));
            if (events.Any(e => e is Plays.Soccer.Event.ThrowIn)) break;
        }
        Assert.Contains(new Plays.Soccer.Event.Out(1), events);
        Assert.Contains(new Plays.Soccer.Event.ThrowIn(0), events);               // the other side brings it back
        Assert.True(s.CurrentPhase == Plays.Soccer.Phase.Play && s.Pitch.Covers(s.TheBall.Position.X));
        // With a wall, the same ball bounces back in.
        var (walled, rng2) = Match(new[] { 0, 1 });
        walled.CurrentPhase = Plays.Soccer.Phase.Play;
        walled.TheBall.Position = new Pt(walled.Pitch.To - 8, walled.Pitch.FloorY + 200);
        walled.TheBall.Velocity = new Vec(500, 0);
        var more = new List<Plays.Soccer.Event>();
        for (int n = 0; n < 30; n++) more.AddRange(walled.Update(1.0 / 60, rng2));
        Assert.True(!more.Any(e => e is Plays.Soccer.Event.Out) && walled.TheBall.Velocity.Dx < 0, "off the wall");
    }

    [Fact]
    public void TheTimeRunsOut()
    {
        var (s, rng) = Match(new[] { 0, 1, 2, 3 }, new[] { new[] { 0, 1 }, new[] { 2, 3 } }, goals: 99, length: 30);
        Play(s, rng);
        Assert.True(s.IsFinished && s.Clock >= 30 && s.Clock < 45, $"{s.Clock}");
    }

    // Baseball

    [Fact]
    public void TheBasesGoOnThreeOtherEdgesRoundTheScreen()
    {
        var home = world.Nearest(new Pt(300, 25));
        var field = Plays.Field.Choose(world, Inset, home)!;
        Assert.Equal(0, field.Home.Edge.Y);                                       // home on the batter's floor
        Assert.True(field.Mound.Edge.Y == 0 && Math.Abs(field.Mound.Edge.X - field.Home.Edge.X) > 300, "the pitcher on the same floor, away from home");
        // First on the right wall, second on the ceiling, third on the left wall: a diamond the size of the screen.
        var b = field.Bases.Select(p => p.Edge).ToList();
        Assert.True(b[0].X == 1440 && b[1].Y == 900 && b[2].X == 0, string.Join(" ", b));
        // A batter on a wall: home goes on the floor.
        var onWall = Plays.Field.Choose(world, Inset, world.Nearest(new Pt(1415, 400)))!;
        Assert.Equal(0, onWall.Home.Edge.Y);
        // Two monitors: still three other edges, as far apart as can be.
        var two = new EdgeWorld(new[] { new Rect(0, 0, 1600, 900), new Rect(1600, 200, 1000, 1100) }, 25);
        var wide = Plays.Field.Choose(two, 25, two.Nearest(new Pt(400, 25)))!;
        Assert.True(wide.Bases.All(p => p.Edge.DistanceTo(wide.Home.Edge) > 500), string.Join(" ", wide.Bases.Select(p => p.Edge)));
    }

    private (Plays.Baseball, Random) Game(int[] ids, int innings = 1, int seed = 1, Func<int, int, double>? closeness = null)
    {
        closeness ??= (_, _) => 0;
        var home = world.Nearest(new Pt(300, 25));
        var field = Plays.Field.Choose(world, Inset, home)!;
        var starts = ids.ToDictionary(i => i, _ => field.Home);
        var teams = ids.Length >= 6 ? Plays.Split(ids, closeness) : null;
        var g = new Plays.Baseball(ids, teams, starts, ids.ToDictionary(i => i, _ => 25.0), field, innings, closeness: closeness);
        return (g, new Random(seed));
    }

    private static List<Plays.Baseball.Event> Play(Plays.Baseball g, Random rng, double seconds = 1200)
    {
        var events = new List<Plays.Baseball.Event>();
        for (double t = 0; !g.IsFinished && t < seconds; t += 1.0 / 60) events.AddRange(g.Update(1.0 / 60, rng));
        return events;
    }

    [Fact]
    public void AGameIsPlayedToTheEndForEveryCount()
    {
        foreach (var (ids, seed) in new[] { (new[] { 0 }, 1), (new[] { 0, 1 }, 2), (new[] { 0, 1, 2 }, 3), (new[] { 0, 1, 2, 3, 4 }, 4), (new[] { 0, 1, 2, 3, 4, 5 }, 5) })
        {
            var (g, rng) = Game(ids, seed: seed);
            var events = Play(g, rng);
            Assert.True(g.IsFinished, $"{ids.Length} players: the game ends");
            var runs = events.Count(e => e is Plays.Baseball.Event.Scored);
            Assert.True(runs == g.RunsBy.Values.Sum() && runs == g.SideRuns.Sum(), "every run counted");
            if (ids.Length == 1)
            {
                Assert.True(g.Swings == g.PracticeSwings && !events.Any(e => e is Plays.Baseball.Event.Pitch), "alone: practice swings, no pitcher");
            }
            else
            {
                Assert.Contains(events, e => e is Plays.Baseball.Event.Pitch);
                Assert.Contains(events, e => e is Plays.Baseball.Event.Out);
                Assert.Contains(events, e => e is Plays.Baseball.Event.SidesChange);
            }
            foreach (var a in g.Actors) Assert.False(a.IsHopping, "everyone has landed");
        }
    }

    [Fact]
    public void ThreeStrikesAndYouAreOut()
    {
        var (g, rng) = Game(new[] { 0, 1 });
        var events = new List<Plays.Baseball.Event>();
        static bool StruckOut(Plays.Baseball.Event e) => e is Plays.Baseball.Event.Out { How: "struck out" };
        for (double t = 0; !events.Any(StruckOut) && t < 600; t += 1.0 / 60) events.AddRange(g.Update(1.0 / 60, rng));
        var out_ = (Plays.Baseball.Event.Out)events.First(StruckOut);
        var strikes = events.OfType<Plays.Baseball.Event.Strike>().Where(s => s.By == out_.By).ToList();
        Assert.Equal(3, strikes.Last().Count);
    }

    [Fact]
    public void AHomeRunGoesOutTheTopAndBringsEveryoneHome()
    {
        // Best of friends pitching: more hits, and more home runs.
        var found = false;
        for (int seed = 1; seed <= 40 && !found; seed++)
        {
            var (g, rng) = Game(new[] { 0, 1, 2 }, innings: 2, seed: seed, closeness: (_, _) => 1);
            for (double t = 0; !g.IsFinished && t < 900 && !found; t += 1.0 / 60)
            {
                foreach (var e in g.Update(1.0 / 60, rng))
                {
                    if (e is not Plays.Baseball.Event.HomeRun { RunsIn: > 1 } hr) continue;
                    var before = g.RunsBy.Values.Sum();
                    Assert.True(g.LastHomeRun is { } exit && exit.Y >= g.Field.Top - 20, "out through the top");
                    for (int n = 0; n < 60 * 8; n++) g.Update(1.0 / 60, rng);
                    Assert.True(g.RunsBy.Values.Sum() >= before + hr.RunsIn, $"{hr.By} and every runner score");
                    found = true;
                    break;
                }
            }
        }
        Assert.True(found, "a home run with someone on base");
    }

    [Fact]
    public void FriendsHitMore()
    {
        int Hits(double c)
        {
            var total = 0;
            for (int seed = 1; seed <= 6; seed++)
            {
                var (g, rng) = Game(new[] { 0, 1 }, innings: 2, seed: seed, closeness: (_, _) => c);
                Play(g, rng);
                total += g.Hits;
            }
            return total;
        }
        Assert.True(Hits(1) > Hits(0));
    }

    [Fact]
    public void TheBoardSaysTheScore()
    {
        Languages.With(Language.English, () =>
        {
            var (g, _) = Game(new[] { 0 });
            g.Hits = 3;
            g.HomeRuns = 1;
            Assert.Equal("Blocky: 3 hits, 1 home run", g.Board(_ => "Blocky"));
            var (two, _) = Game(new[] { 0, 1 });
            two.SideRuns[0] = 2;
            two.SideRuns[1] = 1;
            Assert.Equal("Blocky 2  Zed 1  · inning 1/1, 0 out", two.Board(i => new[] { "Blocky", "Zed" }[i]));
        });
    }
}

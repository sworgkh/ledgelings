using System.Drawing;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Plays: now and then, and more often between close friends, one creature (or a pair) stops walking
/// and plays a game (<see cref="Plays"/>): tag round the edges, a swing on a ninja rope, a parachute jump from
/// the ceiling, a few throws at a hoop on the wall. One game at a time; its players are <c>busy</c> meanwhile,
/// so nothing else (a talk, a tea party, a plane, a grab) starts with them, and a game only starts with
/// creatures that are free and awake. The Mac's <c>Colony+Play</c>.</summary>
public sealed partial class Colony
{
    /// <summary>The game going on, who plays it, and where each part of it is.</summary>
    public sealed class PlaySession
    {
        public enum Stage { Reaching, On, Ending }

        public required Plays.Kind Kind;
        public required int[] Players;
        public required int Serial;
        public Stage Now = Stage.Reaching;
        /// <summary>While ending: when it is let go.</summary>
        public double Until;
        /// <summary>When it began, on the colony's clock; a game that cannot get going gives up.</summary>
        public required double Since;
        public Plays.Tag? Tag;
        public Plays.Rope? Rope;
        public Plays.Chute? Chute;
        public Court? Court;
        public Plays.Pitch? Pitch;
        public Plays.Soccer? Soccer;
        public Plays.Baseball? Baseball;
        public BallGame? BallGame;
        /// <summary>Where the players are going before it starts: leaping to a floor or the ceiling.</summary>
        public Dictionary<int, EdgeWorld.Spot> Reaching = new();
    }

    /// <summary>The hoop on its wall, the ball, and whose throw it is.</summary>
    public sealed class Court
    {
        public enum Step { Walking, WindUp, Throwing, Watching }

        public required Plays.Hoop Hoop;
        public required EdgeWorld.Level Floor;
        /// <summary>The screen's floor and its two ends, for the ball.</summary>
        public required double FloorY;
        public required double From, To;
        public required double Scale;
        public required int ThrowsLeft;
        public int Turn;
        public Step Now = Step.Walking;
        /// <summary>While winding up or throwing: when that step is over.</summary>
        public double StepUntil;
        public Plays.Ball? Ball;
        public double ThrownAt;
        public double? BallGone;
        public double SwishUntil;
        public double Grown;
        public Dictionary<int, int> Made = new();
    }

    private const double ReachTimeout = 6.0;
    private const double EndPause = 0.8;

    /// <summary>The games' props: ball, hoop, parachute, hook, rope, a drop of sweat.</summary>
    private static readonly SpriteAtlas playSheet = SpriteAtlas.Named("play");
    private readonly SpriteAtlas.Frames playFrames = playSheet.MakeFrames();
    private Size PlayCell => playSheet.CellSize;
    /// <summary>The game going on, if any, and when the next one is due.</summary>
    private PlaySession? play;
    public PlaySession? CurrentPlay => play;
    internal double? NextPlayAt { get; set; }
    /// <summary>The "how often" setting the next game was timed with; a change times it afresh.</summary>
    internal double PlayEveryWas { get; set; }
    /// <summary>Counts games, so a model's late line finds whether its game is still on.</summary>
    private int playCount;

    // MARK: When

    /// <summary>Every frame: start a game when one is due, and run the one going on.</summary>
    private void UpdatePlay(double dt)
    {
        if (play is not null) { RunPlay(dt); return; }
        if (!Settings.PlayEnabled || IsNight || hideout.IsActive || CurrentGrab is not null || held is not null) return;
        if (PlayEveryWas != Settings.PlayEveryMinutes || NextPlayAt is null)
        {
            PlayEveryWas = Settings.PlayEveryMinutes;
            NextPlayAt = Elapsed + Plays.Wait(Settings.PlayEveryMinutes, Settings.PlayBondBoost, ClosestPairOnScreen(), rng);
        }
        if (NextPlayAt is not double due || Elapsed < due) return;
        // Nobody free, or nowhere to play: look again in a little while.
        if (!StartPlay(null)) NextPlayAt = Elapsed + 30;
    }

    /// <summary>Awake, on an edge, walking or standing about, and in nothing else.</summary>
    public bool FreeToPlay(int i)
    {
        if (i < 0 || i >= creatures.Count) return false;
        return creatures[i].IsAtLeisure && !busy.Contains(i) && !ExpectsPlane(i) && gifts.Hat(i) is null
            && !gardeners.Contains(i) && !bedTrips.ContainsKey(i) && !letters.Contains(i) && !complaining.Contains(i)
            && !hideout.IsInside(i) && !chats.Any(c => c.Involves(i)) && CurrentGrab?.Index != i && held?.Index != i
            && teaInvite?.Guest != i && teaInvite?.Host != i;
    }

    /// <summary>How close two creatures' characters are, 0...1.</summary>
    private double Closeness(int i, int j) => Plays.Closeness(Bonds.Bond(CharacterFor(i).Name, CharacterFor(j).Name));

    private double ClosestPairOnScreen()
    {
        var best = 0.0;
        for (int i = 0; i < creatures.Count; i++)
            for (int j = i + 1; j < creatures.Count; j++) best = Math.Max(best, Closeness(i, j));
        return best;
    }

    /// <summary>Start a game now: <paramref name="kind"/>, or one chosen for whoever is free (<see cref="Plays.Choose"/>).
    /// The Actions sheet asks for one by kind; tag then takes the closest pair on one outline, basketball the
    /// initiator's closest friend if it has one, and a ball game everyone free, closest friends first, up to its
    /// most players (or <paramref name="count"/>).</summary>
    public bool StartPlay(Plays.Kind? kind, int? chosen = null, int? count = null)
    {
        if (play is not null || hideout.IsActive) return false;
        var free = Enumerable.Range(0, creatures.Count).Where(FreeToPlay).ToList();
        int? first = chosen is int c && free.Contains(c) ? c : free.Count > 0 ? rng.Pick(free) : null;
        if (first is not int initiator) { TalkStatus = L10n.Tr("nobody is free to play"); return false; }
        List<(int Index, double Closeness)> Partners(int i) =>
            free.Where(j => j != i && creatures[j].Spot.Loop == creatures[i].Spot.Loop).Select(j => (j, Closeness(i, j))).ToList();
        var tries = new List<(Plays.Kind Kind, int[] Players)>();
        if (kind is Plays.Kind asked)
        {
            switch (asked)
            {
                case Plays.Kind.Tag:
                {
                    // The closest pair that shares an outline.
                    var pairs = new List<(int I, int J, double C)>();
                    foreach (var i in free.Where(i => chosen is null || i == chosen))
                        foreach (var (j, cl) in Partners(i)) pairs.Add((i, j, cl));
                    if (pairs.Count == 0) { TalkStatus = L10n.Tr("tag needs two free creatures on one screen outline"); return false; }
                    var pair = pairs.MaxBy(p => p.C);
                    tries.Add((Plays.Kind.Tag, chosen is not null || rng.Coin() ? new[] { pair.I, pair.J } : new[] { pair.J, pair.I }));
                    break;
                }
                case Plays.Kind.Basketball:
                {
                    var friends = Partners(initiator).Where(p => p.Closeness >= Plays.FriendsAt / Plays.CloseAt).ToList();
                    tries.Add((Plays.Kind.Basketball, friends.Count > 0 ? new[] { initiator, friends.MaxBy(p => p.Closeness).Index } : new[] { initiator }));
                    break;
                }
                case Plays.Kind.Soccer:
                case Plays.Kind.Baseball:
                    tries.Add((asked, Plays.Joining(initiator, Crowd(initiator),
                        count ?? (Settings.BallGamePlayers.TryGetValue(asked, out var most) ? most : 6))));
                    break;
                default:
                    tries.Add((asked, new[] { initiator }));
                    break;
            }
        }
        else
        {
            // A ball game for everyone free, now and then, if one is due.
            if (Plays.ChooseTeamGame(initiator, Crowd(initiator), BallGamesDue, Settings.BallGamePlayers, rng) is { } team
                && Begin(team.Kind, team.Players))
                return true;
            if (Plays.Choose(initiator, Partners(initiator), Settings.EnabledPlays, rng) is not { } pick) return false;
            tries.Add((pick.Kind, pick.Players));
            // No room for that one here: a game alone that fits instead.
            var others = Plays.AllKinds.ToArray();
            rng.Shuffle(others);
            foreach (var other in others.Where(o => o != pick.Kind && o.CanSolo() && Settings.EnabledPlays.Contains(o)))
                tries.Add((other, new[] { initiator }));
        }
        foreach (var (k, players) in tries) if (Begin(k, players)) return true;
        if (kind is not null) TalkStatus = L10n.Tr("no room to play that here");
        return false;
    }

    // MARK: Starting

    private bool OnFloor(int i) => creatures[i].Loop.Direction(creatures[i].Segment).Dx > 0.5;

    /// <summary>The floor under creature <paramref name="i"/>, in its own world.</summary>
    private EdgeWorld.Level? FloorUnder(int i) => creatures[i].World.Floor(creatures[i].Position);

    private EdgeWorld.Spot SpotOn(EdgeWorld.Level level, double x, int i)
    {
        var w = creatures[i].World;
        var clamped = Math.Min(Math.Max(x, level.From), level.To);
        return new EdgeWorld.Spot(level.Loop, w.Loops[level.Loop].Nearest(new Pt(clamped, level.Y)).T);
    }

    private bool Begin(Plays.Kind kind, int[] players)
    {
        if (!players.All(FreeToPlay)) return false;
        playCount += 1;
        var session = new PlaySession { Kind = kind, Players = players, Serial = playCount, Since = Elapsed };
        switch (kind)
        {
            case Plays.Kind.Tag:
                if (players.Length != 2 || creatures[players[0]].Spot.Loop != creatures[players[1]].Spot.Loop) return false;
                // The one who starts it runs; the other is "it".
                session.Tag = new Plays.Tag(players[1], players[0], Settings.TagSeconds);
                session.Now = PlaySession.Stage.On;
                break;
            case Plays.Kind.Rope:
            {
                var i = players[0];
                if (FloorUnder(i) is not { } floor) return false;
                var x = OnFloor(i) ? creatures[i].Position.X : floor.From + (floor.To - floor.From) * rng.Range(0.25, 0.75);
                var at = SpotOn(floor, x, i);
                if (RopeFor(i, creatures[i].World.Point(at), floor) is null) return false;
                if (!OnFloor(i)) session.Reaching[i] = at;
                break;
            }
            case Plays.Kind.Parachute:
            {
                var i = players[0];
                var w = creatures[i].World;
                var over = w.Ceiling(creatures[i].Position) is { } above ? new[] { above } : Array.Empty<EdgeWorld.Level>();
                var shuffled = w.Ceilings.ToArray();
                rng.Shuffle(shuffled);
                var ceilings = over.Concat(shuffled).Where(level =>
                    level.To - level.From > 120
                    && w.Floor(new Pt((level.From + level.To) / 2, level.Y)) is { } below && level.Y - below.Y > 200).ToList();
                if (ceilings.Count == 0) return false;
                var ceiling = ceilings[0];
                double lo = ceiling.From, hi = ceiling.To;
                var x = Math.Min(Math.Max(creatures[i].Position.X, lo + (hi - lo) * 0.15), hi - (hi - lo) * 0.15);
                if (w.Floor(new Pt(x, ceiling.Y)) is null) return false;
                session.Reaching[i] = SpotOn(ceiling, x, i);
                break;
            }
            case Plays.Kind.Basketball:
            {
                if (CourtFor(players) is not { } court) return false;
                session.Court = court;
                var f = court.Floor;
                foreach (var i in players.Where(i => !(OnFloor(i) && FloorUnder(i)?.Segment == f.Segment && creatures[i].Spot.Loop == f.Loop)))
                    session.Reaching[i] = SpotOn(f, f.From + (f.To - f.From) * rng.Range(0.3, 0.7), i);
                break;
            }
            case Plays.Kind.Soccer:
                if (!BeginSoccer(session)) return false;
                break;
            case Plays.Kind.Baseball:
                if (!BeginBaseball(session)) return false;
                break;
        }
        foreach (var p in players) busy.Add(p);
        foreach (var (i, to) in session.Reaching) creatures[i].Leap(to);
        foreach (var i in players.Where(i => !session.Reaching.ContainsKey(i) && !creatures[i].IsPlaying)) creatures[i].StandStill(double.PositiveInfinity);
        play = session;
        var names = players.Select(p => CharacterFor(p).Name).ToList();
        TalkStatus = names.Count == 2 ? L10n.Tr("%@ and %@: %@", names[0], names[1], kind.Title()) : L10n.Tr("%@: %@", string.Join(", ", names), kind.Title());
        Trace?.Invoke($"play {kind.Raw()} {string.Join(" & ", names)}{(session.Reaching.Count == 0 ? "" : " (getting there)")}");
        if (kind == Plays.Kind.Baseball) StartLine(session);
        else if (session.Reaching.Count == 0) Started();
        return true;
    }

    /// <summary>A rope swing for <paramref name="i"/> from <paramref name="point"/> (its centre on <paramref name="floor"/>), or null when there is no room.</summary>
    private Plays.Rope? RopeFor(int i, Pt point, EdgeWorld.Level floor)
    {
        var w = creatures[i].World;
        var inset = atlas.BodyHalfSize * sizes[i];
        if (w.Ceiling(point) is not { } ceiling) return null;
        var way = point.X < (floor.From + floor.To) / 2 ? 1.0 : -1.0;
        return Plays.Rope.Plan(point, ceiling.Y + inset, floor.From, floor.To, way, inset * 2.5);
    }

    /// <summary>A hoop on a wall at an end of the initiator's floor (or the floor under it), with room to throw from.</summary>
    private Court? CourtFor(int[] players)
    {
        var i = players[0];
        var w = creatures[i].World;
        if (FloorUnder(i) is not { } floor) return null;
        var inset = atlas.BodyHalfSize * sizes[i];
        if (floor.To - floor.From < 260) return null;
        // The wall furthest from it, so it has room to throw.
        var walls = w.Walls(floor);
        if (walls.Count == 0) return null;
        var wall = walls.MaxBy(x => Math.Abs(x.X - creatures[i].Position.X));
        var scale = players.Average(p => sizes[p]);
        var screenFloor = floor.Y - inset;
        var height = Math.Min(Math.Max((wall.Height + inset) * 0.45, 90), 240);
        var hoop = new Plays.Hoop(wall.X + wall.Side * inset, wall.Side, screenFloor, height, scale);
        return new Court
        {
            Hoop = hoop, Floor = floor, FloorY = screenFloor, From = floor.From - inset, To = floor.To + inset,
            Scale = scale, ThrowsLeft = Settings.BasketballThrows * players.Length,
        };
    }

    /// <summary>Everyone is in place: the game begins, and whoever started it says so.</summary>
    private void Started()
    {
        if (play is not PlaySession session) return;
        session.Now = PlaySession.Stage.On;
        var i = session.Players[0];
        switch (session.Kind)
        {
            case Plays.Kind.Rope:
                if (FloorUnder(i) is not { } floor || RopeFor(i, creatures[i].Position, floor) is not { } rope) { EndPlay(false); return; }
                creatures[i].Face(rope.Way);
                creatures[i].TakeOff();
                session.Rope = rope;
                break;
            case Plays.Kind.Parachute:
                if (creatures[i].World.Floor(creatures[i].Position) is not { } below) { EndPlay(false); return; }
                creatures[i].TakeOff();
                session.Chute = new Plays.Chute(creatures[i].Position, below.Y, below.From, below.To, Settings.ParachuteFallSpeed);
                break;
            case Plays.Kind.Soccer:
                if (!StartSoccer(session)) { EndPlay(false); return; }
                break;
        }
        StartLine(session);
    }

    // MARK: Running

    private void RunPlay(double dt)
    {
        if (play is not PlaySession session) return;
        if (hideout.IsActive || !session.Players.All(p => p < creatures.Count)) { EndPlay(false); return; }
        if (session.Now == PlaySession.Stage.Ending)
        {
            if (session.Court is { } court) court.Grown = Math.Max(0, court.Grown - dt / 0.4);
            if (Elapsed >= session.Until) EndPlay(true);
            return;
        }
        if (session.Now == PlaySession.Stage.Reaching)
        {
            if (Elapsed - session.Since > ReachTimeout) { EndPlay(false); return; }
            // Leapt off course (startled, picked up): no game.
            static bool OnTheWay(Creature c) => c.IsJumping || c.HasArrived || c.CurrentMode is Creature.Mode.Landing;
            if (session.Reaching.Keys.Any(k => !OnTheWay(creatures[k]))) { EndPlay(false); return; }
            if (!session.Reaching.Keys.All(k => creatures[k].HasArrived)) return;
            foreach (var i in session.Players) creatures[i].StandStill(double.PositiveInfinity);
            Started();
            return;
        }
        switch (session.Kind)
        {
            case Plays.Kind.Tag: RunTag(session, dt); break;
            case Plays.Kind.Rope: RunRope(session, dt); break;
            case Plays.Kind.Parachute: RunChute(session, dt); break;
            case Plays.Kind.Basketball: RunBasketball(session, dt); break;
            case Plays.Kind.Soccer: RunSoccer(session, dt); break;
            case Plays.Kind.Baseball: RunBaseball(session, dt); break;
        }
    }

    private void RunTag(PlaySession s, double dt)
    {
        if (s.Tag is not { } tag) return;
        int a = s.Players[0], b = s.Players[1];
        // Picked up, startled into a jump, asleep: the game is off.
        if (!new[] { a, b }.All(k => !creatures[k].IsHeld && !creatures[k].IsJumping && !creatures[k].LooksAsleep && !creatures[k].IsChatting))
        {
            EndPlay(false);
            return;
        }
        foreach (var e in tag.Update(dt))
        {
            switch (e)
            {
                case Plays.Tag.Event.Go:
                    Trace?.Invoke($"play tag {CharacterFor(tag.It).Name} is it");
                    break;
                case Plays.Tag.Event.Puffing:
                    foreach (var k in new[] { a, b }) creatures[k].StandStill(Plays.Tag.PuffTime + 1);
                    creatures[a].Face(Facing(a, b));
                    creatures[b].Face(Facing(b, a));
                    Trace?.Invoke($"play tag over after {tag.Touches} touches, both out of breath");
                    break;
                case Plays.Tag.Event.Over:
                    WrapUp(s, tag.It);
                    return;
            }
        }
        if (tag.CurrentPhase != Plays.Tag.Phase.Chase) return;
        int it = tag.It, runner = tag.Runner;
        var loop = creatures[runner].Loop;
        var ahead = loop.Wrap(creatures[it].T - creatures[runner].T);
        var gap = Math.Min(ahead, loop.Length - ahead);
        var away = ahead <= loop.Length / 2 ? -1.0 : 1.0;
        creatures[runner].Run(creatures[runner].T + away * 400, Plays.Tag.FleeSpeed / creatures[runner].Settings.WalkSpeed);
        if (tag.ItIsCounting)
        {
            if (creatures[it].IsRunning) creatures[it].StandStill(double.PositiveInfinity);
        }
        else
        {
            creatures[it].Run(creatures[runner].T, Plays.Tag.ChaseSpeed / creatures[it].Settings.WalkSpeed);
        }
        var reach = atlas.BodyHalfSize * (sizes[it] + sizes[runner]);
        if (tag.Near(gap, reach) is { } tagged)
        {
            var now = tagged.Now;
            creatures[now].StandStill(double.PositiveInfinity);
            sparks.Burst(creatures[now].Position, creatures[now].Loop.Inward(creatures[now].Segment), 8, rng);
            Trace?.Invoke($"play tag {CharacterFor(tagged.By).Name} tags {CharacterFor(now).Name}");
        }
    }

    private void RunRope(PlaySession s, double dt)
    {
        var i = s.Players[0];
        if (s.Rope is not { } rope || !creatures[i].IsPlaying) { EndPlay(false); return; }
        var name = CharacterFor(i).Name;
        foreach (var e in rope.Update(dt))
        {
            switch (e)
            {
                case Plays.Rope.Event.Fired:
                    Trace?.Invoke($"play rope {name} fires at ({rope.Anchor.X:F0}, {rope.Anchor.Y:F0})");
                    break;
                case Plays.Rope.Event.LetGo:
                    Trace?.Invoke($"play rope {name} lets go");
                    break;
                case Plays.Rope.Event.Landed:
                    creatures[i].Carry(rope.Position, 0, "land");
                    creatures[i].TouchDown(1);
                    Trace?.Invoke($"play rope {name} lands at {rope.Position.X:F0}");
                    WrapUp(s, i);
                    return;
            }
        }
        creatures[i].Carry(rope.Position, rope.Rotation, rope.Pose);
    }

    private void RunChute(PlaySession s, double dt)
    {
        var i = s.Players[0];
        if (s.Chute is not { } chute || !creatures[i].IsPlaying) { EndPlay(false); return; }
        var name = CharacterFor(i).Name;
        foreach (var e in chute.Update(dt))
        {
            switch (e)
            {
                case Plays.Chute.Event.Jumped: Trace?.Invoke($"play parachute {name} jumps"); break;
                case Plays.Chute.Event.Opened: Trace?.Invoke($"play parachute {name} opens the parachute"); break;
                case Plays.Chute.Event.Landed: Trace?.Invoke($"play parachute {name} lands at {chute.Position.X:F0}"); break;
                case Plays.Chute.Event.Packed:
                    creatures[i].Carry(chute.Position, 0, "idle");
                    creatures[i].TouchDown(0.8);
                    WrapUp(s, i);
                    return;
            }
        }
        creatures[i].Carry(chute.Position, chute.Rotation, chute.Pose);
    }

    private void RunBasketball(PlaySession s, double dt)
    {
        if (s.Court is not { } court) return;
        court.Grown = Math.Min(1, court.Grown + dt / 0.4);
        var thrower = s.Players[court.Turn % s.Players.Length];
        // Startled into a jump or picked up: the game is off.
        if (!s.Players.All(k => !creatures[k].IsHeld && !creatures[k].IsJumping && !creatures[k].LooksAsleep)) { EndPlay(false); return; }
        foreach (var k in s.Players.Where(k => k != thrower && creatures[k].IsRunning)) creatures[k].StandStill(double.PositiveInfinity);
        var name = CharacterFor(thrower).Name;
        switch (court.Now)
        {
            case Court.Step.Walking:
            {
                var c = creatures[thrower];
                if (!c.IsRunning && !c.HasArrived)
                {
                    var d = rng.Range(150, 380);
                    var wallLoopX = court.Hoop.WallX - court.Hoop.Side * atlas.BodyHalfSize * sizes[thrower];
                    var to = SpotOn(court.Floor, wallLoopX - court.Hoop.Side * d, thrower);
                    creatures[thrower].Run(to.T, 2.2);
                }
                else if (c.HasArrived)
                {
                    creatures[thrower].Face(court.Hoop.Side);
                    creatures[thrower].TakeOff();
                    creatures[thrower].Carry(c.Position, c.RestingRotation, "land");
                    court.Now = Court.Step.WindUp;
                    court.StepUntil = Elapsed + 0.35;
                }
                break;
            }
            case Court.Step.WindUp:
            {
                if (Elapsed < court.StepUntil) break;
                var c = creatures[thrower];
                var half = atlas.BodyHalfSize * sizes[thrower];
                creatures[thrower].Carry(c.Position, c.RestingRotation, "jump");
                var from = new Pt(c.Position.X + court.Hoop.Side * half * 0.4, c.Position.Y + half * 1.1);
                var v = Plays.Ball.Aim(from, court.Hoop, rng.Range(50, 150));
                var makes = rng.NextDouble() < Plays.MakeChance;
                if (!makes) v = v with { Dx = v.Dx * (rng.Coin() ? rng.Range(0.8, 0.9) : rng.Range(1.1, 1.2)) };
                court.Ball = new Plays.Ball(from, v, Plays.Props.BallRadius * court.Scale, Settings.BallBounce / 100,
                                            court.Hoop, court.FloorY, court.From, court.To);
                court.ThrownAt = Elapsed;
                court.BallGone = null;
                court.ThrowsLeft -= 1;
                court.Now = Court.Step.Throwing;
                court.StepUntil = Elapsed + 0.3;
                Trace?.Invoke($"play basketball {name} throws");
                break;
            }
            case Court.Step.Throwing:
                if (Elapsed < court.StepUntil) break;
                creatures[thrower].TouchDown(double.PositiveInfinity);
                court.Now = Court.Step.Watching;
                break;
        }
        if (court.Ball is not { } ball) return;
        foreach (var e in ball.Step(dt))
        {
            switch (e)
            {
                case Plays.Ball.Event.Scored:
                    court.Made[thrower] = court.Made.GetValueOrDefault(thrower) + 1;
                    court.SwishUntil = Elapsed + 0.5;
                    sparks.Burst(new Pt(court.Hoop.RimX, court.Hoop.RimY), new Vec(0, 1), 8, rng);
                    Trace?.Invoke($"play basketball {name} scores");
                    break;
                case Plays.Ball.Event.Rim: Trace?.Invoke("play basketball clang off the rim"); break;
                case Plays.Ball.Event.Board: Trace?.Invoke("play basketball off the board"); break;
            }
        }
        if (court.BallGone is null && (ball.Resting || Elapsed - court.ThrownAt > 5)) court.BallGone = Elapsed;
        if (court.BallGone is not double gone || Elapsed - gone <= 0.5 || court.Now != Court.Step.Watching) return;
        court.Ball = null;
        if (!ball.Scored) Trace?.Invoke($"play basketball {name} misses");
        if (court.ThrowsLeft <= 0)
        {
            var best = s.Players.MaxBy(p => court.Made.GetValueOrDefault(p));
            Trace?.Invoke("play basketball over: " + string.Join(", ", s.Players.Select(p => $"{CharacterFor(p).Name} {court.Made.GetValueOrDefault(p)}")));
            WrapUp(s, best);
            return;
        }
        court.Turn += 1;
        court.Now = Court.Step.Walking;
        creatures[s.Players[court.Turn % s.Players.Length]].StandStill(double.PositiveInfinity);
    }

    // MARK: Ending

    /// <summary>The game is over and went well: the last word, its place in their story, then let go.</summary>
    private void WrapUp(PlaySession s, int speaker)
    {
        s.Now = PlaySession.Stage.Ending;
        s.Until = Elapsed + EndPause;
        if (s.Kind.IsTeamGame())
        {
            // Playing together brings them closer: teammates, or everyone in a small game.
            foreach (var (a, b) in BallGamePairs(s)) Shared(a, b, Core.Bonds.MomentKind.Play, s.Kind.Raw());
        }
        else if (s.Players.Length == 2) Shared(s.Players[0], s.Players[1], Core.Bonds.MomentKind.Play, s.Kind.Raw());
        DoneLine(speaker, s);
    }

    /// <summary>Let everyone go: down from the air, off the spot they waited on, out of <c>busy</c>.</summary>
    public void EndPlay(bool completed)
    {
        if (play is not PlaySession s) return;
        play = null;
        foreach (var i in s.Players.Where(i => i < creatures.Count))
        {
            if (creatures[i].IsPlaying) creatures[i].TouchDown();
            if (creatures[i].CurrentMode is Creature.Mode.Idle) creatures[i].StandStill(0.6);
            if (creatures[i].IsRunning) creatures[i].StandStill(0.6);
        }
        foreach (var p in s.Players) busy.Remove(p);
        if (s.Kind.IsTeamGame())
        {
            ballGameEnded[s.Kind] = Elapsed;
            // The final score stays up a moment, fading.
            if (BallGameProps(s).FirstOrDefault(p => p.Size is not null && p.Position == s.BallGame?.BoardAt) is { } board)
                fadingBoard = (board, Elapsed + BoardShown);
        }
        NextPlayAt = Elapsed + Plays.Wait(Settings.PlayEveryMinutes, Settings.PlayBondBoost, ClosestPairOnScreen(), rng);
        if (!completed) Trace?.Invoke($"play {s.Kind.Raw()} broken off");
        Trace?.Invoke($"play {s.Kind.Raw()} done");
    }

    // MARK: Words

    private bool PlayCanTalk => Settings.PlayTalk && Settings.TalkEnabled && !VoiceIsTakenNow;

    private string PlaySituation(PlaySession s)
    {
        var parts = new List<string> { TimeOfDay };
        if (AlmanacSentence.Length > 0) parts.Insert(0, AlmanacSentence);
        parts.AddRange(s.Players.Where(p => p < creatures.Count).Select(p => Describe(p) + "."));
        return string.Join(" ", parts);
    }

    /// <summary>Whoever started it says so: a built-in line, or one from the model.</summary>
    private void StartLine(PlaySession s)
    {
        if (!PlayCanTalk) return;
        var i = s.Players[0];
        var me = CharacterFor(i);
        var other = string.Join(", ", s.Players.Skip(1).Take(4).Select(p => CharacterFor(p).Name));
        var builtIn = Plays.StartLine(me.Name, s.Kind, other);
        var situation = PlaySituation(s);
        var service = Settings.Brain != BrainKind.Script ? Settings.ChatClient() : null;
        if (service is null)
        {
            SayPlayLine(builtIn, i, situation, AppSettings.BrainTitle(BrainKind.Script), "", null, null);
            return;
        }
        var vars = new Dictionary<string, string>
        {
            ["speaker"] = me.Name, ["speakerKind"] = Banter.Spoken(KindOf(i)), ["speakerPersona"] = Banter.Persona(me.Persona),
            ["play"] = s.Kind.Title(), ["others"] = other.Length == 0 ? "" : L10n.Tr(" with %@", other), ["situation"] = situation,
        };
        _ = StartLineByModel(service, s.Kind, s.Serial, i, me.Name, builtIn, situation, vars);
    }

    private async Task StartLineByModel(ChatClient service, Plays.Kind kind, int serial, int i, string name, string builtIn, string situation,
                                        Dictionary<string, string> vars)
    {
        var line = "";
        double? cost = null;
        int? tokens = null;
        try
        {
            var answer = await service.Line(Plays.LineSystemPrompt, Banter.Render(Plays.LinePrompt, vars));
            if (answer.Usage is Core.Spend.Usage usage)
            {
                if (service.Kind == ChatClient.Provider.LmStudio) usage.Cost = 0;       // a local model is free
                cost = usage.Cost;
                tokens = usage.PromptTokens + usage.CompletionTokens;
                Spend.Record(service.Kind, service.Model, usage,
                             kind.IsTeamGame() ? Core.Spend.Purpose.BallGames : Core.Spend.Purpose.Plays);
            }
            line = Banter.CleanLine(answer.Text, name, cut: answer.Cut);
        }
        catch (Exception e)
        {
            Console.Error.WriteLine("Ledgelings play: " + e.Message);
        }
        if (play?.Serial != serial) return;
        if (line.Length == 0) SayPlayLine(builtIn, i, situation, AppSettings.BrainTitle(BrainKind.Script), "", null, null);
        else SayPlayLine(line, i, situation, service.ProviderTitle, service.Model, cost, tokens, builtIn: false);
    }

    private void DoneLine(int i, PlaySession s)
    {
        if (!PlayCanTalk || i >= creatures.Count) return;
        SayPlayLine(Plays.DoneLine(CharacterFor(i).Name, rng), i, PlaySituation(s), AppSettings.BrainTitle(BrainKind.Script), "", null, null);
    }

    private void SayPlayLine(string text, int i, string situation, string provider, string model, double? cost, int? tokens, bool builtIn = true)
    {
        if (text.Length == 0 || i >= creatures.Count) return;
        Say(text, i, builtIn);
        History.Record(new ChatLog.Exchange
        {
            Time = DateTimeOffset.Now, Situation = situation, Provider = provider, Model = model,
            Lines = new List<ChatLog.Line> { new(CharacterFor(i).Name, text) }, Cost = cost, Tokens = tokens,
        });
    }

    // MARK: Drawing

    /// <summary>How much higher creature <paramref name="i"/>'s bubble floats: clear of its open parachute.</summary>
    private double PlayBubbleLift(int i)
    {
        if (play is not { Kind: Plays.Kind.Parachute } s || s.Players[0] != i || s.Chute is not { Canopy: > 0 } chute) return 0;
        return PlayCell.Height * sizes[i] * chute.Canopy;
    }

    /// <summary>The props of the game going on, in global points.</summary>
    internal List<PropSnapshot> PlayProps()
    {
        var fading = new List<PropSnapshot>();
        if (fadingBoard is { } f)
        {
            if (Elapsed > f.Until) fadingBoard = null;
            else fading.Add(f.Prop with { Opacity = (float)Math.Min(1, (f.Until - Elapsed) / 1.2) });
        }
        var props = new List<PropSnapshot>();
        if (play is not PlaySession s) return fading;
        Bitmap? Image(string animation, double time = 0) => playFrames.Frame(animation, time);
        static Vec Up(double rotation) => new(-Math.Sin(rotation), Math.Cos(rotation));
        switch (s.Kind)
        {
            case Plays.Kind.Tag:
                if (s.Tag is not { CurrentPhase: Plays.Tag.Phase.Puffing or Plays.Tag.Phase.Over }) break;
                foreach (var i in s.Players)
                {
                    var c = creatures[i];
                    var scale = sizes[i];
                    var half = atlas.BodyHalfSize * scale;
                    var bob = Math.Sin(Elapsed * 6) * scale;
                    var u = Up(c.Rotation);
                    var lift = half + 5 * scale + bob;
                    var side = c.IsMirrored ? 1 : -1;
                    props.Add(new PropSnapshot(Image("drop"), new Pt(c.Position.X + u.Dx * lift + u.Dy * half * 0.7 * side,
                                                                     c.Position.Y + u.Dy * lift - u.Dx * half * 0.7 * side), c.Rotation, scale));
                }
                break;
            case Plays.Kind.Rope:
            {
                if (s.Rope is not { RopeIsOut: true } rope) break;
                var i = s.Players[0];
                var c = creatures[i];
                var scale = sizes[i];
                var half = atlas.BodyHalfSize * scale;
                var u = Up(c.Rotation);
                var hands = new Pt(c.Position.X + u.Dx * half * 0.8, c.Position.Y + u.Dy * half * 0.8);
                var toHook = new Vec(rope.Hook.X - hands.X, rope.Hook.Y - hands.Y);
                var length = Math.Sqrt(toHook.Dx * toHook.Dx + toHook.Dy * toHook.Dy);
                var turn = Math.Atan2(-toHook.Dx, toHook.Dy);
                // The hook's shaft ends 3 sheet pixels below its middle; the rope runs up to there.
                var shaft = Math.Max(0, length - 3 * scale);
                for (double along = 0; along < shaft; along += 2 * scale)
                {
                    var k = along / Math.Max(length, 1);
                    props.Add(new PropSnapshot(Image("rope"), new Pt(hands.X + toHook.Dx * k, hands.Y + toHook.Dy * k), 0, scale));
                }
                props.Add(new PropSnapshot(Image("hook"), rope.Hook, turn, scale));
                break;
            }
            case Plays.Kind.Parachute:
            {
                if (s.Chute is not { Canopy: > 0 } chute) break;
                var i = s.Players[0];
                var c = creatures[i];
                var scale = sizes[i];
                var half = atlas.BodyHalfSize * scale;
                var open = chute.Canopy;
                var u = Up(c.Rotation);
                var lift = half * 0.8 + PlayCell.Height * scale * open / 2;
                props.Add(new PropSnapshot(Image("chute"), new Pt(c.Position.X + u.Dx * lift, c.Position.Y + u.Dy * lift), c.Rotation, scale * open));
                break;
            }
            case Plays.Kind.Basketball:
            {
                if (s.Court is not { Grown: > 0 } court) break;
                props.Add(new PropSnapshot(Image(Elapsed < court.SwishUntil ? "swish" : "hoop"), court.Hoop.Centre, 0, court.Scale,
                                           Mirrored: court.Hoop.Side < 0, Opacity: (float)court.Grown));
                if (court.Ball is { } ball)
                {
                    var fade = court.BallGone is double gone ? (float)Math.Max(0, 1 - (Elapsed - gone) / 0.5) : 1f;
                    // A frame for every eighth of a turn it has rolled: the seams go round.
                    props.Add(new PropSnapshot(Image("ball", Math.Abs(ball.Turn) / (Math.PI / 4) / 8), ball.Position, 0, court.Scale,
                                               Opacity: fade, InFront: true));
                }
                break;
            }
            case Plays.Kind.Soccer:
            case Plays.Kind.Baseball:
                props.AddRange(BallGameProps(s));
                break;
        }
        props.AddRange(fading);
        return props;
    }
}

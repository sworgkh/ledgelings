namespace Ledgelings.Core;

/// <summary>Soccer on one long floor (SPEC §7.10, Ball games): the widest one there is becomes the pitch, with a
/// little net at its ends. One plays keepy-uppy and shoots at an empty goal; two have a goal each; three play
/// one goal, a keeper and two attackers, the keeper changing after each goal; four or more split into two teams
/// by friendship, with a keeper each from six. They dribble, pass, steal the ball with a slide (nobody is
/// knocked down), shoot, head it, and the keepers dive. A ball over the bar bounces off the screen's wall
/// behind the goal, or, where the floor just ends, falls off and is brought back with a throw-in. First to
/// <c>GoalsToWin</c>, or the best score when time is up. Pure: the colony reads where everyone is each frame.
/// The Mac's <c>Plays+Soccer.swift</c>.</summary>
public static partial class Plays
{
    /// <summary>The pitch: the widest floor, in screen points (the edge itself, not where a creature's centre
    /// goes). Null when no floor is long enough to play on.</summary>
    public sealed record Pitch(EdgeWorld.Level Level, double FloorY, double From, double To, bool WallLeft, bool WallRight)
    {
        public const double Shortest = 300;
        public double Length => To - From;
        public bool Covers(double x) => x >= From && x <= To;

        /// <summary>The widest floor of <paramref name="world"/> (whose loops are <paramref name="inset"/> in from
        /// the screens), the lower one when two are as wide.</summary>
        public static Pitch? Choose(EdgeWorld world, double inset)
        {
            EdgeWorld.Level? widest = null;
            foreach (var f in world.Floors)
            {
                if (widest is not { } w) { widest = f; continue; }
                double la = w.To - w.From, lb = f.To - f.From;
                if (Math.Abs(la - lb) > 0.5 ? la < lb : w.Y > f.Y) widest = f;
            }
            if (widest is not { } best) return null;
            var walls = world.Walls(best);
            bool wallLeft = walls.Any(x => x.Side < 0), wallRight = walls.Any(x => x.Side > 0);
            // A wall stands half a body beyond the line a creature walks; where the floor steps down, the edge
            // ends half a body before it.
            double from = best.From + (wallLeft ? -inset : inset), to = best.To + (wallRight ? inset : -inset);
            if (to - from < Shortest) return null;
            return new Pitch(best, best.Y - inset, from, to, wallLeft, wallRight);
        }
    }

    public sealed class Soccer
    {
        public enum Phase { Juggling, Kickoff, Play, Goal, OutOfPlay, Over }

        public abstract record Event
        {
            public sealed record Kickoff(int By) : Event;
            /// <summary>Keepy-uppy, done: this many touches before it dropped.</summary>
            public sealed record Touches(int By, int Count) : Event;
            public sealed record Pass(int From, int To) : Event;
            public sealed record Shot(int By) : Event;
            public sealed record Header(int By) : Event;
            /// <summary>In: <c>Score</c> as the board shows it.</summary>
            public sealed record Goal(int By, string Score) : Event;
            public sealed record Save(int By) : Event;
            /// <summary>Off the post or the bar.</summary>
            public sealed record Woodwork(int By) : Event;
            /// <summary>Swung at it and kicked the air.</summary>
            public sealed record Whiff(int By) : Event;
            public sealed record Tackle(int By, int From) : Event;
            /// <summary>Off the pitch; whoever touched it last.</summary>
            public sealed record Out(int? By) : Event;
            public sealed record ThrowIn(int By) : Event;
            public sealed record WandersOff(int Index) : Event;
            public sealed record ComesBack(int Index) : Event;
            /// <summary>In keeper mode: the new one in goal.</summary>
            public sealed record KeeperNow(int Index) : Event;
            public sealed record Over : Event;
        }

        public enum Act { None, Dive, Slide, Stagger, Whiff, Wander, Cheer, Header }

        /// <summary>One player: where it is on the pitch and what it is doing. <c>Index</c> is the creature.</summary>
        public sealed class Player
        {
            public int Index { get; }
            public int Team { get; internal set; }
            public bool IsKeeper { get; internal set; }
            public double Half { get; }
            public double Speed { get; }
            public double X { get; internal set; }
            /// <summary>How far above standing it is: jumping, diving, celebrating.</summary>
            public double Lift { get; internal set; }
            public double Rotation { get; internal set; }
            public double Facing { get; internal set; } = 1;
            public string Pose { get; internal set; } = "idle";
            internal double Rise;
            internal Act Act = Act.None;
            /// <summary>The direction of a dive or a slide, or where a wanderer goes.</summary>
            internal double ActArg;
            internal double ActLeft;
            internal double Cooldown;
            internal double? Spot;
            internal double? ShootFrom;

            internal Player(int index, int team, bool isKeeper, double half, double speed, double x)
            {
                Index = index; Team = team; IsKeeper = isKeeper; Half = half; Speed = speed; X = x;
            }

            public bool IsWandering => Act == Act.Wander;
            internal bool IsBusy => Act != Act.None && Act != Act.Cheer;
        }

        /// <summary>A net at one end of the pitch: its mouth <c>X</c> (the goal line), <c>Side</c> +1 at the right end.</summary>
        public sealed record Goal(double X, double Side, double Height, int? KeptBy)
        {
            internal Goal Kept(int team) => this with { KeptBy = team };
        }

        public sealed class Ball
        {
            public Pt Position { get; internal set; }
            public Vec Velocity { get; internal set; }
            public double Radius { get; }
            /// <summary>Spun this far, for drawing.</summary>
            public double Turn { get; internal set; }
            public double Opacity { get; internal set; } = 1;
            internal Ball(Pt position, double radius) { Position = position; Radius = radius; }
        }

        /// <summary>The net's shape in sheet pixels, as <c>spritetool/painters/play.py</c> draws it in its 32×28
        /// cell, mouth to the left: the post's outer column, the crossbar's top row.</summary>
        public static class Net
        {
            public const double MouthColumn = 16;
            public const double BarRow = 4;
            /// <summary>The ball's radius, in sheet pixels.</summary>
            public const double BallRadius = 4;
        }

        public const double Gravity = 1400;
        public const double GoalTime = 2.8;
        public const double OverTime = 2.6;
        /// <summary>The match is stepped this finely.</summary>
        private const double Step = 1.0 / 120;

        public Lineup Lineup { get; }
        public Pitch Pitch { get; }
        public double Scale { get; }
        public int GoalsToWin { get; }
        public double Length { get; }
        public List<Player> Players { get; } = new();
        public List<Goal> Goals { get; }
        public Ball TheBall { get; }
        public Phase CurrentPhase { get; internal set; }
        /// <summary>Goals by creature, and by team (in duel and team play).</summary>
        public Dictionary<int, int> GoalsBy { get; } = new();
        public int[] TeamGoals { get; } = { 0, 0 };
        public double Clock { get; internal set; }
        public int? LastScorer { get; private set; }
        /// <summary>The one bringing the ball back for a throw-in.</summary>
        public int? Thrower { get; private set; }
        /// <summary>The ball is in someone's hands, up for a throw-in.</summary>
        public bool BallHeld { get; private set; }
        internal double PhaseLeft;
        internal int? LastTouch;
        private int juggles;
        private int juggleTarget = 6;
        private int? kicker;
        private double? wanderAt;
        private readonly List<int> keeperOrder = new();
        private bool finished;

        /// <summary>A match on <paramref name="pitch"/> for <paramref name="ids"/> (creature indices, the first
        /// started it), lined up by how many there are; <paramref name="teams"/> the two sides for team play
        /// (<see cref="Split"/>), <paramref name="keepers"/> their keepers. <paramref name="halves"/> each one's half
        /// size in points, <paramref name="scale"/> points per sheet pixel for the net and the ball; <paramref name="at"/>
        /// where each stands along the pitch to begin with (the middle, if not given).</summary>
        public Soccer(IReadOnlyList<int> ids, IReadOnlyList<int[]>? teams, IReadOnlySet<int>? keepers, IReadOnlyDictionary<int, double> halves,
                      IReadOnlyDictionary<int, double>? at, Pitch pitch, double scale, int goalsToWin, double length, Random rng)
        {
            Lineup = SoccerLineup(ids.Count);
            Pitch = pitch;
            Scale = scale;
            GoalsToWin = Math.Max(1, goalsToWin);
            Length = Math.Max(20, length);
            double lo = pitch.From, hi = pitch.To;
            var height = (Props.CellHeight - Net.BarRow) * scale;
            var depth = (Props.CellWidth - Net.MouthColumn) * scale;
            var right = new Goal(hi - depth, 1, height, null);
            var left = new Goal(lo + depth, -1, height, null);
            IReadOnlyList<int[]> sides;
            switch (Lineup)
            {
                case Lineup.Solo: sides = new[] { ids.ToArray(), Array.Empty<int>() }; Goals = new() { right }; break;
                case Lineup.Duel: sides = new[] { new[] { ids[0] }, new[] { ids[1] } }; Goals = new() { left.Kept(0), right.Kept(1) }; break;
                case Lineup.Keeper: sides = new[] { new[] { ids[0], ids[1] }, new[] { ids[2] } }; Goals = new() { right.Kept(1) }; break;
                default: sides = teams ?? Split(ids, (_, _) => 0); Goals = new() { left.Kept(0), right.Kept(1) }; break;
            }
            for (int team = 0; team < sides.Count; team++)
                foreach (var id in sides[team])
                    Players.Add(new Player(id, team, keepers?.Contains(id) == true || (Lineup == Lineup.Keeper && team == 1),
                                           halves.TryGetValue(id, out var h) ? h : 20, 150 * rng.Range(0.88, 1.12),
                                           Math.Min(Math.Max(at is not null && at.TryGetValue(id, out var x) ? x : (lo + hi) / 2, lo), hi)));
            if (Lineup == Lineup.Keeper) keeperOrder.AddRange(new[] { ids[2], ids[0], ids[1] });
            TheBall = new Ball(new Pt((lo + hi) / 2, pitch.FloorY + Net.BallRadius * scale), Net.BallRadius * scale);
            CurrentPhase = Phase.Kickoff;
            if (Lineup == Lineup.Solo)
            {
                CurrentPhase = Phase.Juggling;
                juggleTarget = rng.Next(4, 10);
                TheBall.Position = new Pt(Players[0].X + 4, pitch.FloorY + Players[0].Half * 2.6);
            }
            else
            {
                LineUp(1, rng);
            }
            if (ids.Count >= 3 && rng.NextDouble() < 0.45) wanderAt = Length * rng.Range(0.25, 0.6);
        }

        /// <summary>The match is over and everyone has cheered: let them go.</summary>
        public bool IsFinished => finished;

        public Player? PlayerOf(int index) => Players.FirstOrDefault(p => p.Index == index);

        /// <summary>Where creature <paramref name="index"/> is: its centre in screen points.</summary>
        public Pt? Position(int index) => PlayerOf(index) is { } p ? new Pt(p.X, Pitch.FloorY + p.Half + p.Lift) : null;

        /// <summary>The score as the board shows it: "Blocky 2 : 1 Zed" for two sides, each player's goals for one
        /// goal or one player. <paramref name="name"/> names a creature.</summary>
        public string Board(Func<int, string> name)
        {
            switch (Lineup)
            {
                case Lineup.Solo:
                    return $"{name(Players[0].Index)} {GoalsBy.GetValueOrDefault(Players[0].Index)}";
                case Lineup.Keeper:
                    return string.Join("  ", Players.Select(p => $"{name(p.Index)} {GoalsBy.GetValueOrDefault(p.Index)}"));
                default:
                    string Side(int t)
                    {
                        var members = Players.Where(p => p.Team == t).ToList();
                        return members.Count == 1 ? name(members[0].Index) : L10n.Tr("%@'s team", name(members[0].Index));
                    }
                    return $"{Side(0)} {TeamGoals[0]} : {TeamGoals[1]} {Side(1)}";
            }
        }

        // Running

        public List<Event> Update(double dt, Random rng)
        {
            var events = new List<Event>();
            var left = dt;
            while (left > 1e-9 && !finished)
            {
                var h = Math.Min(left, Step);
                left -= h;
                Tick(h, events, rng);
            }
            return events;
        }

        private void Tick(double dt, List<Event> events, Random rng)
        {
            if (CurrentPhase != Phase.Over && CurrentPhase != Phase.Goal) Clock += dt;
            PhaseLeft -= dt;
            foreach (var p in Players) p.Cooldown -= dt;
            switch (CurrentPhase)
            {
                case Phase.Juggling: Juggle(dt, events, rng); break;
                case Phase.Kickoff:
                    for (int k = 0; k < Players.Count; k++) Run(k, Players[k].Spot ?? Players[k].X, dt, 1.1);
                    Settle(dt);
                    if (Lineup == Lineup.Solo)
                    {
                        // Carrying the ball back over its head, for more keepy-uppy.
                        TheBall.Position = new Pt(Players[0].X, Pitch.FloorY + Players[0].Half * 2 + TheBall.Radius);
                        if (PhaseLeft <= 0)
                        {
                            CurrentPhase = Phase.Juggling;
                            BallHeld = false;
                            juggles = 0;
                            juggleTarget = rng.Next(4, 10);
                            TheBall.Velocity = new Vec(0, 200);
                        }
                    }
                    else if (PhaseLeft <= 0)
                    {
                        CurrentPhase = Phase.Play;
                        if (kicker is { } id && Slot(id) is { } k)
                        {
                            var d = Attack(Players[k].Team);
                            Kick(k, new Vec(d * 170, 60));
                            events.Add(new Event.Kickoff(Players[k].Index));
                        }
                    }
                    break;
                case Phase.Play:
                    Play(dt, events, rng);
                    if (Clock >= Length) End(events);
                    break;
                case Phase.Goal:
                    Celebrate();
                    Settle(dt);
                    if (PhaseLeft <= 0)
                    {
                        if (Lineup == Lineup.Solo)
                        {
                            CurrentPhase = Phase.Kickoff;
                            PhaseLeft = 2.4;
                            BallHeld = true;
                            TheBall.Velocity = Vec.Zero;
                            TheBall.Opacity = 1;
                            Players[0].Act = Act.None;
                            Players[0].Spot = Lo + (Hi - Lo) * 0.35;
                        }
                        else
                        {
                            LineUp(Conceding, rng);
                        }
                        if (Won) End(events);
                    }
                    break;
                case Phase.OutOfPlay:
                    ThrowIn(dt, events, rng);
                    break;
                case Phase.Over:
                    Celebrate();
                    Settle(dt);
                    if (PhaseLeft <= 0) finished = true;
                    break;
            }
            if (!BallHeld) Flight(dt, events, rng);
        }

        private bool Won => Lineup is Lineup.Solo or Lineup.Keeper
            ? GoalsBy.Values.Any(g => g >= GoalsToWin)
            : TeamGoals.Any(g => g >= GoalsToWin);

        /// <summary>The side that let the last one in kicks off.</summary>
        private int Conceding => LastScorer is { } s && PlayerOf(s) is { } p ? 1 - p.Team : 1;

        private void End(List<Event> events)
        {
            if (CurrentPhase == Phase.Over) return;
            CurrentPhase = Phase.Over;
            PhaseLeft = OverTime;
            events.Add(new Event.Over());
            foreach (var p in Players) if (p.IsBusy) p.Act = Act.None;
            var won = Winners;
            foreach (var p in Players) if (won.Contains(p.Index)) p.Act = Act.Cheer;
        }

        /// <summary>Who won: the best side, or the best scorer; nobody when it is level.</summary>
        public IReadOnlySet<int> Winners
        {
            get
            {
                switch (Lineup)
                {
                    case Lineup.Solo:
                        return GoalsBy.Count == 0 ? new HashSet<int>() : new HashSet<int> { Players[0].Index };
                    case Lineup.Keeper:
                        if (GoalsBy.Count == 0) return new HashSet<int>();
                        var best = GoalsBy.Values.Max();
                        return GoalsBy.Values.Count(g => g == best) == 1 ? GoalsBy.Where(g => g.Value == best).Select(g => g.Key).ToHashSet() : new HashSet<int>();
                    default:
                        if (TeamGoals[0] == TeamGoals[1]) return new HashSet<int>();
                        var t = TeamGoals[0] > TeamGoals[1] ? 0 : 1;
                        return Players.Where(p => p.Team == t).Select(p => p.Index).ToHashSet();
                }
            }
        }

        private int? Slot(int index)
        {
            var k = Players.FindIndex(p => p.Index == index);
            return k < 0 ? null : k;
        }

        /// <summary>Which way a team attacks: team 0 to the right.</summary>
        private static double Attack(int team) => team == 0 ? 1 : -1;

        /// <summary>The goal a team shoots at.</summary>
        private Goal? Target(int team) => Lineup is Lineup.Solo or Lineup.Keeper
            ? (team == 0 ? Goals[0] : null)
            : Goals.FirstOrDefault(g => g.KeptBy == 1 - team);

        private Goal? Own(int team) => Goals.FirstOrDefault(g => g.KeptBy == team);

        private double Lo => Pitch.From;
        private double Hi => Pitch.To;
        private double Middle => (Lo + Hi) / 2;

        /// <summary>Everyone to their own half (keepers in goal), the ball on the spot, <paramref name="team"/> to kick off.</summary>
        private void LineUp(int team, Random rng)
        {
            CurrentPhase = Phase.Kickoff;
            PhaseLeft = 2.2;
            TheBall.Position = new Pt(Middle, Pitch.FloorY + TheBall.Radius);
            TheBall.Velocity = Vec.Zero;
            TheBall.Opacity = 1;
            LastTouch = null;
            for (int t = 0; t <= 1; t++)
            {
                var members = Players.Where(p => p.Team == t && !p.IsKeeper).ToList();
                for (int n = 0; n < members.Count; n++)
                {
                    var d = Attack(t);
                    // Spread through the own half, the kicker on the ball.
                    var share = (double)(n + 1) / (members.Count + 1);
                    members[n].Spot = Middle - d * (40 + (Hi - Lo) / 2 * 0.7 * share);
                }
                foreach (var p in Players.Where(p => p.Team == t && p.IsKeeper))
                    if (Own(t) is { } g) p.Spot = g.X - g.Side * (p.Half + 6);
            }
            var takers = Players.Where(p => p.Team == team && !p.IsKeeper).ToList();
            var taker = takers.Count > 0 ? rng.Pick(takers) : Players.FirstOrDefault(p => !p.IsKeeper);
            if (taker is not null)
            {
                taker.Spot = Middle - Attack(taker.Team) * (taker.Half + TheBall.Radius);
                kicker = taker.Index;
            }
            for (int k = 0; k < Players.Count; k++)
            {
                Players[k].Act = Act.None;
                if (Players[k].Spot is { } s) Players[k].Spot = Clamp(s, k);
            }
        }

        private double Clamp(double x, int k) => Math.Min(Math.Max(x, Lo + Players[k].Half), Hi - Players[k].Half);

        /// <summary>Run player <paramref name="k"/> toward <paramref name="x"/> at its speed (times <paramref name="pace"/>), facing the way it goes.</summary>
        private void Run(int k, double x, double dt, double pace = 1)
        {
            var p = Players[k];
            var to = Clamp(x, k);
            var gap = to - p.X;
            var stride = p.Speed * pace * dt;
            if (Math.Abs(gap) > 2)
            {
                p.X += Math.Max(-stride, Math.Min(stride, gap));
                p.Facing = gap > 0 ? 1 : -1;
                if (p.Lift == 0 && !p.IsBusy) p.Pose = "walk";
            }
            else if (p.Lift == 0 && !p.IsBusy)
            {
                p.Pose = "idle";
                p.Facing = TheBall.Position.X >= p.X ? 1 : -1;
            }
        }

        /// <summary>Falling back down after a jump, and the rotation coming back upright.</summary>
        private void Settle(double dt)
        {
            foreach (var p in Players)
            {
                if (p.Lift > 0 || p.Rise > 0)
                {
                    p.Rise -= Gravity * dt;
                    p.Lift += p.Rise * dt;
                    if (p.Lift <= 0) { p.Lift = 0; p.Rise = 0; p.Pose = "land"; }
                }
                p.ActLeft -= dt;
                if (p.ActLeft <= 0 && p.IsBusy && !p.IsWandering)
                {
                    p.Act = Act.None;
                    p.Rotation = 0;
                }
                if (p.Act == Act.None && p.Lift == 0 && Math.Abs(p.Rotation) > 0.01) p.Rotation *= Math.Max(0, 1 - 10 * dt);
            }
        }

        private void Kick(int k, Vec v)
        {
            TheBall.Velocity = v;
            LastTouch = Players[k].Index;
            Players[k].Cooldown = 0.3;
            Players[k].Facing = v.Dx >= 0 ? 1 : -1;
        }

        // Keepy-uppy

        private void Juggle(double dt, List<Event> events, Random rng)
        {
            const int k = 0;
            var p = Players[k];
            Run(k, TheBall.Position.X, dt, 0.7);
            Settle(dt);
            var foot = Pitch.FloorY + p.Half * 0.9;
            if (!(TheBall.Velocity.Dy < 0 && TheBall.Position.Y < foot && Math.Abs(TheBall.Position.X - p.X) < p.Half * 1.3))
            {
                if (TheBall.Position.Y <= Pitch.FloorY + TheBall.Radius + 0.5 && TheBall.Velocity.Dy == 0) Dropped(events);
                return;
            }
            juggles++;
            p.Pose = "jump";
            p.Rise = 120;
            p.Lift = Math.Max(p.Lift, 0.1);
            var fumble = juggles >= 3 && rng.NextDouble() < 0.1;
            if (juggles >= juggleTarget || fumble)
            {
                // The last one goes off sideways and it is a game again.
                Kick(k, new Vec((fumble ? -1 : 1) * rng.Range(60, 120), 240));
                events.Add(new Event.Touches(p.Index, juggles));
                CurrentPhase = Phase.Play;
            }
            else
            {
                Kick(k, new Vec((p.X - TheBall.Position.X) * 2 + rng.Range(-25, 25), rng.Range(330, 430)));
            }
        }

        private void Dropped(List<Event> events)
        {
            events.Add(new Event.Touches(Players[0].Index, juggles));
            CurrentPhase = Phase.Play;
        }

        // Open play

        private void Play(double dt, List<Event> events, Random rng)
        {
            if (wanderAt is { } at && Clock >= at) { wanderAt = null; Wander(events, rng); }
            var ball = TheBall;
            var low = ball.Position.Y - Pitch.FloorY < 30;
            // Who has it at their feet.
            int? holder = null;
            for (int k = 0; k < Players.Count; k++)
            {
                var p = Players[k];
                if (p.IsBusy || p.IsKeeper || p.Lift != 0 || !low || Math.Abs(ball.Position.X - p.X) >= p.Half + ball.Radius + 6) continue;
                if (holder is not { } h || Math.Abs(ball.Position.X - p.X) < Math.Abs(ball.Position.X - Players[h].X)) holder = k;
            }
            var chasers = new HashSet<int>();
            for (int t = 0; t <= 1; t++)
            {
                int? best = null;
                for (int k = 0; k < Players.Count; k++)
                {
                    var p = Players[k];
                    if (p.Team != t || p.IsKeeper || p.IsBusy) continue;
                    if (best is not { } b || Math.Abs(p.X - ball.Position.X) < Math.Abs(Players[b].X - ball.Position.X)) best = k;
                }
                if (best is { } c) chasers.Add(c);
            }
            for (int k = 0; k < Players.Count; k++)
            {
                var p = Players[k];
                switch (p.Act)
                {
                    case Act.Wander:
                        Run(k, p.ActArg, dt, 0.35);
                        if (Math.Abs(p.X - Clamp(p.ActArg, k)) < 3) { p.Facing = p.ActArg > Middle ? 1 : -1; p.Pose = "idle"; }
                        if (p.ActLeft <= 0) { p.Act = Act.None; events.Add(new Event.ComesBack(p.Index)); }
                        continue;
                    case Act.Slide:
                        p.X = Clamp(p.X + p.ActArg * 220 * dt, k);
                        continue;
                    case Act.Dive:
                        p.X = Clamp(p.X + p.ActArg * 140 * dt, k);
                        continue;
                    case Act.Stagger:
                    case Act.Whiff:
                    case Act.Header:
                    case Act.Cheer:
                        if (p.Act == Act.Whiff) p.Rotation += 9 * dt * p.Facing;
                        continue;
                }
                if (p.IsKeeper) { Keep(k, dt, rng); continue; }
                var d = Attack(p.Team);
                if (k == holder)
                {
                    Hold(k, dt, events, rng);
                }
                else if (chasers.Contains(k))
                {
                    Run(k, ball.Position.X - d * (p.Half * 0.6), dt);
                    if (holder is { } h && Players[h].Team != p.Team && p.Cooldown <= 0
                        && Math.Abs(Players[h].X - p.X) < Players[h].Half + p.Half + 12
                        && rng.NextDouble() < 0.8 * dt)
                        TackleBall(k, h, events, rng);
                }
                else if (holder is { } mate && Players[mate].Team == p.Team)
                {
                    // Up the pitch ahead of a teammate with the ball, for a pass.
                    Run(k, Math.Max(Lo, Math.Min(Hi, Players[mate].X + d * 140)), dt, 0.9);
                }
                else if (Own(p.Team) is { } g)
                {
                    // Back between the ball and its own goal.
                    Run(k, (ball.Position.X * 2 + g.X) / 3, dt, 0.8);
                }
                else
                {
                    Run(k, ball.Position.X - d * 120, dt, 0.7);
                }
            }
            Settle(dt);
            Touch(events);
        }

        /// <summary>Player <paramref name="k"/> has the ball: dribble on, pass, or shoot.</summary>
        private void Hold(int k, double dt, List<Event> events, Random rng)
        {
            var p = Players[k];
            var d = Attack(p.Team);
            var ball = TheBall;
            if (Target(p.Team) is not { } goal)
            {
                // Nothing to shoot at (the keeper's own attackers have it): back to them.
                Run(k, ball.Position.X, dt);
                return;
            }
            var dist = Math.Abs(goal.X - p.X);
            p.ShootFrom ??= rng.Range(140, 360);
            if (p.Cooldown > 0) { Run(k, ball.Position.X + d * 4, dt, 0.8); return; }
            if ((goal.X - p.X) * d > 0 && dist < (p.ShootFrom ?? 220))
            {
                p.ShootFrom = null;
                if (rng.NextDouble() < 0.12)
                {
                    // A big swing at the ball, and it is not there: round it goes.
                    p.Act = Act.Whiff;
                    p.ActLeft = 0.7;
                    p.Pose = "jump";
                    p.Cooldown = 0.9;
                    events.Add(new Event.Whiff(p.Index));
                    return;
                }
                var aim = goal.Height * rng.Range(0.15, 1.25);
                var speed = rng.Range(400, 600);
                var t = Math.Max(0.15, dist / speed);
                var rise = (aim - (ball.Position.Y - Pitch.FloorY) + Gravity * t * t / 2) / t;
                Kick(k, new Vec(d * dist / t, Math.Max(40, rise)));
                events.Add(new Event.Shot(p.Index));
                return;
            }
            var mates = Enumerable.Range(0, Players.Count).Where(j => Players[j].Team == p.Team && j != k && !Players[j].IsKeeper && !Players[j].IsBusy).ToList();
            var pressed = Players.Any(o => o.Team != p.Team && !o.IsKeeper && (o.X - p.X) * d > -10 && Math.Abs(o.X - p.X) < 80);
            var ahead = mates.Where(j => (Players[j].X - p.X) * d > 40).ToList();
            if (pressed && ahead.Count > 0)
            {
                var m = rng.Pick(ahead);
                if (rng.NextDouble() < 2 * dt)
                {
                    var gap = Players[m].X - ball.Position.X;
                    var t = Math.Max(0.25, Math.Abs(gap) / 380);
                    Kick(k, new Vec(gap / t, Gravity * t / 2.4));
                    events.Add(new Event.Pass(p.Index, Players[m].Index));
                    p.ShootFrom = null;
                    return;
                }
            }
            // Dribble: run on, tapping it ahead.
            Run(k, p.X + d * 60, dt, 0.85);
            if ((ball.Position.X - p.X) * d < p.Half * 0.9 || ball.Velocity.Dx * d < p.Speed * 0.6)
            {
                Kick(k, new Vec(d * p.Speed * 1.2, 50));
                p.Cooldown = 0.18;
            }
        }

        private void TackleBall(int k, int from, List<Event> events, Random rng)
        {
            var d = Attack(Players[k].Team);
            var p = Players[k];
            var f = Players[from];
            p.Act = Act.Slide;
            p.ActArg = f.X > p.X ? 1 : -1;
            p.ActLeft = 0.45;
            p.Pose = "land";
            p.Rotation = -d * 0.45;
            f.Act = Act.Stagger;
            f.ActLeft = 0.5;
            f.Pose = "land";
            f.ShootFrom = null;
            f.Cooldown = 0.9;
            Kick(k, new Vec(d * rng.Range(200, 300), 90));
            events.Add(new Event.Tackle(p.Index, f.Index));
        }

        /// <summary>A keeper: in front of its goal, a little toward the ball; a dive at a shot coming in.</summary>
        private void Keep(int k, double dt, Random rng)
        {
            var p = Players[k];
            if (Own(p.Team) is not { } g) return;
            var ball = TheBall;
            var outward = Math.Min(80, Math.Abs(ball.Position.X - g.X) * 0.15);
            Run(k, g.X - g.Side * (p.Half + 4 + outward), dt, 0.9);
            // At its feet: a long kick up the pitch.
            if (p.Cooldown <= 0 && ball.Position.Y - Pitch.FloorY < p.Half && Math.Abs(ball.Position.X - p.X) < p.Half + ball.Radius + 4)
            {
                Kick(k, new Vec(-g.Side * rng.Range(380, 520), rng.Range(250, 400)));
                return;
            }
            var v = ball.Velocity;
            if (v.Dx * g.Side <= 150) return;
            var t = (g.X - ball.Position.X) / v.Dx;
            if (!(t > 0.05 && t < 0.6 && p.Cooldown <= 0)) return;
            var up = ball.Position.Y - Pitch.FloorY + v.Dy * t - Gravity * t * t / 2;
            if (up >= g.Height + ball.Radius * 2) return;
            // Read it (or not quite): a dive toward where it is going.
            var reads = rng.NextDouble() < 0.55;
            var height = reads ? Math.Max(0, up - p.Half) : Math.Max(0, up - p.Half) * 0.3 + 60;
            p.Act = Act.Dive;
            p.ActArg = -g.Side * 0.2;
            p.ActLeft = 0.75;
            p.Rise = Math.Sqrt(2 * Gravity * Math.Max(10, height));
            p.Lift = Math.Max(p.Lift, 0.1);
            p.Pose = "jump";
            p.Rotation = g.Side * Math.PI / 2 * (up > p.Half * 2 ? 0.6 : 1);
        }

        /// <summary>The ball against bodies: a header, a chest, a keeper's save.</summary>
        private void Touch(List<Event> events)
        {
            var ball = TheBall;
            for (int k = 0; k < Players.Count; k++)
            {
                var p = Players[k];
                if (p.Cooldown > 0 || p.IsWandering) continue;
                var cx = p.X; var cy = Pitch.FloorY + p.Half + p.Lift;
                double dx = ball.Position.X - cx, dy = ball.Position.Y - cy;
                if (!(Math.Sqrt(dx * dx + dy * dy) < p.Half + ball.Radius && (ball.Position.Y - Pitch.FloorY > p.Half * 1.2 || p.Act != Act.None))) continue;
                if (p.Act == Act.Dive && Own(p.Team) is { } own)
                {
                    ball.Velocity = new Vec(-own.Side * Math.Max(120, Math.Abs(ball.Velocity.Dx) * 0.45), 300);
                    LastTouch = p.Index;
                    p.Cooldown = 0.6;
                    events.Add(new Event.Save(p.Index));
                    continue;
                }
                if (ball.Position.Y - Pitch.FloorY <= p.Half * 1.2) continue;
                var d = p.IsKeeper ? -(Own(p.Team)?.Side ?? 1) : Attack(p.Team);
                // Near the goal it is nodded down at it; elsewhere up and on.
                if (!p.IsKeeper && Target(p.Team) is { } g && Math.Abs(g.X - p.X) < 260 && (g.X - p.X) * d > 0)
                    Kick(k, new Vec(d * 300, -140));
                else
                    Kick(k, new Vec(d * 330, 220));
                if (p.Lift > 0) events.Add(new Event.Header(p.Index));
            }
            // A ball dropping onto a player's head: up it goes for a header.
            foreach (var p in Players)
            {
                if (p.Lift != 0 || p.IsBusy || p.IsKeeper) continue;
                var over = ball.Position.Y - Pitch.FloorY;
                if (ball.Velocity.Dy < 0 && over > p.Half * 2.2 && over < p.Half * 4 && Math.Abs(ball.Position.X - p.X) < p.Half && p.Cooldown <= 0)
                {
                    p.Rise = 380;
                    p.Lift = 0.1;
                    p.Pose = "jump";
                    p.Act = Act.Header;
                    p.ActLeft = 0.5;
                }
            }
        }

        // The ball

        private void Flight(double dt, List<Event> events, Random rng)
        {
            var ball = TheBall;
            if (CurrentPhase == Phase.Over && ball.Opacity <= 0) return;
            var before = ball.Position;
            var vx = ball.Velocity.Dx;
            var vy = ball.Velocity.Dy - Gravity * dt;
            double x = before.X + vx * dt, y = before.Y + vy * dt;
            ball.Turn += vx * dt / Math.Max(1, ball.Radius);
            var ground = Pitch.FloorY + ball.Radius;
            // Past the floor's end there is nothing to land on.
            var onPitch = Pitch.Covers(x);
            if (onPitch && y < ground && before.Y >= ground - 1)
            {
                y = ground;
                vy = vy < -80 ? -vy * 0.5 : 0;
            }
            if (onPitch && y <= ground + 0.5) vx *= Math.Exp(-1.1 * dt);
            ball.Position = new Pt(x, y);
            ball.Velocity = new Vec(vx, vy);
            // Gone off: it falls away, fading, while someone fetches it.
            if (CurrentPhase == Phase.OutOfPlay) { ball.Opacity = Math.Max(0, ball.Opacity - dt * 2); return; }
            if (CurrentPhase is Phase.Goal or Phase.Over) { BounceOffEnds(); return; }
            foreach (var g in Goals)
            {
                var crossed = g.Side > 0 ? before.X < g.X && x >= g.X : before.X > g.X && x <= g.X;
                if (!crossed) continue;
                var up = y - Pitch.FloorY;
                if (up < g.Height - ball.Radius * 0.5) { Scored(g, events); return; }
                if (up < g.Height + ball.Radius)
                {
                    // Off the bar.
                    ball.Velocity = new Vec(-vx * 0.5, Math.Abs(vy) * 0.6 + 80);
                    ball.Position = new Pt(g.X - g.Side * ball.Radius, y);
                    if (LastTouch is { } t) events.Add(new Event.Woodwork(t));
                    return;
                }
            }
            // Past an end: off a wall behind the goal, or over the edge.
            if (x < Lo + ball.Radius || x > Hi - ball.Radius)
            {
                var right = x > Middle;
                if (right ? Pitch.WallRight : Pitch.WallLeft) BounceOffEnds();
                else if (x < Lo - ball.Radius * 2 || x > Hi + ball.Radius * 2) Out(events);
            }
            // Over a goal's net and dropping behind it, where there is a wall: back into play.
            foreach (var g in Goals)
            {
                if (!((ball.Position.X - g.X) * g.Side > 0 && ball.Position.Y - Pitch.FloorY < g.Height + ball.Radius)) continue;
                ball.Position = new Pt(ball.Position.X, Pitch.FloorY + g.Height + ball.Radius);
                ball.Velocity = new Vec(-g.Side * Math.Max(60, Math.Abs(ball.Velocity.Dx) * 0.6), Math.Abs(ball.Velocity.Dy) * 0.4);
            }
        }

        private void BounceOffEnds()
        {
            var ball = TheBall;
            if (ball.Position.X < Lo + ball.Radius && (Pitch.WallLeft || CurrentPhase != Phase.Play))
            {
                ball.Position = new Pt(Lo + ball.Radius, ball.Position.Y);
                ball.Velocity = new Vec(Math.Abs(ball.Velocity.Dx) * 0.55, ball.Velocity.Dy);
            }
            if (ball.Position.X > Hi - ball.Radius && (Pitch.WallRight || CurrentPhase != Phase.Play))
            {
                ball.Position = new Pt(Hi - ball.Radius, ball.Position.Y);
                ball.Velocity = new Vec(-Math.Abs(ball.Velocity.Dx) * 0.55, ball.Velocity.Dy);
            }
        }

        private void Scored(Goal g, List<Event> events)
        {
            var attackers = Lineup is Lineup.Solo or Lineup.Keeper ? 0 : 1 - (g.KeptBy ?? 1);
            // The last attacker on it scores; an own goal counts for them all the same.
            var scorer = LastTouch is { } lt && PlayerOf(lt) is { } toucher && toucher.Team == attackers ? toucher.Index
                : Players.Where(p => p.Team == attackers).OrderBy(p => Math.Abs(p.X - g.X)).Select(p => (int?)p.Index).FirstOrDefault()
                  ?? Players[0].Index;
            GoalsBy[scorer] = GoalsBy.GetValueOrDefault(scorer) + 1;
            if (Lineup != Lineup.Solo && Lineup != Lineup.Keeper) TeamGoals[attackers]++;
            LastScorer = scorer;
            TheBall.Velocity = new Vec(TheBall.Velocity.Dx * 0.25, 0);
            CurrentPhase = Phase.Goal;
            PhaseLeft = GoalTime;
            foreach (var p in Players)
            {
                p.Act = p.Index == scorer ? Act.Cheer : Act.None;
                p.Pose = "idle";
            }
            events.Add(new Event.Goal(scorer, Board(i => i.ToString())));
            if (Lineup == Lineup.Keeper) RotateKeeper(events);
        }

        /// <summary>Three at one goal: the one in goal goes out, the next comes in.</summary>
        private void RotateKeeper(List<Event> events)
        {
            if (keeperOrder.Count != 3) return;
            keeperOrder.Add(keeperOrder[0]);
            keeperOrder.RemoveAt(0);
            var next = keeperOrder[0];
            foreach (var p in Players)
            {
                p.IsKeeper = p.Index == next;
                p.Team = p.IsKeeper ? 1 : 0;
            }
            events.Add(new Event.KeeperNow(next));
        }

        private void Celebrate()
        {
            foreach (var p in Players)
                if (p.Act == Act.Cheer && p.Lift == 0 && p.Rise <= 0)
                {
                    p.Rise = 300;
                    p.Lift = 0.1;
                    p.Pose = "jump";
                }
        }

        // Out, and brought back

        private void Out(List<Event> events)
        {
            CurrentPhase = Phase.OutOfPlay;
            var touched = LastTouch is { } t ? PlayerOf(t) : null;
            events.Add(new Event.Out(touched?.Index));
            var x = TheBall.Position.X < Middle ? Lo : Hi;
            // The other side brings it back (anyone, when everyone is on one side).
            var pool = Enumerable.Range(0, Players.Count).Where(j => !Players[j].IsKeeper && Players[j].Team != touched?.Team).ToList();
            var from = pool.Count == 0 ? Enumerable.Range(0, Players.Count).Where(j => !Players[j].IsKeeper).ToList() : pool;
            var k = from.Count == 0 ? 0 : from.OrderBy(j => Math.Abs(Players[j].X - x)).First();
            Thrower = Players[k].Index;
            BallHeld = false;
            Players[k].Spot = Clamp(x, k);
            PhaseLeft = 6;
            foreach (var p in Players) if (p.IsBusy && !p.IsWandering) p.Act = Act.None;
        }

        private void ThrowIn(double dt, List<Event> events, Random rng)
        {
            if (Thrower is not { } id || Slot(id) is not { } k) { CurrentPhase = Phase.Play; return; }
            var p = Players[k];
            var to = p.Spot ?? p.X;
            Run(k, to, dt, 1.2);
            Settle(dt);
            if (!(BallHeld || Math.Abs(p.X - Clamp(to, k)) < 3 || PhaseLeft <= 0)) return;
            if (!BallHeld)
            {
                // Held up over its head, facing into the pitch.
                BallHeld = true;
                TheBall.Opacity = 1;
                TheBall.Velocity = Vec.Zero;
                PhaseLeft = 0.8;
                p.Facing = p.X > Middle ? -1 : 1;
            }
            TheBall.Position = new Pt(p.X, Pitch.FloorY + p.Half * 2 + TheBall.Radius);
            p.Pose = "jump";
            if (PhaseLeft > 0) return;
            BallHeld = false;
            Kick(k, new Vec(p.Facing * rng.Range(220, 320), 320));
            p.Spot = null;
            Thrower = null;
            CurrentPhase = Phase.Play;
            events.Add(new Event.ThrowIn(id));
        }

        // Wandering off

        private void Wander(List<Event> events, Random rng)
        {
            var pool = Players.Where(p => !p.IsKeeper && Math.Abs(p.X - TheBall.Position.X) > 60).ToList();
            if (pool.Count == 0) return;
            var p = rng.Pick(pool);
            // To the far end from the ball, to look at something else for a while.
            p.Act = Act.Wander;
            p.ActArg = TheBall.Position.X > Middle ? Lo + 20 : Hi - 20;
            p.ActLeft = rng.Range(6, 9);
            events.Add(new Event.WandersOff(p.Index));
        }
    }
}

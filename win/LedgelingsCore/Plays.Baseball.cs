namespace Ledgelings.Core;

/// <summary>Baseball on every edge they walk (SPEC §7.10, Ball games): home plate where the batter stands, the
/// three bases on three other edges as far apart as can be (on one screen: the right wall, the ceiling, the left
/// wall), the pitcher on the batter's own floor. A pitch, a swing (a hit, a foul or a miss: closer friends pitch
/// kinder balls, a good mood helps, and some luck), and a hit ball flies in an arc to some edge. Fielders hop
/// edge to edge to catch it or fetch it and throw it in; the batter runs the bases by hopping edge to edge, as far
/// as it dares. A ball hit out through the top of the screen is a home run. One creature takes practice swings;
/// two pitch to each other in turns; three to five bat one at a time while the rest field; six or more play as
/// two teams. A runner who has to bat again leaves a ghost on its base. Pure. The Mac's <c>Plays+Baseball.swift</c>.</summary>
public static partial class Plays
{
    /// <summary>A place on the screen's outline: the edge point, the way into the screen from it, the edge's turn
    /// and its walking direction. A creature stands on it with its centre <c>half</c> along <c>Inward</c>.</summary>
    public readonly record struct Place(Pt Edge, Vec Inward, double Rotation, Vec Along)
    {
        public Pt Centre(double half) => new(Edge.X + Inward.Dx * half, Edge.Y + Inward.Dy * half);

        /// <summary>The place at <paramref name="spot"/> of <paramref name="world"/>, whose loops are <paramref name="inset"/> in from the screens.</summary>
        public static Place At(EdgeWorld.Spot spot, EdgeWorld world, double inset)
        {
            var loop = world.Loops[spot.Loop];
            var s = loop.Segment(spot.T);
            var p = loop.Point(spot.T);
            var n = loop.Inward(s);
            return new Place(new Pt(p.X - n.Dx * inset, p.Y - n.Dy * inset), n, loop.Rotation(s), loop.Direction(s));
        }

        /// <summary>+1 when <paramref name="point"/> lies the way the edge is walked.</summary>
        public double FacingToward(Pt point) => (point.X - Edge.X) * Along.Dx + (point.Y - Edge.Y) * Along.Dy >= 0 ? 1 : -1;

        /// <summary>The same place moved <paramref name="by"/> points along its edge.</summary>
        public Place Shifted(double by) => this with { Edge = new Pt(Edge.X + Along.Dx * by, Edge.Y + Along.Dy * by) };
    }

    /// <summary>Home, the three bases, the pitcher's mound, and where the fielders wait.</summary>
    public sealed class Field
    {
        public Place Home { get; }
        public IReadOnlyList<Place> Bases { get; }
        public Place Mound { get; }
        public IReadOnlyList<Place> Posts { get; }
        /// <summary>The screen's top over home: above this a ball is gone.</summary>
        public double Top { get; }
        /// <summary>Every edge of the world, for where a hit ball comes down.</summary>
        private readonly List<(Pt From, Pt To, Vec Inward, double Rotation)> edges;
        /// <summary>The outlines, in screen points, for keeping a ball's arc on screen.</summary>
        private readonly List<List<Pt>> outlines;

        private Field(Place home, IReadOnlyList<Place> bases, Place mound, IReadOnlyList<Place> posts,
                      List<(Pt, Pt, Vec, double)> edges, List<List<Pt>> outlines, double top)
        {
            Home = home; Bases = bases; Mound = mound; Posts = posts; this.edges = edges; this.outlines = outlines; Top = top;
        }

        /// <summary>A field in <paramref name="world"/> (loops <paramref name="inset"/> in from the screens) with home
        /// at <paramref name="batter"/>'s spot when its edge is long enough to pitch along, else on the widest floor.
        /// The bases go on the three other edges that are furthest apart from home and each other, in turn round the
        /// screen the way a real diamond goes (first to the batter's right). Null when there are not three.</summary>
        public static Field? Choose(EdgeWorld world, double inset, EdgeWorld.Spot batter)
        {
            double Len(int l, int s) => world.Loops[l].SegmentLength(s);
            int homeLoop = batter.Loop, homeSeg = world.Loops[batter.Loop].Segment(batter.T);
            const double pitchable = 420;
            if (Len(homeLoop, homeSeg) < pitchable || Math.Abs(world.Loops[homeLoop].Direction(homeSeg).Dy) > 0.5)
            {
                EdgeWorld.Level? widest = null;
                foreach (var f in world.Floors) if (widest is not { } w || (f.To - f.From) > (w.To - w.From)) widest = f;
                if (widest is not { } floor || floor.To - floor.From < pitchable) return null;
                homeLoop = floor.Loop; homeSeg = floor.Segment;
            }
            var loop = world.Loops[homeLoop];
            double start = loop.T(homeSeg, 0), seg = Len(homeLoop, homeSeg);
            // Home where the batter is, kept to the outer part of its edge: the pitcher needs room.
            var at = homeLoop == batter.Loop && loop.Segment(batter.T) == homeSeg ? loop.Wrap(batter.T - start) : seg * 0.25;
            var homeShare = Math.Min(Math.Max(at / seg, 0.12), 0.88);
            var homeT = start + seg * homeShare;
            var moundT = start + seg * (homeShare < 0.5 ? Math.Min(0.85, homeShare + 0.45) : Math.Max(0.15, homeShare - 0.45));
            var home = Place.At(new EdgeWorld.Spot(homeLoop, loop.Wrap(homeT)), world, inset);
            var mound = Place.At(new EdgeWorld.Spot(homeLoop, loop.Wrap(moundT)), world, inset);

            // Candidate bases: the middle of every other edge long enough to stand on.
            var candidates = new List<Place>();
            foreach (var s in world.Segments)
                if (s.Length >= 80 && !(s.Loop == homeLoop && s.Segment == homeSeg))
                    candidates.Add(Place.At(new EdgeWorld.Spot(s.Loop, world.Loops[s.Loop].T(s.Segment, 0.5)), world, inset));
            if (candidates.Count < 3) return null;
            static double D(Place a, Place b) => Math.Sqrt(Math.Pow(a.Edge.X - b.Edge.X, 2) + Math.Pow(a.Edge.Y - b.Edge.Y, 2));
            Place[]? picks = null;
            var bestScore = 0.0;
            var n = candidates.Count;
            for (int i = 0; i < n; i++) for (int j = i + 1; j < n; j++) for (int k = j + 1; k < n; k++)
            {
                var trio = new[] { candidates[i], candidates[j], candidates[k] };
                var all = new[] { home }.Concat(trio).ToArray();
                var score = double.PositiveInfinity;
                for (int a = 0; a < all.Length; a++) for (int b = a + 1; b < all.Length; b++) score = Math.Min(score, D(all[a], all[b]));
                if (picks is null || score > bestScore + 0.5) { bestScore = score; picks = trio; }
            }
            // Round the field counter-clockwise from home, as a diamond is run.
            var four = new[] { home }.Concat(picks!).ToArray();
            var centre = new Pt(four.Average(p => p.Edge.X), four.Average(p => p.Edge.Y));
            double Angle(Place p)
            {
                var a = Math.Atan2(p.Edge.Y - centre.Y, p.Edge.X - centre.X) - Math.Atan2(home.Edge.Y - centre.Y, home.Edge.X - centre.X);
                return a < 0 ? a + 2 * Math.PI : a;
            }
            var bases = picks!.OrderBy(Angle).ToList();

            // Where the fielders wait: a little way along from each base, second base's first.
            var posts = new List<Place>();
            var order = new[] { bases[1], bases[0], bases[2], bases[1], bases[0], bases[2], bases[1], bases[0], bases[2] };
            for (int k = 0; k < order.Length; k++) posts.Add(order[k].Shifted(k < 3 ? 70 : k < 6 ? -70 : 140));
            var edges = new List<(Pt, Pt, Vec, double)>();
            var outlines = new List<List<Pt>>();
            foreach (var lp in world.Loops)
            {
                var outline = new List<Pt>();
                for (int s = 0; s < lp.SegmentCount; s++)
                {
                    var nv = lp.Inward(s);
                    Pt a = lp.Vertices[s], b = lp.Vertices[(s + 1) % lp.SegmentCount];
                    Pt ea = new(a.X - nv.Dx * inset, a.Y - nv.Dy * inset), eb = new(b.X - nv.Dx * inset, b.Y - nv.Dy * inset);
                    edges.Add((ea, eb, nv, lp.Rotation(s)));
                    outline.Add(ea);
                }
                outlines.Add(outline);
            }
            var top = world.Ceiling(home.Centre(inset)) is { } c ? c.Y + inset : home.Edge.Y + 600;
            return new Field(home, bases, mound, posts, edges, outlines, top);
        }

        /// <summary>Inside one of the screens (well, the outlines): a ball there is still in the air.</summary>
        public bool IsInside(Pt p) => outlines.Any(poly =>
        {
            var inside = false;
            for (int i = 0, j = poly.Count - 1; i < poly.Count; j = i++)
            {
                Pt a = poly[i], b = poly[j];
                if ((a.Y > p.Y) != (b.Y > p.Y) && p.X < (b.X - a.X) * (p.Y - a.Y) / (b.Y - a.Y) + a.X) inside = !inside;
            }
            return inside;
        });

        /// <summary>A random point on some edge at least <paramref name="away"/> from <paramref name="from"/>, with its place.</summary>
        public Place? Landing(Pt from, double away, Random rng)
        {
            static double Len((Pt From, Pt To, Vec Inward, double Rotation) e) => Math.Sqrt(Math.Pow(e.To.X - e.From.X, 2) + Math.Pow(e.To.Y - e.From.Y, 2));
            var total = edges.Sum(Len);
            if (total <= 0) return null;
            for (int tries = 0; tries < 40; tries++)
            {
                var pick = rng.NextDouble() * total;
                foreach (var e in edges)
                {
                    var len = Len(e);
                    if (pick > len) { pick -= len; continue; }
                    var k = Math.Min(Math.Max(pick / Math.Max(len, 1), 0.08), 0.92);
                    var p = new Pt(e.From.X + (e.To.X - e.From.X) * k, e.From.Y + (e.To.Y - e.From.Y) * k);
                    if (Math.Sqrt(Math.Pow(p.X - from.X, 2) + Math.Pow(p.Y - from.Y, 2)) < away) break;
                    var along = new Vec((e.To.X - e.From.X) / Math.Max(len, 1), (e.To.Y - e.From.Y) / Math.Max(len, 1));
                    return new Place(p, e.Inward, e.Rotation, along);
                }
            }
            return null;
        }
    }

    public sealed class Baseball
    {
        public enum Phase { GettingReady, Pitching, InPlay, Over }

        public enum Swing { Hit, Foul, Miss }

        public abstract record Event
        {
            public sealed record Pitch(int By) : Event;
            /// <summary>The batter tosses it up for itself: practice.</summary>
            public sealed record Toss(int By) : Event;
            public sealed record Swung(int By, Swing Result) : Event;
            public sealed record Strike(int By, int Count) : Event;
            /// <summary>Out: "struck out", "caught", or "at first"… (<c>How</c>).</summary>
            public sealed record Out(int By, string How) : Event;
            public sealed record Caught(int By) : Event;
            /// <summary>Dropped it: a funny miss.</summary>
            public sealed record Fumble(int By) : Event;
            public sealed record Runs(int By, int To) : Event;
            public sealed record Safe(int By, int At) : Event;
            public sealed record Scored(int By, string Score) : Event;
            public sealed record HomeRun(int By, int RunsIn) : Event;
            public sealed record Fetch(int By) : Event;
            /// <summary>The other side bats now: <c>Inning</c> counted from 1.</summary>
            public sealed record SidesChange(int Inning, int[] Batting) : Event;
            public sealed record Ghost(int Index, int Base) : Event;
            public sealed record Over : Event;
        }

        /// <summary>One player: where it stands, and the hops it is making.</summary>
        public sealed class Actor
        {
            public int Index { get; }
            public double Half { get; }
            public Place Place { get; internal set; }
            public double Facing { get; internal set; } = 1;
            internal Place? From;
            internal double Hop;
            internal double HopTime;
            internal List<Place> Hops = new();
            internal double Landed = 1;
            internal double Squat;
            internal double Cheer;
            public bool IsHopping => From is not null;
            internal Actor(int index, double half, Place place) { Index = index; Half = half; Place = place; }
        }

        public abstract record BallState
        {
            public sealed record Gone : BallState;
            public sealed record Held(int By) : BallState;
            public sealed record Flying(Pt From, Vec Velocity, double Gravity, double Clock, double Time) : BallState;
            public sealed record Resting(Pt At) : BallState;
        }

        public sealed record Runner(int Owner, bool Ghost);

        private abstract record Step
        {
            public sealed record Hop(int Index, Place[] Places) : Step;
            public sealed record Fly(Pt From, Pt To, double Time, double Gravity) : Step;
            public sealed record Hold(int Index) : Step;
            public sealed record Rest(Pt At) : Step;
            public sealed record Tell(Event Event) : Step;
            public sealed record Out(int Index, string How) : Step;
            public sealed record Score(int Index) : Step;
            public sealed record Occupy(int Base, Runner? Runner) : Step;
            public sealed record Resolve : Step;
            public sealed record BatterUp : Step;
            public sealed record SwingBat : Step;
            public sealed record Cheer(int Index, double Seconds) : Step;
        }

        public const double Gravity = 700;
        public const double HopSpeed = 1300;
        public const double ThrowSpeed = 900;

        public Lineup Lineup { get; }
        public Field Field { get; }
        public int Innings { get; }
        /// <summary>Who bats in turn: one list per side.</summary>
        public IReadOnlyList<int[]> Sides { get; }
        public List<Actor> Actors { get; } = new();
        public BallState Ball { get; private set; } = new BallState.Gone();
        public Runner?[] Bases { get; private set; } = new Runner?[3];
        public Phase CurrentPhase { get; private set; } = Phase.GettingReady;
        public int Inning { get; private set; } = 1;
        public int Batting { get; private set; }
        public int Batter { get; private set; }
        public int? Pitcher { get; private set; }
        public int Strikes { get; private set; }
        public int Outs { get; private set; }
        /// <summary>Runs in this side's turn at bat: a small game's turn ends at <see cref="Mercy"/> of them.</summary>
        public int TurnRuns { get; private set; }
        public Dictionary<int, int> RunsBy { get; } = new();
        public int[] SideRuns { get; }
        public int Swings { get; private set; }
        public int Hits { get; internal set; }
        public int HomeRuns { get; internal set; }
        /// <summary>The bat's swing, 0 at rest over the shoulder to 1 right through.</summary>
        public double BatSwing { get; private set; }
        /// <summary>A home run has just gone out: where, for the fireworks.</summary>
        public Pt? LastHomeRun { get; private set; }
        public int PracticeSwings { get; }
        private readonly double mood;
        private readonly Dictionary<int, Dictionary<int, double>> close = new();
        private double clock;
        private double overUntil;
        private readonly List<(double At, Step Step)> schedule = new();
        private readonly int[] next;
        private bool finished;
        private Swing pending = Swing.Miss;
        /// <summary>The batter's turn is over: a hit, or out.</summary>
        private bool atBatOver;

        /// <summary>A game on <paramref name="field"/> for <paramref name="ids"/> (creature indices; the first started
        /// it) standing at <paramref name="starts"/>, each <paramref name="halves"/> in half size; <paramref name="teams"/>
        /// the two sides from six. <paramref name="innings"/> long; <paramref name="mood"/> −1…1 (a playful cursor helps).</summary>
        public Baseball(IReadOnlyList<int> ids, IReadOnlyList<int[]>? teams, IReadOnlyDictionary<int, Place> starts, IReadOnlyDictionary<int, double> halves,
                        Field field, int innings, double mood = 0, Func<int, int, double>? closeness = null)
        {
            closeness ??= (_, _) => 0;
            Lineup = BaseballLineup(ids.Count);
            Field = field;
            Innings = Math.Max(1, innings);
            this.mood = Math.Min(Math.Max(mood, -1), 1);
            foreach (var a in ids) foreach (var b in ids) if (b != a)
            {
                if (!close.TryGetValue(a, out var row)) close[a] = row = new();
                row[b] = closeness(a, b);
            }
            Sides = Lineup == Lineup.Teams ? (teams ?? Split(ids, closeness)) : ids.Select(i => new[] { i }).ToArray();
            SideRuns = new int[Sides.Count];
            PracticeSwings = Innings * 4;
            foreach (var i in ids) Actors.Add(new Actor(i, halves.TryGetValue(i, out var h) ? h : 20, starts.TryGetValue(i, out var s) ? s : field.Home));
            Batter = Sides[0][0];
            next = new int[Sides.Count];
            next[0] = 1;
            TakePositions(true);
        }

        public bool IsFinished => finished;

        public Actor? ActorOf(int index) => Actors.FirstOrDefault(a => a.Index == index);

        /// <summary>Runs that end a turn at bat early: three in a small game, five for teams.</summary>
        public int Mercy => Lineup == Lineup.Teams ? 5 : 3;

        /// <summary>Who is fielding: everyone not on the batting side.</summary>
        public IReadOnlyList<int> Fielders => Lineup == Lineup.Solo ? Array.Empty<int>()
            : Actors.Select(a => a.Index).Where(i => !Sides[Batting].Contains(i)).ToList();

        /// <summary>Creature <paramref name="index"/>'s centre, turn, pose and facing, as the colony draws it.</summary>
        public (Pt Position, double Rotation, string Pose, double Facing)? PoseOf(int index)
        {
            if (ActorOf(index) is not { } a) return null;
            if (a.From is { } from)
            {
                var s = Math.Min(1, a.Hop / Math.Max(a.HopTime, 0.01));
                Pt p0 = from.Centre(a.Half), p1 = a.Place.Centre(a.Half);
                var dist = Math.Sqrt(Math.Pow(p1.X - p0.X, 2) + Math.Pow(p1.Y - p0.Y, 2));
                var bulge = new Vec(from.Inward.Dx + a.Place.Inward.Dx, from.Inward.Dy + a.Place.Inward.Dy);
                var bl = Math.Sqrt(bulge.Dx * bulge.Dx + bulge.Dy * bulge.Dy);
                bulge = bl < 0.3 ? new Vec(-(p1.Y - p0.Y) / Math.Max(dist, 1), (p1.X - p0.X) / Math.Max(dist, 1)) : new Vec(bulge.Dx / bl, bulge.Dy / bl);
                var rise = Math.Min(240, dist * 0.3) * 4 * s * (1 - s);
                var turn = a.Place.Rotation - from.Rotation;
                while (turn > Math.PI) turn -= 2 * Math.PI;
                while (turn < -Math.PI) turn += 2 * Math.PI;
                return (new Pt(p0.X + (p1.X - p0.X) * s + bulge.Dx * rise, p0.Y + (p1.Y - p0.Y) * s + bulge.Dy * rise), from.Rotation + turn * s, "jump", a.Facing);
            }
            var c = a.Place.Centre(a.Half);
            var lift = a.Cheer > 0 ? Math.Abs(Math.Sin(a.Cheer * 9)) * a.Half * 0.6 : 0;
            var pose = a.Cheer > 0 ? (lift > 2 ? "jump" : "land") : a.Landed < 0.15 || a.Squat > 0 ? "land" : "idle";
            return (new Pt(c.X + a.Place.Inward.Dx * lift, c.Y + a.Place.Inward.Dy * lift), a.Place.Rotation, pose, a.Facing);
        }

        /// <summary>Where the ball is, or null while nobody can see it.</summary>
        public Pt? BallPosition
        {
            get
            {
                switch (Ball)
                {
                    case BallState.Resting r: return r.At;
                    case BallState.Held h:
                        if (ActorOf(h.By) is not { } a || PoseOf(h.By) is not { } pose) return null;
                        return new Pt(pose.Position.X + a.Place.Inward.Dx * a.Half * 0.5 + a.Place.Along.Dx * a.Facing * a.Half * 0.7,
                                      pose.Position.Y + a.Place.Inward.Dy * a.Half * 0.5 + a.Place.Along.Dy * a.Facing * a.Half * 0.7);
                    case BallState.Flying f:
                        return new Pt(f.From.X + f.Velocity.Dx * f.Clock, f.From.Y + f.Velocity.Dy * f.Clock - f.Gravity * f.Clock * f.Clock / 2);
                    default: return null;
                }
            }
        }

        /// <summary>The board: runs by side (or by player), the inning and the outs.</summary>
        public string Board(Func<int, string> name)
        {
            if (Lineup == Lineup.Solo)
                return $"{name(Batter)}: {L10n.TrCount(Hits, "hit", "hits")}, {L10n.TrCount(HomeRuns, "home run", "home runs")}";
            var scores = Lineup == Lineup.Teams
                ? $"{L10n.Tr("%@'s team", name(Sides[0][0]))} {SideRuns[0]} : {SideRuns[1]} {L10n.Tr("%@'s team", name(Sides[1][0]))}"
                : string.Join("  ", Enumerable.Range(0, Sides.Count).Select(s => $"{name(Sides[s][0])} {SideRuns[s]}"));
            return scores + "  · " + L10n.Tr("inning %d/%d, %d out", Math.Min(Inning, Innings), Innings, Outs);
        }

        private int? Slot(int index)
        {
            var k = Actors.FindIndex(a => a.Index == index);
            return k < 0 ? null : k;
        }

        // Positions

        /// <summary>Everyone to their places for the next batter: the batter to home, the pitcher to the mound, the
        /// fielders to their posts, the rest of the batting side by home, out of the way.</summary>
        private void TakePositions(bool first = false)
        {
            CurrentPhase = Phase.GettingReady;
            var side = Sides[Batting];
            var fielders = Fielders;
            Pitcher = Lineup == Lineup.Solo || fielders.Count == 0 ? null : fielders[0];
            for (int n = 0; n < fielders.Count - 1; n++) Go(fielders[n + 1], Field.Posts[n % Field.Posts.Count]);
            if (Pitcher is { } p) Go(p, Field.Mound);
            Go(Batter, Field.Home);
            var bench = 0;
            foreach (var m in side)
            {
                if (m == Batter || Bases.Any(b => b is { Ghost: false } r && r.Owner == m)) continue;
                bench++;
                Go(m, Field.Home.Shifted(bench * 46 * -FacingMound));
            }
            BatSwing = 0;
            schedule.Clear();
            var catcher = Pitcher ?? Batter;
            if (first || BallPosition is null)
                Ball = new BallState.Held(catcher);
            else if (Ball is BallState.Held held && held.By == catcher) { }
            else if (BallPosition is { } at && ActorOf(catcher) is { } c)
            {
                // Thrown back to the pitcher (or picked up by the batter, alone).
                var spot = Pitcher is null ? Field.Home : Field.Mound;
                Later(0.1, new Step.Fly(at, spot.Centre(c.Half * 1.5), 0.8, Gravity));
                Later(0.9, new Step.Hold(catcher));
            }
            Later(first ? 0.4 : 1.0, new Step.BatterUp());
        }

        /// <summary>From home, which way the mound is along home's edge.</summary>
        private double FacingMound => Field.Home.FacingToward(Field.Mound.Edge);

        private void Go(int index, Place place)
        {
            if (Slot(index) is not { } k) return;
            var a = Actors[k];
            if (a.Place == place && a.From is null) return;
            a.Hops = new() { place };
            if (a.From is null) StartHop(a);
        }

        private static void StartHop(Actor a)
        {
            if (a.Hops.Count == 0) return;
            var to = a.Hops[0];
            a.Hops.RemoveAt(0);
            var d = Math.Sqrt(Math.Pow(to.Edge.X - a.Place.Edge.X, 2) + Math.Pow(to.Edge.Y - a.Place.Edge.Y, 2));
            if (d < 4 && a.Place.Rotation == to.Rotation) { a.Place = to; return; }
            a.From = a.Place;
            a.Facing = a.Place.FacingToward(to.Edge);
            a.Place = to;
            a.Hop = 0;
            a.HopTime = HopTime(d);
        }

        /// <summary>Seconds for a hop of <paramref name="distance"/> points.</summary>
        public static double HopTime(double distance) => Math.Min(Math.Max(0.35 + distance / HopSpeed, 0.45), 1.3);

        public static double ThrowTime(double distance) => Math.Min(Math.Max(distance / ThrowSpeed, 0.3), 1.2);

        /// <summary>Seconds for <paramref name="index"/> to make every hop in <paramref name="places"/> from where it is.</summary>
        private double Hopping(int index, IEnumerable<Place> places)
        {
            if (ActorOf(index) is not { } a) return 0;
            var at = a.Place.Edge;
            var total = 0.0;
            foreach (var p in places)
            {
                total += HopTime(Math.Sqrt(Math.Pow(p.Edge.X - at.X, 2) + Math.Pow(p.Edge.Y - at.Y, 2))) + 0.05;
                at = p.Edge;
            }
            return total;
        }

        /// <summary>The throw from <paramref name="from"/> that lands at <paramref name="to"/> in <paramref name="time"/>.</summary>
        private static Vec Velocity(Pt from, Pt to, double time, double gravity)
        {
            var t = Math.Max(0.05, time);
            return new Vec((to.X - from.X) / t, (to.Y - from.Y) / t + gravity * t / 2);
        }

        private static BallState Throw(Pt from, Pt to, double time, double gravity) =>
            new BallState.Flying(from, Velocity(from, to, time, gravity), gravity, 0, time);

        private static double Dist(Pt a, Pt b) => Math.Sqrt(Math.Pow(a.X - b.X, 2) + Math.Pow(a.Y - b.Y, 2));

        // Running

        public List<Event> Update(double dt, Random rng)
        {
            var events = new List<Event>();
            if (finished) return events;
            clock += dt;
            foreach (var a in Actors)
            {
                a.Landed += dt;
                a.Squat = Math.Max(0, a.Squat - dt);
                if (a.Cheer > 0) a.Cheer = Math.Max(0, a.Cheer - dt);
                if (a.From is null) continue;
                a.Hop += dt;
                if (a.Hop >= a.HopTime)
                {
                    a.From = null;
                    a.Landed = 0;
                    StartHop(a);
                }
            }
            if (Ball is BallState.Flying f) Ball = f with { Clock = Math.Min(f.Clock + dt, f.Time) };
            BatSwing = BatSwing > 0 && BatSwing < 1 ? Math.Min(1, BatSwing + dt / 0.22) : BatSwing;
            if (CurrentPhase == Phase.Over)
            {
                finished = clock >= overUntil;
                return events;
            }
            // Facing: the batter the mound, everyone else the ball.
            if (ActorOf(Batter) is { From: null } bat && CurrentPhase != Phase.InPlay) bat.Facing = FacingMound;
            if (BallPosition is { } ballAt)
                foreach (var a in Actors)
                    if (a.From is null && (a.Index != Batter || CurrentPhase == Phase.InPlay)) a.Facing = a.Place.FacingToward(ballAt);
            while (schedule.Count > 0 && schedule[0].At <= clock)
            {
                var step = schedule[0].Step;
                schedule.RemoveAt(0);
                Perform(step, events, rng);
                if (finished) break;
            }
            return events;
        }

        /// <summary>Do <paramref name="step"/> <paramref name="seconds"/> from now, after anything already due then.</summary>
        private void Later(double seconds, Step step)
        {
            var at = clock + seconds;
            var k = schedule.FindIndex(s => s.At > at);
            schedule.Insert(k < 0 ? schedule.Count : k, (at, step));
        }

        private void Perform(Step step, List<Event> events, Random rng)
        {
            switch (step)
            {
                case Step.Hop h:
                    if (ActorOf(h.Index) is not { } a) return;
                    a.Hops = h.Places.ToList();
                    if (a.From is null) StartHop(a);
                    break;
                case Step.Fly fly: Ball = Throw(fly.From, fly.To, fly.Time, fly.Gravity); break;
                case Step.Hold hold: Ball = new BallState.Held(hold.Index); break;
                case Step.Rest rest: Ball = new BallState.Resting(rest.At); break;
                case Step.Tell tell: events.Add(tell.Event); break;
                case Step.Out o:
                    Outs++;
                    atBatOver = true;
                    events.Add(new Event.Out(o.Index, o.How));
                    break;
                case Step.Score sc:
                    RunsBy[sc.Index] = RunsBy.GetValueOrDefault(sc.Index) + 1;
                    TurnRuns++;
                    for (int s = 0; s < Sides.Count; s++) if (Sides[s].Contains(sc.Index)) { SideRuns[s]++; break; }
                    events.Add(new Event.Scored(sc.Index, string.Join("-", SideRuns)));
                    break;
                case Step.Occupy oc: Bases[oc.Base] = oc.Runner; break;
                case Step.Resolve: Resolve(events, rng); break;
                case Step.BatterUp: BatterUp(rng); break;
                case Step.SwingBat: BatSwing = 0.01; break;
                case Step.Cheer ch:
                    if (ActorOf(ch.Index) is { } who) who.Cheer = ch.Seconds;
                    break;
            }
        }

        /// <summary>Everyone is in place: the pitch (or, alone, the toss).</summary>
        private void BatterUp(Random rng)
        {
            // Still hopping into place: wait for them.
            if (Actors.Any(a => a.From is not null)) { Later(0.2, new Step.BatterUp()); return; }
            CurrentPhase = Phase.Pitching;
            if (ActorOf(Batter) is not { } b) return;
            var hands = b.Place.Centre(b.Half * 1.6);
            var swing = Outcome(rng);
            Swings++;
            double flight;
            if (Pitcher is { } p && ActorOf(p) is { } pa)
            {
                pa.Squat = 0.6;
                var from = pa.Place.Centre(pa.Half * 1.5);
                flight = 0.6;
                Later(0.6, new Step.Tell(new Event.Pitch(p)));
                Later(0.6, new Step.Fly(from, hands, flight, 150));
            }
            else
            {
                // Practice: up it goes, and down to the bat.
                flight = 0.9;
                Later(0.3, new Step.Tell(new Event.Toss(Batter)));
                Later(0.3, new Step.Fly(hands, hands, flight, 1400));
            }
            var contact = (Pitcher is null ? 0.3 : 0.6) + flight;
            pending = swing;
            Later(contact - 0.12, new Step.SwingBat());
            Later(contact, new Step.Tell(new Event.Swung(Batter, swing)));
            Later(contact, new Step.Resolve());
            CurrentPhase = Phase.Pitching;
        }

        private double Friends => Pitcher is { } p && close.TryGetValue(Batter, out var row) && row.TryGetValue(p, out var c) ? c : 0;

        /// <summary>Hit, foul or miss: kinder pitches between friends, a good mood, and luck.</summary>
        private Swing Outcome(Random rng)
        {
            var hit = (Pitcher is null ? 0.6 : 0.34) + 0.22 * Friends + 0.06 * mood + rng.Range(-0.08, 0.08);
            var roll = rng.NextDouble();
            if (roll < hit) return Swing.Hit;
            return roll < hit + (Pitcher is null ? 0 : 0.2) ? Swing.Foul : Swing.Miss;
        }

        /// <summary>The ball reaches the bat: what happens next.</summary>
        private void Resolve(List<Event> events, Random rng)
        {
            if (CurrentPhase != Phase.Pitching) { AfterPlay(events); return; }
            if (ActorOf(Batter) is not { } b) return;
            var from = b.Place.Centre(b.Half * 1.6);
            if (pending == Swing.Hit)
            {
                Hits++;
                atBatOver = true;
                CurrentPhase = Phase.InPlay;
                Hit(from, events, rng);
                return;
            }
            var back = -FacingMound;
            if (pending == Swing.Miss)
            {
                // Past the bat and away behind home, where it rolls to a stop.
                Ball = Throw(from, Field.Home.Shifted(back * 120).Centre(4), 0.4, 300);
            }
            else
            {
                var behind = Field.Home.Shifted(back * 260).Centre(4);
                var to = Field.IsInside(behind) ? behind : Field.Home.Centre(140);
                Ball = Throw(from, to, 1.0, Gravity);
            }
            if (pending == Swing.Miss || Strikes < 2)
            {
                Strikes++;
                events.Add(new Event.Strike(Batter, Strikes));
            }
            if (Strikes >= 3 && Lineup != Lineup.Solo) Later(0.5, new Step.Out(Batter, "struck out"));
            CurrentPhase = Phase.InPlay;
            Later(1.0, new Step.Resolve());
        }

        /// <summary>A hit ball: a home run out over the top, or an arc to some edge, fielded.</summary>
        private void Hit(Pt from, List<Event> events, Random rng)
        {
            var power = 0.13 + 0.08 * Friends + 0.04 * mood;
            if (rng.NextDouble() < power) { HomeRun(from, events, rng); return; }
            if (Field.Landing(Field.Home.Edge, 260, rng) is not { } landing) { HomeRun(from, events, rng); return; }
            var to = landing.Centre(Props.BallRadius);
            var dist = Dist(to, from);
            // The highest arc that stays on screen, or a line drive.
            double time = 0, g = Gravity;
            foreach (var t in new[] { 1.7, 1.45, 1.2, 1.0, 0.8 })
            {
                var tt = Math.Min(t, Math.Max(0.7, dist / 500));
                var v = Velocity(from, to, tt, g);
                var onScreen = Enumerable.Range(1, 11).All(k =>
                {
                    var s = tt * k / 12;
                    return Field.IsInside(new Pt(from.X + v.Dx * s, from.Y + v.Dy * s - g * s * s / 2));
                });
                if (onScreen) { time = tt; break; }
            }
            if (time == 0) { time = Math.Max(0.5, dist / 900); g = 0; }
            Ball = Throw(from, to, time, g);

            if (Lineup == Lineup.Solo) { FetchAlone(landing, time); return; }

            // The fielder who gets there first goes for it.
            var pool = Fielders;
            if (pool.Count == 0) return;
            var catcher = pool.OrderBy(f => Hopping(f, new[] { landing })).First();
            var arrive = 0.25 + Hopping(catcher, new[] { landing });
            Later(0.25, new Step.Hop(catcher, new[] { landing }));
            var caught = arrive <= time + 0.05 && rng.NextDouble() < 0.72;
            if (caught)
            {
                Later(time, new Step.Hold(catcher));
                Later(time, new Step.Tell(new Event.Caught(catcher)));
                Later(time + 0.3, new Step.Out(Batter, "caught"));
                Later(time + 1.0, new Step.Resolve());
                // The batter sets off anyway, and turns back.
                Later(0.15, new Step.Hop(Batter, new[] { Field.Bases[0] }));
                Later(time + 0.6, new Step.Hop(Batter, new[] { Field.Home }));
                return;
            }
            var pickup = Math.Max(arrive, time) + 0.3;
            if (arrive <= time + 0.05)
            {
                // There in time, and it bounces off its head.
                Later(time, new Step.Tell(new Event.Fumble(catcher)));
                pickup += 0.8;
            }
            Later(time, new Step.Rest(to));
            Later(pickup, new Step.Hold(catcher));
            Later(pickup - 0.3, new Step.Tell(new Event.Fetch(catcher)));
            Run(catcher, landing, pickup, rng);
        }

        /// <summary>The batter runs as far as it dares before the throw comes in; the others go as far.</summary>
        private void Run(int fielder, Place landing, double pickup, Random rng)
        {
            var catcherAt = landing.Centre(ActorOf(fielder)?.Half ?? 20);
            var courage = rng.Range(-0.3, 0.5);
            var route = Field.Bases.Append(Field.Home).ToArray();
            var reach = 1;
            while (reach < 4)
            {
                var mine = 0.15 + Hopping(Batter, route.Take(reach + 1));
                var ahead = route[reach];
                var theirs = pickup + ThrowTime(Dist(ahead.Edge, catcherAt));
                if (mine + courage < theirs) reach++; else break;
            }
            var target = route[reach - 1];
            var arrive = 0.15 + Hopping(Batter, route.Take(reach));
            var throwArrives = pickup + ThrowTime(Dist(target.Edge, catcherAt));
            var safe = arrive < throwArrives;
            Later(0.15, new Step.Hop(Batter, route.Take(reach).ToArray()));
            for (int b = 0; b < reach; b++) Later(0.15 + Hopping(Batter, route.Take(b)), new Step.Tell(new Event.Runs(Batter, b + 1)));
            // The throw, to whoever waits at that base (or straight there).
            var others = Fielders.Where(f => f != fielder).ToList();
            int? receiver = others.Count == 0 ? null : others.OrderBy(f => Dist(ActorOf(f)!.Place.Edge, target.Edge)).First();
            if (receiver is { } r) Later(Math.Max(0.2, throwArrives - 1.2), new Step.Hop(r, new[] { Beside(target) }));
            Later(pickup, new Step.Fly(catcherAt, target.Centre(30), throwArrives - pickup, Gravity));
            Later(throwArrives, receiver is { } rr ? new Step.Hold(rr) : new Step.Rest(target.Centre(8)));
            // The runners already on base go as far as the batter gets safely.
            AdvanceRunners(safe ? reach : reach - 1, 0.15);
            if (reach == 4 && safe)
            {
                Later(arrive, new Step.Score(Batter));
                Later(arrive, new Step.Cheer(Batter, 1.5));
            }
            else if (safe)
            {
                Later(arrive, new Step.Tell(new Event.Safe(Batter, reach)));
                Later(arrive, new Step.Occupy(reach - 1, new Runner(Batter, false)));
            }
            else
            {
                Later(throwArrives, new Step.Out(Batter, reach == 4 ? "at home" : new[] { "at first", "at second", "at third" }[reach - 1]));
                Later(throwArrives + 0.4, new Step.Hop(Batter, new[] { Field.Home }));
            }
            Later(Math.Max(arrive, throwArrives) + 0.8, new Step.Resolve());
        }

        /// <summary>Next to a base, where a fielder takes the throw.</summary>
        private static Place Beside(Place b) => b.Shifted(34);

        /// <summary>The runners on base move up <paramref name="count"/> bases; past third they score.</summary>
        private void AdvanceRunners(int count, double start)
        {
            if (count <= 0) return;
            var route = Field.Bases.Append(Field.Home).ToArray();
            var moved = new Runner?[3];
            for (int b = 2; b >= 0; b--)
            {
                if (Bases[b] is not { } runner) continue;
                var to = b + count;
                var path = route[(b + 1)..(Math.Min(3, to) + 1)];
                var arrive = runner.Ghost ? 0.6 : Hopping(runner.Owner, path);
                if (!runner.Ghost) Later(start, new Step.Hop(runner.Owner, path));
                if (to >= 3)
                {
                    Later(start + arrive, new Step.Score(runner.Owner));
                    if (!runner.Ghost) Later(start + arrive + 0.3, new Step.Hop(runner.Owner, new[] { BenchSpot(runner.Owner) }));
                }
                else
                {
                    moved[to] = runner;
                }
                Bases[b] = null;
            }
            for (int b = 0; b < 3; b++) if (moved[b] is not null) Later(start + 0.6, new Step.Occupy(b, moved[b]));
        }

        /// <summary>A place by home for a batter waiting its turn.</summary>
        private Place BenchSpot(int index)
        {
            var n = Array.IndexOf(Sides[Batting], index) + 1;
            return Field.Home.Shifted(Math.Max(1, n) * 46 * -FacingMound);
        }

        private void HomeRun(Pt from, List<Event> events, Random rng)
        {
            HomeRuns++;
            // Up and out through the top of the screen, somewhere over the field.
            var outside = new Pt(from.X + FacingMound * rng.Range(100, 500), Field.Top + 200);
            const double time = 1.3;
            Ball = Throw(from, outside, time, Gravity);
            LastHomeRun = new Pt(from.X + (outside.X - from.X) * 0.85, Field.Top - 10);
            var runs = 1 + Bases.Count(b => b is not null);
            events.Add(new Event.HomeRun(Batter, runs));
            if (Lineup == Lineup.Solo)
            {
                Later(0.3, new Step.Cheer(Batter, 2));
                Later(2.6, new Step.Resolve());
                return;
            }
            // A lap of honour round every base, the runners ahead of it.
            AdvanceRunners(4, 0.3);
            var route = Field.Bases.Append(Field.Home).ToArray();
            Later(0.4, new Step.Hop(Batter, route));
            var lap = 0.4 + Hopping(Batter, route);
            Later(lap, new Step.Score(Batter));
            Later(lap + 0.1, new Step.Tell(new Event.Safe(Batter, 4)));
            Later(lap + 0.1, new Step.Cheer(Batter, 1.5));
            Later(lap + 1.8, new Step.Resolve());
        }

        /// <summary>Alone: off it goes to fetch the ball, and back to home with it.</summary>
        private void FetchAlone(Place landing, double time)
        {
            Later(time, new Step.Rest(landing.Centre(Props.BallRadius)));
            var there = time + 0.2 + Hopping(Batter, new[] { landing });
            Later(time + 0.2, new Step.Hop(Batter, new[] { landing }));
            Later(time + 0.2, new Step.Tell(new Event.Fetch(Batter)));
            Later(there, new Step.Hold(Batter));
            Later(there + 0.1, new Step.Hop(Batter, new[] { Field.Home }));
            Later(there + 0.2 + HopTime(Dist(landing.Edge, Field.Home.Edge)) + 0.5, new Step.Resolve());
        }

        /// <summary>The play is over: count the outs, change sides, or the next batter.</summary>
        private void AfterPlay(List<Event> events)
        {
            if (Lineup == Lineup.Solo)
            {
                if (Swings >= PracticeSwings) { End(events); return; }
                TakePositions();
                return;
            }
            var limit = Lineup == Lineup.Teams ? 3 : 2;
            if (Outs >= limit || TurnRuns >= Mercy)
            {
                Outs = 0;
                TurnRuns = 0;
                Bases = new Runner?[3];
                Batting++;
                if (Batting >= Sides.Count)
                {
                    Batting = 0;
                    Inning++;
                    if (Inning > Innings) { End(events); return; }
                }
                events.Add(new Event.SidesChange(Inning, Sides[Batting]));
                atBatOver = true;
            }
            if (atBatOver)
            {
                atBatOver = false;
                Strikes = 0;
                Batter = NextBatter(events);
            }
            TakePositions();
        }

        /// <summary>Next in the batting order; a runner who is the only one left leaves a ghost on its base.</summary>
        private int NextBatter(List<Event> events)
        {
            var side = Sides[Batting];
            for (int step = 0; step < side.Length; step++)
            {
                var m = side[(next[Batting] + step) % side.Length];
                if (!Bases.Any(b => b is { Ghost: false } r && r.Owner == m))
                {
                    next[Batting] = (next[Batting] + step + 1) % side.Length;
                    return m;
                }
            }
            // Everyone is on base: the one furthest round runs home to bat, leaving a ghost.
            var at = 0;
            for (int b = 2; b >= 0; b--) if (Bases[b] is { Ghost: false }) { at = b; break; }
            var owner = Bases[at]?.Owner ?? side[0];
            Bases[at] = new Runner(owner, true);
            events.Add(new Event.Ghost(owner, at + 1));
            return owner;
        }

        private void End(List<Event> events)
        {
            CurrentPhase = Phase.Over;
            events.Add(new Event.Over());
            Ball = new BallState.Gone();
            var won = Winners;
            foreach (var a in Actors) if (won.Contains(a.Index) || Lineup == Lineup.Solo) a.Cheer = 2.4;
            schedule.Clear();
            overUntil = clock + 2.6;
        }

        /// <summary>Who won: the side with the most runs, or nobody when it is level (or alone).</summary>
        public IReadOnlyList<int> Winners
        {
            get
            {
                if (Lineup == Lineup.Solo || SideRuns.Length == 0) return Array.Empty<int>();
                var best = SideRuns.Max();
                return SideRuns.Count(r => r == best) == 1 ? Sides[Array.IndexOf(SideRuns, best)] : Array.Empty<int>();
            }
        }
    }
}

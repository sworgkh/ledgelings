namespace Ledgelings.Core;

public static partial class Plays
{
    /// <summary>Which feature a model call for this game is priced under.</summary>
    public static Spend.Purpose SpendPurpose(this Kind kind) => kind switch
    {
        Kind.Soccer or Kind.Baseball => Spend.Purpose.BallGames,
        Kind.Surf => Spend.Purpose.Surfing,
        _ => Spend.Purpose.Plays,
    };

    /// <summary>
    /// Surfing (SPEC §7.10), the Mac's <c>Plays+Surf.swift</c>: the tide comes in along the bottom edge of the screen, a
    /// band of see-through water a little deeper than a creature is tall, and waves roll along it from one end of the floor
    /// to the other. Everyone who plays paddles out on its own board to a spot near the end the waves come from and waits,
    /// bobbing. As a wave's face reaches it, it catches the wave (<see cref="CatchChance"/>) or lets it roll by underneath;
    /// a rider stands up and rides the face, carving, and now and then tries a trick, a hop or a spin. A ride scores
    /// <see cref="PointsPerSecond"/> while it lasts plus each trick landed, banked when the rider kicks out at the far end;
    /// a wipe-out (a trick gone wrong, or just bad luck) splashes, tumbles the rider under, loses that ride's points, and
    /// it paddles back out. After <see cref="Waves"/> waves, or once <see cref="Length"/> seconds are up, the last wave
    /// rides out and the tide goes out again, setting everyone down on the floor. The best score wins; one surfing alone
    /// just surfs.
    ///
    /// Pure, like the other games: the colony asks where each rider and board is, frame by frame, and draws them and the
    /// water (<see cref="Surface"/>).
    /// </summary>
    public sealed partial class Surf
    {
        public enum Phase { TideIn, Session, TideOut, Over }
        public enum Trick { Hop, Spin }

        public abstract record Event
        {
            public sealed record TideIn : Event;
            /// <summary>Wave <c>Number</c> (from 1) starts rolling in, <c>Way</c> +1 toward growing x.</summary>
            public sealed record Wave(int Number, double Way) : Event;
            public sealed record Caught(int By) : Event;
            /// <summary>The wave rolled by under it.</summary>
            public sealed record Missed(int By) : Event;
            /// <summary>A trick landed (the Mac's <c>.trick</c>).</summary>
            public sealed record Landed(int By, Trick Trick) : Event;
            public sealed record Wipeout(int By, Pt At) : Event;
            /// <summary>Rode it to the end: <c>Points</c> for the ride, banked.</summary>
            public sealed record KickOut(int By, int Points) : Event;
            /// <summary>Back out where it waits for the next one.</summary>
            public sealed record Back(int By) : Event;
            public sealed record TideOut : Event;
            /// <summary>The best score: one winner, several for a tie; empty alone.</summary>
            public sealed record Won(IReadOnlyList<int> By) : Event;
            public sealed record Over : Event;
        }

        public abstract record State
        {
            public sealed record Paddling(double To) : State;
            public sealed record Waiting : State;
            public sealed record Riding : State;
            /// <summary>Trying a trick (the Mac's <c>.trick</c>), <c>Left</c> seconds still to go.</summary>
            public sealed record Tricking(Trick Trick, double Left) : State;
            public sealed record Tumbling(double Left) : State;
            /// <summary>Waiting for the tide to go out.</summary>
            public sealed record Done : State;
        }

        public sealed class Rider
        {
            public int Index { get; }
            public double Half { get; }
            /// <summary>Where it waits for a wave.</summary>
            public double Lineup { get; }
            public double X { get; internal set; }
            public double Y { get; internal set; }
            public double Rotation { get; internal set; }
            public double Facing { get; internal set; } = 1;
            public string Pose { get; internal set; } = "idle";
            public State State { get; internal set; }
            public int Score { get; internal set; }
            public int Rides { get; internal set; }
            public int Wipeouts { get; internal set; }
            /// <summary>Waves it let go by because two were on them already.</summary>
            public int GaveWay { get; internal set; }
            public int Tricks { get; internal set; }
            /// <summary>The board: where its middle is, its turn, and whether it is under the rider's feet.</summary>
            public Pt Board { get; internal set; } = Pt.Zero;
            public double BoardRotation { get; internal set; }
            public bool OnBoard { get; internal set; } = true;
            /// <summary>The ride going on: how long, and its tricks' points.</summary>
            internal double RideTime;
            internal int RidePoints, RideBonus;
            internal double Lift, Spin;
            internal readonly double Bob;
            /// <summary>How far down the face it rides, 0 at the crest, 1 at the foot: each rider its own line.</summary>
            internal double Pocket;

            internal Rider(int index, double half, double lineup, double x, State state, double bob, double pocket)
            {
                Index = index; Half = half; Lineup = lineup; X = x; State = state; Bob = bob; Pocket = pocket;
            }

            public bool IsRiding => State is State.Riding or State.Tricking;
        }

        /// <summary>A wave rolling along: its crest's x, and which one it is (the Mac's <c>Wave</c>).</summary>
        public sealed record Swell(double Crest, int Number);

        public const double TideTime = 1.5;
        public const double WaveGap = 2.5;
        /// <summary>Points per second: the wave, and a creature paddling.</summary>
        public const double WaveSpeed = 170;
        public const double PaddleSpeed = 140;
        public const double CatchChance = 0.75;
        /// <summary>Riders one wave carries: one low on the face, one up by the curl. The rest wait their turn.</summary>
        public const int PerWave = 2;
        /// <summary>Where they ride, down the face from the crest: the first to catch it, and the second.</summary>
        public static readonly IReadOnlyList<double> Pockets = new[] { 0.62, 0.18 };
        /// <summary>Chances per second of riding: trying a trick (after the first second), wiping out.</summary>
        public const double TrickRate = 0.35;
        public const double WipeRate = 0.03;
        /// <summary>A trick that goes wrong is a wipe-out.</summary>
        public const double TrickFailChance = 0.2;
        public const double TrickTime = 0.7;
        public const double TumbleTime = 1.4;
        public const double PointsPerSecond = 10.0;
        public static readonly IReadOnlyDictionary<Trick, int> TrickPoints = new Dictionary<Trick, int> { [Trick.Hop] = 20, [Trick.Spin] = 35 };
        /// <summary>The steepest a board leans riding, either way: a ride, not a climb.</summary>
        public const double Steepest = 0.42;
        /// <summary>Waiting on a wave that never comes (a rider who cannot get back): it starts without it.</summary>
        public const double WaitAtMost = 8.0;

        public double FloorY { get; }
        public double From { get; }
        public double To { get; }
        /// <summary>The tallest a wave stands over the calm water, and the calm water's depth.</summary>
        public double Height { get; }
        public double Depth { get; }
        /// <summary>+1: the waves roll toward growing x.</summary>
        public double Way { get; }
        public int Waves { get; }
        public double Length { get; }
        public Phase CurrentPhase { get; private set; } = Phase.TideIn;
        private readonly List<Rider> riders;
        public IReadOnlyList<Rider> Riders => riders;
        public Swell? Wave { get; private set; }
        public int WavesRolled { get; private set; }
        /// <summary>How far in the tide is, 0 (dry) to 1.</summary>
        public double Tide { get; private set; }
        public double Clock { get; private set; }
        private double phaseClock;
        private double nextWaveAt = TideTime + 1.0;
        private readonly HashSet<int> scoring = new();

        /// <summary>A session on a floor at <paramref name="floorY"/> running <paramref name="from"/> to <paramref name="to"/>,
        /// for <paramref name="players"/> (each its half size and where it stands). <paramref name="waveHeight"/> and
        /// <paramref name="depth"/> in points; <paramref name="waves"/> waves at most, <paramref name="length"/> seconds at most.</summary>
        public Surf(IReadOnlyList<int> players, IReadOnlyDictionary<int, double> halves, IReadOnlyDictionary<int, double> at,
                    double floorY, double from, double to, double waveHeight, double depth, int waves, double length, Random rng)
        {
            FloorY = floorY;
            From = from;
            To = to;
            Height = Math.Max(20, waveHeight);
            Depth = Math.Max(8, depth);
            Waves = Math.Max(1, waves);
            Length = Math.Max(10, length);
            var way = rng.Coin() ? 1.0 : -1.0;
            Way = way;
            var start = way > 0 ? from : to;
            var room = (to - from) * 0.3;
            var n = players.Count;
            var bobs = players.Select(_ => rng.Range(0, 2 * Math.PI)).ToList();
            riders = players.Select((p, k) =>
            {
                var line = start + way * room * (0.25 + 0.75 * (k + 0.5) / Math.Max(n, 1));
                return new Rider(p, halves.TryGetValue(p, out var h) ? h : 20, line, at.TryGetValue(p, out var x) ? x : line,
                                 new State.Paddling(line), bobs[k], Pockets[0]);
            }).ToList();
            foreach (var r in riders) Place(r);
        }

        public bool IsFinished => CurrentPhase == Phase.Over;
        public Rider? RiderOf(int index) => riders.FirstOrDefault(r => r.Index == index);
        public IReadOnlyDictionary<int, int> Scores => riders.ToDictionary(r => r.Index, r => r.Score);

        /// <summary>The best score's riders; empty for one surfing alone.</summary>
        public IReadOnlyList<int> Winners
        {
            get
            {
                if (riders.Count <= 1) return Array.Empty<int>();
                var best = riders.Max(r => r.Score);
                return riders.Where(r => r.Score == best).Select(r => r.Index).ToList();
            }
        }

        /// <summary>The scoreboard: "SURF Blocky 120 · Pip 85", the best first.</summary>
        public string Board(Func<int, string> name) =>
            L10n.Tr("SURF") + " " + string.Join(" · ", riders.OrderByDescending(r => r.Score).Select(r => $"{name(r.Index)} {r.Score}"));

        // MARK: The water

        /// <summary>The front of a wave (ahead of the crest) and its back, in points.</summary>
        public double FaceWidth => Height * 1.6;
        public double BackWidth => Height * 2.8;

        /// <summary>How far the wave lifts the water at <paramref name="x"/>, 0 off it.</summary>
        public double LiftAt(double x)
        {
            if (Wave is not { } wave) return 0;
            var d = (x - wave.Crest) * Way;
            var w = d >= 0 ? FaceWidth : BackWidth;
            if (Math.Abs(d) >= w) return 0;
            // The face hollow, steep under the crest and flattening to its foot; the back a long gentle slope.
            var shape = d >= 0 ? Math.Pow(1 - d / w, 3) : 0.5 + 0.5 * Math.Cos(Math.PI * (d / w));
            return Height * shape * Tide;
        }

        /// <summary>The water's top at <paramref name="x"/>, in screen points.</summary>
        public double Surface(double x) => FloorY + Depth * Tide + LiftAt(x);

        /// <summary>The water's slope at <paramref name="x"/>, as an angle (positive rising toward growing x).</summary>
        public double Slope(double x) => Math.Atan2(Surface(x + 2) - Surface(x - 2), 4);

        /// <summary>The far end: a wave rides out there.</summary>
        internal double FarEnd => Way > 0 ? To : From;
        internal double NearEnd => Way > 0 ? From : To;

        // MARK: Running

        public List<Event> Update(double dt, Random rng)
        {
            Clock += dt;
            phaseClock += dt;
            var events = new List<Event>();
            switch (CurrentPhase)
            {
                case Phase.TideIn:
                    if (phaseClock <= dt) events.Add(new Event.TideIn());
                    Tide = Math.Min(1, phaseClock / TideTime);
                    if (Tide >= 1) { CurrentPhase = Phase.Session; phaseClock = 0; }
                    break;
                case Phase.Session:
                {
                    Tide = 1;
                    RollWave(dt);
                    var timeUp = Clock >= TideTime + Length;
                    if (Wave is null && (WavesRolled >= Waves || timeUp))
                    {
                        // Nobody still under: the tide goes out where they are.
                        if (riders.All(r => r.State is not State.Tumbling))
                        {
                            foreach (var r in riders) r.State = new State.Done();
                            CurrentPhase = Phase.TideOut;
                            phaseClock = 0;
                            events.Add(new Event.TideOut());
                            events.Add(new Event.Won(Winners));
                        }
                    }
                    else if (Wave is null && Clock >= nextWaveAt
                             && (riders.All(r => r.State is State.Waiting) || Clock >= nextWaveAt + WaitAtMost))
                    {
                        WavesRolled += 1;
                        Wave = new Swell(NearEnd - Way * BackWidth, WavesRolled);
                        events.Add(new Event.Wave(WavesRolled, Way));
                    }
                    break;
                }
                case Phase.TideOut:
                    Tide = Math.Max(0, 1 - phaseClock / TideTime);
                    if (Tide <= 0) { CurrentPhase = Phase.Over; events.Add(new Event.Over()); }
                    break;
                case Phase.Over:
                    break;
            }
            foreach (var r in riders) Step(r, dt, events, rng);
            return events;
        }

        private void RollWave(double dt)
        {
            if (Wave is not { } w) return;
            w = w with { Crest = w.Crest + Way * WaveSpeed * dt };
            Wave = w;
            // Gone past the far end, its back and all.
            if ((w.Crest - FarEnd) * Way > BackWidth)
            {
                Wave = null;
                nextWaveAt = Clock + WaveGap;
            }
        }

        private void Step(Rider r, double dt, List<Event> events, Random rng)
        {
            switch (r.State)
            {
                case State.Paddling paddling:
                {
                    if (CurrentPhase == Phase.TideIn) break;
                    var to = paddling.To;
                    var gap = to - r.X;
                    var move = Math.Min(Math.Abs(gap), PaddleSpeed * dt);
                    r.Facing = gap >= 0 ? 1 : -1;
                    r.X += gap >= 0 ? move : -move;
                    if (Math.Abs(to - r.X) < 0.5)
                    {
                        r.X = to;
                        r.State = new State.Waiting();
                        r.Facing = Way;
                        events.Add(new Event.Back(r.Index));
                    }
                    break;
                }
                case State.Waiting:
                {
                    if (Wave is not { } w) break;
                    var d = (r.X - w.Crest) * Way;
                    // The face reaches it: on it, or under it rolls.
                    if (d > 0 && d < FaceWidth * 0.5 && !scoring.Contains(r.Index) && (w.Crest - NearEnd) * Way > -BackWidth * 0.2)
                    {
                        scoring.Add(r.Index);
                        var onIt = riders.Count(x => x.IsRiding);
                        if (onIt < PerWave && rng.NextDouble() < CatchChance)
                        {
                            r.Pocket = Pockets[Math.Min(onIt, Pockets.Count - 1)];
                            r.State = new State.Riding();
                            r.RideTime = 0; r.RidePoints = 0; r.RideBonus = 0;
                            r.Rides += 1;
                            r.Facing = Way;
                            events.Add(new Event.Caught(r.Index));
                        }
                        else
                        {
                            events.Add(new Event.Missed(r.Index));
                        }
                    }
                    if (Wave is null || d < -BackWidth) scoring.Remove(r.Index);
                    break;
                }
                case State.Riding:
                {
                    if (Wave is not { } w) { KickOut(r, events); break; }
                    r.RideTime += dt;
                    r.RidePoints = (int)(r.RideTime * PointsPerSecond);
                    // Carving up and down the face, a little ahead of the crest.
                    r.X = w.Crest + Way * FaceWidth * (r.Pocket + 0.12 * Math.Sin(r.RideTime * 2.2));
                    if ((r.X - FarEnd) * Way >= 0) { r.X = FarEnd; KickOut(r, events); break; }
                    if (rng.NextDouble() < WipeRate * dt)
                        WipeOut(r, events);
                    else if (r.RideTime > 1 && rng.NextDouble() < TrickRate * dt)
                        r.State = new State.Tricking(rng.Coin() ? Trick.Hop : Trick.Spin, TrickTime);
                    break;
                }
                case State.Tricking trying:
                {
                    if (Wave is not { } w) { r.Lift = 0; r.Spin = 0; KickOut(r, events); break; }
                    var (trick, left) = (trying.Trick, trying.Left);
                    r.RideTime += dt;
                    r.X = w.Crest + Way * FaceWidth * (r.Pocket + 0.12 * Math.Sin(r.RideTime * 2.2));
                    if ((r.X - FarEnd) * Way >= 0) { r.X = FarEnd; r.Lift = 0; r.Spin = 0; KickOut(r, events); break; }
                    var p = 1 - Math.Max(0, left - dt) / TrickTime;
                    r.Lift = r.Half * (trick == Trick.Hop ? 1.6 : 0.8) * Math.Sin(Math.PI * p);
                    r.Spin = trick == Trick.Spin ? -Way * 2 * Math.PI * p : 0;
                    if (left - dt > 0) { r.State = new State.Tricking(trick, left - dt); break; }
                    r.Lift = 0; r.Spin = 0;
                    if (rng.NextDouble() < TrickFailChance)
                    {
                        WipeOut(r, events);
                    }
                    else
                    {
                        r.RideBonus += TrickPoints[trick];
                        r.Tricks += 1;
                        r.State = new State.Riding();
                        events.Add(new Event.Landed(r.Index, trick));
                    }
                    break;
                }
                case State.Tumbling tumbling:
                {
                    var left = tumbling.Left;
                    // Rolled under and carried a little way by the wave, slowing.
                    r.X += Way * WaveSpeed * 0.4 * (left / TumbleTime) * dt;
                    r.X = Math.Min(Math.Max(r.X, From), To);
                    r.Spin -= Way * 7 * dt;
                    if (left - dt > 0) { r.State = new State.Tumbling(left - dt); break; }
                    r.Spin = 0;
                    r.OnBoard = true;
                    r.State = new State.Paddling(r.Lineup);
                    break;
                }
                case State.Done:
                    break;
            }
            Place(r);
        }

        private void KickOut(Rider r, List<Event> events)
        {
            var points = r.RidePoints + r.RideBonus;
            r.Score += points;
            r.Lift = 0; r.Spin = 0;
            r.State = CurrentPhase == Phase.Session && WavesRolled < Waves && Clock < TideTime + Length
                ? new State.Paddling(r.Lineup) : new State.Paddling(r.X);
            events.Add(new Event.KickOut(r.Index, points));
        }

        private void WipeOut(Rider r, List<Event> events)
        {
            r.Wipeouts += 1;
            r.RidePoints = 0; r.RideBonus = 0;
            r.Lift = 0;
            r.OnBoard = false;
            r.State = new State.Tumbling(TumbleTime);
            events.Add(new Event.Wipeout(r.Index, new Pt(r.X, Surface(r.X))));
        }

        /// <summary>Where rider <paramref name="r"/> and its board are drawn, from its state and the water.</summary>
        private void Place(Rider r)
        {
            var water = Surface(r.X);
            var thick = r.Half * 0.25;
            var angle = Math.Min(Math.Max(Slope(r.X), -Steepest), Steepest);
            if (r.State is State.Tumbling tumbling)
            {
                // Under the water's top, rolling; the board bobs where it was lost.
                var sink = r.Half * 0.6 * Math.Sin(Math.PI * Math.Min(1, (TumbleTime - tumbling.Left) / TumbleTime));
                r.Y = water - sink;
                r.Rotation = r.Spin;
                r.Pose = "jump";
                r.Board = new Pt(r.X - Way * r.Half * 1.6, water + thick);
                r.BoardRotation = Math.Sin(Clock * 5) * 0.5;
                return;
            }
            var bob = r.State is State.Waiting or State.Done ? Math.Sin(Clock * 2.4 + r.Bob) * 1.5 * Tide : 0;
            var floating = water + thick + bob;
            // On the floor when the tide is out.
            var onFloor = FloorY + thick * 2;
            var level = Math.Max(floating, onFloor);
            r.Board = new Pt(r.X, level - thick + r.Lift);
            r.BoardRotation = r.IsRiding ? angle : angle * 0.5;
            r.Rotation = (r.IsRiding ? angle : angle * 0.5) + r.Spin;
            var upDy = Math.Cos(r.Rotation);
            r.Y = r.Board.Y + thick + r.Half * upDy;
            r.Pose = r.State switch
            {
                State.Paddling => "walk",
                State.Tricking => "jump",
                _ => "idle",
            };
        }
    }
}

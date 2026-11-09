namespace Ledgelings.Core;

/// <summary>
/// Scuba diving (SPEC §7.19): started by hand only, never on its own. Water rises from the bottom edge to cover a
/// share of the screen; a few creatures gear up (a mask and a tank), jump in with a splash and swim among fish, a
/// jellyfish, a crab, a turtle and an octopus, coming up for air now and then; when the time is up the water drains
/// and they climb out dripping. Stop activity clears it at once.
///
/// The sea life is not characters: it says nothing and has no persona. It reacts to the divers (fish scatter, the
/// crab raises its claws, the octopus inks and jets off) and the divers react to it (<see cref="Event"/>), which is
/// what they talk about and what lands in their pair's memory.
///
/// Pure: global points, y up, stepped by <see cref="Update"/>. The macOS app's <c>Dive.swift</c>.
/// </summary>
public sealed partial class Dive
{
    public enum Phase
    {
        /// <summary>The water coming up; the divers gear up meanwhile.</summary>
        Rising,
        On,
        /// <summary>Time is up: the water going down, the divers going down with it.</summary>
        Draining,
        /// <summary>Dry again: the colony lets the divers go.</summary>
        Over,
    }

    /// <summary>The kinds of sea life. Their sheet frames are named after these (<see cref="DiveLives.Code"/>).</summary>
    public enum Life { FishA, FishB, FishC, Jelly, Crab, Turtle, Octopus }

    public static IReadOnlyList<Life> AllLives { get; } = Enum.GetValues<Life>();

    /// <summary>One animal.</summary>
    public sealed class Critter
    {
        public Life Kind { get; set; }
        /// <summary>Which pool (monitor) it lives in.</summary>
        public int Pool { get; set; }
        public Pt Position { get; set; }
        public Vec Velocity { get; set; }
        /// <summary>The fish swim in schools; -1 for everyone else.</summary>
        public int School { get; set; }
        public bool FacingRight { get; set; }
        /// <summary>Seconds into its swimming, for its two frames.</summary>
        public double Time { get; set; }
        /// <summary>Frightened for this many more seconds: fleeing, claws up, inking.</summary>
        public double Scared { get; set; }
        /// <summary>Where it wanders about: the crab's and the octopus's patch of floor.</summary>
        public double Home { get; set; }
    }

    /// <summary>An air bubble rising to the surface.</summary>
    public sealed class Bubble
    {
        public Pt Position { get; set; }
        /// <summary>0, 1 or 2: small, middle, big.</summary>
        public int Size { get; set; }
        public double Rise { get; set; }
        public double Wobble { get; set; }
    }

    /// <summary>A strand of seaweed on the floor.</summary>
    public sealed class Weed
    {
        public int Pool { get; set; }
        public double X { get; set; }
        /// <summary>Its height, in sheet pixels.</summary>
        public int Height { get; set; }
        public double Phase { get; set; }
    }

    public enum DiverState
    {
        /// <summary>Putting the gear on, standing where it was, until <see cref="Diver.Until"/>.</summary>
        Gearing,
        /// <summary>In the air over the water, <see cref="Diver.From"/> to <see cref="Diver.To"/>, starting at
        /// <see cref="Diver.Start"/>, for <see cref="Diver.Duration"/>.</summary>
        Leaping,
        Swimming,
        /// <summary>At the surface, getting its breath, until <see cref="Diver.Until"/>.</summary>
        Breathing,
        /// <summary>Going down with the draining water.</summary>
        Settling,
    }

    public sealed class Diver
    {
        /// <summary>The creature's index in the colony.</summary>
        public int Index { get; set; }
        public int Pool { get; set; }
        public DiverState State { get; set; }
        /// <summary>Gearing and breathing: until when, on the dive's clock.</summary>
        public double Until { get; set; }
        /// <summary>Leaping: from where, to where, from when and for how long.</summary>
        public Pt From { get; set; }
        public Pt To { get; set; }
        public double Start { get; set; }
        public double Duration { get; set; }
        public Pt Position { get; set; }
        public Vec Velocity { get; set; } = Vec.Zero;
        public Pt Target { get; set; }
        public bool FacingRight { get; set; }
        /// <summary>When it next needs air.</summary>
        public double NextAir { get; set; }
        public double NextBubble { get; set; }
        /// <summary>When it last saw each kind, so it points once a while, not every frame.</summary>
        public Dictionary<Life, double> Saw { get; } = new();
        public double LastScatter { get; set; } = -100;
        /// <summary>How big its body is, in points (half), to keep it inside the water.</summary>
        public double Half { get; set; }

        public bool IsUnder => State is DiverState.Swimming or DiverState.Settling;
    }

    public enum EventKind
    {
        Splash,
        Sees,
        /// <summary>The fish scattered round it.</summary>
        Scattered,
        /// <summary>The octopus gave it a fright.</summary>
        Startled,
        Surfaced,
        /// <summary>The water has filled; the dive is on.</summary>
        Filled,
        Drained,
    }

    /// <summary>What happened this step, for lines, sounds and memory. <c>Diver</c>: the diver's creature index (-1 for
    /// none); <c>What</c>: what it sees; <c>At</c>: where a splash was.</summary>
    public sealed record Event(EventKind Kind, int Diver = -1, Life? What = null, Pt? At = null);

    /// <summary>Seconds the water takes to come up, and to go down.</summary>
    public const double RiseSeconds = 2.5;
    public const double DrainSeconds = 2.5;
    /// <summary>Seconds between one diver jumping in and the next.</summary>
    public const double JumpGap = 0.45;
    public const double LeapSeconds = 0.8;
    /// <summary>A diver needs air every so often (seconds), and stays up this long.</summary>
    public static readonly (double Low, double High) AirEvery = (16.0, 32.0);
    public const double BreathSeconds = 1.6;
    /// <summary>How near a diver comes to see something, or frighten it, in points.</summary>
    public const double SeeRadius = 110;
    public const double ScareRadius = 70;
    /// <summary>A diver points at the same kind again only after this many seconds.</summary>
    public const double SeeAgain = 25.0;
    public const double SwimSpeed = 60;
    /// <summary>Fish per school at most.</summary>
    public const int SchoolSize = 4;

    /// <summary>Each monitor's frame the water covers; the first is where most divers are.</summary>
    public IReadOnlyList<Rect> Pools { get; }
    /// <summary>The share of a pool's height the water covers when full.</summary>
    public double Share { get; }
    /// <summary>Seconds the dive lasts once the water is up.</summary>
    public double Length { get; }
    /// <summary>Screen points per sheet pixel, for the sea life's size.</summary>
    public double Scale { get; }
    public Phase CurrentPhase { get; private set; } = Phase.Rising;
    /// <summary>0 dry … 1 full.</summary>
    public double Level { get; private set; }
    public double Time { get; private set; }
    /// <summary>When the water was full, on the dive's clock.</summary>
    public double? FilledAt { get; private set; }
    public List<Critter> Critters { get; } = new();
    public List<Bubble> Bubbles { get; } = new();
    public List<Weed> Weeds { get; } = new();
    public List<Diver> Divers { get; } = new();
    /// <summary>Where each school is heading.</summary>
    internal Dictionary<int, Pt> SchoolGoals { get; } = new();

    /// <summary><paramref name="divers"/>: each creature's index, where it stands, and half its body in points.</summary>
    public Dive(IReadOnlyList<Rect> pools, double share, double seconds, double scale,
                IReadOnlyList<(int Index, Pt At, double Half)> divers, int seaLife, Random rng)
    {
        Pools = pools.Count == 0 ? new[] { new Rect(0, 0, 1000, 600) } : pools.ToArray();
        Share = share;
        Length = seconds;
        Scale = scale;
        var first = Pools[0];
        var fullTop = first.MinY + first.Height * share;
        for (var k = 0; k < divers.Count; k++)
        {
            var d = divers[k];
            var pool = Math.Max(0, Pools.ToList().FindIndex(p => p.InsetBy(-1, -1).Contains(d.At)));
            var target = new Pt(d.At.X, (Pools[pool].MinY + fullTop) / 2);
            var facingRight = rng.Coin();
            Divers.Add(new Diver
            {
                Index = d.Index, Pool = pool, State = DiverState.Gearing, Until = RiseSeconds + k * JumpGap,
                Position = d.At, Target = target, FacingRight = facingRight,
                NextAir = RiseSeconds + rng.Range(AirEvery), NextBubble = 0, Half = d.Half,
            });
        }
        Populate(seaLife, rng);
    }

    // MARK: Where the water is

    /// <summary>The surface's height in pool <paramref name="k"/>, now.</summary>
    public double Surface(int k)
    {
        var p = Pools[k];
        return p.MinY + p.Height * (Share * Level);
    }

    /// <summary>The surface when the water is full.</summary>
    public double FullSurface(int k) => Pools[k].MinY + Pools[k].Height * Share;

    /// <summary>The water in pool <paramref name="k"/> now, as a rectangle.</summary>
    public Rect Water(int k)
    {
        var p = Pools[k];
        return new Rect(p.MinX, p.MinY, p.Width, Surface(k) - p.MinY);
    }

    public bool IsOver => CurrentPhase == Phase.Over;

    // MARK: Filling the sea

    private void Populate(int fish, Random rng)
    {
        var widths = Pools.Select(p => p.Width).ToList();
        var total = Math.Max(1, widths.Sum());
        int RandomPool()
        {
            var pick = rng.NextDouble() * total;
            for (var k = 0; k < widths.Count; k++) { if (pick < widths[k]) return k; pick -= widths[k]; }
            return 0;
        }
        Pt PointIn(int k, double low = 0.15, double high = 0.85)
        {
            var p = Pools[k];
            var top = FullSurface(k);
            var x = rng.Range(p.MinX + 30, p.MaxX - 30);
            return new Pt(x, p.MinY + (top - p.MinY) * rng.Range(low, high));
        }
        var kinds = new[] { Life.FishA, Life.FishB, Life.FishC };
        int left = Math.Max(0, fish), school = 0;
        while (left > 0)
        {
            var n = Math.Min(left, rng.Next(2, SchoolSize + 1));
            var k = RandomPool();
            var centre = PointIn(k);
            var kind = kinds[school % kinds.Length];
            var right = rng.Coin();
            for (var i = 0; i < n; i++)
            {
                var ax = centre.X + rng.Range(-24, 24);
                var at = new Pt(ax, centre.Y + rng.Range(-14, 14));
                Critters.Add(new Critter
                {
                    Kind = kind, Pool = k, Position = at, Velocity = new Vec(right ? 30 : -30, 0), School = school,
                    FacingRight = right, Time = rng.Range(0, 1), Home = at.X,
                });
            }
            SchoolGoals[school] = PointIn(k);
            school++;
            left -= n;
        }
        // One each of the others in the first pool, the crab and the octopus on its floor.
        var p0 = Pools[0];
        double FloorY(Life kind) => p0.MinY + kind.HalfSize().Height * Scale;
        var jelly = PointIn(0, 0.4, 0.8);
        Critters.Add(new Critter { Kind = Life.Jelly, Pool = 0, Position = jelly, Velocity = new Vec(6, 0), School = -1, FacingRight = true, Home = jelly.X });
        var crabX = rng.Range(p0.MinX + p0.Width * 0.1, p0.MinX + p0.Width * 0.4);
        Critters.Add(new Critter { Kind = Life.Crab, Pool = 0, Position = new Pt(crabX, FloorY(Life.Crab)), Velocity = new Vec(14, 0), School = -1, FacingRight = true, Home = crabX });
        var turtle = PointIn(0, 0.35, 0.7);
        Critters.Add(new Critter { Kind = Life.Turtle, Pool = 0, Position = turtle, Velocity = new Vec(18, 0), School = -1, FacingRight = true, Home = turtle.X });
        var octoX = rng.Range(p0.MinX + p0.Width * 0.6, p0.MinX + p0.Width * 0.9);
        Critters.Add(new Critter { Kind = Life.Octopus, Pool = 0, Position = new Pt(octoX, FloorY(Life.Octopus)), Velocity = Vec.Zero, School = -1, FacingRight = false, Home = octoX });
        // Seaweed along every floor, every 60-140 points.
        for (var k = 0; k < Pools.Count; k++)
        {
            var pool = Pools[k];
            var x = pool.MinX + rng.Range(20, 80);
            while (x < pool.MaxX - 10)
            {
                var height = rng.Next(10, 25);
                Weeds.Add(new Weed { Pool = k, X = x, Height = height, Phase = rng.Range(0, 6) });
                x += rng.Range(60, 140);
            }
        }
    }

    // MARK: The step

    /// <summary>Time is up early: start draining now (the Actions sheet's "Out of the water").</summary>
    public void Drain()
    {
        if (CurrentPhase is not (Phase.Rising or Phase.On)) return;
        CurrentPhase = Phase.Draining;
        foreach (var d in Divers.Where(d => d.IsUnder || d.State == DiverState.Breathing)) d.State = DiverState.Settling;
    }

    public List<Event> Update(double dt, Random rng)
    {
        var events = new List<Event>();
        Time += dt;
        switch (CurrentPhase)
        {
            case Phase.Rising:
                Level = Math.Min(1, Level + dt / RiseSeconds);
                if (Level >= 1) { CurrentPhase = Phase.On; FilledAt = Time; events.Add(new Event(EventKind.Filled)); }
                break;
            case Phase.On:
                if (FilledAt is double at && Time - at >= Length) Drain();
                break;
            case Phase.Draining:
                Level = Math.Max(0, Level - dt / DrainSeconds);
                if (Level <= 0) { CurrentPhase = Phase.Over; events.Add(new Event(EventKind.Drained)); }
                break;
            case Phase.Over:
                return events;
        }
        UpdateDivers(dt, events, rng);
        UpdateCritters(dt, events, rng);
        UpdateBubbles(dt);
        return events;
    }

    private void UpdateDivers(double dt, List<Event> events, Random rng)
    {
        foreach (var d in Divers)
        {
            var pool = Pools[d.Pool];
            var top = Surface(d.Pool);
            switch (d.State)
            {
                case DiverState.Gearing:
                    // Jumps once the water is up, one after another.
                    if (CurrentPhase == Phase.On && Time >= d.Until)
                    {
                        var entry = new Pt(Math.Min(Math.Max(d.Position.X + (d.FacingRight ? 40 : -40), pool.MinX + 40), pool.MaxX - 40), top);
                        d.State = DiverState.Leaping;
                        d.From = d.Position;
                        d.To = entry;
                        d.Start = Time;
                        d.Duration = LeapSeconds;
                    }
                    else if (CurrentPhase is Phase.Draining or Phase.Over)
                    {
                        d.State = DiverState.Settling;
                    }
                    break;
                case DiverState.Leaping:
                {
                    Pt from = d.From, to = d.To;
                    var u = Math.Min(1, (Time - d.Start) / d.Duration);
                    var peak = Math.Max(from.Y, to.Y) + 70;
                    // A parabola through from, peak and to.
                    var x = from.X + (to.X - from.X) * u;
                    var a = 1 - u;
                    var y = a * a * from.Y + 2 * a * u * peak + u * u * to.Y;
                    d.FacingRight = to.X >= from.X;
                    d.Position = new Pt(x, y);
                    if (u >= 1)
                    {
                        events.Add(new Event(EventKind.Splash, At: new Pt(to.X, top)));
                        d.State = CurrentPhase == Phase.Draining ? DiverState.Settling : DiverState.Swimming;
                        d.Velocity = new Vec(d.FacingRight ? 20 : -20, -90);
                        d.Target = RandomTarget(d.Pool, d.Half, rng);
                    }
                    break;
                }
                case DiverState.Swimming:
                {
                    if (Time >= d.NextAir) d.Target = new Pt(d.Position.X, top - d.Half * 0.5);
                    var breathingUp = Time >= d.NextAir;
                    Steer(d, dt, breathingUp ? SwimSpeed * 1.3 : SwimSpeed);
                    if (breathingUp && d.Position.Y >= top - d.Half * 0.7)
                    {
                        d.State = DiverState.Breathing;
                        d.Until = Time + BreathSeconds;
                        d.Velocity = Vec.Zero;
                        events.Add(new Event(EventKind.Surfaced, d.Index));
                    }
                    else if (!breathingUp && d.Target.DistanceTo(d.Position) < 14)
                    {
                        d.Target = RandomTarget(d.Pool, d.Half, rng);
                    }
                    if (Time >= d.NextBubble)
                    {
                        d.NextBubble = Time + rng.Range(0.5, 1.1);
                        var at = new Pt(d.Position.X + (d.FacingRight ? d.Half * 0.6 : -d.Half * 0.6), d.Position.Y + d.Half * 0.5);
                        var size = rng.Next(0, 2);
                        var rise = rng.Range(40, 60);
                        Bubbles.Add(new Bubble { Position = at, Size = size, Rise = rise, Wobble = rng.Range(0, 6) });
                    }
                    break;
                }
                case DiverState.Breathing:
                    // Bobbing at the surface.
                    d.Position = d.Position with { Y = top - d.Half * 0.5 + Math.Sin(Time * 5) * 1.5 };
                    if (Time >= d.Until)
                    {
                        d.State = DiverState.Swimming;
                        d.NextAir = Time + rng.Range(AirEvery);
                        d.Target = RandomTarget(d.Pool, d.Half, rng);
                    }
                    break;
                case DiverState.Settling:
                {
                    // Down with the water, and to the floor.
                    var floor = pool.MinY + d.Half;
                    d.Velocity = Vec.Zero;
                    d.Position = d.Position with { Y = Math.Max(floor, Math.Min(d.Position.Y - dt * 40, top - d.Half * 0.5)) };
                    break;
                }
            }
            // Inside the water, whatever it does under it.
            if (d.IsUnder || d.State == DiverState.Swimming)
            {
                var x = Math.Min(Math.Max(d.Position.X, pool.MinX + d.Half), pool.MaxX - d.Half);
                d.Position = new Pt(x, Math.Max(d.Position.Y, pool.MinY + d.Half));
            }
        }
    }

    private Pt RandomTarget(int k, double half, Random rng)
    {
        var p = Pools[k];
        var top = Surface(k);
        double low = p.MinY + half + 6, high = Math.Max(low + 1, top - half * 2);
        var x = rng.Range(p.MinX + half + 20, Math.Max(p.MinX + half + 21, p.MaxX - half - 20));
        return new Pt(x, rng.Range(low, high));
    }

    private static void Steer(Diver d, double dt, double speed)
    {
        double dx = d.Target.X - d.Position.X, dy = d.Target.Y - d.Position.Y;
        var distance = Math.Max(1, Math.Sqrt(dx * dx + dy * dy));
        var want = new Vec(dx / distance * speed, dy / distance * speed);
        var k = Math.Min(1, dt * 2.5);
        d.Velocity = new Vec(d.Velocity.Dx + (want.Dx - d.Velocity.Dx) * k, d.Velocity.Dy + (want.Dy - d.Velocity.Dy) * k);
        d.Position = new Pt(d.Position.X + d.Velocity.Dx * dt, d.Position.Y + d.Velocity.Dy * dt);
        if (Math.Abs(d.Velocity.Dx) > 6) d.FacingRight = d.Velocity.Dx > 0;
    }

    private void UpdateCritters(double dt, List<Event> events, Random rng)
    {
        var under = Divers.Where(d => d.IsUnder).ToList();
        // The schools' goals move on once reached.
        foreach (var (school, goal) in SchoolGoals.ToList())
        {
            var members = Critters.Where(c => c.School == school).ToList();
            if (members.Count == 0) continue;
            var cx = members.Average(c => c.Position.X);
            var cy = members.Average(c => c.Position.Y);
            if (goal.DistanceTo(new Pt(cx, cy)) < 30)
            {
                var p = Pools[members[0].Pool];
                var top = Surface(members[0].Pool);
                var x = rng.Range(p.MinX + 30, p.MaxX - 30);
                SchoolGoals[school] = new Pt(x, p.MinY + Math.Max(10, top - p.MinY) * rng.Range(0.15, 0.85));
            }
        }
        foreach (var c in Critters)
        {
            c.Time += dt;
            c.Scared = Math.Max(0, c.Scared - dt);
            var p = Pools[c.Pool];
            var top = Surface(c.Pool);
            var size = c.Kind.HalfSize();
            double halfW = size.Width * Scale, halfH = size.Height * Scale;
            // The nearest diver under water in the same pool.
            var near = under.Where(d => d.Pool == c.Pool).OrderBy(d => d.Position.DistanceTo(c.Position)).FirstOrDefault();
            var distance = near?.Position.DistanceTo(c.Position) ?? double.PositiveInfinity;
            if (near is not null && distance < SeeRadius)
            {
                if (Time - near.Saw.GetValueOrDefault(c.Kind, -100) > SeeAgain && CurrentPhase == Phase.On)
                {
                    near.Saw[c.Kind] = Time;
                    events.Add(c.Kind == Life.Octopus && distance < ScareRadius ? new Event(EventKind.Startled, near.Index) : new Event(EventKind.Sees, near.Index, c.Kind));
                }
                if (distance < ScareRadius && c.Scared == 0)
                {
                    c.Scared = c.Kind == Life.Octopus ? 2.5 : 1.2;
                    if (c.Kind.IsFish() && Time - near.LastScatter > 12 && CurrentPhase == Phase.On)
                    {
                        near.LastScatter = Time;
                        events.Add(new Event(EventKind.Scattered, near.Index));
                    }
                    if (c.Kind == Life.Octopus && Time - near.Saw.GetValueOrDefault(Life.Octopus, -100) > 1 && CurrentPhase == Phase.On)
                    {
                        near.Saw[Life.Octopus] = Time;
                        events.Add(new Event(EventKind.Startled, near.Index));
                    }
                }
            }
            var away = Vec.Zero;
            if (near is not null)
            {
                double ax = c.Position.X - near.Position.X, ay = c.Position.Y - near.Position.Y;
                var ad = Math.Max(1, Math.Sqrt(ax * ax + ay * ay));
                away = new Vec(ax / ad, ay / ad);
            }
            var v = c.Velocity;
            var pos = c.Position;
            switch (c.Kind)
            {
                case Life.FishA or Life.FishB or Life.FishC:
                {
                    var goal = SchoolGoals.TryGetValue(c.School, out var g) ? g : c.Position;
                    double dx = goal.X - c.Position.X, dy = goal.Y - c.Position.Y;
                    var d = Math.Max(1, Math.Sqrt(dx * dx + dy * dy));
                    double wantX = dx / d * 36, wantY = dy / d * 22;
                    // Keep a little apart from the rest of the school.
                    foreach (var other in Critters.Where(o => o.School == c.School))
                    {
                        double ox = c.Position.X - other.Position.X, oy = c.Position.Y - other.Position.Y;
                        var od = Math.Sqrt(ox * ox + oy * oy);
                        if (od > 0.5 && od < 16) { wantX += ox / od * 20; wantY += oy / od * 20; }
                    }
                    if (c.Scared > 0) { wantX = away.Dx * 150; wantY = away.Dy * 110; }
                    var ease = Math.Min(1, dt * (c.Scared > 0 ? 6 : 1.5));
                    v = new Vec(v.Dx + (wantX - v.Dx) * ease, v.Dy + (wantY - v.Dy) * ease);
                    break;
                }
                case Life.Jelly:
                {
                    // Pulses up, drifts down; pushed off by a diver.
                    var pulse = Math.Sin(c.Time * 1.6);
                    v = new Vec(v.Dx * 0.98 + (c.Scared > 0 ? away.Dx * 20 : 0) * (dt * 4), pulse > 0.6 ? 22 : -8);
                    if (Math.Abs(v.Dx) < 3) v = v with { Dx = c.FacingRight ? 5 : -5 };
                    break;
                }
                case Life.Crab:
                    // Sideways along the floor about its patch; claws up and away when a diver comes.
                    if (c.Scared > 0) v = new Vec((away.Dx >= 0 ? 1 : -1) * 55, 0);
                    else if (Math.Abs(c.Position.X - c.Home) > 70) v = v with { Dx = c.Position.X > c.Home ? -14 : 14 };
                    pos = pos with { Y = p.MinY + halfH };
                    v = v with { Dy = 0 };
                    break;
                case Life.Turtle:
                    v = new Vec((c.FacingRight ? 1 : -1) * (c.Scared > 0 ? 34 : 18), Math.Sin(c.Time * 0.5) * 6);
                    if (c.Position.X > p.MaxX - halfW - 10) c.FacingRight = false;
                    if (c.Position.X < p.MinX + halfW + 10) c.FacingRight = true;
                    break;
                case Life.Octopus:
                    // Scared, it jets off, up and away, then sinks back to the floor.
                    v = c.Scared > 0 ? new Vec(away.Dx * 90, 50) : new Vec((c.Home - c.Position.X) * 0.3, -30);
                    break;
            }
            pos = new Pt(pos.X + v.Dx * dt, pos.Y + v.Dy * dt);
            // Inside the water.
            double low = p.MinY + halfH, high = Math.Max(low, top - halfH - 4);
            if (pos.Y < low) { pos = pos with { Y = low }; if (c.Kind is Life.Octopus or Life.Crab) v = v with { Dy = 0 }; }
            if (pos.Y > high) { pos = pos with { Y = high }; v = v with { Dy = Math.Min(0, v.Dy) }; }
            if (pos.X < p.MinX + halfW) { pos = pos with { X = p.MinX + halfW }; v = v with { Dx = Math.Abs(v.Dx) }; c.Home = Math.Max(c.Home, pos.X + 40); }
            if (pos.X > p.MaxX - halfW) { pos = pos with { X = p.MaxX - halfW }; v = v with { Dx = -Math.Abs(v.Dx) }; c.Home = Math.Min(c.Home, pos.X - 40); }
            if (c.Kind != Life.Turtle && Math.Abs(v.Dx) > 4) c.FacingRight = v.Dx > 0;
            c.Position = pos;
            c.Velocity = v;
        }
    }

    private void UpdateBubbles(double dt)
    {
        foreach (var b in Bubbles)
        {
            b.Wobble += dt * 4;
            b.Position = new Pt(b.Position.X + Math.Sin(b.Wobble) * 0.4, b.Position.Y + b.Rise * dt);
        }
        var tops = Enumerable.Range(0, Pools.Count).Select(Surface).ToList();
        Bubbles.RemoveAll(b =>
        {
            var k = Math.Max(0, Pools.ToList().FindIndex(p => p.MinX <= b.Position.X && b.Position.X <= p.MaxX));
            return b.Position.Y >= tops[k] - 2;
        });
    }

    // MARK: Words

    /// <summary>The line diver <paramref name="name"/> says for <paramref name="kind"/> (<c>in</c>, <c>see</c>, <c>fish</c>,
    /// <c>octopus</c>, <c>air</c>, <c>out</c>); <paramref name="what"/> fills a sighting's <c>{what}</c>.</summary>
    public static string Line(string name, string kind, Life? what, Random rng)
    {
        var l = Languages.Current;
        var pool = LinesIn(l).TryGetValue(name, out var mine) && mine.TryGetValue(kind, out var own) ? own
            : AnyoneIn(l).TryGetValue(kind, out var anyone) ? anyone : Array.Empty<string>();
        var line = pool.Count == 0 ? "" : rng.Pick(pool);
        return CursorMoods.Current.Adjust(Fill(line, what?.Spoken() ?? ""));
    }

    /// <summary><c>{what}</c> filled in, with a capital where it opens a sentence: "There. A turtle."</summary>
    public static string Fill(string line, string what)
    {
        var at = line.IndexOf("{what}", StringComparison.Ordinal);
        if (at < 0) return line;
        var before = line[..at].Trim(' ', '\t');
        var opens = before.Length == 0 || new[] { ".", "!", "?", "…" }.Any(s => before.EndsWith(s, StringComparison.Ordinal));
        var word = opens && what.Length > 0 ? what[..1].ToUpperInvariant() + what[1..] : what;
        return line[..at] + word + line[(at + "{what}".Length)..];
    }

    /// <summary>Every character's lines in <paramref name="l"/>: the English, each with its own from <see cref="Shared"/>
    /// (<c>dive.lines</c>) when it has some there.</summary>
    public static IReadOnlyDictionary<string, IReadOnlyDictionary<string, IReadOnlyList<string>>> LinesIn(Language l)
    {
        if (Shared.In(l) is not Shared s || s.DiveLines.Count == 0) return EnglishLines;
        return EnglishLines.ToDictionary(kv => kv.Key, kv => s.DiveLines.TryGetValue(kv.Key, out var t) && t.Count > 0
            ? (IReadOnlyDictionary<string, IReadOnlyList<string>>)t.ToDictionary(p => p.Key, p => (IReadOnlyList<string>)p.Value)
            : kv.Value);
    }

    /// <summary>Anyone's lines in <paramref name="l"/>, for a character the user made.</summary>
    public static IReadOnlyDictionary<string, IReadOnlyList<string>> AnyoneIn(Language l) =>
        Shared.In(l) is Shared s && s.DiveAnyone.Count > 0
            ? s.DiveAnyone.ToDictionary(p => p.Key, p => (IReadOnlyList<string>)p.Value)
            : EnglishAnyone;

    /// <summary>What a dive left in a pair's memory, for its storyline: "a school of fish, a turtle".</summary>
    public static string Memory(IEnumerable<Life> saw)
    {
        var named = saw.Select(l => l.IsFish() ? Life.FishA : l).Distinct()
            .OrderBy(l => l.Code(), StringComparer.Ordinal).Select(l => l.Spoken()).ToList();
        return named.Count == 0 ? "" : string.Join(", ", named);
    }
}

/// <summary>The sea life's names and sizes.</summary>
public static class DiveLives
{
    /// <summary>The sheet frame's name: <c>fish-a</c>, <c>jelly</c>, <c>octopus</c>.</summary>
    public static string Code(this Dive.Life life) => life switch
    {
        Dive.Life.FishA => "fish-a",
        Dive.Life.FishB => "fish-b",
        Dive.Life.FishC => "fish-c",
        Dive.Life.Jelly => "jelly",
        Dive.Life.Crab => "crab",
        Dive.Life.Turtle => "turtle",
        _ => "octopus",
    };

    public static bool IsFish(this Dive.Life life) => life is Dive.Life.FishA or Dive.Life.FishB or Dive.Life.FishC;

    /// <summary>What a diver calls it when it points: "a turtle".</summary>
    public static string Spoken(this Dive.Life life) => L10n.Tr(life switch
    {
        Dive.Life.FishA or Dive.Life.FishB or Dive.Life.FishC => "a school of fish",
        Dive.Life.Jelly => "a jellyfish",
        Dive.Life.Crab => "a crab",
        Dive.Life.Turtle => "a turtle",
        _ => "an octopus",
    });

    /// <summary>Half its body, in sheet pixels: how near counts as touching.</summary>
    public static (double Width, double Height) HalfSize(this Dive.Life life) => life switch
    {
        Dive.Life.FishA or Dive.Life.FishB or Dive.Life.FishC => (6, 4),
        Dive.Life.Jelly => (6, 8),
        Dive.Life.Crab => (8, 5),
        Dive.Life.Turtle => (12, 7),
        _ => (9, 9),
    };
}

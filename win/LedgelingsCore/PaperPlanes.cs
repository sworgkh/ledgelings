namespace Ledgelings.Core;

/// <summary>Air moving over the screen: a smooth, ever-changing field made of a few
/// crossing sine waves, so a paper plane drifts, swoops and wobbles instead of
/// flying a straight line. Pure and deterministic: the same point at the same
/// time always blows the same way. Every plane is thrown into its own weather
/// (<c>Random</c>): other phases, another scale, another pace, another strength.</summary>
public sealed record Wind
{
    /// <summary>Peak push, in points per second per second.</summary>
    public double Strength { get; set; } = 260;
    /// <summary>Where each of the four waves starts, radians.</summary>
    public IReadOnlyList<double> Phases { get; init; } = new double[] { 0, 0, 0, 0 };
    /// <summary>Larger: broader gusts. Smaller: choppier air.</summary>
    public double Scale { get; init; } = 1;
    /// <summary>How fast the weather changes.</summary>
    public double Pace { get; init; } = 1;

    public Wind() { }

    public Wind(double strength) { Strength = strength; }

    public static Wind Random(Random rng) => new()
    {
        Strength = rng.Range(180, 480),
        Phases = Enumerable.Range(0, 4).Select(_ => rng.Range(0, 2 * Math.PI)).ToArray(),
        Scale = rng.Range(0.6, 1.6),
        Pace = rng.Range(0.7, 1.8),
    };

    public Vec At(Pt p, double time)
    {
        double t = time * Pace, x = p.X / Scale, y = p.Y / Scale;
        var dx = Math.Sin(y / 260 + t * 0.35 + Phases[0]) + 0.6 * Math.Sin((x + y) / 410 - t * 0.23 + Phases[1]);
        var dy = Math.Cos(x / 310 - t * 0.29 + Phases[2]) + 0.6 * Math.Cos((x - y) / 470 + t * 0.19 + Phases[3]);
        return new Vec(Strength * dx / 1.6, Strength * dy / 1.6);
    }
}

/// <summary>
/// One folded note in the air, from one creature to another.
///
/// It steers for the catcher's head the way a paper plane would if it could:
/// weakly at first, so its wind and its swirl carry it about, and harder the
/// longer it has been flying and the closer it gets, so it always arrives.
/// The swirl pushes it sideways, back and forth, into S-curves and now and
/// then a loop. Its speed breathes around its own cruise. It rolls about its
/// fold as it goes: banking into its turns, and turning over, never snapping,
/// when it comes round to fly the other way. Behind it, a dotted trail of
/// puffs that fade within a second.
///
/// A class here, a value on the Mac: <see cref="Clone"/> is the Swift copy.
/// </summary>
public sealed class PaperPlane
{
    public readonly record struct Puff(Pt Position, double Age);

    public int From { get; set; }
    public int To { get; set; }
    public Pt Position { get; private set; }
    /// <summary>Where it was a step ago, so a fast plane cannot skip past its catcher.</summary>
    public Pt Previous { get; private set; }
    public Vec Velocity { get; private set; }
    public double Age { get; private set; }
    public List<Puff> Trail { get; private set; } = new();

    /// <summary>This plane's own weather.</summary>
    public Wind Wind { get; set; } = new();
    /// <summary>The speed it would like to fly at, points per second, and how much it
    /// breathes around it (0.25 = up to a quarter faster and slower).</summary>
    public double Cruise { get; set; } = 240;
    public double Surge { get; set; }
    /// <summary>Sideways push, points per second per second, swinging from one side to
    /// the other <see cref="SwirlRate"/> radians per second. Zero: no swirl.</summary>
    public double Swirl { get; set; }
    public double SwirlRate { get; set; } = 2;
    public double Phase { get; set; }
    public (double Low, double High) SpeedRange { get; set; } = (90, 760);
    /// <summary>How far apart the trail's puffs are, and how long each lasts.</summary>
    public double PuffSpacing { get; set; } = 9;
    public double PuffLife { get; set; } = 1.1;
    /// <summary>The screens it may fly over. Near an edge with no screen beyond it the
    /// plane is turned back, and it never crosses one. Empty: the open sky.</summary>
    public IReadOnlyList<Rect> Sky { get; set; } = Array.Empty<Rect>();
    /// <summary>How far its middle keeps from such an edge: half its drawn size, so no
    /// wingtip goes past it.</summary>
    public double Margin { get; set; }
    /// <summary>How close to an edge the turning back starts, points.</summary>
    public const double EdgeZone = 140;
    /// <summary>Thrown from outside the sky, or from right by its edge, it is let in
    /// first and kept in from then on.</summary>
    public bool InSky { get; private set; }
    private double sinceLastPuff;

    /// <summary>How far it is rolled about its fold, radians in −π…π: 0 is upright with
    /// the wing on top, positive turns its top toward you, ±π is upside down.</summary>
    public double Roll { get; private set; }
    /// <summary>Which way up it is heading for: wing on top flying right, and the other
    /// way up (which looks the same, mirrored) flying left.</summary>
    private bool flyingRight = true;
    /// <summary>How fast it is turning, radians per second, smoothed over a few frames.</summary>
    public double TurnRate { get; private set; }
    /// <summary>Radians of bank for every radian per second it turns, and the most.</summary>
    public const double BankPerTurn = 0.3;
    public const double MaxBank = 1.3;
    /// <summary>Fastest roll, radians per second: turning over takes about a third of a second.</summary>
    public const double RollRate = 9.0;
    /// <summary>It rolls over only once it is well into the other half: no flicker
    /// while it climbs or dives straight up and down.</summary>
    public const double TurnOverAt = 0.25;

    /// <summary>Thrown from <paramref name="start"/>, up into the screen along <paramref name="inward"/>, roughly toward
    /// <paramref name="target"/>, into still weather: the plain, predictable plane.</summary>
    public PaperPlane(int from, int to, Pt start, Vec inward, Pt target)
    {
        From = from;
        To = to;
        Position = start;
        Previous = start;
        var d = Unit(target - start);
        Velocity = new Vec((d.Dx * 0.5 + inward.Dx) * 220, (d.Dy * 0.5 + inward.Dy) * 220);
        flyingRight = Velocity.Dx >= 0;
        Roll = flyingRight ? 0 : Math.PI;
    }

    private PaperPlane(PaperPlane other)
    {
        From = other.From; To = other.To; Position = other.Position; Previous = other.Previous; Velocity = other.Velocity;
        Age = other.Age; Trail = new List<Puff>(other.Trail); Wind = other.Wind with { }; Cruise = other.Cruise;
        Surge = other.Surge; Swirl = other.Swirl; SwirlRate = other.SwirlRate; Phase = other.Phase; SpeedRange = other.SpeedRange;
        PuffSpacing = other.PuffSpacing; PuffLife = other.PuffLife; Sky = other.Sky; Margin = other.Margin; InSky = other.InSky;
        sinceLastPuff = other.sinceLastPuff; Roll = other.Roll; flyingRight = other.flyingRight; TurnRate = other.TurnRate;
    }

    /// <summary>An independent copy, the way a Swift value is copied.</summary>
    public PaperPlane Clone() => new(this);

    /// <summary>A real throw: its own wind, its own swirl, and a speed that is quick
    /// four times in five and a leisurely glide the fifth.</summary>
    public static PaperPlane Thrown(int from, int to, Pt start, Vec inward, Pt target, Random rng)
    {
        var plane = new PaperPlane(from, to, start, inward, target)
        {
            Wind = Wind.Random(rng),
        };
        plane.Cruise = rng.NextDouble() < 0.8 ? rng.Range(380, 580) : rng.Range(220, 340);
        plane.Surge = rng.Range(0.1, 0.3);
        plane.Swirl = rng.Range(250, 1100);
        plane.SwirlRate = rng.Range(1.2, 3.4);
        plane.Phase = rng.Range(0, 2 * Math.PI);
        var kick = plane.Cruise / 240;
        plane.Velocity = new Vec(plane.Velocity.Dx * kick, plane.Velocity.Dy * kick);
        return plane;
    }

    /// <summary>Which way the nose points, in radians.</summary>
    public double Heading => Math.Atan2(Velocity.Dy, Velocity.Dx);

    /// <summary>The drawings of the plane at different rolls, each named after its
    /// animation in the plane sheet (<see cref="Animation"/>). <c>Side</c> is the wing on top, nose right.</summary>
    public enum View { Side, Bank, Top, Tilt, Belly }

    /// <summary>The animation in the plane sheet that draws <paramref name="view"/>.</summary>
    public static string Animation(View view) => view switch
    {
        View.Side => "fly", View.Bank => "bank", View.Top => "top", View.Tilt => "tilt", _ => "belly",
    };

    /// <summary>Which drawing shows a plane rolled <paramref name="roll"/>, and whether it is flipped
    /// upside down. Past a quarter turn a symmetric plane looks like the
    /// mirror image of the roll short of a half turn, so the five drawings
    /// cover a whole roll.</summary>
    public static (View View, bool Flipped) ViewAt(double roll)
    {
        var r = Wrap(roll);
        var flipped = Math.Abs(r) > Math.PI / 2;
        var seen = flipped ? (r > 0 ? Math.PI - r : -Math.PI - r) : r;
        if (seen < -3 * Math.PI / 8) return (View.Belly, flipped);
        if (seen < -Math.PI / 8) return (View.Tilt, flipped);
        if (seen <= Math.PI / 8) return (View.Side, flipped);
        if (seen <= 3 * Math.PI / 8) return (View.Bank, flipped);
        return (View.Top, flipped);
    }

    public (View View, bool Flipped) CurrentView => ViewAt(Roll);

    /// <summary>An angle brought into −π…π.</summary>
    public static double Wrap(double angle)
    {
        var a = Math.IEEERemainder(angle, 2 * Math.PI);
        return a == -Math.PI ? Math.PI : a;
    }

    public double DistanceTo(Pt point) => Position.DistanceTo(point);

    /// <summary>True when its last step passed within <paramref name="reach"/> of <paramref name="point"/>: a catch even
    /// if the plane went through the catcher between two frames.</summary>
    public bool Passed(double reach, Pt point)
    {
        var seg = Position - Previous;
        var length2 = seg.Dx * seg.Dx + seg.Dy * seg.Dy;
        var k = length2 > 0 ? Math.Min(1, Math.Max(0, ((point.X - Previous.X) * seg.Dx + (point.Y - Previous.Y) * seg.Dy) / length2)) : 0;
        return point.DistanceTo(new Pt(Previous.X + seg.Dx * k, Previous.Y + seg.Dy * k)) <= reach;
    }

    /// <summary>How hard it steers: grows with time in the air and near the target.</summary>
    internal double Grip(Pt target)
    {
        var far = DistanceTo(target);
        return Math.Min(8, 0.9 + Age * 0.45) * (far < 160 ? 2.2 : 1);
    }

    /// <summary>The speed it wants right now: its cruise, breathing.</summary>
    public double WantedSpeed => Cruise * (1 + Surge * Math.Sin(Age * 1.7 + Phase * 0.5));

    public void Fly(double dt, Pt toward, double time)
    {
        var step = dt;
        var headingBefore = Heading;
        var toTarget = toward - Position;
        var want = Unit(toTarget);
        var grip = Grip(toward);
        var speedNow = WantedSpeed;
        // Close in, wind and swirl matter less: the last swoop is the plane's own.
        var far = toTarget.Length;
        var calm = Math.Min(1, far / 220);
        var gust = Wind.At(Position, time);
        var side = Unit(new Vec(-Velocity.Dy, Velocity.Dx));
        var twist = Swirl * Math.Sin(Age * SwirlRate + Phase) * calm;
        var vx = Velocity.Dx + ((want.Dx * speedNow - Velocity.Dx) * grip + (gust.Dx + side.Dx * twist) * calm) * step;
        var vy = Velocity.Dy + ((want.Dy * speedNow - Velocity.Dy) * grip + (gust.Dy + side.Dy * twist) * calm) * step;
        var push = InSky ? EdgePush() : Vec.Zero;
        vx += push.Dx * calm * step;
        vy += push.Dy * calm * step;
        var speed = Math.Sqrt(vx * vx + vy * vy);
        var clamped = Math.Min(Math.Max(speed, SpeedRange.Low), SpeedRange.High);
        if (speed > 0 && clamped != speed)
        {
            vx *= clamped / speed;
            vy *= clamped / speed;
        }
        Velocity = new Vec(vx, vy);
        Previous = Position;
        Position = new Pt(Position.X + vx * step, Position.Y + vy * step);
        KeepInSky();
        Age += dt;
        if (dt > 0) Turn(dt, Wrap(Heading - headingBefore));

        AgeTrail(dt);
        sinceLastPuff += clamped * step;
        while (sinceLastPuff >= PuffSpacing)
        {
            // A fast plane still leaves evenly spaced puffs, laid back along its step.
            sinceLastPuff -= PuffSpacing;
            var back = sinceLastPuff / Math.Max(clamped * step, 1e-6);
            Trail.Add(new Puff(new Pt(Position.X - Velocity.Dx * step * back, Position.Y - Velocity.Dy * step * back), 0));
        }
    }

    /// <summary>Banks into the turn, and turns over when it comes round to fly the
    /// other way, at <see cref="RollRate"/> at most.</summary>
    internal void Turn(double dt, double turned)
    {
        TurnRate += (turned / dt - TurnRate) * Math.Min(1, dt * 6);
        var c = Math.Cos(Heading);
        if (c < -TurnOverAt) flyingRight = false; else if (c > TurnOverAt) flyingRight = true;
        var bank = Math.Min(MaxBank, Math.Max(-MaxBank, TurnRate * BankPerTurn));
        var wanted = flyingRight ? bank : Math.PI - bank;
        var gap = Wrap(wanted - Roll);
        var most = RollRate * dt;
        Roll = Wrap(Roll + Math.Min(most, Math.Max(-most, gap * Math.Min(1, dt * 10))));
    }

    // MARK: The edges of the sky

    /// <summary>The screen it is over, or the nearest one.</summary>
    internal Rect? ScreenAt(Pt p)
    {
        foreach (var r in Sky) if (r.Contains(p)) return r;
        if (Sky.Count == 0) return null;
        return Sky.MinBy(r => Gap(p, r));
    }

    /// <summary>True when the screen stops at <paramref name="p"/>: no other screen goes on past it.</summary>
    internal bool IsOpenEdge(Pt p) => !Sky.Any(r => r.Contains(p));

    /// <summary>Air pushing it back from any edge that has no screen beyond it, harder
    /// the closer it is: it swoops round rather than bouncing off.</summary>
    internal Vec EdgePush()
    {
        if (ScreenAt(Position) is not Rect rect) return Vec.Zero;
        const double zone = EdgeZone, strength = 3000;
        double Force(double distance)
        {
            var d = Math.Max(0, distance - Margin);
            return d >= zone ? 0 : strength * Math.Pow(1 - d / zone, 2);
        }
        var y = Math.Min(Math.Max(Position.Y, rect.MinY), rect.MaxY - 1);
        var x = Math.Min(Math.Max(Position.X, rect.MinX), rect.MaxX - 1);
        double px = 0, py = 0;
        if (IsOpenEdge(new Pt(rect.MinX - 1, y))) px += Force(Position.X - rect.MinX);
        if (IsOpenEdge(new Pt(rect.MaxX + 1, y))) px -= Force(rect.MaxX - Position.X);
        if (IsOpenEdge(new Pt(x, rect.MinY - 1))) py += Force(Position.Y - rect.MinY);
        if (IsOpenEdge(new Pt(x, rect.MaxY + 1))) py -= Force(rect.MaxY - Position.Y);
        return new Vec(px, py);
    }

    /// <summary>Never past an edge: a plane that would cross one stays on it and loses
    /// the part of its speed that was taking it out.</summary>
    internal void KeepInSky()
    {
        if (ScreenAt(Position) is not Rect rect) return;
        var inner = rect.InsetBy(Math.Min(Margin, rect.Width / 2), Math.Min(Margin, rect.Height / 2));
        if (inner.Contains(Position)) { InSky = true; return; }
        if (!InSky) return;
        var p = Position;
        var beyond = new Pt(p.X < inner.MinX ? rect.MinX - 1 : p.X > inner.MaxX ? rect.MaxX + 1 : p.X,
                            p.Y < inner.MinY ? rect.MinY - 1 : p.Y > inner.MaxY ? rect.MaxY + 1 : p.Y);
        // Going on to the next screen is fine.
        if (!IsOpenEdge(beyond) && Sky.Any(r => r.Contains(p))) return;
        double x = p.X, y = p.Y, vx = Velocity.Dx, vy = Velocity.Dy;
        if (x < inner.MinX) { x = inner.MinX; vx = Math.Max(0, vx); }
        if (x > inner.MaxX) { x = inner.MaxX; vx = Math.Min(0, vx); }
        if (y < inner.MinY) { y = inner.MinY; vy = Math.Max(0, vy); }
        if (y > inner.MaxY) { y = inner.MaxY; vy = Math.Min(0, vy); }
        Position = new Pt(x, y);
        Velocity = new Vec(vx, vy);
    }

    internal static double Gap(Pt p, Rect r)
    {
        var dx = Math.Max(Math.Max(r.MinX - p.X, 0), p.X - r.MaxX);
        var dy = Math.Max(Math.Max(r.MinY - p.Y, 0), p.Y - r.MaxY);
        return Math.Sqrt(dx * dx + dy * dy);
    }

    /// <summary>The trail keeps fading after the plane is gone.</summary>
    public void FadeTrail(double dt) => AgeTrail(dt);

    private void AgeTrail(double dt)
    {
        var life = PuffLife;
        Trail = Trail.Select(p => p with { Age = p.Age + dt }).Where(p => p.Age < life).ToList();
    }

    internal static Vec Unit(Vec v)
    {
        var length = v.Length;
        return length > 1e-6 ? new Vec(v.Dx / length, v.Dy / length) : new Vec(1, 0);
    }
}

/// <summary>When the next paper plane is due: every <see cref="QuietFor"/> seconds, counted from
/// the last plane that went up.</summary>
public sealed class Post
{
    /// <summary>Seconds from one plane to the next. Zero or less: never.</summary>
    public double QuietFor { get; set; }
    public double LastStir { get; private set; }

    public Post(double quietFor) { QuietFor = quietFor; }

    /// <summary>A plane just went up: the next one is a whole interval away.</summary>
    public void Stir(double time) => LastStir = time;

    public bool IsDue(double time) => QuietFor > 0 && time - LastStir >= QuietFor;

    /// <summary>Nobody could send one just now: try again in <paramref name="seconds"/>, not a whole quiet spell later.</summary>
    public void Retry(double time, double seconds) => LastStir = Math.Min(time, time - QuietFor + seconds);

    /// <summary>Who throws and who catches, from the creatures free to do either
    /// (positions by index). The sender is anyone; the catcher is one of the
    /// farther half from it, so the plane has some sky to cross.</summary>
    public static (int From, int To)? PickPair(IReadOnlyDictionary<int, Pt> free, Random rng)
    {
        if (free.Count < 2) return null;
        var sender = rng.Pick(free.Keys.OrderBy(k => k).ToList());
        var at = free[sender];
        var others = free.Where(kv => kv.Key != sender).OrderByDescending(kv => kv.Value.DistanceTo(at)).ToList();
        var far = others.Take(Math.Max(1, (others.Count + 1) / 2)).ToList();
        if (far.Count == 0) return null;
        return (sender, rng.Pick(far).Key);
    }
}

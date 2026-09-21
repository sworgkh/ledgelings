namespace Ledgelings.Core;

public enum Eyes { Open, Half, Closed }

public static class EyesExtensions
{
    /// <summary>The atlas suffix: "open", "half", "closed".</summary>
    public static string Key(this Eyes eyes) => eyes switch { Eyes.Open => "open", Eyes.Half => "half", _ => "closed" };
}

/// <summary>
/// One creature's whole behaviour, with no window and no clock of its own.
/// Feed it <see cref="Update"/>; read back where and how to draw it.
/// </summary>
public sealed class Creature
{
    public sealed class Config
    {
        public double WalkSpeed = 55;                    // points per second
        public double FleeRadius = 90;                   // cursor closer than this -> jump
        public double TurnSpeed = 9;                     // radians per second, at corners
        public double JumpSpeed = 1500;                  // points per second through the air
        public (double Low, double High) JumpDuration = (0.35, 0.8);
        public double LandDuration = 0.16;
        public (double Low, double High) WalkSpell = (3, 9);
        public (double Low, double High) IdleSpell = (0.8, 2.5);
        public (double Low, double High) BlinkEvery = (1.5, 5);
        /// <summary>At nightfall each creature keeps going this long before it nods off,
        /// so a colony does not drop asleep in the same frame.</summary>
        public (double Low, double High) DozeOffAfter = (0.5, 7);
        public (double Low, double High) WakeUpAfter = (0, 3);
        /// <summary>Startled awake at night: how long it wanders before sleeping again.</summary>
        public (double Low, double High) RestlessSpell = (1.5, 3.5);
        public double ReverseChance = 0.35;
    }

    public sealed class Jump
    {
        public Pt From;
        public double FromRotation;
        public EdgeWorld.Spot To;
        /// <summary>Which way the flight path bows, as a vector of length 0...1.</summary>
        public Vec Bulge;
        public double Duration;
        public double Elapsed;
    }

    public abstract record Mode
    {
        public sealed record Walking(double Remaining) : Mode;
        public sealed record Idle(double Remaining) : Mode;
        public sealed record Jumping(Jump Jump) : Mode;
        public sealed record Landing(double Remaining) : Mode;
        /// <summary><c>WakeIn</c> is null while it is night, and counts down once day breaks.</summary>
        public sealed record Sleeping(double? WakeIn) : Mode;
        /// <summary>Picked up by the user, going wherever the cursor goes.</summary>
        public sealed record Held : Mode;
        /// <summary>Stopped to talk to another creature; walks on when told, or when this runs out.</summary>
        public sealed record Chatting(double Remaining) : Mode;
        /// <summary>Hurrying to a spot on its own loop: home, when the house is out.</summary>
        public sealed record Running(double To) : Mode;
    }

    public EdgeWorld World { get; private set; }
    public Config Settings { get; set; }
    public EdgeWorld.Spot Spot { get; private set; }
    /// <summary>+1 walks counter-clockwise (rightwards along the bottom edge), -1 clockwise.</summary>
    public double Direction { get; private set; } = 1;
    public Pt Position { get; private set; }
    public double Rotation { get; private set; }
    public Mode CurrentMode { get; private set; }
    public Eyes Eyes { get; private set; } = Eyes.Open;
    /// <summary>Seconds spent in the current animation; the renderer turns it into a frame.</summary>
    public double AnimationTime { get; private set; }

    private double blinkIn;
    private double? blinkElapsed;
    private bool knowsItIsNight;
    /// <summary>Put to sleep by hand. Daylight does not end a nap; the next dawn does.</summary>
    public bool IsNapping { get; private set; }
    /// <summary>Set while a dropped sleeper falls back to an edge, so it lands still asleep.</summary>
    private bool sleepsThroughLanding;
    /// <summary>The way it was going before it turned to talk to someone.</summary>
    private double courseBeforeChat = 1;
    /// <summary>Whether it was asleep when picked up, so it lands the same way.</summary>
    private bool napsInHand;
    /// <summary>A <see cref="Leap"/> lands and waits instead of walking off.</summary>
    private bool waitsAfterLanding;
    /// <summary>Reached the spot it was running or leaping to, and has not moved since.</summary>
    public bool HasArrived { get; private set; }

    /// <summary>half -> closed -> half, in seconds.</summary>
    private static readonly (Eyes Eyes, double Length)[] BlinkPhases = { (Eyes.Half, 0.05), (Eyes.Closed, 0.09), (Eyes.Half, 0.05) };

    public Creature(EdgeWorld world, EdgeWorld.Spot? spot = null, bool facingForwards = true, Config? config = null)
    {
        World = world;
        Direction = facingForwards ? 1 : -1;
        Settings = config ?? new Config();
        var s = spot ?? new EdgeWorld.Spot(0, 0);
        Spot = new EdgeWorld.Spot(s.Loop, world.Loops[s.Loop].Wrap(s.T));
        Position = world.Point(Spot);
        Rotation = world.Loops[s.Loop].Rotation(world.Loops[s.Loop].Segment(s.T));
        CurrentMode = new Mode.Walking(Settings.WalkSpell.High);
        blinkIn = Settings.BlinkEvery.Low;
    }

    // MARK: What to draw

    public EdgeLoop Loop => World.Loops[Spot.Loop];
    public double T => Spot.T;
    public int Segment => Loop.Segment(Spot.T);
    /// <summary>The angle the creature should stand at where it is now.</summary>
    public double RestingRotation => Loop.Rotation(Segment);

    public string Animation => CurrentMode switch
    {
        Mode.Walking => "walk",
        Mode.Idle => "idle",
        Mode.Jumping => "jump",
        Mode.Landing => "land",
        Mode.Sleeping => "sleep",
        Mode.Held => napsInHand ? "sleep" : "idle",
        Mode.Chatting => AnimationTime < Settings.LandDuration ? "land" : "idle",      // a squash on impact
        Mode.Running => "walk",
        _ => "idle",
    };

    public bool IsRunning => CurrentMode is Mode.Running;
    public bool IsChatting => CurrentMode is Mode.Chatting;

    /// <summary>Asleep on an edge, or asleep in the user's hand.</summary>
    public bool IsSleeping => CurrentMode switch { Mode.Sleeping => true, Mode.Held => napsInHand, _ => false };

    public bool IsHeld => CurrentMode is Mode.Held;
    /// <summary>Eyes shut and Zs floating: asleep, or a sleeper falling back to an edge.</summary>
    public bool LooksAsleep => IsSleeping || sleepsThroughLanding;

    /// <summary>The sheet is drawn facing right; mirror it to walk the other way.</summary>
    public bool IsMirrored => Direction < 0;

    public bool IsJumping => CurrentMode is Mode.Jumping;

    // MARK: Driving it

    public void Update(double dt, Pt? cursor, bool isNight, Random rng)
    {
        if (dt <= 0) return;
        if (LooksAsleep) { Eyes = Eyes.Closed; blinkElapsed = null; } else UpdateBlink(dt, rng);
        NoticeTimeOfDay(isNight, rng);

        // A sleeper does not notice the cursor. That is what lets you pick it up.
        if (!IsJumping && !LooksAsleep && !IsHeld && !IsRunning && cursor is Pt c && c.DistanceTo(Position) < Settings.FleeRadius)
            Startle(rng);

        AnimationTime += dt;
        switch (CurrentMode)
        {
            case Mode.Walking(var remaining):
                Spot = Spot with { T = Loop.Wrap(Spot.T + Direction * Settings.WalkSpeed * dt) };
                Position = World.Point(Spot);
                Turn(RestingRotation, dt);
                if (remaining - dt <= 0)
                    Enter(isNight ? new Mode.Sleeping(null) : new Mode.Idle(rng.Range(Settings.IdleSpell)));
                else
                    CurrentMode = new Mode.Walking(remaining - dt);
                break;

            case Mode.Idle(var remaining):
                Turn(RestingRotation, dt);
                if (remaining - dt <= 0)
                {
                    if (isNight) { Enter(new Mode.Sleeping(null)); break; }
                    if (rng.NextDouble() < Settings.ReverseChance) Direction = -Direction;
                    Enter(new Mode.Walking(rng.Range(Settings.WalkSpell)));
                }
                else CurrentMode = new Mode.Idle(remaining - dt);
                break;

            case Mode.Jumping(var jump):
            {
                jump.Elapsed += dt;
                var p = Math.Min(1, jump.Elapsed / jump.Duration);
                var eased = p * p * (3 - 2 * p);
                var target = World.Point(jump.To);
                var landing = World.Loops[jump.To.Loop];
                // Arc through the air, bulging away from the edges it leaves and lands on.
                var distance = target.DistanceTo(jump.From);
                var pull = Math.Sin(Math.PI * p) * 0.2 * distance;
                Position = new Pt(
                    jump.From.X + (target.X - jump.From.X) * eased + jump.Bulge.Dx * pull,
                    jump.From.Y + (target.Y - jump.From.Y) * eased + jump.Bulge.Dy * pull);
                var goal = landing.Rotation(landing.Segment(jump.To.T));
                Rotation = jump.FromRotation + ShortestArc(jump.FromRotation, goal) * eased;
                if (p >= 1)
                {
                    Spot = jump.To;
                    Position = target;
                    Rotation = goal;
                    Enter(new Mode.Landing(Settings.LandDuration));
                }
                break;
            }

            case Mode.Landing(var remaining):
                if (remaining - dt <= 0 && sleepsThroughLanding)
                {
                    sleepsThroughLanding = false;
                    Enter(new Mode.Sleeping(null));
                }
                else if (remaining - dt <= 0 && waitsAfterLanding)
                {
                    waitsAfterLanding = false;
                    Enter(new Mode.Idle(double.PositiveInfinity));
                    HasArrived = true;
                }
                else if (remaining - dt <= 0)
                    Enter(new Mode.Walking(rng.Range(isNight ? Settings.RestlessSpell : Settings.WalkSpell)));
                else
                    CurrentMode = new Mode.Landing(remaining - dt);
                break;

            case Mode.Sleeping(var wakeIn):
                Turn(RestingRotation, dt);
                if (wakeIn is not double w) break;
                if (w - dt <= 0) Enter(new Mode.Walking(rng.Range(Settings.WalkSpell)));
                else CurrentMode = new Mode.Sleeping(w - dt);
                break;

            case Mode.Held:
                Turn(0, dt);      // dangles upright
                break;

            case Mode.Chatting(var remaining):
                Turn(RestingRotation, dt);
                if (remaining - dt <= 0) WalkOn(rng); else CurrentMode = new Mode.Chatting(remaining - dt);
                break;

            case Mode.Running(var target):
            {
                var step = Settings.WalkSpeed * 2.5 * dt;
                var left = Direction > 0 ? Loop.Wrap(target - Spot.T) : Loop.Wrap(Spot.T - target);
                if (left <= step)
                {
                    Spot = Spot with { T = target };
                    Enter(new Mode.Idle(double.PositiveInfinity));
                    HasArrived = true;
                }
                else Spot = Spot with { T = Loop.Wrap(Spot.T + Direction * step) };
                Position = World.Point(Spot);
                Turn(RestingRotation, dt);
                break;
            }
        }
    }

    // MARK: Going home

    /// <summary>Hurry to <paramref name="target"/> on this loop, the short way round, waking up if needed.
    /// Not from the air or the user's hand; the caller waits for those.</summary>
    public void Run(double target)
    {
        if (IsJumping || IsHeld) return;
        IsNapping = false;
        sleepsThroughLanding = false;
        var ahead = Loop.Wrap(target - Spot.T);
        Direction = ahead <= Loop.Length / 2 ? 1 : -1;
        Enter(new Mode.Running(Loop.Wrap(target)));
    }

    /// <summary>Jump straight to <paramref name="spot"/> (any loop) and wait there.</summary>
    public void Leap(EdgeWorld.Spot spot)
    {
        if (IsJumping || IsHeld) return;
        IsNapping = false;
        sleepsThroughLanding = false;
        waitsAfterLanding = true;
        var landing = World.Loops[spot.Loop];
        var target = World.Point(spot);
        var distance = target.DistanceTo(Position);
        var duration = Math.Min(Math.Max(distance / Settings.JumpSpeed, Settings.JumpDuration.Low), Settings.JumpDuration.High);
        var a = Loop.Inward(Segment);
        var b = landing.Inward(landing.Segment(spot.T));
        Enter(new Mode.Jumping(new Jump
        {
            From = Position, FromRotation = Rotation, To = spot,
            Bulge = new Vec((a.Dx + b.Dx) / 2, (a.Dy + b.Dy) / 2), Duration = duration,
        }));
    }

    /// <summary>Step out of the door at <paramref name="spot"/>, walking <paramref name="facing"/> (+1 or -1).</summary>
    public void Emerge(EdgeWorld.Spot spot, double facing, Random rng)
    {
        Spot = new EdgeWorld.Spot(spot.Loop, World.Loops[spot.Loop].Wrap(spot.T));
        Position = World.Point(Spot);
        Rotation = RestingRotation;
        Direction = facing < 0 ? -1 : 1;
        IsNapping = false;
        sleepsThroughLanding = false;
        waitsAfterLanding = false;
        Enter(new Mode.Walking(rng.Range(Settings.WalkSpell)));
    }

    // MARK: Meeting someone

    /// <summary>Stop and face the other creature: <paramref name="facing"/> is +1 when it is further along
    /// the loop, -1 when it is behind. Only an awake creature on the ground can.</summary>
    public void Meet(double facing, double seconds = 30)
    {
        if (IsJumping || LooksAsleep || IsHeld) return;
        if (!IsChatting) courseBeforeChat = Direction;
        Direction = facing < 0 ? -1 : 1;
        Enter(new Mode.Chatting(seconds));
    }

    /// <summary>The conversation is over: back on the old course.</summary>
    public void WalkOn(Random rng)
    {
        if (!IsChatting) return;
        Direction = courseBeforeChat;
        Enter(new Mode.Walking(rng.Range(Settings.WalkSpell)));
    }

    // MARK: The user's hand

    /// <summary>Shift-right-click: put an awake creature down for a nap, or wake a sleeper.</summary>
    public void ToggleNap(Random rng)
    {
        if (IsJumping || IsHeld) return;
        if (IsSleeping)
        {
            IsNapping = false;
            Enter(new Mode.Walking(rng.Range(Settings.WalkSpell)));
        }
        else
        {
            IsNapping = true;
            Enter(new Mode.Sleeping(null));
        }
    }

    /// <summary>A sleeper can always be picked up; an awake one only when the caller
    /// says so (a Shift-drag). Returns whether it was.</summary>
    public bool PickUp(bool evenAwake = false)
    {
        if (IsJumping || IsHeld) return false;
        if (CurrentMode is Mode.Sleeping) napsInHand = true;
        else if (evenAwake) napsInHand = false;
        else return false;
        Enter(new Mode.Held());
        return true;
    }

    public void Drag(Pt point)
    {
        if (!IsHeld) return;
        Position = point;
    }

    /// <summary>Let go: it drops to the nearest edge of any monitor, asleep if it was asleep.</summary>
    public void Drop()
    {
        if (!IsHeld) return;
        var to = World.Nearest(Position);
        var target = World.Point(to);
        var distance = target.DistanceTo(Position);
        sleepsThroughLanding = napsInHand;
        Enter(new Mode.Jumping(new Jump
        {
            From = Position, FromRotation = Rotation, To = to, Bulge = Vec.Zero,
            Duration = Math.Max(0.12, Math.Min(distance / Settings.JumpSpeed, Settings.JumpDuration.High)),
        }));
    }

    /// <summary>React to dusk and dawn, once each.</summary>
    private void NoticeTimeOfDay(bool isNight, Random rng)
    {
        if (isNight && !knowsItIsNight)
        {
            var awakeFor = rng.Range(Settings.DozeOffAfter);
            switch (CurrentMode)
            {
                case Mode.Walking(var remaining): CurrentMode = new Mode.Walking(Math.Min(remaining, awakeFor)); break;
                case Mode.Idle(var remaining): CurrentMode = new Mode.Idle(Math.Min(remaining, awakeFor)); break;
            }
        }
        if (!isNight && knowsItIsNight) IsNapping = false;      // dawn ends every nap
        if (!isNight && !IsNapping && CurrentMode is Mode.Sleeping { WakeIn: null })
            CurrentMode = new Mode.Sleeping(rng.Range(Settings.WakeUpAfter));
        if (isNight && CurrentMode is Mode.Sleeping { WakeIn: not null }) CurrentMode = new Mode.Sleeping(null);
        knowsItIsNight = isNight;
    }

    /// <summary>Jump to a random spot on a random OTHER edge -- of any monitor. Longer
    /// edges are likelier, so a big monitor gets its fair share of landings.</summary>
    public void Startle(Random rng)
    {
        if (IsJumping) return;
        var hereLoop = Spot.Loop;
        var hereSegment = Segment;
        var others = World.Segments.Where(s => (s.Loop != hereLoop || s.Segment != hereSegment) && s.Length > 1).ToList();
        if (others.Count == 0) return;
        var pick = rng.Range(0, others.Sum(s => s.Length));
        var chosen = others[^1];
        foreach (var s in others) { pick -= s.Length; if (pick < 0) { chosen = s; break; } }
        var landing = World.Loops[chosen.Loop];
        var to = new EdgeWorld.Spot(chosen.Loop, landing.T(chosen.Segment, rng.Range(0.15, 0.85)));
        var target = World.Point(to);
        var distance = target.DistanceTo(Position);
        var duration = Math.Min(Math.Max(distance / Settings.JumpSpeed, Settings.JumpDuration.Low), Settings.JumpDuration.High);
        var a = Loop.Inward(Segment);
        var b = landing.Inward(chosen.Segment);
        Direction = rng.Coin() ? 1 : -1;
        Enter(new Mode.Jumping(new Jump
        {
            From = Position, FromRotation = Rotation, To = to,
            Bulge = new Vec((a.Dx + b.Dx) / 2, (a.Dy + b.Dy) / 2), Duration = duration,
        }));
    }

    /// <summary>The monitors changed under the creature -- resized, unplugged, rearranged.
    /// Put it on the nearest edge that still exists and abandon any jump.</summary>
    public void Rehome(EdgeWorld newWorld)
    {
        World = newWorld;
        Spot = newWorld.Nearest(Position);
        Position = newWorld.Point(Spot);
        Rotation = RestingRotation;
        var asleep = LooksAsleep;
        sleepsThroughLanding = false;
        Enter(asleep ? new Mode.Sleeping(null) : new Mode.Walking(Settings.WalkSpell.Low));
        knowsItIsNight = asleep;
    }

    // MARK: Internals

    private void Enter(Mode newMode)
    {
        CurrentMode = newMode;
        AnimationTime = 0;
        HasArrived = false;
    }

    private void Turn(double goal, double dt)
    {
        var delta = ShortestArc(Rotation, goal);
        var step = Settings.TurnSpeed * dt;
        Rotation = Math.Abs(delta) <= step ? goal : Rotation + (delta > 0 ? step : -step);
    }

    private void UpdateBlink(double dt, Random rng)
    {
        if (blinkElapsed is double elapsed)
        {
            var clock = elapsed + dt;
            blinkElapsed = clock;
            foreach (var (phase, length) in BlinkPhases)
            {
                if (clock < length) { Eyes = phase; return; }
                clock -= length;
            }
            Eyes = Eyes.Open;
            blinkElapsed = null;
            blinkIn = rng.Range(Settings.BlinkEvery);
        }
        else
        {
            blinkIn -= dt;
            if (blinkIn <= 0)
            {
                blinkElapsed = 0;
                Eyes = BlinkPhases[0].Eyes;
            }
        }
    }

    /// <summary>The signed angle in (-π, π] that takes <paramref name="from"/> to <paramref name="to"/> the short way round.</summary>
    public static double ShortestArc(double from, double to)
    {
        var raw = to - from;
        var delta = raw - Math.Truncate(raw / (2 * Math.PI)) * 2 * Math.PI;
        if (delta > Math.PI) delta -= 2 * Math.PI;
        if (delta <= -Math.PI) delta += 2 * Math.PI;
        return delta;
    }
}

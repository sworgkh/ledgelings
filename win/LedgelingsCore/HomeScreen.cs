namespace Ledgelings.Core;

/// <summary>
/// Which monitors the colony lives on (<c>homeScreen</c>): all of them, or one. The Mac's HomeScreen (SPEC §2.4).
///
/// A monitor is known by an id that stays the same across relaunches and re-plugging (here the monitor's
/// device path, on the Mac the display's UUID), and shown by its name. While the chosen monitor is unplugged
/// the colony lives on every monitor left, and the choice is kept: plugged back in, the creatures go back to it.
/// </summary>
public static class HomeScreen
{
    /// <summary>The setting's value for "every monitor".</summary>
    public const string All = "";

    public sealed record Monitor(string Id, string Name, Rect Frame);

    /// <summary>The monitors they live on: the chosen one while it is attached, else every one.
    /// Every one, not the primary, when it is away: the primary is often the laptop's own, shut in a
    /// dock; and every monitor is what they did before there was a choice, so nobody lands somewhere new.</summary>
    public static IReadOnlyList<Monitor> Home(string chosen, IReadOnlyList<Monitor> monitors)
    {
        if (chosen == All) return monitors;
        var one = monitors.FirstOrDefault(m => m.Id == chosen);
        return one is null ? monitors : new[] { one };
    }

    /// <summary>A monitor is chosen but not attached: they live everywhere until it is back.</summary>
    public static bool IsAway(string chosen, IReadOnlyList<Monitor> monitors) => chosen != All && monitors.All(m => m.Id != chosen);

    /// <summary>Whether <paramref name="point"/> counts as on the home monitors: on one, or within <paramref name="slack"/> of one.</summary>
    public static bool IsHome(Pt point, IEnumerable<Rect> home, double slack) =>
        home.Any(r => r.InsetBy(-slack, -slack).Contains(point));

    /// <summary>Seconds between one creature and the next coming down on the new monitor, so they arrive
    /// one after another, not in a heap.</summary>
    public const double ArrivalGap = 0.45;

    /// <summary>
    /// A creature leaving a monitor the colony no longer lives on: one big spring straight up and out
    /// through the top of its screen, turning as it goes, before it comes down on the new one by parachute
    /// (<see cref="Plays.Chute"/>).
    /// </summary>
    public sealed class Hop
    {
        /// <summary>Seconds it crouches before it springs.</summary>
        public const double Crouch = 0.25;
        /// <summary>It turns once round on the way up, the way it faces.</summary>
        public const double Spin = 2 * Math.PI;

        public Pt From { get; }
        public double FromRotation { get; }
        /// <summary>Where it is out of sight: past the top of its screen.</summary>
        public double Gone { get; }
        public double Speed { get; }
        public double Way { get; }
        public Pt Position { get; private set; }
        public double Rotation { get; private set; }
        public double Clock { get; private set; }
        public bool IsGone { get; private set; }

        /// <param name="gone">A y above the screen's top by more than a body.</param>
        /// <param name="way">+1 right, −1 left.</param>
        public Hop(Pt from, double rotation, double gone, double way)
        {
            From = from;
            FromRotation = rotation;
            Gone = Math.Max(gone, from.Y + 1);
            Way = way < 0 ? -1 : 1;
            // Fast enough to be past the top while still going up.
            Speed = Math.Sqrt(2 * Plays.Gravity * (Gone - from.Y)) * 1.15;
            Position = from;
            Rotation = rotation;
        }

        /// <summary>How it looks: crouched, then in the air.</summary>
        public string Pose => Clock < Crouch ? "land" : "jump";

        /// <summary>Seconds from the spring to out of sight.</summary>
        public double FlightTime
        {
            get
            {
                double g = Plays.Gravity, v = Speed, h = Gone - From.Y;
                return (v - Math.Sqrt(v * v - 2 * g * h)) / g;
            }
        }

        public void Update(double dt)
        {
            if (IsGone) return;
            Clock += dt;
            var t = Math.Max(0, Clock - Crouch);
            if (t <= 0) return;
            Position = new Pt(From.X + Way * 40 * t, From.Y + Speed * t - Plays.Gravity * t * t / 2);
            var share = Math.Min(1, t / Math.Max(FlightTime, 0.01));
            Rotation = FromRotation * (1 - share) - Way * Spin * share;
            if (Position.Y >= Gone) IsGone = true;
        }
    }
}

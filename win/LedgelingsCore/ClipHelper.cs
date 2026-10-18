namespace Ledgelings.Core;

/// <summary>
/// The creature who brings the clipboard picker (SPEC §7.11.1), the Mac's <c>ClipHelper.swift</c>: on the
/// shortcut it leaps from its edge to the paper's top-left corner, the sheet unfolds out of it, and it holds
/// that corner while the picker is open; once something is chosen it leaps back. Pure geometry and choice,
/// so both apps leap the same way. The lines are the Mac's word for word; the Russian comes from <see cref="Shared"/>.
/// </summary>
public static class ClipHelper
{
    /// <summary>Seconds the sheet takes to unfold out of the creature, and to collapse, at speed 1.</summary>
    public const double UnfoldSeconds = 0.14, CollapseSeconds = 0.18;

    /// <summary>A quick jump along an arc, after a short crouch.</summary>
    public sealed class Leap
    {
        /// <summary>Seconds it crouches before it springs: short, the picker is waiting.</summary>
        public const double Crouch = 0.06;

        public Pt From { get; }
        public Pt To { get; }
        /// <summary>Seconds in the air, crouch not counted.</summary>
        public double Flight { get; }
        /// <summary>How far the arc rises over the higher of its two ends.</summary>
        public double Rise { get; }
        public double Clock { get; private set; }

        public Leap(Pt from, Pt to, double flight)
        {
            From = from;
            To = to;
            Flight = Math.Max(flight, 0.01);
            Rise = Math.Clamp(from.DistanceTo(to) * 0.2, 24, 160);
        }

        public double Duration => Crouch + Flight;
        public bool IsDone => Clock >= Duration;
        public void Update(double dt) => Clock = Math.Min(Clock + dt, Duration);
        /// <summary>Its share of the flight, 0 to 1.</summary>
        public double Share => Math.Clamp((Clock - Crouch) / Flight, 0, 1);

        /// <summary>Straight between the ends, plus an arc that peaks halfway, <see cref="Rise"/> over the higher end.</summary>
        public Pt Position
        {
            get
            {
                var s = Share;
                double x = From.X + (To.X - From.X) * s, y = From.Y + (To.Y - From.Y) * s;
                var top = Math.Max(From.Y, To.Y) + Rise - (From.Y + (To.Y - From.Y) * 0.5);
                return new Pt(x, y + 4 * top * s * (1 - s));
            }
        }

        /// <summary>Crouched, in the air, landed.</summary>
        public string Pose => Clock < Crouch ? "land" : IsDone ? "idle" : "jump";

        /// <summary>A flip on the way, the way it travels; upright again once landed.</summary>
        public double Rotation
        {
            get
            {
                var way = To.X >= From.X ? -1.0 : 1.0;
                return IsDone ? 0 : way * 2 * Math.PI * Share;
            }
        }
    }

    /// <summary>Seconds in the air for a leap of <paramref name="distance"/> points: about a quarter of a second
    /// across a laptop screen, never more than 0.4, divided by <paramref name="speed"/>.</summary>
    public static double Flight(double distance, double speed) => Math.Clamp(0.14 + distance / 6000, 0.14, 0.4) / Math.Max(speed, 0.1);

    /// <summary>One creature as the choice sees it.</summary>
    public readonly record struct Candidate(string Name, Pt Position, bool Asleep, bool Free);

    /// <summary>Who comes: the one named <paramref name="wanted"/> when it is free, else the free creature nearest
    /// <paramref name="centre"/>, an awake one before a sleeper. Null when nobody is free.</summary>
    public static int? Choose(IReadOnlyList<Candidate> candidates, Pt centre, string wanted)
    {
        var free = Enumerable.Range(0, candidates.Count).Where(i => candidates[i].Free).ToList();
        if (wanted.Length > 0 && free.FirstOrDefault(i => candidates[i].Name == wanted, -1) is var named and >= 0) return named;
        if (free.Count == 0) return null;
        return free.OrderBy(i => candidates[i].Asleep).ThenBy(i => candidates[i].Position.DistanceTo(centre)).First();
    }

    /// <summary>Where its centre goes to hold the paper by its top-left corner: its body over the corner, a little out and up.</summary>
    public static Pt Perch(Rect paper, double half) => new(paper.MinX - half * 0.25, paper.MaxY + half * 0.45);

    // MARK: Lines

    public static IReadOnlyDictionary<string, IReadOnlyList<string>> LinesIn(Language l) =>
        Translated.Lists(Shared.In(l)?.ClipHelperLines, EnglishLines, t => (IReadOnlyList<string>)t);

    public static IReadOnlyList<string> AnyoneIn(Language l) => Translated.List(Shared.In(l)?.ClipHelperAnyone, EnglishAnyone);

    /// <summary>What it says as the sheet unfolds, in its own voice.</summary>
    public static string Line(string name, Random rng)
    {
        var l = Languages.Current;
        var pool = LinesIn(l).TryGetValue(name, out var mine) ? mine : AnyoneIn(l);
        return pool.Count == 0 ? "" : rng.Pick(pool);
    }

    public static readonly IReadOnlyList<string> EnglishAnyone = new[] { "Here. Pick one.", "Got it right here." };

    public static readonly IReadOnlyDictionary<string, IReadOnlyList<string>> EnglishLines = new Dictionary<string, IReadOnlyList<string>>
    {
        ["Blocky"] = new[] { "Fine. Pick one.", "Hold still, cursor." },
        ["Pip"] = new[] { "Ooh, which one?!", "Pick pick pick!" },
        ["Mortimer"] = new[] { "Choose wisely, youngster.", "Ah, the old papers." },
        ["Zed"] = new[] { "*yawn* ...pick one.", "Mm. Here. Sleepy." },
        ["Dot"] = new[] { "Already here. Go.", "Fastest paper ever." },
        ["Ruth"] = new[] { "Sorted, newest first.", "All counted. Pick." },
        ["Whiskers"] = new[] { "Not that I care. Pick.", "Hm. This one?" },
        ["Mittens"] = new[] { "Purr... warm papers.", "Mrrp. Pick a nice one." },
        ["Sir Pounce"] = new[] { "The hunt for words!", "Pounce on one!" },
        ["Hopper"] = new[] { "Longest jump ever!", "Boing! Got it!" },
        ["Mossy"] = new[] { "Still ponds keep all.", "Slowly. Pick one." },
        ["Croak"] = new[] { "Dry papers. Hurry.", "Grumble. Pick." },
        ["Boo"] = new[] { "BOO! ...pick one.", "Spooky papers!" },
        ["Wisp"] = new[] { "Words that drifted here.", "Old copies, like old monitors." },
        ["Sheet"] = new[] { "Technically, I'm floating.", "Paper on paper." },
        ["Morel"] = new[] { "Slowly... pick.", "Damp and quiet. Choose." },
        ["Puff"] = new[] { "Hee! Spores! Kidding. Pick.", "Ooh, so many!" },
        ["Cap"] = new[] { "In my day we wrote it down.", "In my day: carbon paper." },
        ["Unit 7"] = new[] { "Picker online. 100%.", "Items loaded. Select 1." },
        ["Sprocket"] = new[] { "Freshly oiled papers!", "All tightened. Pick." },
        ["Glitch"] = new[] { "Pick pick one.", "No viruses. Probably." },
        ["Goop"] = new[] { "Nice papers!", "Sticky! Pick one." },
        ["Puddle"] = new[] { "Careful, don't spill.", "Quick, before I dry." },
        ["Blorp"] = new[] { "Blorp! Papers!", "Shloop. Pick." },
        ["Spike"] = new[] { "Point at one.", "Sharp choice, please." },
        ["Wedge"] = new[] { "Steady. Pick.", "Not tipping. Choose." },
        ["Delta"] = new[] { "New since last time.", "Something changed. Pick." },
    };
}

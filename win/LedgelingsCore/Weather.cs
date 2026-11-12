namespace Ledgelings.Core;

/// <summary>
/// Weather on a quiet screen (SPEC §7.20), the Mac's <c>Weather.swift</c>: when the screen counts as quiet, which
/// weather comes in which season, how a spell of it comes and eases off, the snow piles, who shares an umbrella, the
/// umbrella filling on the top edge, and what the wind does to a creature. The falling particles are
/// <see cref="Sky"/>, drawn with the shared <c>FXParticles</c>; the colony (<c>Colony.Weather.cs</c>) puts it all on
/// the screen. The codes saved are the Mac's (<c>snow</c>, <c>medium</c>, <c>sometimes</c>).
/// </summary>
public static partial class Weather
{
    // MARK: The kinds

    public enum Kind { Snow, Rain, Wind, Storm }
    /// <summary>How deep, how heavy, how strong.</summary>
    public enum Level { Low, Medium, High }
    /// <summary>How often weather comes once the screen is quiet.</summary>
    public enum Frequency { Rarely, Sometimes, Often }

    public static IReadOnlyList<Kind> Kinds { get; } = Enum.GetValues<Kind>();
    public static IReadOnlyList<Level> Levels { get; } = Enum.GetValues<Level>();
    public static IReadOnlyList<Frequency> Frequencies { get; } = Enum.GetValues<Frequency>();

    static string Code(Enum e) { var s = e.ToString(); return char.ToLowerInvariant(s[0]) + s[1..]; }

    /// <summary>Its raw value, the Mac's (<c>snow</c>), also its English name for the printed steps.</summary>
    public static string Code(this Kind k) => Code((Enum)k);
    public static string Name(this Kind k) => k.Code();
    public static Kind? KindNamed(string? code) => Kinds.Cast<Kind?>().FirstOrDefault(k => k!.Value.Code() == code);

    public static string Title(this Kind k) => L10n.Tr(k switch { Kind.Snow => "Snow", Kind.Rain => "Rain", Kind.Wind => "Wind", _ => "Storm" });

    /// <summary>What it does, for its row and its menu item's tooltip.</summary>
    public static string Detail(this Kind k) => L10n.Tr(k switch
    {
        Kind.Snow => "Flakes drift down and pile up on the bottom edge and the tops of windows; the creatures wade, shiver, build snowmen and throw snowballs",
        Kind.Rain => "Rain with splashes and puddles; the creatures open umbrellas and huddle under one when they stand close",
        Kind.Wind => "Gusts from one side blow leaves across; the creatures lean in, and a strong gust pushes the light ones",
        _ => "Rain and wind together: umbrellas turn inside out",
    });

    public static bool Snows(this Kind k) => k == Kind.Snow;
    public static bool Rains(this Kind k) => k is Kind.Rain or Kind.Storm;
    public static bool Blows(this Kind k) => k is Kind.Wind or Kind.Storm;

    public static string Code(this Level l) => Code((Enum)l);
    public static Level? LevelNamed(string? code) => Levels.Cast<Level?>().FirstOrDefault(l => l!.Value.Code() == code);
    public static string Title(this Level l) => L10n.Tr(l switch { Level.Low => "Low", Level.Medium => "Medium", _ => "High" });
    /// <summary>Times the medium amount.</summary>
    public static double Factor(this Level l) => l switch { Level.Low => 0.5, Level.Medium => 1, _ => 1.6 };

    public static string Code(this Frequency f) => Code((Enum)f);
    public static Frequency? FrequencyNamed(string? code) => Frequencies.Cast<Frequency?>().FirstOrDefault(f => f!.Value.Code() == code);
    public static string Title(this Frequency f) => L10n.Tr(f switch { Frequency.Rarely => "Rarely", Frequency.Sometimes => "Sometimes", _ => "Often" });
    /// <summary>About how many quiet minutes go by between two spells.</summary>
    public static double EveryMinutes(this Frequency f) => f switch { Frequency.Rarely => 60, Frequency.Sometimes => 20, _ => 5 };

    // MARK: The switches

    /// <summary>Every weather setting at once, as the settings hold them.</summary>
    public sealed record Switches
    {
        public bool Enabled { get; init; } = true;
        public bool Snow { get; init; } = true;
        public bool Rain { get; init; } = true;
        public bool Wind { get; init; } = true;
        public double QuietMinutes { get; init; } = 5;
        public Frequency Frequency { get; init; } = Frequency.Sometimes;
        public double LastsMinutes { get; init; } = 3;
        public Level SnowDepth { get; init; } = Level.Medium;
        public Level RainHeaviness { get; init; } = Level.Medium;
        public Level WindStrength { get; init; } = Level.Medium;
        /// <summary>Creatures closer than this (points, along the edge) share one umbrella; 0: everyone has its own.</summary>
        public double ShareDistance { get; init; } = 40;
        public bool FollowSeason { get; init; } = true;
        public bool WindowTops { get; init; } = true;
        /// <summary>Reduce motion as it stands now, the system's setting already read: half the particles, no pushing.</summary>
        public bool ReduceMotion { get; init; }

        /// <summary>Whether <paramref name="kind"/> may come on its own: everything it needs is switched on (a storm needs rain and wind).</summary>
        public bool Allows(Kind kind) => Enabled && kind switch
        {
            Kind.Snow => Snow,
            Kind.Rain => Rain,
            Kind.Wind => Wind,
            _ => Rain && Wind,
        };
    }

    // MARK: When the screen is quiet

    /// <summary>What the computer says about the screen now.</summary>
    public readonly record struct Screen(double KeyIdle, double CursorTravel, bool FullScreen = false, bool Activity = false, bool Meeting = false);

    /// <summary>The cursor may wander this many points in the quiet minutes and still count as left alone.</summary>
    public const double CursorAllowance = 150;

    /// <summary>Quiet: no key for <paramref name="minutes"/>, the cursor barely moved in them, nothing full screen, no activity, no meeting.</summary>
    public static bool IsQuiet(Screen s, double minutes) =>
        s.KeyIdle >= minutes * 60 && s.CursorTravel <= CursorAllowance && !s.FullScreen && !s.Activity && !s.Meeting;

    /// <summary>Someone is back: a key in the last two seconds, or the cursor moved more than a nudge in them.</summary>
    public static bool IsBack(double keyIdle, double recentTravel) => keyIdle < 2 || recentTravel > 60;

    /// <summary>The cursor's path, sampled now and then: how far it went in a window of time.</summary>
    public sealed class CursorTrail
    {
        readonly List<(double At, double X, double Y)> samples = new();
        public void Add(Pt p, double now, double keep)
        {
            samples.Add((now, p.X, p.Y));
            samples.RemoveAll(s => now - s.At > keep);
        }
        /// <summary>Points travelled since <paramref name="since"/>.</summary>
        public double Travel(double since)
        {
            var recent = samples.Where(s => s.At >= since).ToList();
            double sum = 0;
            for (int i = 1; i < recent.Count; i++) sum += Math.Sqrt(Math.Pow(recent[i].X - recent[i - 1].X, 2) + Math.Pow(recent[i].Y - recent[i - 1].Y, 2));
            return sum;
        }
        /// <summary>How long the trail goes back.</summary>
        public double Span => samples.Count == 0 ? 0 : samples[^1].At - samples[0].At;
        public void Reset() => samples.Clear();
    }

    // MARK: Which weather

    /// <summary>How likely each weather is in <paramref name="season"/>: snow mostly in winter, rain any time, wind in autumn.</summary>
    public static IReadOnlyDictionary<Kind, double> Weights(Effects.Season season, Switches switches)
    {
        Dictionary<Kind, double> b = !switches.FollowSeason
            ? new() { [Kind.Snow] = 1, [Kind.Rain] = 1, [Kind.Wind] = 1, [Kind.Storm] = 1 }
            : season switch
            {
                Effects.Season.Winter => new() { [Kind.Snow] = 6, [Kind.Rain] = 1, [Kind.Wind] = 1.5, [Kind.Storm] = 0.5 },
                Effects.Season.Spring => new() { [Kind.Snow] = 0.3, [Kind.Rain] = 4, [Kind.Wind] = 1.5, [Kind.Storm] = 1 },
                Effects.Season.Summer => new() { [Kind.Snow] = 0, [Kind.Rain] = 4, [Kind.Wind] = 1, [Kind.Storm] = 2 },
                _ => new() { [Kind.Snow] = 0.3, [Kind.Rain] = 3, [Kind.Wind] = 4, [Kind.Storm] = 2 },
            };
        return b.Where(kv => switches.Allows(kv.Key) && kv.Value > 0).ToDictionary(kv => kv.Key, kv => kv.Value);
    }

    /// <summary>One weather drawn from the weights with <paramref name="roll"/> in 0..&lt;1, or null when none is allowed.</summary>
    public static Kind? Pick(Effects.Season season, Switches switches, double roll)
    {
        var w = Weights(season, switches);
        var total = w.Values.Sum();
        if (total <= 0) return null;
        var left = roll * total;
        foreach (var kind in Kinds)
        {
            if (!w.TryGetValue(kind, out var v)) continue;
            if (left < v) return kind;
            left -= v;
        }
        return Kinds.Last(w.ContainsKey);
    }

    /// <summary>The chance per check, every <paramref name="step"/> seconds of quiet, that weather comes.</summary>
    public static double Chance(double step, Frequency frequency) => 1 - Math.Exp(-step / (frequency.EveryMinutes() * 60));

    // MARK: A spell of weather

    /// <summary>One weather from its start to its end: it comes in over a few seconds, stays its time, and eases off.</summary>
    public sealed class Spell
    {
        public Kind Kind { get; }
        public double Lasts { get; }
        public double Age { get; private set; }
        /// <summary>When it began easing off (its age then), or null.</summary>
        public double? EasingSince { get; private set; }
        /// <summary>Started by hand (the menu, Play now): the owner coming back does not end it.</summary>
        public bool ByHand { get; }
        public const double ComeIn = 6, EaseOff = 8;

        public Spell(Kind kind, double lasts, bool byHand = false) { Kind = kind; Lasts = lasts; ByHand = byHand; }

        public bool IsComing => EasingSince is null && Age < ComeIn;

        public void Update(double dt)
        {
            Age += dt;
            if (EasingSince is not null) return;
            if (Age >= Lasts) Ease();
        }
        /// <summary>Ease off from now (time up, or someone came back): never all at once.</summary>
        public void Ease() { EasingSince ??= Age; }
        public bool IsEasing => EasingSince is not null;
        /// <summary>How much of it there is, 0…1: rising as it comes, falling as it eases.</summary>
        public double Intensity
        {
            get
            {
                var rise = Math.Min(1, Age / ComeIn);
                return EasingSince is double since ? rise * Math.Max(0, 1 - (Age - since) / EaseOff) : rise;
            }
        }
        /// <summary>Eased off all the way: no more falling (the snow on the ground melts on its own).</summary>
        public bool IsOver => IsEasing && Intensity <= 0;
    }

    // MARK: Snow piles

    /// <summary>Snow lying along a surface (the bottom edge, a window's top): a height in art pixels per column, up to a cap.</summary>
    public sealed class Pile
    {
        readonly double[] heights;
        public double Cap { get; set; }
        public Pile(int width, double cap) { heights = new double[Math.Max(0, width)]; Cap = cap; }
        public IReadOnlyList<double> Heights => heights;
        public int Width => heights.Length;
        public double Height(int x) => x >= 0 && x < heights.Length ? heights[x] : 0;
        public double Deepest => heights.Length == 0 ? 0 : heights.Max();
        public double Average => heights.Length == 0 ? 0 : heights.Sum() / heights.Length;
        public bool IsEmpty => heights.All(h => h <= 0.01);

        /// <summary>A flake landed at column <paramref name="x"/>: a little more there, less either side, never past the cap.</summary>
        public void Land(int x, double amount = 0.5)
        {
            if (x < 0 || x >= heights.Length) return;
            Add(x, amount);
            Add(x - 1, amount / 2);
            Add(x + 1, amount / 2);
            Settle(x);
        }
        /// <summary>Snow everywhere at once, <paramref name="amount"/> deep.</summary>
        public void Grow(double amount) { for (int x = 0; x < heights.Length; x++) heights[x] = Math.Min(Cap, heights[x] + amount); }
        /// <summary>It melts: <paramref name="amount"/> less everywhere, never below nothing.</summary>
        public void Melt(double amount) { for (int x = 0; x < heights.Length; x++) heights[x] = Math.Max(0, heights[x] - amount); }
        /// <summary>A foot stepped at <paramref name="x"/>: a dent a pixel deep, two wide.</summary>
        public void Step(int x) { foreach (var k in new[] { x, x + 1 }) if (k >= 0 && k < heights.Length) heights[k] = Math.Max(0, heights[k] - 1); }
        public void Clear() => Array.Clear(heights);

        void Add(int x, double a) { if (x >= 0 && x < heights.Length) heights[x] = Math.Min(Cap, heights[x] + a); }

        void Settle(int x)
        {
            // A few passes outward, so a heap slides down both sides rather than leaving a step further out.
            for (int pass = 0; pass < 6; pass++)
            {
                var moved = false;
                for (int k = Math.Max(0, x - 10); k <= Math.Min(heights.Length - 1, x + 10); k++)
                {
                    foreach (var n in new[] { k - 1, k + 1 })
                    {
                        if (n < 0 || n >= heights.Length || heights[k] - heights[n] <= 2) continue;
                        var slide = (heights[k] - heights[n] - 2) / 2 + 0.01;
                        heights[k] -= slide;
                        heights[n] += slide;
                        moved = true;
                    }
                }
                if (!moved) break;
            }
        }
    }

    /// <summary>The tallest the bottom pile grows, in art pixels, and a window top's.</summary>
    public static double BottomCap(Level depth) => 8 * depth.Factor();
    public static double WindowCap(Level depth) => 4 * depth.Factor();
    /// <summary>Art pixels of snow a second, at full intensity, on top of what the flakes bring.</summary>
    public static double Snowfall(Level depth) => 0.05 * depth.Factor();
    /// <summary>Art pixels melting a second once the snow has stopped: slowly.</summary>
    public const double MeltRate = 0.03;
    /// <summary>A creature in snow this deep (a share of the cap) walks this much slower: at most half its pace.</summary>
    public static double Wading(double depth, double cap) => cap <= 0 ? 1 : 1 - 0.5 * Math.Min(1, Math.Max(0, depth / cap));

    // MARK: Umbrellas

    /// <summary>A creature where the rain can fall on it: which edge it stands on and where along it, in points.</summary>
    public readonly record struct Standing(int Index, int Edge, double Along);

    /// <summary>The most under one umbrella.</summary>
    public const int MostUnderOne = 3;

    /// <summary>Who shares an umbrella: creatures on the same edge each within <paramref name="distance"/> of the next,
    /// at most three to one; everyone else has its own.</summary>
    public static List<List<int>> UmbrellaGroups(IEnumerable<Standing> standing, double distance)
    {
        var all = standing.ToList();
        var groups = new List<List<int>>();
        foreach (var edge in all.Select(s => s.Edge).Distinct().OrderBy(e => e))
        {
            var row = all.Where(s => s.Edge == edge).OrderBy(s => s.Along).ThenBy(s => s.Index).ToList();
            var current = new List<Standing>();
            foreach (var s in row)
            {
                if (current.Count > 0 && distance > 0 && s.Along - current[^1].Along <= distance && current.Count < MostUnderOne) current.Add(s);
                else
                {
                    if (current.Count > 0) groups.Add(current.Select(c => c.Index).ToList());
                    current = new List<Standing> { s };
                }
            }
            if (current.Count > 0) groups.Add(current.Select(c => c.Index).ToList());
        }
        return groups;
    }
    /// <summary>The one holding a group's umbrella: the middle one.</summary>
    public static int Holder(IReadOnlyList<int> group) => group[group.Count / 2];
    /// <summary>An umbrella's canopy for <paramref name="count"/> creatures under it, in the creatures' own pixels.</summary>
    public static int UmbrellaWidth(int count) => 27 + 22 * Math.Max(0, count - 1);

    /// <summary>The umbrella of a creature hanging from the top edge: upside down, it is a bowl, and the rain fills it.</summary>
    public sealed class Bowl
    {
        public enum State { Holding, Tipping, Fallen }
        public enum Event { Full, Spills }
        public double Water { get; private set; }
        public State Now { get; private set; } = State.Holding;
        double tipping;
        /// <summary>Seconds of medium rain to fill it.</summary>
        public const double FillSeconds = 20;
        /// <summary>Seconds it takes to tip over once full.</summary>
        public const double TipSeconds = 1.2;

        /// <summary>Rain at <paramref name="intensity"/> (0…1) with <paramref name="heaviness"/>: it fills; full, it tips; tipped, it spills and falls.</summary>
        public Event? Update(double dt, double intensity, Level heaviness)
        {
            switch (Now)
            {
                case State.Holding:
                    Water = Math.Min(1, Water + dt * intensity * heaviness.Factor() / FillSeconds);
                    if (Water >= 1) { Now = State.Tipping; tipping = 0; return Event.Full; }
                    break;
                case State.Tipping:
                    tipping += dt;
                    if (tipping >= TipSeconds) { Now = State.Fallen; Water = 0; return Event.Spills; }
                    break;
            }
            return null;
        }
        /// <summary>How far it has tipped, 0…1.</summary>
        public double Tip => Now switch { State.Holding => 0, State.Tipping => Math.Min(1, tipping / TipSeconds), _ => 1 };
    }

    /// <summary>Seconds a puddle takes to dry once the rain has stopped, at its deepest.</summary>
    public const double DrySeconds = 90;

    // MARK: Wind

    /// <summary>The wind of one spell: from the left (+1, blowing rightwards) or the right (-1), with gusts.</summary>
    public sealed class Wind
    {
        public double From { get; }
        public Level Strength { get; }
        public const double GustEvery = 9, GustLasts = 2.5;
        public Wind(bool fromLeft, Level strength) { From = fromLeft ? 1 : -1; Strength = strength; }

        /// <summary>How hard it blows at <paramref name="time"/> seconds into the spell, 0…1.</summary>
        public double Force(double time)
        {
            var phase = time % GustEvery;
            var gust = phase < GustLasts ? Math.Sin(Math.PI * phase / GustLasts) : 0;
            return 0.3 + 0.7 * gust * gust;
        }
        /// <summary>A gust at its peak now: the middle of one crossed in this step.</summary>
        public bool Peaks(double time, double dt)
        {
            const double mid = GustLasts / 2;
            double a = (time - dt) % GustEvery, b = time % GustEvery;
            return a < mid && b >= mid;
        }
        /// <summary>Sideways speed it gives the particles, in art pixels a second.</summary>
        public double Drift(double time, double intensity) => From * Force(time) * 70 * Strength.Factor() * intensity;
        /// <summary>How far the creatures lean into it, in radians.</summary>
        public double Lean(double time, double intensity) => -From * Force(time) * 0.18 * Strength.Factor() * intensity;
    }

    /// <summary>Times its pace a creature walks: slower into the wind, faster with it. <paramref name="walking"/> is +1 rightwards.</summary>
    public static double WindPace(double walking, Wind wind, double force)
    {
        var f = force * wind.Strength.Factor();
        return walking * wind.From > 0 ? 1 + 0.3 * f : 1 - 0.4 * Math.Min(1, f);
    }

    /// <summary>Points a gust at <paramref name="force"/> pushes a creature of <paramref name="size"/> along the wind.</summary>
    public static double Push(double size, double force, Level strength)
    {
        if (size <= 0) return 0;
        var p = 6 * force * strength.Factor() / (size * size);
        return p < 0.75 ? 0 : Math.Round(p, MidpointRounding.AwayFromZero);
    }

    /// <summary>A gust this strong blows a creature of <paramref name="size"/> off the top edge.</summary>
    public static bool BlowsOff(double size, double force, Level strength) => force * strength.Factor() / size >= 1.25;

    /// <summary>Whether a gust turns an umbrella inside out: a strong enough gust, and <paramref name="roll"/>.</summary>
    public static bool TurnsInsideOut(double force, Level strength, double roll) => force * strength.Factor() >= 0.9 && roll < 0.4;

    // MARK: Words

    /// <summary>The kinds of line, as the tables name them.</summary>
    public static readonly string[] LineKinds = { "snow", "cold", "snowman", "throw", "hit", "rain", "share", "soaked", "wind", "insideOut", "blown" };

    /// <summary>The line <paramref name="name"/> says for <paramref name="kind"/>; <paramref name="friend"/> fills <c>{friend}</c>.</summary>
    public static string Line(string name, string kind, string friend, Random rng)
    {
        var l = Languages.Current;
        var pool = LinesIn(l).TryGetValue(name, out var mine) && mine.TryGetValue(kind, out var own) ? own
            : AnyoneIn(l).TryGetValue(kind, out var anyone) ? anyone : Array.Empty<string>();
        var line = pool.Count == 0 ? "" : rng.Pick(pool);
        return CursorMoods.Current.Adjust(line.Replace("{friend}", friend, StringComparison.Ordinal));
    }

    /// <summary>Every character's lines in <paramref name="l"/>: the English, each with its own from <see cref="Shared"/>
    /// (<c>weather.lines</c>) when it has some there.</summary>
    public static IReadOnlyDictionary<string, IReadOnlyDictionary<string, IReadOnlyList<string>>> LinesIn(Language l)
    {
        if (Shared.In(l) is not Shared s || s.WeatherLines.Count == 0) return EnglishLines;
        return EnglishLines.ToDictionary(kv => kv.Key, kv => s.WeatherLines.TryGetValue(kv.Key, out var t) && t.Count > 0
            ? (IReadOnlyDictionary<string, IReadOnlyList<string>>)t.ToDictionary(p => p.Key, p => (IReadOnlyList<string>)p.Value)
            : kv.Value);
    }

    /// <summary>Anyone's lines in <paramref name="l"/>, for a character the user made.</summary>
    public static IReadOnlyDictionary<string, IReadOnlyList<string>> AnyoneIn(Language l) =>
        Shared.In(l) is Shared s && s.WeatherAnyone.Count > 0
            ? s.WeatherAnyone.ToDictionary(p => p.Key, p => (IReadOnlyList<string>)p.Value)
            : EnglishAnyone;
}

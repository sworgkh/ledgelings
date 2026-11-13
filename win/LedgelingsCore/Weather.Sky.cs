using Ledgelings.Core.PixelFX;

namespace Ledgelings.Core;

public static partial class Weather
{
    /// <summary>A window's top as the sky sees it: where it is in art pixels (y down, from the monitor's top-left), and
    /// which of its columns are open to the sky (not under another window in front).</summary>
    public sealed record Ledge(int X, int Y, bool[] Open)
    {
        public int Width => Open.Length;
    }

    /// <summary>The season's light particles (Settings › Weather &amp; Sky).</summary>
    public enum LightKind { Snow, Leaves, Petals }
    /// <summary>Pixels a second it falls: petals drift, leaves flutter, flakes float.</summary>
    public static double Fall(this LightKind k) => k switch { LightKind.Snow => 12, LightKind.Leaves => 22, _ => 15 };
    public static string Code(this LightKind k) => Code((Enum)k);

    /// <summary>The season's light particles: a few snowflakes in winter, leaves in autumn, petals in spring, falling
    /// from above the top edge the whole height and gone at the bottom. <c>Intensity</c> 0…1 rises as they come out.</summary>
    public readonly record struct Light(LightKind Kind, double Count, double Intensity = 1);

    /// <summary>
    /// What falls on one monitor and what lies there, the Mac's <c>Weather+Sky.swift</c>: the flakes, drops and leaves
    /// (the shared <see cref="FXParticles"/>, in art pixels, y down), the snow along the bottom and on the window tops,
    /// the puddles, and the splashes. Drawn into an <see cref="FXFrame"/> the size of the monitor in art pixels; the
    /// overlay scales it up, pixel for pixel.
    /// </summary>
    public sealed class Sky
    {
        public readonly int W, H;
        public readonly FXParticles Particles;
        /// <summary>Where blown snow and the shower off a window come down: on the bottom pile.</summary>
        public Pile Bottom { get; }
        readonly Dictionary<int, (Ledge Ledge, Pile Pile)> ledges = new();
        /// <summary>How wet the bottom edge is, per column, 0…1: a puddle where it is over a half.</summary>
        public readonly double[] Wet;
        /// <summary>Where puddles can form along the bottom: a few dips, not the whole edge.</summary>
        public readonly bool[] Dips;
        readonly Rng rng;
        /// <summary>Snow showers off windows that moved or closed, as they start (for the film's steps).</summary>
        public Action<int, int>? OnShower;
        /// <summary>Leaves (autumn) rather than dust on the wind.</summary>
        public bool Leafy;

        public static readonly FXColor[] SnowColours = new[] { "#ffffff", "#eef4ff", "#dce8f8" }.Select(FX.Hex).ToArray();
        public static readonly FXColor RainColour = FX.Hex("#9cc4ff");
        public static readonly FXColor[] Splash = new[] { "#d8ecff", "#9cc4ff", "#6f9fe6", "#4a78c4" }.Select(FX.Hex).ToArray();
        public static readonly FXColor[] LeafColours = new[] { "#d9822b", "#c9541f", "#e0b13a", "#8f6a2f" }.Select(FX.Hex).ToArray();
        public static readonly FXColor[] DustColours = new[] { "#c8b89a", "#a89878", "#d8ccb4" }.Select(FX.Hex).ToArray();
        // The pile in Blocky's style: a dark-tint outline on top, a light line under it, a flat fill, a shade low down.
        static readonly FXColor SnowOutline = FX.Hex("#8aa2c0"), SnowLight = FX.Hex("#ffffff"), SnowFill = FX.Hex("#e6eef8"), SnowShade = FX.Hex("#c4d3e6");
        static readonly FXColor PrintShade = FX.Hex("#b2c4dc");
        static readonly FXColor PuddleOutline = FX.Hex("#2e5190"), PuddleLight = FX.Hex("#b4d4ff"), PuddleFill = FX.Hex("#4f82d6");

        public Sky(int width, int height, Level depth, double seed = 7)
        {
            W = Math.Max(1, width);
            H = Math.Max(1, height);
            rng = new Rng(seed);
            Particles = new FXParticles(seed: seed + 1, sparks: Splash);
            Bottom = new Pile(W, BottomCap(depth));
            Wet = new double[W];
            Dips = new bool[W];
            var x = (int)rng.Range(10, 40);
            while (x < W)
            {
                var width2 = (int)rng.Range(8, 22);
                for (int k = x; k < Math.Min(W, x + width2); k++) Dips[k] = true;
                x += width2 + (int)rng.Range(30, 90);
            }
            Particles.Ground = gx => GroundY((int)gx);
        }

        /// <summary>The row the bottom pile's surface is on at column <paramref name="x"/>.</summary>
        public int GroundY(int x) => H - 1 - (int)Math.Floor(Bottom.Height(Math.Min(Math.Max(0, x), W - 1)));

        public bool IsEmpty => Particles.Count == 0 && Bottom.IsEmpty && ledges.Values.All(v => v.Pile.IsEmpty) && Wet.All(v => v < 0.05);

        /// <summary>The depth settings changed: the caps follow.</summary>
        public void SetDepth(Level depth)
        {
            Bottom.Cap = BottomCap(depth);
            foreach (var v in ledges.Values) v.Pile.Cap = WindowCap(depth);
        }

        // MARK: Windows

        /// <summary>The windows as they stand now. A window gone, moved or resized drops its snow as a little shower; a new one starts bare.</summary>
        public void SetLedges(IReadOnlyDictionary<int, Ledge> now, Level depth)
        {
            foreach (var (id, was) in ledges.ToList())
            {
                if (now.TryGetValue(id, out var still) && still.X == was.Ledge.X && still.Y == was.Ledge.Y && still.Width == was.Ledge.Width) continue;
                Shower(was.Ledge, was.Pile);
                ledges.Remove(id);
            }
            foreach (var (id, ledge) in now)
            {
                if (ledges.TryGetValue(id, out var have)) ledges[id] = (ledge, have.Pile);
                else ledges[id] = (ledge, new Pile(ledge.Width, WindowCap(depth)));
            }
        }

        void Shower(Ledge ledge, Pile pile)
        {
            if (pile.Average <= 0.3) return;
            var flakes = 0;
            for (int x = 0; x < ledge.Width; x++)
            {
                if (pile.Height(x) <= 0.3 || !ledge.Open[x]) continue;
                var n = (int)Math.Ceiling(pile.Height(x));
                for (int k = 0; k < n; k++)
                {
                    if ((x + k) % 2 != 0) continue;
                    Particles.Spawn(FXKind.Grit, ledge.X + x, ledge.Y - k, rng.Range(-12, 12), rng.Range(-30, 5), 3, SnowColours[k % 3], 1);
                    flakes++;
                }
            }
            OnShower?.Invoke(ledge.X, flakes);
        }

        /// <summary>Snow on a window top, as an outsider sees it (tests, the film).</summary>
        public Pile? LedgePile(int id) => ledges.TryGetValue(id, out var v) ? v.Pile : null;

        // MARK: Every frame

        /// <summary>One step: <paramref name="kind"/> falling at <paramref name="intensity"/> (0 once it is over), the
        /// wind's drift in pixels a second, as <paramref name="s"/> say; and <paramref name="light"/>, the season's light
        /// particles, if they are out. Reduce motion halves them all.</summary>
        public void Update(double dt, Kind? kind, double intensity, double drift, Switches s, Light? light = null)
        {
            Particles.Wind = drift;
            if (kind is Kind k && intensity > 0) Spawn(dt, k, intensity, drift, s);
            if (light is { } l && l.Intensity > 0) SpawnLight(dt, l, s.ReduceMotion);
            Particles.Update(dt);
            Land(s);
            var snowing = kind == Kind.Snow && intensity > 0 && s.SnowPiles;
            if (snowing)
            {
                Bottom.Grow(dt * Snowfall(s.SnowDepth) * intensity);
                if (s.WindowTops) foreach (var v in ledges.Values) v.Pile.Grow(dt * Snowfall(s.SnowDepth) * intensity * 0.6);
            }
            else
            {
                Bottom.Melt(dt * MeltRate);
                foreach (var v in ledges.Values) v.Pile.Melt(dt * MeltRate * 1.5);
            }
            if (!(kind is Kind r && r.Rains() && intensity > 0 && s.Puddles))
                for (int x = 0; x < Wet.Length; x++) if (Wet[x] > 0) Wet[x] = Math.Max(0, Wet[x] - dt / (s.Puddles ? DrySeconds : 1));
            if (!s.WindowTops) foreach (var v in ledges.Values) if (!v.Pile.IsEmpty) v.Pile.Clear();
        }

        /// <summary>Everything gone at once: what falls, what lies, the puddles (Stop, once the picture has faded).</summary>
        public void ClearAll()
        {
            Particles.List.Clear();
            Bottom.Clear();
            foreach (var v in ledges.Values) v.Pile.Clear();
            Array.Clear(Wet);
        }

        /// <summary>The lowest row anything has been born on so far (rows count down from the monitor's top edge): below
        /// zero, everything starts above the screen and falls the whole height.</summary>
        public double SpawnTop { get; private set; } = double.NegativeInfinity;
        /// <summary>The falling things on the monitor now: flakes, drops and leaves, not the splashes or puffs.</summary>
        public int Falling => Particles.List.Count(p => p.K is FXKind.Flake or FXKind.Drop or FXKind.Leaf);

        double owedSnow, owedRain, owedLeaf, owedLight;

        /// <summary>Particles a second that keep <paramref name="count"/> on a monitor this wide, each falling the whole
        /// height at <paramref name="fall"/> pixels a second: as many are born as reach the bottom.</summary>
        public static double BirthRate(double count, double fall, int width, int height) =>
            height <= 0 || fall <= 0 ? 0 : count * width / ReferenceWidth * fall / height;

        /// <summary>How fast snow, rain and the wind's leaves fall, in pixels a second.</summary>
        public static double SnowFall(Switches s) => 16 * s.SnowSpeed;
        public static double RainFall(Switches s) => 260 * s.RainSpeed;
        public const double LeafFall = 28;

        (double X, double Y) SpawnPoint(double drift, double fall)
        {
            // Upwind, some start off the side, so the wind carries them in and leaves no bare strip.
            var margin = Math.Min(W, Math.Abs(drift) * H / fall);
            var x = rng.Range(-margin * (drift > 0 ? 1 : 0), W + margin * (drift < 0 ? 1 : 0));
            return (x, rng.Range(-6, -1));
        }

        void Born(double y) => SpawnTop = Math.Max(SpawnTop, y);

        void Spawn(double dt, Kind kind, double intensity, double drift, Switches s)
        {
            var k = intensity * (s.ReduceMotion ? 0.5 : 1);
            double h = H;
            if (kind.Snows())
            {
                var fall = SnowFall(s);
                owedSnow += dt * k * BirthRate(s.SnowCount, fall, W, H);
                while (owedSnow >= 1)
                {
                    owedSnow -= 1;
                    var (x, y) = SpawnPoint(drift * 0.5, fall);
                    var big = rng.Chance(s.FlakeSize.BigShare());
                    Particles.Spawn(FXKind.Flake, x, y, drift * 0.5, fall * rng.Range(0.5, 1), h / fall * 3 + 30, rng.Pick(SnowColours), big ? 1.6 : 1, fall: fall);
                    Born(y);
                }
            }
            if (kind.Rains())
            {
                var fall = RainFall(s);
                owedRain += dt * k * BirthRate(s.RainCount * (kind.Blows() ? 1.3 : 1), fall, W, H);
                while (owedRain >= 1)
                {
                    owedRain -= 1;
                    var (x, y) = SpawnPoint(drift, fall);
                    Particles.Spawn(FXKind.Drop, x, y, drift, fall * rng.Range(0.9, 1.1), h / fall * 3 + 5, RainColour, 1);
                    Born(y);
                }
            }
            if (kind.Blows())
            {
                // Leaves in autumn, dust the rest of the year (Leafy set by the colony), falling from the top too.
                owedLeaf += dt * k * BirthRate(WindLeaves * s.WindStrength.Factor() * (kind.Rains() ? 0.5 : 1), LeafFall, W, H);
                while (owedLeaf >= 1)
                {
                    owedLeaf -= 1;
                    var (x, y) = SpawnPoint(drift, LeafFall);
                    Particles.Spawn(FXKind.Leaf, x, y, drift, 0, h / LeafFall * 3 + 10, rng.Pick(Leafy ? LeafColours : DustColours),
                                    rng.Chance(0.5) ? 1.6 : 1, fall: LeafFall);
                    Born(y);
                }
            }
        }

        public static readonly FXColor[] PetalColours = new[] { "#ffd1dc", "#ffb3c6", "#f7a1b5", "#fff0f4" }.Select(FX.Hex).ToArray();

        void SpawnLight(double dt, Light light, bool reduced)
        {
            var fall = light.Kind.Fall();
            owedLight += dt * light.Intensity * (reduced ? 0.5 : 1) * BirthRate(light.Count, fall, W, H);
            while (owedLight >= 1)
            {
                owedLight -= 1;
                double x = rng.Range(0, W), y = rng.Range(-6, -1), life = (double)H / fall * 3 + 10;
                switch (light.Kind)
                {
                    case LightKind.Snow:
                        Particles.Spawn(FXKind.Flake, x, y, 0, fall * 0.6, life, rng.Pick(SnowColours), rng.Chance(0.2) ? 1.6 : 1, 0, FXFlag.Light, fall);
                        break;
                    case LightKind.Leaves:
                        Particles.Spawn(FXKind.Leaf, x, y, 0, 0, life, rng.Pick(LeafColours), rng.Chance(0.5) ? 1.6 : 1, 0, FXFlag.Light, fall);
                        break;
                    default:
                        Particles.Spawn(FXKind.Leaf, x, y, 0, 0, life, rng.Pick(PetalColours), rng.Chance(0.4) ? 1.6 : 1, 0, FXFlag.Light, fall);
                        break;
                }
                Born(y);
            }
        }

        /// <summary>Flakes and drops that reached a surface stop there: snow on the pile, a splash and a wet patch for
        /// rain. The season's light ones and the leaves are simply gone.</summary>
        void Land(Switches s)
        {
            var list = Particles.List;
            for (int i = list.Count - 1; i >= 0; i--)
            {
                var p = list[i];
                if (p.K == FXKind.Leaf)
                {
                    if (p.X < -W || p.X > W * 2 || p.Y >= GroundY((int)Math.Floor(p.X))) list.RemoveAt(i);
                    continue;
                }
                if (!((p.K == FXKind.Flake || p.K == FXKind.Drop) && p.Delay <= 0)) continue;
                var x = (int)Math.Floor(p.X);
                if (x < -Math.Max(40, W) || x > W * 2 || p.Y > H + 4) { list.RemoveAt(i); continue; }
                var light = (p.Flag & FXFlag.Light) != 0;
                var before = p.Y - p.Vy / 60;
                if (!light && s.WindowTops && LedgeHit(x, before, p.Y) is (int id, int top))
                {
                    list.RemoveAt(i);
                    if (p.K == FXKind.Flake) { if (s.SnowPiles) ledges[id].Pile.Land(x - ledges[id].Ledge.X, 0.35); }
                    else SplashAt(x, top);
                    continue;
                }
                if (x < 0 || x >= W) continue;
                var g = GroundY(x);
                if (p.Y >= g)
                {
                    list.RemoveAt(i);
                    if (light) continue;
                    if (p.K == FXKind.Flake) { if (s.SnowPiles) Bottom.Land(x, 0.35); }
                    else
                    {
                        SplashAt(x, g);
                        if (s.Puddles) foreach (var k in new[] { x - 1, x, x + 1 }) if (k >= 0 && k < W && Dips[k]) Wet[k] = Math.Min(1, Wet[k] + 0.012);
                    }
                }
            }
        }

        /// <summary>The ledge a particle at column <paramref name="x"/> crossed falling from <paramref name="from"/> to <paramref name="to"/>, and the row it hit.</summary>
        (int, int)? LedgeHit(int x, double from, double to)
        {
            foreach (var (id, v) in ledges)
            {
                var col = x - v.Ledge.X;
                if (col < 0 || col >= v.Ledge.Width || !v.Ledge.Open[col]) continue;
                var top = v.Ledge.Y - (int)Math.Floor(v.Pile.Height(col));
                if (from < top && to >= top) return (id, top);
            }
            return null;
        }

        void SplashAt(double x, double y)
        {
            if (!rng.Chance(0.35)) return;
            for (int k = 0; k < 2; k++) Particles.Spawn(FXKind.Spark, x, y - 1, rng.Range(-40, 40), rng.Range(-110, -50), rng.Range(0.18, 0.3), 0, 1);
        }

        // MARK: Creatures in it

        /// <summary>A creature walked over column <paramref name="x"/> of the bottom: a footprint, a dent in the snow.</summary>
        public void Footprint(int x) => Bottom.Step(x);

        /// <summary>How deep the snow is at column <paramref name="x"/>, and the cap.</summary>
        public (double Depth, double Cap) Depth(int x) => (Bottom.Height(x), Bottom.Cap);

        /// <summary>A puff of snow kicked up, or a snowball bursting.</summary>
        public void Puff(double x, double y, int count = 6)
        {
            for (int k = 0; k < count; k++) Particles.Spawn(FXKind.Grit, x, y, rng.Range(-30, 30), rng.Range(-80, -20), 1.2, rng.Pick(SnowColours), 1);
        }

        /// <summary>The water spilled from an umbrella: a burst of drops where it lands.</summary>
        public void Spill(double x, double y)
        {
            for (int k = 0; k < 14; k++) Particles.Spawn(FXKind.Spark, x + rng.Range(-6, 6), y, rng.Range(-60, 60), rng.Range(-90, 20), rng.Range(0.3, 0.6), 0, 1);
            for (int k = (int)x - 6; k <= (int)x + 6; k++) if (k >= 0 && k < W) Wet[k] = Math.Min(1, Wet[k] + 0.3);
        }

        /// <summary>Snow lies thick enough here for a snowman.</summary>
        public bool CanBuildSnowman(int x) => Bottom.Height(x) >= Bottom.Cap * 0.4;

        /// <summary>Fill the piles by hand: the film's and the tests' way to a given depth.</summary>
        public void FillBottom(double amount) => Bottom.Grow(amount);
        public void FillLedges(double amount) { foreach (var v in ledges.Values) v.Pile.Grow(amount); }

        // MARK: Drawing

        /// <summary>Everything, into <paramref name="frame"/> (cleared first): the piles and puddles, then what is falling.</summary>
        public void Draw(FXFrame frame)
        {
            frame.Clear();
            var p = new Painter(frame);
            p.Reset();
            DrawPile(Bottom, 0, H - 1, null, true, frame);
            foreach (var v in ledges.Values) DrawPile(v.Pile, v.Ledge.X, v.Ledge.Y - 1, v.Ledge.Open, false, frame);
            DrawPuddles(frame);
            Particles.Draw(p, null);
        }

        static void Put(FXFrame f, int x, int y, FXColor c)
        {
            if (x < 0 || y < 0 || x >= f.W || y >= f.H) return;
            f.Color[y * f.W + x] = c;
        }

        static void DrawPile(Pile pile, int x0, int floor, bool[]? open, bool prints, FXFrame f)
        {
            if (pile.IsEmpty) return;
            for (int x = 0; x < pile.Width; x++)
            {
                if (open is not null && !open[x]) continue;
                var n = (int)Math.Floor(pile.Height(x));
                if (n <= 0) continue;
                var X = x0 + x;
                var dent = prints && x > 0 && x < pile.Width - 1 && pile.Height(x) + 0.6 < Math.Min(pile.Height(x - 1), pile.Height(x + 1));
                for (int k = 0; k < n; k++)
                {
                    var y = floor - k;
                    FXColor c;
                    if (k == n - 1) c = SnowOutline;
                    else if (k == n - 2) c = dent ? PrintShade : SnowLight;
                    else if (k == 0 && n > 3) c = SnowShade;
                    else c = SnowFill;
                    Put(f, X, y, c);
                }
            }
        }

        void DrawPuddles(FXFrame f)
        {
            var x = 0;
            while (x < W)
            {
                if (Wet[x] <= 0.5) { x++; continue; }
                var end = x;
                while (end < W && Wet[end] > 0.5) end++;
                if (end - x >= 3)
                {
                    var g = GroundY(x);
                    double most = 0;
                    for (int k = x; k < end; k++) most = Math.Max(most, Wet[k]);
                    var deep = most > 0.85 ? 2 : 1;
                    for (int k = x; k < end; k++)
                    {
                        var edge = k == x || k == end - 1;
                        Put(f, k, g - deep, PuddleOutline);
                        for (int d = 0; d < deep; d++) Put(f, k, g - d, edge ? PuddleOutline : (d == deep - 1 && k < x + (end - x) / 2 ? PuddleLight : PuddleFill));
                    }
                }
                x = end;
            }
        }
    }
}

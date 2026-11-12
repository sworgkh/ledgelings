// Numbers, easing, randomness, noise and colours for the effects: a port of pixelfx's core
// (https://github.com/patch-gg/pixelfx, MIT, see THIRD-PARTY-NOTICES.md), kept to the same
// arithmetic so an effect drawn here at time t is the same picture pixelfx draws. Where JavaScript
// rounds, truncates or wraps a number its own way, the helpers below do it the JavaScript way.
// The Mac's twin is Sources/LedgelingsCore/PixelFX/FXMath.swift, line for line.

global using FXColor = System.UInt32;

using System.Globalization;
using System.Runtime.CompilerServices;

namespace Ledgelings.Core.PixelFX;

/// <summary>The effects' toolkit: everything an effect draws with lives under this name.</summary>
public static partial class FX
{
    public const double Tau = Math.PI * 2;

    // JavaScript's number rules

    /// <summary><c>x | 0</c>: truncated toward zero and wrapped to 32 bits, NaN and infinity to 0.</summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static int I32(double x)
    {
        if (!double.IsFinite(x)) return 0;
        var t = Math.Truncate(x);
        if (t >= -2_147_483_648d && t <= 2_147_483_647d) return (int)t;
        var m = t % 4_294_967_296d;
        var u = m < 0 ? m + 4_294_967_296d : m;
        return unchecked((int)(uint)u);
    }
    /// <summary><c>x &amp; 255</c> for a double, as JavaScript reads it.</summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static uint Byte(double x) => unchecked((uint)I32(x)) & 255;
    /// <summary><c>Math.round</c>: halves go up, toward positive infinity. Never Math.Round (halves to even).</summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static double Round(double x) => Math.Floor(x + 0.5);
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static double Floor(double x) => Math.Floor(x);
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static double Ceil(double x) => Math.Ceiling(x);
    /// <summary><c>a % b</c> on doubles: the sign of a.</summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static double Mod(double a, double b) => a % b;
    /// <summary><c>Math.min</c>/<c>Math.max</c> of two.</summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static double Min(double a, double b) => a < b ? a : b;
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static double Max(double a, double b) => a > b ? a : b;
    /// <summary><c>Math.hypot</c> the way V8 works it out (scaled to the larger, Kahan-summed), not libm's.</summary>
    public static double Hypot(double a, double b)
    {
        bool nan = false;
        double max = 0, x = 0, y = 0;
        if (double.IsNaN(a)) nan = true; else { x = Math.Abs(a); if (x > max) max = x; }
        if (double.IsNaN(b)) nan = true; else { y = Math.Abs(b); if (y > max) max = y; }
        if (double.IsPositiveInfinity(max)) return double.PositiveInfinity;
        if (nan) return double.NaN;
        if (max == 0) return 0;
        double sum = 0, compensation = 0;
        foreach (var v in (ReadOnlySpan<double>)[x, y])
        {
            var n = v / max;
            var summand = n * n - compensation;
            var preliminary = sum + summand;
            compensation = (preliminary - sum) - summand;
            sum = preliminary;
        }
        return Math.Sqrt(sum) * max;
    }

    // Numbers and easing

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static double Clamp(double x, double a = 0, double b = 1) => x < a ? a : x > b ? b : x;
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static double Lerp(double a, double b, double t) => a + (b - a) * t;
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static double InvLerp(double a, double b, double x) => b == a ? 0 : (x - a) / (b - a);
    public static double Remap(double x, double a0, double a1, double b0, double b1) => Lerp(b0, b1, InvLerp(a0, a1, x));
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static double Fract(double x) => x - Floor(x);
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static double Wrap(double x, double m) => Mod(Mod(x, m) + m, m);
    /// <summary>Progress 0...1 of t through the window [t0, t1]: 0 before it, 1 after it.</summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static double Seg(double t, double t0, double t1) => Clamp((t - t0) / (t1 - t0));
    /// <summary>Hermite smoothstep of x between e0 and e1.</summary>
    public static double Smooth(double e0, double e1, double x)
    {
        var t = Seg(x, e0, e1);
        return t * t * (3 - 2 * t);
    }
    /// <summary>0 → 1 → 0 over [t0, t1], a sine bump.</summary>
    public static double Bump(double t, double t0, double t1) => t <= t0 || t >= t1 ? 0 : Math.Sin(Math.PI * Seg(t, t0, t1));
    public static double Pingpong(double x) => 1 - Math.Abs(Wrap(x, 2) - 1);
    public static double Dist(double x0, double y0, double x1, double y1) => Hypot(x1 - x0, y1 - y0);

    /// <summary>Easing curves: 0...1 in, 0...1 out (back and elastic overshoot).</summary>
    public static class Ease
    {
        public static double Linear(double t) => t;
        public static double InQuad(double t) => t * t;
        public static double OutQuad(double t) => 1 - (1 - t) * (1 - t);
        public static double InOutQuad(double t) => t < 0.5 ? 2 * t * t : 1 - Math.Pow(-2 * t + 2, 2) / 2;
        public static double InCubic(double t) => t * t * t;
        public static double OutCubic(double t) => 1 - Math.Pow(1 - t, 3);
        public static double InOutCubic(double t) => t < 0.5 ? 4 * t * t * t : 1 - Math.Pow(-2 * t + 2, 3) / 2;
        public static double InQuart(double t) => t * t * t * t;
        public static double OutQuart(double t) => 1 - Math.Pow(1 - t, 4);
        public static double InExpo(double t) => t <= 0 ? 0 : Math.Pow(2, 10 * t - 10);
        public static double OutExpo(double t) => t >= 1 ? 1 : 1 - Math.Pow(2, -10 * t);
        public static double InSine(double t) => 1 - Math.Cos((t * Math.PI) / 2);
        public static double OutSine(double t) => Math.Sin((t * Math.PI) / 2);
        public static double InOutSine(double t) => -(Math.Cos(Math.PI * t) - 1) / 2;
        public static double InBack(double t, double s = 1.70158) =>
            t <= 0 ? 0 : t >= 1 ? 1 : (s + 1) * t * t * t - s * t * t;
        public static double OutBack(double t, double s = 1.70158) =>
            t <= 0 ? 0 : t >= 1 ? 1 : 1 + (s + 1) * Math.Pow(t - 1, 3) + s * Math.Pow(t - 1, 2);
        public static double OutElastic(double t) =>
            t <= 0 ? 0 : t >= 1 ? 1 : Math.Pow(2, -10 * t) * Math.Sin((t * 10 - 0.75) * ((2 * Math.PI) / 3)) + 1;
        public static double OutBounce(double t)
        {
            double n = 7.5625, d = 2.75;
            if (t < 1 / d) return n * t * t;
            if (t < 2 / d) { var u = t - 1.5 / d; return n * u * u + 0.75; }
            if (t < 2.5 / d) { var u = t - 2.25 / d; return n * u * u + 0.9375; }
            var w = t - 2.625 / d;
            return n * w * w + 0.984375;
        }
    }

    // Randomness and noise

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static uint Imul(uint a, uint b) => unchecked(a * b);

    /// <summary>32-bit integer hash of any number of integers (JavaScript's <c>n | 0</c> first).</summary>
    public static uint Hash(params ReadOnlySpan<double> ns)
    {
        uint h = 0x9e3779b9;
        foreach (var n in ns)
        {
            h = Imul(h ^ unchecked((uint)I32(n)), 0x85ebca6b);
            h ^= h >> 13;
            h = Imul(h, 0xc2b2ae35);
            h ^= h >> 16;
        }
        return h;
    }
    /// <summary>A repeatable random number in [0, 1) from integers (seed, particle index, which value...).</summary>
    public static double Rand(params ReadOnlySpan<double> ns) => Hash(ns) / 4_294_967_296d;

    /// <summary>A generator for one particle: <c>Rng(seed, i)</c> gives the same numbers every frame.</summary>
    public static Rng Rng(params ReadOnlySpan<double> ns) => PixelFX.Rng.Seeded(Hash(ns));

    /// <summary>Smooth 1D value noise in [-1, 1].</summary>
    public static double Noise(double x, double seed = 0)
    {
        double i = Floor(x), f = x - i, u = f * f * (3 - 2 * f);
        return Lerp(Rand(i, seed), Rand(i + 1, seed), u) * 2 - 1;
    }
    /// <summary>Smooth 2D value noise in [-1, 1].</summary>
    public static double Noise2(double x, double y, double seed = 0)
    {
        double ix = Floor(x), iy = Floor(y), fx = x - ix, fy = y - iy;
        double ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy);
        double a = Rand(ix, iy, seed), b = Rand(ix + 1, iy, seed), c = Rand(ix, iy + 1, seed), d = Rand(ix + 1, iy + 1, seed);
        return Lerp(Lerp(a, b, ux), Lerp(c, d, ux), uy) * 2 - 1;
    }
    /// <summary>Fractal 2D noise in about [-1, 1].</summary>
    public static double Fbm(double x, double y, double seed = 0, int octaves = 3)
    {
        double s = 0, a = 0.5, n = 0;
        for (int o = 0; o < octaves; o++)
        {
            s += Noise2(x, y, seed + o * 101d) * a;
            n += a;
            x *= 2.03;
            y *= 2.03;
            a *= 0.5;
        }
        return s / n;
    }
    /// <summary>2D value noise whose lattice repeats every px cells in x and py cells in y (0: no repeat).</summary>
    public static double TileNoise(double x, double y, double px = 0, double py = 0, double seed = 0)
    {
        double ix = Floor(x), iy = Floor(y), fx = x - ix, fy = y - iy;
        double ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy);
        double x0 = px != 0 ? Wrap(ix, px) : ix, x1 = px != 0 ? Wrap(ix + 1, px) : ix + 1;
        double y0 = py != 0 ? Wrap(iy, py) : iy, y1 = py != 0 ? Wrap(iy + 1, py) : iy + 1;
        double a = Rand(x0, y0, seed), b = Rand(x1, y0, seed), c = Rand(x0, y1, seed), d = Rand(x1, y1, seed);
        return Lerp(Lerp(a, b, ux), Lerp(c, d, ux), uy) * 2 - 1;
    }
    /// <summary>Fractal TileNoise: every octave keeps the repeat, so scrolled fields still loop.</summary>
    public static double TileFbm(double x, double y, double px = 0, double py = 0, double seed = 0, int octaves = 3)
    {
        double s = 0, a = 0.5, n = 0, k = 1;
        for (int o = 0; o < octaves; o++)
        {
            s += TileNoise(x * k, y * k, px * k, py * k, seed + o * 101d) * a;
            n += a;
            a *= 0.5;
            k *= 2;
        }
        return s / n;
    }
    /// <summary>Noise that loops: the same value at phase 0 and phase 1.</summary>
    public static double LoopNoise(double phase, double radius = 1, double seed = 0)
    {
        var a = phase * Tau;
        return Noise2(Math.Cos(a) * radius + 50, Math.Sin(a) * radius + 50, seed);
    }
}

/// <summary>Seeded random generator (mulberry32), number for number the same as pixelfx's. A class, as in
/// JavaScript: an effect and its particle system share one and draw from it in turn.</summary>
public sealed class Rng
{
    public uint S;
    /// <summary><c>new Rng(seed)</c> with a JavaScript number: <c>seed &gt;&gt;&gt; 0 || 1</c>.</summary>
    public Rng(double seed = 1) : this(unchecked((uint)FX.I32(seed)), true) { }
    Rng(uint seed, bool _) { S = seed == 0 ? 1 : seed; }
    /// <summary>From a 32-bit state as it is (0 becomes 1).</summary>
    public static Rng Seeded(uint seed) => new(seed, true);

    public double Next()
    {
        unchecked
        {
            S += 0x6d2b79f5;
            var t = S;
            t = FX.Imul(t ^ (t >> 15), t | 1);
            t ^= t + FX.Imul(t ^ (t >> 7), t | 61);
            return (t ^ (t >> 14)) / 4_294_967_296d;
        }
    }
    public double Range(double a, double b) => a + (b - a) * Next();
    public double Int(double a, double b) => FX.Floor(Range(a, b + 1));
    public bool Chance(double p) => Next() < p;
    public double Sign() => Next() < 0.5 ? -1 : 1;
    public T Pick<T>(IReadOnlyList<T> list) => list[(int)FX.Floor(Next() * list.Count)];
    /// <summary>Roughly normal, mean 0, sd 1.</summary>
    public double Gauss() => (Next() + Next() + Next() + Next() - 2) * 1.732;
}

// Colours: 32-bit numbers laid out like the bytes of an RGBA image (R in the low byte), as in pixelfx.
// 0 means "nothing". FXColor is an alias of uint (top of this file).

public static partial class FX
{
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static FXColor Rgb(double r, double g, double b) => (255u << 24) | (Byte(b) << 16) | (Byte(g) << 8) | Byte(r);
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static double Red(FXColor c) => c & 255;
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static double Green(FXColor c) => (c >> 8) & 255;
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static double Blue(FXColor c) => (c >> 16) & 255;

    /// <summary>"#rgb" or "#rrggbb" to a colour.</summary>
    public static FXColor Hex(string h)
    {
        var s = h.StartsWith('#') ? h[1..] : h;
        if (s.Length == 3) s = string.Concat(s.Select(ch => $"{ch}{ch}"));
        var v = uint.TryParse(s.Length > 6 ? s[..6] : s, NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out var n) ? n : 0;
        return Rgb((v >> 16) & 255, (v >> 8) & 255, v & 255);
    }
    public static FXColor[] Ramp(IEnumerable<string> list) => list.Select(Hex).ToArray();

    /// <summary>Linear mix of two colours.</summary>
    public static FXColor Mix(FXColor a, FXColor b, double t)
    {
        t = Clamp(t);
        return Rgb(Red(a) + (Red(b) - Red(a)) * t, Green(a) + (Green(b) - Green(a)) * t, Blue(a) + (Blue(b) - Blue(a)) * t);
    }
    /// <summary>A colour's brightness times k.</summary>
    public static FXColor Scale(FXColor c, double k) => Rgb(Min(255, Red(c) * k), Min(255, Green(c) * k), Min(255, Blue(c) * k));
    /// <summary>Perceived brightness 0...1.</summary>
    public static double Luma(FXColor c) => (0.299 * Red(c) + 0.587 * Green(c) + 0.114 * Blue(c)) / 255;
    /// <summary>A ramp resampled to exactly n steps, its ends kept.</summary>
    public static FXColor[] Fit(FXColor[] r, int n)
    {
        if (r.Length == n) return r;
        var o = new FXColor[n];
        for (int i = 0; i < n; i++) o[i] = r[(int)Round((double)(i * (r.Length - 1)) / Math.Max(1, n - 1))];
        return o;
    }
    /// <summary>The ramp step for t in 0...1, no blending.</summary>
    public static FXColor At(FXColor[] r, double t) => r[(int)Clamp(Floor(t * r.Length), 0, r.Length - 1)];
    /// <summary>Blended colour along a ramp (for light, where smooth is right).</summary>
    public static FXColor Blend(FXColor[] r, double t)
    {
        var x = Clamp(t) * (r.Length - 1);
        var i = Math.Min(r.Length - 2, (int)Floor(x));
        return Mix(r[i], r[i + 1], x - i);
    }

    public const FXColor White = 0xffffffff;
    public const FXColor Black = 0xff000000;
    public const FXColor Ink = 0xff100a0b;

    /// <summary>pixelfx's named ramps, dark to bright.</summary>
    public static readonly IReadOnlyDictionary<string, string[]> Pal = new Dictionary<string, string[]>
    {
        ["fire"] = ["#1f0b10", "#4a1118", "#8c1d1c", "#cc3a1a", "#f2701f", "#ffae35", "#ffe27a", "#fff8d6"],
        ["smoke"] = ["#0e0c12", "#1d1a22", "#2e2a35", "#433e4b", "#5c5664", "#7b7484", "#a39cab"],
        ["dust"] = ["#1c1610", "#33281c", "#4f3f2c", "#6e5a40", "#927a58", "#b89f78", "#dcc8a2"],
        ["ice"] = ["#0c1430", "#162c5c", "#1f4f94", "#2f7fcc", "#58b4ec", "#9bdcff", "#d8f4ff", "#ffffff"],
        ["electric"] = ["#0a0f2e", "#172a78", "#2550d0", "#3f8cff", "#7cc8ff", "#c8f0ff", "#ffffff"],
        ["volt"] = ["#24160a", "#5e3a0c", "#a8680f", "#e8a218", "#ffd23c", "#fff08a", "#ffffff"],
        ["holy"] = ["#2a1c08", "#5a3e10", "#9a6c18", "#d8a428", "#ffd84a", "#fff09a", "#fffbe6", "#ffffff"],
        ["heal"] = ["#08201a", "#0f3f2c", "#17663e", "#24924e", "#3ec466", "#7ee88a", "#c8ffc4", "#ffffff"],
        ["arcane"] = ["#140a26", "#2b1252", "#481c88", "#6b2cc0", "#9a48ec", "#c684ff", "#ecc8ff", "#ffffff"],
        ["shadow"] = ["#050308", "#0f0a18", "#1c1230", "#2c1a4a", "#432468", "#5e3290", "#8048b8", "#a970e0"],
        ["earth"] = ["#140e0a", "#2a1e14", "#47321e", "#69492a", "#8e6638", "#b88a52", "#dcb47c"],
        ["stone"] = ["#0e0e12", "#1c1c24", "#2c2c38", "#42424f", "#5c5c6b", "#7d7d8c", "#a4a4b2", "#d0d0da"],
        ["gold"] = ["#1e1206", "#4a2c08", "#86520c", "#c48412", "#f0b424", "#ffe066", "#fff6c4", "#ffffff"],
        ["leaf"] = ["#0c1a0e", "#163418", "#225224", "#357530", "#4f9a3a", "#7cc048", "#b4e070", "#e4ffb0"],
        ["wood"] = ["#160c06", "#2e1a0c", "#4a2c14", "#6a421e", "#8e5c2c", "#b47c40", "#d8a464"],
        ["candy"] = ["#ff4a5a", "#ff9a2a", "#ffe03c", "#5ad84a", "#3cc8ff", "#7a6cff", "#f53cd1"],
        ["night"] = ["#07060d", "#0c0a18", "#131026", "#1b1734", "#241f44", "#2f2956"],
    };
    public static FXColor[] PAL(string name) => Ramp(Pal.TryGetValue(name, out var l) ? l : []);
}

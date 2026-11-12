// Shared by the effects a creature wears (frost, smitten, fired up, haunted, the clock, sleep, dizzy):
// the creature's shape, noise that loops, flame, smoke and ember drawn from their age alone, little shaded
// icons and the creature's eyes. Ported from pixelfx's `fx/status/_lib.js` (MIT); its flame, smoke and
// ember recipes and its shaded icons adapt Sprite Fusion's open-source fire and heal
// (https://www.spritefusion.com/pixel-art-vfx), MIT, Copyright (c) 2026 Hugo Duprez.
// The Mac's twin is StatusLib.swift.

namespace Ledgelings.Core.PixelFX;

/// <summary>Worked out once per creature shape (or per shape and seed) and kept.</summary>
public sealed class FXMemo<TValue>
{
    readonly Dictionary<int, TValue> store = new();
    readonly Lock gate = new();
    public TValue Get(int key, Func<TValue> make)
    {
        lock (gate)
        {
            if (store.TryGetValue(key, out var v)) return v;
            v = make();
            if (store.Count > 512) store.Clear();
            store[key] = v;
            return v;
        }
    }
}

public static class FXStatus
{
    /// <summary>The creature's shape in mask space (0, 0 its top-left).</summary>
    public sealed class Shape
    {
        public required int W, H;
        public required byte[] Data;
        /// <summary>Every pixel of the body.</summary>
        public required List<(int X, int Y)> Body;
        /// <summary>Pixels with nothing above them: where flames stand.</summary>
        public required List<(int X, int Y)> Up;
        /// <summary>Pixels open to the left (-1) or right (1).</summary>
        public required List<(int X, int Y, int D)> Side;
        /// <summary>Empty cells touching it, with the outward normal.</summary>
        public required List<(int X, int Y, double Nx, double Ny)> Outline;
        /// <summary>Each column's first row, -1 if empty.</summary>
        public required List<int> Top;
        /// <summary>[left, right] of each row.</summary>
        public required List<(int L, int R)> Rows;
        public bool On(int x, int y) => x >= 0 && y >= 0 && x < W && y < H && Data[y * W + x] > 0;
    }

    static readonly FXMemo<Shape> Shapes = new();

    public static Shape ShapeOf(FXActor a) => Shapes.Get(a.Key, () =>
    {
        var m = a.Mask;
        int w = m.W, h = m.H;
        var data = m.Data;
        bool On(int x, int y) => x >= 0 && y >= 0 && x < w && y < h && data[y * w + x] > 0;
        var body = new List<(int X, int Y)>();
        var up = new List<(int X, int Y)>();
        var side = new List<(int X, int Y, int D)>();
        var outline = new List<(int X, int Y, double Nx, double Ny)>();
        var top = new List<int>();
        var rows = new List<(int L, int R)>();
        for (int x = 0; x < w; x++)
        {
            int y = 0;
            while (y < h && !On(x, y)) y++;
            top.Add(y < h ? y : -1);
        }
        for (int y = 0; y < h; y++)
        {
            int l = -1, r = -1;
            for (int x = 0; x < w; x++)
            {
                if (!On(x, y)) continue;
                if (l < 0) l = x;
                r = x;
                body.Add((x, y));
                if (!On(x, y - 1)) up.Add((x, y));
                if (!On(x - 1, y)) side.Add((x, y, -1));
                if (!On(x + 1, y)) side.Add((x, y, 1));
            }
            rows.Add((l, r));
        }
        for (int y = -1; y <= h; y++)
        {
            for (int x = -1; x <= w; x++)
            {
                if (On(x, y)) continue;
                double nx = 0, ny = 0;
                for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++) if (On(x + dx, y + dy)) { nx -= dx; ny -= dy; }
                if (On(x - 1, y) || On(x + 1, y) || On(x, y - 1) || On(x, y + 1))
                {
                    var hl = FX.Hypot(nx, ny);
                    var len = hl == 0 ? 1 : hl;
                    outline.Add((x, y, nx / len, ny / len));
                }
            }
        }
        return new Shape { W = w, H = h, Data = data, Body = body, Up = up, Side = side, Outline = outline, Top = top, Rows = rows };
    });

    /// <summary>The creature's own colour at mask pixel (x, y).</summary>
    public static FXColor ColorAt(FXActor a, int x, int y) => a.Pixels[y * a.Mask.W + x];

    /// <summary>1D value noise in [-1, 1] whose lattice wraps every P cells.</summary>
    public static double Wnoise(double x, double P, double seed = 0)
    {
        double i = FX.Floor(x), f = x - i, u = f * f * (3 - 2 * f);
        double a = FX.Rand(FX.Wrap(i, P), seed), b = FX.Rand(FX.Wrap(i + 1, P), seed);
        return (a + (b - a) * u) * 2 - 1;
    }
    /// <summary>Noise of time t that repeats every D seconds, about f wiggles a second; off slides along it.</summary>
    public static double Tnoise(double t, double D, double f, double seed = 0, double off = 0)
    {
        var P = Math.Max(2, FX.Round(f * D));
        return Wnoise((t / D) * P + off, P, seed);
    }
    /// <summary>How far something has moved after age a, launched at v under acceleration g with linear drag d.</summary>
    public static double Travel(double v, double g, double d, double a) =>
        d > 0 ? (g / d) * a + ((v - g / d) * (1 - Math.Exp(-d * a))) / d : v * a + 0.5 * g * a * a;

    /// <summary>A tongue's nested layers: width, height, ramp step (0 brightest).</summary>
    public static readonly (double W, double H, int Ri)[] Layers = [(1, 1, 6), (0.76, 0.86, 4), (0.54, 0.68, 2), (0.3, 0.42, 0)];

    /// <summary>A flame tongue standing on (x, y), h tall, w half-wide at its root, its tip swept sx sideways.</summary>
    public static void Tongue(Painter p, double x, double y, double h, double w, double sx, FXColor[] F,
                              double t, double D, double n, (double W, double H, int Ri)[]? layers = null)
    {
        if (h < 1) return;
        foreach (var (lw, lh, ri) in layers ?? Layers)
        {
            if (ri == 0 && h < 4) continue;
            var H = h * lh;
            var col = F[ri];
            for (double r = 0; r <= H; r += 1)
            {
                var u = r / Math.Max(1, H);
                var half = w * lw * Math.Pow(1 - u, 0.85) * Math.Min(1, (r + 1.5) / 3.5) + Tnoise(t, D, 9, n, r * 0.45) * 0.5;
                if (half < 0.3) continue;
                var cx = x + sx * u * u * lh + Tnoise(t, D, 4, n + 7, r * 0.2) * u * 1.1;
                for (var px = FX.Round(cx - half); px <= FX.Round(cx + half); px += 1) p.Px(px, FX.Round(y - r), col);
            }
        }
    }

    /// <summary>A ball of flame at age u of its life, cooling down F as it rises.</summary>
    public static void Flame(Painter p, double x, double y, double size, double u, FXColor[] F, double heatSeed = 0)
    {
        int n = F.Length;
        var k = 1 - u;
        var heat = Math.Min(0.999, Math.Pow(u, 0.62) + heatSeed * 0.1);
        var idx = Math.Min(n - 2, (int)FX.Floor(heat * (n - 1)));
        var r = size * (0.55 + 0.45 * Math.Min(1, u * 7)) * (1 - u * 0.55);
        var c = F[idx];
        if (idx >= n - 2) { p.Disc(x, y, r, c, Math.Min(1, k * 3) * 0.85); return; }
        p.Circle(x, y, r, F[Math.Min(n - 1, idx + 2)]);
        p.Circle(x - r * 0.16, y - r * 0.22, r * 0.78, c);
        if (r > 1.6) p.Circle(x, y - r * 0.9, r * 0.42, c);
        if (idx <= 3 && r > 1.8) p.Circle(x - r * 0.28, y - r * 0.34, r * 0.36, F[Math.Max(0, idx - 1)]);
        if (idx < 6) p.Glow(x, y, r * 2.4 + 2, c, 0.18 * k);
    }

    /// <summary>A puff of smoke at age u: three soft discs, swelling and thinning; warm lights its underside.</summary>
    public static void Smoke(Painter p, double x, double y, double size, double u, FXColor col, double k = 1, FXColor warm = 0)
    {
        var r = size * (0.65 + Math.Min(1, u * 2.5) * 0.45 + u * 0.4);
        var a = Math.Min(1, u * 12) * Math.Min(1, (1 - u) * 2.4) * 0.58 * k;
        if (a <= 0.01) return;
        var c = col != 0 ? FX.Mix(col, FX.RampAt(FX.SmokeRamp, u), u) : FX.RampAt(FX.SmokeRamp, u * 1.05);
        p.Disc(x, y, r, c, a * 0.45);
        p.Disc(x + r * 0.05, y + r * 0.06, r * 0.74, c, a * 0.62);
        if (warm != 0 && u < 0.6) p.Disc(x + r * 0.1, y + r * 0.3, r * 0.56, FX.Mix(c, warm, 0.5), a * 0.7 * (1 - u / 0.6));
        if (u < 0.5) p.Disc(x - r * 0.22, y - r * 0.3, r * 0.5, FX.Mix(c, FX.White, 0.12), a * 0.4 * (1 - u * 2));
    }

    /// <summary>An ember at age u: hot and flickering, cooling to a dim red that blinks out. E is hot, warm, cool.</summary>
    public static void Ember(Painter p, double x, double y, double u, FXColor[] E, double ph, double k = 1)
    {
        var left = 1 - u;
        if (left < 0.22 && Math.Sin(ph * 40) < 0) return;
        var c = left > 0.5 ? (Math.Sin(ph * 22) > -0.2 ? E[0] : E[1]) : left > 0.22 ? E[1] : E[2];
        p.Px(x, y, c);
        p.Glow(x, y, 3, c, 0.32 * left * k);
    }

    /// <summary>A flat, translucent bank of haze centred on (x, y), thinning to nothing at its edge.</summary>
    public static void Haze(Painter p, double x, double y, double rx, double ry, FXColor col, double a)
    {
        if (a <= 0.01 || rx < 0.5 || ry < 0.5) return;
        for (var py = FX.Floor(y - ry); py <= FX.Ceil(y + ry); py += 1)
        {
            for (var px = FX.Floor(x - rx); px <= FX.Ceil(x + rx); px += 1)
            {
                double dx = (px + 0.5 - x) / rx, dy = (py + 0.5 - y) / ry, d = dx * dx + dy * dy;
                if (d < 1) p.Blend(px, py, col, a * (1 - d));
            }
        }
    }

    /// <summary>A shape from a bitmap (rows, "." empty), centred on (0, 0), scaled by whole k: the character at (dx, dy), or null.</summary>
    public static Func<int, int, char?> Bitmap(IReadOnlyList<string> rows, int k = 1, bool flip = false)
    {
        int h = rows.Count, w = rows[0].Length, ox = (w * k) / 2, oy = (h * k) / 2;
        return (dx, dy) =>
        {
            var bx = (int)FX.Floor((double)(dx + ox) / k);
            var by = (int)FX.Floor((double)(dy + oy) / k);
            if (bx < 0 || by < 0 || bx >= w || by >= h) return null;
            if (flip) bx = w - 1 - bx;
            var c = rows[by][bx];
            return c == '.' ? null : c;
        };
    }

    /// <summary>A little shaded pixel icon at (x, y): every cell inside within ext of the centre, filled from
    /// R = outline, shadow, body, light, and repainted where inside returns a character listed in paint.</summary>
    public static void Icon(Painter p, double x, double y, int ext, Func<int, int, char?> inside, FXColor[] R,
                            double a = 1, IReadOnlyDictionary<char, FXColor>? paint = null)
    {
        double X = FX.Round(x), Y = FX.Round(y);
        bool At(int dx, int dy) => inside(dx, dy) != null;
        for (int dy = -ext - 1; dy <= ext + 1; dy++)
        {
            for (int dx = -ext - 1; dx <= ext + 1; dx++)
            {
                FXColor c;
                if (inside(dx, dy) is { } ch)
                {
                    if (paint != null && paint.TryGetValue(ch, out var pc)) c = pc;
                    else
                    {
                        bool top = !At(dx, dy - 1), left = !At(dx - 1, dy), bottom = !At(dx, dy + 1), right = !At(dx + 1, dy);
                        c = top || left ? R[3] : bottom || right ? R[1] : R[2];
                    }
                }
                else if (R[0] != 0 && (At(dx - 1, dy) || At(dx + 1, dy) || At(dx, dy - 1) || At(dx, dy + 1))) c = R[0];
                else continue;
                p.Dot(X + dx, Y + dy, c, a);
            }
        }
    }

    /// <summary>inside(dx, dy) for a shape given in its own unit space by f(u, v), turned by ang and scaled by s.</summary>
    public static Func<int, int, char?> Shaped(Func<double, double, bool> f, double s, double ang = 0)
    {
        double c = Math.Cos(ang), n = Math.Sin(ang);
        return (dx, dy) =>
        {
            double x = dx + 0.5, y = dy + 0.5;
            return f((x * c + y * n) / s, (-x * n + y * c) / s) ? '#' : null;
        };
    }

    /// <summary>A five-pointed star in unit space (points at radius 1, inner corners at r0).</summary>
    public static Func<double, double, bool> StarShape(double r0 = 0.45) => (u, v) =>
    {
        double a = Math.Atan2(v, u) + Math.PI / 2, d = FX.Hypot(u, v), seg = (2 * Math.PI) / 5;
        var k = 1 - Math.Abs(FX.Mod(FX.Mod(a, seg) + seg, seg) - seg / 2) / (seg / 2);
        return d <= 1 - (1 - r0) * Math.Pow(k, 0.8);
    };

    /// <summary>A heart in unit space (two lobes and a point, about 2 wide and 2 tall, centred).</summary>
    public static bool HeartShape(double u, double v) =>
        Math.Pow(u + 0.5, 2) + Math.Pow(v + 0.32, 2) <= Math.Pow(0.55, 2) || Math.Pow(u - 0.5, 2) + Math.Pow(v + 0.32, 2) <= Math.Pow(0.55, 2)
            || (v >= -0.32 && v <= 1 && Math.Abs(u) <= 1.04 * Math.Pow(1 - (v + 0.32) / 1.32, 0.75));

    /// <summary>One eye: its box, its pixels, and the skin round it to paint it shut with.</summary>
    public sealed record Eye(int X0, int X1, int Y0, int Y1, List<(int X, int Y)> Px, FXColor Skin);

    static readonly FXMemo<List<Eye>> EyeMemo = new();

    static readonly (int X, int Y)[] Near4 = [(1, 0), (-1, 0), (0, 1), (0, -1)];
    static readonly (int X, int Y)[] Near6 = [(1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0)];

    /// <summary>The creature's eyes, if any can be found: small blobs of very dark pixels inside the upper body,
    /// surrounded by it, left to right. Empty when nothing looks like eyes.</summary>
    public static List<Eye> Eyes(FXActor a) => EyeMemo.Get(a.Key, () =>
    {
        if (a.Eyes is { } given)
            return given.Select(e => new Eye(e.X, e.X, e.Y, e.Y + 1, [(e.X, e.Y), (e.X, e.Y + 1)], ColorAt(a, e.X, e.Y))).ToList();
        var S = ShapeOf(a);
        var W = S.W;
        FXColor Col(int x, int y) => S.On(x, y) ? ColorAt(a, x, y) : 0;
        bool Dark(int x, int y) =>
            S.On(x, y) && y < S.H * 0.4 && FX.Luma(Col(x, y)) < 0.15
                && S.On(x - 1, y) && S.On(x + 1, y) && S.On(x, y - 1) && S.On(x, y + 1);
        var seen = new HashSet<int>();
        var list = new List<Eye>();
        foreach (var (x0, y0) in S.Body)
        {
            if (seen.Contains(y0 * W + x0) || !Dark(x0, y0)) continue;
            var px = new List<(int X, int Y)>();
            var q = new List<(int X, int Y)> { (x0, y0) };
            seen.Add(y0 * W + x0);
            while (q.Count > 0)
            {
                var (x, y) = q[^1];
                q.RemoveAt(q.Count - 1);
                px.Add((x, y));
                foreach (var (dx, dy) in Near4)
                {
                    int nx = x + dx, ny = y + dy, k = ny * W + nx;
                    if (seen.Contains(k) || !(Dark(nx, ny) || (S.On(nx, ny) && FX.Luma(Col(nx, ny)) > 0.95))) continue;
                    seen.Add(k);
                    q.Add((nx, ny));
                }
            }
            if (px.Count < 2 || px.Count > 14) continue;
            // counted in the order JavaScript's Map keeps: first seen first
            var counts = new List<(FXColor C, int N)>();
            foreach (var (x, y) in px)
            {
                foreach (var (dx, dy) in Near6)
                {
                    var c = Col(x + dx, y + dy);
                    var l = FX.Luma(c);
                    if (c != 0 && l > 0.5 && l < 0.95 && !px.Contains((x + dx, y + dy)))
                    {
                        var i = counts.FindIndex(e => e.C == c);
                        if (i >= 0) counts[i] = (c, counts[i].N + 1); else counts.Add((c, 1));
                    }
                }
            }
            var sorted = FX.JsSort(counts, (p, q) => q.N - p.N);
            if (sorted.Count == 0) continue;
            var skin = sorted[0].C;
            int ex0 = px.Min(e => e.X), ex1 = px.Max(e => e.X), ey0 = px.Min(e => e.Y), ey1 = px.Max(e => e.Y);
            if (ex1 - ex0 <= 4 && ey1 - ey0 <= 5) list.Add(new Eye(ex0, ex1, ey0, ey1, px, skin));
        }
        list = FX.JsSort(list, (p, q) => p.X0 - q.X0);
        if (list.Count > 2) list = [];
        return list;
    });
}

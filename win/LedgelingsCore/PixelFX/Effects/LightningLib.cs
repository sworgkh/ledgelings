// Shared by the lightning effects: bolts that fork and thin as they split, inked as a deep halo, a pale body
// and a white core, thin crackles, and spark trajectories for pure loops. pixelfx's `fx/lightning/_lib.js`
// (MIT), which adapts the bolt and its inking from Sprite Fusion's open-source lightning
// (https://www.spritefusion.com/pixel-art-vfx/lightning), MIT, Copyright (c) 2026 Hugo Duprez.
// The Mac's twin is LightningLib.swift.

namespace Ledgelings.Core.PixelFX;

public static class FXLightning
{
    /// <summary>Default palette, dark to bright: deep violet shadow, electric blue, icy white.</summary>
    public static readonly string[] Volt = ["#120a33", "#2a1b78", "#4630c0", "#5a62f0", "#58a6ff", "#9ed8ff", "#e4f6ff", "#ffffff"];
    /// <summary>Plasma sparks, head to tail.</summary>
    public static readonly string[] Plasma = ["#ffffff", "#c8f8ff", "#7ff3ff", "#1ab8e6"];

    /// <summary>One stroke of a bolt: its points and its weight (1 the trunk, thinner for forks).</summary>
    public sealed class Path(List<(double X, double Y)> pts, double w)
    {
        public readonly List<(double X, double Y)> Pts = pts;
        public readonly double W = w;
    }

    /// <summary>A bolt from (x0, y0) to (x1, y1) by midpoint displacement down to ~3 px segments, with forks that
    /// split off along the way, each thinner and forking again up to two levels. The trunk first.</summary>
    public static List<Path> Zigzag(Rng R, double x0, double y0, double x1, double y1, double jag = 0.32,
                                    double forks = 0.35, double w = 1, int depth = 0)
    {
        var @out = new List<Path>();
        var L = FX.Hypot(x1 - x0, y1 - y0);
        var pts = new List<(double X, double Y)> { (x0, y0), (x1, y1) };
        var off = L * jag;
        while (pts.Count < 2 + L / 3)
        {
            var nxt = new List<(double X, double Y)> { pts[0] };
            for (int i = 0; i < pts.Count - 1; i++)
            {
                var (ax, ay) = pts[i];
                var (bx, by) = pts[i + 1];
                var h = FX.Hypot(bx - ax, by - ay);
                double l = h == 0 ? 1 : h, o = R.Range(-off, off);
                nxt.Add(((ax + bx) / 2 + (-(by - ay) / l) * o, (ay + by) / 2 + ((bx - ax) / l) * o));
                nxt.Add((bx, by));
            }
            pts = nxt;
            off *= 0.52;
        }
        @out.Add(new Path(pts, w));
        if (depth < 2)
            for (int i = 2; i < pts.Count - 3; i++)
                if (R.Chance(forks / (1 + depth) / Math.Max(4, pts.Count / 6.0)))
                {
                    var (ax, ay) = pts[i];
                    var (bx, by) = pts[Math.Min(pts.Count - 1, i + 3)];
                    var a = Math.Atan2(by - ay, bx - ax) + R.Sign() * R.Range(0.35, 0.9);
                    var l = (L - ((double)i / pts.Count) * L) * R.Range(0.25, 0.55);
                    @out.AddRange(Zigzag(R, ax, ay, ax + Math.Cos(a) * l, ay + Math.Sin(a) * l, jag * 1.1, forks, w * 0.55, depth + 1));
                }
        return @out;
    }

    // Inking. Pixels are gathered in a grid at a level (higher wins), then drawn once each.
    sealed class Ink
    {
        public const int N = 1024, Half = 512;
        readonly byte[] grid = new byte[N * N];
        readonly List<int> hit = new();
        public void Mark(double x, double y, byte lvl)
        {
            int X = (int)FX.Floor(x) + Half, Y = (int)FX.Floor(y) + Half;
            if (X < 0 || Y < 0 || X >= N || Y >= N) return;
            int i = Y * N + X;
            var v = grid[i];
            if (v == 0) hit.Add(i);
            if (lvl > v) grid[i] = lvl;
        }
        public void Stamp(double x, double y, double r, byte lvl)
        {
            if (r <= 0.5) { Mark(FX.Round(x), FX.Round(y), lvl); return; }
            var r2 = r * r;
            for (var py = FX.Floor(y - r); py <= FX.Ceil(y + r); py++)
            {
                var dy = py + 0.5 - y;
                for (var px = FX.Floor(x - r); px <= FX.Ceil(x + r); px++)
                {
                    var dx = px + 0.5 - x;
                    if (dx * dx + dy * dy <= r2) Mark(px, py, lvl);
                }
            }
        }
        /// <summary>Draw what was gathered: level n in cols[n - 1] at alpha alphas[n - 1] (dithered below 1).</summary>
        public void Flush(Painter p, FXColor[] cols, double[] alphas)
        {
            foreach (var i in hit)
            {
                int v = grid[i];
                grid[i] = 0;
                double x = i % N - Half, y = i / N - Half, a = alphas[v - 1];
                if (a >= 1) p.Px(x, y, cols[v - 1]);
                else if (a > 0) p.Dot(x, y, cols[v - 1], a);
            }
            hit.Clear();
        }
    }
    static readonly Ink ink = new();

    static void Walk(List<(double X, double Y)> pts, Action<double, double> fn)
    {
        for (int i = 0; i < pts.Count - 1; i++)
        {
            var (ax, ay) = pts[i];
            var (bx, by) = pts[i + 1];
            var l = Math.Max(1, FX.Hypot(bx - ax, by - ay));
            for (var d = 0.0; d <= l; d += 0.5) fn(ax + ((bx - ax) * d) / l, ay + ((by - ay) * d) / l);
        }
    }

    /// <summary>A bolt at full power: a deep halo, a pale body, a white core on the trunk, light every few points. k is
    /// the stroke's brightness (forks drop out below 0.5, the trunk thins below 0.6), s scales the thickness;
    /// hero: a white frame, the body goes white.</summary>
    public static void Stroke(Painter p, List<Path> b, double k, FXColor[] C, double s = 1, bool hero = false,
                              double light = 0.5, double a = 1, double? upTo = null, double? core = null, double? minY = null)
    {
        if (k <= 0.02) return;
        var lk = light;
        foreach (var q in b)
        {
            var trunk = q.W >= 1;
            if (!trunk && k < 0.5) continue;
            double rh = (trunk ? (k > 0.6 ? 2.1 : 1.6) : 1.1) * s, rb = (trunk ? (k > 0.6 ? 1.3 : 0.8) : 0.5) * s;
            var pts = upTo != null && trunk ? q.Pts.Take(Math.Max(2, (int)FX.Ceil(q.Pts.Count * upTo.Value))).ToList() : q.Pts;
            Walk(pts, (x, y) =>
            {
                ink.Stamp(x, y, rh, 1);
                ink.Stamp(x, y, rb, (byte)(trunk ? 3 : 2));
                if (trunk && k > 0.3) { if (core is double c && c != 0) ink.Stamp(x, y, c, 4); else ink.Mark(x, y, 4); }
            });
            for (int i = 0; i < pts.Count - 1; i += 3)
                if (minY == null || pts[i].Y > minY.Value) p.Glow(pts[i].X, pts[i].Y, (trunk ? 14 : 7) * s, C[4], lk * k * q.W);
        }
        ink.Flush(p, hero ? [C[3], C[6], C[7], C[7]] : [C[2], C[4], C[5], C[7]], [a, a, a, a]);
    }

    static readonly (double X, double Y)[] Cross = [(1, 0), (-1, 0), (0, 1), (0, -1)];

    /// <summary>A thin crackle: a 1 px core (white on the trunk while bright), a 2 px pale body, a dithered halo while
    /// k is high, light along it.</summary>
    public static void Crackle(Painter p, List<Path> b, double k, FXColor[] C, double glowK = 0.5, double a = 1)
    {
        if (k <= 0.02) return;
        foreach (var q in b)
        {
            var thick = q.W >= 1;
            Walk(q.Pts, (x, y) =>
            {
                if (k > 0.45 && thick) foreach (var (dx, dy) in Cross) ink.Mark(x + dx * 1.5, y + dy * 1.5, 1);
                if (k > 0.25 && (thick || q.W > 0.4)) { ink.Mark(x + 1, y, 2); ink.Mark(x, y + 1, 2); }
                ink.Mark(x, y, (byte)(thick && k > 0.3 ? 4 : 3));
            });
            for (int i = 0; i < q.Pts.Count - 1; i += 3)
                p.Glow(q.Pts[i].X, q.Pts[i].Y, (thick ? 9 : 5) * (0.5 + k * 0.5), C[4], glowK * k * q.W);
        }
        ink.Flush(p, [C[3], C[5], C[5], C[7]], [Math.Min(1, (k - 0.45) * 1.6) * a, a, a, a]);
    }

    /// <summary>Where a spark launched at (x, y, vx, vy) is after <c>age</c> seconds, stepped like the simulation's spark.</summary>
    public static (double X, double Y, double Vx, double Vy) Flight(double x, double y, double vx, double vy, double age, double g = 0.45,
                                                                    double drag = 2.2, double floor = double.PositiveInfinity, double bounce = 0.45)
    {
        const double dt = 1.0 / 120;
        for (var s = 0.0; s < age; s += dt)
        {
            var h = Math.Min(dt, age - s);
            vy += FX.Gravity * g * h;
            vx -= vx * drag * h;
            vy -= vy * drag * h;
            var ny = y + vy * h;
            x += vx * h;
            if (vy > 0 && y <= floor && ny >= floor) { vy = -vy * bounce; vx *= 0.7; y = floor - 0.25; }
            else y = ny;
        }
        return (x, y, vx, vy);
    }

    /// <summary>A spark drawn the way the simulation draws one, for pure loops.</summary>
    public static void Spark(Painter p, double x, double y, double vx, double vy, double k, FXColor[] S)
    {
        var h = FX.Hypot(vx, vy);
        double sp = h == 0 ? 1 : h, ux = vx / sp, uy = vy / sp;
        var head = k > 0.6 ? S[0] : k > 0.3 ? S[1] : S[2];
        var len = Math.Min(9, 1 + sp * 0.022);
        p.Line(x - ux * len, y - uy * len, x - ux * len * 0.4, y - uy * len * 0.4, k > 0.5 ? head : S[S.Length - 1]);
        p.Line(x - ux * len * 0.45, y - uy * len * 0.45, x, y, head);
        p.Glow(x, y, 3, head, 0.45 * k);
    }
}

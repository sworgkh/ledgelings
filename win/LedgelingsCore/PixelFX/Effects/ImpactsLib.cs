// Shared by the impacts: floor cracks that glow and cool, soft lumpy dust rings, faceted tumbling rocks, and
// the stone colours they share. Ported from pixelfx's `fx/impacts/_lib.js` (MIT); its stone colours adapt
// Sprite Fusion's open-source explosion (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT,
// Copyright (c) 2026 Hugo Duprez. The Mac's twin is ImpactsLib.swift.

namespace Ledgelings.Core.PixelFX;

public static class FXImpacts
{
    public static readonly FXColor SOOT = FX.Hex("#0d0a12");
    public static readonly FXColor OUTLINE = FX.Hex("#1a1422");
    static readonly double LIGHT = Math.Atan2(-1.0, -1.0); // light comes from the top left

    /// <summary>Stone colours from one body colour.</summary>
    public readonly record struct Stone(FXColor Light, FXColor Body, FXColor Shade, FXColor Dust, FXColor Lip);
    public static Stone StoneOf(FXColor c) =>
        new(FX.Mix(FX.Scale(c, 1.35), FX.White, 0.08), c, FX.Scale(c, 0.64),
            FX.Mix(FX.Scale(c, 1.2), FX.Rgb(150, 140, 150), 0.3), FX.Mix(FX.Scale(c, 1.55), FX.White, 0.12));

    /// <summary>A crack: its points (where, and how far along it), its length, when it starts, its forks.</summary>
    public sealed record Crack(List<(double X, double Y, double D)> Pts, double Len, double T0, List<List<(double X, double Y, double D)>> Kids);

    /// <summary>A jagged walk from (x, y) heading a for L px.</summary>
    public static List<(double X, double Y, double D)> Walk(Rng R, double x, double y, double a, double L, double jit = 0.55, double steer = 0.45,
                                                            (double A, double B)? step = null, double maxY = double.PositiveInfinity, double d0 = 0)
    {
        var st = step ?? (2, 4);
        var pts = new List<(double X, double Y, double D)> { (x, y, d0) };
        double d = 0, cur = a;
        while (d < L - 0.01)
        {
            var s = Math.Min(L - d, R.Range(st.A, st.B));
            cur += R.Range(-jit, jit) + (a - cur) * steer;
            x += Math.Cos(cur) * s;
            y = FX.Clamp(y + Math.Sin(cur) * s, 0.5, maxY);
            d += s;
            pts.Add((x, y, d0 + d));
        }
        return pts;
    }

    /// <summary>Cracks in the floor face below (0, 0): n jagged lines, alternately left and right.</summary>
    public static List<Crack> MakeCracks(Rng R, int n, (double A, double B)? len = null, double dive = 0.85, double maxY = 22,
                                         double forks = 0.5, (double A, double B)? x0 = null)
    {
        var ln = len ?? (14, 40);
        var xs = x0 ?? (1, 5);
        var @out = new List<Crack>();
        for (int i = 0; i < n; i++)
        {
            double side = i % 2 != 0 ? 1 : -1, dip = 0.06 + Math.Pow(R.Next(), 1.7) * dive, L = R.Range(ln.A, ln.B) * (1 - (0.5 * dip) / (dive + 0.06));
            var a = side > 0 ? dip : Math.PI - dip;
            double sx = side * R.Range(xs.A, xs.B), sy = R.Range(0.5, 1.5);
            var pts = Walk(R, sx, sy, a, L, maxY: maxY);
            var t0 = R.Range(0, 0.035);
            var kids = new List<List<(double X, double Y, double D)>>();
            for (int j = 2; j < pts.Count - 1; j++)
            {
                if (!R.Chance(forks * 0.4)) continue;
                var f = pts[j];
                double fa = a + R.Sign() * R.Range(0.45, 1), fl = R.Range(3, 9) * (1 - (0.5 * j) / pts.Count);
                kids.Add(Walk(R, f.X, f.Y, fa, fl, jit: 0.7, step: (1.5, 3), maxY: maxY, d0: f.D));
            }
            @out.Add(new Crack(pts, L, t0, kids));
        }
        return @out;
    }

    /// <summary>Draw cracks grown to g(c) px of their length, lit from the hot ramp by heat(d) before they cool to dark.</summary>
    public static void DrawCracks(Painter p, List<Crack> cracks, Func<Crack, double> g, Func<double, double> heat,
                                  FXColor[] hot, FXColor dark, FXColor lip, double k = 1)
    {
        if (k <= 0) return;
        FXColor Col(double d)
        {
            var h = heat(d);
            return h > 0.75 ? hot[0] : h > 0.5 ? hot[1] : h > 0.3 ? hot[2] : h > 0.12 ? hot[3] : dark;
        }
        foreach (var c in cracks)
        {
            var G = g(c);
            if (G <= 0) continue;
            var paths = new List<List<(double X, double Y, double D)>> { c.Pts };
            paths.AddRange(c.Kids);
            foreach (var path in paths)
                for (int i = 1; i < path.Count; i++)
                {
                    var (x0, y0, d0) = path[i - 1];
                    var (x1, y1, d1) = path[i];
                    if (d0 >= G) break;
                    double f = d1 > G ? (G - d0) / (d1 - d0) : 1, ex = x0 + (x1 - x0) * f, ey = y0 + (y1 - y0) * f;
                    p.Line(x0, y0 + 1, ex, ey + 1, _ => lip, u =>
                        FX.Rand(FX.Round(x0 + (ex - x0) * u), FX.Round(y0 + (ey - y0) * u), 5) < 0.3 ? k * 0.8 : 0);
                    p.Line(x0, y0, ex, ey, u => Col(d0 + (d1 - d0) * f * u), k);
                    var h = heat(d0);
                    if (h > 0.12) p.Glow((x0 + ex) / 2, (y0 + ey) / 2, 4 + h * 4, hot[2], 0.22 * h * k);
                }
        }
    }

    /// <summary>A soft, lumpy ring of dust round (cx, cy), translucent and lit on its upper side; half -1 the far half
    /// only, 1 the near half only.</summary>
    public static void DustRing(Painter p, double cx, double cy, double r, double w, double k, FXColor c,
                                double sy = 1, double ph = 0, double brk = 0, double lit = 0.35, double maxY = double.PositiveInfinity, double half = 0)
    {
        if (k <= 0.01 || r <= 0) return;
        var W = w * 1.6;
        var lite = FX.Mix(c, FX.White, lit);
        var y1 = Math.Min(maxY - 1, FX.Ceil(cy + (r + W) * sy) + 1);
        for (var y = FX.Floor(cy - (r + W) * sy) - 1; y <= y1; y += 1)
        {
            var x1 = FX.Ceil(cx + r + W) + 1;
            for (var x = FX.Floor(cx - r - W) - 1; x <= x1; x += 1)
            {
                double dx = x + 0.5 - cx, dy = (y + 0.5 - cy) / sy, d = FX.Hypot(dx, dy), g = Math.Atan2(dy, dx);
                if ((half < 0 && dy >= 0) || (half > 0 && dy < 0)) continue;
                var lumpy = 0.6 + 0.3 * Math.Sin(5 * g + ph) + 0.18 * Math.Sin(11 * g + ph * 2.1) + 0.12 * Math.Sin(17 * g + ph * 0.7);
                double wt = w * lumpy, off = Math.Abs(d - r - w * 0.25 * Math.Sin(7 * g + ph));
                if (off >= wt) continue;
                var tear = brk > 0 ? FX.Clamp((0.55 + 0.45 * Math.Sin(6 * g + ph * 1.7) - brk) / 0.25) : 1;
                var a = k * (1 - Math.Pow(off / wt, 2)) * tear;
                if (a > 0.01) p.Blend(x, y, dy < 0 && d > r - wt * 0.3 ? lite : c, a);
            }
        }
    }

    /// <summary>A rock's outline: n vertex radii round its centre.</summary>
    public static double[] RockShape(Rng R, int n = 6)
    {
        var pts = new double[n];
        for (int i = 0; i < n; i++) pts[i] = R.Range(0.7, 1.12);
        return pts;
    }

    /// <summary>A faceted rock tumbling at angle a: every facet shaded by how it faces the light, a dark outline,
    /// dithering out over its last half second.</summary>
    public static void Rock(Painter p, double bx, double by, double ba, double bs, double life, double[] pts, Stone st)
    {
        double r = 0.75 + bs * 0.8, fade = Math.Min(1, life / 0.5), ca = Math.Cos(ba), sa = Math.Sin(ba);
        int n = pts.Length;
        p.Shade(bx - r - 2, by - r - 2, bx + r + 2, by + r + 2, (x, y, o) =>
        {
            double dx = x - bx, dy = y - by, u = dx * ca + dy * sa, v = -dx * sa + dy * ca, d = FX.Hypot(u, v);
            var ang = Math.Atan2(v, u);
            if (ang < 0) ang += FX.Tau;
            var f = (ang / FX.Tau) * n;
            var i = (int)FX.Floor(f) % n;
            double w = f - FX.Floor(f), edge = r * (pts[i] * (1 - w) + pts[(i + 1) % n] * w);
            if (d > edge + 0.85) return 0;
            o.A = fade;
            if (d > edge) return OUTLINE;
            var lit = Math.Cos(((i + 0.5) / n) * FX.Tau + ba - LIGHT);
            if (d < edge * 0.42) return lit > 0.55 ? st.Light : st.Body;
            return lit > 0.35 ? st.Light : lit < -0.4 ? st.Shade : st.Body;
        });
    }
}

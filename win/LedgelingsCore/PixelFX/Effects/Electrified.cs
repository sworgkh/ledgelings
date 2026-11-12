// Current runs through a character: arcs crawl over and leap across the body, sparks spit off, the body flares
// to an electric silhouette on each jolt, and the feet ground out. pixelfx's `lightning/electrified` (MIT),
// after Sprite Fusion's open-source lightning crackle (https://www.spritefusion.com/pixel-art-vfx/lightning),
// MIT, Copyright (c) 2026 Hugo Duprez. The Mac's twin is Electrified.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXElectrified : IFXEffect
{
    public static readonly FXMeta Meta = new("lightning/electrified", size: (108, 92), origin: (54, 76), duration: 2, loop: true, palette: FXLightning.Volt, seed: 5);
    const double Fps = 30.0, P = 2.0;
    const int N = 60;
    static readonly (int F0, double K)[] Jolts = [(3, 1), (22, 0.7), (41, 0.9)];
    static readonly FXMemo<List<(double X, double Y)>> Edges = new();
    readonly FXOptions o;
    readonly FXColor[] C, S;
    public FXElectrified(FXOptions o) { this.o = o; C = FX.Fit(o.Palette, 8); S = FX.Ramp(FXLightning.Plasma); }

    /// <summary>The silhouette's edge pixels, in local space (pixel centres).</summary>
    static List<(double X, double Y)> EdgeOf(FXActor A) => Edges.Get(A.Key, () =>
    {
        var m = A.Mask;
        bool On(int x, int y) => x >= 0 && y >= 0 && x < m.W && y < m.H && m.Data[y * m.W + x] != 0;
        var e = new List<(double X, double Y)>();
        for (int y = 0; y < m.H; y++)
            for (int x = 0; x < m.W; x++)
                if (On(x, y) && (!On(x - 1, y) || !On(x + 1, y) || !On(x, y - 1) || !On(x, y + 1))) e.Add((A.X + x + 0.5, A.Y + y + 0.5));
        return e;
    });
    static (int A, double K)? Jolt(int f)
    {
        foreach (var (f0, k) in Jolts) if (f >= f0 && f < f0 + 3) return (f - f0, k);
        return null;
    }
    static int Frame(double t) => (int)FX.Floor(t * Fps + 1e-6) % N;

    public void DrawBack(Painter p, double t)
    {
        var C = this.C;
        var A = o.Actor;
        var f = Frame(t);
        var j = Jolt(f);
        var r = FX.Rng(o.Seed, 4, f);
        // a cold aura: a broken outline that flickers round the body, light pooling at the feet
        var oc = j != null ? C[4] : r.Next() < 0.5 ? C[2] : C[1];
        p.Outline(A.Mask, A.X, A.Y, (_, _) => oc);
        p.Glow(0, -18, 30, C[3], j != null ? 0.55 * j.Value.K : 0.16 + 0.1 * r.Next());
        p.Glow(0, -2, 22, C[4], 0.18);
    }

    public void Draw(Painter p, double t)
    {
        var C = this.C;
        var S = this.S;
        var A = o.Actor;
        var E = EdgeOf(A);
        var f = Frame(t);
        var j = Jolt(f);
        var seed = o.Seed;
        // the jolt: the body flares to an electric silhouette, then fades back through its own shading
        if (j is var (ja, jk))
        {
            var lift = new[] { 1.1, 0.6, -0.2 }[ja] * jk;
            FXColor[] ramp = [C[1], C[2], C[3], C[4], C[5], C[6], C[7]];
            for (int y = 0; y < A.H; y++)
                for (int x = 0; x < A.W; x++)
                {
                    var c = A.Pixels[y * A.W + x];
                    if (c != 0) p.Px(A.X + x, A.Y + y, ramp[(int)FX.Clamp(FX.Round(0.4 + FX.Luma(c) * 6 + lift), 0, 6)]);
                }
            p.Glow(0, -19, 26, C[5], 0.5 * jk * (1 - ja / 3.0));
        }
        // arcs: two or three at a time, re-struck every other frame, leaping between nearby points of the edge
        var r = FX.Rng(seed, 7, f >> 1);
        var n = 2 + (j != null ? 2 : (int)r.Int(0, 1));
        for (int i = 0; i < n; i++)
        {
            var a = r.Pick(E);
            double ang = r.Range(0, FX.Tau), d = r.Range(6, 14);
            (double X, double Y) b = (a.X + Math.Cos(ang) * d, a.Y + Math.Sin(ang) * d);
            for (int q = 0; q < 10; q++)
            {
                var c = r.Pick(E);
                if (FX.Hypot(c.X - b.X, c.Y - b.Y) < 5 && FX.Hypot(c.X - a.X, c.Y - a.Y) > 4) b = c;
            }
            var k = ((f & 1) != 0 ? 0.75 : 0.95) * r.Range(0.6, 1);
            FXLightning.Crackle(p, FXLightning.Zigzag(FX.Rng(seed, 8, f, i), a.X, a.Y, b.X, b.Y, 0.42, 0.35), k, C, 0.4);
            // the edge catches the light where an arc touches it
            foreach (var (x, y) in E) if (FX.Hypot(x - a.X, y - a.Y) < 3.5 || FX.Hypot(x - b.X, y - b.Y) < 3) p.Px(x - 0.5, y - 0.5, C[5]);
        }
        // the feet ground out to the floor now and then
        if (r.Next() < (j != null ? 0.9 : 0.35))
        {
            var s = r.Sign();
            var x0 = s * r.Range(3, 8);
            var g = FX.Rng(seed, 9, f);
            FXLightning.Crackle(p, FXLightning.Zigzag(g, x0, -1.5, x0 + s * r.Range(5, 12), -0.5, 0.45, 0.3), 0.7, C, 0.35);
            p.Glow(x0, -1, 10, C[5], 0.35);
        }
        // sparks: a spray off the edge with every jolt, and a few spat out between them
        foreach (var (f0, k) in Jolts)
        {
            var age = FX.Mod(FX.Mod(t - f0 / Fps, P) + P, P);
            for (int i = 0; i < 9; i++)
            {
                var q = FX.Rng(seed, 21, f0, i);
                var life = q.Range(0.18, 0.4);
                if (age >= life) continue;
                var (x0, y0) = E[(int)FX.Floor(q.Next() * E.Count)];
                double ang = Math.Atan2(y0 + 19, x0) + q.Range(-0.7, 0.7), sp = q.Range(60, 150) * k;
                var (x, y, vx, vy) = FXLightning.Flight(x0, y0, Math.Cos(ang) * sp, Math.Sin(ang) * sp - 30, age, floor: 0);
                FXLightning.Spark(p, x, y, vx, vy, 1 - age / life, S);
            }
        }
        FX.Cycle(t, P, 8, seed + 3, g => g.Range(0.15, 0.3), (age, life, q, _) =>
        {
            var (x0, y0) = E[(int)FX.Floor(q.Next() * E.Count)];
            double ang = Math.Atan2(y0 + 19, x0) + q.Range(-0.6, 0.6), sp = q.Range(50, 110);
            var (x, y, vx, vy) = FXLightning.Flight(x0, y0, Math.Cos(ang) * sp, Math.Sin(ang) * sp - 20, age, floor: 0);
            FXLightning.Spark(p, x, y, vx, vy, 1 - age / life, S);
        });
    }
}

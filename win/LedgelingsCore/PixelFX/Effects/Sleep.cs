// Fast asleep: eyes shut, soft outlined Zs float up off the head one after another, swaying and growing as
// they rise, dream motes drift, a slow breathing glow. pixelfx's `status/sleep` (MIT); its shaded, outlined
// letters adapt Sprite Fusion's open-source heal (https://www.spritefusion.com/pixel-art-vfx/heal),
// MIT, Copyright (c) 2026 Hugo Duprez. The Mac's twin is Sleep.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXSleep : IFXEffect
{
    public static readonly FXMeta Meta = new("status/sleep", size: (60, 82), origin: (26, 74), duration: 2.4, loop: true,
                                             palette: ["#1a1636", "#3c3a7a", "#6f78c8", "#a9b8f0", "#dfe6ff", "#ffffff"], seed: 3);
    const double D = 2.4;
    const int NZ = 3;
    const FXColor LidColor = 0xff1f1726;
    // the letter at four sizes: it grows a step at a time as it rises
    static readonly Func<int, int, char?>[] Zs = new string[][]
    {
        ["#####", "...#.", "..#..", ".#...", "#####"],
        ["#######", ".....#.", "....#..", "...#...", "..#....", ".#.....", "#######"],
        [".#######.", "#########", "......##.", ".....##..", "....##...", "...##....", "..##.....", "#########", ".#######."],
        [".#########.", "###########", ".......###.", "......###..", ".....###...", "....###....", "...###.....", "..###......", ".###.......", "###########", ".#########."],
    }.Select(rows => FXStatus.Bitmap(rows)).ToArray();
    readonly FXOptions o;
    readonly FXColor[] C;
    public FXSleep(FXOptions o) { this.o = o; C = FX.Fit(o.Palette, 6); }

    /// <summary>A Z at age u (0..1): where it is, how big, how solid.</summary>
    (double X, double Y, int Size, double K) ZAt(int i, double u)
    {
        var a = o.Actor;
        double side = i % 2 != 0 ? 1 : 0.6, x0 = a.X + a.W * 0.78, y0 = a.Y + 7;
        double x = x0 + 13 * side * u + 2.5 * Math.Sin(FX.Tau * 1.1 * u + i * 2.1), y = y0 - 32 * (1 - Math.Pow(1 - u, 1.35));
        var size = u < 0.18 ? 0 : u < 0.42 ? 1 : u < 0.68 ? 2 : 3;
        var k = Math.Min(1, u / 0.06);
        return (x, y, size, k);
    }

    /// <summary>Shut the eyes: paint them over with skin and draw a soft lid line.</summary>
    void Shut(Painter p)
    {
        var a = o.Actor;
        double ax = a.X, ay = a.Y;
        foreach (var e in FXStatus.Eyes(a))
        {
            foreach (var (x, y) in e.Px) p.Px(ax + x, ay + y, e.Skin);
            var ly = ay + e.Y1 - 1;
            for (int x = e.X0; x <= e.X1; x++) p.Px(ax + x, ly, LidColor);
            p.Px(ax + e.X0 - 1, ly - 1, LidColor);
            p.Px(ax + e.X1 + 1, ly - 1, LidColor);
        }
    }

    public void Draw(Painter p, double t)
    {
        var C = this.C;
        var a = o.Actor;
        var breath = 0.5 + 0.5 * Math.Sin((t / D) * FX.Tau * 2);
        double ax = a.X, ay = a.Y, aw = a.W;
        Shut(p);
        // a slow breathing glow round the head, and soft dream light drifting about it
        p.Glow(0, ay + 10, 24, C[3], 0.1 + 0.1 * breath);
        FX.Cycle(t, D, 5, o.Seed + 6, D, (age, life, r, _) =>
        {
            double u = age / life, x = ax + aw * r.Range(0.3, 1.1) + Math.Sin(u * FX.Tau + r.Next() * FX.Tau) * 3, y = ay + r.Range(-6, 8) - u * 10;
            double rad = r.Range(3, 5) * (0.8 + 0.4 * u), k = Math.Sin(Math.PI * u);
            p.Glow(x, y, rad * 2.4, C[3], 0.1 * k);
        });
        // dream motes drifting up
        FX.Cycle(t, D, 14, o.Seed + 4, r => r.Range(1.2, 2), (age, life, r, _) =>
        {
            double u = age / life, x = ax + aw * r.Range(0.4, 1.1) + Math.Sin(age * 2 + r.Next() * FX.Tau) * 2, y = ay + r.Range(0, 10) - age * r.Range(10, 18);
            var tw = Math.Sin(Math.PI * u) * (0.6 + 0.4 * Math.Sin(age * 9 + r.Next() * FX.Tau));
            if (tw < 0.15) return;
            FX.Sparkle(p, x, y, tw > 0.7 && r.Next() < 0.4 ? 1 : 0, C[4], C[3], 0.3 * tw);
            p.Dot(x, y, tw > 0.6 ? C[5] : C[4], tw * 1.3);
        });
        // the Zs, oldest (biggest) first so the young ones sit on top
        var zs = new List<(int I, double U)>();
        for (int i = 0; i < NZ; i++) zs.Add((i, FX.Mod(FX.Mod(t - (i * D) / NZ, D) + D, D) / D));
        zs = FX.JsSort(zs, (p1, p2) => p2.U - p1.U);
        foreach (var (i, u) in zs)
        {
            var z = ZAt(i, u);
            if (u > 0.9)
            {
                // it pops into motes
                var k = (u - 0.9) / 0.1;
                for (int j = 0; j < 7; j++)
                {
                    double an = (j / 7.0) * FX.Tau + i, d = 3 + 6 * Math.Sqrt(k);
                    p.Dot(z.X + Math.Cos(an) * d, z.Y + Math.Sin(an) * d * 0.8, j % 2 != 0 ? C[4] : C[5], 1.2 - k);
                }
                p.Glow(z.X, z.Y, 10, C[3], 0.25 * (1 - k));
                continue;
            }
            // a dotted trail where it has been
            for (int j = 1; j <= 6; j++)
            {
                var q = ZAt(i, Math.Max(0, u - j * 0.025));
                if (j % 2 == 0 || u - j * 0.025 < 0.05) continue;
                p.Dot(q.X - 1, q.Y + 4 + q.Size, C[3], (1 - j / 7.0) * 0.9);
            }
            // it dims down the ramp as it gets old
            var old = u > 0.78;
            FXColor[] R = old ? [C[0], C[1], C[2], C[3]] : [C[1], C[2], C[3], C[4]];
            double fs = z.Size;
            FXStatus.Icon(p, z.X, z.Y, 7, Zs[z.Size], R, z.K);
            if (!old) p.Px(z.X - 2 - fs, z.Y - 2 - fs * 0.8, C[5]);
            p.Glow(z.X, z.Y, 7 + fs * 3, C[3], (old ? 0.12 : 0.26) * z.K);
        }
    }
}

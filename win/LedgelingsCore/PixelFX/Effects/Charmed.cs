// Smitten: a big heart beats over the head, throwing a ring and a flush of light with every beat, little
// hearts float up, the eyes go pink and the cheeks blush. pixelfx's `status/charmed` (MIT); its shaded,
// outlined hearts adapt Sprite Fusion's open-source heal (https://www.spritefusion.com/pixel-art-vfx/heal),
// MIT, Copyright (c) 2026 Hugo Duprez. The Mac's twin is Charmed.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXCharmed : IFXEffect
{
    public static readonly FXMeta Meta = new("status/charmed", size: (60, 76), origin: (30, 68), duration: 2.4, loop: true,
                                             palette: ["#3a0a1e", "#7a1238", "#c4245a", "#f04e86", "#ff8ab0", "#ffc8da", "#ffffff"], seed: 8);
    const double D = 2.4, Beat = D / 2;
    static readonly Func<int, int, char?> Heart5 = FXStatus.Bitmap([".#.#.", "#####", "#####", ".###.", "..#.."]);
    static readonly Func<int, int, char?> Heart7 = FXStatus.Bitmap([".##.##.", "#######", "#######", ".#####.", "..###..", "...#..."]);
    readonly FXOptions o;
    readonly FXColor[] C;
    public FXCharmed(FXOptions o) { this.o = o; C = FX.Fit(o.Palette, 7); }

    /// <summary>A heartbeat: a strong lub and a softer dub.</summary>
    static double Thump(double ph) => Math.Exp(-Math.Pow((ph - 0.04) / 0.07, 2)) + 0.6 * Math.Exp(-Math.Pow((ph - 0.26) / 0.07, 2));

    /// <summary>Little hearts drifting up (a third of them behind the creature).</summary>
    void Hearts(Painter p, double t, bool back)
    {
        var C = this.C;
        double ay = o.Actor.Y;
        FX.Cycle(t, D, 12, o.Seed + 4, r => r.Range(1.3, 1.9), (age, life, r, i) =>
        {
            if ((i % 3 == 0) != back) return;
            double u = age / life, side = r.Next() < 0.5 ? -1 : 1, ph = r.Range(0, FX.Tau);
            var big = r.Next() < 0.3;
            double x = side * r.Range(4, 15) + Math.Sin(age * 4 + ph) * 2.2, y = ay + r.Range(8, 30) - age * r.Range(14, 22);
            var k = Math.Min(1, u * 6);
            if (u > 0.88)
            {
                // it pops into a twinkle
                var q = (u - 0.88) / 0.12;
                FX.Sparkle(p, x, y, FX.Round(2 * (1 - q)), C[5], C[4], 0.4 * (1 - q));
                return;
            }
            FXColor[] R = back ? [C[0], C[1], C[2], C[3]] : [C[0], C[2], C[3], C[4]];
            FXStatus.Icon(p, x, y, 4, big ? Heart7 : Heart5, R, k);
            if (!back) p.Px(x - (big ? 2 : 1), y - 1, C[6]);
            p.Glow(x, y, 6, C[3], (back ? 0.12 : 0.22) * k);
        });
    }

    public void DrawBack(Painter p, double t)
    {
        double ph = FX.Mod(FX.Mod(t, Beat) + Beat, Beat), th = Thump(ph);
        p.Glow(0, o.Actor.Y - 8, 26 + 8 * th, C[3], 0.16 + 0.22 * th);
        Hearts(p, t, true);
    }

    public void Draw(Painter p, double t)
    {
        var C = this.C;
        var a = o.Actor;
        double ph = FX.Mod(FX.Mod(t, Beat) + Beat, Beat), th = Thump(ph);
        double ax = a.X, ay = a.Y;
        // lovestruck: pink eyes with a bright catchlight, flushed cheeks
        foreach (var e in FXStatus.Eyes(a))
        {
            foreach (var (x, y) in e.Px) p.Px(ax + x, ay + y, y == e.Y0 ? C[3] : C[2]);
            p.Px(ax + e.X0, ay + e.Y0 + 1, C[6]);
            var blush = FX.Mix(e.Skin, C[3], 0.55);
            var @out = e.X0 < a.W / 2.0 ? -1 : 1;
            double bx = @out < 0 ? e.X0 - 1 : e.X1;
            p.Px(ax + bx, ay + e.Y1 + 1, blush);
            p.Px(ax + bx + 1, ay + e.Y1 + 1, blush);
        }
        Hearts(p, t, false);
        // the big heart, beating
        double hx = 0, hy = ay - 10, s = 5.6 * (1 + 0.24 * th);
        // a heart-shaped ring thrown off with each beat
        foreach (var (t0, kk) in (ReadOnlySpan<(double, double)>)[(0.04, 1.0), (0.26, 0.6)])
        {
            var u = (ph - t0) / 0.5;
            if (u < 0 || u > 1) continue;
            var S1 = 5.6 * (1.25 + 1.3 * u);
            var outer = FXStatus.Shaped(FXStatus.HeartShape, S1);
            var inner = FXStatus.Shaped(FXStatus.HeartShape, S1 - 1.3);
            var E = (int)FX.Ceil(S1 * 1.2) + 1;
            for (int dy = -E; dy <= E; dy++)
                for (int dx = -E; dx <= E; dx++)
                    if (outer(dx, dy) != null && inner(dx, dy) == null) p.Dot(hx + dx, hy + dy, u < 0.3 ? C[5] : C[4], (1 - u) * kk * 1.3);
        }
        FXStatus.Icon(p, hx, hy, 9, FXStatus.Shaped(FXStatus.HeartShape, s), [C[0], C[2], C[3], C[4]]);
        // a glint on the left lobe
        double gx = hx - FX.Round(s * 0.55), gy = hy - FX.Round(s * 0.45);
        p.Px(gx, gy, C[6]);
        p.Px(gx + 1, gy, C[5]);
        p.Px(gx, gy + 1, C[5]);
        p.Glow(hx, hy, 12 + 6 * th, C[4], 0.3 + 0.4 * th);
        if (th > 0.5) FX.Sparkle(p, hx + s * 0.9, hy - s * 0.8, FX.Round(3 * th), C[5], C[4], 0.4 * th);
        // twinkles round the heart
        FX.Cycle(t, D, 8, o.Seed + 2, r => r.Range(0.3, 0.5), (age, life, r, _) =>
        {
            double an = r.Range(0, FX.Tau), d = r.Range(8, 15), u = age / life;
            FX.Sparkle(p, hx + Math.Cos(an) * d, hy + Math.Sin(an) * d * 0.8, FX.Round(1.6 * Math.Sin(Math.PI * u)), C[5], C[4], 0.3 * Math.Sin(Math.PI * u));
        });
    }
}

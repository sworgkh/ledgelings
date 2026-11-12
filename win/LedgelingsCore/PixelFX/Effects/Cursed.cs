// Haunted: violet smoke rises off the body in winding trails, a dark stain creeps up from the feet with a
// glowing edge, the eyes burn, a skull glitches in overhead. pixelfx's `status/cursed` (MIT); its soft lit
// smoke puffs and shaded, outlined skull adapt Sprite Fusion's open-source poison
// (https://www.spritefusion.com/pixel-art-vfx/poison), MIT, Copyright (c) 2026 Hugo Duprez. The Mac's twin is Cursed.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXCursed : IFXEffect
{
    public static readonly FXMeta Meta = new("status/cursed", size: (64, 84), origin: (32, 76), duration: 2.4, loop: true,
                                             palette: ["#0c0612", "#1f0f2e", "#3a1a55", "#5e2a85", "#8a3fc0", "#b86ef0", "#e0b0ff", "#ffffff"], seed: 9);
    const double D = 2.4;
    static readonly Func<int, int, char?> Skull = FXStatus.Bitmap([
        "...#####...",
        ".#########.",
        "###########",
        "##eee#eee##",
        "##eEe#eEe##",
        "##eee#eee##",
        "#####.#####",
        ".####.####.",
        "..#######..",
        "..#.#.#.#..",
        "...#####...",
    ]);
    // the skull's life in the loop: hidden, glitching in, hanging there, glitching out
    const double TIn = 0.5, Hold = 0.75, TOut = 1.85, Gone = 2.1;
    readonly FXOptions o;
    readonly FXColor[] C;
    public FXCursed(FXOptions o) { this.o = o; C = FX.Fit(o.Palette, 8); }

    /// <summary>How high the stain has crept at column x (0 at the feet, 1 at the head): a slow tide with crawling tendrils.</summary>
    static double Tide(double t) => 0.3 + 0.12 * Math.Sin((t / D) * FX.Tau);
    static double Reach(double x, double t, double seed) => Tide(t) + 0.13 * FX.TileFbm(x * 0.35, (t / D) * 4, 0, 4, seed, 2);

    /// <summary>Smoke trails: each rises from a spot on the body as a ribbon of soft puffs that wind as they climb,
    /// swell, cool and thin.</summary>
    void Trails(Painter p, FXStatus.Shape S, double t, bool front)
    {
        var C = this.C;
        var a = o.Actor;
        (double Q, double Side)[] spots = [(0.12, -1), (0.1, 1), (0.5, -1), (0.48, 1)];
        for (int j = 0; j < spots.Length; j++)
        {
            var (q, side) = spots[j];
            if ((j % 2 == 0) != front) continue;
            var my = (int)FX.Round(S.H * q);
            var (l, r) = my >= 0 && my < S.Rows.Count ? S.Rows[my] : (0, 0);
            double x0 = a.X + (side < 0 ? l : r + 1), y0 = a.Y + my, life = 1.6;
            const int n = 18;
            for (int i = n - 1; i >= 0; i--)
            {
                double age = FX.Mod(FX.Mod(t - ((double)i / n) * D - j * 0.37, D) + D, D), tb = t - age, u = age / life;
                if (u >= 1) continue;
                var sway = Math.Sin((tb / D) * FX.Tau * 2 + j * 1.7) * 4 * Math.Min(1, u * 1.6);
                double x = x0 + side * u * 7 + sway + (FX.Rand(i, j, 71) - 0.5) * 2.5 * u, y = y0 - age * 19 - 5 * u * u;
                var rad = (1.3 + 3.6 * (1 - Math.Pow(1 - u, 3))) * (0.7 + 0.6 * FX.Rand(i, j, 72));
                var k = FX.Smooth(0, 0.12, u) * (1 - FX.Smooth(0.45, 1, u)) * (front ? 0.5 : 0.62);
                var c = FX.Mix(FX.Rand(i, j, 70) < 0.5 ? C[4] : FX.Mix(C[4], C[3], 0.4), C[1], u * 0.85);
                p.Disc(x, y, rad * 1.08, c, k * 0.4);
                p.Disc(x + rad * 0.05, y + rad * 0.08, rad * 0.76, c, k * 0.55);
                p.Disc(x - rad * 0.22, y - rad * 0.3, rad * 0.48, FX.Mix(c, C[6], 0.25), k * 0.38 * (1 - u * 0.6));
                if (i % 3 == 0) p.Glow(x, y, rad * 1.6, C[4], 0.08 * k);
            }
        }
    }

    public void DrawBack(Painter p, double t)
    {
        var C = this.C;
        var a = o.Actor;
        var S = FXStatus.ShapeOf(a);
        // the stain pooling round the feet, its rim glowing
        var (fl, fr) = S.Rows[S.H - 1];
        double cx = a.X + (fl + fr + 1) / 2.0, rx = (fr - fl) / 2.0 + 7 + 2 * Math.Sin((t / D) * FX.Tau);
        for (var x = FX.Floor(cx - rx - 1); x <= cx + rx + 1; x += 1)
        {
            double q = Math.Abs(x + 0.5 - cx) / rx, n = FX.Rand(x, 31);
            if (q > 1 + n * 0.12) continue;
            p.Px(x, 0, q > 0.8 ? C[4] : n < 0.2 ? C[3] : C[2]);
            if (q < 0.85) p.Px(x, 1, C[1]);
            if (q < 0.55 && n < 0.7) p.Px(x, 2, C[1]);
        }
        p.Shade(cx - rx - 6, -4, cx + rx + 6, 5, (x, y, @out) =>
        {
            var d = FX.Hypot((x - cx) / (rx + 6), y / 4);
            if (d < 1) { @out.L = C[4]; @out.K = 0.2 * (1 - d) * (1 - d); }
            return 0;
        });
        Trails(p, S, t, false);
    }

    public void Draw(Painter p, double t)
    {
        var C = this.C;
        var a = o.Actor;
        var S = FXStatus.ShapeOf(a);
        double H = S.H, ax = a.X, ay = a.Y, seed = o.Seed;
        // the stain on the body: everything below the creeping line drowned in violet, the line itself burning
        foreach (var (mx, my) in S.Body)
        {
            var c = FXStatus.ColorAt(a, mx, my);
            double up = 1 - (my + 0.5) / H, lv = Reach(mx, t, seed);
            if (up > lv + 0.035) continue;
            double x = ax + mx, y = ay + my;
            if (up > lv - 0.02) p.Px(x, y, C[6]);
            else if (up > lv - 0.06) p.Px(x, y, C[4]);
            else p.Px(x, y, FX.Mix(C[1], C[3], FX.Clamp(FX.Luma(c) * 1.6)));
        }
        for (int mx = 0; mx < S.W; mx++)
        {
            double lv = Reach(mx, t, seed), my = FX.Floor((1 - lv) * H);
            if (S.On(mx, (int)my)) p.Glow(ax + mx, ay + my, 4, C[5], 0.14);
        }
        // the eyes burn
        foreach (var e in FXStatus.Eyes(a))
        {
            foreach (var (x, y) in e.Px) p.Px(ax + x, ay + y, y == e.Y0 ? C[7] : C[5]);
            p.Glow(ax + (e.X0 + e.X1 + 1) / 2.0, ay + (e.Y0 + e.Y1 + 1) / 2.0, 5, C[5], 0.4);
        }
        Trails(p, S, t, true);
        // the skull glitches in, hangs there bobbing, and glitches out
        if (t >= TIn && t < Gone)
        {
            var glitch = t < Hold ? 1 - (t - TIn) / (Hold - TIn) : t > TOut ? (t - TOut) / (Gone - TOut) : 0;
            var f = FX.Floor(t * 30);
            var on = glitch < 0.15 || FX.Rand(f, 3) > glitch * 0.6;
            double x = 0, y = ay - 12 + Math.Sin((t / D) * FX.Tau * 2) * 1.2;
            if (on)
            {
                char? Tear(int dx, int dy)
                {
                    var row = dy + 6;
                    var shift = glitch > 0 && FX.Rand(f, row >> 1, 7) < glitch * 0.8 ? (int)FX.Round((FX.Rand(f, row, 9) - 0.5) * 6 * glitch) : 0;
                    return Skull(dx - shift, dy);
                }
                if (glitch > 0)
                {
                    FXStatus.Icon(p, x - 2, y, 7, Tear, [0, C[2], C[2], C[3]], 0.7 * glitch);
                    FXStatus.Icon(p, x + 2, y, 7, Tear, [0, C[6], C[6], C[6]], 0.5 * glitch);
                }
                FXStatus.Icon(p, x, y, 8, Tear, [C[0], C[4], C[6], C[7]], 1, new Dictionary<char, FXColor> { ['e'] = C[0], ['E'] = C[7] });
                p.Glow(x - 3, y - 1, 5, C[5], 0.6);
                p.Glow(x + 3, y - 1, 5, C[5], 0.6);
                p.Glow(x, y, 16, C[4], 0.24 + 0.3 * glitch);
            }
            // scanlines fizzing as it comes and goes
            if (glitch > 0.1)
            {
                for (int k = 0; k < 3; k++)
                {
                    double ly = y - 5 + FX.Floor(FX.Rand(f, k, 11) * 11), lx = FX.Round((FX.Rand(f, k, 12) - 0.5) * 10), len = 3 + FX.Floor(FX.Rand(f, k, 13) * 8);
                    p.Line(lx - len / 2, ly, lx + len / 2, ly, k % 2 != 0 ? C[6] : C[4], glitch);
                }
            }
        }
        p.Glow(0, ay + H * (1 - Tide(t)), 24, C[4], 0.2);
        p.Glow(0, ay + H * 0.45, 30, C[3], 0.12);
    }
}

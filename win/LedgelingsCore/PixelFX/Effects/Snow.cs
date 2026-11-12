// Snow at three depths in a gusty breeze: far specks, drifting flakes, big near crystals that spin and glow;
// they settle on a sparkling drift and melt away. pixelfx's `weather/snow` (MIT), its recipe adapted from
// Sprite Fusion's open-source snow (https://www.spritefusion.com/pixel-art-vfx/snow, MIT, Hugo Duprez).
// The Mac's twin is Snow.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXSnow : IFXEffect, IFXBackdropped
{
    public static readonly FXMeta Meta = new("weather/snow", size: (320, 180), origin: (160, 170), duration: 12, loop: true,
                                             palette: ["#0c1020", "#161d36", "#24304f", "#3a4a72", "#5f74a3", "#93abd6", "#cfe0fa", "#ffffff"], seed: 6);
    const double D = 12.0;
    /// <summary>far to near: how many, falls a loop, share of a fall spent in the air (the rest lying on the drift), sway, wind</summary>
    readonly record struct Layer(int N, double M0, double M1, double Air, double Sway0, double Sway1, double Wind, double Gust);
    static readonly Layer[] Layers =
    [
        new(230, 1, 2, 1, 1, 3, 3, 0.4),
        new(140, 2, 3, 0.8, 3, 7, 6, 0.7),
        new(24, 2, 3, 0.74, 8, 15, 9, 1),
    ];
    static readonly (double X, double Y)[] Axis = [(1, 0), (-1, 0), (0, 1), (0, -1)], DiagDirs = [(1, 1), (-1, -1), (1, -1), (-1, 1)];
    static readonly (double X, double Y)[] Glint = [(1, 0), (-1, 0), (0, -1)];

    readonly FXOptions o;
    readonly FXColor[] C;
    /// <summary>false: no cold haze over the whole canvas (drawn over the desktop); the snow, drift and glints stay.</summary>
    public bool Backdrop { get; set; } = true;
    public FXSnow(FXOptions o) { this.o = o; C = FX.Fit(o.Palette, 8); }

    /// <summary>The drift's top edge.</summary>
    static double Bank(double x) => -3 + 1.6 * Math.Sin(x * 0.045 + 1.3) + 1.1 * Math.Sin(x * 0.12 + 0.4) + 0.6 * Math.Sin(x * 0.31 + 2);
    /// <summary>The gusts: a sway of the whole snowfall, periodic so the loop closes.</summary>
    static double Gust(double t) => 10 * Math.Sin((FX.Tau * t) / D + 0.6) + 4 * Math.Sin((FX.Tau * 2 * t) / D + 2.1);

    public void DrawBack(Painter p, double t)
    {
        var q = new FXWeather.Clip(p, Meta);
        var S = o.Seed;
        var C = this.C;
        // a cold haze, thicker low down, so the sky's stars don't read as snow
        if (Backdrop)
        {
            var haze = FX.Mix(C[1], C[2], 0.4);
            FXWeather.Pass(p, Meta, -170, 9, (_, y, @out) =>
            {
                @out.C = haze;
                @out.A = 0.26 + 0.22 * FX.Smooth(-170, 0, y);
                @out.B = true;
            });
        }
        DrawLayer(q, t, S, 0);
        Drift(q, t, S);
        DrawLayer(q, t, S, 1);
    }

    public void Draw(Painter p, double t) => DrawLayer(new FXWeather.Clip(p, Meta), t, o.Seed, 2);

    void DrawLayer(FXWeather.Clip q, double t, double S, int L)
    {
        var C = this.C;
        var Ly = Layers[L];
        var sd = S * 13 + L;
        const FXColor white = FX.White;
        FXWeather.Trips(t, D, Ly.N, sd, Ly.M0, Ly.M1, (u, k, m, i) =>
        {
            double j = FX.Wrap(k, m), dur = D / m;
            double R(double n) => FX.Rand(sd, i, j, n);
            double tf = dur * Ly.Air, age = Math.Min(u * dur, tf), sw = Ly.Sway0 + R(3) * (Ly.Sway1 - Ly.Sway0), f = 0.25 + R(4) * 0.35, ph = R(5) * FX.Tau;
            double XAt(double a) =>
                -175 + R(2) * 350 + Ly.Wind * a + (Gust(t - u * dur + a) - Gust(t - u * dur)) * Ly.Gust + sw * Math.Sin(FX.Tau * f * a + ph);
            double x = XAt(age), xl = XAt(tf), y0 = -176.0, y1 = L != 0 ? Bank(xl) - 0.5 : -110 + R(1) * 106;
            double y = y0 + (y1 - y0) * (age / tf), rest = u * dur - tf;
            if (L == 0)
            {
                // far: a speck, thinning out before it's gone
                var a = Math.Min(1, (1 - u) * 6);
                q.Dot(x, y, R(6) < 0.5 ? C[4] : C[5], a);
                return;
            }
            var fade = rest > 0 ? 1 - rest / (dur - tf) : 1;
            if (L == 1)
            {
                // a drifting flake: a point with a smaller one beside it, a plus when it's big
                var big = R(6) < 0.3;
                if (rest > 0) { q.Dot(xl, y1, C[7], fade * 0.9); return; }
                q.Px(x, y, big ? white : C[7]);
                if (big) { foreach (var (dx, dy) in Axis) q.Px(x + dx, y + dy, C[5]); }
                else { q.Px(x + 1, y, C[6]); q.Px(x, y + 1, C[6]); q.Px(x + 1, y + 1, C[5]); }
                return;
            }
            // a near crystal: six arms with side branches, spinning, a white heart, a cold glow; it lies down on the drift
            double r = R(6) < 0.4 ? 3 : R(6) < 0.8 ? 4 : 5, spin = 1.5 + R(7) * 2.5;
            if (rest > 0)
            {
                q.Dot(xl - 1, y1, C[6], fade);
                q.Dot(xl, y1, white, fade);
                q.Dot(xl + 1, y1, C[6], fade);
                q.Glow(xl, y1, 5, C[5], 0.25 * fade);
                return;
            }
            Crystal(q, x, y, r, FX.Mod(FX.Floor(age * spin + R(8) * 2), 2) != 0);
        });
    }

    /// <summary>A near crystal, kept crisp: long arms on one set of four directions, short ones on the other, nubs near
    /// the tips; turning means trading which set is long.</summary>
    void Crystal(FXWeather.Clip q, double x, double y, double r, bool turn)
    {
        var C = this.C;
        const FXColor white = FX.White;
        double X = FX.Round(x), Y = FX.Round(y), R = turn ? r - 1 : r;
        var @long = turn ? DiagDirs : Axis;
        var @short = turn ? Axis : DiagDirs;
        // long arms with a white-blue tip; nubs only where they can't touch the next arm, so the gaps stay open
        foreach (var (dx, dy) in @long)
        {
            for (var d = 1.0; d <= R; d += 1) q.Px(X + dx * d, Y + dy * d, d == R ? white : C[6]);
            double[] nubs = turn ? (R >= 3 ? [R - 1] : []) : R >= 5 ? [R - 1, R - 2] : R >= 4 ? [R - 1] : [];
            foreach (var n in nubs)
            {
                double ox = turn ? dx : dy, oy = turn ? -dy : -dx;
                q.Px(X + dx * n + (turn ? 0 : ox), Y + dy * n + oy, C[4]);
                q.Px(X + dx * n + (turn ? -dx : -ox) + (turn ? dx : 0), Y + dy * n + (turn ? dy * 0 : -oy), C[4]);
            }
        }
        var shortLen = turn ? 1 : Math.Max(1, FX.Floor(R / 2));
        foreach (var (dx, dy) in @short)
            for (var d = 1.0; d <= shortLen; d += 1) q.Px(X + dx * d, Y + dy * d, d == 1 ? C[6] : C[5]);
        q.Px(X, Y, white);
        // a faint halo, wide enough not to fill the gaps between the arms
        q.Glow(X + 0.5, Y + 0.5, r * 2.5 + 5, C[5], 0.13);
        q.Light(X, Y, C[6], 0.4);
    }

    /// <summary>The drift on the floor: a lumpy bank with a white crest, blue shade below, and glints that twinkle.</summary>
    void Drift(FXWeather.Clip q, double t, double S)
    {
        var C = this.C;
        const FXColor white = FX.White;
        FXWeather.Pass(q.P, Meta, -7, 9, (x, y, @out) =>
        {
            double top = Bank(x), d = y - top;
            if (d < 0) return;
            @out.C = d < 1 ? white : d < 2 ? C[7] : d < 3.5 ? C[6] : d < 6 ? C[5] : C[4];
            if (d < 1) { @out.L = C[6]; @out.K = 0.12; }
        });
        for (int i = 0; i < 18; i++)
        {
            double x = -156 + FX.Rand(S, i, 81) * 312, c = 1 + FX.Floor(FX.Rand(S, i, 82) * 3);
            var tw = Math.Sin((FX.Tau * c * t) / D + FX.Rand(S, i, 83) * FX.Tau);
            if (tw < 0.55) continue;
            double y = FX.Ceil(Bank(x)) + FX.Floor(FX.Rand(S, i, 84) * 3), k = (tw - 0.55) / 0.45;
            q.Px(x, y, white);
            if (k > 0.5) foreach (var (dx, dy) in Glint) q.Px(x + dx, y + dy, C[6]);
            q.Glow(x + 0.5, y + 0.5, 6, C[6], 0.35 * k);
        }
    }
}

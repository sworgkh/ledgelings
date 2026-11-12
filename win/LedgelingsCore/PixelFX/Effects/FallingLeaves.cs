// Autumn leaves swing down through the air, tilting and flipping to show their pale backs, ride a gust, land flat
// in the litter and fade. pixelfx's `weather/falling-leaves` (MIT), the falling leaf adapted from Sprite Fusion's
// open-source falling leaves (https://www.spritefusion.com/pixel-art-vfx/falling-leaves, MIT, Hugo Duprez).
// The Mac's twin is FallingLeaves.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXFallingLeaves : IFXEffect, IFXBackdropped
{
    public static readonly FXMeta Meta = new("weather/falling-leaves", size: (320, 180), origin: (160, 170), duration: 10, loop: true,
                                             palette: ["#4a1d0c", "#8a3a14", "#c8621e", "#f0982e", "#ffcf72", "#fff0c4"], seed: 8);
    const double D = 10.0, FLOOR = 1.0;
    static readonly FXColor[] Reds = FX.Fit(FX.Ramp(["#40101a", "#7c1c22", "#b8302a", "#e85a3c", "#ff9a72", "#ffd8c4"]), 6);
    static readonly FXColor[] Golds = FX.Fit(FX.Ramp(["#3e300c", "#7a5c14", "#b8901e", "#e8c23a", "#fff09a", "#fffbe0"]), 6);
    static readonly FXColor[] Backs = [FX.Hex("#9c8a78"), FX.Hex("#c8b49c"), FX.Hex("#e0d0b8"), FX.Hex("#e8dcc8")];

    readonly FXOptions o;
    readonly FXColor[][] R3;
    FXWeather.Recorder? litter;
    /// <summary>false: no dusk haze over the whole canvas (drawn over the desktop); the litter and the leaves stay.</summary>
    public bool Backdrop { get; set; } = true;
    public FXFallingLeaves(FXOptions o) { this.o = o; R3 = [FX.Fit(o.Palette, 6), Reds, Golds]; }

    static double Gust(double t) => 16 * Math.Sin((FX.Tau * t) / D - 1.2) + 5 * Math.Sin((FX.Tau * 3 * t) / D);
    /// <summary>∫|cos| from the start of a swing: speeds up through the bottom of each arc, so the drop does too.</summary>
    static double Hc(double th)
    {
        var k = FX.Floor((th + Math.PI / 2) / Math.PI);
        return 2 * k + 1 + Math.Sin(th - k * Math.PI);
    }
    /// <summary>A leaf's outline in its own frame: u along it (-1 stem..1 tip), v across; 0 inside, &gt; 1 outside.</summary>
    static double ShapeAt(int i, double u, double v)
    {
        switch (i)
        {
            case 0: return Math.Abs(u) >= 1 ? 9 : (v * v) / (0.36 * (1 - u * u) * (1.15 - 0.3 * u)); // a beech: a long oval, pointed tip
            case 1:
                double r = FX.Hypot(u, v * 1.1), a = Math.Atan2(v, u);
                return r / (0.62 + 0.38 * Math.Pow(Math.Abs(Math.Cos(2.5 * a)), 1.5)); // a maple: five lobes
            default: return Math.Abs(u) >= 1 ? 9 : (v * v) / (0.16 * (1 - u * u)); // a willow: long and thin
        }
    }

    public void DrawBack(Painter p, double t)
    {
        var q = new FXWeather.Clip(p, Meta);
        var S = o.Seed;
        var C = R3[0];
        // a faint dusk haze, warmer low down, that keeps the sky's stars out of the leaves' way
        if (Backdrop)
        {
            FXColor top = FX.Hex("#0e0a12"), low = FX.Mix(FX.Hex("#140c14"), C[0], 0.3);
            FXWeather.Rows(p, Meta, -170, 9, (y, R) =>
            {
                var k = (y + 170) / 180;
                R.Fill(FX.Mix(top, low, k * k), 0.32 + 0.1 * k, blend: true);
            });
        }
        (litter ??= MakeLitter()).Replay(q);
        Leaves(q, t, S, false);
    }

    public void Draw(Painter p, double t) => Leaves(new FXWeather.Clip(p, Meta), t, o.Seed, true);

    void Leaves(FXWeather.Clip q, double t, double S, bool front)
    {
        var R3 = this.R3;
        FXWeather.Trips(t, D, 62, S * 19, 2, 3, (u, k, m, i) =>
        {
            var j = FX.Wrap(k, m);
            double R(double n) => FX.Rand(S * 19, i, j, n);
            var near = R(1) < 0.35;
            if (near != front) return;
            double dur = D / m, air = 0.72, tf = dur * air, a = Math.Min(u * dur, tf), rest = u * dur - tf;
            double w = 1.7 + R(2) * 1.2, ph0 = R(3) * FX.Tau, amp = (near ? 14 : 8) + R(4) * 10, x0 = -180 + R(5) * 340, y0 = -186.0;
            // the drop speed that lands it on the floor just as its time in the air runs out
            double Path(double aa) => 0.45 * aa + (0.9 * (Hc(w * aa + ph0) - Hc(ph0))) / w;
            var vy = (FLOOR - y0) / Path(tf);
            var born = t - u * dur;
            double XAt(double aa) => x0 + 7 * aa + Math.Sin(w * aa + ph0) * amp + (Gust(born + aa) - Gust(born)) * (near ? 1 : 0.7);
            var size = (near ? 5.8 : 4.2) + R(6) * 1.6;
            int shape = (int)FX.Floor(R(7) * 3);
            var col = R3[(int)FX.Floor(R(8) * 3)];
            if (rest > 0)
            {
                // lying flat in the litter, fading
                var fade = 1 - rest / (dur - tf);
                Leaf(q, XAt(tf), FLOOR - 1, size, (R(9) - 0.5) * 0.5, 0.42, shape, col, fade);
                return;
            }
            double x = XAt(a), y = y0 + vy * Path(a), tilt = Math.Cos(w * a + ph0) * 0.75 + (near ? 0 : 0.3);
            var flip = Math.Cos(R(10) * FX.Tau + a * (R(11) < 0.3 ? 5 : 1.2));
            Leaf(q, x, y, size, tilt, flip, shape, col, 1);
            // a leaf turned full face to the light catches it for a moment
            if (flip > 0.86)
            {
                double kk = (flip - 0.86) / 0.14, hx = x - Math.Cos(tilt) * size * 0.3, hy = y - Math.Sin(tilt) * size * 0.3 - 1;
                q.Px(hx, hy, col[5]);
                q.Glow(hx, hy, 5 + size * 0.5, col[4], 0.22 * kk);
            }
        });
    }

    /// <summary>A leaf: squashed across by <c>flip</c> (the sign says which face shows), tilted, outlined, a midrib down
    /// the middle, the face lit on one side; the back face is paler and duller.</summary>
    static void Leaf(IFXWeatherShading q, double x, double y, double size, double ang, double flip, int shape, FXColor[] col, double a)
    {
        // like a card turning: never thinner than a third, and the back shows only past edge-on
        bool back = flip < -0.25;
        double fs = 0.35 + 0.65 * Math.Abs(flip), c = Math.Cos(ang), s = Math.Sin(ang);
        double L = size, Wd = size * 0.9, ext = L + 1.5;
        FXColor[] face = back ? [FX.Mix(col[1], Backs[0], 0.2), FX.Mix(col[2], Backs[1], 0.22), FX.Mix(col[3], Backs[2], 0.22)] : [col[2], col[3], col[4]];
        FXColor rim = col[0], vein = back ? FX.Mix(col[2], Backs[3], 0.5) : col[1];
        q.Shade(x - ext, y - ext, x + ext, y + ext, (px, py, @out) =>
        {
            double dx = px - x, dy = py - y, lu = (dx * c + dy * s) / L, lv = (-dx * s + dy * c) / (Wd * fs);
            var d = ShapeAt(shape, lu, lv);
            if (lu < -1.25 || lu > 1.1) return 0;
            // the stem pokes out past the base
            if (lu < -0.92 && Math.Abs(lv * Wd * fs) < 0.5) { @out.C = rim; @out.A = a; return 0; }
            if (d > 1.32) return 0;
            @out.A = a;
            if (d > 1) @out.C = rim;
            else if (Math.Abs(lv * Wd * fs) < 0.45 && lu > -0.9 && lu < 0.75) @out.C = vein;
            else @out.C = lv < -0.15 ? face[2] : lv < 0.35 ? face[1] : face[0];
            return 0;
        });
    }

    /// <summary>Fallen leaves lying in a band along the floor, overlapping; they never move, so they are shaded once.</summary>
    FXWeather.Recorder MakeLitter()
    {
        var rec = new FXWeather.Recorder(resetAlpha: true);
        var S = o.Seed;
        for (int i = 0; i < 64; i++)
        {
            double x = -164 + FX.Rand(S, i, 91) * 328, y = FLOOR - 2 + FX.Floor(FX.Rand(S, i, 92) * 4) * 2;
            var col = R3[(int)FX.Floor(FX.Rand(S, i, 93) * 3)];
            Leaf(rec, x, y, 3.6 + FX.Rand(S, i, 94) * 1.8, (FX.Rand(S, i, 95) - 0.5) * 0.7, 0.45 + FX.Rand(S, i, 96) * 0.25,
                 (int)FX.Floor(FX.Rand(S, i, 97) * 3), col.Select(cc => FX.Mix(cc, col[0], 0.12)).ToArray(), 1);
        }
        return rec;
    }
}

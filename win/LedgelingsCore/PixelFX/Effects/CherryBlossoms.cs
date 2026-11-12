// Pink petals flutter down on a spring breeze, tumbling in little spirals and flashing as they catch the light,
// with a few whole blossoms spinning among them. pixelfx's `weather/cherry-blossoms` (MIT), after Sprite Fusion's
// open-source falling leaves (https://www.spritefusion.com/pixel-art-vfx/falling-leaves, MIT, Hugo Duprez).
// The Mac's twin is CherryBlossoms.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXBlossoms : IFXEffect, IFXBackdropped
{
    public static readonly FXMeta Meta = new("weather/cherry-blossoms", size: (320, 180), origin: (160, 170), duration: 10, loop: true,
                                             palette: ["#4a1832", "#8e3460", "#d26a94", "#f2a2c0", "#ffd2e2", "#fff4f8"], seed: 12);
    const double D = 10.0, FLOOR = 1.0;
    static readonly FXColor Heart = FX.Hex("#ffe08a");

    readonly FXOptions o;
    readonly FXColor[] C;
    FXWeather.Recorder? scatter;
    /// <summary>false: no plum dusk over the whole canvas (drawn over the desktop); the fallen petals and the falling ones stay.</summary>
    public bool Backdrop { get; set; } = true;
    public FXBlossoms(FXOptions o) { this.o = o; C = FX.Fit(o.Palette, 6); }

    static double Gust(double t) => 22 * Math.Sin((FX.Tau * t) / D + 0.4) + 7 * Math.Sin((FX.Tau * 2 * t) / D - 1);

    public void DrawBack(Painter p, double t)
    {
        var q = new FXWeather.Clip(p, Meta);
        var S = o.Seed;
        var C = this.C;
        // a soft plum dusk, so the sky's stars don't read as petals
        if (Backdrop)
        {
            FXColor top = FX.Hex("#0e0a14"), low = FX.Mix(FX.Hex("#1a0e1a"), C[0], 0.4);
            FXWeather.Rows(p, Meta, -170, 9, (y, R) =>
            {
                var k = (y + 170) / 180;
                R.Fill(FX.Mix(top, low, k * k), 0.3 + 0.12 * k, blend: true);
            });
        }
        (scatter ??= MakeScatter()).Replay(q);
        Petals(q, t, S, false);
    }

    public void Draw(Painter p, double t)
    {
        var q = new FXWeather.Clip(p, Meta);
        var S = o.Seed;
        Petals(q, t, S, true);
        Blossoms(q, t, S);
    }

    /// <summary>Petals: each tumbles in a little spiral as it falls and drifts on the breeze, flipping fast; turned full
    /// face to the light it flashes.</summary>
    void Petals(FXWeather.Clip q, double t, double S, bool near)
    {
        var C = this.C;
        int n = near ? 54 : 90;
        var sd = S * 7 + (near ? 1 : 0);
        FXWeather.Trips(t, D, n, sd, 1, 2, (u, k, m, i) =>
        {
            var j = FX.Wrap(k, m);
            double R(double c) => FX.Rand(sd, i, j, c);
            double dur = D / m, tf = dur * 0.84, a = Math.Min(u * dur, tf), rest = u * dur - tf;
            double born = t - u * dur, x0 = -200 + R(1) * 330, y0 = -184.0, vy = (FLOOR + (near ? 2 : 0) - y0) / tf, vx = 9 + R(2) * 10;
            double rho = (near ? 3 : 2) + R(3) * 3, w = 2.2 + R(4) * 2.8, ph = R(5) * FX.Tau, gk = near ? 1.0 : 0.6;
            (double, double) At(double aa) =>
                (x0 + vx * aa + (Gust(born + aa) - Gust(born)) * gk + rho * Math.Cos(w * aa + ph), y0 + vy * aa + rho * 0.6 * Math.Sin(w * aa + ph));
            var len = (near ? 3.6 : 2.6) + R(6) * 1.1;
            if (rest > 0)
            {
                var (lx, ly) = At(tf);
                // a landed petal settles and shrinks away (no dither, so the ground stays clean)
                var fade = 1 - rest / (dur - tf);
                if (fade > 0.15) Petal(q, lx, ly, len * (0.35 + 0.65 * fade), (R(7) - 0.5) * 1.2, 0.5, C, 1);
                return;
            }
            var (x, y) = At(a);
            double flip = Math.Cos(R(8) * FX.Tau + a * (3 + R(9) * 5)), ang = R(10) * FX.Tau + a * (R(11) - 0.5) * 3;
            Petal(q, x, y, len, ang, flip, C, 1);
            if (flip > 0.9)
            {
                var g = (flip - 0.9) / 0.1;
                q.Px(x, y - 1, FX.White);
                q.Glow(x, y, near ? 7 : 5, C[4], (near ? 0.32 : 0.22) * g);
            }
        });
    }

    /// <summary>A petal: a little notched teardrop, squashed across as it flips; its pale face or its deeper back.</summary>
    static void Petal(IFXWeatherShading q, double x, double y, double len, double ang, double flip, FXColor[] C, double a)
    {
        double fs = 0.3 + 0.7 * Math.Abs(flip), c = Math.Cos(ang), s = Math.Sin(ang), e = len + 1;
        bool back = flip < -0.2;
        // deeper at the base, palest at the tip, lit on one side; the back is a step deeper all over
        FXColor[] face = back ? [C[1], C[2], C[3]] : [C[2], C[3], C[4]];
        var tip = back ? C[3] : C[5];
        q.Shade(x - e, y - e, x + e, y + e, (px, py, @out) =>
        {
            double dx = px - x, dy = py - y, u = (dx * c + dy * s) / len, v = (-dx * s + dy * c) / (len * fs);
            if (u < -1 || u > 1) return 0;
            var hw = 0.55 * Math.Sqrt(1 - u * u) * (1 + 0.35 * u);
            if (Math.Abs(v) > hw || (u > 0.7 && Math.Abs(v) < 0.12)) return 0;
            @out.C = u > 0.45 && v < 0.1 ? tip : u < -0.45 ? face[0] : v < 0 ? face[2] : face[1];
            @out.A = a;
            return 0;
        });
    }

    /// <summary>A whole blossom: five petals round a gold heart, spinning slowly as it sinks.</summary>
    void Blossoms(FXWeather.Clip q, double t, double S)
    {
        var C = this.C;
        FXWeather.Trips(t, D, 7, S * 31, 1, 1, (u, _, _, i) =>
        {
            double R(double c) => FX.Rand(S * 31, i, c);
            double y = -190 + (FLOOR + 2 + 190) * Math.Min(1, u / 0.9), born = t - u * D;
            if (u > 0.9) return;
            var x = -190 + R(1) * 330 + 14 * u * D * 0.1 + (Gust(t) - Gust(born)) + 6 * Math.Sin(u * FX.Tau * 2 + R(2) * 6);
            var rot = R(3) * FX.Tau + u * D * (R(4) - 0.5) * 2;
            var r = 3.6 + R(5) * 1.2;
            for (int p = 0; p < 5; p++)
            {
                var an = rot + (p * FX.Tau) / 5;
                Petal(q, x + Math.Cos(an) * r * 0.75, y + Math.Sin(an) * r * 0.75, r * 0.7, an, 1, C, 1);
            }
            q.Px(x, y, Heart);
            q.Glow(x, y, 8, C[4], 0.2);
        });
    }

    /// <summary>Petals already fallen, scattered along the floor; they never move, so they are shaded once.</summary>
    FXWeather.Recorder MakeScatter()
    {
        var rec = new FXWeather.Recorder(resetAlpha: false);
        var S = o.Seed;
        for (int i = 0; i < 46; i++)
            Petal(rec, -164 + FX.Rand(S, i, 71) * 328, FLOOR + FX.Floor(FX.Rand(S, i, 72) * 3) * 2, 2.6 + FX.Rand(S, i, 73),
                  (FX.Rand(S, i, 74) - 0.5) * 1.2, 0.5, C, 1);
        return rec;
    }
}

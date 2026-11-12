// A bold ! springs up off the head, stretching as it shoots up and squashing as it lands; surprise ticks
// flick out, it wobbles, then pops away. pixelfx's `ui/exclamation` (MIT). The Mac's twin is Exclamation.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXExclamation : IFXEffect
{
    public static readonly FXMeta Meta = new("ui/exclamation", size: (84, 104), origin: (42, 92), duration: 1.4, loop: false,
                                             palette: ["#2a1405", "#6a2e06", "#b85a0a", "#f08c14", "#ffc23a", "#ffe580", "#fff6c8", "#ffffff"], seed: 3);
    const double HEAD = -40.0, REST = -45.0, POP = 1.1;
    readonly FXColor[] C;
    readonly Rng R;
    readonly FXParticles ps;
    readonly FXLights lights = new();
    // the mark's foot: shot up off the head with a spring, so it overshoots and settles
    double my = HEAD, vy = -420.0, sq = 0.0;
    bool landed = false;
    double t = 0.0;
    bool popped = false, sprung = false;
    readonly double end = Meta.Duration - 0.05;

    public FXExclamation(FXOptions o)
    {
        C = FX.Fit(o.Palette, 8);
        R = new Rng(o.Seed);
        ps = new FXParticles(rng: R, sparks: [C[7], C[6], C[5], C[3]]);
    }

    /// <summary>The mark: a bar tapering to its foot and a round dot, outlined, lit down its left side, turned by a.</summary>
    void Bang(Painter p, double x, double y, double sx, double sy, double a, bool white)
    {
        var C = this.C;
        double ca = Math.Cos(a), sa = Math.Sin(a);
        static double Hw(double V) => 2.3 + (-V - 10) * 0.09;
        static bool InBar(double U, double V) => V > -24 && V < -9.5 && Math.Abs(U) < Hw(V);
        static bool InDot(double U, double V) => FX.Hypot(U, V + 3.6) < 3.3;
        static bool Inside(double U, double V) => InBar(U, V) || InDot(U, V);
        p.Shade(x - 16, y - 34, x + 16, y + 6, (px, py, _) =>
        {
            double dx = px - x, dy = py - y, u = (dx * ca + dy * sa) / sx, v = (-dx * sa + dy * ca) / sy, ex = 1 / sx, ey = 1 / sy;
            if (!Inside(u, v)) return Inside(u - ex, v) || Inside(u + ex, v) || Inside(u, v - ey) || Inside(u, v + ey) ? C[0] : 0;
            if (white) return FX.White;
            if (InDot(u, v)) return FX.Hypot(u + 1.2, v + 4.8) < 1.2 ? FX.White : u + v + 3.6 < -0.5 ? C[6] : u + v + 3.6 < 1.5 ? C[5] : C[4];
            double w = Hw(v), q = (u + w) / (2 * w);
            if (q < 0.28) return v < -20 ? FX.White : C[7];
            if (q > 0.74) return C[4];
            return v < -18 ? C[6] : C[5];
        });
    }

    public void Update(double dt)
    {
        var C = this.C;
        var R = this.R;
        t += dt;
        if (t < POP)
        {
            // a stiff spring pulls it to its rest above the head
            vy += (-(my - REST) * 900 - vy * 14) * dt;
            my += vy * dt;
            if (!landed && vy > 0) { landed = true; sq = 1; }
        }
        sq = Math.Max(0, sq - dt / 0.12);
        // it leaves the head with a little burst of light
        if (!sprung && t >= 0.04)
        {
            sprung = true;
            lights.Add(0, HEAD - 4, 26, C[5], 0.6, 0.25);
            for (int i = 0; i < 8; i++)
            {
                double an = -Math.PI / 2 + R.Range(-1.3, 1.3), sp = R.Range(40, 90);
                ps.Spawn(FXKind.Star, R.Range(-4, 4), HEAD - 2, Math.Cos(an) * sp, Math.Sin(an) * sp, R.Range(0.2, 0.4), R.Pick([C[7], C[6], C[5]]), i % 3 != 0 ? 0.6 : 1.3);
            }
        }
        if (!popped && t >= POP + 0.05)
        {
            popped = true;
            lights.Add(0, REST - 13, 28, C[5], 0.5, 0.2);
            for (int i = 0; i < 7; i++)
            {
                double an = (i / 7.0) * FX.Tau + R.Range(-0.2, 0.2), sp = R.Range(30, 60);
                ps.Spawn(FXKind.Star, Math.Cos(an) * 5, REST - 13 + Math.Sin(an) * 9, Math.Cos(an) * sp, Math.Sin(an) * sp, Math.Min(R.Range(0.2, 0.35), end - t), R.Pick([C[7], C[6], C[5]]), i % 3 != 0 ? 0.6 : 1.4);
            }
        }
        ps.Update(dt);
        lights.Update(dt);
    }

    public void Draw(Painter p, double tt)
    {
        var C = this.C;
        var k = t;
        // surprise ticks: three flick out each side on the spring, and again on a second beat
        foreach (var (t0, len) in (ReadOnlySpan<(double, double)>)[(0.04, 6.0), (0.48, 4.5)])
        {
            var u = (k - t0) / 0.24;
            if (u <= 0 || u >= 1) continue;
            foreach (var s in (ReadOnlySpan<double>)[-1.0, 1.0])
                for (int i = 0; i < 3; i++)
                {
                    double an = -Math.PI / 2 + s * (0.55 + i * 0.42), r0 = 14 + 7 * FX.Ease.OutCubic(u), L = len * Math.Sin(u * Math.PI) * (i == 1 ? 1 : 0.75);
                    double cx = 0.0, cy = REST - 13, ca = Math.Cos(an), sa = Math.Sin(an);
                    if (L < 0.8) continue;
                    p.Line(cx + ca * r0, cy + sa * r0, cx + ca * (r0 + L), cy + sa * (r0 + L), q => q < 0.5 ? FX.White : C[5]);
                }
        }
        // the mark: stretched while it shoots up, squashed as it lands, wobbling, white on the pop
        var pu = (k - POP) / 0.06;
        if (pu < 1)
        {
            double speed = Math.Min(1, Math.Abs(vy) / 420), up = vy < 0 ? speed : 0;
            double sx = 1 - 0.3 * up + 0.3 * sq, sy = 1 + 0.45 * up - 0.28 * sq;
            if (k < 0.05) { sx *= k / 0.05; sy *= k / 0.05; }
            if (pu > 0) { sx = 1 + 0.3 * pu; sy = sx; }
            var wob = 0.28 * Math.Exp(-k * 4) * Math.Sin(k * 26);
            var white = k < 0.06 || pu > 0;
            if (sx > 0.1) Bang(p, 0, my, sx, sy, wob, white);
            p.Glow(0, my - 13, 20, C[5], 0.35 + (white ? 0.3 : 0));
            if (k > 0.6 && k < 0.85) FX.Sparkle(p, -3, my - 22, 3.5 * Math.Sin(((k - 0.6) / 0.25) * Math.PI), C[7], C[6], 0.4);
        }
        ps.Draw(p, null);
        lights.Draw(p);
    }
}

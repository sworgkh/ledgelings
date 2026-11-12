// Clock ticking: a glassy dial behind the head ticks round in heavy steps, flashing with each, while
// drops sink in slow motion. pixelfx's `status/slowed` (MIT). The Mac's twin is Slowed.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXSlowed : IFXEffect
{
    public static readonly FXMeta Meta = new("status/slowed", size: (64, 76), origin: (32, 68), duration: 2.4, loop: true,
                                             palette: ["#081a24", "#0e3446", "#165a6e", "#2a8a9a", "#52bcc4", "#9ee6e0", "#e2fff8", "#ffffff"], seed: 7);
    const double D = 2.4, Ticks = 4.0, Step = D / Ticks, R = 18.0;
    readonly FXOptions o;
    readonly FXColor[] C;
    public FXSlowed(FXOptions o) { this.o = o; C = FX.Fit(o.Palette, 8); }

    /// <summary>The hand's angle: it waits, pulls back a little, snaps a quarter turn, overshoots and settles.</summary>
    static (double Ang, double Flash, double Ph) Hand(double t)
    {
        double k = FX.Floor(t / Step), ph = (t - k * Step) / Step, @base = -Math.PI / 2 + (k * FX.Tau) / Ticks, q = FX.Tau / Ticks;
        if (ph < 0.62) return (@base, 0, ph);
        if (ph < 0.72) return (@base - 0.1 * Math.Sin(((ph - 0.62) / 0.1) * Math.PI * 0.5), 0, ph);
        double s = (ph - 0.72) / 0.28, snap = FX.Ease.OutBack(FX.Clamp(s / 0.35), 2.2), wob = Math.Exp(-s * 6) * Math.Sin(s * 22) * 0.05;
        return (@base - 0.1 * (1 - FX.Clamp(s / 0.2)) + q * snap + wob, Math.Exp(-s * 5), ph);
    }
    /// <summary>The flash of the last tick, still fading after the hand has settled.</summary>
    static double Afterglow(double t)
    {
        var s = FX.Mod(FX.Mod(t - Step * 0.72, Step) + Step, Step);
        return Math.Exp(-s * 4);
    }

    void Dial(Painter p, double cx, double cy, double t)
    {
        var C = this.C;
        var h = Hand(t);
        var fl = Math.Max(h.Flash, Afterglow(t));
        p.Disc(cx, cy, R - 1, C[2], 0.2);
        p.Disc(cx - R * 0.25, cy - R * 0.3, R * 0.5, C[4], 0.08);
        p.Ring(cx, cy, R + 1, 1, C[0]);
        p.Ring(cx, cy, R, 2, (v, ang) => Math.Sin(ang + 0.8) < -0.3 ? (fl > 0.4 ? C[7] : C[6]) : v > 0.5 ? C[5] : C[4], (_, _) => 1);
        p.Ring(cx, cy, R - 3.5, 1, C[3], 0.6);
        for (int i = 0; i < 60; i++)
        {
            if (i % 5 == 0) continue;
            var a = (i / 60.0) * FX.Tau;
            p.Dot(cx + Math.Cos(a) * (R - 2.6), cy + Math.Sin(a) * (R - 2.6), C[4], 0.8);
        }
        for (int i = 0; i < 12; i++)
        {
            var a = (i / 12.0) * FX.Tau;
            var big = i % 3 == 0;
            double r0 = R - 2.5, r1 = R - (big ? 6 : 4.5), c = Math.Cos(a), s = Math.Sin(a);
            p.Line(cx + c * r0, cy + s * r0, cx + c * r1, cy + s * r1, big ? C[6] : C[5]);
        }
        double shud = h.Flash * Math.Sin(t * 60) * 0.06, ha = -Math.PI / 2 + 2.2 + shud;
        p.Beam(cx, cy, cx + Math.Cos(ha) * R * 0.5, cy + Math.Sin(ha) * R * 0.5, 2.2, C[5]);
        double tx = cx + Math.Cos(h.Ang) * (R - 4), ty = cy + Math.Sin(h.Ang) * (R - 4);
        p.Beam(cx, cy, tx, ty, 2.4, (u, _) => u > 0.8 ? C[7] : C[6], (_, _) => 1);
        p.Circle(cx, cy, 2, C[6]);
        p.Px(cx, cy, C[1]);
        p.Glow(cx, cy, R + 8, C[4], 0.14 + 0.2 * fl);
        p.GlowRing(cx, cy, R, 3, C[5], 0.12 + 0.35 * fl);
        p.Glow(tx, ty, 5, C[6], 0.3 + 0.3 * h.Flash);
        if (h.Flash > 0.02)
        {
            var s = 1 - h.Flash;
            p.Ring(cx, cy, R + 2 + 10 * s, 1, C[5], h.Flash);
            p.GlowRing(cx, cy, R + 2 + 10 * s, 3, C[4], 0.3 * h.Flash);
        }
    }

    public void DrawBack(Painter p, double t)
    {
        var a = o.Actor;
        Dial(p, 0, a.Y + 3, t);
        // the body lags behind itself: an after-image of its outline, dragged a step back after every tick
        var lag = Afterglow(t);
        if (lag > 0.05) p.Outline(a.Mask, a.X - 1 - FX.Round(2 * lag), a.Y, (_, _) => C[5], (_, _) => 0.55 * lag);
    }

    public void Draw(Painter p, double t)
    {
        var C = this.C;
        var a = o.Actor;
        var S = FXStatus.ShapeOf(a);
        var fl = Math.Max(Hand(t).Flash, Afterglow(t));
        double ax = a.X, ay = a.Y;
        foreach (var (mx, my) in S.Body) p.Blend(ax + mx, ay + my, C[5], 0.08 + 0.12 * fl);
        FX.Cycle(t, D, 6, o.Seed + 3, r => r.Range(1.6, 2.2), (age, life, r, _) =>
        {
            double side = r.Next() < 0.5 ? -1 : 1, x = side * r.Range(10, 17), y0 = ay + r.Range(6, 22), v0 = r.Range(18, 30), k = 1.1;
            double YAt(double g) => y0 + (v0 * (1 - Math.Exp(-k * g))) / k + 4 * g;
            double y = YAt(age), u = age / life;
            if (y < -1)
            {
                foreach (var (lag, al) in (ReadOnlySpan<(double, double)>)[(0.22, 0.35), (0.11, 0.6)])
                    if (age > lag) p.Dot(x, YAt(age - lag), C[4], al);
                p.Px(x, y - 1, C[5]);
                p.Px(x, y, C[6]);
                p.Px(x, y + 1, C[5]);
                p.Px(x - 1, y + 1, C[4]);
                p.Px(x - 1, y, C[7]);
                p.Glow(x, y, 4, C[5], 0.3 * (1 - u));
            }
            else
            {
                var g = age;
                while (g > 0 && YAt(g) >= -1) g -= 0.02;
                var s = FX.Clamp((age - g) / 0.9);
                if (s < 1)
                {
                    double rx = 1 + 7 * Math.Sqrt(s);
                    var c = s < 0.3 ? C[6] : C[5];
                    foreach (var sd in (ReadOnlySpan<double>)[-1.0, 1.0]) p.Line(x + sd * rx, -0.5, x + sd * (rx - 1.5), -0.5, c, (1 - s) * 1.2);
                    for (var dx = -rx + 2; dx <= rx - 2; dx += 1) p.Dot(x + dx, -1.5, C[4], (1 - s) * 0.5 * (1 - Math.Abs(dx) / rx));
                    p.Glow(x, -1, 4 + rx, C[4], 0.12 * (1 - s));
                }
            }
        });
    }
}

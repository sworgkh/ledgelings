// Blink out: the caster crackles with gathering light, flashes white, squeezes into a line of light that
// collapses and pops away in sparks. pixelfx's `arcane/blink-out` (MIT), adapted from Sprite Fusion's
// open-source blink (https://www.spritefusion.com/pixel-art-vfx/movement), MIT, Copyright (c) 2026 Hugo Duprez.
// The Mac's twin is BlinkOut.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXBlinkOut : IFXEffect
{
    public static readonly FXMeta Meta = new("arcane/blink-out", size: (136, 96), origin: (68, 80), duration: 1.6, loop: false,
                                             palette: ["#140a26", "#2b1252", "#481c88", "#6b2cc0", "#9a48ec", "#c684ff", "#ecc8ff", "#ffffff"], seed: 11);
    const double OUT = 0.32, SQUEEZE = 0.12, COLLAPSE = 0.08, POP = OUT + SQUEEZE + COLLAPSE;

    readonly FXColor[] C;
    readonly Rng R;
    readonly FXActor A;
    readonly byte[] sh;
    readonly FXParticles ps;
    readonly FXLights lights = new();
    readonly double mx, my;
    readonly FXColor[] COLS;
    double t;
    bool @out, popped;

    public FXBlinkOut(FXOptions o)
    {
        C = FX.Fit(o.Palette, 8); R = new Rng(o.Seed); A = o.Actor; sh = FXArcane.Shades(A);
        ps = new FXParticles(rng: R, ground: _ => 0, sparks: [FX.White, C[6], C[5], C[4]]);
        mx = A.X + A.W / 2.0; my = A.Y + A.H * 0.55;
        COLS = [FX.White, C[6], C[6], C[5], C[4]];
    }

    bool Inside(int x, int y) => x >= 0 && y >= 0 && x < A.W && y < A.H && A.Mask.Data[y * A.W + x] != 0;

    public double ActorAlpha(double t) => t < OUT ? 1 : 0;

    public void Update(double dt)
    {
        t += dt;
        var C = this.C;
        var R = this.R;
        var A = this.A;
        double mx = this.mx, my = this.my;
        if (t < OUT - 0.04 && R.Chance(0.7))
        {
            double a = R.Range(0, FX.Tau), D = R.Range(22, 44), T = R.Range(0.12, 0.18), v = (D * 3) / (Math.Exp(3 * T) - 1);
            double x = mx + Math.Cos(a) * D, y = Math.Min(-2, my + Math.Sin(a) * D), h = FX.Hypot(x - mx, y - my), l = h == 0 ? 1 : h;
            ps.Spawn(FXKind.Streak, x, y, ((mx - x) / l) * v, ((my - y) / l) * v, T, R.Chance(0.5) ? C[6] : C[5]);
        }
        if (!@out && t >= OUT)
        {
            @out = true;
            lights.Add(mx, my - 6, 54, C[5], 0.9, 0.3);
            lights.Add(mx, my, 26, FX.White, 0.8, 0.1);
        }
        if (!popped && t >= POP)
        {
            popped = true;
            lights.Add(mx, my - 6, 58, C[5], 0.9, 0.35);
            lights.Add(mx, my, 24, FX.White, 0.9, 0.08);
            for (int i = 0; i < 110; i++)
            {
                double y = A.Y + R.Range(2, A.H - 2), s = R.Sign();
                double x = mx + R.Range(-1, 1), vx = s * R.Range(25, 105), vy = R.Range(-70, 10), life = R.Range(0.5, 0.95);
                var c = R.Pick(COLS);
                double size = R.Chance(0.3) ? 2 : 1;
                ps.Spawn(FXKind.Ember, x, y, vx, vy, life, c, size);
            }
            for (int i = 0; i < 18; i++)
            {
                double a = R.Range(0, FX.Tau), sp = R.Range(80, 240);
                ps.Spawn(FXKind.Spark, mx, my, Math.Cos(a) * sp, Math.Sin(a) * sp - 40, R.Range(0.2, 0.5));
            }
            for (int i = 0; i < 14; i++)
            {
                double a = R.Range(0, FX.Tau), sp = R.Range(20, 110);
                var life = R.Range(0.4, 0.9);
                var c = R.Pick([FX.White, C[6], C[5]]);
                var size = R.Range(0.8, 1.8);
                ps.Spawn(i % 2 != 0 ? FXKind.Star : FXKind.Mote, mx, my, Math.Cos(a) * sp, Math.Sin(a) * sp * 0.8 - 20, life, c, size);
            }
        }
        ps.Update(dt);
        lights.Update(dt);
    }

    void Ring(Painter p, bool far)
    {
        var C = this.C;
        var k = (t - POP) / 0.5;
        if (k >= 0 && k < 1)
            FX.Band(p, 0, 0, 4 + 30 * FX.Ease.OutCubic(k), 0.2, Math.Max(1, 3 * (1 - k)), 1.15 - k, [C[3], C[5], C[6], FX.White],
                    far ? g => Math.Sin(g) < 0 : g => Math.Sin(g) >= 0, k < 0.25);
    }

    public void DrawBack(Painter p, double tt)
    {
        var C = this.C;
        var A = this.A;
        // the afterimage it leaves: a translucent violet ghost that thins away
        if (t > POP && t < POP + 0.6)
        {
            var k = 0.5 * (1 - (t - POP) / 0.6);
            for (int y = 0; y < A.H; y++)
                for (int x = 0; x < A.W; x++)
                    if (sh[y * A.W + x] != 0) p.Blend(A.X + x, A.Y + y, sh[y * A.W + x] == 1 ? C[3] : C[4], k);
        }
        Ring(p, true);
        if (t < POP + 0.3) p.Glow(0, -1, 26, C[5], 0.3 * (t < OUT ? t / OUT : 1 - FX.Clamp((t - POP) / 0.3)));
    }

    public void Draw(Painter p, double tt)
    {
        var C = this.C;
        var A = this.A;
        double mx = this.mx, my = this.my;
        var f = FX.Floor(t * 30);
        if (t < OUT)
        {
            // the body brightens and an outline of light crackles round it, thicker as it gathers
            double k = t / OUT, ax = A.X, ay = A.Y;
            for (int y = 0; y < A.H; y++)
                for (int x = 0; x < A.W; x++)
                {
                    if (Inside(x, y)) p.Light(ax + x, ay + y, C[6], k * k * (sh[y * A.W + x] == 1 ? 0.3 : 0.75));
                    else if ((Inside(x - 1, y) || Inside(x + 1, y) || Inside(x, y - 1) || Inside(x, y + 1)) && FX.Rand(x, y, f) < 0.25 + 0.65 * k)
                        p.Px(ax + x, ay + y, k > 0.6 && FX.Rand(x, y, 7) < 0.5 ? FX.White : C[6]);
                }
            p.Glow(mx, my, 30, C[5], 0.5 * k);
        }
        else if (t < OUT + 0.05)
        {
            FXArcane.Squeezed(p, A, sh, 1, FX.White, C[6]);
            p.Glow(mx, my, 40, C[5], 0.8);
        }
        else if (t < OUT + SQUEEZE)
        {
            // squeezed into a line
            var q = FX.Ease.InCubic((t - OUT - 0.05) / (SQUEEZE - 0.05));
            FXArcane.Squeezed(p, A, sh, 1 - q, FX.White, C[6]);
            p.Glow(mx, my, 34, C[5], 0.8);
        }
        else if (t < POP)
        {
            // the line shrinks to a point
            double q = (t - OUT - SQUEEZE) / COLLAPSE, hh = (A.H / 2.0 + 2) * (1 - FX.Ease.InQuad(q));
            for (var y = -hh - 3; y <= hh + 3; y += 1) p.Dot(mx, my + y, Math.Abs(y) < hh ? FX.White : C[6], Math.Abs(y) < hh ? 1 : 0.7);
            if (hh > 4)
                for (var y = -hh * 0.7; y <= hh * 0.7; y += 1) { p.Dot(mx - 1, my + y, C[5], 0.6); p.Dot(mx + 1, my + y, C[5], 0.6); }
            p.Glow(mx, my, 30, C[5], 0.9);
            p.Glow(mx, my, 8, FX.White, 0.5);
        }
        if (t >= POP && t < POP + 0.22)
        {
            var q = (t - POP) / 0.22;
            FX.Flare(p, mx, my, 22 * Math.Pow(1 - q, 1.5) + 2, 1 - q, C);
            if (q < 0.3) p.Circle(mx, my, 4 * (1 - q / 0.3) + 1, FX.White);
        }
        Ring(p, false);
        if (t > POP && t < POP + 0.3) FX.Sparkle(p, mx, my - 1, 3, C[6], C[5], 0.3 * (1 - (t - POP) / 0.3));
        ps.Draw(p, null);
        lights.Draw(p);
    }
}

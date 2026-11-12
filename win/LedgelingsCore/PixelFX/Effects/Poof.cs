// A cartoon death poof: a white pop, a ring of soft round smoke balls bursting out between speed lines, little
// stars spinning off, and the cloud lifting and thinning away. pixelfx's `spawn/poof` (MIT), after Sprite
// Fusion's open-source explosion (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT,
// Copyright (c) 2026 Hugo Duprez. The Mac's twin is Poof.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXPoof : IFXEffect
{
    public static readonly FXMeta Meta = new("spawn/poof", size: (112, 92), origin: (56, 80), duration: 1.6, loop: false,
                                             palette: ["#2a2440", "#5e5878", "#9a94b4", "#cdc8e0", "#f2f0fa", "#ffffff"], seed: 21);
    static readonly string[] Stars = ["#ffd84a", "#fff3a6", "#ffffff"];
    const double CY = -17.0;
    struct Ball { public double X, Y, Vx, Vy, R0, R1, Life, Delay, Max; }
    readonly record struct Line(double A, double R1, double D);
    enum Layer { Shade, Body, Cap }

    readonly FXOptions o;
    readonly FXColor[] C, S;
    readonly Rng R;
    readonly FXParticles ps;
    readonly FXLights lights = new();
    readonly List<Ball> balls = new();
    readonly List<Line> lines = new();
    double t;

    public FXPoof(FXOptions o)
    {
        this.o = o;
        var C = FX.Fit(o.Palette, 6);
        var S = FX.Fit(FX.Ramp(Stars), 3);
        var R = new Rng(o.Seed);
        const FXColor W = FX.White;
        this.C = C; this.S = S; this.R = R;
        ps = new FXParticles(rng: R, ground: _ => 0, sparks: [W, S[1], S[0], C[2]]);
        // a ring of fat balls round a fat core, thrown out fast and stopped by drag, each swelling as it slows
        const int ring = 9;
        for (int i = 0; i < ring; i++)
        {
            double a = ((double)i / ring) * FX.Tau + R.Range(-0.2, 0.2), sp = R.Range(95, 140), r = R.Range(5, 7);
            var life = R.Range(0.7, 1.05);
            balls.Add(new Ball { X = Math.Cos(a) * 3, Y = CY + Math.Sin(a) * 3, Vx = Math.Cos(a) * sp, Vy = Math.Sin(a) * sp * 0.8 - 12, R0 = r * 0.5, R1 = r, Life = life, Delay = R.Range(0, 0.03) });
        }
        for (int i = 0; i < 5; i++)
        {
            double a = R.Range(0, FX.Tau), sp = R.Range(20, 60);
            double r1 = R.Range(6.5, 8.5), life = R.Range(0.85, 1.2);
            balls.Add(new Ball { X = Math.Cos(a) * 2, Y = CY + Math.Sin(a) * 2, Vx = Math.Cos(a) * sp, Vy = Math.Sin(a) * sp - 16, R0 = 4, R1 = r1, Life = life, Delay = R.Range(0.02, 0.06) });
        }
        // a few small puffs flung further out, gone quickly, so the cloud's edge is ragged
        for (int i = 0; i < 7; i++)
        {
            double a = R.Range(0, FX.Tau), sp = R.Range(170, 240), r = R.Range(2.2, 3.6);
            var life = R.Range(0.32, 0.5);
            balls.Add(new Ball { X = Math.Cos(a) * 4, Y = CY + Math.Sin(a) * 4, Vx = Math.Cos(a) * sp, Vy = Math.Sin(a) * sp * 0.75 - 10, R0 = r * 0.6, R1 = r, Life = life, Delay = R.Range(0.01, 0.04) });
        }
        for (int i = 0; i < balls.Count; i++) { var b = balls[i]; b.Max = b.Life; balls[i] = b; }
        // speed lines between the balls, flicked out and gone in a few frames
        for (int i = 0; i < 12; i++)
        {
            double a = (i / 12.0) * FX.Tau + R.Range(-0.12, 0.12) + 0.13, sa = Math.Sin(a);
            // the ones that point down stop at the floor
            var r1 = Math.Min(R.Range(24, 34), sa > 0.1 ? (-2 - CY) / sa : 99);
            lines.Add(new Line(a, r1, R.Range(0, 0.04)));
        }
        // little stars spun off the pop
        for (int i = 0; i < 7; i++)
        {
            double a = R.Range(-Math.PI, 0.3), sp = R.Range(70, 125);
            ps.Spawn(FXKind.Star, Math.Cos(a) * 6, CY + Math.Sin(a) * 6, Math.Cos(a) * sp, Math.Sin(a) * sp - 30, R.Range(0.55, 0.95), R.Pick([S[2], S[1], S[1], S[0]]), R.Range(1.3, 2.4), R.Range(0.02, 0.1));
        }
        for (int i = 0; i < 10; i++)
        {
            double a = R.Range(0, FX.Tau), sp = R.Range(40, 110);
            ps.Spawn(FXKind.Star, Math.Cos(a) * 5, CY + Math.Sin(a) * 5, Math.Cos(a) * sp, Math.Sin(a) * sp - 20, R.Range(0.3, 0.6), R.Pick([W, S[1]]), 0.6, R.Range(0, 0.08));
        }
        // the feet go too: a skid of dust along the floor
        for (int i = 0; i < 6; i++)
        {
            var s = R.Sign();
            ps.Spawn(FXKind.Dust, s * R.Range(1, 6), -1, s * R.Range(25, 70), -R.Range(2, 10), R.Range(0.4, 0.7), C[2], R.Range(1.6, 3), R.Range(0.02, 0.08));
        }
        lights.Add(0, CY, 46, C[4], 0.8, 0.4);
        lights.Add(0, CY, 22, W, 0.8, 0.1);
    }

    /// <summary>A ball swells out, breathes, then shrinks to nothing.</summary>
    static double Radius(Ball b)
    {
        double age = b.Max - b.Life, u = age / b.Max;
        double grow = b.R0 + (b.R1 - b.R0) * FX.Ease.OutBack(FX.Clamp(age / 0.22), 2), breathe = 1 + 0.06 * Math.Sin(age * 14 + b.R1);
        return grow * breathe * (u < 0.62 ? 1 : 1 - FX.Ease.InBack(FX.Clamp((u - 0.62) / 0.38), 1.4));
    }
    void DrawBall(Painter p, Ball b, Layer layer)
    {
        var C = this.C;
        const FXColor W = FX.White;
        double age = b.Max - b.Life, r = Radius(b), a = Math.Min(1, age * 20);
        var lit = age < 0.12;
        if (r < 0.6) return;
        // the whole cloud is lit from above: the balls underneath are a step darker
        var hy = (b.Y - CY + 6) / 14;
        bool lo = hy > 0.4, hi = hy < -0.3;
        switch (layer)
        {
            case Layer.Shade: p.Disc(b.X + r * 0.16, b.Y + r * 0.2, r, lit ? C[3] : lo ? C[1] : C[2], 0.8 * a); break;
            case Layer.Body: p.Disc(b.X - r * 0.06, b.Y - r * 0.08, r * 0.86, lit ? C[4] : lo ? C[2] : C[3], 0.88 * a); break;
            case Layer.Cap:
                if (!lo || lit)
                {
                    p.Disc(b.X - r * 0.28, b.Y - r * 0.34, r * 0.42, lit || hi ? W : C[4], 0.85 * a);
                    if (age < 0.25) p.Disc(b.X - r * 0.3, b.Y - r * 0.38, r * 0.2, W, 0.9 * a * (1 - age / 0.25));
                }
                break;
        }
    }

    public void Update(double dt)
    {
        t += dt;
        for (int i = balls.Count - 1; i >= 0; i--)
        {
            var b = balls[i];
            if (b.Delay > 0) { b.Delay -= dt; balls[i] = b; continue; }
            b.Life -= dt;
            if (b.Life <= 0)
            {
                // each ball goes with a pip of light
                if (b.R1 > 4) ps.Spawn(FXKind.Star, b.X, b.Y, 0, -8, 0.22, FX.White, 0.6);
                balls.RemoveAt(i);
                continue;
            }
            // fast burst, hard drag, then a slow lift
            b.Vx -= b.Vx * 7 * dt;
            b.Vy -= b.Vy * 7 * dt + 30 * dt;
            b.X += b.Vx * dt;
            b.Y = Math.Min(b.Y + b.Vy * dt, -Radius(b) * 0.7);
            balls[i] = b;
        }
        ps.Update(dt);
        lights.Update(dt);
    }

    public void DrawBack(Painter p, double _t)
    {
        // a soft shadow where the body stood, and the light of the pop on the floor
        var s = 1 - FX.Smooth(0.1, 0.9, t);
        if (s > 0) p.Glow(0, -1, 26, C[4], 0.25 * s);
        ps.Draw(p, FXLayer.Back);
    }

    public void Draw(Painter p, double _t)
    {
        var C = this.C;
        var t = this.t;
        const FXColor W = FX.White;
        // the cloud: shade, body, then caps, so neighbouring balls merge into one lumpy cloud
        var live = balls.Where(b => b.Delay <= 0).ToList();
        foreach (var layer in (ReadOnlySpan<Layer>)[Layer.Shade, Layer.Body, Layer.Cap]) foreach (var b in live) DrawBall(p, b, layer);
        // the pop: a white ball and an 8-ray flare for a couple of frames, then a ring
        if (t < 0.07)
        {
            var k = t / 0.07;
            p.Circle(0, CY, 9 + 3 * k, C[4]);
            p.Circle(0, CY, 7 + 3 * k, W);
            FX.Flare(p, 0, CY, 20 * (1 - k * 0.5), 1 - k, C);
        }
        var rk = (t - 0.03) / 0.2;
        if (rk > 0 && rk < 1) p.Ring(0, CY, 8 + 18 * FX.Ease.OutCubic(rk), Math.Max(1, 2.5 * (1 - rk)), rk < 0.3 ? W : C[4], 1.1 - rk);
        foreach (var l in lines)
        {
            var u = (t - l.D) / 0.2;
            if (u <= 0 || u >= 1) continue;
            double head = 8 + (l.R1 - 8) * FX.Ease.OutExpo(FX.Clamp(u / 0.6)), tail = 8 + (l.R1 - 8) * FX.Ease.InCubic(u), ca = Math.Cos(l.A), sa = Math.Sin(l.A);
            p.Line(ca * tail, CY + sa * tail, ca * head, CY + sa * head, v => v > 0.6 ? W : C[4]);
            p.GlowLine(ca * tail, CY + sa * tail, ca * head, CY + sa * head, 3, C[4], 0.25);
        }
        ps.Draw(p, FXLayer.Front);
        lights.Draw(p);
    }
}

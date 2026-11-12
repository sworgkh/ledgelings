// Two party poppers bang one after the other: paper bits and curly streamers burst out, stall, then tumble
// and flutter down, flipping, and settle on the floor. pixelfx's `ui/confetti` (MIT); the flutter adapts
// Sprite Fusion's open-source falling leaves (https://www.spritefusion.com/pixel-art-vfx/falling-leaves),
// MIT License, Copyright (c) 2026 Hugo Duprez. The Mac's twin is Confetti.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXConfetti : IFXEffect
{
    public static readonly FXMeta Meta = new("ui/confetti", size: (200, 140), origin: (100, 126), duration: 3.4, loop: false,
                                             palette: ["#ff4a5a", "#ff9a2a", "#ffe03c", "#5ad84a", "#3cc8ff", "#7a6cff", "#f53cd1"], seed: 11);
    readonly record struct Popper(double X, double Y, double A, double T);
    static readonly Popper[] POPPERS = [new(-74, -1, -Math.PI / 2 + 0.62, 0.1), new(74, -1, -Math.PI / 2 - 0.62, 0.26)];
    static readonly FXColor INK = FX.Hex("#141019"), BACK = FX.Hex("#c8c0d8"), SMOKE = FX.Hex("#5d5660");

    sealed class Bit
    {
        public double X, Y, Vx, Vy; public FXColor C; public double W, H, Ang, Spin;
        public double Flip, Fs, Ph, Amp, Fw, X0 = 0; public int Mode = 0; public double Rest = 0, Fall;
    }
    sealed class Ribbon
    {
        public (double X, double Y)[] Pts = []; public double Vx, Vy; public FXColor C; public double Ph, Amp, Fw;
        public int Mode = 0; public double X0 = 0, Curl, Fall;
    }

    readonly FXColor[] C;
    readonly Rng R;
    readonly FXParticles ps;
    readonly FXLights lights = new();
    readonly List<Bit> bits = new();
    readonly List<Ribbon> ribbons = new();
    readonly bool[] fired = [false, false];
    readonly double end = Meta.Duration - 0.05;
    double t = 0.0;

    public FXConfetti(FXOptions o)
    {
        C = FX.Fit(o.Palette, 7);
        R = new Rng(o.Seed);
        ps = new FXParticles(rng: R, ground: _ => 0, sparks: new[] { "#ffffff", "#fff3a6", "#ffc23d", "#ff8a2a" }.Select(FX.Hex).ToArray());
    }

    static double Kick(double t, Popper pp) => t < pp.T ? 0 : 3 * Math.Exp(-(t - pp.T) * 14);

    /// <summary>A party popper: a striped cone pointing along a, kicked back k px when it fires.</summary>
    void DrawPopper(Painter p, double x, double y, double a, double k, double alpha)
    {
        var C = this.C;
        double ca = Math.Cos(a), sa = Math.Sin(a), bx = x - ca * k, by = y - sa * k;
        p.Shade(bx - 12, by - 12, bx + 12, by + 12, (px, py, o) =>
        {
            double dx = px - bx, dy = py - by, u = dx * ca + dy * sa, v = -dx * sa + dy * ca;
            // u along the cone (0 at its tip on the floor, 11 at its mouth), v across
            if (u < 0 || u > 11) return 0;
            var hw = 0.8 + u * 0.32;
            if (Math.Abs(v) > hw + 0.6) return 0;
            o.A = alpha;
            if (Math.Abs(v) > hw - 0.4 || u > 10.2 || u < 0.8) return INK;
            var stripe = FX.Mod(FX.Floor((u + v * 0.6) / 2.2), 2) == 0;
            return stripe ? (v < 0 ? C[2] : FX.Scale(C[2], 0.75)) : v < 0 ? FX.White : BACK;
        });
    }

    void Fire(Popper pp)
    {
        var C = this.C;
        var R = this.R;
        double mx = pp.X + Math.Cos(pp.A) * 11, my = pp.Y + Math.Sin(pp.A) * 11;
        lights.Add(mx, my, 34, FX.White, 0.6, 0.12);
        lights.Add(mx, my, 50, C[2], 0.4, 0.4);
        for (int i = 0; i < 6; i++) ps.Spawn(FXKind.Smoke, mx, my, Math.Cos(pp.A) * R.Range(20, 60) + R.Range(-10, 10), Math.Sin(pp.A) * R.Range(20, 60), R.Range(0.6, 1), SMOKE, R.Range(2.5, 4));
        for (int i = 0; i < 12; i++)
        {
            double an = pp.A + R.Range(-0.5, 0.5), sp = R.Range(120, 260);
            ps.Spawn(FXKind.Spark, mx, my, Math.Cos(an) * sp, Math.Sin(an) * sp, R.Range(0.1, 0.25));
        }
        // paper: thrown hard up the cone, the air soon stalls it
        for (int i = 0; i < 46; i++)
        {
            double an = pp.A + R.Range(-0.38, 0.38), sp = R.Range(200, 380);
            var b = new Bit { X = mx, Y = my, Vx = Math.Cos(an) * sp, Vy = Math.Sin(an) * sp };
            b.C = R.Pick(C); b.W = R.Range(2, 3); b.H = R.Range(3, 4.6); b.Ang = R.Range(0, FX.Tau); b.Spin = R.Range(-14, 14); b.Flip = R.Range(0, FX.Tau);
            b.Fs = R.Range(5, 13); b.Ph = R.Range(0, FX.Tau); b.Amp = R.Range(5, 12); b.Fw = R.Range(2, 3.4); b.Fall = R.Range(26, 40);
            bits.Add(b);
        }
        // streamers: a head that flies like the paper, a tail that follows it and curls
        for (int i = 0; i < 4; i++)
        {
            double an = pp.A + R.Range(-0.25, 0.25), sp = R.Range(220, 330);
            const int n = 11;
            var r = new Ribbon { Pts = Enumerable.Repeat((mx, my), n).ToArray(), Vx = Math.Cos(an) * sp, Vy = Math.Sin(an) * sp };
            r.C = R.Pick(C); r.Ph = R.Range(0, FX.Tau); r.Amp = R.Range(6, 12); r.Fw = R.Range(1.5, 2.4); r.Curl = R.Range(0.7, 1.1); r.Fall = R.Range(22, 32);
            ribbons.Add(r);
        }
    }

    public void Update(double dt)
    {
        var R = this.R;
        t += dt;
        for (int i = 0; i < POPPERS.Length; i++)
            if (!fired[i] && t >= POPPERS[i].T) { fired[i] = true; Fire(POPPERS[i]); }
        foreach (var b in bits)
        {
            if (b.Mode == 2) { b.Rest += dt; continue; }
            b.Flip += b.Fs * dt;
            if (b.Mode == 0)
            {
                // the burst: heavy drag, a little gravity, tumbling fast; once slow it starts to flutter
                b.Vx -= b.Vx * 3.4 * dt;
                b.Vy -= b.Vy * 3.4 * dt - 140 * dt;
                b.X += b.Vx * dt;
                b.Y += b.Vy * dt;
                b.Ang += b.Spin * dt;
                if (FX.Hypot(b.Vx, b.Vy) < 40) { b.Mode = 1; b.X0 = b.X - Math.Sin(b.Ph) * b.Amp; }
            }
            else
            {
                b.Ph += b.Fw * dt;
                b.X0 += b.Vx * dt;
                b.Vx -= b.Vx * 2 * dt;
                b.X = b.X0 + Math.Sin(b.Ph) * b.Amp;
                b.Y += b.Fall * (0.4 + 0.9 * Math.Abs(Math.Cos(b.Ph))) * dt;
                b.Ang = Math.Cos(b.Ph) * 0.9;
                if (b.Y >= -1) { b.Y = -0.5; b.Mode = 2; b.Ang = R.Range(-0.3, 0.3); b.Flip = 0; }
            }
        }
        foreach (var r in ribbons)
        {
            if (r.Mode == 0)
            {
                r.Vx -= r.Vx * 3 * dt;
                r.Vy -= r.Vy * 3 * dt - 120 * dt;
                r.Pts[0].X += r.Vx * dt;
                r.Pts[0].Y += r.Vy * dt;
                if (FX.Hypot(r.Vx, r.Vy) < 35) { r.Mode = 1; r.X0 = r.Pts[0].X - Math.Sin(r.Ph) * r.Amp; }
            }
            else if (r.Pts[0].Y < -1)
            {
                r.Ph += r.Fw * dt;
                r.X0 += r.Vx * dt;
                r.Vx -= r.Vx * 2 * dt;
                r.Pts[0].X = r.X0 + Math.Sin(r.Ph) * r.Amp;
                r.Pts[0].Y += r.Fall * (0.5 + 0.7 * Math.Abs(Math.Cos(r.Ph))) * dt;
            }
            // the tail follows the head link by link and hangs a little
            for (int i = 1; i < r.Pts.Length; i++)
            {
                var a = r.Pts[i - 1];
                var b = r.Pts[i];
                b.Y = Math.Min(-0.5, b.Y + 20 * dt);
                double dx = b.X - a.X, dy = b.Y - a.Y, hd = FX.Hypot(dx, dy), d = hd == 0 ? 1 : hd;
                if (d > 2.6) { b.X = a.X + (dx / d) * 2.6; b.Y = a.Y + (dy / d) * 2.6; }
                r.Pts[i] = b;
            }
        }
        ps.Update(dt);
        lights.Update(dt);
    }

    public void DrawBack(Painter p, double tt) => ps.Draw(p, FXLayer.Back);

    public void Draw(Painter p, double tt)
    {
        var C = this.C;
        var t = this.t;
        var fade = 1 - FX.Seg(t, end - 0.45, end - 0.05);
        foreach (var pp in POPPERS)
        {
            var k = Kick(t, pp);
            DrawPopper(p, pp.X, pp.Y, pp.A, k, 1 - FX.Seg(t, 2.5, 2.9));
            var ft = t - pp.T;
            if (ft > 0 && ft < 0.12) FX.Sparkle(p, pp.X + Math.Cos(pp.A) * 13, pp.Y + Math.Sin(pp.A) * 13, 7 * (1 - ft / 0.12), FX.White, C[2], 0.7);
        }
        // streamers: a two-tone ribbon that curls along its length
        foreach (var r in ribbons)
        {
            var pts = new (double X, double Y)[r.Pts.Length];
            for (int i = 0; i < pts.Length; i++) pts[i] = (r.Pts[i].X + Math.Sin(i * r.Curl + t * 9 + r.Ph) * (i != 0 ? 1.6 : 0), r.Pts[i].Y);
            for (int i = 1; i < pts.Length; i++)
            {
                var (x0, y0) = pts[i - 1];
                var (x1, y1) = pts[i];
                var front = Math.Sin(i * r.Curl + t * 9 + r.Ph) > 0;
                p.Line(x0, y0, x1, y1, front ? r.C : FX.Scale(r.C, 0.6), fade);
                p.Line(x0 + 1, y0, x1 + 1, y1, front ? FX.Mix(r.C, FX.White, 0.35) : FX.Scale(r.C, 0.45), fade);
            }
        }
        // paper bits: a little card turned by its tilt, its width by its flip; the back side shows darker
        foreach (var b in bits)
        {
            if (b.Y > 1) continue;
            double fw = b.Mode == 2 ? 1 : Math.Cos(b.Flip), w = Math.Max(0.5, Math.Abs(fw) * b.W), ca = Math.Cos(b.Ang), sa = Math.Sin(b.Ang);
            var c = fw >= 0 ? b.C : FX.Scale(b.C, 0.62);
            var a = fade;
            if (b.Mode == 2)
            {
                p.Dot(b.X, b.Y, FX.Scale(b.C, 0.8), a);
                p.Dot(b.X + 1, b.Y, FX.Scale(b.C, 0.6), a);
                continue;
            }
            p.Shade(b.X - 4, b.Y - 4, b.X + 4, b.Y + 4, (x, y, o) =>
            {
                double dx = x - b.X, dy = y - b.Y, u = dx * ca + dy * sa, v = -dx * sa + dy * ca;
                if (Math.Abs(u) > w / 2 + 0.2 || Math.Abs(v) > b.H / 2) return 0;
                o.A = a;
                return Math.Abs(fw) > 0.92 && v < -b.H / 2 + 1 ? FX.White : c;
            });
            // it catches the light as it turns face-on
            if (Math.Abs(fw) > 0.97) p.Glow(b.X, b.Y, 5, FX.Mix(b.C, FX.White, 0.5), 0.35 * fade);
        }
        ps.Draw(p, FXLayer.Front);
        lights.Draw(p);
    }
}

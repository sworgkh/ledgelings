// The moment of pickup: a white flash and a cross of light, a thin ring snapping out ahead of a softer one,
// twinkles thrown wide on curving paths that brake, hang and wink out. pixelfx's `pickups/collect-burst` (MIT),
// after Sprite Fusion's open-source pickup (https://www.spritefusion.com/pixel-art-vfx/pickup), MIT,
// Copyright (c) 2026 Hugo Duprez. The Mac's twin is CollectBurst.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXCollectBurst : IFXEffect
{
    public static readonly FXMeta Meta = new("pickups/collect-burst", size: (112, 108), origin: (56, 94), duration: 1.35, loop: false,
                                             palette: ["#1a0516", "#3d0a33", "#701560", "#b0228f", "#f53cd1", "#ff86e6", "#ffd2f6", "#ffffff"], seed: 3);
    const double CY = -30.0;
    sealed class Star(double x, double y, double a, double sp, double turn, double life, double size, FXColor c, double ph)
    {
        public double X = x, Y = y, A = a, Sp = sp, Turn = turn, Life = life, Age, Size = size;
        public readonly List<(double X, double Y)> Tr = new();
        public readonly FXColor C = c;
        public readonly double Ph = ph;
    }
    readonly record struct Mote(double X, double Y, double Vy, double Life, double D, double W);

    readonly FXOptions o;
    readonly FXColor[] C;
    readonly FXLights lights = new();
    readonly List<Star> stars = new();
    readonly List<Mote> motes = new();
    double t;

    public FXCollectBurst(FXOptions o)
    {
        this.o = o;
        var C = FX.Fit(o.Palette, 8);
        var R = new Rng(o.Seed);
        this.C = C;
        lights.Add(0, CY, 36, C[5], 0.85, 0.32);
        lights.Add(0, CY, 14, FX.White, 0.75, 0.08);
        // twinkles thrown out on curving paths: each one's heading turns as it flies, and drag brakes it
        for (int i = 0; i < 14; i++)
        {
            double a = (i / 14.0) * FX.Tau + R.Range(-0.2, 0.2), sp = R.Range(145, 225) * (i % 3 == 0 ? 1.12 : 0.85);
            double turn = (i % 2 != 0 ? 1.0 : -1.0) * R.Range(2.5, 5), life = R.Range(0.75, 1.15), size = i % 3 == 0 ? 2.6 : R.Range(1.2, 2);
            var c = i % 4 == 0 ? FX.White : i % 2 != 0 ? C[6] : C[5];
            stars.Add(new Star(0, CY, a, sp, turn, life, size, c, R.Range(0, FX.Tau)));
        }
        for (int i = 0; i < 7; i++)
        {
            double x = R.Range(-8, 8), y = CY + R.Range(-4, 6), vy = -R.Range(12, 30), life = R.Range(0.5, 0.9), d = R.Range(0.05, 0.25);
            motes.Add(new Mote(x, y, vy, life, d, R.Range(0, FX.Tau)));
        }
    }

    public void Update(double dt)
    {
        t += dt;
        foreach (var s in stars)
        {
            if (s.Age > s.Life) continue;
            s.Age += dt;
            s.Tr.Insert(0, (s.X, s.Y));
            if (s.Tr.Count > 4) s.Tr.RemoveAt(s.Tr.Count - 1);
            s.A += s.Turn * dt * Math.Max(0, 1 - s.Age * 1.5);
            s.Sp -= s.Sp * 4.3 * dt;
            s.X += Math.Cos(s.A) * s.Sp * dt;
            s.Y += Math.Sin(s.A) * s.Sp * dt + 6 * s.Age * dt;
            // the floor turns them back up
            if (s.Y > -2) { s.Y = -2; s.A = -Math.Abs(s.A); s.Sp *= 0.5; }
        }
        lights.Update(dt);
    }

    public void Draw(Painter p, double _t)
    {
        var C = this.C;
        var t = this.t;
        const FXColor W = FX.White;
        // the flash: a white disc and a cross of light, gone in a few frames
        if (t < 0.07) p.Circle(0, CY, 5.5 * (1 - t / 0.07) + 1, W);
        if (t < 0.16)
        {
            double k = 1 - t / 0.16, L = 26 * FX.Ease.OutCubic(Math.Min(1, t / 0.03 + 0.4)) * k;
            foreach (var (dx, dy, l) in (ReadOnlySpan<(double, double, double)>)[(1, 0, 1), (-1, 0, 1), (0, 1, 0.6), (0, -1, 0.6)])
                p.Line(0, CY, dx * L * l, CY + dy * L * l, u => u < 0.3 ? W : u < 0.65 ? C[6] : C[5], u => (u < 0.5 ? 1 : (1 - u) * 2) * (0.5 + k));
            p.Glow(0, CY, 20 * k + 4, C[5], 0.6 * k);
        }
        // a thin ring snapping out fast, a softer ring following
        var u1 = t / 0.32;
        if (u1 < 1)
        {
            var r = 3 + 23 * FX.Ease.OutExpo(u1);
            p.Ring(0, CY, r, 1, u1 < 0.3 ? W : C[6], 1.3 - u1 * 1.2);
            p.GlowRing(0, CY, r, 4, C[5], 0.4 * (1 - u1));
        }
        var u2 = (t - 0.04) / 0.5;
        if (u2 > 0 && u2 < 1)
        {
            var r = 2 + 16 * FX.Ease.OutCubic(u2);
            p.Ring(0, CY, r, Math.Max(1, 2.6 * (1 - u2)), C[5], 1 - u2);
        }
        // the twinkles, with short trails, flickering as they hang and wink out
        foreach (var s in stars)
        {
            if (s.Age > s.Life) continue;
            double k = 1 - s.Age / s.Life, tw = 0.65 + 0.35 * Math.Sin(s.Age * 26 + s.Ph);
            for (int i = 1; i < s.Tr.Count; i++) p.Dot(s.Tr[i].X, s.Tr[i].Y, i < 2 ? C[5] : C[4], (1 - i / 4.0) * k * 1.4);
            if (k < 0.3 && Math.Sin(s.Age * 40 + s.Ph) < 0) continue;
            FXPickups.Glint(p, s.X, s.Y, FX.Round(s.Size * tw * Math.Min(1, k * 2.5)), s.C, 0.45 * k);
        }
        // motes drifting up after
        foreach (var m in motes)
        {
            var a = t - m.D;
            if (a < 0 || a > m.Life) continue;
            double k = 1 - a / m.Life, x = m.X + Math.Sin(a * 6 + m.W) * 1.5, y = m.Y + m.Vy * a;
            p.Dot(x, y, k > 0.5 ? C[6] : C[5], k * 1.5);
            p.Glow(x + 0.5, y + 0.5, 3, C[5], 0.3 * k);
        }
        lights.Draw(p);
    }
}

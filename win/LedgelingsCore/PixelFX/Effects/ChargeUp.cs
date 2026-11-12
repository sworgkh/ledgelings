// Sparks streak and arcs whip in to a crackling core at the caster's hand that swells and pulses faster, then
// it flashes and bursts: bolts every way, a ring, a spray of sparks. pixelfx's `lightning/charge-up` (MIT),
// after Sprite Fusion's open-source energy charge (https://www.spritefusion.com/pixel-art-vfx/energy), MIT,
// Copyright (c) 2026 Hugo Duprez. The Mac's twin is ChargeUp.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXChargeUp : IFXEffect
{
    public static readonly FXMeta Meta = new("lightning/charge-up", size: (272, 184), origin: (124, 148), duration: 2.7, loop: false, palette: FXLightning.Volt, seed: 4);
    const double CX = 15.0, CY = -21.0, Charge = 1.6;
    static readonly double[] BK = [1, 0.7, 0.95, 0.5, 0.8, 0.35];
    static readonly FXColor Ash = FX.Hex("#5b5566");
    static readonly FXMemo<List<(int X, int Y)>> Edges = new();
    readonly record struct Bolt(double X1, double Y1, double T0);
    readonly record struct Arc(double X, double Y, double T, double Seed);

    readonly FXOptions o;
    readonly FXColor[] C;
    readonly Rng R;
    readonly FXParticles ps;
    readonly FXLights lights = new();
    readonly List<Bolt> bolts = new();
    readonly List<Arc> arcs = new();
    double t, phase;
    bool released;
    List<double> beats = new();

    public FXChargeUp(FXOptions o)
    {
        this.o = o;
        C = FX.Fit(o.Palette, 8);
        R = new Rng(o.Seed);
        ps = new FXParticles(rng: R, ground: _ => 0, sparks: FX.Ramp(FXLightning.Plasma));
        for (int i = 0; i < 8; i++)
        {
            double a = (i / 8.0) * FX.Tau + R.Range(-0.25, 0.25), L = R.Range(44, 72), x1 = CX + Math.Cos(a) * L, y1 = Math.Min(0, CY + Math.Sin(a) * L);
            bolts.Add(new Bolt(x1, y1, Charge + R.Range(0, 0.05)));
        }
    }

    static List<(int X, int Y)> EdgeOf(FXActor A) => Edges.Get(A.Key, () =>
    {
        var m = A.Mask;
        bool On(int x, int y) => x >= 0 && y >= 0 && x < m.W && y < m.H && m.Data[y * m.W + x] != 0;
        var e = new List<(int X, int Y)>();
        for (int y = 0; y < m.H; y++)
            for (int x = 0; x < m.W; x++)
                if (On(x, y) && (!On(x - 1, y) || !On(x + 1, y) || !On(x, y - 1) || !On(x, y + 1))) e.Add((A.X + x, A.Y + y));
        return e;
    });

    double Level => FX.Clamp(t / Charge);

    public void Update(double dt)
    {
        var C = this.C;
        var R = this.R;
        t += dt;
        double k = Level, e = k * k;
        if (t < Charge)
        {
            // energy rushes in: long streaks spiralling in from all round, more and more of them
            for (var acc = (60 + 360 * e) * dt; acc > 0; acc--)
            {
                if (acc < 1 && !R.Chance(acc)) break;
                double a = R.Range(0, FX.Tau), d = R.Range(30, 72) * (1 - 0.35 * k), life = R.Range(0.16, 0.26), sp = (d / life) * 0.95;
                ps.Spawn(FXKind.Mote, CX + Math.Cos(a) * d, Math.Min(-2, CY + Math.Sin(a) * d), -Math.Cos(a) * sp - Math.Sin(a) * sp * 0.4,
                         -Math.Sin(a) * sp + Math.Cos(a) * sp * 0.4, life, R.Pick([C[7], C[6], C[5]]), 1);
            }
            // arcs whip in from the air, more and more of them
            if (k > 0.2 && R.Chance((2 + 16 * e) * dt))
            {
                double a = R.Range(0, FX.Tau), d = R.Range(20, 40);
                arcs.Add(new Arc(CX + Math.Cos(a) * d, Math.Min(-3, CY + Math.Sin(a) * d), t, R.Int(0, 1e6)));
            }
            // the pulse quickens
            phase += (1.5 + 11 * e) * dt;
            if (phase >= 1) { phase -= 1; beats.Add(t); }
            if (R.Chance(4 * e * dt)) ps.Spawn(FXKind.Star, CX + R.Range(-14, 14), CY + R.Range(-14, 10), 0, -4, R.Range(0.2, 0.35), C[6], R.Range(1, 2));
        }
        else if (!released)
        {
            released = true;
            lights.Add(CX, CY, 110, C[4], 0.8, 0.5);
            lights.Add(CX, CY, 28, FX.White, 0.6, 0.08);
            for (int i = 0; i < 70; i++)
            {
                double a = R.Range(0, FX.Tau), sp = R.Range(140, 330) * (Math.Sin(a) > 0.4 ? 0.55 : 1);
                ps.Spawn(Math.Sin(a) < -0.2 && R.Chance(0.35) ? FXKind.Mote : FXKind.Spark, CX, CY, Math.Cos(a) * sp, Math.Sin(a) * sp,
                         R.Range(0.25, 0.55), R.Pick([C[7], C[6], C[5]]), R.Range(0.8, 1.4));
            }
            for (int i = 0; i < 10; i++)
            {
                double a = R.Range(0, FX.Tau), sp = R.Range(60, 160);
                ps.Spawn(FXKind.Star, CX, CY, Math.Cos(a) * sp, Math.Sin(a) * sp, R.Range(0.4, 0.8), R.Chance(0.5) ? C[6] : C[5], R.Range(1.2, 2.4));
            }
            for (int i = 0; i < 4; i++)
                ps.Spawn(FXKind.Smoke, CX + R.Range(-5, 5), CY + R.Range(-4, 4), R.Range(-12, 12), -R.Range(8, 18), R.Range(0.6, 0.85),
                         FX.Mix(Ash, C[4], 0.3), R.Range(3, 5), R.Range(0.05, 0.15));
        }
        beats = beats.Where(b => t - b < 0.22).ToList();
        for (int i = arcs.Count - 1; i >= 0; i--) if (t - arcs[i].T > 0.07) arcs.RemoveAt(i);
        ps.Update(dt);
        lights.Update(dt);
    }

    public void DrawBack(Painter p, double _t)
    {
        var k = Level;
        if (t < Charge) p.Glow(CX * 0.5, -3, 40, C[3], 0.3 * k * k);
        ps.Draw(p, FXLayer.Back);
    }

    public void Draw(Painter p, double _t)
    {
        var C = this.C;
        var seed = o.Seed;
        var t = this.t;
        double k = Level, e = k * k;
        var f = (int)FX.Floor(t * 30 + 1e-4);
        var A = o.Actor;
        if (t < Charge)
        {
            double jit = k > 0.85 ? (f % 2 != 0 ? 1.0 : -1.0) * ((k - 0.85) / 0.15) : 0, x = CX + jit, y = CY, pr = 0.5 + 0.5 * Math.Sin(phase * FX.Tau);
            // the body catches the core's light along its near edge
            foreach (var (ex, ey) in EdgeOf(A))
            {
                var d = FX.Hypot(ex + 0.5 - x, ey + 0.5 - y);
                if (d < 6 + 10 * k && e > 0.08) p.Px(ex, ey, d < 4 + 6 * k && e > 0.4 ? C[6] : C[4]);
            }
            // rings fall inward to the core on every beat
            foreach (var b in beats)
            {
                var q = (t - b) / 0.22;
                p.Ring(x, y, 4 + 20 * (1 - FX.Ease.InQuad(q)) * (0.5 + k), 1, q > 0.6 ? C[6] : C[4], 0.4 + 0.6 * q);
            }
            // arcs whipping in to the core
            foreach (var a in arcs) FXLightning.Crackle(p, FXLightning.Zigzag(FX.Rng(a.Seed, f), a.X, a.Y, x, y, 0.35, 0.4), 0.85, C, 0.4);
            // the core: swelling, layered, with arcs racing round its skin
            var r = 1.2 + 6.5 * e + pr * (0.5 + 1.2 * k);
            p.Circle(x, y, r + 1.3, C[2]);
            p.Circle(x, y, r, C[4]);
            p.Circle(x - r * 0.12, y - r * 0.12, r * 0.7, C[5]);
            p.Circle(x, y, r * 0.38, FX.White);
            if (r > 3)
                foreach (var s in (ReadOnlySpan<double>)[0, Math.PI])
                    for (var a = 0.0; a < 1.3; a += 0.12)
                    {
                        double ang = t * 10 + s + a, rr = r * (0.62 + 0.1 * Math.Sin(a * 3));
                        p.Dot(x + Math.Cos(ang) * rr, y + Math.Sin(ang) * rr, a < 0.5 ? FX.White : C[6]);
                    }
            if (k > 0.35)
            {
                var q = FX.Rng(seed, 5, f);
                double a = q.Range(0, FX.Tau), l = q.Range(3, 6) * (0.5 + k);
                FXLightning.Crackle(p, FXLightning.Zigzag(q, x + Math.Cos(a) * r, y + Math.Sin(a) * r, x + Math.Cos(a) * (r + l), y + Math.Sin(a) * (r + l), 0.4, 0.3), 0.7, C, 0.3);
            }
            p.Glow(x, y, 12 + 30 * k, C[4], 0.35 + 0.45 * k);
            p.Glow(x, y, 6 + 6 * k, C[6], 0.25 + 0.3 * k);
        }
        else
        {
            var a = t - Charge;
            // the release: the caster flashed white, a flare, a white core blown open
            if (a < 0.07) { var c = a < 0.035 ? FX.White : C[6]; p.Mask(A.Mask, A.X, A.Y, (_, _) => c); }
            if (a < 0.22)
            {
                var q = a / 0.22;
                FX.Flare(p, CX, CY, 46 * Math.Pow(1 - q, 1.4), 1 - q, C);
                if (q < 0.3) p.Circle(CX, CY, 12 * (1 - q * 2.5) + 1.5, FX.White);
            }
            // bolts every way, struck and flickering
            for (int i = 0; i < bolts.Count; i++)
            {
                var b = bolts[i];
                var ba = (int)FX.Floor((t - b.T0) * 30 + 1e-4);
                if (t < b.T0 || ba >= BK.Length) continue;
                FXLightning.Stroke(p, FXLightning.Zigzag(FX.Rng(seed, 3, i, ba >> 1), CX, CY, b.X1, b.Y1, 0.25, 0.75), BK[ba], C,
                                   ba == 0 ? 0.95 : 0.75, hero: ba == 0);
                if (b.Y1 > -1) p.Glow(b.X1, -3, 18, C[5], 0.5 * BK[ba]);
            }
            // a ring bursting out with a fainter echo inside it
            var qq = a / 0.45;
            if (qq < 1)
            {
                var r = 8 + 80 * FX.Ease.OutCubic(qq);
                var rc = qq < 0.25 ? FX.White : C[5];
                p.Ring(CX, CY, r, Math.Max(1, 3 * (1 - qq)), (_, _) => rc, (_, g) => CY + Math.Sin(g) * r > -1 ? 0 : 1.1 - qq);
                var r2 = 6 + 56 * FX.Ease.OutCubic(Math.Min(1, qq * 1.3));
                var c4 = C[4];
                p.Ring(CX, CY, r2, 1, (_, _) => c4, (_, g) => CY + Math.Sin(g) * r2 > -1 ? 0 : 0.8 - qq);
                p.Glow(CX, CY - 6, Math.Min(r * 0.9, 46), C[3], 0.42 * (1 - qq) * (1 - qq));
            }
            // the charge bleeds off in a few last crackles at the hand
            if (a > 0.15 && a < 0.5)
            {
                var g = FX.Rng(seed, 8, f);
                double ang = g.Range(0, FX.Tau), l = g.Range(5, 10);
                FXLightning.Crackle(p, FXLightning.Zigzag(g, CX, CY, CX + Math.Cos(ang) * l, CY + Math.Sin(ang) * l, 0.45, 0.3), 0.8 * (1 - (a - 0.15) / 0.35) + 0.15, C, 0.3);
            }
        }
        ps.Draw(p, FXLayer.Front);
        lights.Draw(p);
    }
}

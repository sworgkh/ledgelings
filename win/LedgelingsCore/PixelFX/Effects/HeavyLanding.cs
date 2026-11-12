// Heavy landing: the floor dents and cracks under the feet, two rings of dust roll out along the floor one after
// the other, and pebbles hop away. pixelfx's `impacts/heavy-landing` (MIT); the rocks, grit and dust adapt
// Sprite Fusion's open-source explosion (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT,
// Copyright (c) 2026 Hugo Duprez. The Mac's twin is HeavyLanding.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXHeavyLanding : IFXEffect
{
    public static readonly FXMeta Meta = new("impacts/heavy-landing", size: (176, 80), origin: (88, 60), duration: 1.6, loop: false,
                                             palette: ["#1c1a24", "#2f2a3a", "#4a4258", "#6b6280", "#9088a4", "#bdb6cc", "#e6e1ee"], seed: 14);
    static readonly FXColor StoneColor = FX.Hex("#4a3f69");

    /// <summary>A pebble: tumbles, bounces and settles like pixelfx's Bits, and keeps its outline and last speed.</summary>
    sealed class Pebble(double x, double y, double vx, double vy, double a, double va, double s, double life, double[] pts)
    {
        public double X = x, Y = y, Vx = vx, Vy = vy, A = a, Va = va, S = s, Life = life;
        public readonly double G = 1.0, Drag = 0.5, Bounce = 0.55;
        public readonly double[] Pts = pts;
        public bool Rest;
        public double Pvy;
    }

    readonly FXColor[] C;
    readonly FXImpacts.Stone st;
    readonly Rng R;
    readonly FXParticles back, front;
    readonly List<Pebble> bits = new();
    readonly List<FXImpacts.Crack> cracks;
    readonly FXColor DUST, LIT;
    readonly double PH;
    double t;

    public FXHeavyLanding(FXOptions o)
    {
        C = FX.Fit(o.Palette, 7); st = FXImpacts.StoneOf(StoneColor); R = new Rng(o.Seed);
        var R_ = R;
        back = new FXParticles(rng: R_, ground: _ => 0); front = new FXParticles(rng: R_, ground: _ => 0);
        cracks = FXImpacts.MakeCracks(R_, 6, len: (8, 20), dive: 0.7, maxY: 12, forks: 0.4, x0: (2, 6));
        DUST = FX.Mix(st.Dust, C[5], 0.4); LIT = FX.Mix(DUST, FX.White, 0.3); PH = R_.Range(0, FX.Tau);
        FXColor dust = DUST, lit = LIT;
        var bk = back;
        var fr = front;
        // puffs riding each ring out along the floor
        void Ring(int n, double v0, double v1, (double A, double B) size, double delay)
        {
            for (int i = 0; i < n; i++)
            {
                double g = ((double)i / n) * FX.Tau + R_.Range(-0.1, 0.1), v = R_.Range(v0, v1);
                var far = Math.Sin(g) < 0;
                double vy = Math.Sin(g) * v * 0.16 - R_.Range(2, 10), life = R_.Range(0.45, 0.8);
                var c = R_.Chance(0.45) ? lit : dust;
                double sz = R_.Range(size.A, size.B), dl = delay + R_.Range(0, 0.03);
                (far ? bk : fr).Spawn(FXKind.Dust, Math.Cos(g) * 4, Math.Sin(g) * 0.7 - 1, Math.Cos(g) * v, vy, life, c, sz, dl);
            }
        }
        Ring(20, 140, 190, (2.2, 3.4), 0.01);
        Ring(18, 70, 110, (3.4, 5.4), 0.12);
        // and a low cloud at the feet that rises a little and hangs
        for (int i = 0; i < 12; i++)
        {
            var s = R_.Sign();
            var up = i < 6;
            double x = s * R_.Range(2, 10), y = -R_.Range(1, 4), vx = s * R_.Range(10, 35) * (up ? 0.6 : 1), vy = -(up ? R_.Range(25, 60) : R_.Range(4, 12));
            var life = R_.Range(0.55, 0.9);
            var c = R_.Chance(0.5) ? LIT : DUST;
            double sz = R_.Range(3, 5), dl = R_.Range(0.02, 0.1);
            (i % 2 != 0 ? front : back).Spawn(FXKind.Dust, x, y, vx, vy, life, c, sz, dl);
        }
        // pebbles that hop away along the floor, and grit
        for (int i = 0; i < 12; i++)
        {
            double s = R_.Sign(), v = R_.Range(50, 130);
            double x = s * R_.Range(3, 8), vy = -R_.Range(140, 230), life = R_.Range(1, 1.45), a = R_.Range(0, FX.Tau), va = s * R_.Range(8, 16);
            double sz = R_.Chance(0.3) ? 2 : 1;
            var pts = FXImpacts.RockShape(R_);
            bits.Add(new Pebble(x, -1, s * v, vy, a, va, sz, life, pts));
        }
        for (int i = 0; i < 24; i++)
        {
            double s = R_.Sign(), a = -Math.PI / 2 + s * R_.Range(0.3, 1.2), v = R_.Range(60, 170);
            double x = s * R_.Range(2, 7), life = R_.Range(0.6, 1.1);
            var c = R_.Pick([st.Light, st.Body, st.Lip]);
            double sz = R_.Chance(0.3) ? 2 : 1;
            front.Spawn(FXKind.Grit, x, -1, Math.Cos(a) * v, Math.Sin(a) * v, life, c, sz);
        }
    }

    void StepBits(double dt)
    {
        for (int i = bits.Count - 1; i >= 0; i--)
        {
            var b = bits[i];
            b.Life -= dt;
            if (b.Life <= 0) { bits.RemoveAt(i); continue; }
            if (b.Rest) continue;
            b.Vy += FX.Gravity * b.G * dt;
            b.Vx -= b.Vx * b.Drag * dt;
            b.Vy -= b.Vy * b.Drag * dt;
            b.X += b.Vx * dt;
            b.Y += b.Vy * dt;
            b.A += b.Va * dt;
            double floor = 0.0, sp = b.Vy;
            if (b.G <= 0 || b.Y < floor || sp <= 0) continue;
            b.Y = floor - 0.01;
            if (b.Bounce > 0 && sp > 70) { b.Vy = -sp * b.Bounce; b.Vx *= 0.7; b.Va *= 0.6; }
            else { b.Rest = true; b.Vx = 0; b.Vy = 0; }
        }
    }

    public void Update(double dt)
    {
        t += dt;
        foreach (var b in bits) b.Pvy = b.Vy;
        StepBits(dt);
        foreach (var b in bits)
        {
            if (!(b.Pvy > 80 && b.Vy <= 0)) continue;
            double vx = R.Sign() * R.Range(6, 20), vy = -R.Range(2, 10), life = R.Range(0.25, 0.45), sz = R.Range(1, 1.8);
            front.Spawn(FXKind.Dust, b.X, -0.5, vx, vy, life, DUST, sz);
            b.Pvy = 0;
        }
        back.Update(dt);
        front.Update(dt);
    }

    /// <summary>The dent: the floor's edge pressed into a shallow dish, scuffed lips either side.</summary>
    void Dent(Painter p, double k)
    {
        for (int xi = -10; xi <= 9; xi++)
        {
            double x = xi, q = Math.Abs(x + 0.5) / 10, dep = FX.Round(1.8 * (1 - q * q));
            if (q < 0.82)
            {
                for (var y = 0.0; y < dep; y += 1) p.Dot(x, y, FXImpacts.SOOT, k);
                p.Dot(x, dep, st.Lip, k);
            }
            else p.Dot(x, -1, q > 0.92 ? st.Light : st.Lip, k);
        }
    }

    /// <summary>The two dust rings themselves: soft bands on the floor, the second slower, lumpier and later.</summary>
    void Rings(Painter p, bool far)
    {
        foreach (var (t0, dur, r1, w, k0, edge) in (ReadOnlySpan<(double, double, double, double, double, bool)>)[(0.01, 0.45, 58.0, 4.5, 0.75, true), (0.12, 0.85, 42.0, 6.0, 0.8, false)])
        {
            var g = (t - t0) / dur;
            if (g <= 0 || g >= 1) continue;
            var r = 6 + r1 * FX.Ease.OutCubic(g);
            FXImpacts.DustRing(p, 0, 0, r, w * (1 + g), k0 * Math.Pow(1 - g, 1.2) * Math.Min(1, g / 0.06), DUST,
                               sy: 0.2, ph: PH + t0 * 10, brk: g * 0.8, half: far ? -1 : 1);
            // the fast ring's leading edge: a crisp lit band on the floor
            if (edge && g < 0.75)
                FX.Band(p, 0, 0.5, r + 2, 0.2, Math.Max(1, 2.5 * (1 - g)), 1.1 - g / 0.75, [st.Body, st.Light, LIT, FX.White], a => (Math.Sin(a) < 0) == far);
        }
    }

    public void DrawBack(Painter p, double tt)
    {
        var D = Meta.Duration;
        var fade = 1 - FX.Smooth(D - 0.5, D - 0.1, t);
        var t_ = t;
        var W = FX.White;
        Dent(p, fade);
        FXImpacts.DrawCracks(p, cracks, c => c.Len * FX.Ease.OutCubic(FX.Clamp((t_ - c.T0) / 0.08)), _ => 0, [W, W, W, W], FXImpacts.SOOT, st.Light, fade);
        Rings(p, true);
        back.Draw(p, null);
    }

    public void Draw(Painter p, double tt)
    {
        var C = this.C;
        Rings(p, false);
        front.Draw(p, null);
        foreach (var b in bits) FXImpacts.Rock(p, b.X, b.Y, b.A, b.S, b.Life, b.Pts, st);
        // the thud: a flat streak of light along the floor for a frame or two
        if (t < 0.035) p.Ellipse(0, 0, 15, 2.5, (d, _) => d < 0.55 ? FX.White : C[6], (_, _) => 1);
        else if (t < 0.07)
            for (int xi = -22; xi <= 22; xi++) { double x = xi; p.Dot(x, 0, Math.Abs(x) < 10 ? FX.White : C[5], 1 - Math.Abs(x) / 24); }
        if (t < 0.12) p.GlowLine(-20, 0, 20, 0, 8, C[6], 0.45 * (1 - t / 0.12));
    }
}

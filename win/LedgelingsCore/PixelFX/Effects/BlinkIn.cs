// Blink in: glittering bits spiral in to a point of light that opens into a line, then into a white silhouette
// that cools into the caster. pixelfx's `arcane/blink-in` (MIT), adapted from Sprite Fusion's open-source blink
// (https://www.spritefusion.com/pixel-art-vfx/movement), MIT, Copyright (c) 2026 Hugo Duprez.
// The Mac's twin is BlinkIn.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXBlinkIn : IFXEffect
{
    public static readonly FXMeta Meta = new("arcane/blink-in", size: (136, 96), origin: (68, 80), duration: 1.4, loop: false,
                                             palette: ["#140a26", "#2b1252", "#481c88", "#6b2cc0", "#9a48ec", "#c684ff", "#ecc8ff", "#ffffff"], seed: 12);
    const double LINE = 0.26, GROW = 0.1, OPEN = 0.12, ARRIVE = LINE + GROW + OPEN;

    readonly record struct Bit(double Tx, double Ty, double Ox, double Oy, double T0, double T1, double Spin, FXColor C);

    readonly FXColor[] C;
    readonly Rng R;
    readonly FXActor A;
    readonly byte[] sh;
    readonly FXParticles ps;
    readonly FXLights lights = new();
    readonly double mx, my;
    readonly FXColor[] COLS;
    readonly List<Bit> bits = new();
    double t;
    bool arrived;

    public FXBlinkIn(FXOptions o)
    {
        C = FX.Fit(o.Palette, 8); R = new Rng(o.Seed); A = o.Actor; sh = FXArcane.Shades(A);
        ps = new FXParticles(rng: R, ground: _ => 0, sparks: [FX.White, C[6], C[5], C[4]]);
        mx = A.X + A.W / 2.0; my = A.Y + A.H * 0.55;
        COLS = [FX.White, C[6], C[6], C[5], C[4]];
        double ay = A.Y, ah = A.H;
        for (int n = 0; n < 230; n++)
        {
            double a = R.Range(0, FX.Tau), d = R.Range(16, 46), ty = ay + R.Range(3, ah - 2);
            var oy = Math.Sin(a) * d * 0.8 - 6;
            if (ty + oy > -2) oy = -Math.Abs(oy) - 2;
            double tx = mx + R.Range(-1, 1), t0 = R.Range(0, 0.1), t1 = LINE + R.Range(-0.02, GROW);
            var spin = R.Range(0.8, 1.8) * R.Sign();
            var c = R.Pick(COLS);
            bits.Add(new Bit(tx, ty, Math.Cos(a) * d, oy, t0, t1, spin, c));
        }
    }

    bool Inside(int x, int y) => x >= 0 && y >= 0 && x < A.W && y < A.H && A.Mask.Data[y * A.W + x] != 0;

    (double X, double Y, double K) At(Bit b, double tt)
    {
        double k = FX.Clamp((tt - b.T0) / (b.T1 - b.T0)), e = FX.Ease.OutCubic(k), r = 1 - e, sp = b.Spin * r * 1.2;
        double ox = b.Ox * Math.Cos(sp) - b.Oy * Math.Sin(sp), oy = b.Ox * Math.Sin(sp) + b.Oy * Math.Cos(sp);
        return (b.Tx + ox * r, Math.Min(-1, b.Ty + oy * r), k);
    }

    public double ActorAlpha(double t) => t < ARRIVE ? 0 : 1;

    public void Update(double dt)
    {
        t += dt;
        var C = this.C;
        var R = this.R;
        if (t < LINE && R.Chance(0.6))
        {
            double a = R.Range(0, FX.Tau), D = R.Range(22, 44), T = R.Range(0.12, 0.18), v = (D * 3) / (Math.Exp(3 * T) - 1);
            double x = mx + Math.Cos(a) * D, y = Math.Min(-2, my + Math.Sin(a) * D), h = FX.Hypot(x - mx, y - my), l = h == 0 ? 1 : h;
            ps.Spawn(FXKind.Streak, x, y, ((mx - x) / l) * v, ((my - y) / l) * v, T, R.Chance(0.5) ? C[6] : C[5]);
        }
        if (!arrived && t >= ARRIVE)
        {
            arrived = true;
            lights.Add(mx, my - 6, 56, C[5], 0.9, 0.35);
            lights.Add(mx, my, 24, FX.White, 0.8, 0.1);
            for (int i = 0; i < 30; i++)
            {
                double a = R.Range(0, FX.Tau), sp = R.Range(35, 110);
                var k = R.Chance(0.6) ? FXKind.Star : FXKind.Mote;
                var life = R.Range(0.4, 0.85);
                var c = R.Pick(COLS);
                var s = R.Range(0.6, 1.6);
                ps.Spawn(k, mx, my, Math.Cos(a) * sp, Math.Sin(a) * sp * 0.7 - 30, life, c, s);
            }
            for (int i = 0; i < 12; i++)
            {
                var s = R.Sign();
                double x = mx + s * R.Range(2, 8), vx = s * R.Range(60, 180), vy = -R.Range(20, 110), life = R.Range(0.2, 0.45);
                ps.Spawn(FXKind.Spark, x, -1, vx, vy, life);
            }
        }
        ps.Update(dt);
        lights.Update(dt);
    }

    void Ring(Painter p, bool far)
    {
        var C = this.C;
        var k = (t - ARRIVE + 0.03) / 0.5;
        if (k >= 0 && k < 1)
            FX.Band(p, 0, 0, 4 + 30 * FX.Ease.OutCubic(k), 0.2, Math.Max(1, 3 * (1 - k)), 1.15 - k, [C[3], C[5], C[6], FX.White],
                    far ? g => Math.Sin(g) < 0 : g => Math.Sin(g) >= 0, k < 0.25);
    }

    public void DrawBack(Painter p, double tt)
    {
        Ring(p, true);
        p.Glow(0, -1, 26, C[5], 0.3 * (t < ARRIVE ? t / ARRIVE : 1 - FX.Clamp((t - ARRIVE) / 0.5)));
    }

    public void Draw(Painter p, double tt)
    {
        var C = this.C;
        var A = this.A;
        double mx = this.mx, my = this.my;
        foreach (var b in bits)
        {
            if (t < b.T0 || t > b.T1 + 0.02) continue;
            var (x, y, k) = At(b, t);
            p.Dot(x, y, k > 0.75 ? FX.White : b.C, Math.Min(1, 0.35 + k * 2));
            if (k > 0.55)
            {
                var (px, py, _) = At(b, t - 0.015);
                p.Dot((x + px) / 2, (y + py) / 2, C[5], 0.8);
            }
            if (k > 0.8) p.Glow(x, y, 3, C[6], 0.3);
        }
        if (t >= LINE - 0.04 && t < LINE)
        {
            var q = (t - LINE + 0.04) / 0.04;
            FX.Sparkle(p, mx, my, 2 + 3 * q, C[6], C[5], 0.6);
        }
        else if (t >= LINE && t < LINE + GROW)
        {
            double q = FX.Ease.OutCubic((t - LINE) / GROW), hh = (A.H / 2.0 + 3) * q;
            for (var y = -hh - 2; y <= hh + 2; y += 1) p.Dot(mx, my + y, Math.Abs(y) < hh ? FX.White : C[6], Math.Abs(y) < hh ? 1 : 0.7);
            for (var y = -hh * 0.7; y <= hh * 0.7; y += 1) { p.Dot(mx - 1, my + y, C[5], 0.6); p.Dot(mx + 1, my + y, C[5], 0.6); }
            p.Glow(mx, my, 30, C[5], 0.9);
            p.Glow(mx, my, 8, FX.White, 0.5);
        }
        else if (t >= LINE + GROW && t < ARRIVE)
        {
            var q = FX.Ease.OutCubic((t - LINE - GROW) / OPEN);
            FXArcane.Squeezed(p, A, sh, q, FX.White, C[6]);
            p.Glow(mx, my, 36, C[5], 0.8);
        }
        else if (t >= ARRIVE && t < ARRIVE + 0.42)
        {
            double k = 1 - (t - ARRIVE) / 0.42, f = FX.Floor(t * 30);
            if (k > 0.86) FXArcane.Squeezed(p, A, sh, 1, FX.White, C[6]);
            double ax = A.X, ay = A.Y;
            for (int y = 0; y < A.H; y++)
                for (int x = 0; x < A.W; x++)
                {
                    if (Inside(x, y)) p.Light(ax + x, ay + y, C[6], k * k * (sh[y * A.W + x] == 1 ? 0.3 : 0.8));
                    else if ((Inside(x - 1, y) || Inside(x + 1, y) || Inside(x, y - 1) || Inside(x, y + 1)) && FX.Rand(x, y, f) < 0.85 * k)
                        p.Px(ax + x, ay + y, k > 0.5 && FX.Rand(x, y, 7) < 0.5 ? FX.White : C[6]);
                }
            p.Glow(mx, my, 34, C[5], 0.6 * k);
        }
        if (t >= ARRIVE && t < ARRIVE + 0.2)
        {
            var q = (t - ARRIVE) / 0.2;
            FX.Flare(p, mx, my - 4, 18 * Math.Pow(1 - q, 1.5) + 2, 1 - q, C);
        }
        Ring(p, false);
        ps.Draw(p, null);
        lights.Draw(p);
    }
}

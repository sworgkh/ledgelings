// Magic circle cast: a circle draws itself on the floor, runes ignite one by one, it flashes, and a column of
// light fires up and breaks apart into glints. pixelfx's `arcane/magic-circle-cast` (MIT); the column is adapted
// from Sprite Fusion's open-source holy light (https://www.spritefusion.com/pixel-art-vfx/holy-light), MIT,
// Copyright (c) 2026 Hugo Duprez. The Mac's twin is MagicCircle.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXMagicCircle : IFXEffect
{
    public static readonly FXMeta Meta = new("arcane/magic-circle-cast", size: (200, 220), origin: (100, 192), duration: 3.9, loop: false,
                                             palette: ["#140a26", "#2b1252", "#481c88", "#6b2cc0", "#9a48ec", "#c684ff", "#ecc8ff", "#ffffff"], seed: 6);
    // the circle on the floor (plane px; the floor squashes depth by SY), the column, the beats
    const double R = 40.0, R2 = 35.0, RI = 24.0, RR = 30.0, SY = 0.3, TOP = 192.0, W = 11.0;
    const int NRUNE = 8;
    static readonly (double A, double B) PEN = (0.04, 0.42), PEN2 = (0.1, 0.48), INNER = (0.3, 0.6), STAR = (0.52, 0.88), RUNES = (0.9, 1.3);
    const double FLASH = 1.52, BREAK = 2.42, GONE = 3.45, END = 3.9;

    static double Wrap(double a) => FX.Mod(FX.Mod(a, FX.Tau) + FX.Tau, FX.Tau);
    static double FromFront(double g) => Math.Abs(Math.Atan2(Math.Sin(g - Math.PI / 2), Math.Cos(g - Math.PI / 2)));
    static double OuterAt(double g, (double A, double B) w) => w.A + (FromFront(g) / Math.PI) * (w.B - w.A);
    static double InnerAt(double g) => INNER.A + (Wrap(g + Math.PI / 2) / FX.Tau) * (INNER.B - INNER.A);
    static double RuneAngle(int k) => -Math.PI / 2 + ((k + 0.5) * FX.Tau) / NRUNE;
    static double RuneLit(int k) => RUNES.A + (k * (RUNES.B - RUNES.A)) / (NRUNE - 1);
    static double RuneOut(int k) => BREAK + 0.2 + k * 0.08;

    /// <summary>How bright the drawn circle burns: settled while it's drawn, swelling as the runes light, white at the flash.</summary>
    static double Level(double t)
    {
        if (t < RUNES.A) return 0.55;
        if (t < FLASH) return 0.55 + 0.4 * FX.Smooth(RUNES.A, FLASH, t);
        if (t < FLASH + 0.07) return 1.2;
        if (t < BREAK) return 0.92;
        return 0.92 * (1 - FX.Smooth(BREAK, GONE, t));
    }

    readonly record struct Strand(double O, double W, double F);
    readonly record struct Edge((double X, double Y) P0, (double X, double Y) P1, double T0, double Dur);

    readonly FXColor[] C;
    readonly double S;
    readonly Rng Rg;
    readonly FXParticles ps;
    readonly FXLights lights = new();
    readonly FXColor[] COL;
    readonly List<Strand> strands = new();
    readonly List<Edge> edges = new();
    double t;
    bool flashed, broke;
    readonly bool[] @out = new bool[NRUNE];

    public FXMagicCircle(FXOptions o)
    {
        C = FX.Fit(o.Palette, 8); S = o.Seed; Rg = new Rng(S);
        ps = new FXParticles(rng: Rg, ground: _ => 0, sparks: [FX.White, C[6], C[5], C[4]]);
        COL = [FX.White, C[6], C[5], C[4], C[3]];
        for (int i = 0; i < 9; i++)
        {
            double so = Rg.Range(-0.85, 0.85), sw = Rg.Range(0.04, 0.1), sf = Rg.Range(1, 3);
            strands.Add(new Strand(so, sw, sf));
        }
        // the hexagram: two triangles inside the inner ring, each drawn edge by edge
        static (double X, double Y)[] Tri(double a0)
        {
            var pts = new (double X, double Y)[3];
            for (int k = 0; k < 3; k++) { var a = a0 + (k * FX.Tau) / 3; pts[k] = (Math.Cos(a) * RI, Math.Sin(a) * RI); }
            return pts;
        }
        var A = Tri(-Math.PI / 2);
        var Bt = Tri(Math.PI / 2);
        for (int k = 0; k < 3; k++)
            foreach (var T in new[] { A, Bt })
                edges.Add(new Edge(T[k], T[(k + 1) % 3], STAR.A + (k * (STAR.B - STAR.A)) / 3, (STAR.B - STAR.A) / 3));
    }

    FXColor LineCol(double lvl, double age) =>
        age < 0.05 ? FX.White : age < 0.16 ? C[6] : lvl > 1 ? FX.White : lvl > 0.8 ? C[6] : lvl > 0.45 ? C[5] : lvl > 0.28 ? C[4] : C[3];
    static double LineA(double lvl) => FX.Clamp(lvl / 0.3);

    /// <summary>A straight line on the floor plane, drawn by a pen from p0 to p1 over [t0, t0 + dur]; only the far or near part.</summary>
    void PlaneLine(Painter p, (double X, double Y) p0, (double X, double Y) p1, double t0, double dur, double lvl, bool far)
    {
        var s = FX.Clamp((t - t0) / dur);
        if (s <= 0) return;
        double u0 = 0, u1 = s;
        double v0 = p0.Y, v1 = p1.Y;
        if ((v0 < 0) != (v1 < 0))
        {
            var uc = v0 / (v0 - v1);
            if ((v0 < 0) == far) u1 = Math.Min(u1, uc); else u0 = uc;
        }
        else if ((v0 < 0) != far) return;
        if (u1 <= u0) return;
        (double, double) P(double u) => (p0.X + (p1.X - p0.X) * u, (v0 + (v1 - v0) * u) * SY);
        var (xa, ya) = P(u0);
        var (xb, yb) = P(u1);
        var tt = t;
        p.Line(xa, ya, xb, yb, q => LineCol(lvl, tt - (t0 + (u0 + (u1 - u0) * q) * dur)), LineA(lvl));
    }

    void Circle(Painter p, bool far)
    {
        var t = this.t;
        if (t >= GONE) return;
        double lvl = Level(t), a = LineA(lvl);
        Func<double, bool> keep = far ? g => Math.Sin(g) < 0 : g => Math.Sin(g) >= 0;
        void Ring(double r, Func<double, double> when, Func<double, bool>? chase) =>
            FXArcane.FloorRing(p, 0, 0, r, SY, g => chase != null && chase(g) ? FX.White : LineCol(lvl, t - when(g)), g => t < when(g) ? 0 : a, keep);
        // from the moment the runes start to light, two sparks of light chase round the outer ring, faster and faster
        Func<double, bool>? chase = null;
        if (t > RUNES.A && t < BREAK)
        {
            var run = (t - RUNES.A) * 5 + Math.Pow(t - RUNES.A, 2) * 4;
            chase = g => Math.Abs(Math.Atan2(Math.Sin(g - run - 0), Math.Cos(g - run - 0))) < 0.22
                      || Math.Abs(Math.Atan2(Math.Sin(g - run - Math.PI), Math.Cos(g - run - Math.PI))) < 0.22;
        }
        Ring(R, g => OuterAt(g, PEN), chase);
        Ring(R2, g => OuterAt(g, PEN2), null);
        Ring(RI, InnerAt, null);
        // ticks across the band between the two outer rings
        for (int j = 0; j < 32; j++)
        {
            var g = ((j + 0.5) * FX.Tau) / 32;
            if ((Math.Sin(g) < 0) != far) continue;
            var when = OuterAt(g, PEN2) + 0.03;
            if (t < when) continue;
            p.Line(Math.Cos(g) * R2, Math.Sin(g) * R2 * SY, Math.Cos(g) * R, Math.Sin(g) * R * SY, LineCol(lvl, t - when), a * (j % 2 != 0 ? 0.6 : 1));
        }
        foreach (var e in edges) PlaneLine(p, e.P0, e.P1, e.T0, e.Dur, lvl, far);
    }

    /// <summary>The runes stand on the circle; dim when the inner pen passes, lit one by one, out one by one.</summary>
    void Runes(Painter p, bool far)
    {
        var t = this.t;
        var C = this.C;
        for (int k = 0; k < NRUNE; k++)
        {
            var g = RuneAngle(k);
            if ((Math.Sin(g) < 0) != far) continue;
            double x = Math.Cos(g) * RR, y0 = Math.Sin(g) * RR * SY, lit = t - RuneLit(k), gone = FX.Clamp((t - RuneOut(k)) / 0.25);
            if (t < InnerAt(g) || gone >= 1) continue;
            if (lit < 0)
            {
                FXArcane.Glyph(p, k, x, y0 - 1, C[3]);
                continue;
            }
            double rise = 3 * FX.Ease.OutBack(FX.Clamp(lit / 0.2), 2.4), bob = lit > 0.2 ? Math.Sin(t * 5 + k) * 0.5 : 0, y = y0 - 1 - rise + bob;
            var hot = lit < 0.07 || (t > FLASH && t < FLASH + 0.07);
            var lvl = Level(t);
            FXArcane.Glyph(p, k, x, y, hot ? FX.White : lvl > 0.8 ? FX.White : C[6], 1 - gone, hot ? C[6] : C[4]);
            if (lit < 0.1) FX.Sparkle(p, x, y - 2, 4 * (1 - lit / 0.1) + 1, C[6], C[5], 0.5);
            p.Glow(x, y - 2, 8, C[5], (0.3 + 0.3 * lvl) * (1 - gone));
            p.Glow(x, y0, 6, C[4], 0.2 * (1 - gone));
        }
    }

    /// <summary>The column of light: the thread that climbs first, then the beam that fires up, holds and breaks apart.</summary>
    void Column(Painter p)
    {
        var t = this.t;
        var C = this.C;
        if (t < FLASH - 0.22 || t > BREAK + 0.6) return;
        if (t < FLASH)
        {
            double a = FX.Smooth(FLASH - 0.22, FLASH - 0.04, t), top0 = -(TOP - 10) * FX.Ease.OutCubic(a);
            for (var y = -1.0; y >= top0; y -= 1) p.Dot(0, y, y > top0 + 6 ? C[6] : FX.White, a * (0.35 + 0.65 * (1 + y / TOP)));
            p.Glow(0, top0, 9, C[6], 0.5 * a);
            p.Glow(0, -6, 24, C[5], 0.4 * a);
            return;
        }
        double u = t - FLASH, brk = FX.Clamp((t - BREAK) / 0.45), top = -TOP * FX.Ease.OutExpo(FX.Clamp(u / 0.09));
        var w = t < BREAK ? W * (1 + 0.38 * Math.Exp(-u * 9)) : W * (1 - FX.Ease.OutCubic(brk) * 0.85);
        var fade = 1 - FX.Smooth(BREAK + 0.25, BREAK + 0.55, t);
        var white = u < 0.067;
        if (fade <= 0) return;
        var yEnd = (int)FX.Ceil(top);
        for (int yi = 3; yi >= yEnd; yi--)
        {
            double y = yi;
            int hi = -yi;
            double h = hi;
            var ww = w * (1 + 0.5 * Math.Exp(-Math.Max(0, h) / 6));
            var pulse = FX.Fract(h * 0.022 - u * 2.6) < 0.07 ? 1 : 0;
            int xEnd = (int)FX.Ceil(ww * 1.3);
            for (int xi = (int)FX.Floor(-ww * 1.3); xi <= xEnd; xi++)
            {
                double x = xi, q = Math.Abs(x + 0.5) / ww;
                // as it breaks, holes open and grow and drift upward until only shards are left
                if (brk > 0 && FX.Noise2(x * 0.32, h * 0.11 - (t - BREAK) * 6, S) * 0.5 + 0.5 < brk * 1.25 - 0.1) continue;
                var lv = q < 0.2 ? 0 : q < 0.42 ? 1 : q < 0.66 ? 2 : q < 0.88 ? 3 : 4;
                foreach (var s in strands)
                    if (Math.Abs((x + 0.5) / ww - s.O - 0.05 * Math.Sin(t * s.F + s.O * 9)) < s.W) lv = Math.Max(0, lv - 1);
                lv = white ? 0 : Math.Max(0, lv - pulse);
                var a = (q < 0.88 ? 1 : (1.3 - q) / 0.42) * fade;
                if (a <= FXArcane.Bayer(x, y) * (q < 0.66 ? 0.2 : 1)) continue;
                p.Px(x, y, COL[lv]);
            }
            if ((hi & 7) == 0 && h < TOP - ww * 2.4 - 8) p.Glow(0, y, ww * 2.4 + 6, C[5], 0.3 * fade);
        }
        // halos climbing it
        for (int i = 0; i < 6; i++)
        {
            var k = (t - (FLASH + 0.08 + i * 0.16)) / 0.8;
            if (k < 0 || k > 1) continue;
            double rx = w * 1.4 * (1 + k * 0.35), ry = rx * 0.3, yc = -3 - FX.Ease.OutQuad(k) * 120;
            var n = (int)FX.Ceil(rx * 7);
            for (int j = 0; j < n; j++)
            {
                var g = ((double)j / n) * FX.Tau;
                p.Dot(Math.Cos(g) * rx, yc + Math.Sin(g) * ry, k < 0.3 ? FX.White : C[6], (1 - k) * fade * (Math.Sin(g) < 0 ? 0.6 : 1));
            }
        }
        // white-hot where it meets the floor
        p.Glow(0, -4, 34, C[6], 0.45 * fade);
        p.Glow(0, -60, 70, C[4], 0.25 * fade);
    }

    void Shock(Painter p, bool far)
    {
        foreach (var (d, r0, r1, th, dur) in (ReadOnlySpan<(double, double, double, double, double)>)[(0.0, R * 0.6, R * 2, 6.0, 0.5), (0.08, R * 0.4, R * 1.4, 3.0, 0.4)])
        {
            var k = (t - FLASH - d) / dur;
            if (k < 0 || k >= 1) continue;
            FX.Band(p, 0, 0, r0 + (r1 - r0) * FX.Ease.OutCubic(k), SY, Math.Max(1, th * (1 - k)), 1.15 - k, [C[3], C[5], C[6], FX.White],
                    g => (Math.Sin(g) < 0) == far, k < 0.2);
        }
    }

    public void Update(double dt)
    {
        t += dt;
        var t_ = t;
        var C = this.C;
        var Rg = this.Rg;
        // the pens shed glitter as they write
        if (t_ > PEN.A && t_ < STAR.B && Rg.Chance(0.5))
        {
            double x, y;
            if (t_ < PEN.B)
            {
                var g = Math.PI / 2 + Rg.Sign() * ((t_ - PEN.A) / (PEN.B - PEN.A)) * Math.PI;
                x = Math.Cos(g) * R; y = Math.Sin(g) * R * SY;
            }
            else if (t_ < INNER.B)
            {
                var g = -Math.PI / 2 + ((t_ - INNER.A) / (INNER.B - INNER.A)) * FX.Tau;
                x = Math.Cos(g) * RI; y = Math.Sin(g) * RI * SY;
            }
            else
            {
                var live = edges.Where(e => t_ >= e.T0 && t_ < e.T0 + e.Dur).ToList();
                var pick = (int)FX.Floor(Rg.Next() * live.Count);
                var e = pick < live.Count ? live[pick] : edges[0];
                var s = FX.Clamp((t_ - e.T0) / e.Dur);
                x = e.P0.X + (e.P1.X - e.P0.X) * s; y = (e.P0.Y + (e.P1.Y - e.P0.Y) * s) * SY;
            }
            double vx = Rg.Range(-12, 12), vy = Rg.Range(-30, -8), life = Rg.Range(0.25, 0.55);
            ps.Spawn(FXKind.Ember, x, y - 1, vx, vy, life, C[6], 1);
        }
        // gathering: light rushes in along the floor to the heart of the circle
        if (t_ > RUNES.B - 0.1 && t_ < FLASH - 0.05 && Rg.Chance(0.7))
        {
            double g = Rg.Range(0, FX.Tau), D = Rg.Range(R * 0.7, R * 1.1), T = Rg.Range(0.16, 0.24), v = (D * 3) / (Math.Exp(3 * T) - 1);
            double x = Math.Cos(g) * D, y = Math.Sin(g) * D * SY - 1, h = FX.Hypot(x, y + 2), l = h == 0 ? 1 : h;
            ps.Spawn(FXKind.Streak, x, y, (-x / l) * v, ((-2 - y) / l) * v, T, Rg.Chance(0.5) ? C[6] : C[5]);
        }
        if (!flashed && t_ >= FLASH)
        {
            flashed = true;
            lights.Add(0, -56, 104, C[5], 0.9, 0.6);
            lights.Add(0, -5, 36, FX.White, 0.8, 0.14);
            for (int i = 0; i < 36; i++)
            {
                double s = Rg.Sign(), sp = Rg.Range(80, 175);
                double x = s * Rg.Range(0, R * 0.5), vy = -Rg.Range(30, 180), life = Rg.Range(0.25, 0.7);
                ps.Spawn(FXKind.Spark, x, -1, s * sp, vy, life);
            }
            for (int i = 0; i < 26; i++)
            {
                double x = Rg.Range(-R, R), y = -Rg.Range(1, 6), vx = Rg.Range(-20, 20), vy = -Rg.Range(40, 130), life = Rg.Range(0.5, 1.1);
                var c = Rg.Pick([FX.White, C[6], C[5]]);
                var size = Rg.Range(0.8, 2.3);
                ps.Spawn(FXKind.Star, x, y, vx, vy, life, c, size);
            }
            // and a spray of twinkles flung out low across the floor
            for (int i = 0; i < 34; i++)
            {
                var s = Rg.Sign();
                double x = s * Rg.Range(0, 14), y = -Rg.Range(1, 4), vx = s * Rg.Range(50, 140), vy = -Rg.Range(10, 90), life = Rg.Range(0.4, 0.95);
                var c = Rg.Pick([FX.White, C[6], C[6], C[5]]);
                var size = Rg.Range(0.7, 2.2);
                ps.Spawn(FXKind.Star, x, y, vx, vy, life, c, size);
            }
        }
        // glints pop along the burning circle
        if (t_ > RUNES.A && t_ < BREAK + 0.2 && Rg.Chance(0.12))
        {
            var g = Rg.Range(0, FX.Tau);
            var r = Rg.Pick([R, R2, RI]);
            double vy = -Rg.Range(2, 8), life = Rg.Range(0.25, 0.45);
            var c = Rg.Pick([FX.White, C[6]]);
            var size = Rg.Range(0.8, 2);
            ps.Spawn(FXKind.Star, Math.Cos(g) * r, Math.Sin(g) * r * SY - 0.5, 0, vy, life, c, size);
        }
        // the column throws off stars, and light streams up inside it
        if (t_ > FLASH && t_ < BREAK)
        {
            if (Rg.Chance(0.5))
            {
                double x = Rg.Range(-1, 1) * W * 1.5, y = -Rg.Range(0, 120), vx = Rg.Range(-10, 10), vy = -Rg.Range(30, 85), life = Rg.Range(0.5, 1.1);
                var c = Rg.Pick([FX.White, C[6], C[5]]);
                var size = Rg.Range(0.7, 2);
                ps.Spawn(FXKind.Star, x, y, vx, vy, life, c, size);
            }
            if (Rg.Chance(0.35))
            {
                double x = Rg.Range(-1, 1) * W * 0.8, y = -Rg.Range(0, 50), vy = -Rg.Range(160, 300), life = Rg.Range(0.2, 0.35);
                ps.Spawn(FXKind.Mote, x, y, 0, vy, life, Rg.Chance(0.5) ? FX.White : C[6], 0.8);
            }
        }
        // it breaks apart into glints that twinkle as they drift up
        if (!broke && t_ >= BREAK)
        {
            broke = true;
            for (int i = 0; i < 46; i++)
            {
                double x = Rg.Range(-1, 1) * W * 0.9, y = -Rg.Range(2, TOP * 0.8), vx = Rg.Range(-12, 12), vy = -Rg.Range(8, 40), life = Rg.Range(0.5, 1.15);
                var c = Rg.Pick([FX.White, FX.White, C[6], C[5]]);
                var size = Rg.Range(0.6, 2.4);
                ps.Spawn(FXKind.Star, x, y, vx, vy, life, c, size);
            }
        }
        if (t_ > BREAK && t_ < BREAK + 0.4 && Rg.Chance(0.8))
        {
            double x = Rg.Range(-1, 1) * W * 0.7, y = -Rg.Range(2, TOP * 0.78), vx = Rg.Range(-8, 8), vy = -Rg.Range(10, 50), life = Rg.Range(0.4, 0.9);
            var c = Rg.Pick([FX.White, C[6], C[5]]);
            var size = Rg.Range(0.6, 1.8);
            ps.Spawn(FXKind.Star, x, y, vx, vy, life, c, size);
            if (Rg.Chance(0.4))
            {
                double mx = Rg.Range(-1, 1) * W * 0.5, my = -Rg.Range(2, TOP * 0.7), mvy = -Rg.Range(60, 140), mlife = Rg.Range(0.2, 0.4);
                ps.Spawn(FXKind.Mote, mx, my, 0, mvy, mlife, C[6], 0.7);
            }
        }
        // the runes go out one by one, each in a little puff of glints
        for (int k = 0; k < NRUNE; k++)
        {
            if (@out[k] || t_ < RuneOut(k)) continue;
            @out[k] = true;
            double g = RuneAngle(k), x = Math.Cos(g) * RR, y = Math.Sin(g) * RR * SY - 5;
            for (int i = 0; i < 4; i++)
            {
                double px = x + Rg.Range(-2, 2), py = y + Rg.Range(-2, 2), vx = Rg.Range(-14, 14), vy = -Rg.Range(10, 40), life = Rg.Range(0.3, 0.55);
                var c = Rg.Pick([FX.White, C[6]]);
                var size = Rg.Range(0.6, 1.6);
                ps.Spawn(FXKind.Star, px, py, vx, vy, life, c, size);
            }
        }
        ps.Update(dt);
        lights.Update(dt);
    }

    public void DrawBack(Painter p, double tt)
    {
        var lvl = Level(t);
        if (t < GONE)
        {
            var k = lvl * FX.Smooth(PEN.A, PEN.B + 0.2, t);
            p.Glow(0, 0, R * 1.3, C[4], 0.28 * k);
            foreach (var s in (ReadOnlySpan<double>)[-1.0, 1.0]) p.Glow(s * R * 0.6, 1, R * 0.7, C[5], 0.12 * k);
        }
        Shock(p, true);
        Circle(p, true);
        Runes(p, true);
        Column(p);
        ps.Draw(p, FXLayer.Back);
    }

    public void Draw(Painter p, double tt)
    {
        var t = this.t;
        var C = this.C;
        Shock(p, false);
        Circle(p, false);
        Runes(p, false);
        // the pens: white points running round, writing light
        void Pen(double x, double y)
        {
            FX.Sparkle(p, x, y, 2, C[6], C[5], 0.5);
            p.Glow(x, y, 7, C[6], 0.45);
        }
        if (t > PEN.A && t < PEN.B)
            foreach (var s in (ReadOnlySpan<double>)[-1.0, 1.0])
            {
                var g = Math.PI / 2 + s * ((t - PEN.A) / (PEN.B - PEN.A)) * Math.PI;
                Pen(Math.Cos(g) * R, Math.Sin(g) * R * SY);
            }
        if (t > INNER.A && t < INNER.B)
        {
            var g = -Math.PI / 2 + ((t - INNER.A) / (INNER.B - INNER.A)) * FX.Tau;
            Pen(Math.Cos(g) * RI, Math.Sin(g) * RI * SY);
        }
        foreach (var e in edges)
        {
            if (!(t > e.T0 && t < e.T0 + e.Dur)) continue;
            var s = (t - e.T0) / e.Dur;
            Pen(e.P0.X + (e.P1.X - e.P0.X) * s, (e.P0.Y + (e.P1.Y - e.P0.Y) * s) * SY);
        }
        // the flash
        if (t >= FLASH && t < FLASH + 0.24)
        {
            var a = (t - FLASH) / 0.24;
            FX.Flare(p, 0, -8, 34 * Math.Pow(1 - a, 1.5), 1 - a, C);
            p.Glow(0, -26, 56, FX.White, 0.5 * (1 - a));
        }
        ps.Draw(p, FXLayer.Front);
        lights.Draw(p);
    }
}

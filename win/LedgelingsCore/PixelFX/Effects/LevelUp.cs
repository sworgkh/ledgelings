// Gold gathers at the feet and bursts up as a pillar of light round the hero; rings climb it, LEVEL UP!
// drops in letter by letter, a shine sweeps it, sparkles twinkle. pixelfx's `ui/level-up` (MIT); the
// pillar's strands and climbing rings adapt Sprite Fusion's open-source holy light
// (https://www.spritefusion.com/pixel-art-vfx/holy-light), and the rushing streaks its power-up
// (https://www.spritefusion.com/pixel-art-vfx/power-up), MIT License, Copyright (c) 2026 Hugo Duprez.
// The Mac's twin is LevelUp.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXLevelUp : IFXEffect
{
    public static readonly FXMeta Meta = new("ui/level-up", size: (176, 138), origin: (88, 114), duration: 3.2, loop: false,
                                             palette: ["#2a1405", "#5c3008", "#9a5a0e", "#d48e18", "#f5b92c", "#ffde5e", "#fff4bc", "#ffffff"], seed: 5);
    const string Text = "LEVEL UP!";
    // release, pillar lifts off, pillar gone, pillar height, text top, first letter, stagger, shine, letters pop
    const double REL = 0.28, RET = 1.02, GONE = 1.34, TOP = 100.0, TY = -68.0, DROP = 0.5, STAG = 0.05, LANDED = 1.06, SHINE = 1.24, EXIT = 2.3;
    // strands of light streaming up the pillar in dashes: where across it, how fast, dash period and length
    readonly record struct Strand(double X, double Sp, double Per, double Duty, double Ph, int Lvl, double End);
    static readonly Strand[] STRANDS = Enumerable.Range(0, 9).Select(n =>
    {
        double i = n;
        return new Strand(X: (i / 8 - 0.5) * 1.5 + (FX.Rand(i, 1) - 0.5) * 0.16, Sp: 170 + FX.Rand(i, 2) * 170, Per: 10 + FX.Rand(i, 3) * 16,
                          Duty: 0.3 + FX.Rand(i, 4) * 0.35, Ph: FX.Rand(i, 5), Lvl: FX.Rand(i, 6) < 0.35 ? 1 : 2, End: 0.5 + FX.Rand(i, 7) * 0.42);
    }).ToArray();

    /// <summary>Half-width of the pillar at time t.</summary>
    static double WidthAt(double t) =>
        t < REL ? 0 : 12 * (1 + 0.4 * Math.Exp(-(t - REL) * 10)) * (1 - 0.82 * FX.Smooth(RET - 0.12, RET + 0.16, t));

    sealed class Letter(FXUI.Glyph g, double w, double cx, double born, double pop)
    {
        public readonly FXUI.Glyph G = g;
        public readonly double W = w, Cx = cx, Born = born, Pop = pop;
        public double Off = -18.0, V = 60.0, Sq = 0.0, Flash = 0.0;
        public bool On = false, Landed = false, Rest = false, Burst = false;
    }
    readonly record struct Sat(double X, double Y, double T0, double Dur, double L);
    struct Rush { public double X, Y, Vx, Vy, Life, Len; public FXColor C; public bool Back; }

    readonly FXColor[] C;
    readonly Rng R;
    readonly FXActor A;
    readonly FXColor SHADOW;
    readonly FXParticles ps;
    readonly FXLights lights = new();
    readonly double BASE, X0, right;
    readonly List<Letter> lets;
    readonly Sat[] sats;
    readonly List<double> halos = new();
    double t = 0.0, nextHalo = REL + 0.03, gather = 0.0;
    bool released = false;
    readonly List<Rush> rush = new();

    public FXLevelUp(FXOptions o)
    {
        C = FX.Fit(o.Palette, 8);
        var R = new Rng(o.Seed);
        this.R = R;
        A = o.Actor;
        SHADOW = FX.Scale(C[0], 0.5);
        ps = new FXParticles(rng: R, ground: _ => 0, sparks: [C[7], C[6], C[5], C[3]]);
        var word = FXUI.Spell(Text);
        BASE = TY + 14;
        X0 = -(double)word.W;
        var x0 = X0;
        lets = word.Letters.Where(L => L.G != null).Select((L, i) =>
            new Letter(L.G!, L.W, x0 + (L.X + L.W / 2.0) * 2, DROP + i * STAG, EXIT + i * 0.04)).ToList();
        right = X0 + word.W * 2.0;
        // sparkles that pop round the title one after another
        sats = new Sat[8];
        for (int i = 0; i < 8; i++)
        {
            double s = i % 2 != 0 ? 1 : -1, x = s * R.Range(20, 60), y = TY + 7 + (Math.Abs(x) < 50 ? R.Sign() * R.Range(11, 18) : R.Range(-14, 14));
            double t0 = SHINE - 0.1 + i * 0.13 + R.Range(0, 0.05), dur = R.Range(0.32, 0.5), L = R.Range(3, 6);
            sats[i] = new Sat(x, y, t0, dur, L);
        }
    }

    /// <summary>Every particle is gone by the end.</summary>
    void Spawn(FXKind k, double x, double y, double vx, double vy, double life,
               FXColor col = FX.White, double size = 1, double delay = 0, int flag = 0) =>
        ps.Spawn(k, x, y, vx, vy, Math.Min(life, Meta.Duration - 0.05 - t), col, size, delay, flag);

    /// <summary>The pillar: shoots up from the feet (one white-hot frame), then stands as light: two flowing walls, a
    /// white core and strands streaming up in dashes; at the end its foot lifts off and it shoots away.</summary>
    void Column(Painter p, double t)
    {
        var C = this.C;
        var a = t - REL;
        if (a < 0 || t > GONE) return;
        double top = -TOP * FX.Ease.OutExpo(FX.Clamp(a / 0.12)), bot = -TOP * FX.Ease.InCubic(FX.Seg(t, RET, GONE)), W = WidthAt(t), k = 1 - FX.Smooth(RET, GONE, t);
        p.GlowLine(0, top, 0, Math.Min(bot, -34), W * 1.6 + 6, C[5], 0.2 * k + 0.06);
        p.GlowLine(0, top, 0, Math.Min(bot, -40), 5, FX.White, 0.18 * k);
        if (a < 0.04)
        {
            for (var y = FX.Floor(top); y < bot; y++)
            {
                var wr = W * 0.55 * (1 - 0.3 * (-y / TOP));
                for (var x = FX.Floor(-wr); x <= FX.Ceil(wr); x++) p.Dot(x, y, Math.Abs(x + 0.5) < wr - 1.5 ? FX.White : C[6], FX.Clamp((y + TOP) / 20) * 1.5);
            }
            return;
        }
        for (var y = FX.Ceil(top); y < FX.Ceil(bot); y++)
        {
            double h = -y / TOP, fade = FX.Clamp((y + TOP) / 16) * (t < RET ? 1 : FX.Clamp((bot - y) / 10));
            var head = y - top < 3 && a < 0.16;
            var wr = W * (1 - 0.3 * h) + 0.9 * FX.Noise2(y * 0.2, t * 12, 3);
            foreach (var s in (ReadOnlySpan<double>)[-1.0, 1.0])
            {
                var run = FX.Fract(y * 0.06 + t * 3.4 + (s > 0 ? 0.5 : 0)) < 0.78;
                var xw = s * wr;
                p.Dot(xw, y, head ? FX.White : run ? C[6] : C[5], fade * 1.4);
                p.Dot(xw + s, y, C[4], fade * (run ? 0.5 : 0.25));
                if (run) p.Dot(xw - s, y, C[5], fade * 1.2);
            }
            p.Dot(0, y, FX.White, fade * 1.6);
            p.Dot(-1, y, FX.Noise2(y * 0.3, t * 14, 5) > -0.2 ? FX.White : C[6], fade * 1.3);
            if (FX.Noise2(y * 0.25, t * 9, 8) > 0.25) p.Dot(1, y, C[6], fade * 1.2);
            foreach (var S in STRANDS)
            {
                if (h > S.End) continue;
                var ph = FX.Fract((y + t * S.Sp) / S.Per + S.Ph);
                if (ph > S.Duty) continue;
                var u = ph / S.Duty;
                p.Px(S.X * wr, y, head || u < 0.2 ? FX.White : u < 0.65 ? C[7 - S.Lvl] : C[6 - S.Lvl]);
            }
        }
    }

    /// <summary>The plate of light the pillar stands on.</summary>
    void Plate(Painter p, double t, double k)
    {
        if (k <= 0.02) return;
        var C = this.C;
        double rx = 9 + 9 * k + Math.Sin(t * 9), ry = 2.2;
        p.Shade(-rx, -ry, rx, ry, (x, y, o) =>
        {
            double dx = x / rx, dy = y / ry, d = Math.Sqrt(dx * dx + dy * dy);
            if (d > 1) return 0;
            var u = d / Math.Max(0.05, k);
            o.C = u < 0.3 ? FX.White : u < 0.55 ? C[6] : u < 0.8 ? C[5] : C[4];
            o.A = d < 0.6 * k ? 1 : k * (1 - d) * 2.2;
            return 0;
        });
        p.Glow(0, -1, rx * 2.2, C[4], 0.35 * k);
    }

    /// <summary>Rays above and below the title, starting on an ellipse just outside the word so none crosses it.</summary>
    void Rays(Painter p, double t, double k, double cx, double cy)
    {
        if (k <= 0.02) return;
        var C = this.C;
        for (int n = 0; n < 20; n++)
        {
            double i = n, an = (i / 20) * FX.Tau + 0.08, ca = Math.Cos(an), sa = Math.Sin(an);
            var @long = n % 2 == 0;
            if (Math.Abs(sa) < 0.4) continue;
            double ex = ca / 52, ey = sa / 12;
            double r0 = 1 / Math.Sqrt(ex * ex + ey * ey) + 2 * k, len = (@long ? 15 + 7 * FX.Rand(i, 9) : 7 + 4 * FX.Rand(i, 8)) * k;
            if (len < 1) continue;
            double sh = 0.75 + 0.25 * Math.Sin(t * 7 + i * 2.1), x0 = cx + ca * r0, y0 = cy + sa * r0;
            p.Line(x0, y0, x0 + ca * len, y0 + sa * len, u => u < 0.3 ? C[7] : u < 0.6 ? C[6] : C[5], u => sh * (u < 0.55 ? 1.3 : (1.3 * (1 - u)) / 0.45));
        }
    }

    /// <summary>A gathering streak: a gold tail and a white head, running straight in.</summary>
    void DrawRush(Painter p, bool back)
    {
        foreach (var m in rush)
        {
            if (m.Back != back) continue;
            double sp = FX.Hypot(m.Vx, m.Vy), ux = m.Vx / sp, uy = m.Vy / sp, L = m.Len;
            p.Line(m.X - ux * L, m.Y - uy * L, m.X - ux * L * 0.4, m.Y - uy * L * 0.4, m.C);
            p.Line(m.X - ux * L * 0.35, m.Y - uy * L * 0.35, m.X, m.Y, FX.White);
            p.Glow(m.X, m.Y, 4, C[5], 0.25);
        }
    }

    public void Update(double dt)
    {
        var C = this.C;
        var R = this.R;
        var A = this.A;
        const int BACK = FXFlag.Back;
        this.t += dt;
        var t = this.t;
        // the gathering: streaks pour in along the floor to the feet and in from all round to the body, and in
        // the last beat run up the hero from the feet; the late ones are swallowed by the burst
        gather += t < REL ? dt * 420 : 0;
        while (gather >= 1)
        {
            gather -= 1;
            double kind = R.Next(), sp = R.Range(140, 250) * (1 + t * 2);
            double x, y, tx, ty;
            if (kind < 0.42)
            {
                double an = R.Range(0, FX.Tau), D = R.Range(22, 70);
                x = Math.Cos(an) * D; y = -1 - Math.Abs(Math.Sin(an)) * D * 0.1; tx = Math.Cos(an) * 3; ty = -1;
            }
            else if (kind < 0.84)
            {
                double an = R.Range(0, FX.Tau), D = R.Range(34, 64);
                x = Math.Cos(an) * D; y = Math.Min(-3, -20 + Math.Sin(an) * D * 0.85); tx = Math.Cos(an) * 11; ty = -20 + Math.Sin(an) * 14;
            }
            else
            {
                if (t < REL * 0.4) continue;
                x = R.Range(-9, 9); y = -1; tx = x * 0.7; ty = -R.Range(26, 44);
            }
            double dx = tx - x, dy = ty - y, hl = FX.Hypot(dx, dy), l = hl == 0 ? 1 : hl;
            double life = Math.Min(l / sp, REL + 0.06 - t), len = R.Range(5, 9);
            var c = R.Chance(0.45) ? C[6] : C[5];
            var back = kind > 0.84 && R.Chance(0.5);
            rush.Add(new Rush { X = x, Y = y, Vx = (dx / l) * sp, Vy = (dy / l) * sp, Life = life, Len = len, C = c, Back = back });
        }
        for (int i = rush.Count - 1; i >= 0; i--)
        {
            var m = rush[i];
            m.Life -= dt;
            if (m.Life <= 0) { rush.RemoveAt(i); continue; }
            m.X += m.Vx * dt; m.Y += m.Vy * dt;
            rush[i] = m;
        }
        if (t < REL && R.Chance(0.12)) Spawn(FXKind.Star, R.Range(-30, 30), -R.Range(0, 3), 0, -R.Range(10, 30), R.Range(0.3, 0.5), C[6], 0.6);
        if (!released && t >= REL)
        {
            released = true;
            lights.Add(0, -24, 90, C[5], 0.6, 0.7);
            lights.Add(0, -8, 40, FX.White, 0.6, 0.12);
            // speed lines flung out from the hero
            for (int n = 0; n < 22; n++)
            {
                double an = (n / 22.0) * FX.Tau + R.Range(-0.12, 0.12), sp = R.Range(260, 460);
                double y0 = -18 + Math.Sin(an) * 8, vy = Math.Sin(an) * sp * 0.8;
                var life = Math.Min(Math.Min(R.Range(0.1, 0.2), vy > 0 ? -y0 / vy : vy < 0 ? (y0 + 104) / -vy : 1), 78 / Math.Abs(Math.Cos(an) * sp));
                Spawn(FXKind.Mote, Math.Cos(an) * 6, y0, Math.Cos(an) * sp, vy, life, R.Chance(0.4) ? C[7] : C[6], 1, 0, an > 0.3 && an < Math.PI - 0.3 ? BACK : 0);
            }
            for (int n = 0; n < 26; n++)
            {
                double an = -Math.PI / 2 + R.Range(-1.3, 1.3), sp = R.Range(120, 290);
                Spawn(FXKind.Spark, R.Range(-5, 5), -2, Math.Cos(an) * sp, Math.Sin(an) * sp, R.Range(0.35, 0.8));
            }
            for (int n = 0; n < 16; n++)
                Spawn(FXKind.Star, R.Range(-10, 10), R.Range(-36, -4), R.Range(-30, 30), -R.Range(15, 60), R.Range(0.6, 1.3), R.Pick([C[7], C[6], C[5]]),
                      R.Chance(0.35) ? R.Range(1.5, 2.6) : R.Range(0.4, 0.9), 0, R.Chance(0.4) ? BACK : 0);
        }
        var W = WidthAt(t);
        if (t >= nextHalo && t < RET - 0.1) { halos.Add(t); nextHalo += 0.16; }
        // streaks race up beside the pillar
        if (t > REL && t < RET + 0.1 && R.Chance(0.5))
        {
            var s = R.Sign();
            double y = R.Range(-4, -60), vy = -R.Range(140, 260);
            Spawn(FXKind.Mote, s * R.Range(0.75, 1.6) * W, y, 0, vy, Math.Min(R.Range(0.16, 0.32), (y + 96) / -vy), R.Chance(0.5) ? C[7] : C[6], R.Range(0.6, 1), 0, R.Chance(0.5) ? BACK : 0);
        }
        // motes rise from the floor while the light lasts
        if (t > REL && t < 2.4 && R.Chance(0.14 * (1 - FX.Seg(t, 1.6, 2.4))))
            Spawn(FXKind.Ember, R.Range(-20, 20), -R.Range(1, 30), R.Range(-15, 15), -R.Range(20, 55), R.Range(0.8, 1.6), C[5], R.Range(1, 2), 0, R.Chance(0.4) ? BACK : 0);
        // gold motes lift off the hero while the light lasts
        if (t > REL + 0.1 && t < 2.2 && R.Chance(0.09))
        {
            var m = A.Mask;
            for (int n = 0; n < 12; n++)
            {
                int i = (int)R.Int(0, m.W - 1), j = (int)R.Int(0, m.H - 1);
                if (m.Data[j * m.W + i] == 0) continue;
                Spawn(FXKind.Star, A.X + i + 0.5, A.Y + j + 0.5, R.Range(-8, 8), -R.Range(14, 34), R.Range(0.6, 1.1), R.Pick([C[7], C[6], C[5]]),
                      R.Chance(0.2) ? 1.5 : 0.6, 0, R.Chance(0.5) ? BACK : 0);
                break;
            }
        }
        // twinkles round the title and the hero while it holds
        if (t > 1.0 && t < 2.5 && R.Chance(0.13))
        {
            var up = R.Chance(0.6);
            double x = up ? R.Range(-58, 58) : R.Range(-20, 20), y = up ? TY + 7 + R.Range(-16, 16) : R.Range(-44, -6);
            Spawn(FXKind.Star, x, y, R.Range(-6, 6), -R.Range(4, 14), R.Range(0.4, 0.8), R.Pick([C[7], C[6], C[6], C[5]]),
                  R.Chance(0.3) ? R.Range(1.5, 2.4) : 0.6, 0, R.Chance(0.3) ? BACK : 0);
        }
        // the letters drop in, bounce and settle; then pop away one by one
        foreach (var L in lets)
        {
            if (t < L.Born) continue;
            L.On = true;
            if (!L.Rest)
            {
                L.V += 1700 * dt;
                L.Off += L.V * dt;
                if (L.Off >= 0 && L.V > 0)
                {
                    L.Off = 0;
                    if (L.V > 110)
                    {
                        L.Sq = 1;
                        if (!L.Landed)
                        {
                            L.Landed = true;
                            L.Flash = 1;
                            lights.Add(L.Cx, BASE - 7, 18, C[5], 0.55, 0.25);
                            foreach (var s in (ReadOnlySpan<double>)[-1.0, 1.0])
                                Spawn(FXKind.Star, L.Cx + s * L.W, BASE - R.Range(0, 3), s * R.Range(15, 40), -R.Range(5, 25), R.Range(0.25, 0.45), C[6], R.Range(0.5, 1.2));
                        }
                        L.V = -L.V * 0.3;
                    }
                    else { L.V = 0; L.Rest = true; }
                }
            }
            L.Sq = Math.Max(0, L.Sq - dt / 0.1);
            L.Flash = Math.Max(0, L.Flash - dt / 0.12);
            if (!L.Burst && t >= L.Pop + 0.06)
            {
                L.Burst = true;
                for (int i = 0; i < 3; i++)
                {
                    double an = R.Range(0, FX.Tau), sp = R.Range(20, 55);
                    Spawn(FXKind.Star, L.Cx + R.Range(-3, 3), BASE - 7 + R.Range(-4, 4), Math.Cos(an) * sp, Math.Sin(an) * sp - 15, R.Range(0.3, 0.6), R.Pick([C[7], C[6]]), i != 0 ? 0.6 : R.Range(1.2, 2));
                }
            }
        }
        ps.Update(dt);
        lights.Update(dt);
    }

    /// <summary>The tilted rings: the gathering ring, the two shock rings and the halos climbing the pillar, the half keep picks.</summary>
    void Rings(Painter p, double t, Func<double, bool> keep)
    {
        var C = this.C;
        if (t < REL)
        {
            var k = FX.Seg(t, 0.02, REL);
            FX.Band(p, 0, 0, 4 + 52 * (1 - FX.Ease.InQuad(k)), 0.2, 1.5, k * 1.1, C, keep);
        }
        foreach (var (d, r1, th) in (ReadOnlySpan<(double, double, double)>)[(0.0, 72.0, 4.0), (0.08, 46.0, 2.5)])
        {
            var k = (t - REL - d) / 0.55;
            if (k > 0 && k < 1) FX.Band(p, 0, 0, 5 + r1 * FX.Ease.OutCubic(k), 0.2, Math.Max(1, th * (1 - k)), 1.15 - k, C, keep, k < 0.15);
        }
        foreach (var h0 in halos)
        {
            var k = (t - h0) / 0.6;
            if (k > 0 && k < 1) FX.Band(p, 0, -2 - 72 * FX.Ease.OutQuad(k), (WidthAt(t) * 1.45 + 4) * (1 - 0.4 * k), 0.3, 1.5, (1 - k) * 1.4, C, keep, k < 0.12);
        }
    }

    public void DrawBack(Painter p, double tt)
    {
        var t = this.t;
        Rays(p, t, FX.Ease.OutExpo(FX.Seg(t, LANDED, LANDED + 0.2)) * (1 - FX.Ease.InQuad(FX.Seg(t, EXIT - 0.15, EXIT + 0.1))), 0, TY + 7);
        Rings(p, t, g => Math.Sin(g) < 0);
        Column(p, t);
        Plate(p, t, t < REL ? 0.55 * FX.Seg(t, 0.05, REL) : 1 - FX.Smooth(RET - 0.1, GONE + 0.2, t));
        ps.Draw(p, FXLayer.Back);
        DrawRush(p, true);
    }

    public void Draw(Painter p, double tt)
    {
        var C = this.C;
        var t = this.t;
        var A = this.A;
        // near halves of the rings, in front of the hero
        Rings(p, t, g => Math.Sin(g) >= 0);
        // the hero: warming as it gathers, flashed white on the release, then lit gold with a glowing edge
        var lit = FX.Smooth(REL - 0.02, REL + 0.04, t) * (1 - FX.Smooth(RET, 2.5, t));
        FXUI.TintActor(p, A, t < REL ? 0 : t < REL + 0.06 ? 1 : Math.Exp(-(t - REL - 0.06) / 0.07), [C[4], C[5], C[6]]);
        FXUI.LightActor(p, A, C[5], 0.1 * FX.Seg(t, 0.05, REL) * (1 - lit) + 0.06 * lit, 0.6 * lit, t);
        FXUI.HaloActor(p, A, C[5], 0.85 * lit * (1 - FX.Smooth(RET, GONE + 0.3, t)) + 0.3 * lit, t);
        // the spark gathering at the feet, then the flare of the release
        if (t < REL)
        {
            double k = FX.Seg(t, 0.05, REL), q = t - REL * 0.6, beat = 1 + 0.4 * Math.Exp(-(q * q) / 0.001);
            FX.Sparkle(p, 0, -2, (1 + 4 * k * k) * beat, C[6], C[5], 0.3 + 0.4 * k);
        }
        else if (t < REL + 0.22)
        {
            var a = (t - REL) / 0.22;
            FX.Flare(p, 0, -4, 28 * Math.Pow(1 - a, 1.5), 1 - a, C);
            p.Glow(0, -16, 48, FX.White, 0.3 * (1 - a));
        }
        ps.Draw(p, FXLayer.Front);
        DrawRush(p, false);
        // the title
        var items = new List<FXUI.Item>();
        var done = (t - LANDED) / 0.12;
        foreach (var L in lets)
        {
            if (!L.On) continue;
            double sx = 2.0, sy = 2.0, flash = L.Flash;
            if (!L.Landed && L.V > 150) { sx = 1.8; sy = 2.3; }
            if (L.Sq > 0) { sx = 2 * (1 + 0.22 * L.Sq); sy = 2 * (1 - 0.22 * L.Sq); }
            double pu = (t - L.Pop) / 0.07, hop = FX.Seg(t, L.Pop - 0.1, L.Pop);
            if (pu >= 1) continue;
            if (hop > 0 && pu <= 0) { sx = 2 * (1 - 0.1 * hop); sy = 2 * (1 + 0.15 * hop); }
            if (pu > 0) { sx = 2 * (1 + 0.3 * pu); sy = sx; flash = 1; }
            flash = Math.Max(flash, done > 0 && done < 1 ? 1 - done : 0);
            double h = 7 * sy, w = L.W * sx;
            items.Add(new FXUI.Item(L.G, L.Cx - w / 2, BASE + L.Off - h - 3 * FX.Ease.OutQuad(hop), sx, sy, a: FX.Clamp((t - L.Born) / 0.05), flash: flash));
        }
        var sh = FX.Seg(t, SHINE, SHINE + 0.34);
        double? shine = sh > 0 && sh < 1 ? X0 - 14 + (right - X0 + 30) * FX.Ease.InOutSine(sh) : null;
        FXUI.DrawWord(p, items, new FXUI.WordStyle { Fill = [C[3], C[4], C[5], C[6]], Edge = FX.White, Under = C[2], Outline = C[0], Shadow = SHADOW, Shine = shine, ShineY = TY, Glint = C[6] });
        if (shine is double sv && sv > X0 && sv < right) p.GlowLine(sv, TY, sv + 8.4, BASE, 9, C[6], 0.3);
        var hold = FX.Smooth(0.9, 1.2, t) * (1 - FX.Smooth(EXIT, EXIT + 0.4, t));
        if (hold > 0) p.Glow(0, TY + 7, 50, C[5], 0.22 * hold + (done > 0 && done < 1 ? 0.3 * (1 - done) : 0));
        // each letter twinkles out where it popped
        foreach (var L in lets)
        {
            var u = (t - L.Pop - 0.07) / 0.16;
            if (u > 0 && u < 1) FX.Sparkle(p, L.Cx, BASE - 7, 6 * (1 - u) * (1 - u), C[6], C[5], 0.5);
        }
        // the glint where the shine leaves the word, and sparkles popping round it
        var g = (t - SHINE - 0.3) / 0.26;
        if (g > 0 && g < 1) FX.Sparkle(p, right - 2, TY + 1, 7 * Math.Sin(g * Math.PI), C[6], C[5], 0.6);
        foreach (var s in sats)
        {
            var u = (t - s.T0) / s.Dur;
            if (u > 0 && u < 1) FX.Sparkle(p, s.X, s.Y, s.L * Math.Pow(Math.Sin(u * Math.PI), 0.7), C[6], C[5], 0.5);
        }
        lights.Draw(p);
    }
}

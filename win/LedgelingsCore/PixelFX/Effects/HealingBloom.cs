// Healing bloom: a sprout pushes up and unfurls, a bud swells and opens round a glowing golden heart in a flare
// of healing light; its petals lift away one by one as motes. pixelfx's `nature/healing-bloom` (MIT); the healing
// light adapts Sprite Fusion's open-source heal (https://www.spritefusion.com/pixel-art-vfx/heal), MIT,
// Copyright (c) 2026 Hugo Duprez. The Mac's twin is HealingBloom.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXHealingBloom : IFXEffect
{
    public static readonly FXMeta Meta = new("nature/healing-bloom", size: (124, 120), origin: (62, 108), duration: 3.3, loop: false,
                                             palette: ["#0c1a10", "#173a1a", "#24582a", "#357a34", "#52a03e", "#86c84e", "#c4ec7a", "#f4ffd0"], seed: 4);
    static readonly FXColor[] PetalRamp = FX.Ramp(["#4a1a3a", "#a8406e", "#ec8ab0", "#ffd8e8"]);
    static readonly FXColor[] HeartRamp = FX.Ramp(["#a8641a", "#f0b42e", "#ffe680", "#fffbe0"]);
    const double STEM = 0.42, BUD = 0.75, OPEN = 1.05, LIFT = 1.7, WILT = 2.4, H = 36.0;
    const int NPET = 6;

    /// <summary>A bevelled cross of light.</summary>
    static void Cross(Painter p, double x, double y, int L, FXColor[] C, double a, bool glint)
    {
        double X = FX.Round(x), Y = FX.Round(y);
        bool Ins(int dx, int dy) => (dx == 0 && Math.Abs(dy) <= L) || (dy == 0 && Math.Abs(dx) <= L);
        for (int dy = -L - 1; dy <= L + 1; dy++)
            for (int dx = -L - 1; dx <= L + 1; dx++)
            {
                if (Ins(dx, dy)) p.Dot(X + dx, Y + dy, glint && dx == 0 && dy == 0 ? FX.White : dy < 0 || dx < 0 ? C[6] : C[5], a);
                else if (L > 1 && (Ins(dx - 1, dy) || Ins(dx + 1, dy) || Ins(dx, dy - 1) || Ins(dx, dy + 1))) p.Dot(X + dx, Y + dy, C[2], a * 0.8);
            }
        p.Glow(x, y, 5 + L * 2, C[6], 0.35 * a);
    }

    sealed class Petal(double az, double at)
    {
        public readonly double Az = az, At = at;
        public bool Gone;
    }
    sealed class Flying(double x, double y, double vx, double vy, double a, double va, double vf, double life)
    {
        public double X = x, Y = y, Vx = vx, Vy = vy, A = a, Va = va, Fl = 0, Vf = vf, Life = life, Max = life;
    }
    readonly record struct GlyphOf(double X, double Y, double T0, double Life, int L, double Seed);

    readonly FXColor[] C, Pt, Ht;
    readonly Rng R;
    readonly FXParticles ps;
    readonly FXLights lights = new();
    readonly List<Flying> flying = new();
    readonly List<GlyphOf> glyphs = new();
    readonly List<Petal> petals = new();
    double t;
    bool popped, sprouted;

    public FXHealingBloom(FXOptions o)
    {
        C = FX.Fit(o.Palette, 8); Pt = FX.Fit(PetalRamp, 4); Ht = FX.Fit(HeartRamp, 4); R = new Rng(o.Seed);
        ps = new FXParticles(rng: R, ground: _ => 0, sparks: [Ht[3], Ht[2], Ht[1], Ht[0]]);
        for (int i = 0; i < NPET; i++)
        {
            double di = i;
            petals.Add(new Petal((di / NPET) * FX.Tau + 0.3, LIFT + FX.Mod(di * 0.37, 1) * 0.55));
        }
    }

    double Grow() => FX.Ease.OutCubic(FX.Clamp(t / STEM)) * (1 - FX.Ease.InCubic(FX.Clamp((t - WILT) / 0.6)));
    double Sway() => Math.Sin(t * 2.6) * 1.4 * FX.Smooth(0.2, 0.6, t);
    /// <summary>The stem's points, base to tip: a gentle S that sways.</summary>
    List<(double X, double Y)> Stem()
    {
        var g = Grow();
        var pts = new List<(double X, double Y)>(13);
        for (int i = 0; i <= 12; i++)
        {
            var s = i / 12.0;
            pts.Add((Math.Sin(s * 3.2) * 2.2 * s + Sway() * s * s, (1 - g) * H * 1.1 - s * H));
        }
        return pts;
    }
    double Open() => FX.Ease.OutBack(FX.Clamp((t - BUD) / (OPEN - BUD)), 1.4);

    public void Update(double dt)
    {
        t += dt;
        var t_ = t;
        var C = this.C;
        var Ht = this.Ht;
        var Pt = this.Pt;
        var R = this.R;
        var D = Meta.Duration;
        var f = Math.Min(1, dt * 120);
        var top = Stem()[12];
        if (!sprouted)
        {
            sprouted = true;
            for (int i = 0; i < 8; i++)
            {
                double x = R.Range(-3, 3), vx = R.Range(-40, 40), vy = -R.Range(40, 100), life = R.Range(0.5, 0.8);
                var c = R.Pick([C[2], C[3]]);
                ps.Spawn(FXKind.Grit, x, -1, vx, vy, life, c, 1);
            }
            for (int i = 0; i < 3; i++)
            {
                double x = R.Range(-3, 3), vx = R.Sign() * R.Range(10, 30), vy = -R.Range(4, 10), life = R.Range(0.4, 0.6), sz = R.Range(1.5, 2.5);
                ps.Spawn(FXKind.Dust, x, -1, vx, vy, life, C[3], sz);
            }
        }
        // the bud draws light in as it swells
        if (t_ > STEM && t_ < BUD && R.Chance(0.3 * f))
        {
            double a = R.Range(0, FX.Tau), d = R.Range(14, 26), x = top.X + Math.Cos(a) * d, y = top.Y - 3 + Math.Sin(a) * d * 0.8;
            var life = R.Range(0.18, 0.26);
            var c = R.Chance(0.5) ? Ht[2] : C[6];
            ps.Spawn(FXKind.Streak, x, y, (top.X - x) * 3.4, (top.Y - 3 - y) * 3.4, life, c);
        }
        if (!popped && t_ >= OPEN - 0.12)
        {
            popped = true;
            lights.Add(top.X, top.Y - 3, 22, FX.White, 0.45, 0.08);
            lights.Add(top.X, top.Y - 3, 70, Ht[2], 0.5, 0.8);
            for (int i = 0; i < 16; i++)
            {
                double a = R.Range(0, FX.Tau), sp = R.Range(40, 120);
                var life = R.Range(0.4, 0.8);
                var c = R.Chance(0.5) ? Ht[3] : C[7];
                ps.Spawn(FXKind.Mote, top.X, top.Y - 3, Math.Cos(a) * sp, Math.Sin(a) * sp - 20, life, c, 0.7);
            }
            for (int i = 0; i < 5; i++)
            {
                double x = top.X + R.Range(-10, 10), y = top.Y - R.Range(0, 14), life = R.Range(0.3, 0.6), sz = R.Range(1, 2.4), dl = R.Range(0, 0.3);
                ps.Spawn(FXKind.Star, x, y, 0, -6, life, Ht[3], sz, dl);
            }
        }
        // while it blooms: crosses and motes of light drift up round it
        if (t_ > OPEN && t_ < WILT && R.Chance(0.13 * f))
        {
            double x = R.Range(-22, 22), y = -R.Range(2, 36), life = Math.Min(R.Range(0.7, 1.1), D - 0.05 - t_);
            var L = R.Chance(0.35) ? 3 : 2;
            var seed = R.Next() * 9;
            glyphs.Add(new GlyphOf(x, y, t_, life, L, seed));
        }
        if (t_ > OPEN - 0.1 && t_ < WILT && R.Chance(0.35 * f))
        {
            double x = R.Range(-20, 20), y = -R.Range(0, 8), vx = R.Range(-6, 6), vy = -R.Range(25, 55), life = Math.Min(R.Range(0.6, 1.1), D - 0.05 - t_);
            var c = R.Chance(0.6) ? C[6] : Ht[2];
            double sz = R.Chance(0.3) ? 2 : 1;
            ps.Spawn(FXKind.Ember, x, y, vx, vy, life, c, sz);
        }
        for (int i = glyphs.Count - 1; i >= 0; i--) if (t_ - glyphs[i].T0 > glyphs[i].Life) glyphs.RemoveAt(i);
        // petals let go one by one and lift away, turning, until they twinkle out
        foreach (var q in petals)
        {
            if (q.Gone || t_ < q.At) continue;
            q.Gone = true;
            double e = Math.PI / 2 - 0.15, dx = Math.Sin(e) * Math.Cos(q.Az), L = 10.0;
            double vx = dx * 30 + R.Range(-10, 10), vy = -R.Range(25, 45), va = R.Range(-5, 5), vf = R.Range(5, 9), life = Math.Min(R.Range(0.75, 1.0), D - 0.45 - t_);
            flying.Add(new Flying(top.X + dx * L * 0.6, top.Y - 3 - Math.Cos(e) * L * 0.6, vx, vy, Math.Atan2(-Math.Cos(e), dx), va, vf, life));
        }
        for (int i = flying.Count - 1; i >= 0; i--)
        {
            var q = flying[i];
            q.Life -= dt;
            if (q.Life <= 0)
            {
                ps.Spawn(FXKind.Star, q.X, q.Y, 0, -8, Math.Min(0.35, D - 0.05 - t_), Pt[3], 1.8);
                flying.RemoveAt(i);
                continue;
            }
            q.Vx -= q.Vx * 1.5 * dt;
            q.Vy -= q.Vy * 0.8 * dt + 10 * dt;
            q.X += q.Vx * dt + Math.Sin(q.Fl) * 12 * dt;
            q.Y += q.Vy * dt;
            q.A += q.Va * dt;
            q.Fl += q.Vf * dt;
        }
        ps.Update(dt);
        lights.Update(dt);
    }

    /// <summary>A petal: from closed round the bud to splayed open round the heart, foreshortened by where it points.</summary>
    void DrawPetal(Painter p, Petal q, (double X, double Y) top)
    {
        var Pt = this.Pt;
        double op = Open(), e = FX.Lerp(0.15, Math.PI / 2 - 0.2, op), dx = Math.Sin(e) * Math.Cos(q.Az), dz = Math.Sin(e) * Math.Sin(q.Az), dy = -Math.Cos(e);
        double L = FX.Lerp(8, 12, op), len = L * FX.Hypot(dx, dy), ang = Math.Atan2(dy, dx), cy = top.Y - 3;
        var back = dz < 0;
        if (len < 1.5) return;
        FXNature.DrawLeaf(p, top.X + dx * L * 0.5, cy + dy * L * 0.5, len + 1, 3 + (1 - Math.Abs(dz)) * 0.8, ang, back ? 0.9 : 0.2,
                          back ? [Pt[0], Pt[0], Pt[1], Pt[2]] : [Pt[0], Pt[1], Pt[2], Pt[3]]);
    }

    public void DrawBack(Painter p, double tt)
    {
        var t = this.t;
        var C = this.C;
        var Ht = this.Ht;
        var bloom = FX.Smooth(OPEN - 0.15, OPEN + 0.2, t) * (1 - FX.Smooth(WILT - 0.2, WILT + 0.5, t));
        var top = Stem()[12];
        // a column of soft healing light, and a lit ring on the floor that blooms out as it opens
        for (var h = 0.0; h < 70; h += 7) p.Glow(0, -h, 22, C[5], 0.12 * bloom * (1 - h / 80));
        var k = FX.Clamp((t - OPEN + 0.12) / 0.6);
        if (k > 0 && k < 1)
            FX.Band(p, 0, 0.5, 6 + 30 * FX.Ease.OutCubic(k), 0.18, Math.Max(1, 3 * (1 - k)), 1.1 - k, [C[3], C[5], Ht[2], Ht[3]], g => Math.Sin(g) < 0);
        var fw = 6 + 16 * FX.Smooth(0, 0.8, t);
        for (int xi = (int)FX.Floor(-fw); xi <= fw; xi++)
        {
            // past fw, 1 - u goes below 0 and a is NaN, as in pixelfx: its glow then sets the light it covers to
            // nothing (the painter's NaN turns to 0, as `NaN | 0` does)
            double x = xi, u = Math.Abs(x) / fw, a = Math.Sqrt(1 - u) * FX.Smooth(0, 0.4, t) * (1 - FX.Smooth(WILT, WILT + 0.6, t));
            p.Dot(x, 0, u < 0.3 ? C[6] : u < 0.65 ? C[5] : C[4], a);
            if (xi % 5 == 0) p.Glow(x, 0, 8, C[5], 0.2 * a * (1 - u));
        }
        // the far petals sit behind the heart
        if (t > BUD - 0.05) foreach (var q in petals) if (Math.Sin(q.Az) < 0 && !q.Gone) DrawPetal(p, q, top);
        ps.Draw(p, FXLayer.Back);
    }

    public void Draw(Painter p, double tt)
    {
        var t = this.t;
        var C = this.C;
        var Ht = this.Ht;
        var Pt = this.Pt;
        var pts = Stem();
        var top = pts[12];
        var g = Grow();
        if (g > 0.02)
        {
            // the stem: a 2 px shoot, lit down its left side
            for (int i = 1; i < pts.Count; i++)
            {
                var (x0, y0) = pts[i - 1];
                var (x1, y1) = pts[i];
                if (y1 > 0) continue;
                p.Line(x0, y0, x1, y1, C[5]);
                p.Line(x0 + 1, y0, x1 + 1, y1, C[3]);
            }
            // leaves unfurl off it
            foreach (var (i, sd, d) in (ReadOnlySpan<(int, double, double)>)[(4, -1.0, 0.1), (7, 1.0, 0.22)])
            {
                var lk = FX.Ease.OutBack(FX.Clamp((t - d - 0.12) / 0.3), 1.6) * (1 - FX.Smooth(WILT, WILT + 0.5, t) * 0.4);
                var (x, y) = pts[i];
                if (lk <= 0 || y > -1) continue;
                var la = sd < 0 ? -2.6 + 0.4 * (1 - lk) : -0.55 - 0.4 * (1 - lk);
                FXNature.DrawLeaf(p, x + Math.Cos(la) * 6 * lk, y + Math.Sin(la) * 6 * lk, 12 * lk, 3.4, la, 0.25, [C[1], C[3], C[5], C[6]]);
            }
            // the bud, then the heart once it opens
            if (t > STEM - 0.1 && t < OPEN - 0.1)
            {
                double b = FX.Clamp((t - STEM + 0.1) / (BUD - STEM)), w = 2 + 2.5 * b, h = 3.5 + 5 * b;
                p.Ellipse(top.X, top.Y - h * 0.6, w, h, (dd, a) => Math.Cos(a) < -0.2 ? Pt[2] : dd > 0.7 ? Pt[0] : Pt[1], (_, _) => 1);
                p.Glow(top.X, top.Y - h * 0.6, 8 + 8 * b, Ht[2], 0.25 * b);
            }
        }
        foreach (var q in petals) if (Math.Sin(q.Az) >= 0 && !q.Gone && t > BUD - 0.05) DrawPetal(p, q, top);
        if (t > OPEN - 0.12 && t < WILT + 0.3)
        {
            double pulse = 0.85 + 0.15 * Math.Sin(t * 9), k = 1 - FX.Smooth(WILT - 0.3, WILT + 0.3, t), cy = top.Y - 4;
            p.Circle(top.X, cy, 3.3 * k, Ht[1]);
            p.Circle(top.X - 0.5, cy - 0.5, 2.2 * k, Ht[2]);
            p.Px(top.X - 1, cy - 1, Ht[3]);
            p.Glow(top.X, cy, 16 * pulse, Ht[2], 0.5 * k);
            p.Glow(top.X, cy, 34, C[5], 0.2 * k);
        }
        var e = t - OPEN + 0.12;
        if (e > 0 && e < 0.16) FX.Sparkle(p, top.X, top.Y - 3, 10 * (1 - e / 0.16), Ht[3], Ht[2], 0.6);
        foreach (var q in flying) FXNature.DrawLeaf(p, q.X, q.Y, 6, 2.2, q.A, q.Fl, [Pt[0], Pt[1], Pt[2], Pt[3]], Math.Min(1, q.Life / 0.3));
        foreach (var q in glyphs)
        {
            var k = (t - q.T0) / q.Life;
            Cross(p, q.X + Math.Sin(k * 5 + q.Seed) * 2, q.Y - k * 24, q.L, C, Math.Sin(Math.PI * k), Math.Sin(k * 14 + q.Seed) > 0.8);
        }
        ps.Draw(p, FXLayer.Front);
        lights.Draw(p);
    }
}

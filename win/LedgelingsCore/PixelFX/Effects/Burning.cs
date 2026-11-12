// Fired up: small flames lick from four hot spots, trailing sparks and thin smoke; every 0.6 s they flare,
// the body flashes white then orange, scorch marks spread. pixelfx's `status/burning` (MIT); its flame
// tongues, embers and thin smoke adapt Sprite Fusion's open-source fire
// (https://www.spritefusion.com/pixel-art-vfx/fire), MIT, Copyright (c) 2026 Hugo Duprez. The Mac's twin is Burning.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXBurning : IFXEffect
{
    public static readonly FXMeta Meta = new("status/burning", size: (72, 80), origin: (36, 70), duration: 1.2, loop: true,
                                             palette: ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"], seed: 3);
    static readonly FXColor[] CharRamp = FX.Fit(FX.Ramp(["#120c0a", "#2a1a14", "#4a2c1c"]), 3);
    static readonly FXColor SmokeColor = FX.Hex("#5b5566");
    const double D = 1.2, TickTime = 0.6, Wind = -14.0;
    readonly FXOptions o;
    readonly FXColor[] F;
    public FXBurning(FXOptions o) { this.o = o; F = FX.Fit(o.Palette, 9).Reverse().ToArray(); }

    static double Since(double t) => FX.Mod(FX.Mod(t, TickTime) + TickTime, TickTime);
    static double Flare(double t) => Math.Exp(-Since(t) / 0.12);
    /// <summary>The stand-in is hidden for the one white frame of each tick (the effect draws the body then).</summary>
    public double ActorAlpha(double t) => Since(t) < 0.034 ? 0 : 1;

    readonly record struct Tongue(double Dx, double H, double N);
    sealed record Spot(double X, double Y, List<Tongue> Tongues);
    readonly record struct Scorch(double X, double Y, double R);
    sealed record Spots(List<Spot> List, List<List<Scorch>> Scorch);
    static readonly FXMemo<Spots> Memo = new();

    /// <summary>The hot spots on the outline: the hair tips, a shoulder, the back, a sleeve; scorch spots near them per tick.</summary>
    static Spots SpotsOf(FXActor a, double seed) => Memo.Get(unchecked(a.Key * 31 + (int)seed), () =>
    {
        var S = FXStatus.ShapeOf(a);
        double H = S.H, W = S.W, ax = a.X, ay = a.Y;
        var R = new Rng(seed * 13 + 5);
        (int X, int Y) At(double q, int side)
        {
            var my = (int)FX.Round(H * q);
            var (l, r) = S.Rows[my];
            return (side < 0 ? l : r, my);
        }
        var hair = FX.JsSort(S.Up.Where(u => u.X < W * 0.42), (p, q) =>
        {
            double d = p.Y - q.Y;
            return d != 0 ? d : p.X - q.X;
        })[0];
        var sh = FX.JsSort(S.Up.Where(u => u.X > W / 2 && u.Y > H * 0.4 && u.Y < H * 0.62), (p, q) => p.Y - q.Y);
        var shoulder = sh.Count > 0 ? sh[0] : At(0.5, 1);
        ((int X, int Y) Pt, int N, double H)[] raw = [(hair, 3, 4.5), (shoulder, 2, 4), (At(0.62, -1), 2, 3.5), (At(0.6, 1), 2, 3.5)];
        var list = new List<Spot>();
        for (int i = 0; i < raw.Length; i++)
        {
            var (pt, n, h) = raw[i];
            var tongues = new List<Tongue>();
            for (int j = 0; j < n; j++)
            {
                var dx = (j - (n - 1) / 2.0) * 1.6 + R.Range(-0.4, 0.4);
                tongues.Add(new Tongue(dx, h * R.Range(0.8, 1.2), i * 17 + j * 5 + seed));
            }
            list.Add(new Spot(ax + pt.X + 0.5, ay + pt.Y + 1.5, tongues));
        }
        // scorch marks: each tick chars two patches on the clothes near the spots
        double Lum(int x, int y) => FX.Luma(FXStatus.ColorAt(a, x, y));
        var scorch = new List<List<Scorch>>();
        for (int tick = 0; tick < 2; tick++)
        {
            var row = new List<Scorch>();
            for (int k = 0; k < 2; k++)
            {
                // on the clothes (mid-tones, where char shows), near a hot spot
                var sp = list[(tick * 2 + k + 1) % list.Count];
                var cand = S.Body.Where(b => FX.Hypot(ax + b.X + 0.5 - sp.X, ay + b.Y + 0.5 - sp.Y) < 9 && b.Y > H * 0.42 && Lum(b.X, b.Y) > 0.3 && Lum(b.X, b.Y) < 0.6).ToList();
                if (cand.Count == 0) cand = S.Body.Where(b => b.Y > H * 0.45).ToList();
                var (x, y) = cand[(int)FX.Floor(R.Next() * cand.Count)];
                row.Add(new Scorch(ax + x + 0.5, ay + y + 0.5, R.Range(3.2, 4.4)));
            }
            scorch.Add(row);
        }
        return new Spots(list, scorch);
    });

    public void DrawBack(Painter p, double t)
    {
        var F = this.F;
        var a = o.Actor;
        double fl = Flare(t), flick = 0.8 + 0.2 * FXStatus.Tnoise(t, D, 7.5, 3);
        // warm flicker on the floor
        p.Shade(-30, -3, 30, 7, (x, y, @out) =>
        {
            var d = FX.Hypot(x / 26, (y - 0.5) / 4.5);
            if (d < 1) { @out.L = FX.Mix(F[3], F[4], 0.5); @out.K = (0.16 + 0.22 * fl) * flick * (1 - d) * (1 - d); }
            return 0;
        });
        // thin smoke drifting up and away from each spot
        var smokeC = FX.Mix(SmokeColor, F[6], 0.2);
        var list = SpotsOf(a, o.Seed).List;
        FX.Cycle(t, D, 16, o.Seed + 4, r => r.Range(0.8, 1.2), (age, life, r, i) =>
        {
            var sp = list[i % list.Count];
            double x = sp.X + FXStatus.Travel(Wind * 0.6, Wind * 0.5, 0.8, age) + Math.Sin(age * 4 + i) * 1.2, y = sp.Y - 3 - FXStatus.Travel(18, 6, 1, age);
            FXStatus.Smoke(p, x, y, r.Range(1.1, 1.9), age / life, smokeC, 0.9);
        });
    }

    public void Draw(Painter p, double t)
    {
        var F = this.F;
        var CH = CharRamp;
        var a = o.Actor;
        var S = FXStatus.ShapeOf(a);
        var sp0 = SpotsOf(a, o.Seed);
        var list = sp0.List;
        double ax = a.X, ay = a.Y;
        double ph = Since(t), fl = Flare(t);
        var tick = (int)FX.Mod(FX.Floor(t / TickTime), 2);
        // the tick: the body's own pixels flash white for a frame, then orange, fading
        if (ph < 0.034) { foreach (var (mx, my) in S.Body) p.Px(ax + mx, ay + my, FX.White); }
        else if (ph < 0.22)
        {
            var k = 1 - (ph - 0.034) / 0.186;
            foreach (var (mx, my) in S.Body) p.Blend(ax + mx, ay + my, F[4], 0.55 * k);
        }
        // scorch marks spreading over the clothes from this tick, ember-edged, cooling and fading by the next
        foreach (var sc in sp0.Scorch[tick])
        {
            double grow = FX.Clamp(ph / 0.14), fade = 1 - FX.Clamp((ph - 0.25) / 0.33), r = sc.R * (0.4 + 0.6 * grow);
            if (fade <= 0) continue;
            foreach (var (mx, my) in S.Body)
            {
                double x = ax + mx + 0.5, y = ay + my + 0.5, d = FX.Hypot(x - sc.X, (y - sc.Y) * 1.2) + FX.Rand(mx, my, 7) * 0.9;
                if (d > r) continue;
                var edge = d > r - 1;
                if (edge) p.Dot(x - 0.5, y - 0.5, FX.Rand(mx, my, FX.Floor(t * 20)) < 0.5 ? F[3] : F[4], fade * 1.2);
                else p.Dot(x - 0.5, y - 0.5, d < r * 0.5 ? CH[0] : CH[1], fade * 1.1);
            }
            p.Glow(sc.X, sc.Y, 6, F[4], 0.3 * fade);
        }
        // the hot spots: little tongues licking up, flaring on the tick
        foreach (var sp in list)
        {
            foreach (var tg in sp.Tongues)
            {
                var h = tg.H * (0.85 + 0.25 * FXStatus.Tnoise(t, D, 5, tg.N)) * (1 + 1.6 * fl);
                FXStatus.Tongue(p, sp.X + tg.Dx, sp.Y, h, 1.1 + 0.3 * fl, Wind * 0.08 * h / 4 + FXStatus.Tnoise(t, D, 3, tg.N + 9) * 0.8, F, t, D, tg.N);
            }
            p.Glow(sp.X, sp.Y - 2, 9 + 6 * fl, F[4], 0.22 + 0.35 * fl);
        }
        // sparks streaming up and away
        FX.Cycle(t, D, 20, o.Seed + 6, r => r.Range(0.5, 0.9), (age, life, r, i) =>
        {
            var sp = list[i % list.Count];
            var x = sp.X + r.Range(-1.5, 1.5) + FXStatus.Travel(Wind + r.Range(-10, 6), Wind * 0.6, 1.2, age) + Math.Sin(age * 9 + i) * 1.2 * age;
            var y = sp.Y - 2 + FXStatus.Travel(-r.Range(25, 55), -18, 1.4, age);
            FXStatus.Ember(p, x, y, age / life, [F[1], F[3], F[5]], age + i);
        });
        // the tick throws a burst of sparks off every spot
        if (ph < 0.3)
        {
            for (int k = 0; k < list.Count; k++)
            {
                var sp = list[k];
                for (int j = 0; j < 4; j++)
                {
                    double an = -Math.PI / 2 + (FX.Rand(k, j, tick) - 0.5) * 2.2, v = 50 + 50 * FX.Rand(k, j, 2);
                    double x = sp.X + Math.Cos(an) * FXStatus.Travel(v, 0, 3, ph), y = sp.Y - 2 + Math.Sin(an) * FXStatus.Travel(v, 0, 3, ph) + 60 * ph * ph;
                    p.Px(x, y, ph < 0.12 ? F[1] : F[3]);
                    p.Light(x, y, F[3], 0.4 * (1 - ph / 0.3));
                }
            }
        }
    }
}

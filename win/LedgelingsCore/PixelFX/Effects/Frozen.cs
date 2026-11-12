// Chilled to the bone: frost ferns creep over the body, icicles hang and drip, breath steams, snow settles,
// a shiver every second, frost spreads underfoot. pixelfx's `status/frozen` (MIT). The Mac's twin is Frozen.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXFrozen : IFXEffect
{
    public static readonly FXMeta Meta = new("status/frozen", size: (72, 64), origin: (36, 54), duration: 2, loop: true,
                                             palette: ["#151a3d", "#212f6b", "#2c58aa", "#3a8bd8", "#62c8f4", "#a6ecff", "#dcfbff", "#ffffff"], seed: 4);
    const double D = 2.0, Shiver = 1.0;
    readonly FXOptions o;
    readonly FXColor[] C;
    public FXFrozen(FXOptions o) { this.o = o; C = FX.Fit(o.Palette, 8); }

    static double Since(double t) => FX.Mod(FX.Mod(t, Shiver) + Shiver, Shiver);
    static double Shake(double t) => Since(t) < 0.22 ? (FX.Mod(FX.Floor(t * 50), 2) != 0 ? 1 : -1) : 0;
    /// <summary>The effect draws the whole (chilled, shivering) body, so the stand-in is hidden throughout.</summary>
    public double ActorAlpha(double t) => 0;

    readonly record struct Icicle(double X, double Y, double Len, double Phase, double Period);
    sealed record Plan(List<(int X, int Y, double U, int I)> Ferns, List<Icicle> Icicles, List<(int X, int Y, int D)> Snow, (double X, double Y) Mouth);
    static readonly FXMemo<Plan> Plans = new();

    /// <summary>Worked out once per creature: fern paths creeping in from the outline, icicle roots, snow ledges, the mouth.</summary>
    static Plan PlanOf(FXActor a, double seed) => Plans.Get(unchecked(a.Key * 31 + (int)seed), () =>
    {
        var S = FXStatus.ShapeOf(a);
        double H = S.H, W = S.W;
        var R = new Rng(seed * 11 + 1);
        // ferns: a stem walking in from an edge with fronds branching off it at alternate sides
        var ferns = new List<(int X, int Y, double U, int I)>();
        var roots = FX.JsSort(S.Side.Where(s => s.Y > H * 0.2 && s.Y < H * 0.85), (_, _) => R.Next() - 0.5).Take(6).ToList();
        for (int i = 0; i < roots.Count; i++)
        {
            var (x0, y0, dir) = roots[i];
            double x = x0, y = y0, ang = dir < 0 ? -0.5 : Math.PI + 0.5;
            ang += R.Range(-0.4, 0.4);
            for (int s = 0; s < 9; s++)
            {
                x += Math.Cos(ang) * 1.1;
                y += Math.Sin(ang) * 1.1;
                int px = (int)FX.Round(x), py = (int)FX.Round(y);
                if (!S.On(px, py)) break;
                ferns.Add((px, py, s / 9.0, i));
                if (s % 2 == 1)
                {
                    foreach (var side in (ReadOnlySpan<double>)[-1.0, 1.0])
                    {
                        double ba = ang + side * 1.05;
                        int L = 1 + (int)FX.Round(R.Range(0, 2) * (1 - s / 9.0));
                        for (int k = 1; k <= L; k++)
                        {
                            int bx = (int)FX.Round(x + Math.Cos(ba) * k), by = (int)FX.Round(y + Math.Sin(ba) * k);
                            if (S.On(bx, by)) ferns.Add((bx, by, (s + k * 0.6) / 9, i));
                        }
                    }
                }
                ang += R.Range(-0.25, 0.25);
            }
        }
        // icicles under the hair tips, the jaw and the hands: bottom edges with clear space under them
        int Clear(int x, int y)
        {
            var n = 0;
            while (n < 7 && y + 1 + n < S.H && !S.On(x, y + 1 + n)) n++;
            return n;
        }
        var hangs = S.Body.Where(b => !S.On(b.X, b.Y + 1) && S.On(b.X, b.Y - 1) && b.Y < H * 0.72 && b.Y > 4)
            .Select(b => (X: b.X, Y: b.Y, C: Clear(b.X, b.Y))).Where(h => h.C >= 4).ToList();
        (int X, int Y, int C)? Best(Func<(int X, int Y, int C), bool> f, Func<(int X, int Y, int C), (int X, int Y, int C), double> key)
        {
            var l = FX.JsSort(hangs.Where(f), key);
            return l.Count > 0 ? l[0] : null;
        }
        (int X, int Y, int C)?[] picks =
        [
            Best(h => h.Y < H * 0.36, (p, q) => p.X - q.X),
            Best(h => h.Y < H * 0.36, (p, q) => q.X - p.X),
            Best(h => h.Y >= H * 0.36 && h.Y < H * 0.5 && h.X < W / 2, (p, q) => q.X - p.X),
            Best(h => h.Y >= H * 0.36 && h.Y < H * 0.5 && h.X >= W / 2, (p, q) => p.X - q.X),
            Best(h => h.Y >= H * 0.5 && h.X < W / 2, (p, q) => p.X - q.X),
            Best(h => h.Y >= H * 0.5 && h.X >= W / 2, (p, q) => q.X - p.X),
        ];
        var icicles = new List<Icicle>();
        foreach (var pk in picks)
        {
            if (pk is not { } h) continue;
            var i = icicles.Count;
            var len = Math.Min(h.C - 1, R.Range(3, 5.5));
            icicles.Add(new Icicle(h.X, h.Y + 1, len, R.Next(), i % 2 != 0 ? 1 : 2));
        }
        // snow ledges: the upward edges of the head and the shoulders
        var snow = S.Up.Where(u => u.Y < H * 0.6).Select(u => (u.X, u.Y, D: 1 + (FX.Rand(u.X, seed, 3) < 0.45 ? 1 : 0))).ToList();
        var E = FXStatus.Eyes(a);
        var mouth = E.Count == 2 ? ((E[0].X1 + E[1].X0 + 1) / 2.0, (double)(Math.Max(E[0].Y1, E[1].Y1) + 2)) : (W / 2, H * 0.38);
        return new Plan(ferns, icicles, snow, mouth);
    });

    /// <summary>Frost on the floor round the feet: a white crust, a pale bloom under it, its edge creeping out and back.</summary>
    void Frost(Painter p, double t, double reach)
    {
        var C = this.C;
        for (var x = -FX.Ceil(reach) - 1; x <= reach + 1; x += 1)
        {
            double q = Math.Abs(x + 0.5) / reach, h = FX.Rand(x, 17), k = 1 - q * q;
            if (q > 1 + h * 0.15) continue;
            var tw = Math.Sin((t / D) * FX.Tau * 2 + FX.Rand(x, 3) * FX.Tau) > 0.94;
            p.Px(x, 0, tw || h < 0.3 ? C[7] : q > 0.85 ? C[5] : C[6]);
            if (h < 0.3 * k) p.Px(x, -1, C[6]);
            for (var j = 1.0; j <= 1 + FX.Round(2 * k); j += 1) p.Dot(x, j, j == 1 ? C[5] : C[4], (1.05 - j / 4) * 0.85);
        }
    }

    public void DrawBack(Painter p, double t)
    {
        var C = this.C;
        var reach = 13 + 3.5 * Math.Sin((t / D) * FX.Tau);
        p.Shade(-28, -3, 28, 6, (x, y, @out) =>
        {
            var d = FX.Hypot(x / 24, (y - 0.5) / 4);
            if (d < 1) { @out.L = C[4]; @out.K = 0.24 * (1 - d) * (1 - d); }
            return 0;
        });
        Frost(p, t, reach);
    }

    public void Draw(Painter p, double t)
    {
        var C = this.C;
        var a = o.Actor;
        var S = FXStatus.ShapeOf(a);
        double H = S.H, dx = Shake(t), ph = Since(t);
        var P = PlanOf(a, o.Seed);
        double ax = a.X, ay = a.Y;
        double X(double mx) => ax + mx + dx;
        double Y(double my) => ay + my;
        // the body, chilled: its colours pulled toward ice; the rim frosted and lit
        foreach (var (mx, my) in S.Body)
        {
            var c = FXStatus.ColorAt(a, mx, my);
            var ice = C[(int)FX.Clamp(1 + FX.Round(FX.Luma(c) * 5.6), 1, 7)];
            var rim = !S.On(mx - 1, my) || !S.On(mx, my - 1) || !S.On(mx + 1, my);
            p.Px(X(mx), Y(my), rim && FX.Luma(c) < 0.3 ? (my < H * 0.5 || !S.On(mx - 1, my) ? C[5] : C[3]) : FX.Mix(c, ice, 0.38));
        }
        // frost ferns creeping in from the outline; each shiver cracks most of it off and it creeps back
        var grow = 0.2 + 0.65 * FX.Smooth(0.05, 0.95, ph);
        foreach (var (x, y, u, _) in P.Ferns)
            if (u < grow) p.Px(X(x), Y(y), u > grow - 0.1 ? FX.White : FX.Rand(x, y, 5) < 0.5 ? C[6] : C[5]);
        // snow settled on the head and shoulders
        foreach (var (x, y, d) in P.Snow)
        {
            p.Px(X(x), Y(y) - 1, C[7]);
            if (d > 1) p.Px(X(x), Y(y) - 2, FX.Rand(x, y, 9) < 0.5 ? C[7] : C[6]);
        }
        // icicles hanging under the chin, hands and hair: they grow, a drop gathers and falls, they shrink back
        foreach (var ic in P.Icicles)
        {
            double per = ic.Period, u = FX.Mod(FX.Mod(t / per + ic.Phase, 1) + 1, 1), L = ic.Len * (0.55 + 0.45 * FX.Smooth(0, 0.7, u));
            double x = X(ic.X), y0 = Y(ic.Y);
            for (var j = 0.0; j < L; j += 1)
            {
                var v = j / L;
                p.Px(x, y0 + j, v > 0.75 ? FX.White : v < 0.3 ? C[7] : C[6]);
                if (v < 0.5) p.Px(x + 1, y0 + j, C[4]);
            }
            // the drop: it swells at the tip, lets go and falls to the floor
            if (u > 0.7 && u < 0.86) p.Px(x, y0 + L, C[6]);
            else if (u >= 0.86)
            {
                double f = (u - 0.86) * per, y = y0 + L + 0.5 * 760 * f * f;
                if (y < -1) { p.Px(x, y, C[6]); p.Px(x, y - 1, C[5]); }
            }
            p.Glow(x, y0 + L * 0.6, 4, C[5], 0.18);
        }
        // breath steaming from the mouth between shivers
        var (mx0, my0) = P.Mouth;
        for (int i = 0; i < 4; i++)
        {
            var age = ph - 0.35 - i * 0.05;
            if (age < 0 || age > 0.65) continue;
            double u = age / 0.65, x = X(mx0) + 1 + FXStatus.Travel(16, 0, 2.2, age) + i, y = Y(my0) - FXStatus.Travel(6, 3, 1, age) - i * 0.5;
            var rad = 0.8 + 2.4 * Math.Sqrt(u);
            p.Disc(x, y, rad, C[7], 0.5 * (1 - u) * Math.Min(1, u * 8));
            p.Disc(x - rad * 0.2, y - rad * 0.3, rad * 0.5, FX.White, 0.4 * (1 - u));
        }
        // snow falling and settling; flakes flung off by the shiver
        FX.Cycle(t, D, 9, o.Seed + 2, r => r.Range(1.2, 1.8), (age, _, r, _) =>
        {
            double x = r.Range(-14, 14) + Math.Sin(age * 3 + r.Next() * FX.Tau) * 1.5, y = ay - 16 + age * 14;
            if (y > ay + 2) return;
            p.Dot(x, y, r.Next() < 0.5 ? FX.White : C[6], Math.Min(1, age * 4));
        });
        if (ph < 0.5)
        {
            for (int i = 0; i < 8; i++)
            {
                double side = i % 2 != 0 ? 1 : -1;
                double vx = side * (20 + 30 * FX.Rand(i, 4)), vy = -(20 + 30 * FX.Rand(i, 5));
                double x = side * (6 + 6 * FX.Rand(i, 6)) + vx * ph, y = ay + 3 * FX.Rand(i, 7) + vy * ph + 0.5 * 300 * ph * ph;
                p.Dot(x, y, i % 3 != 0 ? C[6] : FX.White, 1.2 - ph * 2);
            }
        }
        if (ph < 0.25) FX.Sparkle(p, X(FX.Round(S.W * 0.3)), Y(4), FX.Round(3 * (1 - ph / 0.25)), C[6], C[5], 0.4);
        // cold light: off the body, lifting with each shiver
        p.Glow(0, ay + H * 0.45, 30, C[4], 0.2 + 0.12 * Math.Exp(-ph / 0.2));
        p.Glow(0, ay + 2, 16, C[5], 0.1);
    }
}

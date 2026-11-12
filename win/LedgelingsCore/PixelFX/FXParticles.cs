// Particles for the effects, ported from pixelfx (https://github.com/patch-gg/pixelfx, MIT): closed-form
// ones whose place is a function of their age (so a loop has no seam), and simulated ones that streak,
// bounce, swell and thin. pixelfx adapts the simulated kinds from Sprite Fusion's open-source pixel art VFX
// (https://www.spritefusion.com/pixel-art-vfx), MIT, Copyright (c) 2026 Hugo Duprez. Units are art pixels
// and seconds. This is the shared particle layer the creatures' moments and the seasons draw with.
// The Mac's twin is FXParticles.swift.

namespace Ledgelings.Core.PixelFX;

public static partial class FX
{
    public const double Gravity = 950.0;
    public static readonly (double X, double Y)[] Cross = [(1, 0), (-1, 0), (0, 1), (0, -1)];
    public static readonly (double X, double Y)[] Diag = [(1, 1), (1, -1), (-1, 1), (-1, -1)];
    public static readonly FXColor[] Hot = Ramp(["#fff3a6", "#ffe26b", "#ff8a2a", "#f2561d"]);
    /// <summary>Fire from white-hot to smouldering, and smoke from fresh to thin.</summary>
    public static readonly FXColor[] FireRamp = Ramp(["#ffffff", "#fff3a6", "#ffe26b", "#ffc23d", "#ff8a2a", "#f2561d", "#c9281f", "#8a1f17", "#4a1712"]);
    public static readonly FXColor[] SmokeRamp = Ramp(["#7b6f72", "#5d5660", "#433d48", "#2b2630", "#1a171e"]);
    public static FXColor RampAt(FXColor[] r, double t) => r[Math.Min(r.Length - 1, Math.Max(0, (int)Floor(t * r.Length)))];

    // Closed-form particles

    /// <summary>Where a particle is after t seconds, launched from (x, y) at (vx, vy), under gravity g and linear drag.</summary>
    public static (double X, double Y) Fly(double x, double y, double vx, double vy, double t, double g = 0, double drag = 0)
    {
        if (drag <= 0) return (x + vx * t, y + vy * t + 0.5 * g * t * t);
        double f = (1 - Math.Exp(-drag * t)) / drag, vt = g / drag;
        return (x + vx * f, y + vt * t + (vy - vt) * f);
    }
    /// <summary>Its velocity at t.</summary>
    public static (double X, double Y) FlyV(double vx, double vy, double t, double g = 0, double drag = 0)
    {
        if (drag <= 0) return (vx, vy + g * t);
        double e = Math.Exp(-drag * t), vt = g / drag;
        return (vx * e, vt + (vy - vt) * e);
    }
    /// <summary>n one-shot particles, each with its own repeatable generator.</summary>
    public static void Burst(int n, double seed, Action<Rng, int> fn)
    {
        for (int i = 0; i < n; i++) fn(Rng(seed, i), i);
    }
    /// <summary>Particles that repeat every <c>period</c> seconds: fn(age, life, r, i) for every live copy.</summary>
    public static void Cycle(double t, double period, int count, double seed, double life, Action<double, double, Rng, int> fn) =>
        Cycle(t, period, count, seed, _ => life, fn);
    public static void Cycle(double t, double period, int count, double seed, Func<Rng, double> life, Action<double, double, Rng, int> fn)
    {
        for (int i = 0; i < count; i++)
        {
            var g = Rng(seed, i, 911);
            var born = g.Next() * period;
            var L = life(g);
            var age = Mod(Mod(t - born, period) + period, period);
            while (age < L) { fn(age, L, Rng(seed, i), i); age += period; }
        }
    }
    /// <summary>Particles born at a steady rate between t0 and t1: fn(age, life, r, i) for every one alive at t.</summary>
    public static void Stream(double t, double t0, double t1, double rate, double seed, Func<Rng, double> life,
                              Action<double, double, Rng, int> fn)
    {
        var n = (int)Floor((Math.Min(t, t1) - t0) * rate);
        if (n < 0) return;
        for (int i = 0; i <= n; i++)
        {
            double born = t0 + i / rate;
            var g = Rng(seed, i, 911);
            var L = life(g);
            var age = t - born;
            if (age >= 0 && age < L) fn(age, L, Rng(seed, i), i);
        }
    }

    // Shapes

    /// <summary>A jagged lightning path by midpoint displacement; jag is how far a midpoint may move, as a share of its segment.</summary>
    public static List<(double X, double Y)> Bolt(Rng r, double x0, double y0, double x1, double y1, double jag = 0.22, int depth = 5)
    {
        var pts = new List<(double X, double Y)> { (x0, y0), (x1, y1) };
        for (int d = 0; d < depth; d++)
        {
            var next = new List<(double X, double Y)> { pts[0] };
            for (int i = 1; i < pts.Count; i++)
            {
                var (ax, ay) = pts[i - 1];
                var (bx, by) = pts[i];
                double dx = bx - ax, dy = by - ay, L = Hypot(dx, dy);
                double off = (r.Next() * 2 - 1) * jag * L, l = L == 0 ? 1 : L;
                next.Add(((ax + bx) / 2 + (-dy / l) * off, (ay + by) / 2 + (dx / l) * off));
                next.Add(pts[i]);
            }
            pts = next;
        }
        return pts;
    }
    /// <summary>Forks off a bolt path: count branches, each up to len px long.</summary>
    public static List<List<(double X, double Y)>> Forks(Rng r, IReadOnlyList<(double X, double Y)> path, int count = 3, double len = 20,
                                                         double jag = 0.3, double spread = 0.9)
    {
        var o = new List<List<(double X, double Y)>>();
        for (int k = 0; k < count; k++)
        {
            var i = 1 + (int)Floor(r.Next() * (path.Count - 2));
            var (x, y) = path[i];
            var (px, py) = path[i - 1];
            var a = Math.Atan2(y - py, x - px) + (r.Next() < 0.5 ? -1 : 1) * spread * (0.4 + 0.6 * r.Next());
            var l = len * (0.4 + 0.6 * r.Next());
            o.Add(Bolt(r, x, y, x + Math.Cos(a) * l, y + Math.Sin(a) * l, jag, 3));
        }
        return o;
    }
    /// <summary>A star: n points between radii r1 (tips) and r0 (inner corners).</summary>
    public static List<(double X, double Y)> Star(double cx, double cy, double r0, double r1, int n = 5, double rot = -Math.PI / 2) =>
        Enumerable.Range(0, n * 2).Select(i =>
        {
            double a = rot + (i * Math.PI) / n, r = i % 2 != 0 ? r0 : r1;
            return (cx + Math.Cos(a) * r, cy + Math.Sin(a) * r);
        }).ToList();
    /// <summary>A regular polygon with n sides.</summary>
    public static List<(double X, double Y)> Ngon(double cx, double cy, double r, int n = 6, double rot = 0) =>
        Enumerable.Range(0, n).Select(i => (cx + Math.Cos(rot + (i * Tau) / n) * r, cy + Math.Sin(rot + (i * Tau) / n) * r)).ToList();
    /// <summary>Positions of pos(t - i·dt) for i = 0..n-1, newest first.</summary>
    public static List<(double X, double Y)> Trail(Func<double, (double X, double Y)> pos, double t, int n, double dt) =>
        Enumerable.Range(0, n).Select(i => pos(Math.Max(0, t - i * dt))).ToList();

    // Glints, flares, bands

    /// <summary>A star glint: arms of length arm in c with tips in tip, a white heart, light.</summary>
    public static void Sparkle(Painter p, double x, double y, double arm, FXColor c, FXColor? tip = null, double k = 0.6)
    {
        var tp = tip ?? c;
        var n = (int)Round(arm);
        if (n < 1) return;
        double X = Floor(x), Y = Floor(y);
        for (int d = 1; d <= n; d++)
        {
            var cc = d > n * 0.6 ? tp : c;
            foreach (var (dx, dy) in Cross) p.Px(X + dx * d, Y + dy * d, cc);
        }
        if (n >= 3) foreach (var (dx, dy) in Diag) p.Px(X + dx, Y + dy, c);
        if (n >= 6) foreach (var (dx, dy) in Diag) p.Px(X + dx * 2, Y + dy * 2, tp);
        p.Px(X, Y, White);
        p.Glow(x, y, 4 + n * 2, c, k);
    }
    /// <summary>An 8-ray flare: long rays on the axes, shorter between, fading along their length. ramp dark to bright.</summary>
    public static void Flare(Painter p, double x, double y, double L, double k, FXColor[] R)
    {
        if (L < 1) return;
        var n = R.Length;
        for (int i = 0; i < 8; i++)
        {
            double an = (i * Math.PI) / 4, len = i % 4 == 0 ? L : i % 2 == 0 ? L * 0.6 : L * 0.3, ca = Math.Cos(an), sa = Math.Sin(an);
            for (double d = 0; d <= len; d += 0.5)
            {
                var u = d / len;
                p.Dot(x + ca * d, y + sa * d, u < 0.35 ? White : u < 0.7 ? R[n - 2] : R[n - 3], u < 0.6 ? 1 : k * 1.5 * (1 - u) + 0.2);
            }
        }
    }
    /// <summary>A ring on a tilted plane (sy squashes it), thickness th inward, alpha k, coloured by depth through the band;
    /// keep(angle) picks which part to draw, so the far half can go behind and the near half in front.</summary>
    public static void Band(Painter p, double cx, double cy, double r, double sy, double th, double k,
                            FXColor[] R, Func<double, bool>? keep = null, bool hot = false)
    {
        if (r <= 0 || k <= 0) return;
        int n = R.Length, m = (int)Ceil(r * Tau * 1.2);
        for (int j = 0; j < m; j++)
        {
            double ang = ((double)j / m) * Tau, ca = Math.Cos(ang), sa = Math.Sin(ang);
            if (keep != null && !keep(ang)) continue;
            for (var o = th; o >= 0; o -= 0.5)
            {
                var u = o / th;
                var c = u < 0.15 ? (hot ? White : R[n - 1]) : u < 0.4 ? R[n - 2] : u < 0.7 ? R[n - 3] : R[n - 4];
                p.Dot(cx + ca * (r - o), cy + sa * (r - o) * sy, c, k * (u < 0.4 ? 1.2 : 1.15 - u));
            }
        }
    }
}

// Simulated particles

/// <summary>Particle kinds, as pixelfx numbers them.</summary>
public enum FXKind { Spark = 0, Mote, Streak, Flake, Vapour, Dust, Star, Ember, Smoke, Fire, Brand, Grit }

/// <summary>Particle flags: smokes (a fire puff leaves smoke), big (bigger, slower smoke), back (drawn behind).</summary>
public static class FXFlag { public const int Smokes = 1, Big = 2, Back = 4; }

/// <summary>A particle system: spawn kinds, step them, draw "back" (the soft kinds) or "front" (the rest).</summary>
public sealed class FXParticles
{
    /// <summary>A struct, as in Swift: change one with <c>var p = List[i]; …; List[i] = p;</c>.</summary>
    public struct P
    {
        public FXKind K;
        public double X, Y, Vx, Vy, Life, Max;
        public FXColor Col;
        public double Size, Seed, Delay;
        public int Flag;
    }
    public readonly Rng R;
    public List<P> List = new();
    public double T;
    public Func<double, double> Ground;
    public FXColor[] Sparks;
    public FXColor? Haze;
    public Action<double, double>? OnLand;

    public FXParticles(Rng? rng = null, double seed = 1, Func<double, double>? ground = null, FXColor[]? sparks = null, FXColor? haze = null)
    {
        R = rng ?? new Rng(seed);
        Ground = ground ?? (_ => double.PositiveInfinity);
        Sparks = sparks ?? FX.Hot;
        Haze = haze;
    }
    public int Count => List.Count;

    /// <summary>delay: seconds before it appears; col 0 lets fire and smoke use their own ramps.</summary>
    public void Spawn(FXKind k, double x, double y, double vx, double vy, double life,
                      FXColor col = FX.White, double size = 1, double delay = 0, int flag = 0)
    {
        List.Add(new P { K = k, X = x, Y = y, Vx = vx, Vy = vy, Life = life, Max = life, Col = col, Size = size, Seed = R.Next() * 100, Delay = delay, Flag = flag });
    }

    static bool Soft(FXKind k) => k == FXKind.Vapour || k == FXKind.Dust || k == FXKind.Smoke;

    public void Update(double dt)
    {
        T += dt;
        var R = this.R;
        var t = T;
        for (int i = List.Count - 1; i >= 0; i--)
        {
            var p = List[i];
            if (p.Delay > 0) { p.Delay -= dt; List[i] = p; continue; }
            p.Life -= dt;
            if (p.Life <= 0)
            {
                if (p.K == FXKind.Fire && (p.Flag & FXFlag.Smokes) != 0)
                {
                    var big = (p.Flag & FXFlag.Big) != 0;
                    Spawn(FXKind.Smoke, p.X, p.Y, p.Vx * 0.6, p.Vy * 0.6 - 6, big ? R.Range(1.3, 2.3) : R.Range(0.8, 1.4), 0, p.Size * (big ? 0.85 : 0.7), 0, big ? FXFlag.Big : 0);
                }
                List.RemoveAt(i);
                continue;
            }
            switch (p.K)
            {
                case FXKind.Fire:
                    p.Vy -= 95 * dt;
                    p.Vx += Math.Sin(t * 17 + p.Seed) * 30 * dt;
                    p.Vx -= p.Vx * 5 * dt;
                    p.Vy -= p.Vy * 3.2 * dt;
                    break;
                case FXKind.Grit:
                {
                    p.Vy += FX.Gravity * dt;
                    p.Vx -= p.Vx * 0.8 * dt;
                    double g = Ground(p.X), ny = p.Y + p.Vy * dt;
                    p.X += p.Vx * dt;
                    if (p.Vy > 0 && p.Y <= g && ny >= g)
                    {
                        p.Y = g - 0.25;
                        if (p.Vy > 130 && R.Chance(0.4)) { p.Vy = -p.Vy * 0.25; p.Vx = p.Vx * 0.5 + R.Range(-10, 10); }
                        else { p.Vx = 0; p.Vy = 0; p.Life = Math.Min(p.Life, 0.5); }
                    }
                    else p.Y = ny;
                    List[i] = p;
                    continue;
                }
                case FXKind.Brand:
                {
                    p.Vy += FX.Gravity * 0.8 * dt;
                    p.Vx -= p.Vx * 0.9 * dt;
                    List[i] = p;
                    if (R.Chance(0.9 * Math.Min(1, dt * 60)))
                    {
                        Spawn(FXKind.Fire, p.X, p.Y, p.Vx * 0.1 + R.Range(-7, 7), p.Vy * 0.1 - 10, R.Range(0.16, 0.32), 0,
                              R.Range(0.9, 1.7) * (0.5 + (p.Life / p.Max) * 0.6), 0, R.Chance(0.4) ? FXFlag.Smokes : 0);
                    }
                    double g = Ground(p.X), ny = p.Y + p.Vy * dt;
                    p.X += p.Vx * dt;
                    if (p.Vy > 0 && p.Y <= g && ny >= g)
                    {
                        OnLand?.Invoke(p.X, g);
                        List.RemoveAt(i);
                    }
                    else { p.Y = ny; List[i] = p; }
                    continue;
                }
                case FXKind.Spark:
                {
                    p.Vy += FX.Gravity * 0.45 * dt;
                    p.Vx -= p.Vx * 2.2 * dt;
                    p.Vy -= p.Vy * 2.2 * dt;
                    double g = Ground(p.X), ny = p.Y + p.Vy * dt;
                    p.X += p.Vx * dt;
                    if (p.Vy > 0 && p.Y <= g && ny >= g) { p.Vy = -p.Vy * 0.45; p.Vx *= 0.7; p.Y = g - 0.25; }
                    else p.Y = ny;
                    List[i] = p;
                    continue;
                }
                case FXKind.Streak:
                    p.Vx += p.Vx * 3 * dt; p.Vy += p.Vy * 3 * dt;
                    break;
                case FXKind.Flake:
                    p.Vx -= p.Vx * 2.2 * dt;
                    p.Vy -= p.Vy * 2.2 * dt - 35 * dt;
                    p.X += Math.Sin(T * 2.5 + p.Seed) * 7 * dt;
                    break;
                case FXKind.Ember:
                    p.Vy += (-30 + Math.Sin(t * 3 + p.Seed) * 20) * dt;
                    p.Vx += Math.Cos(t * 2.3 + p.Seed) * 45 * dt;
                    p.Vx -= p.Vx * 1.6 * dt;
                    p.Vy -= p.Vy * 1.6 * dt;
                    break;
                case FXKind.Smoke:
                {
                    var big = (p.Flag & FXFlag.Big) != 0;
                    p.Vy -= (big ? 23 : 16) * dt;
                    p.Vx += Math.Sin(t * 1.3 + p.Seed) * 8 * dt;
                    p.Vx -= p.Vx * 1.6 * dt;
                    p.Vy -= p.Vy * 1.2 * dt;
                    break;
                }
                case FXKind.Mote:
                    p.Vx -= p.Vx * 0.6 * dt; p.Vy -= p.Vy * 0.6 * dt;
                    break;
                default:
                {
                    var drag = Soft(p.K) ? 4.0 : 1.6;
                    p.Vx -= p.Vx * drag * dt;
                    p.Vy -= p.Vy * drag * dt + 5 * dt;
                    break;
                }
            }
            p.X += p.Vx * dt;
            p.Y += p.Vy * dt;
            List[i] = p;
        }
    }

    public void Draw(Painter p, FXLayer? layer)
    {
        var t = T;
        foreach (var q in List)
        {
            if (q.Delay > 0) continue;
            if (layer is { } l && (Soft(q.K) || (q.Flag & FXFlag.Back) != 0 ? FXLayer.Back : FXLayer.Front) != l) continue;
            double k = q.Life / q.Max, x = q.X, y = q.Y, h = FX.Hypot(q.Vx, q.Vy), sp = h == 0 ? 1 : h, ux = q.Vx / sp, uy = q.Vy / sp;
            switch (q.K)
            {
                case FXKind.Spark:
                {
                    var S = Sparks;
                    var head = k > 0.6 ? S[0] : k > 0.3 ? S[1] : S[2];
                    var len = Math.Min(9, 1 + sp * 0.022);
                    p.Line(x - ux * len, y - uy * len, x - ux * len * 0.4, y - uy * len * 0.4, k > 0.5 ? head : S[^1]);
                    p.Line(x - ux * len * 0.45, y - uy * len * 0.45, x, y, head);
                    p.Glow(x, y, 3, head, 0.45 * k);
                    break;
                }
                case FXKind.Mote:
                {
                    double len = Math.Min(16, 0.5 + sp * 0.026) * q.Size, a = k < 0.35 ? k / 0.35 : 1;
                    p.Line(x - ux * len, y - uy * len, x - ux * len * 0.35, y - uy * len * 0.35, FX.Scale(q.Col, 0.55), a);
                    p.Line(x - ux * len * 0.4, y - uy * len * 0.4, x, y, q.Col, a);
                    p.Glow(x, y, 2.5 + q.Size, q.Col, 0.4 * k);
                    break;
                }
                case FXKind.Streak:
                {
                    var L = FX.Clamp(sp / 30, 1, 7);
                    for (var d = L; d >= 0; d -= 0.5)
                        p.Dot(x - ux * d, y - uy * d, d < 1 ? FX.White : d < L * 0.5 ? q.Col : FX.Scale(q.Col, 0.6), d < L * 0.5 ? 1 : 1.2 - d / L);
                    p.Glow(x, y, 4, q.Col, 0.4);
                    break;
                }
                case FXKind.Flake:
                {
                    var a = Math.Min(1, k * 3);
                    p.Dot(x, y, q.Col, a);
                    if (q.Size > 1.3) foreach (var (dx, dy) in FX.Cross) p.Dot(x + dx, y + dy, FX.Scale(q.Col, 0.8), a * 0.8);
                    break;
                }
                case FXKind.Vapour:
                {
                    var r = q.Size * (0.6 + (1 - k) * 0.9);
                    p.Disc(x, y, r, q.Col, Math.Pow(k, 1.3) * 0.45);
                    if (Haze is { } haze) p.Glow(x, y, r * 1.8, haze, 0.16 * k);
                    break;
                }
                case FXKind.Dust:
                    p.Disc(x, y, q.Size * (0.6 + (1 - k) * 0.9), q.Col, Math.Pow(k, 1.3) * 0.7);
                    break;
                case FXKind.Smoke:
                {
                    var age = 1 - k;
                    var big = (q.Flag & FXFlag.Big) != 0;
                    var r = q.Size * (0.65 + Math.Min(1, age * 2.5) * 0.45 + age * (big ? 0.5 : 0.4));
                    var a = Math.Min(1, age * 12) * Math.Min(1, k * 2.4) * (big ? 0.7 : 0.58);
                    var c = q.Col != 0 ? FX.Mix(q.Col, FX.RampAt(FX.SmokeRamp, age), age) : FX.RampAt(FX.SmokeRamp, age * 1.05);
                    p.Disc(x, y, r, c, a * 0.45);
                    p.Disc(x + r * 0.05, y + r * 0.06, r * 0.74, c, a * 0.62);
                    if (age < 0.5) p.Disc(x - r * 0.22, y - r * 0.3, r * 0.5, FX.Mix(c, FX.White, 0.12), a * 0.4 * (1 - age * 2));
                    break;
                }
                case FXKind.Fire:
                {
                    var age = 1 - k;
                    var heat = Math.Min(0.999, Math.Pow(age, 0.62) + FX.Mod(q.Seed, 1) * 0.1);
                    var F = FX.FireRamp;
                    var n = F.Length;
                    var idx = Math.Min(n - 2, (int)FX.Floor(heat * (n - 1)));
                    var r = q.Size * (0.55 + 0.45 * Math.Min(1, age * 7)) * (1 - age * 0.55);
                    var c = F[idx];
                    if (idx >= n - 2) p.Disc(x, y, r, c, Math.Min(1, k * 3) * 0.85);
                    else
                    {
                        p.Circle(x, y, r, F[Math.Min(n - 1, idx + 2)]);
                        p.Circle(x - r * 0.16, y - r * 0.22, r * 0.78, c);
                        if (r > 1.6) p.Circle(x, y - r * 0.9, r * 0.42, c);
                        if (idx <= 3 && r > 1.8) p.Circle(x - r * 0.28, y - r * 0.34, r * 0.36, F[Math.Max(0, idx - 1)]);
                        if (idx < 6) p.Glow(x, y, r * 2.4 + 2, c, 0.18 * k);
                    }
                    break;
                }
                case FXKind.Brand:
                    p.Circle(x, y, 1.6, FX.Hot[3]);
                    p.Px(x, y, Math.Sin(t * 40 + q.Seed) > 0 ? FX.Hot[0] : FX.Hot[1]);
                    p.Px(x + 1, y, FX.Hot[1]);
                    p.Glow(x, y, 7, FX.Hot[2], 0.45);
                    break;
                case FXKind.Grit:
                    if (k > 0.25 || k * 4 > 0.5)
                    {
                        p.Px(x, y, q.Col);
                        if (q.Size >= 2) { p.Px(x + 1, y, q.Col); p.Px(x, y + 1, FX.Scale(q.Col, 0.8)); p.Px(x + 1, y + 1, FX.Scale(q.Col, 0.7)); }
                    }
                    break;
                case FXKind.Ember:
                {
                    var c = k > 0.6 ? Sparks[0] : k > 0.3 ? Sparks[1] : Sparks[2];
                    if (k < 0.25 && Math.Sin(t * 40 + q.Seed) < 0) break;
                    p.Px(x, y, c);
                    if (q.Size > 1.5) p.Px(x, y + 1, Sparks[^1]);
                    p.Glow(x, y, 3 + q.Size, c, 0.35 * k);
                    break;
                }
                case FXKind.Star:
                {
                    var tw = 0.6 + 0.4 * Math.Sin(t * (8 + FX.Mod(q.Seed, 5)) + q.Seed);
                    if (q.Size < 1)
                    {
                        if (tw * k > 0.25) p.Px(x, y, tw > 0.8 ? FX.White : q.Col);
                        p.Glow(x, y, 3, q.Col, 0.4 * k * tw);
                        break;
                    }
                    FX.Sparkle(p, x, y, q.Size * tw * Math.Min(1, k * 3), q.Col, FX.Scale(q.Col, 0.75), 0.5 * k * tw);
                    break;
                }
            }
        }
    }
}

/// <summary>Little fires burning where something landed: they feed fire puffs into a particle system.</summary>
public sealed class FXBlazes(FXParticles ps)
{
    public struct Blaze { public double X, Y, Life, Max, Acc, Power; }
    public readonly FXParticles Ps = ps;
    public List<Blaze> List = new();
    public int Count => List.Count;
    public void Add(double x, double y, double life, double power) =>
        List.Add(new Blaze { X = x, Y = y, Life = life, Max = life, Acc = Ps.R.Next(), Power = power });
    public void Update(double dt)
    {
        var R = Ps.R;
        for (int i = List.Count - 1; i >= 0; i--)
        {
            var b = List[i];
            b.Life -= dt;
            if (b.Life <= 0) { List.RemoveAt(i); continue; }
            double k = b.Life / b.Max, intensity = b.Power * (k > 0.7 ? 1 : 0.35 + (k / 0.7) * 0.65);
            b.Acc += dt * (6 + 16 * intensity);
            while (b.Acc > 1)
            {
                var s = R.Range(1.2, 2.8) * intensity;
                Ps.Spawn(FXKind.Fire, b.X + R.Range(-1.5, 1.5), b.Y - s * 0.6, R.Range(-6, 6), R.Range(-30, -12), R.Range(0.28, 0.6), 0, s, 0,
                         FXFlag.Back | (R.Chance(0.3) ? FXFlag.Smokes : 0));
                if (R.Chance(0.06)) Ps.Spawn(FXKind.Ember, b.X, b.Y - 1.5, R.Range(-15, 15), R.Range(-45, -15), R.Range(0.6, 1.4), FX.Hot[2], 1, 0, FXFlag.Back);
                b.Acc -= 1;
            }
            List[i] = b;
        }
    }
    public void DrawBack(Painter p)
    {
        foreach (var b in List)
        {
            var k = b.Life / b.Max;
            p.Px(b.X, b.Y, k > 0.4 ? (Math.Sin(b.Life * 31 + b.X) > 0 ? FX.Hot[1] : FX.Hot[2]) : FX.Hot[3]);
            p.Glow(b.X, b.Y, 6 + 5 * k * b.Power, FX.Hot[2], 0.3 * k * b.Power);
        }
    }
}

/// <summary>Rigid debris that tumbles, bounces and settles.</summary>
public sealed class FXBits(Func<double, double>? ground = null)
{
    public enum Kind { Shard, Chunk, Drip }
    /// <summary>A struct, as in Swift; <c>new Bit()</c> and <c>new Bit { … }</c> start from the same defaults.</summary>
    public struct Bit
    {
        public Kind Kind = Kind.Shard;
        public double X, Y, Vx, Vy, A, Va, S = 1;
        public FXColor C = FX.White;
        public FXColor[]? Ramp;
        public double G = 1, Drag, Bounce;
        public bool Rest;
        public double Life = 1, Max = 1;
        public Bit() { }
        public Bit(Kind kind = Kind.Shard, double x = 0, double y = 0, double vx = 0, double vy = 0, double a = 0, double va = 0,
                   double s = 1, FXColor c = FX.White, FXColor[]? ramp = null, double g = 1, double drag = 0, double bounce = 0, double life = 1)
        {
            Kind = kind; X = x; Y = y; Vx = vx; Vy = vy; A = a; Va = va; S = s;
            C = c; Ramp = ramp; G = g; Drag = drag; Bounce = bounce; Life = life; Max = life;
        }
    }
    public List<Bit> List = new();
    public Func<double, double> Ground = ground ?? (_ => double.PositiveInfinity);
    public int Count => List.Count;
    public void Add(Bit b) { b.Max = b.Life; List.Add(b); }
    public void Update(double dt)
    {
        for (int i = List.Count - 1; i >= 0; i--)
        {
            var b = List[i];
            b.Life -= dt;
            if (b.Life <= 0) { List.RemoveAt(i); continue; }
            if (b.Rest) { List[i] = b; continue; }
            b.Vy += FX.Gravity * b.G * dt;
            b.Vx -= b.Vx * b.Drag * dt;
            b.Vy -= b.Vy * b.Drag * dt;
            b.X += b.Vx * dt;
            b.Y += b.Vy * dt;
            b.A += b.Va * dt;
            double floor = Ground(b.X), sp = b.Vy;
            if (b.G <= 0 || b.Y < floor || sp <= 0) { List[i] = b; continue; }
            b.Y = floor - 0.01;
            if (b.Kind == Kind.Drip) b.Life = 0;
            else if (b.Bounce > 0 && sp > 70) { b.Vy = -sp * b.Bounce; b.Vx *= 0.7; b.Va *= 0.6; }
            else { b.Rest = true; b.Vx = 0; b.Vy = 0; }
            List[i] = b;
        }
    }
    static readonly FXColor[] ChunkRamp = FX.Ramp(["#1c2030", "#3a4a66", "#6e86a8", "#a8c0dc", "#e8f2ff"]);
    public void Draw(Painter p)
    {
        foreach (var b in List)
        {
            double a = Math.Min(1, b.Life / 0.4), ca = Math.Cos(b.A), sa = Math.Sin(b.A);
            switch (b.Kind)
            {
                case Kind.Shard:
                    for (var d = -b.S / 2; d <= b.S / 2; d += 0.5) p.Dot(b.X + ca * d, b.Y + sa * d, d > b.S / 2 - 0.6 ? FX.White : b.C, a);
                    break;
                case Kind.Drip:
                    p.Dot(b.X, b.Y, b.C, a);
                    p.Dot(b.X, b.Y - 1, b.C, a * 0.5);
                    break;
                case Kind.Chunk:
                {
                    var R = b.Ramp ?? ChunkRamp;
                    var n = R.Length;
                    double x = FX.Round(b.X), y = FX.Round(b.Y);
                    var r = (int)FX.Ceil(b.S) + 1;
                    for (int py = -r; py <= r; py++)
                    {
                        for (int px = -r; px <= r; px++)
                        {
                            double u = (px + 0.5) * ca + (py + 0.5) * sa, v = -(px + 0.5) * sa + (py + 0.5) * ca;
                            var d = Math.Abs(u) / b.S + Math.Abs(v) / (b.S * 0.62);
                            if (d > 1.3) continue;
                            p.Dot(x + px, y + py, d > 1 ? R[0] : v < 0 ? (u < 0 ? R[n - 1] : R[n - 2]) : u < 0 ? R[n - 3] : R[Math.Max(1, n - 4)], a);
                        }
                    }
                    break;
                }
            }
        }
    }
}

/// <summary>Lights that flare and die.</summary>
public sealed class FXLights
{
    public struct Light { public double X, Y, R; public FXColor Color; public double K, Life, Max; }
    public List<Light> List = new();
    public void Add(double x, double y, double r, FXColor color, double k, double life) =>
        List.Add(new Light { X = x, Y = y, R = r, Color = color, K = k, Life = life, Max = life });
    public void Update(double dt)
    {
        for (int i = List.Count - 1; i >= 0; i--)
        {
            var l = List[i];
            l.Life -= dt;
            if (l.Life <= 0) List.RemoveAt(i); else List[i] = l;
        }
    }
    public void Draw(Painter p)
    {
        foreach (var l in List)
        {
            var k = l.Life / l.Max;
            p.Glow(l.X, l.Y, l.R * (0.55 + 0.45 * k), l.Color, l.K * k * k);
        }
    }
}

// Fireflies wander over a meadow at night, each glowing up and fading on its own rhythm, trailing light and
// lighting the grass tips beneath them. pixelfx's `weather/fireflies` (MIT), the firefly adapted from Sprite
// Fusion's open-source fireflies (https://www.spritefusion.com/pixel-art-vfx/fireflies, MIT, Hugo Duprez).
// The Mac's twin is Fireflies.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXFireflies : IFXEffect, IFXBackdropped
{
    public static readonly FXMeta Meta = new("weather/fireflies", size: (320, 180), origin: (160, 170), duration: 12, loop: true,
                                             palette: ["#2a3a10", "#5a7a1a", "#9ad02a", "#d6ff5a", "#f4ffb8", "#ffffff"], seed: 2);
    const double D = 12.0;
    static readonly FXColor[] GrassRamp = FX.Fit(FX.Ramp(["#070f0b", "#0c1a12", "#13281a", "#1d3a24", "#2b5232", "#3f6e40"]), 6);
    static readonly double[] DepthK = [0.5, 0.8, 1];
    static readonly (double X, double Y)[] Glints = [(0, -2), (0, 2), (-2, 0), (2, 0)];

    readonly FXOptions o;
    readonly FXColor[] C, G;
    /// <summary>false: no night haze over the whole canvas (drawn over the desktop); the grass and the fireflies stay.</summary>
    public bool Backdrop { get; set; } = true;
    public FXFireflies(FXOptions o) { this.o = o; C = FX.Fit(o.Palette, 6); G = GrassRamp; }

    static double Cyc(double t, double n, double ph = 0) => (FX.Tau * n * t) / D + ph;

    /// <summary>A firefly's path and glow, both whole cycles a loop. Depth 0 far..2 near.</summary>
    readonly record struct Fly(double I, int Depth, double K, double Cx, double Cy, double Ax, double Ay, double N1, double N2, double P1, double P2, double Glow)
    {
        public (double X, double Y) Pos(double tt) =>
            (Cx + Ax * Math.Sin(Cyc(tt, N1, P1)) + 10 * K * FX.LoopNoise(tt / D, 1.5, I * 3),
             Cy + Ay * Math.Sin(Cyc(tt, N2, P2)) + 6 * K * FX.LoopNoise(tt / D, 1.5, I * 3 + 1));
    }
    static Fly MakeFly(double S, int i, double t)
    {
        double R(double n) => FX.Rand(S, i, n);
        int depth = i < 14 ? 0 : i < 26 ? 1 : 2;
        var k = DepthK[depth];
        double cx = -150 + R(1) * 300, cy = -16 - R(2) * (depth == 2 ? 70 : 130);
        double ax = (14 + R(3) * 26) * k, ay = (8 + R(4) * 14) * k, n1 = 1 + FX.Floor(R(5) * 2), n2 = 1 + FX.Floor(R(6) * 3);
        // its rhythm: a quick rise, a hold, a slow fade, dark; some flash twice
        double per = D / (3 + FX.Floor(R(9) * 4)), u = FX.Mod(FX.Mod(t / per + R(10), 1) + 1, 1);
        var two = R(11) < 0.35;
        static double Pulse(double v) => v < 0.06 ? v / 0.06 : v < 0.14 ? 1 : v < 0.4 ? 1 - (v - 0.14) / 0.26 : 0;
        var glow = Math.Max(Pulse(u), two ? Pulse(u - 0.22) * 0.8 : 0);
        return new Fly(i, depth, k, cx, cy, ax, ay, n1, n2, R(7) * FX.Tau, R(8) * FX.Tau, glow);
    }

    public void DrawBack(Painter p, double t)
    {
        var q = new FXWeather.Clip(p, Meta);
        var S = o.Seed;
        var G = this.G;
        // a cool night haze, so the sky's stars don't read as fireflies
        if (Backdrop)
            FXWeather.Rows(p, Meta, -170, 9, (y, R) =>
            {
                var k = (y + 170) / 180;
                R.Fill(FX.Mix(G[0], G[1], k), 0.48 + 0.14 * k, blend: true);
            });
        var flies = new Fly[32];
        for (int i = 0; i < 32; i++) flies[i] = MakeFly(S, i, t);
        Grass(q, t, S, flies, false);
        foreach (var f in flies) if (f.Depth < 2) Firefly(q, t, f);
    }

    public void Draw(Painter p, double t)
    {
        var q = new FXWeather.Clip(p, Meta);
        var S = o.Seed;
        var flies = new Fly[32];
        for (int i = 0; i < 32; i++) flies[i] = MakeFly(S, i, t);
        Grass(q, t, S, flies, true);
        foreach (var f in flies) if (f.Depth == 2) Firefly(q, t, f);
    }

    void Firefly(FXWeather.Clip q, double t, Fly f)
    {
        var C = this.C;
        var (x, y) = f.Pos(t);
        double g = f.Glow, X = FX.Round(x), Y = FX.Round(y);
        if (f.Depth == 0)
        {
            if (g < 0.08) return;
            q.Dot(X, Y, g > 0.6 ? C[4] : C[3], Math.Min(1, g * 1.6));
            q.Glow(x, y, 6, C[2], 0.45 * g);
            return;
        }
        // a short trail of light where it has just been, while it's lit
        if (g > 0.3)
            for (int j = 1; j <= 4; j++)
            {
                var (tx, ty) = f.Pos(t - j * 0.05);
                q.Dot(tx, ty, C[2], (g - 0.3) * (1 - j / 5.0) * 1.3);
            }
        if (f.Depth == 1)
        {
            q.Px(X, Y, g > 0.5 ? C[5] : g > 0.15 ? C[3] : C[1]);
            if (g > 0.4) q.Px(X, Y + 1, C[2]);
            q.Glow(x, y, 9, C[2], 0.5 * g);
            q.Glow(x, y, 3, C[4], 0.5 * g);
            return;
        }
        // a close one: a dark body, wings a blur above it, a lantern at its tail; a glint at the peak
        var nx = f.Pos(t + 0.05).X;
        double dir = nx >= x ? 1 : -1, beat = FX.Mod(FX.Floor(t * 30), 2);
        var wing = FX.Mix(C[1], FX.White, 0.4);
        q.Px(X + dir, Y, C[0]);
        q.Px(X + dir * 2, Y, C[0]);
        q.Dot(X, Y - 1 - beat, wing, 0.7);
        q.Dot(X + dir, Y - 1 - beat, wing, 0.7);
        q.Px(X, Y, g > 0.3 ? C[5] : C[1]);
        q.Px(X - dir, Y, g > 0.5 ? C[4] : g > 0.15 ? C[3] : C[1]);
        if (g > 0.6) q.Px(X - dir, Y + 1, C[3]);
        if (g > 0.7) foreach (var (dx, dy) in Glints) q.Dot(X - dir + dx, Y + dy, C[3], (g - 0.7) * 3);
        q.Glow(x, y, 28, C[2], 0.45 * g);
        q.Glow(x, y, 10, C[4], 0.5 * g);
        q.Glow(x, y, 4, C[5], 0.5 * g);
    }

    /// <summary>The meadow: blades in two rows (the front row drawn over the low fireflies), swaying as the breeze rolls
    /// across, a few seed heads; blade tips near a lit firefly catch its light.</summary>
    void Grass(FXWeather.Clip q, double t, double S, Fly[] flies, bool front)
    {
        var C = this.C;
        var G = this.G;
        var lit = new List<(double X, double Y, double G)>();
        foreach (var f in flies)
            if (f.Glow > 0.25 && f.Depth > 0) { var (fx, fy) = f.Pos(t); lit.Add((fx, fy, f.Glow)); }
        int n = front ? 150 : 230;
        var sd = S * 3 + (front ? 1 : 0);
        for (int i = 0; i < n; i++)
        {
            double R(double k) => FX.Rand(sd, i, k);
            double x = -162 + (i + R(1)) * (324.0 / n), h = (front ? 4 : 5) + R(2) * (front ? 8 : 11) + (R(3) < 0.1 ? 6 : 0);
            var @base = (front ? 9 : 2) - R(4) * 3;
            var sway = (1.2 + R(5)) * Math.Sin(Cyc(t, 2, -x * 0.03) + R(6)) + 0.6 * Math.Sin(Cyc(t, 5, x * 0.07));
            int tone = front ? 1 + (int)FX.Floor(R(7) * 3) : 1 + (int)FX.Floor(R(7) * 2);
            var tipLight = 0.0;
            foreach (var (fx, fy, g) in lit)
            {
                var d = FX.Hypot(fx - (x + sway), fy - (@base - h));
                if (d < 28) tipLight = Math.Max(tipLight, g * (1 - d / 28));
            }
            for (var r = 0.0; r < h; r += 1)
            {
                var u = r / h;
                var c = u > 0.8 && tipLight > 0.2 ? (tipLight > 0.55 && u > 0.9 ? C[3] : C[2]) : u > 0.7 ? G[Math.Min(5, tone + 1)] : G[tone];
                q.Px(x + sway * u * u, @base - r, c);
            }
            if (R(8) < 0.07)
            {
                double sx = x + sway, sy = @base - h;
                q.Px(sx, sy - 1, tipLight > 0.2 ? C[3] : G[5]);
                q.Px(sx - 1, sy, G[4]);
                q.Px(sx + 1, sy, G[4]);
            }
        }
    }
}

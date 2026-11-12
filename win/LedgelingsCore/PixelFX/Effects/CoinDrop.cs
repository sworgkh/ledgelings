// An enemy goes up in a soft poof and gold coins spin out of it, bounce with a glint on each hit, settle on the
// floor, twinkle, and wink out one by one. pixelfx's `spawn/coin-drop` (MIT), after Sprite Fusion's open-source
// pickup (https://www.spritefusion.com/pixel-art-vfx/pickup), MIT, Copyright (c) 2026 Hugo Duprez.
// The Mac's twin is CoinDrop.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXCoinDrop : IFXEffect
{
    public static readonly FXMeta Meta = new("spawn/coin-drop", size: (160, 88), origin: (80, 78), duration: 3, loop: false,
                                             palette: ["#2a1606", "#5c3208", "#9a5a0c", "#d48c14", "#f5b82a", "#ffe066", "#fff6c4", "#ffffff"], seed: 23);
    static readonly string[] Smoke = ["#3a3450", "#6c6688", "#a8a2c0", "#dcd8ea"];
    const int CoinCount = 7;
    const double CY = -16.0;
    // an original coin: a rim, a lit face, a raised mark in the middle
    static readonly string[] COIN = ["..oooo..", ".ohhlmo.", "ohlmmmdo", "ohmdhmdo", "olmdhmdo", "olmmmmdo", ".oddddo.", "..oooo.."];
    // lying flat on the floor, seen from the side
    static readonly string[] FLAT = [".lhhhl.", "olmmmdo", ".odddo."];

    struct Ball { public double X, Y, Vx, Vy, R, Life, Max; }
    struct Coin
    {
        public double X, Y, Vx, Vy, Ph, W;
        public bool Rest, Gone;
        public int Hits;
        public double Out, Glint, Born, RestAt;
    }

    readonly FXOptions o;
    readonly FXColor[] C, SM;
    readonly Dictionary<char, FXColor> PAL;
    readonly Rng R;
    readonly FXParticles ps;
    readonly FXLights lights = new();
    readonly List<Coin> coins = new();
    readonly List<Ball> balls = new();
    double t;

    public FXCoinDrop(FXOptions o)
    {
        this.o = o;
        var C = FX.Fit(o.Palette, 8);
        var R = new Rng(o.Seed);
        this.C = C; this.R = R;
        SM = FX.Fit(FX.Ramp(Smoke), 4);
        PAL = new() { ['o'] = C[1], ['h'] = C[6], ['l'] = C[5], ['m'] = C[4], ['d'] = C[3] };
        ps = new FXParticles(rng: R, ground: _ => 0, sparks: [FX.White, C[6], C[5], C[3]]);
        // the poof the enemy goes up in
        for (int i = 0; i < 10; i++)
        {
            double a = (i / 10.0) * FX.Tau + R.Range(-0.25, 0.25), sp = R.Range(60, 100);
            var life = R.Range(0.55, 0.85);
            balls.Add(new Ball { X = Math.Cos(a) * 2, Y = CY + Math.Sin(a) * 2, Vx = Math.Cos(a) * sp, Vy = Math.Sin(a) * sp * 0.7 - 10, R = R.Range(4, 6), Life = life, Max = life });
        }
        // the coins: thrown up and out, each spinning at its own rate
        const int n = CoinCount;
        for (int i = 0; i < n; i++)
        {
            double u = n > 1 ? (double)i / (n - 1) - 0.5 : 0, a = -Math.PI / 2 + u * 1.6 + R.Range(-0.1, 0.1), sp = R.Range(230, 300);
            double x = R.Range(-3, 3), ph = R.Range(0, FX.Tau), w = R.Range(9, 15) * R.Sign();
            double @out = 2.15 + i * 0.07 + R.Range(0, 0.1), glint = R.Range(1.2, 1.9), born = R.Range(0.04, 0.12);
            coins.Add(new Coin { X = x, Y = CY, Vx = Math.Cos(a) * sp * 0.4, Vy = Math.Sin(a) * sp, Ph = ph, W = w, Out = @out, Glint = glint, Born = born });
        }
        for (int i = 0; i < 8; i++)
        {
            double a = R.Range(0, FX.Tau), sp = R.Range(50, 120);
            ps.Spawn(FXKind.Star, 0, CY, Math.Cos(a) * sp, Math.Sin(a) * sp - 20, R.Range(0.3, 0.6), R.Pick([FX.White, C[6], C[5]]), R.Range(0.8, 1.8));
        }
        lights.Add(0, CY, 44, C[4], 0.7, 0.4);
        lights.Add(0, CY, 20, FX.White, 0.7, 0.1);
    }

    /// <summary>A coin turning in the air: its face squashed toward the edge, the rim showing when it's side-on.</summary>
    void DrawCoin(Painter p, double x, double y, double ph)
    {
        var C = this.C;
        double c = Math.Cos(ph), sx = Math.Abs(c);
        if (sx < 0.28)
        {
            for (int dy = -3; dy <= 3; dy++) p.Px(x, y + dy, Math.Abs(dy) == 3 ? C[1] : dy < 0 ? C[6] : C[5]);
            if (sx > 0.12) for (int dy = -2; dy <= 2; dy++) p.Px(x + (c > 0 ? 1 : -1), y + dy, C[3]);
            return;
        }
        var half = 4 * sx;
        for (var px = FX.Floor(x - half); px < FX.Ceil(x + half); px++)
        {
            var col = (int)FX.Floor((px + 0.5 - x) / sx + 4);
            if (col < 0 || col > 7) continue;
            if (c < 0) col = 7 - col;
            for (int row = 0; row < 8; row++)
            {
                var ch = COIN[row][col];
                if (ch != '.') p.Px(px, FX.Round(y - 4 + row), PAL[ch]);
            }
        }
    }

    public void Update(double dt)
    {
        var C = this.C;
        var R = this.R;
        t += dt;
        for (int i = balls.Count - 1; i >= 0; i--)
        {
            var b = balls[i];
            b.Life -= dt;
            if (b.Life <= 0) { balls.RemoveAt(i); continue; }
            b.Vx -= b.Vx * 7 * dt;
            b.Vy -= b.Vy * 7 * dt + 26 * dt;
            b.X += b.Vx * dt;
            b.Y += b.Vy * dt;
            balls[i] = b;
        }
        for (int ci = 0; ci < coins.Count; ci++)
        {
            var c = coins[ci];
            Step(ref c, dt, C, R);
            coins[ci] = c;
        }
        ps.Update(dt);
        lights.Update(dt);
    }

    void Step(ref Coin c, double dt, FXColor[] C, Rng R)
    {
        // a coin winks out with a little burst of gold
        if (!c.Gone && t >= c.Out)
        {
            c.Gone = true;
            for (int j = 0; j < 5; j++)
            {
                double a = R.Range(-Math.PI, 0), sp = R.Range(25, 60);
                ps.Spawn(FXKind.Star, c.X, -3, Math.Cos(a) * sp, Math.Sin(a) * sp, R.Range(0.3, 0.55), R.Pick([FX.White, C[6], C[5]]), R.Range(0.7, 1.4));
            }
            lights.Add(c.X, -3, 14, C[5], 0.6, 0.2);
        }
        if (t < c.Born || t > c.Out || c.Rest) return;
        c.Vy += 820 * dt;
        c.Vx -= c.Vx * 0.4 * dt;
        c.X += c.Vx * dt;
        c.Y += c.Vy * dt;
        c.Ph += c.W * dt;
        if (c.Y >= -1.5 && c.Vy > 0)
        {
            c.Y = -1.5;
            c.Hits++;
            // a tink of light and a puff of dust at each hit
            ps.Spawn(FXKind.Star, c.X, -3, 0, -8, 0.25, FX.White, c.Hits == 1 ? 2.2 : 1.4);
            for (int j = 0; j < 2; j++)
                ps.Spawn(FXKind.Dust, c.X + R.Range(-1, 1), -0.5, R.Sign() * R.Range(8, 24), -R.Range(2, 8), R.Range(0.25, 0.45), SM[1], R.Range(1, 1.8));
            lights.Add(c.X, -3, 12, C[5], 0.5, 0.15);
            if (c.Vy > 110) { c.Vy *= -0.45; c.Vx *= 0.7; c.W = c.W * 0.8 + R.Range(-2, 2); }
            else { c.Rest = true; c.Vx = 0; c.Vy = 0; c.RestAt = t; }
        }
    }

    public void DrawBack(Painter p, double _t)
    {
        // a warm gleam on the floor where the coins lie
        foreach (var c in coins) if (c.Rest && t < c.Out) p.Glow(c.X, -1, 7, C[4], 0.18);
        ps.Draw(p, FXLayer.Back);
    }

    public void Draw(Painter p, double _t)
    {
        var C = this.C;
        var SM = this.SM;
        var t = this.t;
        const FXColor W = FX.White;
        // the poof: soft, top-lit balls, a pop of light in the middle
        for (int layer = 0; layer < 3; layer++)
            foreach (var b in balls)
            {
                double age = b.Max - b.Life, k = b.Life / b.Max, r = b.R * (0.6 + 0.6 * FX.Ease.OutCubic(FX.Clamp(age / 0.2))) * (k < 0.35 ? k / 0.35 : 1);
                if (r < 0.6) continue;
                if (layer == 0) p.Disc(b.X + r * 0.15, b.Y + r * 0.2, r, SM[1], 0.8);
                else if (layer == 1) p.Disc(b.X - r * 0.06, b.Y - r * 0.08, r * 0.86, b.Y > CY + 2 ? SM[1] : SM[2], 0.85);
                else if (b.Y < CY + 2) p.Disc(b.X - r * 0.28, b.Y - r * 0.34, r * 0.4, SM[3], 0.85);
            }
        if (t < 0.07)
        {
            var k = t / 0.07;
            p.Circle(0, CY, 8 + 2 * k, C[6]);
            p.Circle(0, CY, 6 + 2 * k, W);
            FX.Flare(p, 0, CY, 16 * (1 - k * 0.5), 1 - k, C);
        }
        foreach (var c in coins)
        {
            if (t < c.Born || t > c.Out + 0.12) continue;
            if (t > c.Out)
            {
                // a coin winks out with a last flash and a ring
                var k = (t - c.Out) / 0.12;
                FX.Sparkle(p, c.X, -2, FX.Round(5 * (1 - k)), W, C[5], 0.5);
                p.Ring(c.X, -3, 2 + 5 * FX.Ease.OutCubic(k), 1, C[6], 1.1 - k);
                continue;
            }
            if (c.Rest)
            {
                // flat on the floor; now and then a glint runs over it
                p.Sprite(FLAT, PAL, FX.Round(c.X) - 3, -3);
                p.Glow(c.X, -2, 6, C[5], 0.25);
                var g = FX.Mod(t - c.RestAt + c.Glint, 0.95) / 0.95;
                if (g < 0.2) FX.Sparkle(p, c.X - 1, -3, FX.Round(3 * Math.Sin((g / 0.2) * Math.PI)), W, C[5], 0.4);
            }
            else
            {
                DrawCoin(p, c.X, c.Y, c.Ph);
                p.Glow(c.X, c.Y, 8, C[4], 0.3);
                // a glint catches the face as it turns toward us
                if (Math.Abs(Math.Cos(c.Ph)) > 0.96) p.Px(c.X - 1, c.Y - 2, W);
            }
        }
        ps.Draw(p, FXLayer.Front);
        lights.Draw(p);
    }
}

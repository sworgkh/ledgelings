// Dizzy, seeing stars: three spinning stars and two little birds circle the head on a tilted ring, ducking
// behind it and sweeping round in front, trailing glitter. pixelfx's `status/stunned` (MIT); its shaded,
// outlined icons and twinkles adapt Sprite Fusion's open-source heal
// (https://www.spritefusion.com/pixel-art-vfx/heal), MIT, Copyright (c) 2026 Hugo Duprez. The Mac's twin is Stunned.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXStunned : IFXEffect
{
    public static readonly FXMeta Meta = new("status/stunned", size: (60, 64), origin: (30, 56), duration: 2, loop: true,
                                             palette: ["#3a1e0c", "#8a4a12", "#d88a1c", "#f5c030", "#ffe36e", "#fff6c8", "#ffffff"], seed: 2);
    static readonly FXColor[] Birds = FX.Fit(FX.Ramp(["#1a1422", "#6a7fae", "#b8c8e8", "#f4f8ff"]), 4);
    static readonly FXColor Beak = FX.Hex("#ffae35");
    const double D = 2.0, Turns = 2.0;
    const int N = 5;
    static readonly Func<int, int, char?> Star7 = FXStatus.Bitmap(["...#...", "..###..", "#######", ".#####.", "..###..", ".##.##.", ".#...#."]);
    static readonly (int, int)[] WingUp = [(-1, -1), (-1, -2), (-2, -2), (-2, -3), (-3, -3), (-3, -4)];
    static readonly (int, int)[] WingDown = [(-1, 1), (-1, 2), (-2, 2), (-2, 3), (0, 1)];
    /// <summary>A little bird facing right: body, head, eye, beak, tail, a wing that beats.</summary>
    static readonly Func<int, int, char?>[] Bird = [MakeBird(true), MakeBird(false)];
    static Func<int, int, char?> MakeBird(bool up) => (dx, dy) =>
    {
        double x = dx + 0.5, y = dy + 0.5;
        if (dx == 3 && dy == -2) return 'e';
        if ((dx == 5 || dx == 4) && dy == -1) return dx == 5 ? 'b' : '#';
        var wing = up ? WingUp : WingDown;
        if (wing.Any(w => w.Item1 == dx && w.Item2 == dy)) return 'w';
        if (Math.Pow(x / 3.3, 2) + Math.Pow((y - 0.6) / 1.9, 2) <= 1 || Math.Pow(x - 2.8, 2) + Math.Pow(y + 1.2, 2) <= Math.Pow(1.7, 2)) return '#';
        if ((dx == -4 && (dy == -1 || dy == 0)) || (dx == -5 && dy == -1)) return '#';
        return null;
    };
    static readonly Func<double, double, bool> StarFn = FXStatus.StarShape(0.44);
    static Func<int, int, char?> Star(double s, double ang) => FXStatus.Shaped(StarFn, s, ang);

    readonly FXOptions o;
    readonly FXColor[] C;
    public FXStunned(FXOptions o) { this.o = o; C = FX.Fit(o.Palette, 7); }

    readonly record struct Item(int I, double Th, double X, double Y, bool Near, double Depth, bool IsBird, double Rx, double Ry, double Cy);

    /// <summary>The ring round the head: stars at 0, 2, 4, birds between.</summary>
    List<Item> Ring(double t)
    {
        var a = o.Actor;
        double cy = a.Y + 2, rx = a.W * 0.62, ry = 4.5;
        var list = new List<Item>(N);
        for (int i = 0; i < N; i++)
        {
            double th = FX.Tau * ((Turns * t) / D + (double)i / N), s = Math.Sin(th);
            list.Add(new Item(i, th, Math.Cos(th) * rx, cy + s * ry, s >= 0, 0.5 + 0.5 * s, i % 2 == 1, rx, ry, cy));
        }
        return list;
    }

    void Draw1(Painter p, double t, bool far)
    {
        var C = this.C;
        var Bd = Birds;
        FXColor Dim(FXColor c) => far ? FX.Mix(c, Bd[0], 0.3) : c;
        foreach (var it in Ring(t))
        {
            if (it.Near == far) continue;
            // glitter left along the ring behind each star
            if (!it.IsBird)
            {
                for (int k = 1; k <= 12; k++)
                {
                    double th = it.Th - k * 0.085, x = Math.Cos(th) * it.Rx, y = it.Cy - 1 + Math.Sin(th) * it.Ry;
                    if ((Math.Sin(th) >= 0) == far || FX.Rand(it.I, k, FX.Floor(((t / D) * Turns + k * 0.37) * 9)) < 0.25) continue;
                    p.Dot(x, y, Dim(k < 4 ? C[6] : k < 8 ? C[5] : C[4]), 1.1 - k / 13.0);
                    if (k < 6) p.Light(x, y, C[4], 0.3 * (1 - k / 6.0));
                }
            }
            if (it.IsBird)
            {
                var up = FX.Mod(FX.Floor(t * 8 + it.I * 0.5), 2) == 0;
                var bob = Math.Sin((t / D) * FX.Tau * 4 + it.I) * 0.7;
                var f = Bird[up ? 0 : 1];
                Func<int, int, char?> ins = it.Near ? (dx, dy) => f(-dx, dy) : f;
                FXStatus.Icon(p, it.X, it.Y - 3 + bob, 7, ins, [Bd[0], Dim(Bd[1]), Dim(Bd[2]), Dim(Bd[3])], 1,
                              new Dictionary<char, FXColor> { ['e'] = Bd[0], ['b'] = Dim(Beak), ['w'] = Dim(Bd[1]) });
            }
            else
            {
                var spin = (t / D) * FX.Tau * 3 + it.I;
                FXColor[] R = [C[0], Dim(C[3]), Dim(C[4]), Dim(C[5])];
                if (it.Depth > 0.55) FXStatus.Icon(p, it.X, it.Y - 1, 7, Star(4 + 0.8 * it.Depth, spin), R);
                else FXStatus.Icon(p, it.X, it.Y - 1, 5, Star7, R);
                p.Px(it.X, it.Y - 1, far ? C[5] : C[6]);
                p.Glow(it.X, it.Y - 1, 11, C[4], 0.24 + 0.3 * it.Depth);
                p.Glow(it.X, it.Y - 1, 4, C[6], 0.3 * it.Depth);
                // a flare as it sweeps past the front, nearest the eye
                var fr = Math.Exp(-Math.Pow(Math.Atan2(Math.Sin(it.Th - Math.PI / 2), Math.Cos(it.Th - Math.PI / 2)) / 0.32, 2));
                if (!far && fr > 0.08) FX.Flare(p, it.X, it.Y - 1, 9 * fr, fr, [C[3], C[4], C[5], C[6]]);
            }
        }
    }

    public void DrawBack(Painter p, double t) => Draw1(p, t, true);

    public void Draw(Painter p, double t)
    {
        var C = this.C;
        var a = o.Actor;
        double aw = a.W, ay = a.Y;
        Draw1(p, t, false);
        // little twinkles popping round the ring
        FX.Cycle(t, D, 14, o.Seed + 3, r => r.Range(0.25, 0.5), (age, life, r, _) =>
        {
            double th = r.Range(0, FX.Tau), u = age / life, x = Math.Cos(th) * aw * r.Range(0.45, 0.95), y = ay + 1 + Math.Sin(th) * 7 - r.Range(0, 9);
            var arm = FX.Round(r.Range(1, 2.6) * Math.Sin(Math.PI * u));
            if (arm < 1) p.Dot(x, y, C[6], Math.Sin(Math.PI * u) * 1.4);
            FX.Sparkle(p, x, y, arm, C[5], C[4], 0.35 * Math.Sin(Math.PI * u));
        });
        p.Glow(0, ay + 1, 26, C[4], 0.13);
    }
}

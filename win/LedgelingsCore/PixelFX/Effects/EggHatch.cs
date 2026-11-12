// A speckled egg rocks three times, each rock cracking it further with warm light leaking out, then pops: light
// pours out of the opening and lit shell halves tumble away. pixelfx's `spawn/egg-hatch` (MIT), after Sprite
// Fusion's open-source ice shatter (https://www.spritefusion.com/pixel-art-vfx/ice), MIT,
// Copyright (c) 2026 Hugo Duprez. The Mac's twin is EggHatch.swift.

namespace Ledgelings.Core.PixelFX;

public sealed class FXEggHatch : IFXEffect
{
    public static readonly FXMeta Meta = new("spawn/egg-hatch", size: (120, 96), origin: (60, 84), duration: 3.1, loop: false,
                                             palette: ["#1e1826", "#4a3e52", "#857684", "#c4b4ac", "#ece0d2", "#fffaf0"], seed: 31);
    static readonly string[] GlowRamp = ["#ff8a2a", "#ffd25a", "#fff3c0"];
    const string Speckle = "#9a6a52";
    static readonly (double T0, double Amp)[] Wobbles = [(0.3, 0.11), (0.85, 0.19), (1.4, 0.28)];
    const double POP = 1.98, Duration = 3.1, CRUMBLE = Duration - 0.55;
    const int EW = 16, EH = 20, ZY = 11;
    static readonly double[] LIGHT = [-0.72, 0.5, 0.48]; // from the upper left, a little toward us
    static readonly (int X, int Y)[] Cross = [(1, 0), (-1, 0), (0, 1), (0, -1)];

    /// <summary>One pixel of the egg: x across from its middle, y up from its base.</summary>
    struct Egg { public int X, Y; public double U, V, Half; public FXColor C; public double Lit; }
    static readonly Egg[] Shape = MakeShape();
    static Egg[] MakeShape()
    {
        var @out = new List<Egg>();
        for (int y = 0; y < EH; y++)
            for (int x = -EW / 2; x < EW / 2; x++)
            {
                double v = (y + 0.5) / EH, u = (x + 0.5) / (EW / 2), q = 2 * v - 1;
                var half = Math.Sqrt(Math.Max(0, 1 - q * q)) * (1.08 - 0.22 * v);
                if (Math.Abs(u) <= half) @out.Add(new Egg { X = x, Y = y, U = u, V = v, Half = half });
            }
        return @out.ToArray();
    }
    static int Key(int x, int y) => (x + 512) * 1024 + (y + 512);

    sealed class Piece(int id, double x, double y, double vx, double vy, double va, double r, Dictionary<int, (FXColor C, bool Edge)> map, double life, double born)
    {
        public readonly int Id = id;
        public readonly double R = r, Max = life, Born = born;
        public readonly Dictionary<int, (FXColor C, bool Edge)> Map = map;
        public double X = x, Y = y, Vx = vx, Vy = vy, A, Va = va, Life = life;
        public bool Rest;
    }

    readonly FXOptions o;
    readonly FXColor[] C, G;
    readonly FXColor SPK;
    readonly Rng R;
    readonly Egg[] egg;
    readonly Dictionary<int, int> at = new();
    readonly Dictionary<int, int> crack = new();
    readonly List<int> zig = new();
    readonly Dictionary<int, double>[] near;
    readonly FXParticles ps;
    readonly FXLights lights = new();
    readonly FXBits bits = new(_ => 0);
    readonly List<Piece> pieces = new();
    double t, cupA, cupV;
    bool popped, crumbled;
    readonly bool[] done = [false, false, false];

    public FXEggHatch(FXOptions o)
    {
        this.o = o;
        var C = FX.Fit(o.Palette, 6);
        var G = FX.Fit(FX.Ramp(GlowRamp), 3);
        var SPK = FX.Hex(Speckle);
        var R = new Rng(o.Seed);
        const FXColor W = FX.White;
        this.C = C; this.G = G; this.SPK = SPK; this.R = R;
        ps = new FXParticles(rng: R, ground: _ => 0, sparks: [W, G[2], G[1], G[0]]);
        egg = (Egg[])Shape.Clone();
        for (int i = 0; i < egg.Length; i++) at[Key(egg[i].X, egg[i].Y)] = i;
        bool Has(int x, int y) => at.ContainsKey(Key(x, y));
        // shading: a round shell lit from the upper left, a core shadow, a rim of bounce light on the dark side
        var L = LIGHT;
        for (int i = 0; i < egg.Length; i++)
        {
            var e = egg[i];
            double nx = FX.Clamp(e.U / Math.Max(0.05, e.Half), -1, 1), ny = (2 * e.V - 1) * 0.9, nz = Math.Sqrt(Math.Max(0, 1 - nx * nx - ny * ny));
            var d = nx * L[0] + ny * L[1] + nz * L[2];
            var edge = !Has(e.X - 1, e.Y) || !Has(e.X + 1, e.Y) || !Has(e.X, e.Y - 1) || !Has(e.X, e.Y + 1);
            var c = d > 0.9 ? W : d > 0.62 ? C[5] : d > 0.32 ? C[4] : d > 0.02 ? C[3] : d > -0.3 ? C[2] : C[1];
            if (edge && nx > 0.25 && ny < 0.55) c = C[3]; // rim light on the shadow side
            else if (FX.Rand(e.X, e.Y, 3) < 0.08 && e.V > 0.12 && !edge) c = d > 0.2 ? SPK : FX.Mix(SPK, C[1], 0.5);
            egg[i].C = c;
            egg[i].Lit = d;
        }
        // cracks: three stages, the last a zigzag right round the egg where the top breaks off
        var cracks = new List<(int X, int Y, int S)>();
        void Walk(double x, double y, double a, int len, int s)
        {
            double px = FX.Round(x), py = FX.Round(y);
            for (int i = 0; i < len; i++)
            {
                var side = (i % 2 != 0 ? 1.0 : -1.0) * R.Range(0.6, 1.3);
                a += R.Range(-0.25, 0.25);
                x += Math.Cos(a) * 1.8 - Math.Sin(a) * side * 0.6;
                y += Math.Sin(a) * 1.8 + Math.Cos(a) * side * 0.6;
                double nx = FX.Round(x), ny = FX.Round(y), n = Math.Max(Math.Abs(nx - px), Math.Abs(ny - py));
                for (var j = 1.0; j <= n; j++)
                {
                    int cx = (int)FX.Round(px + ((nx - px) * j) / n), cy = (int)FX.Round(py + ((ny - py) * j) / n), k = Key(cx, cy);
                    if (!at.ContainsKey(k)) return;
                    if (!crack.ContainsKey(k)) { crack[k] = s; cracks.Add((cx, cy, s)); }
                }
                px = nx; py = ny;
            }
        }
        Walk(2, 15, -2.2, 3, 0);
        Walk(2, 15, 0.3, 2, 0);
        Walk(-2, 13, -0.6, 3, 1);
        Walk(-2, 13, 2.7, 3, 1);
        Walk(3, 11, 1.9, 2, 1);
        Walk(2, 15, 1.5, 2, 1);
        for (int x = -EW / 2; x < EW / 2; x++)
        {
            int m = (x + 8) % 3, y = ZY + (m == 0 ? 1 : m == 1 ? 0 : -1);
            zig.Add(y);
            if (Has(x, y))
            {
                var k = Key(x, y);
                var idx = cracks.FindIndex(q => Key(q.X, q.Y) == k);
                if (idx >= 0) cracks[idx] = (x, y, 2); else cracks.Add((x, y, 2));
                crack[k] = 2;
            }
        }
        // how close each pixel of shell is to an open crack, per stage: light shows through the shell round them
        near = new Dictionary<int, double>[3];
        for (int s = 0; s < 3; s++)
        {
            var pts = cracks.Where(q => q.S <= s).ToList();
            var m = new Dictionary<int, double>();
            foreach (var e in egg)
            {
                var best = 9.0;
                foreach (var (cx, cy, _) in pts) best = Math.Min(best, FX.Hypot(cx - e.X, cy - e.Y));
                m[Key(e.X, e.Y)] = best;
            }
            near[s] = m;
        }
    }

    int ZigAt(int x) => zig[Math.Min(zig.Count - 1, Math.Max(0, x + EW / 2))];
    Egg? Cell(int x, int y) => at.TryGetValue(Key(x, y), out var i) ? egg[i] : null;
    bool Opened(int x, int y, int st) => crack.TryGetValue(Key(x, y), out var c) && c < st;

    static int Stage(double t) => t > Wobbles[2].T0 + 0.05 ? 3 : t > Wobbles[1].T0 + 0.05 ? 2 : t > Wobbles[0].T0 + 0.05 ? 1 : 0;
    /// <summary>The rock: a damped swing about the base, each one harder; a shiver just before it pops.</summary>
    static double Angle(double t)
    {
        var a = 0.0;
        foreach (var (t0, amp) in Wobbles)
        {
            var u = t - t0;
            if (u > 0 && u < 0.55) a += amp * Math.Sin(u * 22) * Math.Exp(-u * 5);
        }
        if (t > POP - 0.14 && t < POP) a += 0.05 * Math.Sin(t * 120);
        return a;
    }
    /// <summary>The light inside: grows with each crack, flashes at the pop, then dies down in the empty cup.</summary>
    static double Inner(double t)
    {
        double st = Stage(t);
        return t < POP ? st / 3 + 0.25 * Math.Max(0, Math.Sin(t * 9)) * (st / 3) : 1.6 * Math.Exp(-(t - POP) * 2.6);
    }

    /// <summary>Break part of the shell into pieces round a few seeds; each keeps its lit outside and a hot broken edge.</summary>
    void BreakUp(Func<int, int, bool> keep, int n, Func<double, double, (double, double)> v, Func<double> life)
    {
        var R = this.R;
        var C = this.C;
        var seeds = new List<(double X, double Y)>();
        for (int i = 0; i < n; i++) { var sx = R.Range(-EW / 2.0 + 1, EW / 2.0 - 1); seeds.Add((sx, R.Range(0, EH))); }
        var order = new List<int>();
        var cells = new Dictionary<int, List<Egg>>();
        foreach (var e in egg)
        {
            if (!keep(e.X, e.Y)) continue;
            int best = 0;
            var bd = 1e9;
            for (int i = 0; i < seeds.Count; i++)
            {
                var d = FX.Hypot(e.X - seeds[i].X, e.Y - seeds[i].Y);
                if (d < bd) { bd = d; best = i; }
            }
            if (!cells.ContainsKey(best)) { cells[best] = new(); order.Add(best); }
            cells[best].Add(e);
        }
        foreach (var ci in order)
        {
            var px = cells[ci];
            double cx = 0, cy = 0;
            foreach (var e in px) { cx += e.X + 0.5; cy += e.Y + 0.5; }
            cx /= px.Count; cy /= px.Count;
            var map = new Dictionary<int, (FXColor, bool)>();
            var mine = new HashSet<int>(px.Select(e => Key(e.X, e.Y)));
            foreach (var e in px)
            {
                var edge = Cross.Any(q => !mine.Contains(Key(e.X + q.X, e.Y + q.Y)) && at.ContainsKey(Key(e.X + q.X, e.Y + q.Y)));
                // lit by the flash: no piece flies off in shadow
                var c = e.C == C[1] || e.C == C[2] ? C[3] : e.C;
                map[Key((int)FX.Round(e.X + 0.5 - cx), (int)FX.Round(-(e.Y + 0.5 - cy)))] = (c, edge);
            }
            var r = double.NegativeInfinity;
            foreach (var e in px) r = Math.Max(r, FX.Hypot(e.X + 0.5 - cx, e.Y + 0.5 - cy));
            r += 1;
            var (vx, vy) = v(cx, cy);
            var l = life();
            pieces.Add(new Piece(pieces.Count + 1, cx, -cy, vx, vy, R.Range(-10, 10), r, map, l, t));
        }
    }

    void Pop()
    {
        var R = this.R;
        var C = this.C;
        var G = this.G;
        const FXColor W = FX.White;
        popped = true;
        BreakUp((x, y) => y >= ZigAt(x), 6, (cx, _) => (cx * R.Range(8, 13) + R.Range(-14, 14), -R.Range(140, 210)), () => R.Range(0.95, 1.15));
        for (int i = 0; i < 14; i++)
        {
            double a = -Math.PI / 2 + R.Range(-1.2, 1.2), sp = R.Range(70, 170);
            double x = R.Range(-5, 5), y = -ZY - R.Range(0, 4), life = R.Range(0.55, 0.85), an = R.Range(0, FX.Tau), va = R.Range(-20, 20), s = R.Range(1.2, 2.4);
            var c = R.Pick([C[5], C[5], C[4], G[2]]);
            bits.Add(new FXBits.Bit(kind: FXBits.Kind.Shard, x: x, y: y, vx: Math.Cos(a) * sp, vy: Math.Sin(a) * sp, a: an, va: va, s: s, c: c, g: 0.9, drag: 0.6, bounce: 0.3, life: life));
        }
        for (int i = 0; i < 12; i++)
        {
            double a = -Math.PI / 2 + R.Range(-1.1, 1.1), sp = R.Range(50, 110);
            ps.Spawn(FXKind.Star, R.Range(-3, 3), -ZY - 2, Math.Cos(a) * sp, Math.Sin(a) * sp, R.Range(0.4, 0.9), R.Pick([W, G[2], G[1]]), R.Range(1, 2.2));
        }
        for (int i = 0; i < 10; i++)
        {
            double a = -Math.PI / 2 + R.Range(-1, 1), sp = R.Range(100, 200);
            ps.Spawn(FXKind.Spark, R.Range(-3, 3), -ZY - 1, Math.Cos(a) * sp, Math.Sin(a) * sp, R.Range(0.2, 0.45));
        }
        // a puff of pale dust at the base, gone in a few frames
        for (int i = 0; i < 4; i++)
        {
            var s = R.Sign();
            ps.Spawn(FXKind.Dust, s * R.Range(5, 8), -1, s * R.Range(25, 50), -R.Range(2, 6), R.Range(0.15, 0.25), C[5], R.Range(1, 1.8));
        }
        lights.Add(0, -ZY - 10, 40, G[1], 0.9, 0.55);
        lights.Add(0, -ZY - 2, 18, W, 0.9, 0.12);
        cupV = R.Sign() * 3;
    }

    public void Update(double dt)
    {
        var R = this.R;
        var C = this.C;
        var G = this.G;
        const FXColor W = FX.White;
        t += dt;
        // each rock opens more crack: a tick of light, a chip or two of shell, a puff at the base
        for (int i = 0; i < Wobbles.Length; i++)
        {
            if (done[i] || t < Wobbles[i].T0 + 0.05) continue;
            done[i] = true;
            lights.Add(i == 1 ? -3 : 2, -14 + i, 8 + i * 2, G[1], 0.25 + i * 0.08, 0.18);
            for (int j = 0; j < 2 + i * 2; j++)
                ps.Spawn(FXKind.Star, R.Range(-5, 5), -R.Range(8, 17), R.Range(-20, 20), -R.Range(10, 30), R.Range(0.25, 0.5), R.Pick([W, G[2]]), R.Range(0.6, 1.4));
            for (int j = 0; j < i + 1; j++)
            {
                double x = R.Range(-4, 4), y = -R.Range(10, 16), vx = R.Range(-50, 50), vy = -R.Range(40, 90), life = R.Range(0.5, 0.8);
                double a = R.Range(0, FX.Tau), va = R.Range(-20, 20), s = R.Range(1, 1.6);
                bits.Add(new FXBits.Bit(kind: FXBits.Kind.Shard, x: x, y: y, vx: vx, vy: vy, a: a, va: va, s: s, c: C[4], g: 0.9, drag: 0.5, bounce: 0.3, life: life));
            }
            ps.Spawn(FXKind.Dust, R.Sign() * R.Range(5, 7), -0.5, R.Sign() * R.Range(8, 18), -R.Range(1, 3), R.Range(0.15, 0.25), C[5], R.Range(0.8, 1.4));
        }
        if (!popped && t >= POP) Pop();
        // light keeps welling up out of the empty cup for a moment: something came out of there
        if (popped && t < POP + 0.6 && R.Chance(0.35))
            ps.Spawn(FXKind.Mote, R.Range(-4, 4), -ZY - 1, R.Range(-8, 8), -R.Range(40, 80), Math.Min(R.Range(0.4, 0.8), Duration - 0.1 - t), R.Pick([G[2], G[1], W]), 0.7);
        if (popped && !crumbled && t >= CRUMBLE)
        {
            crumbled = true;
            BreakUp((x, y) => y < ZigAt(x), 4, (cx, _) => (cx * R.Range(4, 8), -R.Range(40, 80)), () => R.Range(0.38, 0.48));
            for (int i = 0; i < 3; i++) ps.Spawn(FXKind.Dust, R.Range(-6, 6), -1, R.Sign() * R.Range(10, 25), -R.Range(2, 6), R.Range(0.15, 0.25), C[5], R.Range(1, 1.6));
        }
        if (popped)
        {
            cupV += (-cupA * 90 - cupV * 4) * dt;
            cupA += cupV * dt;
        }
        for (int i = pieces.Count - 1; i >= 0; i--)
        {
            var q = pieces[i];
            q.Life -= dt;
            if (q.Life <= 0) { pieces.RemoveAt(i); continue; }
            if (q.Rest) continue;
            q.Vy += 900 * dt;
            q.Vx -= q.Vx * 0.6 * dt;
            q.X += q.Vx * dt;
            q.Y += q.Vy * dt;
            q.A += q.Va * dt;
            var g = -q.R * 0.45;
            if (q.Y > g && q.Vy > 0)
            {
                q.Y = g;
                if (q.Vy > 80) { q.Vy *= -0.35; q.Vx *= 0.6; q.Va *= 0.5; }
                else { q.Rest = true; q.Vx = 0; q.Vy = 0; }
            }
        }
        bits.Update(dt);
        ps.Update(dt);
        lights.Update(dt);
    }

    public void DrawBack(Painter p, double _t)
    {
        var t = this.t;
        // a soft contact shadow under the egg, shifting as it rocks
        if (!crumbled)
        {
            double sx = popped ? 0 : -Angle(t) * 8, k = popped ? 1 - FX.Smooth(POP, CRUMBLE, t) * 0.4 : 1;
            for (int y = -1; y <= 1; y++)
                for (int x = -10; x <= 10; x++)
                {
                    double dx = (x + 0.5 - sx) / 9.5, dy = (y + 0.5) / 1.8, d = dx * dx + dy * dy;
                    if (d < 1) p.Blend(x, y, C[0], 0.5 * k * (1 - d));
                }
        }
        // warm light on the floor as it leaks out
        var g = Inner(t);
        if (g > 0.05) p.Glow(0, -3, 22, G[0], 0.18 * Math.Min(1.2, g));
        ps.Draw(p, FXLayer.Back);
    }

    public void Draw(Painter p, double _t)
    {
        var C = this.C;
        var G = this.G;
        var SPK = this.SPK;
        const FXColor W = FX.White;
        var t = this.t;
        var popped = this.popped;
        var st = Stage(t);
        double a = popped ? cupA * 0.03 : Angle(t), ca = Math.Cos(a), sa = Math.Sin(a), g = Inner(t);
        if (!crumbled)
            p.Shade(-12, -EH - 4, 12, 1, (x, y, @out) =>
            {
                int ux = (int)FX.Floor(x * ca + y * sa), uy = (int)FX.Floor(-(-x * sa + y * ca));
                var ce = Cell(ux, uy);
                var inside = ce != null && !(popped && uy >= ZigAt(ux));
                if (!inside)
                {
                    // a dark outline holds the egg's shape
                    var n = Cross.Any(q => Cell(ux + q.X, uy + q.Y) != null && !(popped && uy + q.Y >= ZigAt(ux + q.X)));
                    if (n && !(popped && uy >= ZigAt(ux) && uy <= ZigAt(ux) + 1)) @out.C = C[0];
                    return 0;
                }
                var e = ce!.Value;
                if (popped)
                {
                    // the cup: its broken rim burns with the light inside, cooling as it fades
                    var rim = uy >= ZigAt(ux) - 1;
                    @out.C = rim ? (g > 0.9 ? W : g > 0.4 ? G[2] : g > 0.12 ? G[1] : C[4]) : e.C;
                    if (rim) { @out.K = 0.25 * g; @out.L = G[1]; }
                    return 0;
                }
                if (crack.TryGetValue(Key(ux, uy), out var cs) && cs < st)
                {
                    // an open crack: deep orange light in the gap, flashing white the moment it opens
                    var fresh = t - Wobbles[cs].T0 < 0.17;
                    @out.C = fresh ? W : FX.Rand(ux, uy, FX.I32(t * 20)) < 0.25 + 0.1 * st ? G[1] : G[0];
                    @out.K = 0.14 + 0.06 * st;
                    @out.L = G[1];
                    return 0;
                }
                // the lip of each crack falls into shadow below it, so the gap reads as a gap
                if (Opened(ux, uy + 1, st) || Opened(ux + 1, uy, st))
                {
                    @out.C = e.Lit > 0.3 ? C[2] : C[1];
                    return 0;
                }
                // light shows through the shell in a halo round the cracks, and the whole egg warms a little
                double dn = st > 0 ? near[st - 1][Key(ux, uy)] : 9, k = Math.Min(1, g * 1.5);
                var @base = st > 0 && e.C != SPK ? FX.Mix(e.C, G[0], 0.05 * st * k) : e.C;
                @out.C = dn < 1.6 ? FX.Mix(@base, G[1], (st >= 2 ? 0.32 : 0.2) * k) : dn < 2.7 && st >= 2 ? FX.Mix(@base, G[1], 0.14 * k) : @base;
                return 0;
            });
        // the pop: the opening floods white, and light rays fan up out of it
        var q = t - POP;
        if (popped && q < 1.2 && !crumbled && g > 0.22)
        {
            const double oy = -ZY + 0.5;
            const int rx = 7;
            for (int y = -2; y <= 2; y++)
                for (int x = -rx; x <= rx; x++)
                {
                    var d = FX.Hypot((x + 0.5) / rx, (y + 0.5) / 2.2);
                    if (d > 1) continue;
                    if (g < 0.6 && d > 0.75) continue;
                    p.Px(x, oy + y, g > 1 ? (d < 0.7 ? W : G[2]) : g > 0.6 ? (d < 0.5 ? G[2] : G[1]) : d < 0.45 ? G[1] : G[0]);
                }
            p.Glow(0, oy, 16, G[1], 0.6 * g);
            if (q < 0.65)
            {
                double rk = q / 0.65, L = 36 * FX.Ease.OutCubic(FX.Clamp(q / 0.1)) * (1 - rk * 0.6);
                for (int i = 0; i < 7; i++)
                {
                    double an = -Math.PI / 2 + (i - 3) * 0.24 + 0.05 * Math.Sin(t * 6 + i), len = L * (i % 2 != 0 ? 0.65 : 1);
                    var w = i % 2 != 0 ? 1 : 2;
                    double x1 = Math.Cos(an) * len, y1 = oy + Math.Sin(an) * len;
                    for (int j = 0; j < w; j++)
                    {
                        var off = j * 0.8 - 0.4;
                        p.Line(off, oy - 1, x1 + off, y1, u => u < 0.3 ? W : u < 0.65 ? G[2] : G[1], u => (1 - u * u) * (1.1 - rk));
                    }
                    p.GlowLine(0, oy, x1, y1, 5, G[1], 0.35 * (1 - rk));
                }
            }
            if (q < 0.1) p.Glow(0, oy - 4, 30, W, 0.6 * (1 - q / 0.1));
            // the light that lingers over the cup
            p.GlowLine(0, oy, 0, oy - 26, 8, G[1], 0.25 * g);
        }
        // the inside glow through the shell before it pops
        if (!popped && g > 0) p.Glow(0, -EH * 0.55, 7 + 2 * st, G[1], 0.05 * g);
        // pieces of shell: their lit outsides, their broken edges hot at first
        foreach (var s in pieces)
        {
            double c2 = Math.Cos(s.A), s2 = Math.Sin(s.A), f = Math.Min(1, s.Life / 0.4);
            var r = (int)FX.Ceil(s.R);
            var hot = t - s.Born < 0.35;
            for (int py = -r; py <= r; py++)
                for (int px = -r; px <= r; px++)
                {
                    int ux = (int)FX.Round(px * c2 + py * s2), uy = (int)FX.Round(-px * s2 + py * c2);
                    if (s.Map.TryGetValue(Key(ux, uy), out var m) && FX.Rand(ux, uy, s.Id) < f)
                        p.Px(FX.Floor(s.X) + px, FX.Floor(s.Y) + py, m.Edge ? (hot ? G[2] : C[4]) : m.C);
                }
            if (hot) p.Glow(s.X, s.Y, 6, G[1], 0.3);
        }
        bits.Draw(p);
        if (popped && q < 0.9) FX.Sparkle(p, -3, -ZY - 6, FX.Round(4 * (1 - q / 0.9)), W, G[1], 0.4);
        ps.Draw(p, FXLayer.Front);
        lights.Draw(p);
    }
}

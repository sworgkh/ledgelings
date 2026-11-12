// Helpers shared by the weather loops: pixelfx's `fx/weather/_lib.js` (MIT), the parts the ported loops use.
// Weather fills its whole canvas edge to edge, so `Clip` keeps every pixel and every bit of light inside the
// canvas; `Pass` and `Rows` are fast per-pixel shaders over the canvas; `Trips` rains particles that fall a
// whole number of times a loop, somewhere new each time. All of it is a pure function of t.
// The Mac's twin is WeatherLib.swift.

namespace Ledgelings.Core.PixelFX;

/// <summary>Something a pixel shader can be run on: the clipped painter, or a recorder that keeps the pixels to replay.</summary>
public interface IFXWeatherShading
{
    void Shade(double x0, double y0, double x1, double y1, Func<double, double, FXShadeOut, FXColor> fn);
}

/// <summary>What <c>Pass</c> hands a shader: colour, alpha (dithered, or truly blended when B), light colour and amount.</summary>
public sealed class FXWeatherPassOut
{
    public FXColor C;
    public double A = 1;
    public bool B;
    public FXColor L;
    public double K;
    public void Reset() { C = 0; A = 1; B = false; L = 0; K = 0; }
}

/// <summary>One canvas row for <c>Rows</c>: per column, colour (0 for none), alpha (stored as float, as pixelfx's
/// Float32Array), blend or dither, light colour and amount.</summary>
public sealed class FXWeatherRow
{
    public readonly int W;
    public readonly FXColor[] C, L;
    public readonly float[] A, K;
    public readonly bool[] B;
    public FXWeatherRow(int w)
    {
        W = w;
        C = new FXColor[w]; L = new FXColor[w]; A = new float[w]; K = new float[w]; B = new bool[w];
        Array.Fill(A, 1f);
    }
    /// <summary>The whole row one colour, alpha and mode.</summary>
    public void Fill(FXColor col, double alpha, bool blend)
    {
        var fa = (float)alpha;
        for (int i = 0; i < W; i++) { C[i] = col; A[i] = fa; B[i] = blend; }
    }
}

public static class FXWeather
{
    /// <summary>The canvas in local coordinates: X0 &lt;= x &lt; X1, Y0 &lt;= y &lt; Y1.</summary>
    public readonly record struct Box(double X0, double Y0, double X1, double Y1, int W, int H);
    public static Box BoxOf(FXMeta meta)
    {
        int W = meta.Size.W, H = meta.Size.H, OX = meta.Origin.X, OY = meta.Origin.Y;
        return new Box(-OX, -OY, W - OX, H - OY, W, H);
    }

    /// <summary>Whether the painter is turned (pixelfx's <c>p.sn !== 0</c>), read through its public mapping.</summary>
    static bool Rotated(Painter p) => p.ToX(0, 1) != p.ToX(0, 0) || p.ToY(1, 0) != p.ToY(0, 0);

    /// <summary>A painter that draws only inside the effect's canvas: the same calls, with colour, blends and light
    /// outside it dropped. Exact under the painter's flip and rotation.</summary>
    public sealed class Clip : IFXWeatherShading
    {
        public readonly Painter P;
        public readonly Box B;
        readonly bool flat;
        readonly int sx0, sx1, sy0, sy1;

        public Clip(Painter p, FXMeta meta)
        {
            P = p;
            B = BoxOf(meta);
            flat = !Rotated(p);
            if (flat)
            {
                double a = p.ToX(B.X0, 0), b = p.ToX(B.X1, 0);
                sx0 = (int)FX.Round(Math.Min(a, b)); sx1 = (int)FX.Round(Math.Max(a, b));
                sy0 = (int)FX.Round(p.ToY(0, B.Y0)); sy1 = (int)FX.Round(p.ToY(0, B.Y1));
            }
        }

        public bool Ok(int sx, int sy)
        {
            if (flat) return sx >= sx0 && sx < sx1 && sy >= sy0 && sy < sy1;
            double cx = sx + 0.5, cy = sy + 0.5, lx = P.FromX(cx, cy), ly = P.FromY(cx, cy);
            return lx >= B.X0 && lx < B.X1 && ly >= B.Y0 && ly < B.Y1;
        }
        public void Put(int sx, int sy, FXColor c, double a = 1) { if (Ok(sx, sy)) P.Put(sx, sy, c, a); }
        public void Add(int sx, int sy, FXColor c, double k = 1) { if (Ok(sx, sy)) P.Add(sx, sy, c, k); }
        public void BlendPx(int sx, int sy, FXColor c, double a) { if (Ok(sx, sy)) P.BlendPx(sx, sy, c, a); }

        public void Px(double x, double y, FXColor c) => Put(P.CellX(x, y), P.CellY(x, y), c, 1);
        public void Dot(double x, double y, FXColor c, double a = 1) { if (a > 0) Put(P.CellX(x, y), P.CellY(x, y), c, a); }
        public void Light(double x, double y, FXColor c, double k = 1) => Add(P.CellX(x, y), P.CellY(x, y), c, k);
        public void Blend(double x, double y, FXColor c, double a) => BlendPx(P.CellX(x, y), P.CellY(x, y), c, a);

        public void Shade(double x0, double y0, double x1, double y1, Func<double, double, FXShadeOut, FXColor> fn)
        {
            var o = new FXShadeOut();
            P.Each(x0, y0, x1, y1, (lx, ly, sx, sy) =>
            {
                o.C = 0; o.A = 1; o.L = 0; o.K = 0;
                var r = fn(lx, ly, o);
                var c = r != 0 ? r : o.C;
                if (c != 0) Put(sx, sy, c, o.A);
                if (o.K > 0) Add(sx, sy, o.L != 0 ? o.L : c, o.K);
            });
        }

        /// <summary>The painter's glow, with its box cut to the canvas first (big soft lights stay cheap).</summary>
        public void Glow(double x, double y, double r, FXColor c, double k = 0.5)
        {
            if (r < 1 || k <= 0.004) return;
            double x0 = Math.Max(B.X0, FX.Floor(x - r)), x1 = Math.Min(B.X1 - 1, FX.Ceil(x + r));
            double y0 = Math.Max(B.Y0, FX.Floor(y - r)), y1 = Math.Min(B.Y1 - 1, FX.Ceil(y + r));
            for (var py = y0; py <= y1; py += 1)
            {
                var dy = (py + 0.5 - y) / r;
                for (var px = x0; px <= x1; px += 1)
                {
                    double dx = (px + 0.5 - x) / r, d = dx * dx + dy * dy;
                    if (d >= 1) continue;
                    var f = 1 - Math.Sqrt(d);
                    Light(px, py, c, f * f * k);
                }
            }
        }
    }

    /// <summary>Records what a shader draws, to replay it with <c>Replay</c> (things that never move, shaded once).</summary>
    public sealed class Recorder(bool resetAlpha) : IFXWeatherShading
    {
        /// <summary>pixelfx's litter resets alpha between pixels; its scatter does not (<c>resetAlpha</c> false).</summary>
        readonly bool resetAlpha = resetAlpha;
        public readonly List<(double X, double Y, FXColor C, double A)> Px = [];
        public void Shade(double x0, double y0, double x1, double y1, Func<double, double, FXShadeOut, FXColor> fn)
        {
            var o = new FXShadeOut();
            for (var y = FX.Floor(y0); y <= FX.Ceil(y1); y += 1)
                for (var x = FX.Floor(x0); x <= FX.Ceil(x1); x += 1)
                {
                    o.C = 0;
                    if (resetAlpha) o.A = 1;
                    var r = fn(x + 0.5, y + 0.5, o);
                    var c = r != 0 ? r : o.C;
                    if (c != 0) Px.Add((x + 0.5, y + 0.5, c, o.A));
                }
        }
        public void Replay(Clip q) { foreach (var e in Px) q.Dot(e.X, e.Y, e.C, e.A); }
    }

    /// <summary>A per-pixel shader over the canvas rows y0..y1 (local, clipped to the canvas). fn(x, y, out) sets out.C
    /// with out.A (dithered, or blended when out.B), and out.L / out.K (light). x, y are pixel centres.</summary>
    public static void Pass(Painter p, FXMeta meta, double y0In, double y1In, Action<double, double, FXWeatherPassOut> fn)
    {
        var B = BoxOf(meta);
        double y0 = Math.Max(B.Y0, FX.Floor(y0In)), y1 = Math.Min(B.Y1 - 1, FX.Ceil(y1In));
        if (y0 > y1) return;
        var o = new FXWeatherPassOut();
        if (Rotated(p))
        {
            var q = new Clip(p, meta);
            for (var y = y0; y <= y1; y += 1)
                for (var x = B.X0; x < B.X1; x += 1)
                {
                    o.Reset();
                    fn(x + 0.5, y + 0.5, o);
                    if (o.C != 0) { if (o.B) q.Blend(x, y, o.C, o.A); else q.Dot(x, y, o.C, o.A); }
                    if (o.K > 0) q.Light(x, y, o.L != 0 ? o.L : o.C, o.K);
                }
            return;
        }
        FXFrame f = p.Frame;
        int W = f.W, H = f.H, ox = f.Ox, oy = f.Oy;
        double fade = p.Fade, lk = p.LightK * fade, tx = p.ToX(0, 0), ty = p.ToY(0, 0), fx = p.ToX(1, 0) > tx ? 1 : -1;
        for (var y = y0; y <= y1; y += 1)
        {
            int sy = (int)FX.Floor(ty + y + 0.5), ry = sy - oy;
            if (ry < 0 || ry >= H) continue;
            int row = ry * W, by = (sy & 3) << 2;
            var sxf = tx + (B.X0 + 0.5) * fx;
            for (var x = B.X0; x < B.X1; x += 1, sxf += fx)
            {
                int sx = (int)FX.Floor(sxf), rx = sx - ox;
                if (rx < 0 || rx >= W) continue;
                o.Reset();
                fn(x + 0.5, y + 0.5, o);
                Write(f, row + rx, o.C, o.A * fade, o.B, by | (sx & 3), o.L, o.K * lk);
            }
        }
    }

    /// <summary>The fastest whole-sky shader: fn(y, row) fills one canvas row at a time (y the row's pixel centre),
    /// column i = x - box.X0.</summary>
    public static void Rows(Painter p, FXMeta meta, double y0In, double y1In, Action<double, FXWeatherRow> fn)
    {
        var B = BoxOf(meta);
        int w = B.W;
        var R = new FXWeatherRow(w);
        double y0 = Math.Max(B.Y0, FX.Floor(y0In)), y1 = Math.Min(B.Y1 - 1, FX.Ceil(y1In));
        var q = Rotated(p) ? new Clip(p, meta) : null;
        FXFrame f = p.Frame;
        int W = f.W, H = f.H, ox = f.Ox, oy = f.Oy;
        double fade = p.Fade, lk = p.LightK * fade, tx = p.ToX(0, 0), ty = p.ToY(0, 0), fx = p.ToX(1, 0) > tx ? 1 : -1;
        for (var y = y0; y <= y1; y += 1)
        {
            for (int i = 0; i < w; i++) { R.C[i] = 0; R.K[i] = 0; R.A[i] = 1; R.B[i] = false; }
            fn(y + 0.5, R);
            if (q != null)
            {
                for (int i = 0; i < w; i++)
                {
                    var x = B.X0 + i;
                    if (R.C[i] != 0) { if (R.B[i]) q.Blend(x, y, R.C[i], R.A[i]); else q.Dot(x, y, R.C[i], R.A[i]); }
                    if (R.K[i] > 0) q.Light(x, y, R.L[i] != 0 ? R.L[i] : R.C[i], R.K[i]);
                }
                continue;
            }
            int sy = (int)FX.Floor(ty + y + 0.5), ry = sy - oy;
            if (ry < 0 || ry >= H) continue;
            int row = ry * W, by = (sy & 3) << 2;
            var sxf = tx + (B.X0 + 0.5) * fx;
            for (int i = 0; i < w; i++, sxf += fx)
            {
                FXColor c = R.C[i];
                double kk = R.K[i];
                if (c == 0 && !(kk > 0)) continue;
                int sx = (int)FX.Floor(sxf), rx = sx - ox;
                if (rx < 0 || rx >= W) continue;
                Write(f, row + rx, c, (double)R.A[i] * fade, R.B[i], by | (sx & 3), R.L[i], kk * lk);
            }
        }
    }

    /// <summary>One pixel of <c>Pass</c> / <c>Rows</c>: a blend or a dithered colour, then light, written straight into the frame.</summary>
    static void Write(FXFrame f, int i, FXColor c, double a, bool blend, int cell, FXColor l, double k)
    {
        if (c != 0)
        {
            if (blend)
            {
                if (a > 0.004)
                {
                    var d = f.Color[i];
                    double da = (d >> 24) / 255d, oa = a + da * (1 - a), kk = a / oa, j = 1 - kk;
                    var r = FX.Byte((c & 255) * kk + (d & 255) * j);
                    var g = FX.Byte(((c >> 8) & 255) * kk + ((d >> 8) & 255) * j);
                    var b = FX.Byte(((c >> 16) & 255) * kk + ((d >> 16) & 255) * j);
                    f.Color[i] = (FX.Byte(oa * 255) << 24) | (b << 16) | (g << 8) | r;
                }
            }
            else if (a >= 1 || a > Painter.Bayer[cell]) f.Color[i] = c;
        }
        if (k > 0.004)
        {
            FXColor lc = l != 0 ? l : c, d = f.Light[i];
            var r = (uint)Math.Min(255, (d & 255) + (lc & 255) * k);
            var g = (uint)Math.Min(255, ((d >> 8) & 255) + ((lc >> 8) & 255) * k);
            var b = (uint)Math.Min(255, ((d >> 16) & 255) + ((lc >> 16) & 255) * k);
            f.Light[i] = (255u << 24) | (b << 16) | (g << 8) | r;
        }
    }

    /// <summary>Falling particles for a loop of D seconds: n slots, each falling m times a loop (m whole, m0..m1), each
    /// fall somewhere new. fn(u, k, m, i): u 0..1 through the current fall, k its number (Wrap(k, m) names it),
    /// m, the slot i. A fall lasts D / m s.</summary>
    public static void Trips(double t, double D, int n, double seed, double m0, double m1, Action<double, double, double, int> fn)
    {
        for (int i = 0; i < n; i++)
        {
            double m = m0 + FX.Floor(FX.Rand(seed, i, 72) * (m1 - m0 + 1)), s = (t / D) * m + FX.Rand(seed, i, 71), k = FX.Floor(s);
            fn(s - k, k, m, i);
        }
    }
}

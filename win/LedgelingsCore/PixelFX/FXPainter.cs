// The frame an effect draws into, and the painter that draws: pixelfx's `createFrame` and `Painter`
// (https://github.com/patch-gg/pixelfx, MIT). A frame holds opaque colour (faded with ordered dither,
// never blended, except the few translucent volumes) and additive light; `FXComposite` turns the two
// into the 1-bit picture the overlay shows. Effects draw in local coordinates around their origin; the
// painter places and mirrors them. The Mac's twin is FXPainter.swift.

using System.Runtime.CompilerServices;

namespace Ledgelings.Core.PixelFX;

/// <summary>w × h pixels whose top-left sits at (ox, oy).</summary>
public sealed class FXFrame
{
    public readonly int W, H;
    public int Ox, Oy;
    public readonly uint[] Color;
    public readonly uint[] Light;
    Painter? ownPainter;

    public FXFrame(int w, int h, int ox = 0, int oy = 0)
    {
        W = w; H = h; Ox = ox; Oy = oy;
        Color = new uint[w * h];
        Light = new uint[w * h];
    }

    public void Clear()
    {
        Array.Clear(Color);
        Array.Clear(Light);
    }

    /// <summary>The frame's own painter, made once.</summary>
    public Painter Painter => ownPainter ??= new Painter(this);
}

/// <summary>Which pass of an effect is being drawn: behind the creature, or in front of it.</summary>
public enum FXLayer { Back, Front }

/// <summary>What a pixel shader hands back: colour, alpha, light colour and amount.</summary>
public sealed class FXShadeOut
{
    public FXColor C;
    public double A = 1;
    public FXColor L;
    public double K;
}

/// <summary>A 1-bit shape: which pixels of a w × h box are on.</summary>
public sealed class FXMask(int w, int h, byte[] data)
{
    public readonly int W = w, H = h;
    public readonly byte[] Data = data;
}

public sealed class Painter
{
    /// <summary>4×4 ordered (Bayer) thresholds: a pixel at alpha a is drawn when a is above its cell's threshold.</summary>
    public static readonly double[] Bayer = new double[] { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }.Select(v => (v + 0.5) / 16).ToArray();

    public readonly FXFrame Frame;
    int w, h, ox, oy;
    double tx, ty, fx = 1, cs = 1, sn;
    public double Fade = 1;
    public double LightK = 1;
    public FXLayer Layer = FXLayer.Front;

    public Painter(FXFrame frame)
    {
        Frame = frame;
        w = frame.W; h = frame.H; ox = frame.Ox; oy = frame.Oy;
    }

    public Painter Reset()
    {
        w = Frame.W; h = Frame.H; ox = Frame.Ox; oy = Frame.Oy;
        tx = 0; ty = 0; fx = 1; cs = 1; sn = 0; Fade = 1; LightK = 1; Layer = FXLayer.Front;
        return this;
    }

    /// <summary>The effect's origin at (x, y) in frame space, mirrored if flip, rotated by angle.</summary>
    public Painter Place(double x, double y, bool flip = false, double angle = 0)
    {
        tx = x; ty = y; fx = flip ? -1 : 1; cs = Math.Cos(angle); sn = Math.Sin(angle);
        return this;
    }

    // Local space <-> frame space

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public double ToX(double x, double y) => tx + x * fx * cs - y * sn;
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public double ToY(double x, double y) => ty + x * fx * sn + y * cs;
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public double FromX(double sx, double sy) { double dx = sx - tx, dy = sy - ty; return (dx * cs + dy * sn) * fx; }
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public double FromY(double sx, double sy) { double dx = sx - tx, dy = sy - ty; return -dx * sn + dy * cs; }
    /// <summary>The frame pixel of the local pixel cell holding (x, y).</summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public int CellX(double x, double y) => (int)FX.Floor(ToX(FX.Floor(x) + 0.5, FX.Floor(y) + 0.5));
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public int CellY(double x, double y) => (int)FX.Floor(ToY(FX.Floor(x) + 0.5, FX.Floor(y) + 0.5));

    // Raw writes, frame space. Colour 0 is "nothing": it never erases.

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public void Put(int sx, int sy, FXColor c, double a = 1)
    {
        if (c == 0) return;
        a *= Fade;
        if (a < 1 && a <= Bayer[((sy & 3) << 2) | (sx & 3)]) return;
        int x = sx - ox, y = sy - oy;
        if (x < 0 || y < 0 || x >= w || y >= h) return;
        Frame.Color[y * w + x] = c;
    }
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public void Add(int sx, int sy, FXColor c, double k = 1)
    {
        k = k * Fade * LightK;
        if (k <= 0.004) return;
        int x = sx - ox, y = sy - oy;
        if (x < 0 || y < 0 || x >= w || y >= h) return;
        int i = y * w + x;
        var d = Frame.Light[i];
        var r = (uint)Math.Min(255, (d & 255) + (c & 255) * k);
        var g = (uint)Math.Min(255, ((d >> 8) & 255) + ((c >> 8) & 255) * k);
        var b = (uint)Math.Min(255, ((d >> 16) & 255) + ((c >> 16) & 255) * k);
        Frame.Light[i] = (255u << 24) | (b << 16) | (g << 8) | r;
    }
    /// <summary>A colour over what is there at alpha a, keeping the result's own alpha: soft smoke and mist.</summary>
    public void BlendPx(int sx, int sy, FXColor c, double a)
    {
        a *= Fade;
        if (c == 0 || a <= 0.004) return;
        int x = sx - ox, y = sy - oy;
        if (x < 0 || y < 0 || x >= w || y >= h) return;
        int i = y * w + x;
        var d = Frame.Color[i];
        double da = (d >> 24) / 255d, oa = a + da * (1 - a), k = a / oa;
        uint Ch(int s) => FX.Byte(((c >> s) & 255) * k + ((d >> s) & 255) * (1 - k));
        Frame.Color[i] = (FX.Byte(oa * 255) << 24) | (Ch(16) << 16) | (Ch(8) << 8) | Ch(0);
    }
    /// <summary>A translucent pixel at a local point.</summary>
    public void Blend(double x, double y, FXColor c, double a) => BlendPx(CellX(x, y), CellY(x, y), c, a);
    /// <summary>A translucent disc; c and a may depend on (d: 0 centre...1 rim, angle).</summary>
    public void Disc(double cx, double cy, double r, FXColor c, double a) => Disc(cx, cy, r, (_, _) => c, (_, _) => a);
    public void Disc(double cx, double cy, double r, Func<double, double, FXColor> c, Func<double, double, double> a)
    {
        if (r < 0.5) { Blend(cx, cy, c(0, 0), a(0, 0)); return; }
        Each(cx - r, cy - r, cx + r, cy + r, (x, y, sx, sy) =>
        {
            double dx = x - cx, dy = y - cy, d2 = dx * dx + dy * dy;
            if (d2 > r * r) return;
            double d = Math.Sqrt(d2) / r, ang = Math.Atan2(dy, dx);
            BlendPx(sx, sy, c(d, ang), a(d, ang));
        });
    }
    /// <summary>The colour under a local point (0 if empty).</summary>
    public FXColor Get(double x, double y)
    {
        int sx = CellX(x, y) - ox, sy = CellY(x, y) - oy;
        return sx < 0 || sy < 0 || sx >= w || sy >= h ? 0 : Frame.Color[sy * w + sx];
    }

    // Pixels

    /// <summary>One opaque pixel.</summary>
    public void Px(double x, double y, FXColor c) => Put(CellX(x, y), CellY(x, y), c, 1);
    /// <summary>One pixel at alpha a, faded by ordered dither.</summary>
    public void Dot(double x, double y, FXColor c, double a = 1) { if (a > 0) Put(CellX(x, y), CellY(x, y), c, a); }
    /// <summary>Light added to one pixel.</summary>
    public void Light(double x, double y, FXColor c, double k = 1) => Add(CellX(x, y), CellY(x, y), c, k);

    /// <summary>Every frame pixel whose centre falls in the local box, with that centre in local space: fn(lx, ly, sx, sy).</summary>
    public void Each(double x0, double y0, double x1, double y1, Action<double, double, int, int> fn)
    {
        double ax = double.PositiveInfinity, bx = double.NegativeInfinity, ay = double.PositiveInfinity, by = double.NegativeInfinity;
        for (int k = 0; k < 4; k++)
        {
            double x = (k & 1) != 0 ? x1 : x0, y = (k & 2) != 0 ? y1 : y0, sx = ToX(x, y), sy = ToY(x, y);
            if (sx < ax) ax = sx; if (sx > bx) bx = sx; if (sy < ay) ay = sy; if (sy > by) by = sy;
        }
        if (!double.IsFinite(ax) || !double.IsFinite(bx) || !double.IsFinite(ay) || !double.IsFinite(by)) return;
        int sx0 = Math.Max((int)FX.Floor(ax), ox), sx1 = Math.Min((int)FX.Ceil(bx), ox + w - 1);
        int sy0 = Math.Max((int)FX.Floor(ay), oy), sy1 = Math.Min((int)FX.Ceil(by), oy + h - 1);
        if (sx0 > sx1 || sy0 > sy1) return;
        for (int sy = sy0; sy <= sy1; sy++)
        {
            for (int sx = sx0; sx <= sx1; sx++)
            {
                double cx = sx + 0.5, cy = sy + 0.5;
                fn(FromX(cx, cy), FromY(cx, cy), sx, sy);
            }
        }
    }

    /// <summary>A pixel shader over a local box: fn(x, y, out) returns a colour, or sets out's fields; 0 leaves it alone.</summary>
    public void Shade(double x0, double y0, double x1, double y1, Func<double, double, FXShadeOut, FXColor> fn)
    {
        var o = new FXShadeOut();
        Each(x0, y0, x1, y1, (lx, ly, sx, sy) =>
        {
            o.C = 0; o.A = 1; o.L = 0; o.K = 0;
            var r = fn(lx, ly, o);
            var c = r != 0 ? r : o.C;
            if (c != 0) Put(sx, sy, c, o.A);
            if (o.K > 0) Add(sx, sy, o.L != 0 ? o.L : c, o.K);
        });
    }

    // Shapes

    /// <summary>A 1 px line; c and a may depend on u (0 at the start, 1 at the end).</summary>
    public void Line(double x0, double y0, double x1, double y1, FXColor c, double a = 1) => Line(x0, y0, x1, y1, _ => c, _ => a);
    public void Line(double x0, double y0, double x1, double y1, Func<double, FXColor> c, double a = 1) => Line(x0, y0, x1, y1, c, _ => a);
    public void Line(double x0, double y0, double x1, double y1, Func<double, FXColor> c, Func<double, double> a)
    {
        int sx = CellX(x0, y0), sy = CellY(x0, y0);
        int ex = CellX(x1, y1), ey = CellY(x1, y1);
        int dx = Math.Abs(ex - sx), dy = -Math.Abs(ey - sy), stepx = sx < ex ? 1 : -1, stepy = sy < ey ? 1 : -1;
        double n = Math.Max(dx, -dy) == 0 ? 1 : Math.Max(dx, -dy);
        int err = dx + dy;
        double i = 0;
        while (true)
        {
            var u = i / n;
            i += 1;
            Put(sx, sy, c(u), a(u));
            if (sx == ex && sy == ey) break;
            var e2 = 2 * err;
            if (e2 >= dy) { err += dy; sx += stepx; }
            if (e2 <= dx) { err += dx; sy += stepy; }
        }
    }
    /// <summary>Lines through a list of points.</summary>
    public void Polyline(IReadOnlyList<(double X, double Y)> pts, FXColor c, double a = 1)
    {
        for (int i = 1; i < pts.Count; i++) Line(pts[i - 1].X, pts[i - 1].Y, pts[i].X, pts[i].Y, c, a);
    }
    /// <summary>A thick segment with round ends; c and a may depend on (u along, v across: 0 centre, 1 edge).</summary>
    public void Beam(double x0, double y0, double x1, double y1, double width, FXColor c, double a = 1) =>
        Beam(x0, y0, x1, y1, width, (_, _) => c, (_, _) => a);
    public void Beam(double x0, double y0, double x1, double y1, double width,
                     Func<double, double, FXColor> c, Func<double, double, double> a)
    {
        double r = width / 2, dx = x1 - x0, dy = y1 - y0, l2r = dx * dx + dy * dy, L2 = l2r == 0 ? 1e-9 : l2r;
        Shade(Math.Min(x0, x1) - r, Math.Min(y0, y1) - r, Math.Max(x0, x1) + r, Math.Max(y0, y1) + r, (x, y, o) =>
        {
            double u = FX.Clamp(((x - x0) * dx + (y - y0) * dy) / L2), px = x0 + dx * u - x, py = y0 + dy * u - y;
            var d2 = px * px + py * py;
            if (d2 > r * r) return 0;
            var v = Math.Sqrt(d2) / r;
            o.C = c(u, v);
            o.A = a(u, v);
            return 0;
        });
    }
    /// <summary>A filled disc; c and a may depend on (d: 0 centre to 1 rim, angle).</summary>
    public void Circle(double cx, double cy, double r, FXColor c, double a = 1) => Circle(cx, cy, r, (_, _) => c, (_, _) => a);
    public void Circle(double cx, double cy, double r, Func<double, double, FXColor> c, Func<double, double, double> a)
    {
        if (r < 0.6) { Dot(cx, cy, c(0, 0), a(0, 0)); return; }
        Shade(cx - r, cy - r, cx + r, cy + r, (x, y, o) =>
        {
            double dx = x - cx, dy = y - cy, d2 = dx * dx + dy * dy;
            if (d2 > r * r) return 0;
            double d = Math.Sqrt(d2) / r, ang = Math.Atan2(dy, dx);
            o.C = c(d, ang);
            o.A = a(d, ang);
            return 0;
        });
    }
    /// <summary>An ellipse; c and a may depend on (d, angle).</summary>
    public void Ellipse(double cx, double cy, double rx, double ry, FXColor c, double a = 1) => Ellipse(cx, cy, rx, ry, (_, _) => c, (_, _) => a);
    public void Ellipse(double cx, double cy, double rx, double ry, Func<double, double, FXColor> c, Func<double, double, double> a)
    {
        if (rx <= 0 || ry <= 0) return;
        Shade(cx - rx, cy - ry, cx + rx, cy + ry, (x, y, o) =>
        {
            double dx = (x - cx) / rx, dy = (y - cy) / ry, d2 = dx * dx + dy * dy;
            if (d2 > 1) return 0;
            double d = Math.Sqrt(d2), ang = Math.Atan2(dy, dx);
            o.C = c(d, ang);
            o.A = a(d, ang);
            return 0;
        });
    }
    /// <summary>A ring from radius r - w to r; c and a may depend on (v: 0 inner to 1 outer, angle).</summary>
    public void Ring(double cx, double cy, double r, double w, FXColor c, double a = 1) => Ring(cx, cy, r, w, (_, _) => c, (_, _) => a);
    public void Ring(double cx, double cy, double r, double w, Func<double, double, FXColor> c, Func<double, double, double> a)
    {
        var r0 = Math.Max(0, r - w);
        Shade(cx - r, cy - r, cx + r, cy + r, (x, y, o) =>
        {
            double dx = x - cx, dy = y - cy, d2 = dx * dx + dy * dy;
            if (d2 > r * r || d2 < r0 * r0) return 0;
            var span = r - r0 == 0 ? 1 : r - r0;
            double v = w > 0 ? (Math.Sqrt(d2) - r0) / span : 1, ang = Math.Atan2(dy, dx);
            o.C = c(v, ang);
            o.A = a(v, ang);
            return 0;
        });
    }
    /// <summary>A band of a ring from angle a0 to a1 (a1 &gt; a0), radius r - w to r; c and a depend on (u: 0 at a0...1 at a1,
    /// v: 0 inner...1 outer); w may depend on u.</summary>
    public void Arc(double cx, double cy, double r, Func<double, double> w, double a0, double a1,
                    Func<double, double, FXColor> c, Func<double, double, double> a)
    {
        var span = a1 - a0;
        Shade(cx - r, cy - r, cx + r, cy + r, (x, y, o) =>
        {
            double dx = x - cx, dy = y - cy, d = Math.Sqrt(dx * dx + dy * dy);
            if (d > r) return 0;
            var ang = Math.Atan2(dy, dx) - a0;
            ang -= FX.Floor(ang / (Math.PI * 2)) * Math.PI * 2;
            if (ang > span) return 0;
            double u = ang / span, ww = w(u);
            if (ww <= 0 || d < r - ww) return 0;
            var v = (d - (r - ww)) / ww;
            o.C = c(u, v);
            o.A = a(u, v);
            return 0;
        });
    }
    public void Arc(double cx, double cy, double r, double w, double a0, double a1, FXColor c, double a = 1) =>
        Arc(cx, cy, r, _ => w, a0, a1, (_, _) => c, (_, _) => a);
    /// <summary>A filled rectangle.</summary>
    public void Rect(double x, double y, double w, double h, FXColor c, double a = 1)
    {
        if (sn == 0)
        {
            double X0 = FX.Round(x), Y0 = FX.Round(y), X1 = FX.Round(x + w), Y1 = FX.Round(y + h);
            for (var yy = Y0; yy < Y1; yy += 1)
                for (var xx = X0; xx < X1; xx += 1) Put(CellX(xx, yy), CellY(xx, yy), c, a);
            return;
        }
        Shade(x, y, x + w, y + h, (lx, ly, o) =>
        {
            if (lx < x || ly < y || lx >= x + w || ly >= y + h) return 0;
            o.C = c; o.A = a;
            return 0;
        });
    }
    /// <summary>A filled polygon (even-odd rule); c and a may depend on (x, y).</summary>
    public void Poly(IReadOnlyList<(double X, double Y)> pts, FXColor c, double a = 1) => Poly(pts, (_, _) => c, (_, _) => a);
    public void Poly(IReadOnlyList<(double X, double Y)> pts, Func<double, double, FXColor> c, Func<double, double, double> a)
    {
        double x0 = double.PositiveInfinity, y0 = double.PositiveInfinity, x1 = double.NegativeInfinity, y1 = double.NegativeInfinity;
        foreach (var (x, y) in pts) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
        var n = pts.Count;
        Shade(x0, y0, x1, y1, (x, y, o) =>
        {
            bool inside = false;
            int j = n - 1;
            for (int i = 0; i < n; i++)
            {
                var (xi, yi) = pts[i];
                var (xj, yj) = pts[j];
                if ((yi > y) != (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
                j = i;
            }
            if (!inside) return 0;
            o.C = c(x, y);
            o.A = a(x, y);
            return 0;
        });
    }
    public void Tri(double x0, double y0, double x1, double y1, double x2, double y2, FXColor c, double a = 1) =>
        Poly([(x0, y0), (x1, y1), (x2, y2)], c, a);

    // Light

    /// <summary>A radial glow: k at the centre, falling to 0 at radius r.</summary>
    public void Glow(double x, double y, double r, FXColor c, double k = 0.5)
    {
        if (r < 1 || k <= 0.004) return;
        double cx = ToX(x, y), cy = ToY(x, y);
        int x0 = (int)FX.Floor(cx - r), x1 = (int)FX.Ceil(cx + r), y0 = (int)FX.Floor(cy - r), y1 = (int)FX.Ceil(cy + r);
        for (int sy = y0; sy <= y1; sy++)
        {
            var dy = (sy + 0.5 - cy) / r;
            for (int sx = x0; sx <= x1; sx++)
            {
                double dx = (sx + 0.5 - cx) / r, d = dx * dx + dy * dy;
                if (d >= 1) continue;
                var f = 1 - Math.Sqrt(d);
                Add(sx, sy, c, f * f * k);
            }
        }
    }
    /// <summary>A glow around a segment.</summary>
    public void GlowLine(double x0, double y0, double x1, double y1, double r, FXColor c, double k = 0.5)
    {
        if (r < 1 || k <= 0.004) return;
        double ax = ToX(x0, y0), ay = ToY(x0, y0), bx = ToX(x1, y1), by = ToY(x1, y1);
        double dx = bx - ax, dy = by - ay, l2r = dx * dx + dy * dy, L2 = l2r == 0 ? 1e-9 : l2r;
        int X0 = (int)FX.Floor(Math.Min(ax, bx) - r), X1 = (int)FX.Ceil(Math.Max(ax, bx) + r);
        int Y0 = (int)FX.Floor(Math.Min(ay, by) - r), Y1 = (int)FX.Ceil(Math.Max(ay, by) + r);
        for (int sy = Y0; sy <= Y1; sy++)
        {
            for (int sx = X0; sx <= X1; sx++)
            {
                double px = sx + 0.5, py = sy + 0.5, u = FX.Clamp(((px - ax) * dx + (py - ay) * dy) / L2);
                double ex = ax + dx * u - px, ey = ay + dy * u - py, d = Math.Sqrt(ex * ex + ey * ey) / r;
                if (d >= 1) continue;
                var f = 1 - d;
                Add(sx, sy, c, f * f * k);
            }
        }
    }
    /// <summary>A glow hugging a circle of radius R, falling off over width r.</summary>
    public void GlowRing(double x, double y, double R, double r, FXColor c, double k = 0.5)
    {
        if (r < 1 || k <= 0.004) return;
        double cx = ToX(x, y), cy = ToY(x, y), E = R + r;
        for (int sy = (int)FX.Floor(cy - E), sy1 = (int)FX.Ceil(cy + E); sy <= sy1; sy++)
        {
            for (int sx = (int)FX.Floor(cx - E), sx1 = (int)FX.Ceil(cx + E); sx <= sx1; sx++)
            {
                var d = Math.Abs(FX.Hypot(sx + 0.5 - cx, sy + 0.5 - cy) - R) / r;
                if (d >= 1) continue;
                var f = 1 - d;
                Add(sx, sy, c, f * f * k);
            }
        }
    }

    // Sprites, text, masks

    /// <summary>A little sprite from strings ("." and " " empty), top-left at (x, y); pal maps characters to colours.</summary>
    public void Sprite(IReadOnlyList<string> rows, IReadOnlyDictionary<char, FXColor> pal, double x, double y,
                       double scale = 1, double a = 1, bool flip = false, bool flipY = false, FXColor? tint = null)
    {
        var k = scale;
        var W = rows.Count > 0 ? rows[0].Length : 0;
        for (int r = 0; r < rows.Count; r++)
        {
            var s = rows[r];
            for (int q = 0; q < s.Length; q++)
            {
                var ch = s[q];
                if (ch == '.' || ch == ' ') continue;
                var c = tint ?? (pal.TryGetValue(ch, out var pc) ? pc : 0);
                if (c == 0) continue;
                double col = flip ? W - 1 - q : q, row = flipY ? rows.Count - 1 - r : r;
                if (k == 1) Dot(x + col, y + row, c, a); else Rect(x + col * k, y + row * k, k, k, c, a);
            }
        }
    }
    /// <summary>Pixel text, its top at y, set left, centre or right of x.</summary>
    public void Text(string str, double x, double y, FXColor c, FXFont? font = null, double scale = 1,
                     FXFont.Align align = FXFont.Align.Left, FXColor? outline = null, FXColor? shadow = null, double a = 1) =>
        Text(str, x, y, (_, _) => c, font, scale, align, outline, shadow, a);
    public void Text(string str, double x, double y, Func<double, double, FXColor> c, FXFont? font = null, double scale = 1,
                     FXFont.Align align = FXFont.Align.Left, FXColor? outline = null, FXColor? shadow = null, double a = 1)
    {
        font ??= FXFont.Mini;
        var k = scale;
        var w = font.Width(str) * k;
        double left = FX.Round(align == FXFont.Align.Center ? x - w / 2 : align == FXFont.Align.Right ? x - w : x), top = FX.Round(y);
        if (outline is { } ol) font.Raster(str, (gx, gy) => Rect(left + gx * k - 1, top + gy * k - 1, k + 2, k + 2, ol, a));
        if (shadow is { } sh) font.Raster(str, (gx, gy) => Rect(left + gx * k + 1, top + gy * k + 1, k, k, sh, a));
        font.Raster(str, (gx, gy) => Rect(left + gx * k, top + gy * k, k, k, c(gx, gy), a));
    }
    /// <summary>Fill a mask with its top-left at (x, y); c may depend on (mx, my).</summary>
    public void Mask(FXMask m, double x, double y, Func<int, int, FXColor> c, Func<int, int, double>? a = null)
    {
        for (int my = 0; my < m.H; my++)
            for (int mx = 0; mx < m.W; mx++)
                if (m.Data[my * m.W + mx] != 0) Dot(x + mx, y + my, c(mx, my), a?.Invoke(mx, my) ?? 1);
    }
    /// <summary>The 1 px outline just outside a mask.</summary>
    public void Outline(FXMask m, double x, double y, Func<int, int, FXColor> c, Func<int, int, double>? a = null)
    {
        bool At(int mx, int my) => mx >= 0 && my >= 0 && mx < m.W && my < m.H && m.Data[my * m.W + mx] != 0;
        for (int my = -1; my <= m.H; my++)
            for (int mx = -1; mx <= m.W; mx++)
                if (!At(mx, my) && (At(mx - 1, my) || At(mx + 1, my) || At(mx, my - 1) || At(mx, my + 1)))
                    Dot(x + mx, y + my, c(mx, my), a?.Invoke(mx, my) ?? 1);
    }
}

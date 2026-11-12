// Shared by the arcane effects: the ordered dither, rings lying on the floor, an original rune alphabet, and the
// caster's silhouette shaded and squeezed for the blink. Ported from pixelfx's `fx/arcane/_lib.js` (MIT); its
// dithered ramp and the blink's squeeze adapt Sprite Fusion's open-source black hole and blink
// (https://www.spritefusion.com/pixel-art-vfx), MIT, Copyright (c) 2026 Hugo Duprez.
// The Mac's twin is ArcaneLib.swift.

namespace Ledgelings.Core.PixelFX;

public static class FXArcane
{
    static readonly IReadOnlyDictionary<char, FXColor> NoPalette = new Dictionary<char, FXColor>();

    /// <summary>The 4x4 ordered-dither threshold (0..1) of the pixel cell holding (x, y).</summary>
    public static double Bayer(double x, double y) => Painter.Bayer[(((int)FX.Floor(y) & 3) << 2) | ((int)FX.Floor(x) & 3)];

    /// <summary>A ring lying on the floor: centre (cx, cy), radius r, squashed by sy, 1 px thick at any size. c and a
    /// are functions of the angle g round it; keep(g) picks which part to draw.</summary>
    public static void FloorRing(Painter p, double cx, double cy, double r, double sy,
                                 Func<double, FXColor> c, Func<double, double> a, Func<double, bool>? keep = null)
    {
        if (r < 0.5) return;
        var ry = r * sy;
        p.Shade(cx - r - 1, cy - ry - 1, cx + r + 1, cy + ry + 1, (x, y, o) =>
        {
            double nx = (x - cx) / r, ny = (y - cy) / Math.Max(0.3, ry), d = FX.Hypot(nx, ny);
            if (d < 1e-6) return 0;
            var g = FX.Hypot(nx / r, ny / Math.Max(0.3, ry)) / d;
            if (Math.Abs(d - 1) / g > 0.5) return 0;
            var ang = Math.Atan2(ny, nx);
            if (keep != null && !keep(ang)) return 0;
            o.C = c(ang);
            o.A = a(ang);
            return 0;
        });
    }

    /// <summary>An original rune alphabet: angular 3 x 5 glyphs that stay readable standing upright at 1x.</summary>
    public static readonly string[][] Glyphs =
    [
        [".#.", "#.#", ".#.", ".#.", "#.#"],
        ["#.#", "#.#", ".#.", "#.#", "#.#"],
        ["##.", "#.#", "##.", "#..", "#.."],
        ["#..", "#.#", "###", "#.#", "..#"],
        [".##", "#..", ".#.", "..#", "##."],
        ["###", ".#.", "###", ".#.", ".#."],
        ["#.#", "###", "#.#", "..#", "..#"],
        [".#.", ".##", ".#.", "##.", ".#."],
    ];

    /// <summary>Rune i standing on (x, y): its bottom row on y, centred on x, over an optional darker colour a pixel lower.</summary>
    public static void Glyph(Painter p, int i, double x, double y, FXColor c, double a = 1, FXColor under = 0)
    {
        int n = Glyphs.Length;
        var g = Glyphs[((i % n) + n) % n];
        double X = FX.Round(x) - 1, Y = FX.Round(y) - g.Length + 1;
        if (under != 0) p.Sprite(g, NoPalette, X, Y + 1, a: a, tint: under);
        p.Sprite(g, NoPalette, X, Y, a: a, tint: c);
    }

    /// <summary>A character's silhouette shaded by how light each pixel is: 1 its dark outline, 2 mid, 3 light (0 empty).</summary>
    public static byte[] Shades(FXActor A)
    {
        var s = new byte[A.W * A.H];
        for (int i = 0; i < s.Length; i++)
        {
            if (A.Mask.Data[i] == 0) continue;
            var l = FX.Luma(A.Pixels[i]);
            s[i] = (byte)(l < 0.24 ? 1 : l < 0.62 ? 2 : 3);
        }
        return s;
    }

    /// <summary>Silhouette A squeezed to sx of its width about its middle and shifted by dx: body colour on its pixels,
    /// edge colour on its dark outline pixels. sh is Shades(A).</summary>
    public static void Squeezed(Painter p, FXActor A, byte[] sh, double sx, FXColor body, FXColor edge, double a = 1, double dx = 0)
    {
        if (sx <= 0.02) return;
        double cx = A.X + A.W / 2.0, half = A.W / 2.0 + 1;
        for (int y = 0; y < A.H; y++)
        {
            var x1 = FX.Ceil(cx + half * sx);
            for (var x = FX.Floor(cx - half * sx); x <= x1; x += 1)
            {
                var i = (int)FX.Round(cx + (x + 0.5 - cx) / sx - 0.5) - A.X;
                var v = i < 0 || i >= A.W ? 0 : sh[y * A.W + i];
                if (v != 0) p.Dot(x + dx, A.Y + y, v == 1 ? edge : body, a);
            }
        }
    }
}

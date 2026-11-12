// Shared by the nature effects: a leaf that turns and flips about its midrib. Ported from pixelfx's
// `fx/nature/_lib.js` (MIT). The Mac's twin is NatureLib.swift.

namespace Ledgelings.Core.PixelFX;

public static class FXNature
{
    /// <summary>A leaf len px long and wid px across at its widest, centred on (x, y), turned by ang and flipping about
    /// its midrib by fl (radians: edge on at pi/2, its paler underside showing past it). pal: [dark, shade, body, light].</summary>
    public static void DrawLeaf(Painter p, double x, double y, double len, double wid, double ang, double fl, FXColor[] pal, double alpha = 1)
    {
        double ca = Math.Cos(ang), sa = Math.Sin(ang), sq = Math.Cos(fl), w = Math.Max(0.55, Math.Abs(sq) * wid);
        var under = sq < 0;
        var R = (int)FX.Ceil(len / 2 + 2);
        double X = FX.Round(x), Y = FX.Round(y);
        int Inside(int i, int j)
        {
            double fi = i + 0.5, fj = j + 0.5;
            double u = fi * ca + fj * sa + len / 2, v = -fi * sa + fj * ca;
            if (u < 0 || u > len) return 0;
            var half = w * Math.Pow(Math.Sin((Math.PI * u) / len), 0.75);
            return Math.Abs(v) <= half ? (v < 0 ? 1 : 2) : 0;
        }
        for (int j = -R; j <= R; j++)
            for (int i = -R; i <= R; i++)
            {
                var s = Inside(i, j);
                if (s == 0)
                {
                    if (Inside(i - 1, j) != 0 || Inside(i + 1, j) != 0 || Inside(i, j - 1) != 0 || Inside(i, j + 1) != 0)
                        p.Dot(X + i, Y + j, pal[0], alpha);
                    continue;
                }
                double fi = i + 0.5, fj = j + 0.5;
                double u = fi * ca + fj * sa + len / 2, v = -fi * sa + fj * ca;
                var rib = Math.Abs(v) < 0.5 && u > len * 0.12 && u < len * 0.88 && w > 1.2;
                p.Dot(X + i, Y + j, rib ? pal[1] : (s == 1) != under ? pal[3] : pal[2], alpha);
            }
        // the stem trails off the base
        p.Dot(X - ca * (len / 2 + 1), Y - sa * (len / 2 + 1), pal[1], alpha);
    }
}

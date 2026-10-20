using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;

namespace Ledgelings;

/// <summary>Words drawn the way the creatures are: small, blocky letters with no smoothing, a 1-pixel dark outline
/// round them, on a flat plate with a light line along its top and left and a shade line along its bottom and
/// right. For the ball games' scoreboard and their GOAL! and HOME RUN! The overlay draws the result scaled up with
/// square pixels, like any sprite. The Mac's <c>PixelText</c>.</summary>
public static class PixelText
{
    /// <param name="Plate">The plate behind the letters; null for letters alone.</param>
    public sealed record Style(Color Ink, Color? Plate, float Size);

    /// <summary>The scoreboard: pale yellow on a dark plate.</summary>
    public static readonly Style Board = new(Color.FromArgb(250, 222, 110), Color.FromArgb(46, 50, 74), 8);
    /// <summary>A cheer across the screen: big, bright, no plate.</summary>
    public static readonly Style Banner = new(Color.FromArgb(255, 214, 70), null, 13);

    /// <summary><paramref name="text"/> in <paramref name="style"/>, one bitmap pixel per sheet pixel.</summary>
    public static Bitmap? Image(string text, Style style)
    {
        using var font = new Font("Verdana", style.Size, FontStyle.Bold, GraphicsUnit.Pixel);
        var family = font.FontFamily;
        var em = family.GetEmHeight(FontStyle.Bold);
        var ascent = style.Size * family.GetCellAscent(FontStyle.Bold) / em;
        var descent = style.Size * family.GetCellDescent(FontStyle.Bold) / em;
        var format = (StringFormat)StringFormat.GenericTypographic.Clone();
        format.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces;
        int width;
        using (var probe = new Bitmap(1, 1))
        using (var g = Graphics.FromImage(probe))
        {
            g.TextRenderingHint = TextRenderingHint.SingleBitPerPixelGridFit;
            width = (int)Math.Ceiling(g.MeasureString(text, font, PointF.Empty, format).Width);
        }
        var pad = style.Plate is null ? 1 : 4;
        int w = width + pad * 2, h = (int)Math.Ceiling(ascent + descent) + pad * 2;
        if (w <= 2 || h <= 2) return null;

        // The letters, hard-edged: white on black, row 0 the top.
        var mask = new bool[w * h];
        using (var letters = new Bitmap(w, h, PixelFormat.Format32bppArgb))
        {
            using (var g = Graphics.FromImage(letters))
            {
                g.Clear(Color.Black);
                g.TextRenderingHint = TextRenderingHint.SingleBitPerPixelGridFit;
                g.DrawString(text, font, Brushes.White, new PointF(pad, pad), format);
            }
            var data = letters.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            var row = new byte[w * 4];
            for (int y = 0; y < h; y++)
            {
                Marshal.Copy(data.Scan0 + y * data.Stride, row, 0, row.Length);
                for (int x = 0; x < w; x++) mask[y * w + x] = row[x * 4 + 2] > 127;
            }
            letters.UnlockBits(data);
        }
        bool Lit(int x, int y) => x >= 0 && y >= 0 && x < w && y < h && mask[y * w + x];

        // BGRA, as a 32-bit ARGB bitmap lies in memory.
        var pixels = new byte[w * h * 4];
        void Put(int x, int y, Color c)
        {
            var k = (y * w + x) * 4;
            pixels[k] = c.B; pixels[k + 1] = c.G; pixels[k + 2] = c.R; pixels[k + 3] = 255;
        }
        static Color Mix(Color c, int to, double share)
        {
            int M(int v) => (int)(v + (to - v) * share);
            return Color.FromArgb(M(c.R), M(c.G), M(c.B));
        }
        if (style.Plate is Color plate)
        {
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    var edge = x == 0 || y == 0 || x == w - 1 || y == h - 1;
                    var colour = edge ? Mix(plate, 0, 0.6) : (x == 1 || y == 1) ? Mix(plate, 255, 0.25)
                        : (x == w - 2 || y == h - 2) ? Mix(plate, 0, 0.25) : plate;
                    Put(x, y, colour);
                }
        }
        var outline = Mix(style.Ink, 0, 0.78);
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                if (Lit(x, y)) continue;
                var near = false;
                for (int dy = -1; dy <= 1 && !near; dy++)
                    for (int dx = -1; dx <= 1 && !near; dx++) near = Lit(x + dx, y + dy);
                if (near) Put(x, y, outline);
            }
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                if (!Lit(x, y)) continue;
                bool top = !Lit(x, y - 1) || !Lit(x - 1, y), bottom = !Lit(x, y + 1) || !Lit(x + 1, y);
                Put(x, y, top && !bottom ? Mix(style.Ink, 255, 0.3) : bottom && !top ? Mix(style.Ink, 0, 0.15) : style.Ink);
            }

        var image = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        var target = image.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        for (int y = 0; y < h; y++) Marshal.Copy(pixels, y * w * 4, target.Scan0 + y * target.Stride, w * 4);
        image.UnlockBits(target);
        return image;
    }
}

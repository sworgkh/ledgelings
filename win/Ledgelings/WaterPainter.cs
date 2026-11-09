using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>One monitor's water for one frame, in GLOBAL coordinates (<c>Colony.Dive</c>).</summary>
public sealed record WaterSnapshot(Rect Pool, double Surface, double Opacity, double Time, double Scale, Size Cell,
                                   IReadOnlyList<WaterSnapshot.Sprite> Critters, IReadOnlyList<WaterSnapshot.Sprite> Bubbles,
                                   IReadOnlyList<WaterSnapshot.Weed> Weeds, Bitmap? Coral)
{
    public sealed record Sprite(Bitmap? Image, Pt Centre, bool Mirrored);
    public sealed record Weed(double X, int Height, double Phase);
}

/// <summary>Paints the water as pixel art a few hundred pixels wide, which the overlay draws magnified with square
/// pixels, as the Mac's <c>WaterPainter</c> does: flat bands, no gradients. The BACK picture goes behind the
/// creatures (the water, light rays, caustics, the seaweed and coral, the sea life), the FRONT one over them (a
/// thin tint, the wavy surface with its foam, the bubbles).</summary>
public static class WaterPainter
{
    /// <summary>How many pixels of air over the surface the pictures keep, for the waves.</summary>
    public const int Headroom = 4;

    private static readonly (double R, double G, double B) Deep = (18, 74, 128), Water = (40, 120, 182), Ray = (96, 170, 220),
        Caustic = (170, 226, 246), Foam = (236, 248, 252), SurfaceLine = (120, 196, 236),
        WeedBody = (70, 150, 70), WeedLight = (110, 186, 96), WeedEdge = (22, 52, 26);

    /// <summary>The pictures' size in water pixels, and where they sit in global points.</summary>
    public static (int Width, int Height, Rect Frame) Layout(WaterSnapshot w)
    {
        var s = Math.Max(1, w.Scale);
        var width = (int)Math.Ceiling(w.Pool.Width / s);
        var deep = Math.Max(0, (int)Math.Round((w.Surface - w.Pool.MinY) / s));
        var height = deep + Headroom;
        return (width, height, new Rect(w.Pool.MinX, w.Pool.MinY, width * s, height * s));
    }

    /// <summary>The surface's wave at column <paramref name="x"/>, in pixels up (+) or down (-).</summary>
    public static int Wave(int x, double t) => (int)Math.Round(Math.Sin(x * 0.21 + t * 2.1) * 0.9 + Math.Sin(x * 0.07 - t * 1.3) * 0.8);

    private sealed class Canvas
    {
        public readonly int Width, Height;
        public readonly int[] Px;
        public Canvas(int width, int height) { Width = width; Height = height; Px = new int[width * height]; }

        /// <summary>Premultiplied ARGB, <paramref name="y"/> counted up from the bottom row.</summary>
        public void Put(int x, int y, (double R, double G, double B) c, double alpha)
        {
            if (x < 0 || x >= Width || y < 0 || y >= Height) return;
            var a = Math.Clamp(alpha, 0, 1);
            Px[(Height - 1 - y) * Width + x] = ((int)(255 * a) << 24) | ((int)(c.R * a) << 16) | ((int)(c.G * a) << 8) | (int)(c.B * a);
        }

        public Bitmap ToBitmap()
        {
            var bitmap = new Bitmap(Width, Height, PixelFormat.Format32bppPArgb);
            var data = bitmap.LockBits(new Rectangle(0, 0, Width, Height), ImageLockMode.WriteOnly, PixelFormat.Format32bppPArgb);
            for (int row = 0; row < Height; row++) Marshal.Copy(Px, row * Width, data.Scan0 + row * data.Stride, Width);
            bitmap.UnlockBits(data);
            return bitmap;
        }
    }

    public static Bitmap? Back(WaterSnapshot w)
    {
        var (width, height, _) = Layout(w);
        if (width <= 0 || height <= Headroom) return null;
        var deepRows = height - Headroom;
        var canvas = new Canvas(width, height);
        double a = w.Opacity * 0.8, t = w.Time;
        var deepBand = Math.Max(2, deepRows / 4);
        for (int y = 0; y < deepRows; y++)
        {
            var fromTop = deepRows - 1 - y;
            for (int x = 0; x < width; x++)
            {
                // Under the wave's trough only: above it is air.
                if (fromTop + Wave(x, t) < 0) continue;
                var colour = y < deepBand ? Deep : Water;
                var alpha = a;
                // Light rays: slanting bands from the surface, fading in steps on the way down.
                var band = (x + fromTop * 0.45 + t * 2.5) % 46;
                if (band < 5 && fromTop < deepRows * 3 / 4) { colour = Ray; alpha = a * (fromTop < deepRows / 3 ? 1 : 0.8); }
                // Caustics: the moving net of light, bright on the floor and faint above.
                var c = Math.Sin(x * 0.42 + t * 1.3) + Math.Sin(y * 0.61 - t * 1.1 + x * 0.17) + Math.Sin((x + y) * 0.23 + t * 0.8);
                if (y < 6 ? c > 1.9 : y < deepRows / 2 && c > 2.55) { colour = Caustic; alpha = a * 1.25; }
                canvas.Put(x, y, colour, alpha);
            }
        }
        // Seaweed swaying on the floor: a two-pixel strand, outlined, bending more towards its tip.
        foreach (var weed in w.Weeds)
        {
            var bottom = (int)Math.Round((weed.X - w.Pool.MinX) / Math.Max(1, w.Scale));
            var tall = Math.Min(weed.Height, Math.Max(0, deepRows - 3));
            var last = bottom;
            for (int j = 0; j < tall; j++)
            {
                var lean = Math.Sin(weed.Phase + t * 1.2 + j * 0.22) * j / Math.Max(1, tall) * 3.2;
                var x = bottom + (int)Math.Round(lean);
                canvas.Put(x - 1, j, WeedEdge, 1); canvas.Put(x + 2, j, WeedEdge, 1);
                canvas.Put(x, j, WeedLight, 1); canvas.Put(x + 1, j, WeedBody, 1);
                if (x != last) canvas.Put(Math.Min(x, last) + 1, j, x > last ? WeedLight : WeedBody, 1);
                last = x;
            }
            canvas.Put(last, tall, WeedEdge, 1); canvas.Put(last + 1, tall, WeedEdge, 1);
        }
        var bitmap = canvas.ToBitmap();
        Draw(bitmap, w, w.Critters, coralEvery: 3);
        return bitmap;
    }

    public static Bitmap? Front(WaterSnapshot w)
    {
        var (width, height, _) = Layout(w);
        if (width <= 0 || height <= Headroom) return null;
        var deepRows = height - Headroom;
        var canvas = new Canvas(width, height);
        var t = w.Time;
        var tint = w.Opacity * 0.28;
        for (int x = 0; x < width; x++)
        {
            var top = deepRows - 1 + Wave(x, t);
            for (int y = 0; y < Math.Max(0, top); y++) canvas.Put(x, y, Water, tint);
            // The surface: a foam line on the crest, a light line under it, foam flecks riding the crests.
            canvas.Put(x, top, Foam, 0.9);
            canvas.Put(x, top - 1, SurfaceLine, 0.75);
            if ((x + (int)(t * 6)) % 17 == 0) canvas.Put(x, top + 1, Foam, 0.8);
        }
        var bitmap = canvas.ToBitmap();
        Draw(bitmap, w, w.Bubbles, coralEvery: 0);
        return bitmap;
    }

    /// <summary><paramref name="sprites"/> (one sheet pixel to one water pixel) over the picture, and a coral clump at
    /// every <paramref name="coralEvery"/>-th weed.</summary>
    private static void Draw(Bitmap onto, WaterSnapshot w, IReadOnlyList<WaterSnapshot.Sprite> sprites, int coralEvery)
    {
        if (sprites.Count == 0 && coralEvery == 0) return;
        using var g = Graphics.FromImage(onto);
        g.InterpolationMode = InterpolationMode.NearestNeighbor;
        g.PixelOffsetMode = PixelOffsetMode.Half;
        g.SmoothingMode = SmoothingMode.None;
        double s = Math.Max(1, w.Scale), cw = w.Cell.Width, ch = w.Cell.Height;
        // Picture rows count down from the top; water heights count up from the floor.
        float Row(double up) => (float)(onto.Height - up);
        if (coralEvery > 0 && w.Coral is Bitmap coral)
            for (int k = 1; k < w.Weeds.Count; k += coralEvery)
            {
                var x = Math.Round((w.Weeds[k].X - w.Pool.MinX) / s) + 14;
                g.DrawImage(coral, new RectangleF((float)(x - cw / 2), Row(ch / 2 + 4), (float)cw, (float)ch));
            }
        foreach (var sprite in sprites)
        {
            if (sprite.Image is not Bitmap picture) continue;
            var x = Math.Round((sprite.Centre.X - w.Pool.MinX) / s);
            var y = Math.Round((sprite.Centre.Y - w.Pool.MinY) / s);
            var state = g.Save();
            g.TranslateTransform((float)x, Row(y));
            if (sprite.Mirrored) g.ScaleTransform(-1, 1);
            g.DrawImage(picture, new RectangleF((float)(-cw / 2), (float)(-ch / 2), (float)cw, (float)ch));
            g.Restore(state);
        }
    }
}

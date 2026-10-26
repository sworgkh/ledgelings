using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Ledgelings.UI;

/// <summary>A pixel picture (rows of <c>#</c> ink and <c>.</c> paper, the Mac's 11×11 icons) as an image in one
/// colour, drawn square and sharp at any size: the settings sidebar, the Tools tiles, the translator's buttons.</summary>
public static class PixelGlyph
{
    public static BitmapSource Source(IReadOnlyList<string> rows, Color ink)
    {
        var w = rows.Max(r => r.Length);
        var h = rows.Count;
        var pixels = new byte[w * h * 4];
        for (var y = 0; y < h; y++)
            for (var x = 0; x < rows[y].Length; x++)
            {
                if (rows[y][x] != '#') continue;
                var i = (y * w + x) * 4;
                // Premultiplied BGRA, fully opaque.
                pixels[i] = ink.B; pixels[i + 1] = ink.G; pixels[i + 2] = ink.R; pixels[i + 3] = 255;
            }
        var bitmap = BitmapSource.Create(w, h, 96, 96, PixelFormats.Pbgra32, null, pixels, w * 4);
        bitmap.Freeze();
        return bitmap;
    }

    /// <summary>The picture as an element, <paramref name="pixel"/> device-independent pixels to a pixel of it.</summary>
    public static Image Image(IReadOnlyList<string> rows, Color ink, double pixel = 1.5)
    {
        var image = new Image
        {
            Source = Source(rows, ink),
            Width = rows.Max(r => r.Length) * pixel,
            Height = rows.Count * pixel,
            Stretch = Stretch.Fill,
            SnapsToDevicePixels = true,
        };
        RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.NearestNeighbor);
        return image;
    }
}

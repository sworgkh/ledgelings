using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>PNG files in and out of the app's own RGBA byte image, and GDI+ bitmaps for drawing.</summary>
public static class PngIO
{
    /// <summary>The file as straight (not premultiplied) RGBA bytes, rows top to bottom.</summary>
    public static SpriteText.Image Read(string path)
    {
        using var loaded = new Bitmap(path);
        using var bmp = new Bitmap(loaded.Width, loaded.Height, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp))
        {
            g.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy;
            g.DrawImage(loaded, 0, 0, loaded.Width, loaded.Height);
        }
        var data = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            var rgba = new byte[bmp.Width * bmp.Height * 4];
            var row = new byte[data.Stride];
            for (int y = 0; y < bmp.Height; y++)
            {
                Marshal.Copy(data.Scan0 + y * data.Stride, row, 0, data.Stride);
                for (int x = 0; x < bmp.Width; x++)
                {
                    var s = x * 4;
                    var d = (y * bmp.Width + x) * 4;
                    rgba[d] = row[s + 2]; rgba[d + 1] = row[s + 1]; rgba[d + 2] = row[s]; rgba[d + 3] = row[s + 3];
                }
            }
            return new SpriteText.Image(bmp.Width, bmp.Height, rgba);
        }
        finally { bmp.UnlockBits(data); }
    }

    public static void Write(SpriteText.Image image, string path)
    {
        using var bmp = ToBitmap(image, new Rectangle(0, 0, image.Width, image.Height), PixelFormat.Format32bppArgb);
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        bmp.Save(path, ImageFormat.Png);
    }

    /// <summary>A GDI+ bitmap of one region of the image, premultiplied for fast drawing.
    /// Pixel art has 1-bit alpha, so premultiplying is a no-op for every opaque pixel.</summary>
    public static Bitmap ToBitmap(SpriteText.Image image, Rectangle region, PixelFormat format = PixelFormat.Format32bppPArgb)
    {
        var bmp = new Bitmap(region.Width, region.Height, format);
        var data = bmp.LockBits(new Rectangle(0, 0, region.Width, region.Height), ImageLockMode.WriteOnly, format);
        try
        {
            var row = new byte[data.Stride];
            for (int y = 0; y < region.Height; y++)
            {
                Array.Clear(row);
                for (int x = 0; x < region.Width; x++)
                {
                    var sx = region.X + x;
                    var sy = region.Y + y;
                    if (sx < 0 || sy < 0 || sx >= image.Width || sy >= image.Height) continue;
                    var s = (sy * image.Width + sx) * 4;
                    var a = image.Rgba[s + 3];
                    var d = x * 4;
                    if (format == PixelFormat.Format32bppPArgb && a < 255)
                    {
                        row[d] = (byte)(image.Rgba[s + 2] * a / 255);
                        row[d + 1] = (byte)(image.Rgba[s + 1] * a / 255);
                        row[d + 2] = (byte)(image.Rgba[s] * a / 255);
                    }
                    else
                    {
                        row[d] = image.Rgba[s + 2]; row[d + 1] = image.Rgba[s + 1]; row[d + 2] = image.Rgba[s];
                    }
                    row[d + 3] = a;
                }
                Marshal.Copy(row, 0, data.Scan0 + y * data.Stride, data.Stride);
            }
        }
        finally { bmp.UnlockBits(data); }
        return bmp;
    }
}

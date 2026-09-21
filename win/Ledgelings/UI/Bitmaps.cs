using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Ledgelings.UI;

/// <summary>GDI+ bitmaps as WPF image sources, for the settings window.</summary>
public static class Bitmaps
{
    public static BitmapSource ToSource(System.Drawing.Bitmap bitmap)
    {
        var rect = new System.Drawing.Rectangle(0, 0, bitmap.Width, bitmap.Height);
        var data = bitmap.LockBits(rect, ImageLockMode.ReadOnly, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        try
        {
            var bytes = new byte[data.Stride * bitmap.Height];
            Marshal.Copy(data.Scan0, bytes, 0, bytes.Length);
            var source = BitmapSource.Create(bitmap.Width, bitmap.Height, 96, 96, PixelFormats.Bgra32, null, bytes, data.Stride);
            source.Freeze();
            return source;
        }
        finally { bitmap.UnlockBits(data); }
    }

    /// <summary>A species' idle pose: in its own colour when the sheet chose one, otherwise as painted.</summary>
    public static BitmapSource? Preview(SpriteAtlas atlas)
    {
        var own = RGB.FromHex(atlas.Info.Colour);
        var frame = atlas.MakeFrames(own).Frame("idle", 0);
        return frame is null ? null : ToSource(frame);
    }

    public static Color ToMedia(RGB rgb) => Color.FromRgb(rgb.R, rgb.G, rgb.B);
}

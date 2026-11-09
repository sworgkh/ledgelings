using System.Drawing;
using System.Drawing.Drawing2D;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The dive's water on this monitor (SPEC §7.17): drawn, not a window, so clicks go through it to the apps
/// below as everywhere else on the glass. Behind the creatures the water and its life; over them the tint, the surface
/// and the bubbles.</summary>
public sealed partial class ScreenOverlay
{
    /// <summary>Whether any water was drawn on this monitor in the last frame.</summary>
    public bool HasWater { get; private set; }
    /// <summary>Last frame's pictures, let go of once the next frame paints its own.</summary>
    private readonly List<Bitmap> waterPictures = new();

    private void AddWater(List<(Rectangle, Action<Graphics>)> ops, IReadOnlyList<WaterSnapshot>? water, bool front)
    {
        if (!front)
        {
            HasWater = false;
            foreach (var old in waterPictures) old.Dispose();
            waterPictures.Clear();
        }
        if (water is null) return;
        foreach (var w in water)
        {
            var (_, _, frame) = WaterPainter.Layout(w);
            if (frame.MaxX <= Monitor.Frame.MinX || frame.MinX >= Monitor.Frame.MaxX || frame.MaxY <= Monitor.Frame.MinY || frame.MinY >= Monitor.Frame.MaxY) continue;
            var picture = front ? WaterPainter.Front(w) : WaterPainter.Back(w);
            if (picture is null) continue;
            HasWater = true;
            waterPictures.Add(picture);
            var topLeft = ToWindow(new Pt(frame.MinX, frame.MaxY));
            var bounds = new Rectangle((int)Math.Floor(topLeft.X), (int)Math.Floor(topLeft.Y), (int)Math.Ceiling(frame.Width) + 1, (int)Math.Ceiling(frame.Height) + 1);
            ops.Add((bounds, g =>
            {
                g.InterpolationMode = InterpolationMode.NearestNeighbor;
                g.PixelOffsetMode = PixelOffsetMode.Half;
                g.DrawImage(picture, new RectangleF(topLeft.X, topLeft.Y, (float)frame.Width, (float)frame.Height),
                            new RectangleF(0, 0, picture.Width, picture.Height), GraphicsUnit.Pixel);
            }));
        }
    }
}

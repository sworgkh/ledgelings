using System.Drawing;
using System.Drawing.Drawing2D;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The Stop button over everything, and its tag under it while hovered (<c>Colony.StopButton</c>).</summary>
public sealed partial class ScreenOverlay
{
    /// <summary>Its frame in global coordinates while it is on this monitor (tests, the --dive run).</summary>
    public Rect? StopButtonFrame { get; private set; }

    private void AddStopButton(List<(Rectangle, Action<Graphics>)> ops, StopButtonSnapshot? stop)
    {
        StopButtonFrame = stop?.Frame;
        if (stop is null) return;
        Add(stop.Image, stop.Frame);
        if (stop.Tag is Bitmap tag) Add(tag, stop.TagFrame);

        void Add(Bitmap image, Rect frame)
        {
            // Global y up to the window's y down: the frame's top is its MaxY.
            var place = new Rectangle((int)Math.Round(frame.MinX - Monitor.Left), (int)Math.Round(-frame.MaxY - Monitor.Top),
                                      (int)Math.Round(frame.Width), (int)Math.Round(frame.Height));
            ops.Add((Rectangle.Inflate(place, 2, 2), g =>
            {
                g.InterpolationMode = InterpolationMode.NearestNeighbor;
                g.PixelOffsetMode = PixelOffsetMode.Half;
                g.SmoothingMode = SmoothingMode.None;
                g.DrawImage(image, place, 0, 0, image.Width, image.Height, GraphicsUnit.Pixel, pixelEdges);
            }));
        }
    }
}

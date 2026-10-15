using System.Drawing;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>One of a game's props (<c>Colony.Play</c>), in GLOBAL coordinates: drawn about its middle.</summary>
/// <param name="Scale">Screen points per sprite pixel.</param>
/// <param name="InFront">Over the creatures (the ball), rather than behind them (the hoop, the rope).</param>
public sealed record PropSnapshot(Bitmap? Image, Pt Position, double Rotation, double Scale,
                                  bool Mirrored = false, float Opacity = 1, bool InFront = false);

/// <summary>The games' props: the rope's links and its hook, the parachute, the hoop and the ball, a drop of sweat.</summary>
public sealed partial class ScreenOverlay
{
    private void AddProps(List<(Rectangle, Action<Graphics>)> ops, IReadOnlyList<PropSnapshot>? props, Size cell, bool inFront)
    {
        if (props is null) return;
        foreach (var prop in props)
        {
            if (prop.InFront != inFront || prop.Image is not Bitmap image || prop.Scale <= 0 || prop.Opacity <= 0) continue;
            var reach = Math.Max(cell.Width, cell.Height) * prop.Scale;
            if (!Monitor.Frame.InsetBy(-reach, -reach).Contains(prop.Position)) continue;
            var centre = ToWindow(prop.Position);
            var radius = (int)Math.Ceiling(reach + 2);
            ops.Add((new Rectangle((int)centre.X - radius, (int)centre.Y - radius, 2 * radius, 2 * radius), g =>
            {
                g.TranslateTransform(centre.X, centre.Y);
                g.RotateTransform(Degrees(prop.Rotation));
                g.ScaleTransform(prop.Mirrored ? -(float)prop.Scale : (float)prop.Scale, (float)prop.Scale);
                DrawImageCentred(g, image, prop.Opacity);
            }));
        }
    }
}

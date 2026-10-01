using System.Drawing;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>A flower planted in the edge, in GLOBAL coordinates.</summary>
/// <param name="Floor">The foot of its stem, on the screen edge.</param>
/// <param name="Rotation">The edge's turn, as a creature standing there has it.</param>
/// <param name="Grown">0 as it goes in, 1 once it is fully up: it comes up out of the edge.</param>
public sealed record PlantedSnapshot(Bitmap? Image, Pt Floor, double Rotation, double Scale, double Grown, float Opacity);

/// <summary>The planted flowers: each stands on the foot of its stem, turned with its edge.</summary>
public sealed partial class ScreenOverlay
{
    private void AddGarden(List<(Rectangle, Action<Graphics>)> ops, IReadOnlyList<PlantedSnapshot>? garden, Size cell)
    {
        if (garden is null) return;
        foreach (var bed in garden)
        {
            if (bed.Image is null || bed.Opacity <= 0) continue;
            var reach = Math.Max(cell.Width, cell.Height) * bed.Scale;
            // A flower nowhere near this monitor costs it nothing.
            if (!Monitor.Frame.InsetBy(-reach, -reach).Contains(bed.Floor)) continue;
            var foot = ToWindow(bed.Floor);
            var w = (float)(cell.Width * bed.Scale);
            var h = (float)(cell.Height * bed.Scale);
            var radius = (int)Math.Ceiling(Math.Max(w, h) + 2);
            var image = bed.Image;
            ops.Add((new Rectangle((int)foot.X - radius, (int)foot.Y - radius, 2 * radius, 2 * radius), g =>
            {
                // Rotated with its edge, then squashed toward its foot while it grows.
                g.TranslateTransform(foot.X, foot.Y);
                g.RotateTransform(Degrees(bed.Rotation));
                g.ScaleTransform((float)bed.Scale, (float)(bed.Scale * Math.Max(bed.Grown, 0.001)));
                g.TranslateTransform(0, -cell.Height / 2f);      // centred image, standing on its bottom edge
                DrawImageCentred(g, image, bed.Opacity);
            }));
        }
    }
}

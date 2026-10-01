using System.Drawing;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The tea party's table, standing on its edge between the pair, in GLOBAL coordinates.</summary>
/// <param name="Floor">The middle of its feet, on the screen edge.</param>
/// <param name="Rotation">The edge's turn, as a creature standing there has it.</param>
/// <param name="Scale">Screen points per sprite pixel, already grown or shrunk: 0 while it comes up, full once it is out.</param>
public sealed record TeaTableSnapshot(Bitmap? Image, Pt Floor, double Rotation, double Scale);

/// <summary>The tea table: behind the pair, who sit tucked in at its ends; it grows up out of the edge about its feet.</summary>
public sealed partial class ScreenOverlay
{
    private void AddTeaTable(List<(Rectangle, Action<Graphics>)> ops, TeaTableSnapshot? tea, Size cell)
    {
        if (tea is null || tea.Image is null || tea.Scale <= 0) return;
        var reach = Math.Max(cell.Width, cell.Height) * tea.Scale;
        if (!Monitor.Frame.InsetBy(-reach, -reach).Contains(tea.Floor)) return;
        var foot = ToWindow(tea.Floor);
        var radius = (int)Math.Ceiling(reach + 2);
        var image = tea.Image;
        ops.Add((new Rectangle((int)foot.X - radius, (int)foot.Y - radius, 2 * radius, 2 * radius), g =>
        {
            g.TranslateTransform(foot.X, foot.Y);
            g.RotateTransform(Degrees(tea.Rotation));
            g.ScaleTransform((float)tea.Scale, (float)tea.Scale);
            g.TranslateTransform(0, -cell.Height / 2f);      // centred image, standing on its bottom edge
            DrawImageCentred(g, image);
        }));
    }
}

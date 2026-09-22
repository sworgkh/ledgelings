using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;

namespace Ledgelings;

/// <summary>The speech bubble: monospaced text on a dark rounded plate, floated off the
/// creature's head and kept inside its monitor. Not rotated.</summary>
public sealed partial class ScreenOverlay
{
    private static readonly StringFormat BubbleFormat = new(StringFormat.GenericTypographic)
    {
        FormatFlags = StringFormatFlags.LineLimit, Trimming = StringTrimming.Word,
    };

    private void AddBubble(List<(Rectangle, Action<Graphics>)> ops, Dictionary<int, (RectangleF, string, SizeF)> into,
                           CreatureSnapshot snap, int index, double bodyHalf)
    {
        if (string.IsNullOrEmpty(snap.Bubble)) return;
        // One face per DrawString, so the marks come out rather than being styled.
        var text = Core.Banter.Plain(snap.Bubble);
        var pad = 8 * ui;
        SizeF textSize;
        if (bubbles.TryGetValue(index, out var known) && known.Text == text) textSize = known.TextSize;
        else
        {
            var measured = window.Graphics.MeasureString(text, bubbleFont, (int)(250 * ui), BubbleFormat);
            textSize = new SizeF((float)Math.Ceiling(measured.Width) + 2, (float)Math.Ceiling(measured.Height) + 2);
        }
        var size = new SizeF(textSize.Width + pad * 2, textSize.Height + pad * 2);
        // Float it off the creature's "head", then keep it on this screen.
        var centre = new Core.Pt(
            snap.Position.X + snap.Inward.Dx * (bodyHalf + 10 * ui + size.Width / 2),
            snap.Position.Y + snap.Inward.Dy * (bodyHalf + 10 * ui + size.Height / 2));
        var room = Monitor.Frame.InsetBy(size.Width / 2 + 6 * ui, size.Height / 2 + 6 * ui);
        centre = new Core.Pt(Math.Min(Math.Max(centre.X, room.MinX), room.MaxX), Math.Min(Math.Max(centre.Y, room.MinY), room.MaxY));
        var at = ToWindow(centre);
        var plate = new RectangleF((float)Math.Round(at.X - size.Width / 2), (float)Math.Round(at.Y - size.Height / 2), size.Width, size.Height);
        into[index] = (plate, text, textSize);
        ops.Add((Rectangle.Round(RectangleF.Inflate(plate, 3, 3)), g =>
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            using var path = RoundedRectangle(plate, 6 * ui);
            using var fill = new SolidBrush(Color.FromArgb(245, 43, 36, 64));
            using var border = new Pen(Color.FromArgb(89, 255, 255, 255), 1 * ui);
            g.FillPath(fill, path);
            g.DrawPath(border, path);
            g.DrawString(text, bubbleFont, Brushes.White,
                         new RectangleF(plate.X + pad, plate.Y + pad, textSize.Width, textSize.Height), BubbleFormat);
        }));
    }

    private static GraphicsPath RoundedRectangle(RectangleF r, float radius)
    {
        var d = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}

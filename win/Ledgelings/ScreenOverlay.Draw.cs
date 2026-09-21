using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

namespace Ledgelings;

/// <summary>How the sprites are drawn. Pixel art: nearest neighbour, no smoothing.</summary>
public sealed partial class ScreenOverlay
{
    private static readonly ImageAttributes pixelEdges = MakePixelEdges();

    private static ImageAttributes MakePixelEdges()
    {
        var attributes = new ImageAttributes();
        attributes.SetWrapMode(WrapMode.TileFlipXY);      // no smeared edge from sampling outside the frame
        return attributes;
    }

    private static float Degrees(double radiansUp) => (float)(-radiansUp * 180 / Math.PI);      // y is flipped, so turns are mirrored

    /// <summary>The image centred on the origin of the current transform, at its own pixel size.</summary>
    private static void DrawImageCentred(Graphics g, Bitmap image, float opacity = 1)
    {
        g.InterpolationMode = InterpolationMode.NearestNeighbor;
        g.PixelOffsetMode = PixelOffsetMode.Half;
        g.SmoothingMode = SmoothingMode.None;
        var rect = new Rectangle(-image.Width / 2, -image.Height / 2, image.Width, image.Height);
        if (opacity >= 1)
        {
            g.DrawImage(image, rect, 0, 0, image.Width, image.Height, GraphicsUnit.Pixel, pixelEdges);
            return;
        }
        using var faded = new ImageAttributes();
        faded.SetWrapMode(WrapMode.TileFlipXY);
        faded.SetColorMatrix(new ColorMatrix { Matrix33 = Math.Max(0, opacity) }, ColorMatrixFlag.Default, ColorAdjustType.Bitmap);
        g.DrawImage(image, rect, 0, 0, image.Width, image.Height, GraphicsUnit.Pixel, faded);
    }

    private void AddCreature(List<(Rectangle, Action<Graphics>)> ops, CreatureSnapshot snap, Bitmap? z, Size cell, double hatHeight)
    {
        var centre = ToWindow(snap.Position);
        var scale = (float)snap.Scale;
        var bodyHeight = cell.Height * scale;
        var radius = (int)Math.Ceiling(bodyHeight * 1.6 + 4);
        var bounds = new Rectangle((int)centre.X - radius, (int)centre.Y - radius, 2 * radius, 2 * radius);
        ops.Add((bounds, g =>
        {
            // The body transform carries position and the turn onto the edge; the
            // sprite inside it carries only the mirror, so the Zs never flip.
            g.TranslateTransform(centre.X, centre.Y);
            g.RotateTransform(Degrees(snap.Rotation));
            g.ScaleTransform((float)snap.Shrink, (float)snap.Shrink);
            using var body = g.Transform;
            g.ScaleTransform(snap.IsMirrored ? -scale : scale, scale);
            DrawImageCentred(g, snap.Image!);
            g.Transform = body;

            // The flower stands on the head: inside the body, so it turns with the
            // creature onto walls and the ceiling, but never mirrors.
            if (snap.Hat is Bitmap hat)
            {
                g.TranslateTransform(0, -(float)(bodyHeight / 2 + hatHeight / 2 - scale));
                g.ScaleTransform(scale, scale);
                DrawImageCentred(g, hat);
                g.Transform = body;
            }

            if (snap.AsleepFor is double asleep && z is not null)
            {
                for (int k = 0; k < ZCount; k++)
                {
                    var clock = asleep / ZCycle - (double)k / ZCount;
                    if (clock < 0) continue;      // not launched yet
                    var p = clock - Math.Floor(clock);
                    var grow = (float)(0.7 + 0.8 * p);
                    var x = bodyHeight * (0.22 + 0.10 * Math.Sin(p * 2 * Math.PI) + 0.18 * p);
                    var y = bodyHeight * (0.30 + 0.75 * p);
                    var opacity = (float)(Math.Min(1, p * 5) * Math.Min(1, (1 - p) * 2.5));
                    g.TranslateTransform((float)x, -(float)y);
                    g.RotateTransform(-Degrees(snap.Rotation));      // undo the body's turn so the letter stays upright
                    g.ScaleTransform(grow * scale, grow * scale);
                    DrawImageCentred(g, z, opacity);
                    g.Transform = body;
                }
            }
        }));
    }

    private void AddHouse(List<(Rectangle, Action<Graphics>)> ops, HouseSnapshot? house, Size cell)
    {
        if (house is null || house.Image is null || house.Scale <= 0) return;
        var corner = ToWindow(house.Corner);
        var w = (float)(cell.Width * house.Scale);
        var h = (float)(cell.Height * house.Scale);
        var bounds = Rectangle.Round(new RectangleF(corner.X - w - 2, corner.Y - h - 2, w + 4, h + 4));
        ops.Add((bounds, g =>
        {
            g.TranslateTransform(corner.X, corner.Y);
            g.ScaleTransform((float)house.Scale, (float)house.Scale);
            g.InterpolationMode = InterpolationMode.NearestNeighbor;
            g.PixelOffsetMode = PixelOffsetMode.Half;
            g.DrawImage(house.Image, new Rectangle(-cell.Width, -cell.Height, cell.Width, cell.Height),
                        0, 0, cell.Width, cell.Height, GraphicsUnit.Pixel, pixelEdges);
        }));
    }

    private void AddFlight(List<(Rectangle, Action<Graphics>)> ops, FlowerFlight? flight, Size cell)
    {
        if (flight is null || flight.Image is null) return;
        var centre = ToWindow(flight.Position);
        var radius = (int)Math.Ceiling(Math.Max(cell.Width, cell.Height) * flight.Scale * 0.8 + 2);
        ops.Add((new Rectangle((int)centre.X - radius, (int)centre.Y - radius, 2 * radius, 2 * radius), g =>
        {
            g.TranslateTransform(centre.X, centre.Y);
            g.RotateTransform(Degrees(flight.Rotation));
            g.ScaleTransform((float)flight.Scale, (float)flight.Scale);
            DrawImageCentred(g, flight.Image);
        }));
    }

    private void AddSparks(List<(Rectangle, Action<Graphics>)> ops, IReadOnlyList<SparkSnapshot> sparks)
    {
        foreach (var spark in sparks)
        {
            var centre = ToWindow(spark.Position);
            var size = (float)spark.Size;
            var rect = new RectangleF(centre.X - size / 2, centre.Y - size / 2, size, size);
            var colour = Color.FromArgb((int)Math.Round(255 * Math.Clamp(spark.Opacity, 0, 1)), spark.Color);
            ops.Add((Rectangle.Round(RectangleF.Inflate(rect, 2, 2)), g =>
            {
                using var brush = new SolidBrush(colour);
                g.FillRectangle(brush, rect);
            }));
        }
    }
}

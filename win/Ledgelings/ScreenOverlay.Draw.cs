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
        // An effect reaches past the body: the whole of its frame, wherever it stands in the cell.
        if (snap.Effect is { } fx) radius = Math.Max(radius, (int)Math.Ceiling(EffectReach(fx, cell) * scale + 4));
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
            // The effect's back picture under the sprite, its front over it, both under the hat; the mirror flips them too.
            DrawEffect(g, snap.Effect?.Back, snap.Effect, cell);
            if (snap.Effect?.HidesBody != true) DrawImageCentred(g, snap.Image!);
            DrawEffect(g, snap.Effect?.Front, snap.Effect, cell);
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

            // The open letter is held out in front, on the side it faces.
            if (snap.Letter is Bitmap letter)
            {
                g.TranslateTransform((snap.IsMirrored ? -1 : 1) * cell.Width * scale * 0.42f, bodyHeight * 0.08f);
                g.ScaleTransform(scale, scale);
                DrawImageCentred(g, letter);
                g.Transform = body;
            }

            if (snap.AsleepFor is double asleep && z is not null && snap.Effect?.HidesZs != true)
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

    /// <summary>One of an effect's pictures in the creature's sprite pixels, centred on the body as the sprite is:
    /// the frame's top-left at its origin in the cell, the cell's rows running down from its top.</summary>
    private static void DrawEffect(Graphics g, Bitmap? picture, CreatureEffect? fx, Size cell)
    {
        if (picture is null || fx is null) return;
        g.InterpolationMode = InterpolationMode.NearestNeighbor;
        g.PixelOffsetMode = PixelOffsetMode.Half;
        g.SmoothingMode = SmoothingMode.None;
        var rect = new Rectangle(fx.Origin.X - cell.Width / 2, fx.Origin.Y - cell.Height / 2, fx.Size.Width, fx.Size.Height);
        g.DrawImage(picture, rect, 0, 0, picture.Width, picture.Height, GraphicsUnit.Pixel, pixelEdges);
    }

    /// <summary>How far an effect's frame reaches from the body's centre, in sprite pixels.</summary>
    private static double EffectReach(CreatureEffect fx, Size cell)
    {
        double left = fx.Origin.X - cell.Width / 2.0, top = fx.Origin.Y - cell.Height / 2.0;
        return new[] { Math.Abs(left), Math.Abs(left + fx.Size.Width), Math.Abs(top), Math.Abs(top + fx.Size.Height) }.Max() * Math.Sqrt(2);
    }

    /// <summary>Effects standing on their own (a poof), each where its creature's centre was, as the creature would be drawn.</summary>
    private void AddLooseEffects(List<(Rectangle, Action<Graphics>)> ops, IReadOnlyList<LooseEffectSnapshot>? loose, Size cell)
    {
        if (loose is null) return;
        foreach (var e in loose)
        {
            var centre = ToWindow(e.Place);
            var fx = new CreatureEffect(e.Back, e.Front, e.Origin, e.Size, true, false);
            var radius = (int)Math.Ceiling(EffectReach(fx, cell) * e.Scale + 4);
            ops.Add((new Rectangle((int)centre.X - radius, (int)centre.Y - radius, 2 * radius, 2 * radius), g =>
            {
                g.TranslateTransform(centre.X, centre.Y);
                g.RotateTransform(Degrees(e.Rotation));
                g.ScaleTransform(e.Mirrored ? -(float)e.Scale : (float)e.Scale, (float)e.Scale);
                DrawEffect(g, e.Back, fx, cell);
                DrawEffect(g, e.Front, fx, cell);
            }));
        }
    }

    /// <summary>The ambient particles along the bottom edge, a tile at a time, each standing on its monitor's bottom.</summary>
    private void AddAmbient(List<(Rectangle, Action<Graphics>)> ops, IReadOnlyList<AmbientTile>? tiles)
    {
        if (tiles is null) return;
        foreach (var t in tiles)
        {
            if (t.Image is not { } image) continue;
            var w = (float)(image.Width * t.Scale);
            var h = (float)(image.Height * t.Scale);
            var corner = ToWindow(t.BottomLeft);      // the bottom-left corner, y down from here
            var rect = new RectangleF(corner.X, corner.Y - h, w, h);
            if (!rect.IntersectsWith(new RectangleF(0, 0, Monitor.Width, Monitor.Height))) continue;
            ops.Add((Rectangle.Round(RectangleF.Inflate(rect, 1, 1)), g =>
            {
                g.InterpolationMode = InterpolationMode.NearestNeighbor;
                g.PixelOffsetMode = PixelOffsetMode.Half;
                g.SmoothingMode = SmoothingMode.None;
                g.DrawImage(image, rect, new RectangleF(0, 0, image.Width, image.Height), GraphicsUnit.Pixel);
            }));
        }
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

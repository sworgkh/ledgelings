using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The paper plane and its dotted trail, in GLOBAL coordinates.</summary>
/// <param name="Heading">Where the nose points, radians. The sprite points right.</param>
/// <param name="Flipped">Drawn upside down: past a quarter roll (<see cref="PaperPlane.ViewAt"/>), which
/// is how a plane flying left keeps its wing on top.</param>
/// <param name="Opacity">0 once caught (only the trail is left), fading after a miss.</param>
public sealed record PlaneSnapshot(Bitmap? Image, Pt Position, double Heading, bool Flipped, double Scale, float Opacity,
                                   IReadOnlyList<(Pt Position, float Opacity)> Trail, double PuffSize);

/// <summary>A reminder on its way: its plane (or nothing, once it has opened), and the letter.</summary>
public sealed record ReminderSnapshot(PlaneSnapshot? Plane, LetterSnapshot? Letter);

/// <summary>The reminder's letter, open in the middle of the screen.</summary>
/// <param name="Id">Which delivery this is: a new one lays the letter out afresh.</param>
/// <param name="Grow">1 = full size; less while it spreads out or folds away.</param>
/// <param name="Text">The reminder itself, in the user's words.</param>
/// <param name="Note">The thrower's note, in its own voice.</param>
/// <param name="Stamp">The thrower's face, beside its signature.</param>
public sealed record LetterSnapshot(int Id, Pt Centre, double Grow, float Opacity, string Title, string Text, string Note,
                                    string Signature, Bitmap? Stamp, string Hint);

/// <summary>The paper planes (the creatures' and a reminder's: both can be in the air at
/// once), their trails as plain square puffs, and the reminder's letter.</summary>
public sealed partial class ScreenOverlay
{
    /// <summary>Screen points per pixel of the letter's paper, before the monitor's dpi.</summary>
    private const float PaperPixel = 3;
    private const float LetterPad = 30;
    private const float LetterTextWidth = 380;
    public static readonly Color Ink = Color.FromArgb(40, 34, 58);
    public static readonly Color SoftInk = Color.FromArgb(92, 86, 120);
    public static readonly Color FaintInk = Color.FromArgb(150, 146, 170);

    /// <summary>The colour of each pixel of <see cref="Reminders.Paper"/>.</summary>
    public static Color PaperColour(Reminders.Ink ink) => ink switch
    {
        Reminders.Ink.Rim => Color.FromArgb(40, 34, 58),
        Reminders.Ink.Paper => Color.FromArgb(244, 241, 230),
        Reminders.Ink.Light => Color.FromArgb(255, 255, 255),
        Reminders.Ink.Shade => Color.FromArgb(196, 192, 206),
        Reminders.Ink.DeepShade => Color.FromArgb(150, 146, 170),
        _ => Color.FromArgb(228, 224, 212),
    };

    /// <summary><see cref="Reminders.Paper"/> as an image, one image pixel per paper pixel.</summary>
    public static Bitmap PaperImage(int width, int height)
    {
        var rows = Reminders.Paper(width, height);
        int h = rows.Length, w = h == 0 ? 0 : rows[0].Length;
        var image = new Bitmap(Math.Max(1, w), Math.Max(1, h), PixelFormat.Format32bppArgb);
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                image.SetPixel(x, y, rows[y][x] is Reminders.Ink ink ? PaperColour(ink) : Color.Transparent);
        return image;
    }

    /// <summary>The letter laid out once per delivery, then only moved, grown and faded.</summary>
    private (string Key, Bitmap Image)? letter;
    /// <summary>The open letter's frame in global points, while this screen shows it.</summary>
    public Rect? LetterFrame { get; private set; }

    private void AddMail(List<(Rectangle, Action<Graphics>)> ops, PlaneSnapshot? plane, Size planeCell, ReminderSnapshot? reminder)
    {
        AddPlane(ops, plane, planeCell);
        AddPlane(ops, reminder?.Plane, planeCell);
        AddLetter(ops, reminder?.Letter);
    }

    /// <summary>One plane over everything, and its trail as plain square white puffs behind it.</summary>
    private void AddPlane(List<(Rectangle, Action<Graphics>)> ops, PlaneSnapshot? plane, Size cell)
    {
        if (plane is null) return;
        var size = (float)plane.PuffSize;
        foreach (var (position, opacity) in plane.Trail)
        {
            if (!Monitor.Frame.InsetBy(-size, -size).Contains(position)) continue;
            var at = ToWindow(position);
            var rect = new RectangleF((float)Math.Round(at.X) - size / 2, (float)Math.Round(at.Y) - size / 2, size, size);
            var colour = Color.FromArgb((int)Math.Round(255 * Math.Clamp(opacity, 0, 1)), Color.White);
            ops.Add((Rectangle.Round(RectangleF.Inflate(rect, 2, 2)), g =>
            {
                using var brush = new SolidBrush(colour);
                g.FillRectangle(brush, rect);
            }));
        }
        if (plane.Image is not Bitmap image || plane.Opacity <= 0) return;
        var reach = Math.Max(cell.Width, cell.Height) * plane.Scale;
        if (!Monitor.Frame.InsetBy(-reach, -reach).Contains(plane.Position)) return;
        var centre = ToWindow(plane.Position);
        var radius = (int)Math.Ceiling(reach * 0.75 + 4);
        ops.Add((new Rectangle((int)centre.X - radius, (int)centre.Y - radius, 2 * radius, 2 * radius), g =>
        {
            g.TranslateTransform(centre.X, centre.Y);
            g.RotateTransform(Degrees(plane.Heading));
            g.ScaleTransform((float)plane.Scale, (float)(plane.Flipped ? -plane.Scale : plane.Scale));
            DrawImageCentred(g, image, plane.Opacity);
        }));
    }

    /// <summary>Only the screen the letter opened on draws it.</summary>
    private void AddLetter(List<(Rectangle, Action<Graphics>)> ops, LetterSnapshot? snap)
    {
        if (snap is null || !Monitor.Frame.Contains(snap.Centre))
        {
            letter?.Image.Dispose();
            letter = null;
            LetterFrame = null;
            return;
        }
        var key = $"{snap.Id}|{snap.Title}|{snap.Note}";
        if (letter?.Key != key)
        {
            letter?.Image.Dispose();
            letter = (key, MakeLetter(snap));
        }
        var made = letter!.Value.Image;
        LetterFrame = new Rect(snap.Centre.X - made.Width / 2.0, snap.Centre.Y - made.Height / 2.0, made.Width, made.Height);
        var centre = ToWindow(snap.Centre);
        var grow = (float)snap.Grow;
        float w = made.Width * grow, h = made.Height * grow;
        var place = new RectangleF((float)Math.Round(centre.X - w / 2), (float)Math.Round(centre.Y - h / 2), w, h);
        ops.Add((Rectangle.Round(RectangleF.Inflate(place, 2, 2)), g =>
        {
            g.InterpolationMode = Math.Abs(grow - 1) < 0.001 ? InterpolationMode.NearestNeighbor : InterpolationMode.HighQualityBilinear;
            g.PixelOffsetMode = PixelOffsetMode.Half;
            using var faded = new ImageAttributes();
            faded.SetColorMatrix(new ColorMatrix { Matrix33 = Math.Clamp(snap.Opacity, 0, 1) }, ColorMatrixFlag.Default, ColorAdjustType.Bitmap);
            g.DrawImage(made, Rectangle.Round(place), 0, 0, made.Width, made.Height, GraphicsUnit.Pixel, faded);
        }));
    }

    private static readonly StringFormat LetterFormat = new(StringFormat.GenericTypographic) { Trimming = StringTrimming.Word };

    /// <summary>The paper, in blocky's rules, sized to the words; the reminder big, the note
    /// under it, the signature and the thrower's face at the bottom.</summary>
    private Bitmap MakeLetter(LetterSnapshot snap)
    {
        float px = (float)Math.Max(1, Math.Round(PaperPixel * ui)), pad = LetterPad * ui, wide = LetterTextWidth * ui;
        using var titleFont = new Font("Consolas", 11 * ui, FontStyle.Bold, GraphicsUnit.Pixel);
        using var textFont = new Font("Consolas", 24 * ui, FontStyle.Bold, GraphicsUnit.Pixel);
        using var noteFont = new Font("Consolas", 13 * ui, FontStyle.Bold, GraphicsUnit.Pixel);
        using var signatureFont = new Font("Consolas", 13 * ui, FontStyle.Bold, GraphicsUnit.Pixel);
        using var hintFont = new Font("Consolas", 10 * ui, FontStyle.Bold, GraphicsUnit.Pixel);
        SizeF Measure(string text, Font font)
        {
            if (text.Length == 0) return new SizeF(0, font.Height);
            var m = window.Graphics.MeasureString(text, font, (int)wide, LetterFormat);
            return new SizeF((float)Math.Ceiling(m.Width) + 2, (float)Math.Ceiling(m.Height) + 2);
        }
        SizeF title = Measure(snap.Title, titleFont), text = Measure(snap.Text, textFont), note = Measure(snap.Note, noteFont),
              signature = Measure(snap.Signature, signatureFont), hint = Measure(snap.Hint, hintFont);
        var stampSize = snap.Stamp is null ? SizeF.Empty : new SizeF(snap.Stamp.Width * 1.5f * ui, snap.Stamp.Height * 1.5f * ui);

        var inner = new[] { title.Width, text.Width, note.Width, signature.Width + stampSize.Width + 8 * ui, 260 * ui }.Max();
        var width = (float)Math.Ceiling((inner + pad * 2) / px) * px;
        var footer = Math.Max(stampSize.Height, signature.Height);
        var body = title.Height + 10 * ui + text.Height + 14 * ui + note.Height + 14 * ui + footer + 4 * ui + hint.Height;
        var height = (float)Math.Ceiling((body + pad * 2) / px) * px;

        var image = new Bitmap((int)width, (int)height, PixelFormat.Format32bppPArgb);
        using var g = Graphics.FromImage(image);
        using (var paper = PaperImage((int)(width / px), (int)(height / px)))
        {
            g.InterpolationMode = InterpolationMode.NearestNeighbor;
            g.PixelOffsetMode = PixelOffsetMode.Half;
            g.DrawImage(paper, new Rectangle(0, 0, (int)width, (int)height), 0, 0, paper.Width, paper.Height, GraphicsUnit.Pixel);
        }
        g.PixelOffsetMode = PixelOffsetMode.Default;
        g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        // Top down.
        var y = pad;
        void Place(string words, Font font, Color colour, SizeF size, float gap)
        {
            using var brush = new SolidBrush(colour);
            g.DrawString(words, font, brush, new RectangleF(pad, y, wide, size.Height), LetterFormat);
            y += size.Height + gap;
        }
        Place(snap.Title, titleFont, FaintInk, title, 10 * ui);
        Place(snap.Text, textFont, Ink, text, 14 * ui);
        Place(snap.Note, noteFont, SoftInk, note, 14 * ui);
        var footerTop = y;
        if (snap.Stamp is Bitmap stamp)
        {
            g.InterpolationMode = InterpolationMode.NearestNeighbor;
            g.PixelOffsetMode = PixelOffsetMode.Half;
            g.DrawImage(stamp, new RectangleF(width - pad - stampSize.Width + 6 * ui, footerTop, stampSize.Width, stampSize.Height));
            g.PixelOffsetMode = PixelOffsetMode.Default;
        }
        var signatureRight = width - pad - (stampSize.Width > 0 ? stampSize.Width - 2 * ui : 0);
        using (var ink = new SolidBrush(Ink))
            g.DrawString(snap.Signature, signatureFont, ink,
                new RectangleF(signatureRight - signature.Width, footerTop + footer / 2 - signature.Height / 2, signature.Width, signature.Height), LetterFormat);
        y = footerTop + footer + 4 * ui;
        Place(snap.Hint, hintFont, FaintInk, hint, 0);
        return image;
    }
}

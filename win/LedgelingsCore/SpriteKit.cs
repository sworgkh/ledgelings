namespace Ledgelings.Core;

/// <summary>
/// The sprite kit on Settings › Sprites: a small form saying what the creature
/// is, a prompt for an IMAGE model built from it, the two pictures attached to
/// that prompt, and the reader that turns whatever picture the model sends
/// back into a sheet. The Mac's <c>SpriteKit</c>, and the pictures are the same bytes.
///
/// The pictures (<see cref="PosesImage"/>, <see cref="TemplateImage"/>) are 1728×288: a header
/// strip, one row of nine 32×32 cells drawn 6× bigger, and a strip of labels. Image
/// models never answer at exactly that size, so <see cref="Read"/> does not trust the
/// layout: it finds the creatures in the picture, orders them, and brings each down
/// to a 32×32 cell in the sheet's inks.
/// </summary>
public static partial class SpriteKit
{
    // MARK: The form

    /// <summary>What the person filled in. Empty means "let the model choose".</summary>
    public sealed record Form
    {
        public const int CastSize = 3;

        /// <summary>What the creature is: "a fat green frog with big eyes".</summary>
        public string Kind { get; init; } = "";
        public string Name { get; init; } = "";
        /// <summary>Its body colour, <c>#rrggbb</c>; empty lets the model choose.</summary>
        public string Colour { get; init; } = "";
        private readonly IReadOnlyList<Character> cast = Three(Array.Empty<Character>());
        /// <summary>Always three; a character with no name is the model's to choose.</summary>
        public IReadOnlyList<Character> Cast { get => cast; init => cast = Three(value ?? Array.Empty<Character>()); }

        /// <summary><paramref name="cast"/> cut or padded to three.</summary>
        public static IReadOnlyList<Character> Three(IEnumerable<Character> cast) =>
            cast.Concat(Enumerable.Repeat(new Character("", ""), CastSize)).Take(CastSize).ToList();

        public SpriteText.Tint? Tint => SpriteText.Tint.FromHex(Colour.Trim());
        public string TrimmedKind => Kind.Trim();
        /// <summary>The characters that have a name.</summary>
        public IReadOnlyList<Character> NamedCast =>
            Cast.Select(c => new Character(c.Name.Trim(), c.Persona.Trim())).Where(c => c.Name.Length > 0).ToList();

        public bool Equals(Form? other) =>
            other is not null && Kind == other.Kind && Name == other.Name && Colour == other.Colour && Cast.SequenceEqual(other.Cast);
        public override int GetHashCode() => HashCode.Combine(Kind, Name, Colour, Cast.Count);
    }

    /// <summary>A name the sprites folder takes: lowercase Latin letters, digits and dashes.
    /// Null when nothing usable is left.</summary>
    public static string? SpeciesName(string typed)
    {
        var sb = new System.Text.StringBuilder();
        foreach (var c in typed.ToLowerInvariant())
        {
            if (c is >= 'a' and <= 'z' or >= '0' and <= '9') sb.Append(c);
            else if (sb.Length > 0 && sb[^1] != '-') sb.Append('-');
        }
        var name = sb.ToString().TrimEnd('-');
        return name.Length == 0 ? null : name;
    }

    // MARK: The pictures

    /// <summary>Image pixels per sprite pixel in the pictures.</summary>
    public const int Scale = 6;
    public static int CellSize => SpriteText.Cell * Scale;
    /// <summary>Height of the strip above the cells (the picture's number and title) and of the labels below.</summary>
    public const int Strip = 48;
    public static int Width => SpriteText.Poses.Count * CellSize;
    public static int Height => Strip + CellSize + Strip;

    private static readonly SpriteText.Tint Key = new(255, 0, 255);
    private static readonly SpriteText.Tint GridLine = new(200, 0, 200);
    private static readonly SpriteText.Tint BoxLine = new(255, 120, 255);
    private static readonly SpriteText.Tint InkColour = new(0, 0, 0);

    /// <summary>What the pictures say at the top. English in every language: the font
    /// has only Latin capitals, and the prompt names the pictures by number.</summary>
    public const string PosesTitle = "1 - POSES: COPY THIS STYLE AND ORDER";
    public const string TemplateTitle = "2 - TEMPLATE: PAINT YOUR CREATURE HERE";

    /// <summary>Picture 2: the empty sheet to paint on. Magenta, a line between cells,
    /// a pink frame round each body box (its bottom edge is the floor), the poses' names below.</summary>
    public static SpriteText.Image TemplateImage() => Canvas(TemplateTitle);

    /// <summary>Picture 1: <paramref name="sheet"/> (the built-in creature's 288×96 sheet; its top
    /// row, eyes open) drawn on the template, every sprite pixel a 6×6 square.</summary>
    public static SpriteText.Image PosesImage(SpriteText.Image sheet)
    {
        var image = Canvas(PosesTitle);
        var cell = SpriteText.Cell;
        for (var column = 0; column < Math.Min(SpriteText.Poses.Count, sheet.Width / cell); column++)
            for (var y = 0; y < cell; y++)
                for (var x = 0; x < cell; x++)
                {
                    var i = (y * sheet.Width + column * cell + x) * 4;
                    if (sheet.Rgba[i + 3] < 128) continue;
                    var tint = new SpriteText.Tint(sheet.Rgba[i], sheet.Rgba[i + 1], sheet.Rgba[i + 2]);
                    Fill(image, column * CellSize + x * Scale, Strip + y * Scale, Scale, Scale, tint);
                }
        return image;
    }

    private static SpriteText.Image Canvas(string title)
    {
        var image = new SpriteText.Image(Width, Height, new byte[Width * Height * 4]);
        Fill(image, 0, 0, Width, Height, Key);
        var box = SpriteText.Box;
        const int line = 2;
        for (var column = 0; column < SpriteText.Poses.Count; column++)
        {
            var left = column * CellSize;
            // Between cells and round the row.
            Fill(image, left, Strip, line, CellSize, GridLine);
            Fill(image, left + CellSize - line, Strip, line, CellSize, GridLine);
            Fill(image, left, Strip, CellSize, line, GridLine);
            Fill(image, left, Strip + CellSize - line, CellSize, line, GridLine);
            // The body box, just outside it so the creature's own pixels stay clear.
            int bx = left + box.X * Scale, by = Strip + box.Y * Scale, bw = box.W * Scale, bh = box.H * Scale;
            Fill(image, bx - line, by - line, bw + 2 * line, line, BoxLine);
            Fill(image, bx - line, by + bh, bw + 2 * line, line, BoxLine);
            Fill(image, bx - line, by, line, bh, BoxLine);
            Fill(image, bx + bw, by, line, bh, BoxLine);
            // Its pose's name, centred under it.
            var label = SpriteText.Poses[column].ToUpperInvariant();
            const int size = 4;
            Draw(label, left + (CellSize - TextWidth(label) * size) / 2, Strip + CellSize + (Strip - 7 * size) / 2, size, InkColour, image);
        }
        Draw(title, 24, (Strip - 7 * 4) / 2, 4, InkColour, image);
        return image;
    }

    internal static void Fill(SpriteText.Image image, int x, int y, int w, int h, SpriteText.Tint t)
    {
        for (var yy = Math.Max(0, y); yy < Math.Min(image.Height, y + h); yy++)
            for (var xx = Math.Max(0, x); xx < Math.Min(image.Width, x + w); xx++)
            {
                var i = (yy * image.Width + xx) * 4;
                image.Rgba[i] = t.R; image.Rgba[i + 1] = t.G; image.Rgba[i + 2] = t.B; image.Rgba[i + 3] = 255;
            }
    }
}

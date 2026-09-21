using System.Globalization;

namespace Ledgelings.Core;

/// <summary>
/// A creature written as letters: nine 32×32 grids, one per pose, which is
/// what a chat model can produce when asked. This turns such text into the
/// same sheet layout the built-in creature uses (poses in columns, eye
/// variants in rows), with the real palette, so recolouring and blinking work
/// on an imported creature exactly as on the built-in one.
///
/// Letters: <c>.</c> nothing, <c>o</c> outline, <c>b</c> body, <c>l</c> light, <c>s</c> shade,
/// <c>k</c> eye (black; it blinks), <c>x</c> black that never blinks.
/// </summary>
public static partial class SpriteText
{
    public const int Cell = 32;
    /// <summary>x, y, width, height of the square the body must stay inside.</summary>
    public static readonly (int X, int Y, int W, int H) Box = (5, 5, 22, 22);
    /// <summary>The row just below the creature: every pose must have ink on the row above it.</summary>
    public static int Floor => Box.Y + Box.H;
    public static readonly IReadOnlyList<string> Poses = new[] { "idle", "walk-0", "walk-1", "walk-2", "walk-3", "jump", "land", "sleep-0", "sleep-1" };
    public static readonly IReadOnlyList<string> Variants = new[] { "open", "half", "closed" };
    public static readonly IReadOnlyDictionary<string, (IReadOnlyList<string> Frames, double Fps, bool Loop)> Animations =
        new Dictionary<string, (IReadOnlyList<string>, double, bool)>
        {
            ["idle"] = (new[] { "idle" }, 1, true),
            ["walk"] = (new[] { "walk-0", "walk-1", "walk-2", "walk-3" }, 8, true),
            ["jump"] = (new[] { "jump" }, 1, true),
            ["land"] = (new[] { "land" }, 1, true),
            ["sleep"] = (new[] { "sleep-0", "sleep-1" }, 0.8, true),
        };
    public const string DescribePlaceholder = "<describe your creature here>";

    public enum Ink { Clear, Outline, Body, Light, Shade, Eye, Black }

    public static char Letter(this Ink ink) => ink switch
    {
        Ink.Clear => '.', Ink.Outline => 'o', Ink.Body => 'b', Ink.Light => 'l', Ink.Shade => 's', Ink.Eye => 'k', _ => 'x',
    };

    public static Ink? InkFor(char letter) => letter switch
    {
        '.' => Ink.Clear, 'o' => Ink.Outline, 'b' => Ink.Body, 'l' => Ink.Light, 's' => Ink.Shade, 'k' => Ink.Eye, 'x' => Ink.Black,
        _ => null,
    };

    public readonly record struct Tint(byte R, byte G, byte B)
    {
        public static Tint? FromHex(string hex)
        {
            var digits = hex.StartsWith('#') ? hex[1..] : hex;
            if (digits.Length != 6 || !uint.TryParse(digits, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var value)) return null;
            return new Tint((byte)(value >> 16 & 0xff), (byte)(value >> 8 & 0xff), (byte)(value & 0xff));
        }
        public string Hex => $"#{R:x2}{G:x2}{B:x2}";
    }

    /// <summary>The four colours a sheet is painted in; the app swaps them for each creature's own.</summary>
    public sealed record Palette(Tint Body, Tint Light, Tint Shade, Tint Outline)
    {
        public static readonly Palette Blocky = new(Tint.FromHex("#ff8a3d")!.Value, Tint.FromHex("#ffb27a")!.Value,
                                                   Tint.FromHex("#d66220")!.Value, Tint.FromHex("#3b1f0f")!.Value);

        public Tint? TintOf(Ink ink) => ink switch
        {
            Ink.Clear => null,
            Ink.Outline => Outline,
            Ink.Body => Body,
            Ink.Light => Light,
            Ink.Shade => Shade,
            _ => new Tint(0, 0, 0),
        };
    }

    public sealed class Sheet
    {
        public string Name { get; init; } = "";
        /// <summary>What the creature is, for the model: "a fat green frog with big eyes".</summary>
        public string? Kind { get; init; }
        /// <summary>Who its creatures are; creatures of this species take these in turn.</summary>
        public IReadOnlyList<Character> Cast { get; init; } = Array.Empty<Character>();
        /// <summary>The body colour this species always wears, when the sheet says; otherwise
        /// the app paints it in each creature's own colour.</summary>
        public Tint? Colour { get; init; }
        /// <summary>pose → 32 rows of 32 inks, eyes open.</summary>
        public IReadOnlyDictionary<string, Ink[][]> Poses { get; init; } = new Dictionary<string, Ink[][]>();
    }

    /// <summary>An RGBA sheet, 8 bits a channel, rows top to bottom.</summary>
    public sealed class Image
    {
        public int Width { get; }
        public int Height { get; }
        public byte[] Rgba { get; }
        public Image(int width, int height, byte[] rgba) { Width = width; Height = height; Rgba = rgba; }
    }

    public sealed class ParseException : Exception
    {
        public ParseException(string message) : base(message) { }
    }
}

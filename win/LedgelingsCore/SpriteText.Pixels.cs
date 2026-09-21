using System.Text.Json.Nodes;

namespace Ledgelings.Core;

public static partial class SpriteText
{
    // MARK: Pixels

    /// <summary>The whole sheet: poses left to right, eye variants top to bottom.</summary>
    public static Image Pixels(Sheet sheet, Palette palette)
    {
        int width = Poses.Count * Cell, height = Variants.Count * Cell;
        var rgba = new byte[width * height * 4];
        for (int column = 0; column < Poses.Count; column++)
        {
            if (!sheet.Poses.TryGetValue(Poses[column], out var open)) continue;
            for (int row = 0; row < Variants.Count; row++)
            {
                var grid = Variant(open, Variants[row]);
                for (int y = 0; y < Cell; y++)
                    for (int x = 0; x < Cell; x++)
                    {
                        if (palette.TintOf(grid[y][x]) is not Tint tint) continue;
                        var i = ((row * Cell + y) * width + column * Cell + x) * 4;
                        rgba[i] = tint.R; rgba[i + 1] = tint.G; rgba[i + 2] = tint.B; rgba[i + 3] = 255;
                    }
            }
        }
        return new Image(width, height, rgba);
    }

    /// <summary>The open-eyes grid of one pose, read back from a sheet, as rows of letters.
    /// A colour that is none of the palette's comes back as <c>x</c>.</summary>
    public static List<string> Describe(Image image, string pose, Palette palette)
    {
        var column = Poses.ToList().IndexOf(pose);
        var lines = new List<string>();
        if (column < 0) return lines;
        for (int y = 0; y < Cell; y++)
        {
            var chars = new char[Cell];
            for (int x = 0; x < Cell; x++)
            {
                var i = (y * image.Width + column * Cell + x) * 4;
                if (image.Rgba[i + 3] < 128) { chars[x] = Ink.Clear.Letter(); continue; }
                var here = new Tint(image.Rgba[i], image.Rgba[i + 1], image.Rgba[i + 2]);
                char? found = null;
                foreach (var ink in new[] { Ink.Outline, Ink.Body, Ink.Light, Ink.Shade })
                    if (Close(palette.TintOf(ink)!.Value, here)) { found = ink.Letter(); break; }
                chars[x] = found ?? (Close(new Tint(0, 0, 0), here) ? Ink.Eye.Letter() : Ink.Black.Letter());
            }
            lines.Add(new string(chars));
        }
        return lines;
    }

    private static bool Close(Tint a, Tint b) =>
        Math.Abs(a.R - b.R) <= 2 && Math.Abs(a.G - b.G) <= 2 && Math.Abs(a.B - b.B) <= 2;

    // MARK: The atlas file

    /// <summary>The JSON the app loads, for a sheet laid out by <see cref="Pixels"/>.</summary>
    public static JsonObject Atlas(string name, Palette? palette = null, string? kind = null,
                                   IReadOnlyList<Character>? cast = null, Tint? colour = null)
    {
        palette ??= Palette.Blocky;
        var frames = new JsonObject();
        for (int column = 0; column < Poses.Count; column++)
            for (int row = 0; row < Variants.Count; row++)
                frames[$"{Poses[column]}_{Variants[row]}"] = new JsonObject
                {
                    ["x"] = column * Cell, ["y"] = row * Cell, ["w"] = Cell, ["h"] = Cell,
                };
        var animations = new JsonObject();
        foreach (var (key, a) in Animations)
            animations[key] = new JsonObject
            {
                ["frames"] = new JsonArray(a.Frames.Select(f => (JsonNode)f).ToArray()), ["fps"] = a.Fps, ["loop"] = a.Loop,
            };
        var meta = new JsonObject
        {
            ["name"] = name,
            ["image"] = $"{name}.png",
            ["cell"] = new JsonArray(Cell, Cell),
            ["contentBox"] = new JsonArray(Box.X, Box.Y, Box.W, Box.H),
            ["variants"] = new JsonArray(Variants.Select(v => (JsonNode)v).ToArray()),
            ["palette"] = new JsonObject
            {
                ["body"] = palette.Body.Hex, ["light"] = palette.Light.Hex, ["shade"] = palette.Shade.Hex, ["outline"] = palette.Outline.Hex,
            },
            ["frames"] = frames,
            ["animations"] = animations,
        };
        if (kind is not null) meta["kind"] = kind;
        if (cast is { Count: > 0 })
            meta["cast"] = new JsonArray(cast.Select(c => (JsonNode)new JsonObject { ["name"] = c.Name, ["persona"] = c.Persona }).ToArray());
        if (colour is Tint t) meta["colour"] = t.Hex;
        return meta;
    }
}

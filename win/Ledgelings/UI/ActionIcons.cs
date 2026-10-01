using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace Ledgelings.UI;

/// <summary>Each Creature Actions tile's picture, cut from the sprites the creatures already wear,
/// so the sheet is drawn in the same hand as the screen. Talking has no sprite of its own, so its
/// bubble is drawn here in Blocky's rules.</summary>
public static class ActionIcons
{
    private static Dictionary<ActionsTile, Bitmap>? pictures;

    public static Bitmap? Picture(ActionsTile tile) => (pictures ??= Make()).GetValueOrDefault(tile);

    /// <summary>A speech bubble with three dots: o rim, l light, w fill, s shade, k ink.</summary>
    public static readonly string[] Bubble =
    {
        ".oooooooooooooo.",
        "ollllllllllllllo",
        "olwwwwwwwwwwwwso",
        "olwwwwwwwwwwwwso",
        "olwkkwwkkwwkkwso",
        "olwkkwwkkwwkkwso",
        "olwwwwwwwwwwwwso",
        "olwwwwwwwwwwwwso",
        "osssssssssssssso",
        ".ooooowsooooooo.",
        ".....owso.......",
        ".....oso........",
        ".....oo.........",
    };

    private static readonly Dictionary<char, Color> inks = new()
    {
        ['o'] = Color.FromArgb(40, 34, 58), ['l'] = Color.FromArgb(255, 255, 255), ['w'] = Color.FromArgb(244, 241, 230),
        ['s'] = Color.FromArgb(196, 192, 206), ['k'] = Color.FromArgb(40, 34, 58),
    };

    private static Dictionary<ActionsTile, Bitmap> Make()
    {
        var made = new Dictionary<ActionsTile, Bitmap>();
        SpriteAtlas.Frames? Load(string name)
        {
            try { return SpriteAtlas.Named(name).MakeFrames(); }
            catch (Exception e) when (e is IOException or InvalidDataException) { return null; }
        }
        void Put(ActionsTile tile, Bitmap? image) { if (image is not null) made[tile] = Trimmed(image); }
        var blocky = Load("blocky");
        var plane = Load("plane");
        Put(ActionsTile.Jump, blocky?.Frame("jump", 0));
        Put(ActionsTile.Talk, Glyph(Bubble));
        Put(ActionsTile.Tea, Load("tea")?.Frame("steam", 0));
        Put(ActionsTile.Plane, plane?.Frame("fly", 0));
        Put(ActionsTile.Reminder, plane?.Frame("letter", 0));
        Put(ActionsTile.Hide, Load("house")?.Frame("house", 0));
        Put(ActionsTile.Sleep, Compose(blocky?.Frame("sleep", 0), Load("zzz")?.Frame("float", 0)));
        Put(ActionsTile.Flowers, Load("flowers")?.Frame("poppy", 0));
        return made;
    }

    /// <summary>Rows of characters as an image, one pixel each; <c>.</c> is see-through.</summary>
    public static Bitmap Glyph(string[] rows)
    {
        var w = rows.Max(r => r.Length);
        var image = new Bitmap(w, rows.Length, PixelFormat.Format32bppArgb);
        for (int y = 0; y < rows.Length; y++)
            for (int x = 0; x < rows[y].Length; x++)
                if (inks.TryGetValue(rows[y][x], out var c)) image.SetPixel(x, y, c);
        return image;
    }

    /// <summary>The picture cut down to its painted pixels: a sprite cell has room to move in.</summary>
    public static Bitmap Trimmed(Bitmap image)
    {
        var rect = new Rectangle(0, 0, image.Width, image.Height);
        var data = image.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        var bytes = new byte[data.Stride * image.Height];
        try { Marshal.Copy(data.Scan0, bytes, 0, bytes.Length); }
        finally { image.UnlockBits(data); }
        int minX = image.Width, minY = image.Height, maxX = -1, maxY = -1;
        for (int y = 0; y < image.Height; y++)
            for (int x = 0; x < image.Width; x++)
                if (bytes[y * data.Stride + x * 4 + 3] >= 128)
                {
                    minX = Math.Min(minX, x); maxX = Math.Max(maxX, x);
                    minY = Math.Min(minY, y); maxY = Math.Max(maxY, y);
                }
        if (maxX < minX) return image;
        return image.Clone(new Rectangle(minX, minY, maxX - minX + 1, maxY - minY + 1), PixelFormat.Format32bppArgb);
    }

    /// <summary>A sleeper with a Z rising over its head, top right.</summary>
    private static Bitmap? Compose(Bitmap? sleeper, Bitmap? z)
    {
        if (sleeper is null || z is null) return sleeper;
        var image = new Bitmap(sleeper.Width, sleeper.Height, PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(image);
        g.InterpolationMode = InterpolationMode.NearestNeighbor;
        g.PixelOffsetMode = PixelOffsetMode.Half;
        g.DrawImage(sleeper, 0, 0, sleeper.Width, sleeper.Height);
        g.DrawImage(z, sleeper.Width - z.Width, 0, z.Width, z.Height);
        return image;
    }
}

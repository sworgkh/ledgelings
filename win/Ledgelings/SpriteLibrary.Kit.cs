using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The sprite kit: the prompt for an image model, its two pictures, the built-in
/// creature as text (for hand editing), and the magenta key-out of an exact sheet.</summary>
public sealed partial class SpriteLibrary
{
    /// <summary>The built-in creature written in the text format: the worked example, and a file to hand out.</summary>
    public string ExampleText
    {
        get
        {
            var blocky = Atlas("blocky");
            if (blocky is null) return "";
            var image = blocky.Image();
            var lines = new List<string> { "name: blocky" };
            foreach (var pose in SpriteText.Poses)
            {
                lines.Add("pose: " + pose);
                lines.AddRange(SpriteText.Describe(image, pose, SpriteText.Palette.Blocky));
            }
            return string.Join("\n", lines) + "\n";
        }
    }

    /// <summary>What to paste into an image model, with <see cref="KitImages"/> attached.</summary>
    public string Prompt(SpriteKit.Form form) => SpriteKit.ImagePrompt(form);

    private IReadOnlyList<(string Name, SpriteText.Image Image)>? kitImages;

    /// <summary>The prompt's attachments, in its order, by the file names it calls them:
    /// the built-in creature's nine poses, and the empty template. The Mac's bytes.</summary>
    public IReadOnlyList<(string Name, SpriteText.Image Image)> KitImages => kitImages ??= new[]
    {
        (SpriteKit.AttachmentNames[0], SpriteKit.PosesImage(Atlas("blocky")?.Image() ?? new SpriteText.Image(0, 0, Array.Empty<byte>()))),
        (SpriteKit.AttachmentNames[1], SpriteKit.TemplateImage()),
    };

    /// <summary>Write the attachments into <paramref name="folder"/>, overwriting earlier copies. Returns their files.</summary>
    public IReadOnlyList<string> SaveKitImages(string folder)
    {
        System.IO.Directory.CreateDirectory(folder);
        return KitImages.Select(item =>
        {
            var file = Path.Combine(folder, item.Name);
            PngIO.Write(item.Image, file);
            return file;
        }).ToList();
    }

    /// <summary>A sheet in the exact layout, 288×96 or a whole multiple: painted by hand, read pixel for pixel.</summary>
    public static bool IsExactSheet(SpriteText.Image image)
    {
        int w = SpriteText.Poses.Count * SpriteText.Cell, h = SpriteText.Variants.Count * SpriteText.Cell;
        return image.Width >= w && image.Width % w == 0 && image.Height % h == 0 && image.Width / w == image.Height / h;
    }

    /// <summary>A blank 288×96 sheet on magenta with the cells and body boxes marked, for a paint program.</summary>
    public SpriteText.Image TemplateImage()
    {
        int cell = SpriteText.Cell;
        var box = SpriteText.Box;
        int w = SpriteText.Poses.Count * cell, h = SpriteText.Variants.Count * cell;
        var rgba = new byte[w * h * 4];
        void Put(int x, int y, SpriteText.Tint t)
        {
            var i = (y * w + x) * 4;
            rgba[i] = t.R; rgba[i + 1] = t.G; rgba[i + 2] = t.B; rgba[i + 3] = 255;
        }
        var key = KeyColour;
        var grid = new SpriteText.Tint(200, 0, 200);
        var boxLine = new SpriteText.Tint(255, 120, 255);
        for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) Put(x, y, key);
        for (int y = 0; y < h; y++) for (int x = 0; x < w; x += cell) Put(x, y, grid);
        for (int x = 0; x < w; x++) for (int y = 0; y < h; y += cell) Put(x, y, grid);
        for (int column = 0; column < SpriteText.Poses.Count; column++)
            for (int row = 0; row < SpriteText.Variants.Count; row++)
            {
                int ox = column * cell + box.X, oy = row * cell + box.Y;
                for (int x = ox; x < ox + box.W; x++) { Put(x, oy, boxLine); Put(x, oy + box.H - 1, boxLine); }
                for (int y = oy; y < oy + box.H; y++) { Put(ox, y, boxLine); Put(ox + box.W - 1, y, boxLine); }
            }
        return new SpriteText.Image(w, h, rgba);
    }

    /// <summary>Magenta (within tolerance) becomes transparent; alpha is hardened to 1 bit;
    /// a sheet painted at a whole-number scale is brought down by sampling.</summary>
    public static SpriteText.Image KeyedOut(SpriteText.Image image)
    {
        int w = SpriteText.Poses.Count * SpriteText.Cell, h = SpriteText.Variants.Count * SpriteText.Cell;
        if (image.Width % w != 0 || image.Height % h != 0 || image.Width / w != image.Height / h || image.Width < w)
            throw new ImportException(L10n.Tr("the PNG is %d×%d; a sheet is 288×96, or a whole multiple of that", image.Width, image.Height));
        var k = image.Width / w;
        var output = new byte[w * h * 4];
        var key = KeyColour;
        var limit = KeyTolerance * KeyTolerance;
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                var src = ((y * k + k / 2) * image.Width + x * k + k / 2) * 4;
                var dst = (y * w + x) * 4;
                int r = image.Rgba[src], g = image.Rgba[src + 1], b = image.Rgba[src + 2], a = image.Rgba[src + 3];
                var isKey = (r - key.R) * (r - key.R) + (g - key.G) * (g - key.G) + (b - key.B) * (b - key.B) <= limit;
                if (a < 128 || isKey) continue;
                output[dst] = (byte)r; output[dst + 1] = (byte)g; output[dst + 2] = (byte)b; output[dst + 3] = 255;
            }
        return new SpriteText.Image(w, h, output);
    }
}

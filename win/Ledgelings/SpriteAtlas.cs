using System.Drawing;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>An sRGB colour, 8 bits a channel, that round-trips through "#rrggbb".</summary>
public readonly record struct RGB(byte R, byte G, byte B)
{
    public static readonly RGB White = new(255, 255, 255);
    public static readonly RGB Black = new(0, 0, 0);

    public static RGB? FromHex(string? hex)
    {
        if (hex is null) return null;
        var text = hex.StartsWith('#') ? hex[1..] : hex;
        if (text.Length != 6 || !uint.TryParse(text, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var value)) return null;
        return new RGB((byte)(value >> 16 & 0xFF), (byte)(value >> 8 & 0xFF), (byte)(value & 0xFF));
    }

    public string Hex => $"#{R:x2}{G:x2}{B:x2}";

    public RGB Mixed(RGB other, double amount)
    {
        byte Mix(byte a, byte b) => (byte)Math.Round(a * (1 - amount) + b * amount, MidpointRounding.AwayFromZero);
        return new RGB(Mix(R, other.R), Mix(G, other.G), Mix(B, other.B));
    }

    /// <summary>Exact in practice; the slack absorbs a colour-managed decode being off by one.</summary>
    public bool IsClose(RGB other) => Math.Abs(R - other.R) <= 2 && Math.Abs(G - other.G) <= 2 && Math.Abs(B - other.B) <= 2;

    public Color ToColor() => Color.FromArgb(R, G, B);
}

/// <summary>A packed sprite sheet: the PNG and JSON that <c>spritetool pack</c> writes.</summary>
public sealed class SpriteAtlas
{
    public sealed class Meta
    {
        public sealed record FrameRect(int X, int Y, int W, int H);
        public sealed record Animation(List<string> Frames, double Fps, bool Loop);
        public string Name { get; set; } = "";
        public string Image { get; set; } = "";
        public int[] Cell { get; set; } = { 32, 32 };
        public int[] ContentBox { get; set; } = { 5, 5, 22, 22 };
        public List<string> Variants { get; set; } = new();
        public Dictionary<string, string>? Palette { get; set; }
        public Dictionary<string, FrameRect> Frames { get; set; } = new();
        public Dictionary<string, Animation> Animations { get; set; } = new();
        /// <summary>What the creature is, and who its creatures are, when the sheet says.</summary>
        public string? Kind { get; set; }
        public List<Character>? Cast { get; set; }
        /// <summary>The body colour this species always wears, when the sheet chose one.</summary>
        public string? Colour { get; set; }
    }

    /// <summary>One recolouring of the sheet, already cut into frames.</summary>
    public sealed class Frames
    {
        private readonly Meta meta;
        private readonly Dictionary<string, Bitmap> images;
        internal Frames(Meta meta, Dictionary<string, Bitmap> images) { this.meta = meta; this.images = images; }

        /// <summary>The frame for an animation at <paramref name="time"/> seconds in, with the given eye state.</summary>
        public Bitmap? Frame(string animation, double time, Eyes eyes = Eyes.Open)
        {
            if (!meta.Animations.TryGetValue(animation, out var anim) || anim.Frames.Count == 0) return null;
            var raw = (int)(time * anim.Fps);
            var index = anim.Loop ? raw % anim.Frames.Count : Math.Min(raw, anim.Frames.Count - 1);
            var pose = anim.Frames[index];
            return images.TryGetValue($"{pose}_{eyes.Key()}", out var exact) ? exact : images.TryGetValue(pose, out var plain) ? plain : null;
        }
    }

    private static readonly JsonSerializerOptions jsonOptions = new()
    {
        PropertyNameCaseInsensitive = true, NumberHandling = JsonNumberHandling.AllowReadingFromString,
    };

    public Meta Info { get; }
    private readonly SpriteText.Image sheet;

    public Size CellSize => new(Info.Cell[0], Info.Cell[1]);
    /// <summary>Half the width of the square the creature is drawn inside, in sheet pixels.</summary>
    public double BodyHalfSize => Info.ContentBox[2] / 2.0;

    /// <summary>The folder of sheets shipped next to the exe.</summary>
    public static string SpritesDirectory => Path.Combine(AppContext.BaseDirectory, "sprites");

    /// <summary>A sheet shipped inside the app.</summary>
    public static SpriteAtlas Named(string name) => new(SpritesDirectory, name);

    /// <summary>A sheet in any folder: <c>&lt;name&gt;.json</c> next to the PNG it names.</summary>
    public SpriteAtlas(string directory, string name)
    {
        var jsonPath = Path.Combine(directory, name + ".json");
        if (!File.Exists(jsonPath)) throw new FileNotFoundException("sprite resource not found: " + jsonPath);
        Info = JsonSerializer.Deserialize<Meta>(File.ReadAllText(jsonPath), jsonOptions) ?? throw new InvalidDataException("empty atlas: " + jsonPath);
        var imagePath = Path.Combine(directory, Info.Image);
        if (!File.Exists(imagePath)) throw new FileNotFoundException("cannot read sprite resource: " + imagePath);
        sheet = Harden(PngIO.Read(imagePath));
        foreach (var (frame, r) in Info.Frames)
            if (r.X + r.W > sheet.Width || r.Y + r.H > sheet.Height) throw new InvalidDataException($"atlas frame {frame} lies outside the sheet");
    }

    /// <summary>Pixel art has 1-bit alpha: drop the faint pixels, make the rest solid.</summary>
    private static SpriteText.Image Harden(SpriteText.Image image)
    {
        var rgba = new byte[image.Rgba.Length];
        for (int i = 0; i < rgba.Length; i += 4)
        {
            if (image.Rgba[i + 3] < 128) continue;
            rgba[i] = image.Rgba[i]; rgba[i + 1] = image.Rgba[i + 1]; rgba[i + 2] = image.Rgba[i + 2]; rgba[i + 3] = 255;
        }
        return new SpriteText.Image(image.Width, image.Height, rgba);
    }

    /// <summary>The whole sheet as bytes, rows top to bottom, straight alpha.</summary>
    public SpriteText.Image Image() => sheet;

    /// <summary>The sheet cut into frames, recoloured around <paramref name="body"/> when the atlas has a
    /// palette. Null body means "as painted".</summary>
    public Frames MakeFrames(RGB? body = null)
    {
        var source = body is RGB colour ? Recoloured(colour) ?? sheet : sheet;
        var cut = new Dictionary<string, Bitmap>();
        foreach (var (frame, r) in Info.Frames)
            cut[frame] = PngIO.ToBitmap(source, new Rectangle(r.X, r.Y, r.W, r.H));
        return new Frames(Info, cut);
    }

    /// <summary>Swap the atlas palette for shades of <paramref name="body"/>. Every other pixel -- the
    /// black eyes above all -- is left exactly as it was.</summary>
    private SpriteText.Image? Recoloured(RGB body)
    {
        if (Info.Palette is null || Info.Palette.Count == 0) return null;
        var targets = new Dictionary<string, RGB>
        {
            ["body"] = body, ["light"] = body.Mixed(RGB.White, 0.36),
            ["shade"] = body.Mixed(RGB.Black, 0.17), ["outline"] = body.Mixed(RGB.Black, 0.76),
        };
        var swaps = new List<(RGB From, RGB To)>();
        foreach (var (name, hex) in Info.Palette)
            if (RGB.FromHex(hex) is RGB from && targets.TryGetValue(name, out var to)) swaps.Add((from, to));
        var rgba = (byte[])sheet.Rgba.Clone();
        for (int i = 0; i < rgba.Length; i += 4)
        {
            if (rgba[i + 3] != 255) continue;
            var here = new RGB(rgba[i], rgba[i + 1], rgba[i + 2]);
            foreach (var (from, to) in swaps)
                if (from.IsClose(here)) { rgba[i] = to.R; rgba[i + 1] = to.G; rgba[i + 2] = to.B; break; }
        }
        return new SpriteText.Image(sheet.Width, sheet.Height, rgba);
    }
}

using System.Runtime.CompilerServices;
using System.Security.Cryptography;

namespace Ledgelings.Core.Tests;

/// <summary>The sprite kit: the pictures (the Mac's bytes), reading back what an image
/// model paints, and the prompts. The Mac's SpriteKitTests and SpriteKitPromptTests.</summary>
public class SpriteKitTests
{
    /// <summary>The same constants as the Mac's SpriteKitTests: both apps draw the same pictures.</summary>
    private const string TemplateSha = "18203cf4dcf942af7279f82ec25477c37741a7e02bf9e367901bd459a3150535";
    private const string PosesSha = "aab71e929bb733b44e4e7e19bb05c7574fb2df8e68407704d28459580d0d6589";

    private static string Here([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
    private static readonly SpriteText.Sheet BlockyText = SpriteText.Parse(File.ReadAllText(Path.Combine(Here(), "Fixtures", "blocky.txt")));
    private static readonly SpriteText.Image Blocky = SpriteText.Pixels(BlockyText, SpriteText.Palette.Blocky);

    private static string Sha(SpriteText.Image image) => Convert.ToHexString(SHA256.HashData(image.Rgba)).ToLowerInvariant();

    private sealed record Paint
    {
        public int Width { get; init; } = 1728;
        public int Height { get; init; } = 288;
        public SpriteText.Tint Paper { get; init; } = new(255, 0, 255);
        public double Scale { get; init; } = 6;
        public int Columns { get; init; } = 9;
        public double X { get; init; }
        public double Y { get; init; } = 48;
        public double Cell { get; init; } = 192;
        public int Blur { get; init; }
        public int Noise { get; init; }
        public SpriteText.Tint? BodyColour { get; init; }
    }

    /// <summary>Blocky's nine poses painted the way an image model might hand them back.</summary>
    private static SpriteText.Image Painted(Paint p)
    {
        var img = new SpriteText.Image(p.Width, p.Height, new byte[p.Width * p.Height * 4]);
        void Put(int x, int y, SpriteText.Tint t)
        {
            if (x < 0 || y < 0 || x >= p.Width || y >= p.Height) return;
            var i = (y * p.Width + x) * 4;
            img.Rgba[i] = t.R; img.Rgba[i + 1] = t.G; img.Rgba[i + 2] = t.B; img.Rgba[i + 3] = 255;
        }
        for (var y = 0; y < p.Height; y++) for (var x = 0; x < p.Width; x++) Put(x, y, p.Paper);
        for (var n = 0; n < 9; n++)
        {
            double cx = p.X + n % p.Columns * p.Cell, cy = p.Y + n / p.Columns * p.Cell;
            for (var y = 0; y < 32; y++)
                for (var x = 0; x < 32; x++)
                {
                    var i = (y * Blocky.Width + n * 32 + x) * 4;
                    if (Blocky.Rgba[i + 3] < 128) continue;
                    var t = new SpriteText.Tint(Blocky.Rgba[i], Blocky.Rgba[i + 1], Blocky.Rgba[i + 2]);
                    if (p.BodyColour is SpriteText.Tint body && t == SpriteText.Palette.Blocky.Body) t = body;
                    int x0 = (int)(cx + x * p.Scale), x1 = (int)(cx + (x + 1) * p.Scale), y0 = (int)(cy + y * p.Scale), y1 = (int)(cy + (y + 1) * p.Scale);
                    for (var yy = y0; yy < y1; yy++) for (var xx = x0; xx < x1; xx++) Put(xx, yy, t);
                }
        }
        for (var k = 0; k < p.Blur; k++) img = BoxBlur(img);
        if (p.Noise > 0)
        {
            uint seed = 12345;
            for (var i = 0; i < img.Rgba.Length; i++)
            {
                if (i % 4 == 3) continue;
                seed = seed * 1664525 + 1013904223;
                var d = (int)(seed >> 24) % (2 * p.Noise + 1) - p.Noise;
                img.Rgba[i] = (byte)Math.Clamp(img.Rgba[i] + d, 0, 255);
            }
        }
        return img;
    }

    private static SpriteText.Image BoxBlur(SpriteText.Image img)
    {
        var output = new SpriteText.Image(img.Width, img.Height, (byte[])img.Rgba.Clone());
        for (var y = 0; y < img.Height; y++)
            for (var x = 0; x < img.Width; x++)
            {
                int r = 0, g = 0, b = 0, a = 0, n = 0;
                for (var dy = -1; dy <= 1; dy++)
                    for (var dx = -1; dx <= 1; dx++)
                    {
                        int xx = x + dx, yy = y + dy;
                        if (xx < 0 || yy < 0 || xx >= img.Width || yy >= img.Height) continue;
                        var j = (yy * img.Width + xx) * 4;
                        r += img.Rgba[j]; g += img.Rgba[j + 1]; b += img.Rgba[j + 2]; a += img.Rgba[j + 3]; n++;
                    }
                var i = (y * img.Width + x) * 4;
                output.Rgba[i] = (byte)(r / n); output.Rgba[i + 1] = (byte)(g / n); output.Rgba[i + 2] = (byte)(b / n); output.Rgba[i + 3] = (byte)(a / n);
            }
        return output;
    }

    /// <summary>The fewest of a pose's 1024 pixels that came back as Blocky has them.</summary>
    private static int Worst(SpriteKit.Reading reading) => SpriteText.Poses.Min(pose =>
    {
        var want = BlockyText.Poses[pose];
        var got = reading.Poses[pose];
        var same = 0;
        for (var y = 0; y < 32; y++) for (var x = 0; x < 32; x++) if (got[y][x] == want[y][x]) same++;
        return same;
    });

    // MARK: The pictures

    [Fact]
    public void ThePicturesAreTheMacsBytes()
    {
        Assert.Equal(TemplateSha, Sha(SpriteKit.TemplateImage()));
        Assert.Equal(PosesSha, Sha(SpriteKit.PosesImage(Blocky)));
        Assert.True(SpriteKit.TemplateImage().Width == 1728 && SpriteKit.TemplateImage().Height == 288);
    }

    [Fact]
    public void ThePicturesReadBackAsBlockyHimself()
    {
        var reading = SpriteKit.Read(SpriteKit.PosesImage(Blocky));
        Assert.Equal(1024, Worst(reading));
        Assert.Equal(SpriteText.Palette.Blocky.Body, reading.Colour);
    }

    // MARK: Forgiving import

    [Fact]
    public void ABlurredNoisyOffSizeStripStillReads()
    {
        var reading = SpriteKit.Read(Painted(new Paint { Width = 1500, Height = 260, Scale = 5.3, Cell = 166, X = 12, Y = 44, Blur = 2, Noise = 8 }));
        Assert.True(Worst(reading) >= 1000, Worst(reading).ToString());
        Assert.Equal(36, reading.Poses["idle"].SelectMany(r => r).Count(i => i == SpriteText.Ink.Eye));
    }

    [Fact]
    public void ASquarePictureInThreeRowsOnWhiteReads()
    {
        var reading = SpriteKit.Read(Painted(new Paint
        {
            Width = 1024, Height = 1024, Paper = new(250, 250, 248), Columns = 3, Scale = 9.4, Cell = 330, X = 20, Y = 30, Blur = 1, Noise = 4,
            BodyColour = SpriteText.Tint.FromHex("#6cbf4a"),
        }));
        Assert.True(Worst(reading) >= 1000, Worst(reading).ToString());
        var c = reading.Colour;
        Assert.True(Math.Abs(c.R - 0x6c) < 10 && Math.Abs(c.G - 0xbf) < 10 && Math.Abs(c.B - 0x4a) < 10, c.Hex);
    }

    [Fact]
    public void TooFewCreaturesIsSaidPlainly()
    {
        Assert.Throws<SpriteKit.ReadException>(() => SpriteKit.Read(Painted(new Paint { Width = 900 })));
        var e = Assert.Throws<SpriteKit.ReadException>(() => SpriteKit.Read(SpriteKit.TemplateImage()));
        Assert.True(e.Found < 9);
        Assert.Contains("creatures in the picture, not 9", Languages.With(Language.English, () => e.Message));
    }

    // MARK: Prompts

    private static readonly SpriteKit.Form Moss = new()
    {
        Kind = "a boxy moss sprite with a leaf on top", Name = "Moss", Colour = "#55AA33",
        Cast = new[] { new Character("Fern", "tiny, fast, anxious") },
    };

    [Theory]
    [InlineData(Language.English)]
    [InlineData(Language.Russian)]
    public void TheImagePromptAsksForAPictureAndShowsNoLetters(Language language)
    {
        var prompt = SpriteKit.ImagePrompt(Moss, language);
        Assert.True(prompt.Contains("a boxy moss sprite with a leaf on top") && prompt.Contains("#55aa33") && prompt.Contains("moss"));
        foreach (var name in SpriteKit.AttachmentNames) Assert.Contains(name, prompt);
        foreach (var pose in SpriteText.Poses) Assert.Contains(pose, prompt);
        Assert.False(prompt.Contains("oooo") || prompt.Contains("...") || prompt.Contains(". o b l s k x"));
        Assert.False(prompt.Contains("pose:") || prompt.Contains("character:"));
        Assert.DoesNotContain("{", prompt);
    }

    [Fact]
    public void AnEmptyFormLeavesTheChoiceToTheModel()
    {
        var prompt = SpriteKit.ImagePrompt(new SpriteKit.Form(), Language.English);
        Assert.Contains(Languages.With(Language.English, () => SpriteText.DescribePlaceholder), prompt);
        Assert.True(prompt.Contains("Choose a body colour") && !prompt.Contains("Its name"));
    }

    [Fact]
    public void AFormHasThreeCharactersAndASafeName()
    {
        Assert.Equal(3, new SpriteKit.Form().Cast.Count);
        Assert.Equal(3, new SpriteKit.Form { Cast = Enumerable.Repeat(new Character("a", ""), 5).ToList() }.Cast.Count);
        Assert.Equal("moss-ball", SpriteKit.SpeciesName("Moss Ball!"));
        Assert.Null(SpriteKit.SpeciesName("  Ёж "));
        Assert.Equal("chatgpt-image-3-oct", SpriteKit.SpeciesName("ChatGPT Image 3 Oct"));
    }

    [Fact]
    public void TheRefinePromptCarriesTheIdeaAndTheRules()
    {
        var prompt = SpriteKit.RefinePrompt(Moss, Language.English);
        Assert.True(prompt.Contains("a boxy moss sprite") && prompt.Contains("Fern (tiny, fast, anxious)") && prompt.Contains("#55aa33"));
        foreach (var word in new[] { "square body", "outline", "square eyes", "no curves", "SOUNDS", "old or young", "he or she" }) Assert.Contains(word, prompt);
        Assert.Contains("name: none", SpriteKit.RefinePrompt(new SpriteKit.Form(), Language.English));
        Assert.Contains("\"characters\"", SpriteKit.RefinePrompt(Moss, Language.Russian));
    }

    [Fact]
    public void ARefinedAnswerFillsTheForm()
    {
        const string answer = """
            Sure! ```json
            {"name": "Mossy", "kind": "a boxy green moss block with a stepped leaf on top", "colour": "#4f9a3a",
             "characters": [{"name": "Fern", "persona": "A tiny anxious girl who talks fast."},
                            {"name": "Bark", "persona": "An old slow grumpy man."},
                            {"name": "Sprig", "persona": "A cheerful young boy."}]}
            ```
            """;
        var output = SpriteKit.ParseRefine(answer, new SpriteKit.Form { Kind = "moss" })!;
        Assert.True(output.Name == "mossy" && output.Colour == "#4f9a3a" && output.Kind.StartsWith("a boxy green moss block"));
        Assert.Equal(new[] { "Fern", "Bark", "Sprig" }, output.Cast.Select(c => c.Name));
    }

    [Fact]
    public void APartOrUnusableAnswerKeepsWhatWasThere()
    {
        var form = new SpriteKit.Form { Kind = "moss", Name = "moss", Colour = "#112233" };
        var part = SpriteKit.ParseRefine("""{"kind": "a moss cube", "colour": "green"}""", form)!;
        Assert.True(part.Kind == "a moss cube" && part.Colour == "#112233" && part.Name == "moss");
        Assert.Null(SpriteKit.ParseRefine("I cannot help with that.", form));
        Assert.Null(SpriteKit.ParseRefine("{}", form));
    }

    [Fact]
    public void RefiningIsItsOwnLineInTheCosts()
    {
        var usage = new Spend.Usage(400, 200, 0.0003);
        var records = new[]
        {
            new Spend.Record(DateTimeOffset.Now, "OpenRouter", "m", usage, Spend.Purpose.CreatureRefine),
            new Spend.Record(DateTimeOffset.Now, "OpenRouter", "m", usage, Spend.Purpose.Talk),
        };
        var s = Spend.Summarise(records, DateTimeOffset.Now);
        var line = s.ByPurpose.First(p => p.Purpose == Languages.With(Language.English, () => Spend.Purpose.CreatureRefine.Title()));
        Assert.Equal(1, line.Total.Calls);
        Assert.Equal("creatureRefine", Spend.Purpose.CreatureRefine.Raw());
    }
}

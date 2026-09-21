namespace Ledgelings.Tests;

/// <summary>Imported creatures: text or PNG in, a loadable atlas out, kept in their own folder.</summary>
public class SpriteLibraryTests : IDisposable
{
    private readonly List<string> temp = new();

    private string TempPath(string name)
    {
        var path = Path.Combine(Path.GetTempPath(), name);
        temp.Add(path);
        return path;
    }

    private SpriteLibrary Fresh() => new(TempPath("ledgelings-sprites-" + Guid.NewGuid()));

    public void Dispose()
    {
        foreach (var path in temp)
        {
            try { if (Directory.Exists(path)) Directory.Delete(path, true); else File.Delete(path); } catch (IOException) { }
        }
    }

    private static void AssertSameImage(SpriteText.Image expected, SpriteText.Image actual, string? why = null)
    {
        Assert.True(expected.Width == actual.Width && expected.Height == actual.Height, why ?? "sizes differ");
        Assert.True(expected.Rgba.AsSpan().SequenceEqual(actual.Rgba), why ?? "pixels differ");
    }

    [Fact]
    public void TheBuiltInCreatureIsAlwaysThereAndCannotBeRemoved()
    {
        var library = Fresh();
        Assert.Equal(SpriteLibrary.BuiltIn, library.AllSpecies.Select(s => s.Name));
        Assert.True(library.AllSpecies.All(s => s.IsBuiltIn));
        library.Remove("blocky");
        Assert.Equal(SpriteLibrary.BuiltIn, library.AllSpecies.Select(s => s.Name));
        Assert.True(library.Kind("frog").Contains("frog") && library.Cast("frog").Count == 3);
        Assert.Equal(Banter.DefaultCharacters, library.Cast("blocky"));
    }

    [Fact]
    public void TheBuiltInCreatureRoundTripsThroughTheTextFormat()
    {
        var library = Fresh();
        var sheet = SpriteText.Parse(library.ExampleText);
        Assert.Equal("blocky", sheet.Name);
        var original = SpriteAtlas.Named("blocky").Image();
        var rebuilt = SpriteText.Pixels(sheet, SpriteText.Palette.Blocky);
        AssertSameImage(original, rebuilt, "letters -> pixels gives back the shipped sheet exactly");
    }

    [Fact]
    public void ASheetThatNamesItsColourAlwaysWearsIt()
    {
        var library = Fresh();
        var file = TempPath("hog-" + Guid.NewGuid() + ".txt");
        File.WriteAllText(file, library.ExampleText.Replace("name: blocky", "name: hog\ncolour: #f0a0b0"));
        library.ImportFile(file);
        var slot = RGB.FromHex("#3366ff")!.Value;
        Assert.Equal(RGB.FromHex("#f0a0b0"), library.BodyColour("hog", slot));
        Assert.True(library.BodyColour("blocky", slot) == slot, "a sheet with no colour line takes the creature's slot colour");
        Assert.Equal(slot, library.BodyColour("nobody", slot));
    }

    [Fact]
    public void ATextFileBecomesASpeciesWithAFullAtlas()
    {
        var library = Fresh();
        var file = TempPath("pip-" + Guid.NewGuid() + ".txt");
        File.WriteAllText(file, library.ExampleText.Replace("name: blocky", "name: pip"));
        var name = library.ImportFile(file);
        Assert.Equal("pip", name);
        Assert.Equal(SpriteLibrary.BuiltIn.Append("pip"), library.AllSpecies.Select(s => s.Name));
        var atlas = new SpriteAtlas(Path.Combine(library.Directory, "pip"), "pip");
        Assert.Equal(27, atlas.Info.Frames.Count);
        Assert.NotNull(atlas.MakeFrames().Frame("walk", 0.2, Eyes.Half));
        Assert.Equal(11, atlas.BodyHalfSize);
        library.Remove("pip");
        Assert.Equal(SpriteLibrary.BuiltIn, library.AllSpecies.Select(s => s.Name));
        Assert.False(Directory.Exists(Path.Combine(library.Directory, "pip")));
    }

    [Fact]
    public void APaintedSheetOnMagentaIsKeyedOutAndSliced()
    {
        var library = Fresh();
        // The shipped sheet, put back on the key colour, is what an image model would hand us.
        var original = SpriteAtlas.Named("blocky").Image();
        var rgba = (byte[])original.Rgba.Clone();
        for (int i = 0; i < rgba.Length; i += 4)
            if (rgba[i + 3] < 128) { rgba[i] = 255; rgba[i + 1] = 0; rgba[i + 2] = 255; rgba[i + 3] = 255; }
        var onMagenta = new SpriteText.Image(original.Width, original.Height, rgba);
        var file = Path.Combine(TempPath("ledgelings-dot-" + Guid.NewGuid()), "dot.png");
        PngIO.Write(onMagenta, file);
        var name = library.ImportFile(file);
        Assert.Equal("dot", name);
        var atlas = new SpriteAtlas(Path.Combine(library.Directory, "dot"), "dot");
        AssertSameImage(original, atlas.Image(), "magenta became transparent, nothing else changed");
    }

    [Fact]
    public void ABadTextFileIsRefusedWithTheParsersWords()
    {
        var library = Fresh();
        var file = TempPath("bad-" + Guid.NewGuid() + ".txt");
        File.WriteAllText(file, "name: bad\npose: idle\n....\n");
        var error = Assert.Throws<SpriteLibrary.ImportException>(() => library.ImportFile(file));
        Assert.Contains("rows", error.Message);
        Assert.Equal(SpriteLibrary.BuiltIn.Count, library.AllSpecies.Count);
    }

    [Fact]
    public void ThePromptShowsTheBuiltInIdlePoseAsLetters()
    {
        var library = Fresh();
        var prompt = library.Prompt;
        Assert.Contains(SpriteText.DescribePlaceholder, prompt);
        var idle = SpriteText.Describe(SpriteAtlas.Named("blocky").Image(), "idle", SpriteText.Palette.Blocky);
        Assert.Contains(string.Join("\n", idle), prompt);
        Assert.True(idle[26].Contains('o'), "the example stands on the floor");
    }
}

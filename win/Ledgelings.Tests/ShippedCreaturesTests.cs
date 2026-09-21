namespace Ledgelings.Tests;

/// <summary>The built-in creatures are written in the letter format under sprites/text/ at the
/// repo root. This keeps the shipped sheets in step with them. (The rebuild path the macOS
/// suite offers under LEDGELINGS_BUILD_CREATURES is not ported; run `swift test` for that.)</summary>
public class ShippedCreaturesTests
{
    /// <summary>The repo root: the first ancestor of the test binary that holds sprites/text.</summary>
    private static string Repo
    {
        get
        {
            for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
                if (Directory.Exists(Path.Combine(dir.FullName, "sprites", "text"))) return dir.FullName;
            throw new DirectoryNotFoundException("sprites/text not found above " + AppContext.BaseDirectory);
        }
    }

    public static IEnumerable<object[]> TextCreatures => SpriteLibrary.BuiltIn.Where(n => n != "blocky").Select(n => new object[] { n });

    [Theory]
    [MemberData(nameof(TextCreatures))]
    public void ShippedSheetMatchesItsText(string name)
    {
        var text = File.ReadAllText(Path.Combine(Repo, "sprites", "text", name + ".txt"));
        var sheet = SpriteText.Parse(text);
        Assert.Equal(name, sheet.Name);
        Assert.True(sheet.Kind is not null && sheet.Cast.Count >= 3, "a built-in creature knows what it is and has a cast");
        var image = SpriteText.Pixels(sheet, SpriteText.Palette.Blocky);
        var shipped = SpriteAtlas.Named(name).Image();
        var why = $"{name}.png differs from sprites/text/{name}.txt; rebuild with LEDGELINGS_BUILD_CREATURES=1 swift test";
        Assert.True(shipped.Width == image.Width && shipped.Height == image.Height, why);
        Assert.True(shipped.Rgba.AsSpan().SequenceEqual(image.Rgba), why);
        var meta = SpriteAtlas.Named(name).Info;
        Assert.Equal(sheet.Kind, meta.Kind);
        Assert.Equal(sheet.Cast, meta.Cast);
        Assert.Equal(sheet.Colour?.Hex, meta.Colour);
    }
}

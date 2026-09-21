using System.Text.Json;
using System.Text.Json.Nodes;

namespace Ledgelings.Core.Tests;

/// <summary>A creature written as letters, the way a chat model can produce one.</summary>
public class SpriteTextTests
{
    /// <summary>A 32x32 grid with a 12-wide, 8-tall box standing on the floor row (26), eyes as k.</summary>
    static List<string> Grid(int width = 12, int height = 8, int eyeRows = 2)
    {
        var rows = Enumerable.Range(0, 32).Select(_ => new string('.', 32)).ToList();
        int left = 5 + (22 - width) / 2, top = 27 - height;
        for (int y = top; y < 27; y++)
        {
            var row = rows[y].ToCharArray();
            for (int x = left; x < left + width; x++)
            {
                var edge = y == top || y == 26 || x == left || x == left + width - 1;
                row[x] = edge ? 'o' : 'b';
            }
            rows[y] = new string(row);
        }
        for (int y = top + 2; y < top + 2 + eyeRows; y++)
        {
            var row = rows[y].ToCharArray();
            row[left + 4] = 'k'; row[left + 7] = 'k';
            rows[y] = new string(row);
        }
        return rows;
    }

    static string Text(string name = "boxy", IReadOnlyList<string>? poses = null, List<string>? grid = null)
    {
        poses ??= SpriteText.Poses;
        grid ??= Grid();
        var lines = new List<string> { "name: " + name };
        foreach (var pose in poses) { lines.Add("pose: " + pose); lines.AddRange(grid); }
        return string.Join("\n", lines) + "\n";
    }

    [Fact]
    public void ParsesNinePosesOfThirtyTwoByThirtyTwo()
    {
        var sheet = SpriteText.Parse(Text());
        Assert.Equal("boxy", sheet.Name);
        Assert.True(sheet.Poses.Keys.ToHashSet().SetEquals(SpriteText.Poses));
        var idle = sheet.Poses["idle"];
        Assert.True(idle.Length == 32 && idle.All(r => r.Length == 32));
        Assert.True(idle[26][10] == SpriteText.Ink.Outline && idle[22][12] == SpriteText.Ink.Body);
    }

    [Fact]
    public void SpacesDashesAndCommentsAreForgiven()
    {
        var grid = Grid();
        grid[0] = new string('-', 32);
        grid[1] = new string(' ', 32);
        var text = "# my creature\n" + Text(grid: grid).Replace("pose: idle\n", "pose: idle   \n\n");
        var sheet = SpriteText.Parse(text);
        Assert.True(sheet.Poses["idle"][0].All(i => i == SpriteText.Ink.Clear));
    }

    [Fact]
    public void AMissingPoseIsRefusedByName()
    {
        var fewer = SpriteText.Poses.Take(SpriteText.Poses.Count - 1).ToList();
        var error = Assert.Throws<SpriteText.ParseException>(() => SpriteText.Parse(Text(poses: fewer)));
        Assert.Contains("sleep-1", error.Message);
    }

    [Fact]
    public void ARowOfTheWrongLengthOrAStrangeLetterIsRefused()
    {
        var grid = Grid(); grid[20] = new string('.', 12) + "ob" + new string('.', 17);   // 31 with ink
        Assert.Throws<SpriteText.ParseException>(() => SpriteText.Parse(Text(grid: grid)));
        var shortGrid = Grid(); shortGrid[3] = "...";                                       // short but empty: fine
        _ = SpriteText.Parse(Text(grid: shortGrid));
        var odd = Grid(); odd[3] = new string('?', 32);
        Assert.Throws<SpriteText.ParseException>(() => SpriteText.Parse(Text(grid: odd)));
    }

    [Fact]
    public void InkOutsideTheBodyBoxOrFloatingAboveTheFloorIsRefused()
    {
        var outside = Grid(); outside[26] = "o" + new string('.', 31);
        Assert.Throws<SpriteText.ParseException>(() => SpriteText.Parse(Text(grid: outside)));
        var floating = Grid(); floating[26] = new string('.', 32);
        Assert.Throws<SpriteText.ParseException>(() => SpriteText.Parse(Text(grid: floating)));
    }

    [Fact]
    public void EyesCloseDownwardsForTheHalfAndClosedVariants()
    {
        var sheet = SpriteText.Parse(Text(grid: Grid(eyeRows: 4)));
        var open = sheet.Poses["idle"];
        var half = SpriteText.Variant(open, "half");
        var closed = SpriteText.Variant(open, "closed");
        var col = 5 + (22 - 12) / 2 + 4;
        List<int> EyeRows(SpriteText.Ink[][] g) => Enumerable.Range(0, 32).Where(y => g[y][col] == SpriteText.Ink.Eye).ToList();
        Assert.Equal(4, EyeRows(open).Count);
        Assert.True(EyeRows(half).SequenceEqual(EyeRows(open).TakeLast(2)), "the lid comes down, the bottom rows stay");
        Assert.Equal(new[] { EyeRows(open).Last() }, EyeRows(closed));
        Assert.True(half[EyeRows(open)[0]][col] == SpriteText.Ink.Body, "where the eye was is body again");
    }

    [Fact]
    public void PixelsLayOutPosesInColumnsAndVariantsInRowsWithThePalette()
    {
        var sheet = SpriteText.Parse(Text());
        var image = SpriteText.Pixels(sheet, SpriteText.Palette.Blocky);
        Assert.True(image.Width == 288 && image.Height == 96);
        byte[] Px(int x, int y) => image.Rgba[((y * 288 + x) * 4)..((y * 288 + x) * 4 + 4)];
        Assert.Equal(new byte[] { 0, 0, 0, 0 }, Px(0, 0));
        Assert.True(Px(10, 26).SequenceEqual(new byte[] { 0x3b, 0x1f, 0x0f, 255 }), "outline in the open row");
        Assert.True(Px(12, 22).SequenceEqual(new byte[] { 0xff, 0x8a, 0x3d, 255 }), "body");
        Assert.True(Px(32 + 10, 32 + 26).SequenceEqual(new byte[] { 0x3b, 0x1f, 0x0f, 255 }), "walk-0 sits in the second column, half row below");
    }

    [Fact]
    public void AtlasMetadataMatchesTheBuiltInSheetsShape()
    {
        var meta = SpriteText.Atlas("boxy");
        Assert.Equal(new[] { 32, 32 }, meta["cell"]!.Deserialize<int[]>());
        Assert.Equal(new[] { 5, 5, 22, 22 }, meta["contentBox"]!.Deserialize<int[]>());
        var frames = Assert.IsType<JsonObject>(meta["frames"]);
        Assert.Equal(27, frames.Count);
        Assert.Equal(new Dictionary<string, int> { ["x"] = 64, ["y"] = 32, ["w"] = 32, ["h"] = 32 },
                     frames["walk-1_half"]!.Deserialize<Dictionary<string, int>>());
        var animations = Assert.IsType<JsonObject>(meta["animations"]);
        Assert.Equal(new[] { "walk-0", "walk-1", "walk-2", "walk-3" }, animations["walk"]!["frames"]!.Deserialize<string[]>());
        Assert.Equal("#ff8a3d", meta["palette"]!["body"]!.GetValue<string>());
    }

    [Fact]
    public void PixelsReadBackAsTheSameLetters()
    {
        var sheet = SpriteText.Parse(Text());
        var image = SpriteText.Pixels(sheet, SpriteText.Palette.Blocky);
        var back = SpriteText.Describe(image, "idle", SpriteText.Palette.Blocky);
        Assert.Equal(Grid(), back);
    }

    [Fact]
    public void ASheetCanSayWhatItIsAndWhoItsCreaturesAre()
    {
        var text = "name: frog\nkind: a fat green frog with big eyes\ncharacter: Hopper: Bouncy and loud. Brags about jumping.\ncharacter: Mossy : Slow, damp, philosophical.\n"
            + Text(name: "frog").Replace("name: frog\n", "");
        var sheet = SpriteText.Parse(text);
        Assert.Equal("a fat green frog with big eyes", sheet.Kind);
        Assert.Equal(new[] { "Hopper", "Mossy" }, sheet.Cast.Select(c => c.Name));
        Assert.Equal("Slow, damp, philosophical.", sheet.Cast[1].Persona);
        var meta = SpriteText.Atlas("frog", kind: sheet.Kind, cast: sheet.Cast);
        Assert.Equal(sheet.Kind, meta["kind"]!.GetValue<string>());
        Assert.Equal("Hopper", meta["cast"]![0]!["name"]!.GetValue<string>());
    }

    [Fact]
    public void ASheetMayChooseItsOwnColour()
    {
        var text = "name: pig\ncolour: #F0A0B0\n" + Text(name: "pig").Replace("name: pig\n", "");
        var sheet = SpriteText.Parse(text);
        Assert.Equal(SpriteText.Tint.FromHex("#f0a0b0"), sheet.Colour);
        Assert.Equal("#f0a0b0", SpriteText.Atlas("pig", colour: sheet.Colour)["colour"]!.GetValue<string>());
        Assert.Null(SpriteText.Parse(Text()).Colour);
        Assert.Null(SpriteText.Atlas("boxy")["colour"]);
        Assert.Throws<SpriteText.ParseException>(() => SpriteText.Parse("name: pig\ncolour: pinkish\n" + Text(name: "pig")));
        Assert.Contains("colour:", SpriteText.Prompt(Array.Empty<string>()));
    }

    [Fact]
    public void ASheetWithoutKindOrCastStillParses()
    {
        var sheet = SpriteText.Parse(Text());
        Assert.True(sheet.Kind == null && sheet.Cast.Count == 0);
        Assert.Null(SpriteText.Atlas("boxy")["kind"]);
    }

    [Fact]
    public void ThePromptCarriesTheRulesAndTheExample()
    {
        var prompt = SpriteText.Prompt(new[] { "....", "..o." });
        Assert.True(prompt.Contains("pose: idle") && prompt.Contains("32") && prompt.Contains("..o."));
        Assert.Contains(SpriteText.DescribePlaceholder, prompt);
        Assert.True(prompt.Contains("kind:") && prompt.Contains("character:"));
        foreach (var pose in SpriteText.Poses) Assert.Contains(pose, prompt);
    }
}

using System.Runtime.CompilerServices;
using System.Text.RegularExpressions;
using Ledgelings.UI;

namespace Ledgelings.Tests;

/// <summary>The shared look (docs/DESIGN.md), as the Mac's DesignTests has it.</summary>
public class DesignTests
{
    [Fact]
    public void EveryGapIsOnTheScale() =>
        Assert.Equal(new[] { 4.0, 8, 12, 16, 24 }, new[] { Look.Xs, Look.S, Look.M, Look.L, Look.Xl });

    [Fact]
    public void NothingOnThePaperIsSmallerThanAHintButATile()
    {
        Assert.True(Pixel.Tile < Pixel.Hint);
        foreach (var size in new[] { Pixel.Title, Pixel.Label, Pixel.Body, Pixel.Reading, Pixel.Button, Pixel.SmallButton, Pixel.Value, Pixel.Typed, Pixel.Field, Pixel.SmallField })
            Assert.True(size >= Pixel.Hint);
    }

    [Fact]
    public void AKeysLineWrapsBetweenKeysOnly()
    {
        Assert.Equal("ENTER PASTE  CTRL+P PIN", Pixel.KeepingKeysWhole("ENTER PASTE  CTRL+P PIN"));
        Assert.Equal("No tools chosen: Settings.", Pixel.KeepingKeysWhole("No tools chosen: Settings."));
    }

    /// <summary>The pixel paper takes its sizes from <see cref="Pixel"/>: no font size of its own.</summary>
    [Fact]
    public void ThePaperUsesTheSharedFonts()
    {
        var ui = Path.Combine(Root(), "Ledgelings", "UI");
        foreach (var name in new[] { "ActionsSheet", "ChatWindow", "ClipPickerWindow", "ReminderNote", "ReadAloudSheet", "ToolsScreen", "TranslateSheet" })
        {
            var text = File.ReadAllText(Path.Combine(ui, name + ".cs"));
            var own = Regex.Matches(text, @"FontSize\s*=\s*\d").Count + Regex.Matches(text, @"Text\([^;\n]*?,\s*\d+(\.\d+)?\s*,\s*(FontWeights|softInk|faintInk|ink)").Count;
            Assert.True(own == 0, $"{name} sets {own} font size(s) of its own; use Pixel");
        }
    }

    private static string Root([CallerFilePath] string here = "") => Path.GetDirectoryName(Path.GetDirectoryName(here))!;
}

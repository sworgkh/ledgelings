namespace Ledgelings.UI;

// The shared look (docs/DESIGN.md), as on the Mac's Design.swift: the only place the pixel
// paper's font sizes and the spacing scale are defined. The settings window's styles are in
// Design.xaml, merged by every ordinary window.

/// <summary>The spacing scale: every gap and margin is one of these.</summary>
public static class Look
{
    public const double Xs = 4, S = 8, M = 12, L = 16, Xl = 24;
}

/// <summary>The pixel paper's font sizes, all monospaced and heavy as the creatures' lines are.
/// Nothing on the paper is smaller than <see cref="Hint"/> but a tile's caption, and nothing is
/// shrunk to fit: a keys line wraps to a second line instead.</summary>
public static class Pixel
{
    /// <summary>The sheet's name, top left, in capitals (bold): CLIPBOARD, TOOLS.</summary>
    public const double Title = 11;
    /// <summary>A label beside controls, a group's heading in a list: TO:, RECENT.</summary>
    public const double Label = 11;
    /// <summary>What is read: a row, a line, a message; a row's own name before it (heavy).</summary>
    public const double Body = 12;
    /// <summary>A conversation's lines, read at length (Chat).</summary>
    public const double Reading = 13;
    public const double Button = 13;
    public const double SmallButton = 11;
    /// <summary>The keys line, a row's detail, a hover tag.</summary>
    public const double Hint = 10;
    /// <summary>Inside a tile only, whose width is fixed: its second line and its key letter.</summary>
    public const double Tile = 9;
    /// <summary>A value between its arrows: the note's date and time.</summary>
    public const double Value = 15;
    /// <summary>What is typed into a text box (Translate, Read aloud, Chat).</summary>
    public const double Typed = 15;
    /// <summary>The big field of a picker or note.</summary>
    public const double Field = 18;
    /// <summary>A search field in a narrow drawer.</summary>
    public const double SmallField = 14;
    /// <summary>The room kept clear on the right of a sheet's bottom row for its folded corner.</summary>
    public const double CornerRoom = 48;

    /// <summary>Keys are two spaces apart, a key and its word one: a wrap falls between keys,
    /// never between "CTRL+P" and "PIN". A sentence (no double space) wraps as usual.</summary>
    public static string KeepingKeysWhole(string text) =>
        !text.Contains("  ") ? text : string.Join("  ", text.Split("  ").Select(part => part.Replace(' ', '\u00A0')));

    /// <summary>A sheet's keys line: at the hint size, wrapping to a second line rather than cut,
    /// and clear of the folded corner. Call it again after changing the words.</summary>
    public static void AsHints(System.Windows.Controls.TextBlock keys)
    {
        keys.Text = KeepingKeysWhole(keys.Text);
        keys.FontSize = Hint;
        keys.TextWrapping = System.Windows.TextWrapping.Wrap;
        keys.TextTrimming = System.Windows.TextTrimming.CharacterEllipsis;
        keys.MaxHeight = Math.Ceiling(Hint * 1.4 * 2);
        keys.Margin = new System.Windows.Thickness(keys.Margin.Left, keys.Margin.Top, CornerRoom, keys.Margin.Bottom);
    }
}

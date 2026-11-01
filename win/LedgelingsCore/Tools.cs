namespace Ledgelings.Core;

/// <summary>
/// The Tools screen (SPEC §7.15), the Mac's <c>Tools.swift</c>: every tool the creatures run for the owner on
/// one small sheet, a big pixel picture each, its name and its keys. A click, its number, or the arrows and
/// Enter start it; a tool that is switched off is greyed, its tag saying where to switch it on.
/// Windows has no screenshot tool yet, so its screen has no Screenshot, Full screen or Last rectangle tile.
/// Read aloud (0.63) is last, so every older tile keeps its number key.
/// </summary>
public static class Tools
{
    /// <summary>The codes saved are the Mac's: <c>translate</c>, <c>dictation</c>, <c>clipHistory</c>, <c>snippets</c>, <c>reminder</c>, <c>readAloud</c>.</summary>
    public enum Tool { Translate, Dictation, ClipHistory, Snippets, Reminder, ReadAloud }

    public static IReadOnlyList<Tool> All { get; } = Enum.GetValues<Tool>();

    public static string Code(this Tool tool) => tool switch
    {
        Tool.Translate => "translate",
        Tool.Dictation => "dictation",
        Tool.ClipHistory => "clipHistory",
        Tool.Snippets => "snippets",
        Tool.Reminder => "reminder",
        _ => "readAloud",
    };

    public static Tool? Named(string code) => All.Cast<Tool?>().FirstOrDefault(t => t!.Value.Code() == code);

    public static string Title(this Tool tool) => L10n.Tr(tool switch
    {
        Tool.Translate => "TRANSLATE",
        Tool.Dictation => "DICTATE",
        Tool.ClipHistory => "CLIPBOARD HISTORY",
        Tool.Snippets => "SNIPPETS",
        Tool.Reminder => "ADD A REMINDER",
        _ => "READ ALOUD",
    });

    /// <summary>What it does, in plain words, for its hover tag.</summary>
    public static string Does(this Tool tool) => L10n.Tr(tool switch
    {
        Tool.Translate => "Type to translate",
        Tool.Dictation => "Speak, and the words land on the clipboard",
        Tool.ClipHistory => "Your recent copies, to paste again",
        Tool.Snippets => "The snippets, to paste",
        Tool.Reminder => "A reminder, thrown at you by paper plane",
        _ => "Paste text and hear it read",
    });

    /// <summary>Where it is switched on: its settings page.</summary>
    public static SettingsPage Page(this Tool tool) => tool switch
    {
        Tool.Translate => SettingsPage.Translate,
        Tool.Dictation => SettingsPage.Dictation,
        Tool.ClipHistory or Tool.Snippets => SettingsPage.Clipboard,
        Tool.Reminder => SettingsPage.Reminders,
        _ => SettingsPage.ReadAloud,
    };

    /// <summary>The tag: what it does and its keys, <c>1 · Ctrl+Alt+T</c>; switched off, where to switch it on.</summary>
    public static string Tooltip(this Tool tool, int number, string? shortcut, bool on)
    {
        if (!on) return L10n.Tr("Off: switch it on in Settings › Tools › %@ (%d)", tool.Page().Title(), number);
        return shortcut is null ? L10n.Tr("%@ (%d)", tool.Does(), number) : L10n.Tr("%@ (%d · %@)", tool.Does(), number, shortcut);
    }

    /// <summary>11×11, <c>#</c> ink, <c>.</c> paper, drawn like the game; the Mac's pictures.</summary>
    public static IReadOnlyList<string> Icon(this Tool tool) => tool switch
    {
        Tool.Translate => Translate.Button.Translate.Icon(),
        Tool.Dictation => new[] { "...###.....", "..#...#....", "..#.#.#....", "..#...#....", "..#.#.#....", "#.#...#.#..", "#..###..#..", ".#.....#...", "..#####....", "....#......", "..#####...." },
        Tool.ClipHistory => new[] { "...###.....", "####.####..", "#.......#..", "#.#####.#..", "#.......#..", "#.###...#..", "#.......#..", "#.#####.#..", "#.......#..", "#########..", "..........." },
        Tool.Snippets => new[] { "#########..", "#.......##.", "#.#####.#.#", "#.......###", "#.#####...#", "#.........#", "#.###.....#", "#.........#", "#.#####...#", "#.........#", "###########" },
        Tool.ReadAloud => ReadAloud.Speaker,
        _ => new[] { "..........#", "........##.", "......##.#.", "....##..#..", "..##...#...", "##....#....", "..##.#.....", "....##.....", "....#.#....", "....#..#...", "....#......" },
    };

    /// <summary>The Tools screen itself, on the Creature Actions sheet: a wrench, as in the settings sidebar.</summary>
    public static readonly IReadOnlyList<string> SheetIcon = new[] { "......###..", ".....#..#..", "....#..#...", "...#.##....", "..#.#......", ".#.#.......", "#.#........", "##.........", "...........", "...........", "..........." };

    /// <summary>The tools shown, in order, from the saved codes: unknown ones (a Mac-only screenshot tile) dropped, each once.</summary>
    public static IReadOnlyList<Tool> Shown(IEnumerable<string> saved) =>
        saved.Select(Named).OfType<Tool>().Distinct().ToList();

    /// <summary>Every tool, in this order: what the screen shows until the owner changes it.</summary>
    public static IReadOnlyList<string> DefaultShown { get; } = All.Select(t => t.Code()).ToList();

    /// <summary>The tools there were before the screen remembered which it knew (0.62): Windows' first five.</summary>
    public static readonly IReadOnlyList<string> FirstKnown = new[] { "translate", "dictation", "clipHistory", "snippets", "reminder" };

    /// <summary>The saved list with every tool added since it was saved at its end: a list the owner arranged
    /// keeps its order and its number keys, a tool they switched off stays off, and a new tool still shows up
    /// once. <paramref name="known"/>: the tools there were when the list was saved (null: <see cref="FirstKnown"/>).</summary>
    public static IReadOnlyList<string> WithNew(IEnumerable<string> saved, IEnumerable<string>? known)
    {
        var knew = (known ?? FirstKnown).ToHashSet();
        var shown = Shown(saved).Select(t => t.Code()).ToList();
        return shown.Concat(All.Select(t => t.Code()).Where(c => !knew.Contains(c) && !shown.Contains(c))).ToList();
    }

    public enum Arrow { Left, Right, Up, Down }

    public const int Columns = 4;

    /// <summary>The tile <paramref name="from"/> moves to with an arrow, in a grid <paramref name="columns"/> wide; at an edge it stays.</summary>
    public static int Step(int from, Arrow key, int count, int columns = Columns)
    {
        if (count <= 0) return 0;
        var to = key switch
        {
            Arrow.Left => from - 1,
            Arrow.Right => from + 1,
            Arrow.Up => from - columns,
            _ => from + columns,
        };
        return to >= 0 && to < count ? to : from;
    }
}

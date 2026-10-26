using System.Globalization;
using System.Text;

namespace Ledgelings.Core;

/// <summary>One page of the settings window, the Mac's <c>SettingsPage</c>. The sidebar lists them by
/// <see cref="SettingsPages.Group"/>, in this order. Windows has no Screenshots page yet.</summary>
public enum SettingsPage
{
    Creatures, Actions, Sprites, Beds, Flowers, Calendar,
    Chases, Play, BallGames,
    Talk, Voice, Bonds, Relationships,
    Tools, Reminders, Clipboard, Dictation, Translate,
    Costs, Chats,
}

/// <summary>A heading in the settings sidebar, over its pages.</summary>
public enum SettingsGroup { CreaturesAndWorld, Games, TalkAndFriends, Tools, MoneyAndHistory }

public static class SettingsPages
{
    public static IReadOnlyList<SettingsPage> All { get; } = Enum.GetValues<SettingsPage>();
    public static IReadOnlyList<SettingsGroup> Groups { get; } = Enum.GetValues<SettingsGroup>();

    /// <summary>The page's name in English, as the sidebar writes it through <c>Tr</c>.</summary>
    public static string EnglishTitle(this SettingsPage page) => page switch
    {
        SettingsPage.BallGames => "Ball games",
        SettingsPage.Tools => "Tools screen",
        _ => page.ToString(),
    };

    public static string Title(this SettingsPage page) => L10n.Tr(page.EnglishTitle());

    public static SettingsGroup Group(this SettingsPage page) => page switch
    {
        SettingsPage.Creatures or SettingsPage.Actions or SettingsPage.Sprites or SettingsPage.Beds or SettingsPage.Flowers or SettingsPage.Calendar => SettingsGroup.CreaturesAndWorld,
        SettingsPage.Chases or SettingsPage.Play or SettingsPage.BallGames => SettingsGroup.Games,
        SettingsPage.Talk or SettingsPage.Voice or SettingsPage.Bonds or SettingsPage.Relationships => SettingsGroup.TalkAndFriends,
        SettingsPage.Costs or SettingsPage.Chats => SettingsGroup.MoneyAndHistory,
        _ => SettingsGroup.Tools,
    };

    public static string Title(this SettingsGroup group) => L10n.Tr(group switch
    {
        SettingsGroup.CreaturesAndWorld => "Creatures & world",
        SettingsGroup.Games => "Games",
        SettingsGroup.TalkAndFriends => "Talk & friends",
        SettingsGroup.Tools => "Tools",
        _ => "Money & history",
    });

    public static IReadOnlyList<SettingsPage> Pages(this SettingsGroup group) => All.Where(p => p.Group() == group).ToList();

    /// <summary>The page <c>--settings &lt;name&gt;</c> opens: its own name in lower case (<c>ballgames</c>), or an
    /// old tab's. <c>productivity</c>, the old tools tab, opens Reminders.</summary>
    public static SettingsPage? Named(string name)
    {
        var lower = name.ToLowerInvariant();
        if (lower == "productivity") return SettingsPage.Reminders;
        if (lower == "toolsscreen") return SettingsPage.Tools;
        return All.Cast<SettingsPage?>().FirstOrDefault(p => p.ToString()!.ToLowerInvariant() == lower);
    }

    /// <summary>11×11, drawn like the game: square pixels, no curves. The Mac's sidebar pictures.</summary>
    public static IReadOnlyList<string> Icon(this SettingsGroup group) => group switch
    {
        SettingsGroup.CreaturesAndWorld => new[] { "...........", ".##.....##.", ".##.....##.", "...........", "....###....", "...#####...", "...#####...", "....###....", "...........", "...........", "..........." },
        SettingsGroup.Games => new[] { "...#####...", "..#.....#..", ".#..###..#.", ".#.#...#.#.", ".#.#...#.#.", ".#..###..#.", "..#.....#..", "...#####...", "...........", "...........", "..........." },
        SettingsGroup.TalkAndFriends => new[] { "#########..", "#.......#..", "#.##.##.#..", "#.......#..", "#########..", "..##.......", "..#........", "...........", "...........", "...........", "..........." },
        SettingsGroup.Tools => Core.Tools.SheetIcon,
        _ => new[] { "...#####...", "..#.....#..", ".#...#...#.", ".#..###..#.", ".#...#...#.", ".#..###..#.", "..#.....#..", "...#####...", "...........", "...........", "..........." },
    };

    public static readonly IReadOnlyList<string> SearchIcon = new[] { "..####.....", ".#....#....", "#......#...", "#......#...", "#......#...", ".#....#....", "..####.#...", ".......#...", "........#..", ".........#.", "..........." };
    public static readonly IReadOnlyList<string> ClearIcon = new[] { "#.......#..", ".#.....#...", "..#...#....", "...#.#.....", "....#......", "...#.#.....", "..#...#....", ".#.....#...", "#.......#..", "...........", "..........." };
}

/// <summary>
/// The settings search, the Mac's <c>SettingsIndex.search</c>. The Mac keeps a hand list of sections; the
/// Windows window reads its own: every group box of every page, with its heading, the labels of its
/// controls and its footer, in English as the markup writes them. Looked up through <c>Tr</c> when
/// searched, so a search in Russian finds the Russian words and one in English still finds the English.
/// </summary>
public static class SettingsSearch
{
    public sealed record Section(SettingsPage Page, string Title, IReadOnlyList<string> Labels, string Footer = "");

    /// <summary>One place found: the words that matched (a control's label, or the heading), its page and section.</summary>
    public sealed record Hit(SettingsPage Page, string Section, string Text);

    /// <summary>The sections whose words hold every word of <paramref name="query"/>, best first: a label or
    /// heading holding the whole query before a footer that only mentions it. Case and accents do not matter.</summary>
    public static IReadOnlyList<Hit> Search(string query, IReadOnlyList<Section> sections)
    {
        var words = Fold(query).Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        if (words.Length == 0) return Array.Empty<Hit>();
        var whole = string.Join(" ", words);
        var ranked = new List<(int Score, int Order, Hit Hit)>();
        for (var order = 0; order < sections.Count; order++)
        {
            var section = sections[order];
            var title = section.Title.Length == 0 ? "" : L10n.Tr(section.Title);
            var labels = section.Labels.Select(l => L10n.Tr(l)).ToList();
            var footer = section.Footer.Length == 0 ? "" : L10n.Tr(section.Footer);
            var everything = Fold(string.Join(" ", new[] { section.Page.Title(), title, footer, section.Title, section.Footer }.Concat(labels).Concat(section.Labels)));
            if (!words.All(everything.Contains)) continue;
            string? label = null;
            for (var i = 0; i < labels.Count && label is null; i++)
                if (Fold(labels[i]).Contains(whole) || Fold(section.Labels[i]).Contains(whole)) label = labels[i];
            var score = label is not null ? 0 : Fold(title).Contains(whole) ? 1 : Fold(section.Page.Title()).Contains(whole) ? 2 : 3;
            ranked.Add((score, order, new Hit(section.Page, section.Title, label ?? (title.Length == 0 ? section.Page.Title() : title))));
        }
        return ranked.OrderBy(r => r.Score).ThenBy(r => r.Order).Select(r => r.Hit).ToList();
    }

    /// <summary>Lower case without accents: "Café" and "cafe" are one word; ё is е, as a Russian reader types it.</summary>
    public static string Fold(string text)
    {
        var decomposed = text.ToLowerInvariant().Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(decomposed.Length);
        foreach (var c in decomposed)
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) sb.Append(c);
        return sb.ToString().Normalize(NormalizationForm.FormC);
    }
}

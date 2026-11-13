using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The monitors to choose from for <c>homeScreen</c>, as the tray menu, the Actions sheet and the
/// Creatures tab list them: every attached one, left to right, by name, and the chosen one too while it is
/// unplugged. The Mac's ScreenChoice.</summary>
public static class ScreenChoice
{
    /// <summary>Every attached monitor, left to right (top first where two stand in one column).</summary>
    public static List<HomeScreen.Monitor> Attached() =>
        Desktop.Monitors().OrderBy(m => m.Left).ThenBy(m => m.Top).Select(m => m.Home).ToList();

    /// <summary>One monitor, nothing to choose: the choice is only offered with two or more.</summary>
    public static bool IsOffered => Desktop.Monitors().Count > 1;

    /// <summary>The chosen monitor is unplugged: they live on every monitor until it is back.</summary>
    public static bool IsAway(AppSettings settings) => HomeScreen.IsAway(settings.HomeScreenId, Attached());

    /// <summary>The choice in words: "All screens", the monitor's name, or its name and that it is unplugged.</summary>
    public static string Current(AppSettings settings)
    {
        if (settings.HomeScreenId == HomeScreen.All) return L10n.Tr("All screens");
        var name = Attached().FirstOrDefault(m => m.Id == settings.HomeScreenId)?.Name ?? settings.HomeScreenName;
        return IsAway(settings) ? L10n.Tr("%@ (unplugged: all screens till it is back)", name) : name;
    }
}

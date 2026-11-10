namespace Ledgelings.Core;

/// <summary>The Stop button (SPEC §7.17): while a surf, a dive or a game runs, a plate in the top-right corner of the
/// monitor it runs on, a stop sign and the words "Stop · Ctrl + Alt + Q". It is the only part of the overlay a click
/// lands on; the click stops the activity, as the shortcut and the tray do. What it says and where it sits, worked
/// out here; the colony draws it. The Mac's <c>StopButton</c>.</summary>
public static class StopButton
{
    /// <summary>The words on it: the key written out, so nobody has to guess. Only "Stop" while the shortcut is off.</summary>
    public static string Label(string? spokenShortcut) =>
        string.IsNullOrEmpty(spokenShortcut) ? L10n.Tr("Stop") : L10n.Tr("Stop · %@", spokenShortcut);

    /// <summary>The tag hovering shows under it.</summary>
    public static string Tag(string? spokenShortcut) =>
        string.IsNullOrEmpty(spokenShortcut) ? L10n.Tr("Stop the activity") : L10n.Tr("Stop the activity (%@)", spokenShortcut);

    /// <summary>Points from the screen's right edge and from under the top's reserved band.</summary>
    public const double Margin = 12;

    /// <summary>Where a button of <paramref name="width"/> × <paramref name="height"/> sits on a monitor whose frame is
    /// <paramref name="screen"/> (y up): its top-right corner, <paramref name="topInset"/> below the top (a taskbar
    /// along the top), and below anything in <paramref name="avoiding"/> it would cover there (the surfing score board).</summary>
    public static Rect Frame(double width, double height, Rect screen, double topInset, IReadOnlyList<Rect>? avoiding = null)
    {
        var place = new Rect(screen.MaxX - Margin - width, screen.MaxY - topInset - Margin - height, width, height);
        var those = avoiding ?? Array.Empty<Rect>();
        // Each in the way pushes it down below itself; checked again, as moving down may meet another.
        for (int n = 0; n < those.Count; n++)
        {
            if (those.FirstOrDefault(r => r.Intersects(place)) is not { Width: > 0 } hit) break;
            place = place with { Y = hit.MinY - Margin - height };
        }
        return place;
    }

    /// <summary>The stop sign, in the game's style: an eight-sided red plate made of steps (no curves), a 1-pixel dark
    /// outline, a light line top-left, a shade line bottom-right, a white bar across. <c>o</c> outline, <c>l</c> light,
    /// <c>r</c> red, <c>s</c> shade, <c>w</c> white, <c>.</c> nothing. The same rows as the Mac's.</summary>
    public static readonly string[] Icon =
    {
        "...oooooo...",
        "..olllllro..",
        ".olrrrrrrso.",
        "olrrrrrrrrso",
        "olrrrrrrrrso",
        "olwwwwwwwwso",
        "olwwwwwwwwso",
        "olrrrrrrrrso",
        "olrrrrrrrrso",
        ".orrrrrrrso.",
        "..osssssso..",
        "...oooooo...",
    };
}

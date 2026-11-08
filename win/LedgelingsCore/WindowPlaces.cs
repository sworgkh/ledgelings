namespace Ledgelings.Core;

/// <summary>
/// Where the app's windows reopen after the owner moved them, the Mac's <c>WindowPlaces</c>. On
/// Windows a place is the window's top-left in screen pixels, counted as Windows does (y down
/// from the top of the primary monitor), saved per window under its <see cref="Key"/>.
/// </summary>
public static class WindowPlaces
{
    /// <summary>Every window or sheet the app opens. The last five never move: the creatures' layer
    /// over the screen, the screenshot tool's frozen screens and toolbar, and the clipboard's passing
    /// note and flying paper.</summary>
    public enum Window
    {
        Settings, Relationships, Snippets, Actions, Reminder,
        Tools, Translate, ReadAloud, ClipPicker,
        Overlay, ShotScreens, ShotToolbar, ClipToast, ClipGhost,
    }

    public static IReadOnlyList<Window> All { get; } = Enum.GetValues<Window>();

    /// <summary>Dragged by its title bar, its background or its paper.</summary>
    public static bool Movable(this Window window) =>
        window is not (Window.Overlay or Window.ShotScreens or Window.ShotToolbar or Window.ClipToast or Window.ClipGhost);

    /// <summary>The Mac's name for it, so both keep the same keys: <c>readAloud</c>, <c>clipPicker</c>.</summary>
    public static string Key(this Window window) { var s = window.ToString(); return char.ToLowerInvariant(s[0]) + s[1..]; }

    /// <summary>How much of the top edge must land on a screen for a saved place to count.</summary>
    public const double GripWidth = 40, GripHeight = 24;

    /// <summary>The frame for a window <paramref name="width"/> × <paramref name="height"/> whose top-left was saved at
    /// (<paramref name="left"/>, <paramref name="top"/>), kept inside the screen its title strip lands on; null when
    /// that strip is on no screen any more, so the window opens where it always did. Screens are y down.</summary>
    public static Rect? Frame(double left, double top, double width, double height, IReadOnlyList<Rect> screens)
    {
        var strip = new Rect(left, top, Math.Min(width, GripWidth * 3), GripHeight);
        double cx = strip.X + strip.Width / 2, cy = strip.Y + strip.Height / 2;
        foreach (var s in screens)
        {
            var overlap = Math.Min(s.MaxX, strip.MaxX) - Math.Max(s.MinX, strip.MinX);
            if (overlap >= Math.Min(GripWidth, strip.Width) && cx >= s.MinX && cx < s.MaxX && cy >= s.MinY && cy < s.MaxY)
                return Clamped(new Rect(left, top, width, height), s);
        }
        return null;
    }

    /// <summary><paramref name="r"/> moved, not shrunk, so as much of it as fits is inside <paramref name="screen"/>, its top first.</summary>
    public static Rect Clamped(Rect r, Rect screen)
    {
        var x = Math.Min(Math.Max(r.X, screen.MinX), Math.Max(screen.MinX, screen.MaxX - r.Width));
        var y = Math.Max(Math.Min(r.Y, screen.MaxY - r.Height), screen.MinY);
        return new Rect(x, y, r.Width, r.Height);
    }

    /// <summary>A paper drawn inside a window <paramref name="roomWidth"/> × <paramref name="roomHeight"/> (top-left
    /// origin, y down) kept wholly inside it, on whole points.</summary>
    public static Rect Paper(Rect paper, double roomWidth, double roomHeight) => new(
        Math.Round(Math.Min(Math.Max(paper.X, 0), Math.Max(0, roomWidth - paper.Width))),
        Math.Round(Math.Min(Math.Max(paper.Y, 0), Math.Max(0, roomHeight - paper.Height))),
        paper.Width, paper.Height);
}

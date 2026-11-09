namespace Ledgelings.Core;

/// <summary>
/// When "Stop when I use the computer" stops a running activity: a key press or a click that came after it
/// started (and after a short grace, so the click or key that started it does not stop it), unless the click
/// was on a creature. Moving the mouse alone never counts. The Mac's <c>UsePolicy.swift</c>.
/// </summary>
public static class UsePolicy
{
    /// <summary>Seconds after an activity starts in which nothing stops it: the click on the menu, the shortcut's own key coming up.</summary>
    public const double Grace = 0.6;
    /// <summary>A click this close to one the creatures took is that same click.</summary>
    public const double SameClick = 0.25;

    /// <summary><paramref name="runningFor"/>: seconds since the activity started; the others are seconds since the
    /// last key press, the last click anywhere, the last click on a creature.</summary>
    public static bool Stops(double runningFor, double sinceKey, double sinceClick, double sinceOwnClick)
    {
        if (runningFor <= Grace) return false;
        var window = runningFor - Grace;
        if (sinceKey < window) return true;
        if (sinceClick < window && Math.Abs(sinceClick - sinceOwnClick) > SameClick) return true;
        return false;
    }
}

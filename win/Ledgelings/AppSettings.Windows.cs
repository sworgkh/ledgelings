using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Remember where windows were moved (SPEC §12): a dragged window or sheet reopens where it was let go.</summary>
public sealed partial class AppSettings
{
    private bool rememberWindowPlaces;
    private Dictionary<string, List<double>> windowPlaces = new();

    private void LoadWindows()
    {
        // On: the owner asked for windows that stay where they were put.
        rememberWindowPlaces = store.Get<bool?>("rememberWindowPlaces") ?? true;
        windowPlaces = (store.Get<Dictionary<string, List<double>>>("windowPlaces") ?? new())
            .Where(p => p.Value is { Count: 2 }).ToDictionary(p => p.Key, p => p.Value);
    }

    public bool RememberWindowPlaces { get => rememberWindowPlaces; set => Put(ref rememberWindowPlaces, value, "rememberWindowPlaces"); }

    /// <summary>Each moved window's top-left in screen pixels (y down), by <see cref="WindowPlaces.Key"/>.</summary>
    public IReadOnlyDictionary<string, List<double>> WindowPlaceList => windowPlaces;

    /// <summary>Where <paramref name="window"/> was last moved to, when that is remembered.</summary>
    public (double Left, double Top)? PlaceOf(WindowPlaces.Window window) =>
        rememberWindowPlaces && window.Movable() && windowPlaces.TryGetValue(window.Key(), out var p) && p.Count == 2 ? (p[0], p[1]) : null;

    /// <summary>The owner moved <paramref name="window"/>: its top-left now, kept for next time.</summary>
    public void Moved(WindowPlaces.Window window, double left, double top)
    {
        if (!rememberWindowPlaces || !window.Movable()) return;
        windowPlaces[window.Key()] = new List<double> { Math.Round(left), Math.Round(top) };
        store.Set("windowPlaces", windowPlaces);
    }
}

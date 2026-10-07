namespace Ledgelings;

/// <summary>Revenge (SPEC §4.7.3): hunted far too often, a creature grabs the cursor and shames the user until shaken off.</summary>
public sealed partial class AppSettings
{
    /// <summary>Chases or pick-ups of one creature, inside the window, before it grabs the cursor.</summary>
    public const int RevengeAfterMin = 3, RevengeAfterMax = 50;
    /// <summary>Seconds those chases must fall within.</summary>
    public const double RevengeWindowMin = 30, RevengeWindowMax = 600;
    /// <summary>Longest a creature may hold the cursor, in seconds; then it lets go by itself.</summary>
    public const double RevengeHoldMin = 3, RevengeHoldMax = 30;
    /// <summary>Quick back-and-forth strokes it takes to shake a creature off.</summary>
    public const int RevengeShakesMin = 2, RevengeShakesMax = 16;
    /// <summary>Minutes after one grab before any creature grabs again.</summary>
    public const double RevengeCooldownMin = 1, RevengeCooldownMax = 120;

    private bool revengeEnabled;
    private int revengeAfter, revengeShakes;
    private double revengeWindowSeconds, revengeHoldSeconds, revengeCooldownMinutes;

    private void LoadRevenge()
    {
        // On: the owner asked for it. Ten chases in two minutes is well past the fifth-in-a-row
        // complaint, so it only answers real abuse; ten seconds at most, six quick strokes to break
        // free, then ten minutes' peace. The Mac's defaults.
        revengeEnabled = store.Get<bool?>("revengeEnabled") ?? true;
        revengeAfter = Math.Clamp(store.Get<int?>("revengeAfter") ?? 10, RevengeAfterMin, RevengeAfterMax);
        revengeWindowSeconds = Math.Clamp(store.Get<double?>("revengeWindowSeconds") ?? 120, RevengeWindowMin, RevengeWindowMax);
        revengeHoldSeconds = Math.Clamp(store.Get<double?>("revengeHoldSeconds") ?? 10, RevengeHoldMin, RevengeHoldMax);
        revengeShakes = Math.Clamp(store.Get<int?>("revengeShakes") ?? 6, RevengeShakesMin, RevengeShakesMax);
        revengeCooldownMinutes = Math.Clamp(store.Get<double?>("revengeCooldownMinutes") ?? 10, RevengeCooldownMin, RevengeCooldownMax);
    }

    public bool RevengeEnabled { get => revengeEnabled; set => Put(ref revengeEnabled, value, "revengeEnabled"); }
    public int RevengeAfter { get => revengeAfter; set => Put(ref revengeAfter, Math.Clamp(value, RevengeAfterMin, RevengeAfterMax), "revengeAfter"); }
    public double RevengeWindowSeconds { get => revengeWindowSeconds; set => Put(ref revengeWindowSeconds, Math.Clamp(value, RevengeWindowMin, RevengeWindowMax), "revengeWindowSeconds"); }
    public double RevengeHoldSeconds { get => revengeHoldSeconds; set => Put(ref revengeHoldSeconds, Math.Clamp(value, RevengeHoldMin, RevengeHoldMax), "revengeHoldSeconds"); }
    public int RevengeShakes { get => revengeShakes; set => Put(ref revengeShakes, Math.Clamp(value, RevengeShakesMin, RevengeShakesMax), "revengeShakes"); }
    public double RevengeCooldownMinutes { get => revengeCooldownMinutes; set => Put(ref revengeCooldownMinutes, Math.Clamp(value, RevengeCooldownMin, RevengeCooldownMax), "revengeCooldownMinutes"); }
}

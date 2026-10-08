namespace Ledgelings;

/// <summary>Revenge (SPEC §4.7.3): hunted far too often, a creature grabs the cursor and shames the user until shaken off.</summary>
public sealed partial class AppSettings
{
    /// <summary>Chases or pick-ups of one creature, inside the window, before it grabs the cursor.</summary>
    public const int RevengeAfterMin = 3, RevengeAfterMax = 50;
    /// <summary>Seconds those chases must fall within.</summary>
    public const double RevengeWindowMin = 30, RevengeWindowMax = 600;
    /// <summary>Longest a creature may hold the cursor, in seconds; then it lets go by itself. 0: until shaken off.</summary>
    public const double RevengeHoldMin = 0, RevengeHoldMax = 30;
    /// <summary>Seconds between tellings-off while it holds on. 0: only the first.</summary>
    public const double RevengeTauntMin = 0, RevengeTauntMax = 60;
    /// <summary>Points a stroke must travel one way before turning back counts as a shake.</summary>
    public const double RevengeShakeStrokeMin = 10, RevengeShakeStrokeMax = 60;
    /// <summary>Seconds the shakes must fall within.</summary>
    public const double RevengeShakeWindowMin = 1, RevengeShakeWindowMax = 4;
    /// <summary>Quick back-and-forth strokes it takes to shake a creature off.</summary>
    public const int RevengeShakesMin = 2, RevengeShakesMax = 16;
    /// <summary>Minutes after one grab before any creature grabs again.</summary>
    public const double RevengeCooldownMin = 1, RevengeCooldownMax = 120;

    private bool revengeEnabled, revengePinsCursor;
    private int revengeAfter, revengeShakes;
    private double revengeWindowSeconds, revengeHoldSeconds, revengeCooldownMinutes;
    private double revengeTauntSeconds, revengeShakeStroke, revengeShakeWindowSeconds;

    private void LoadRevenge()
    {
        // On: the owner asked for it. Ten chases in two minutes is well past the fifth-in-a-row
        // complaint, so it only answers real abuse; then ten minutes' peace. It rides along on the
        // pointer rather than holding it still, stays until shaken off and tells the user off again
        // every 15 s; four strokes of 20 points within two seconds shake it off. The Mac's defaults.
        revengeEnabled = store.Get<bool?>("revengeEnabled") ?? true;
        revengeAfter = Math.Clamp(store.Get<int?>("revengeAfter") ?? 10, RevengeAfterMin, RevengeAfterMax);
        revengeWindowSeconds = Math.Clamp(store.Get<double?>("revengeWindowSeconds") ?? 120, RevengeWindowMin, RevengeWindowMax);
        revengeHoldSeconds = Math.Clamp(store.Get<double?>("revengeHoldSeconds") ?? 0, RevengeHoldMin, RevengeHoldMax);
        revengeShakes = Math.Clamp(store.Get<int?>("revengeShakes") ?? 4, RevengeShakesMin, RevengeShakesMax);
        revengeCooldownMinutes = Math.Clamp(store.Get<double?>("revengeCooldownMinutes") ?? 10, RevengeCooldownMin, RevengeCooldownMax);
        revengeTauntSeconds = Math.Clamp(store.Get<double?>("revengeTauntSeconds") ?? 15, RevengeTauntMin, RevengeTauntMax);
        revengeShakeStroke = Math.Clamp(store.Get<double?>("revengeShakeStroke") ?? 20, RevengeShakeStrokeMin, RevengeShakeStrokeMax);
        revengeShakeWindowSeconds = Math.Clamp(store.Get<double?>("revengeShakeWindowSeconds") ?? 2, RevengeShakeWindowMin, RevengeShakeWindowMax);
        revengePinsCursor = store.Get<bool?>("revengePinsCursor") ?? false;
    }

    public bool RevengeEnabled { get => revengeEnabled; set => Put(ref revengeEnabled, value, "revengeEnabled"); }
    public int RevengeAfter { get => revengeAfter; set => Put(ref revengeAfter, Math.Clamp(value, RevengeAfterMin, RevengeAfterMax), "revengeAfter"); }
    public double RevengeWindowSeconds { get => revengeWindowSeconds; set => Put(ref revengeWindowSeconds, Math.Clamp(value, RevengeWindowMin, RevengeWindowMax), "revengeWindowSeconds"); }
    public double RevengeHoldSeconds { get => revengeHoldSeconds; set => Put(ref revengeHoldSeconds, Math.Clamp(value, RevengeHoldMin, RevengeHoldMax), "revengeHoldSeconds"); }
    public int RevengeShakes { get => revengeShakes; set => Put(ref revengeShakes, Math.Clamp(value, RevengeShakesMin, RevengeShakesMax), "revengeShakes"); }
    public double RevengeCooldownMinutes { get => revengeCooldownMinutes; set => Put(ref revengeCooldownMinutes, Math.Clamp(value, RevengeCooldownMin, RevengeCooldownMax), "revengeCooldownMinutes"); }
    public double RevengeTauntSeconds { get => revengeTauntSeconds; set => Put(ref revengeTauntSeconds, Math.Clamp(value, RevengeTauntMin, RevengeTauntMax), "revengeTauntSeconds"); }
    public double RevengeShakeStroke { get => revengeShakeStroke; set => Put(ref revengeShakeStroke, Math.Clamp(value, RevengeShakeStrokeMin, RevengeShakeStrokeMax), "revengeShakeStroke"); }
    public double RevengeShakeWindowSeconds { get => revengeShakeWindowSeconds; set => Put(ref revengeShakeWindowSeconds, Math.Clamp(value, RevengeShakeWindowMin, RevengeShakeWindowMax), "revengeShakeWindowSeconds"); }
    /// <summary>Off, the creature rides along on the pointer; on, it holds the pointer where it was.</summary>
    public bool RevengePinsCursor { get => revengePinsCursor; set => Put(ref revengePinsCursor, value, "revengePinsCursor"); }
}

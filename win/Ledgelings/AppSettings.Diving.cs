using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Scuba diving (SPEC §7.17), started by hand only, and Stop activity: the Mac's keys and defaults.</summary>
public sealed partial class AppSettings
{
    public const double DiveWaterShareMin = 0.15, DiveWaterShareMax = 0.6;
    public const double DiveWaterOpacityMin = 0.1, DiveWaterOpacityMax = 0.7;
    public const double DiveMinutesMin = 0.5, DiveMinutesMax = 15;
    public const int DiveDiversMin = 1, DiveDiversMax = 8;
    public const int DiveSeaLifeMin = 3, DiveSeaLifeMax = 40;

    private bool stopActivityShortcutEnabled, stopOnUse, diveAllScreens, diveTalk;
    private Shortcut stopActivityShortcut;
    private string stopActivityShortcutProblem = "";
    private double diveWaterShare, diveWaterOpacity, diveMinutes;
    private int diveDivers, diveSeaLife;

    private void LoadDiving()
    {
        stopActivityShortcutEnabled = store.Get<bool?>("stopActivityShortcutEnabled") ?? true;
        stopActivityShortcut = Shortcut.Saved(store.Get<int?>("stopActivityShortcutKeyCode"), store.Get<int?>("stopActivityShortcutModifiers"), Shortcut.StopActivity);
        stopOnUse = store.Get<bool?>("stopOnUse") ?? true;
        // A third of the screen, as the owner asked; light enough to read the apps through.
        diveWaterShare = Math.Clamp(store.Get<double?>("diveWaterShare") ?? 1.0 / 3, DiveWaterShareMin, DiveWaterShareMax);
        diveWaterOpacity = Math.Clamp(store.Get<double?>("diveWaterOpacity") ?? 0.3, DiveWaterOpacityMin, DiveWaterOpacityMax);
        // Three minutes: long enough to see everything once, short enough to watch to the end.
        diveMinutes = Math.Clamp(store.Get<double?>("diveMinutes") ?? 3, DiveMinutesMin, DiveMinutesMax);
        diveDivers = Math.Clamp(store.Get<int?>("diveDivers") ?? 3, DiveDiversMin, DiveDiversMax);
        // Twelve fish: three small schools, and everyone else besides.
        diveSeaLife = Math.Clamp(store.Get<int?>("diveSeaLife") ?? 12, DiveSeaLifeMin, DiveSeaLifeMax);
        diveAllScreens = store.Get<bool?>("diveAllScreens") ?? false;
        diveTalk = store.Get<bool?>("diveTalk") ?? true;
    }

    /// <summary>Stop activity (Ctrl+Alt+Esc): from any app, ends a dive, a surf or a game at once.</summary>
    public bool StopActivityShortcutEnabled { get => stopActivityShortcutEnabled; set => Put(ref stopActivityShortcutEnabled, value, "stopActivityShortcutEnabled"); }
    public Shortcut StopActivityShortcut { get => stopActivityShortcut; set => PutShortcut(ref stopActivityShortcut, value, "stopActivityShortcut"); }
    /// <summary>Why the Stop activity shortcut does nothing, when Windows refused it. Not saved.</summary>
    public string StopActivityShortcutProblem
    {
        get => stopActivityShortcutProblem;
        set { if (stopActivityShortcutProblem == value) return; stopActivityShortcutProblem = value; Raise(nameof(StopActivityShortcutProblem)); }
    }
    /// <summary>A real key press, or a click anywhere but on a creature, stops a running activity.</summary>
    public bool StopOnUse { get => stopOnUse; set => Put(ref stopOnUse, value, "stopOnUse"); }
    /// <summary>How much of the screen the water covers, from the bottom.</summary>
    public double DiveWaterShare { get => diveWaterShare; set { if (Put(ref diveWaterShare, Math.Clamp(value, DiveWaterShareMin, DiveWaterShareMax), "diveWaterShare")) Raise(nameof(DiveWaterPercent)); } }
    /// <summary>How see-through the water is: 0 is clear glass.</summary>
    public double DiveWaterOpacity { get => diveWaterOpacity; set { if (Put(ref diveWaterOpacity, Math.Clamp(value, DiveWaterOpacityMin, DiveWaterOpacityMax), "diveWaterOpacity")) Raise(nameof(DiveWaterOpacityPercent)); } }
    public double DiveMinutes { get => diveMinutes; set => Put(ref diveMinutes, Math.Clamp(value, DiveMinutesMin, DiveMinutesMax), "diveMinutes"); }
    public int DiveDivers { get => diveDivers; set => Put(ref diveDivers, Math.Clamp(value, DiveDiversMin, DiveDiversMax), "diveDivers"); }
    /// <summary>Fish, in all; the jellyfish, crab, turtle and octopus always come.</summary>
    public int DiveSeaLife { get => diveSeaLife; set => Put(ref diveSeaLife, Math.Clamp(value, DiveSeaLifeMin, DiveSeaLifeMax), "diveSeaLife"); }
    /// <summary>The water's height and how much it shows, as the page's sliders have them: whole percent.</summary>
    public int DiveWaterPercent { get => (int)Math.Round(diveWaterShare * 100); set => DiveWaterShare = value / 100.0; }
    public int DiveWaterOpacityPercent { get => (int)Math.Round(diveWaterOpacity * 100); set => DiveWaterOpacity = value / 100.0; }
    /// <summary>The water on every monitor, not only the creatures' home one.</summary>
    public bool DiveAllScreens { get => diveAllScreens; set { if (Put(ref diveAllScreens, value, "diveAllScreens")) Raise(nameof(DiveHomeOnly)); } }
    /// <summary>The other way round, for the page's two choices.</summary>
    public bool DiveHomeOnly { get => !diveAllScreens; set => DiveAllScreens = !value; }
    /// <summary>The divers say a line as they jump in, when they see something, and as they climb out.</summary>
    public bool DiveTalk { get => diveTalk; set => Put(ref diveTalk, value, "diveTalk"); }
}

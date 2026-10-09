namespace Ledgelings;

/// <summary>Beds (SPEC §7.9): every character sleeps in its own bed, at a favourite place it learns.</summary>
public sealed partial class AppSettings
{
    /// <summary>How strongly a character walks back to its favourite place at nightfall, in percent.</summary>
    public const double BedPullMin = 0, BedPullMax = 100;
    /// <summary>Farthest, in points along its edge, a creature walks to its bed at nightfall.</summary>
    public const double BedWalkMin = 100, BedWalkMax = 6000;

    private bool bedsEnabled, bedTalk;
    private double bedPull, bedWalkDistance;

    private void LoadBeds()
    {
        bedsEnabled = store.Get<bool?>("bedsEnabled") ?? true;
        // 80 %: after two or three nights in one place they nearly always go back, and still wander now and then.
        bedPull = Math.Clamp(store.Get<double?>("bedPull") ?? 80, BedPullMin, BedPullMax);
        // About a laptop screen's width and a half: across one screen, not round the whole outline.
        bedWalkDistance = Math.Clamp(store.Get<double?>("bedWalkDistance") ?? 2000, BedWalkMin, BedWalkMax);
        bedTalk = store.Get<bool?>("bedTalk") ?? true;
    }

    /// <summary>Each character puts its own bed down where it sleeps, and learns a favourite place for it.</summary>
    public bool BedsEnabled { get => bedsEnabled; set => Put(ref bedsEnabled, value, "bedsEnabled"); }
    public double BedPull { get => bedPull; set => Put(ref bedPull, Math.Clamp(value, BedPullMin, BedPullMax), "bedPull"); }
    public double BedWalkDistance { get => bedWalkDistance; set => Put(ref bedWalkDistance, Math.Clamp(value, BedWalkMin, BedWalkMax), "bedWalkDistance"); }
    /// <summary>Now and then a creature says a line as it lays its bed down, or when its bed is moved.</summary>
    public bool BedTalk { get => bedTalk; set => Put(ref bedTalk, value, "bedTalk"); }
}

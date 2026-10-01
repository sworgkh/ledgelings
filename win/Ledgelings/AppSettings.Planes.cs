namespace Ledgelings;

/// <summary>Paper planes: every <see cref="PlaneMinutes"/>, one creature throws another a paper plane with a note in it.</summary>
public sealed partial class AppSettings
{
    /// <summary>Minutes from one paper plane to the next.</summary>
    public const double PlaneMin = 0.5, PlaneMax = 60;

    private bool planesEnabled;
    private double planeMinutes;

    private void LoadPlanes()
    {
        planesEnabled = store.Get<bool?>("planesEnabled") ?? true;
        planeMinutes = Math.Clamp(store.Get<double?>("planeMinutes") ?? 3, PlaneMin, PlaneMax);
    }

    /// <summary>Every <see cref="PlaneMinutes"/>, one creature throws another a paper plane with a note in it.</summary>
    public bool PlanesEnabled { get => planesEnabled; set => Put(ref planesEnabled, value, "planesEnabled"); }
    public double PlaneMinutes { get => planeMinutes; set => Put(ref planeMinutes, Math.Clamp(value, PlaneMin, PlaneMax), "planeMinutes"); }
}

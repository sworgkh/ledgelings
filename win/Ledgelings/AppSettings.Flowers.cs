namespace Ledgelings;

/// <summary>The flowers a meeting brings, once worn: planting them, and the garden they make.
/// (How long a flower is worn and following the giver live in the Talk half, where they were first;
/// the window shows them on the Flowers tab, as the Mac does.)</summary>
public sealed partial class AppSettings
{
    /// <summary>Minutes a planted flower stands in the edge before it wilts.</summary>
    public const double GardenMinutesMin = 1, GardenMinutesMax = 240;
    /// <summary>Most flowers in the ground at once; planting one more wilts the oldest.</summary>
    public const int GardenSizeMin = 1, GardenSizeMax = 40;

    private bool plantFlowers;
    private double gardenMinutes;
    private int gardenSize;

    private void LoadFlowers()
    {
        plantFlowers = store.Get<bool?>("plantFlowers") ?? true;
        // An hour: long enough to come back to a row of them, short enough to keep changing.
        gardenMinutes = Math.Clamp(store.Get<double?>("gardenMinutes") ?? 60, GardenMinutesMin, GardenMinutesMax);
        gardenSize = Math.Clamp(store.Get<int?>("gardenSize") ?? 12, GardenSizeMin, GardenSizeMax);
    }

    /// <summary>A creature with a flower plants it, when and where its character likes, instead of wearing it till it wilts.</summary>
    public bool PlantFlowers { get => plantFlowers; set => Put(ref plantFlowers, value, "plantFlowers"); }
    public double GardenMinutes { get => gardenMinutes; set => Put(ref gardenMinutes, Math.Clamp(value, GardenMinutesMin, GardenMinutesMax), "gardenMinutes"); }
    public int GardenSize { get => gardenSize; set => Put(ref gardenSize, Math.Clamp(value, GardenSizeMin, GardenSizeMax), "gardenSize"); }
}

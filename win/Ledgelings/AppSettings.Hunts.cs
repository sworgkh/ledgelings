namespace Ledgelings;

/// <summary>Chases (SPEC §4.7.2): the cursor's hunts are counted per character, and the creatures know it.</summary>
public sealed partial class AppSettings
{
    /// <summary>Percent of the moments they could bring their count up that they do.</summary>
    public const double HuntTalkChanceMin = 0, HuntTalkChanceMax = 100;
    /// <summary>Hunts in one day before a creature keeps further from the cursor (menace mood only).</summary>
    public const int HuntWaryAfterMin = 5, HuntWaryAfterMax = 200;

    private bool huntCountEnabled, huntTalkEnabled, huntWary;
    private double huntTalkChance;
    private int huntWaryAfter;

    private void LoadHunts()
    {
        huntCountEnabled = store.Get<bool?>("huntCountEnabled") ?? true;
        huntTalkEnabled = store.Get<bool?>("huntTalkEnabled") ?? true;
        // One moment in four: often enough that the numbers come up every so often, rarely enough that they are not all anyone talks about.
        huntTalkChance = Math.Clamp(store.Get<double?>("huntTalkChance") ?? 25, HuntTalkChanceMin, HuntTalkChanceMax);
        huntWary = store.Get<bool?>("huntWary") ?? true;
        // Twenty in a day: a creature chased that much has a reason to keep its distance.
        huntWaryAfter = Math.Clamp(store.Get<int?>("huntWaryAfter") ?? 20, HuntWaryAfterMin, HuntWaryAfterMax);
    }

    /// <summary>Count every chase and pick-up, per character: today, this week, in all.</summary>
    public bool HuntCountEnabled { get => huntCountEnabled; set => Put(ref huntCountEnabled, value, "huntCountEnabled"); }
    /// <summary>The creatures know their count: it reaches the prompts and the built-in lines.</summary>
    public bool HuntTalkEnabled { get => huntTalkEnabled; set => Put(ref huntTalkEnabled, value, "huntTalkEnabled"); }
    public double HuntTalkChance { get => huntTalkChance; set => Put(ref huntTalkChance, Math.Clamp(value, HuntTalkChanceMin, HuntTalkChanceMax), "huntTalkChance"); }
    /// <summary>In the menace mood, much-hunted creatures jump away from further off.</summary>
    public bool HuntWary { get => huntWary; set => Put(ref huntWary, value, "huntWary"); }
    public int HuntWaryAfter { get => huntWaryAfter; set => Put(ref huntWaryAfter, Math.Clamp(value, HuntWaryAfterMin, HuntWaryAfterMax), "huntWaryAfter"); }
}

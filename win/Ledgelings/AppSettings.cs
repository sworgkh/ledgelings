using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ledgelings.Core;
using Ledgelings.Native;

namespace Ledgelings;

/// <summary>Everything the user can change, saved to the settings file as it changes.
/// Raises <see cref="Changed"/> for the colony and <see cref="PropertyChanged"/> for the window.</summary>
public sealed partial class AppSettings : INotifyPropertyChanged
{
    public const int CountMin = 1, CountMax = 24;
    /// <summary>Screen points per sprite pixel. Half steps stay crisp on a hi-dpi display.</summary>
    public const double SizeMin = 1, SizeMax = 5, SizeStep = 0.5;
    public static readonly IReadOnlyList<string> DefaultColors = new[] { "#ff8a3d", "#3dc7b5", "#ff6fa3", "#ffd23d", "#9b7bff", "#7bd65a" };
    public const int MaxColors = 12;

    public event PropertyChangedEventHandler? PropertyChanged;
    /// <summary>Any setting changed. Fired after the value has landed.</summary>
    public event Action? Changed;

    private readonly ISettingsStore store;
    private readonly ISecretStore secrets;
    private const string KeyAccount = "openRouterKey";

    private int creatureCount;
    private IReadOnlyList<string> species;
    private IReadOnlyList<string> colors;
    private double minSize, maxSize, dayMinutes, nightMinutes;

    public AppSettings(ISettingsStore? store = null, ISecretStore? secrets = null)
    {
        this.store = store ?? new JsonSettingsStore(AppFolders.SettingsFile);
        this.secrets = secrets ?? new CredentialStore();
        creatureCount = Math.Clamp(this.store.Get<int?>("creatureCount") ?? 3, CountMin, CountMax);
        species = this.store.Get<List<string>>("species") ?? new List<string> { "blocky" };
        var saved = (this.store.Get<List<string>>("colors") ?? new List<string>()).Where(c => RGB.FromHex(c) is not null).ToList();
        colors = saved.Count == 0 ? DefaultColors.ToList() : saved;
        double Size(string key, double fallback) => Math.Clamp(this.store.Get<double?>(key) ?? fallback, SizeMin, SizeMax);
        double low = Size("minSize", 1.5), high = Size("maxSize", 3);
        minSize = Math.Min(low, high);
        maxSize = Math.Max(low, high);
        dayMinutes = Math.Max(0.5, this.store.Get<double?>("dayMinutes") ?? 3);
        nightMinutes = Math.Max(0, this.store.Get<double?>("nightMinutes") ?? 5);
        LoadTalk();
    }

    public int CreatureCount
    {
        get => creatureCount;
        set => Put(ref creatureCount, Math.Clamp(value, CountMin, CountMax), "creatureCount");
    }

    /// <summary>Names of the sprite sheets in use; creature i wears species i, wrapping round.</summary>
    public IReadOnlyList<string> Species
    {
        get => species;
        set => Put(ref species, value.ToList(), "species");
    }

    /// <summary>Creature number i wears colour i, wrapping round when there are more creatures than colours.</summary>
    public IReadOnlyList<string> Colors
    {
        get => colors;
        set => Put(ref colors, value.ToList(), "colors");
    }

    /// <summary>Each creature gets its own size somewhere from <see cref="MinSize"/> to <see cref="MaxSize"/>.
    /// Setting one past the other drags the other along, so min &lt;= max always holds.</summary>
    public double MinSize
    {
        get => minSize;
        set
        {
            var clamped = Math.Clamp(value, SizeMin, SizeMax);
            if (!Put(ref minSize, clamped, "minSize")) return;
            if (maxSize < minSize) MaxSize = minSize;
        }
    }

    public double MaxSize
    {
        get => maxSize;
        set
        {
            var clamped = Math.Clamp(value, SizeMin, SizeMax);
            if (!Put(ref maxSize, clamped, "maxSize")) return;
            if (minSize > maxSize) MinSize = maxSize;
        }
    }

    public double DayMinutes { get => dayMinutes; set => Put(ref dayMinutes, Math.Max(0.5, value), "dayMinutes"); }
    /// <summary>Zero means they never sleep.</summary>
    public double NightMinutes { get => nightMinutes; set => Put(ref nightMinutes, Math.Max(0, value), "nightMinutes"); }

    public string SpeciesFor(int index) => species.Count == 0 ? "blocky" : species[index % species.Count];

    /// <summary>Forget species that are no longer in the library (removed, or no longer
    /// built in); blocky steps in when nothing is left.</summary>
    public void KeepSpecies(IReadOnlyCollection<string> names)
    {
        var kept = species.Where(names.Contains).ToList();
        var wanted = kept.Count == 0 ? new List<string> { "blocky" } : kept;
        if (!wanted.SequenceEqual(species)) Species = wanted;
    }

    public void ToggleSpecies(string name)
    {
        Species = species.Contains(name) ? species.Where(s => s != name).ToList() : species.Append(name).ToList();
    }

    /// <summary>The size for a creature whose place in the range is <paramref name="share"/> (0 = smallest,
    /// 1 = largest), snapped to the step.</summary>
    public double SizeForShare(double share)
    {
        var raw = minSize + (maxSize - minSize) * Math.Min(Math.Max(share, 0), 1);
        return Math.Round(raw / SizeStep, MidpointRounding.AwayFromZero) * SizeStep;
    }

    public RGB ColorFor(int index) => RGB.FromHex(colors[index % Math.Max(colors.Count, 1)]) ?? RGB.FromHex(DefaultColors[0])!.Value;

    public void SetColor(int index, string hex)
    {
        if (index < 0 || index >= colors.Count || RGB.FromHex(hex) is null) return;
        var list = colors.ToList();
        list[index] = hex;
        Colors = list;
    }

    private bool Put<T>(ref T field, T value, string key, [CallerMemberName] string? property = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        store.Set(key, value);
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(property));
        Changed?.Invoke();
        return true;
    }
}

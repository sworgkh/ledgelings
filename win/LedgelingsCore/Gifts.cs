namespace Ledgelings.Core;

/// <summary>Flowers: the one in the air between two creatures, and the ones on heads.</summary>
public sealed class Gifts
{
    public readonly record struct Flight(string Flower, int From, int To, double Started);

    /// <summary>A flower on a head. <c>From</c> is who gave it; the wearer follows that one while it lasts.
    /// <c>Since</c> is when it landed on the head.</summary>
    public readonly record struct Worn(string Flower, double Until, int From, double Since = 0);

    /// <summary>Everything a creature can give. Each is an animation in the flowers sheet.</summary>
    public static readonly IReadOnlyList<string> Flowers = new[]
    {
        "poppy", "tulip", "daisy", "sunflower", "rose", "bluebell", "dandelion", "lavender", "lily", "forget-me-not",
    };

    /// <summary>A flower's name as people read and hear it, in the current language: what
    /// fills <c>{flower}</c> in a line. The ids above stay English, for the sprite sheet.</summary>
    public static string Name(string flower) =>
        Shared.Current?.Flowers.TryGetValue(flower, out var name) == true && name.Length > 0 ? name : flower;

    public double FlightTime { get; set; }
    public Flight? CurrentFlight { get; private set; }
    private Dictionary<int, Worn> worn = new();
    public IReadOnlyDictionary<int, Worn> WornFlowers => worn;

    public Gifts(double flightTime = 0.6) { FlightTime = flightTime; }

    /// <summary>Start a flower on its way. Refused while another is still in the air.</summary>
    public bool Give(string flower, int from, int to, double time)
    {
        if (CurrentFlight is not null) return false;
        CurrentFlight = new Flight(flower, from, to, time);
        return true;
    }

    /// <summary>0...1 along the flight, or null when nothing is flying.</summary>
    public double? FlightProgress(double time) =>
        CurrentFlight is Flight f ? Math.Min(1, Math.Max(0, (time - f.Started) / Math.Max(FlightTime, 1e-9))) : null;

    public string? Hat(int creature) => worn.TryGetValue(creature, out var w) ? w.Flower : null;

    /// <summary>Who gave the flower <paramref name="creature"/> is wearing, while it is wearing one.</summary>
    public int? Giver(int creature) => worn.TryGetValue(creature, out var w) ? w.From : null;

    /// <summary>How far through its time on the head <paramref name="creature"/>'s flower is, 0...1, while it wears one.
    /// (The Mac's <c>worn(_:at:)</c>; C# cannot name a method after the nested <see cref="Worn"/>.)</summary>
    public double? WornShare(int creature, double time) =>
        worn.TryGetValue(creature, out var w) ? Math.Min(1, Math.Max(0, (time - w.Since) / Math.Max(w.Until - w.Since, 1e-9))) : null;

    /// <summary>Take the flower off <paramref name="creature"/>'s head, to plant it. Null when it wears none.</summary>
    public Worn? TakeOff(int creature) => worn.Remove(creature, out var w) ? w : null;

    /// <summary>Land the flight when its time is up, and drop every hat past its time.</summary>
    public void Update(double time, double wearFor)
    {
        if (CurrentFlight is Flight f && time - f.Started >= FlightTime)
        {
            worn[f.To] = new Worn(f.Flower, time + wearFor, f.From, Since: time);
            CurrentFlight = null;
        }
        worn = worn.Where(kv => kv.Value.Until > time).ToDictionary(kv => kv.Key, kv => kv.Value);
    }

    /// <summary>The colony shrank: creatures at <paramref name="count"/> and beyond are gone.</summary>
    public void Forget(int count)
    {
        worn = worn.Where(kv => kv.Key < count).ToDictionary(kv => kv.Key, kv => kv.Value);
        if (CurrentFlight is Flight f && Math.Max(f.From, f.To) >= count) CurrentFlight = null;
    }
}

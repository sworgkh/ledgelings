namespace Ledgelings.Core;

/// <summary>Flowers: the one in the air between two creatures, and the ones on heads.</summary>
public sealed class Gifts
{
    public readonly record struct Flight(string Flower, int From, int To, double Started);

    public readonly record struct Worn(string Flower, double Until);

    /// <summary>Everything a creature can give. Each is an animation in the flowers sheet.</summary>
    public static readonly IReadOnlyList<string> Flowers = new[]
    {
        "poppy", "tulip", "daisy", "sunflower", "rose", "bluebell", "dandelion", "lavender", "lily", "forget-me-not",
    };

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

    /// <summary>Land the flight when its time is up, and drop every hat past its time.</summary>
    public void Update(double time, double wearFor)
    {
        if (CurrentFlight is Flight f && time - f.Started >= FlightTime)
        {
            worn[f.To] = new Worn(f.Flower, time + wearFor);
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

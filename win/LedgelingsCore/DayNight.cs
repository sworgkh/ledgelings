namespace Ledgelings.Core;

/// <summary>The colony's shared clock: a day, then a night, forever.</summary>
public readonly record struct DayNight
{
    public double Day { get; }      // seconds
    public double Night { get; }    // seconds

    public DayNight(double day, double night)
    {
        Day = Math.Max(1, day);
        Night = Math.Max(0, night);
    }

    public double Cycle => Day + Night;

    private double Phase(double elapsed) => elapsed - Math.Truncate(elapsed / Cycle) * Cycle;

    public bool IsNight(double elapsed) => Night > 0 && Phase(elapsed) >= Day;

    /// <summary>Seconds until the current day or night ends.</summary>
    public double Remaining(double elapsed)
    {
        var phase = Phase(elapsed);
        return phase >= Day ? Cycle - phase : Day - phase;
    }

    /// <summary>The smallest elapsed time after <paramref name="elapsed"/> that falls in the other half.</summary>
    public double SkippingToNextPhase(double elapsed) => elapsed + Remaining(elapsed);
}

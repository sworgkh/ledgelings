namespace Ledgelings.Core;

/// <summary>The few draws the simulation needs, over System.Random so a test can seed it.</summary>
public static class RngExtensions
{
    /// <summary>Uniform in [low, high].</summary>
    public static double Range(this Random rng, double low, double high) => low + (high - low) * rng.NextDouble();

    public static double Range(this Random rng, (double Low, double High) range) => rng.Range(range.Low, range.High);

    public static bool Coin(this Random rng) => rng.Next(2) == 0;

    public static T Pick<T>(this Random rng, IReadOnlyList<T> items) => items[rng.Next(items.Count)];
}

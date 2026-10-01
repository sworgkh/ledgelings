namespace Ledgelings.Core;

/// <summary>
/// How much of a bubble is on show while its line is being said out loud.
///
/// With voice on, a line's bubble first shows dots while the sound is fetched,
/// then types itself out as the voice speaks: in step with the words a reporting
/// voice gives, or evenly over the clip's length for a downloaded one.
/// The bubble is always sized for the whole line; the letters not yet said are
/// drawn invisible, so it does not grow and jump as the text comes in.
/// </summary>
public abstract record SpeechReveal
{
    /// <summary>Everything at once: voice off, or the line could not be said.</summary>
    public sealed record AllShown : SpeechReveal;
    /// <summary>The sound is on its way: <c>...</c>, one dot more every third of a second.</summary>
    public sealed record Waiting(double Since) : SpeechReveal;
    /// <summary>A clip of <c>Duration</c> seconds started playing at <c>Start</c>.</summary>
    public sealed record Timed(double Start, double Duration) : SpeechReveal;
    /// <summary>A voice that reports its progress, now this far through the line.</summary>
    public sealed record Spoken(double Share) : SpeechReveal;

    public static readonly SpeechReveal All = new AllShown();

    public const string Dots = "...";
    /// <summary>Dots a second, while waiting.</summary>
    private const double DotRate = 3.0;

    /// <summary>The text to draw for <paramref name="line"/> at time <paramref name="now"/>, and the share of it to show (0...1).</summary>
    public (string Text, double Share) Shown(string line, double now) => this switch
    {
        Waiting w => (Dots, ((int)(Math.Max(0, now - w.Since) * DotRate) % 3 + 1) / 3.0),
        Timed t when t.Duration > 0 => (line, Math.Min(Math.Max((now - t.Start) / t.Duration, 0), 1)),
        Spoken s => (line, Math.Min(Math.Max(s.Share, 0), 1)),
        _ => (line, 1),
    };

    /// <summary>How many of <paramref name="count"/> characters a <paramref name="share"/> shows. Never half a letter; the
    /// last one only once the share is whole.</summary>
    public static int Visible(double share, int count) =>
        share >= 1 ? count : Math.Min(count, Math.Max(0, (int)Math.Floor(share * count)));
}

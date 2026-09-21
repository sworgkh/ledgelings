namespace Ledgelings.Core;

/// <summary>Who a creature is when it opens its mouth.</summary>
public sealed record Character(string Name, string Persona);

/// <summary>The words that go to the model. Pure string work, so it is testable without
/// a server: templates with <c>{placeholders}</c>, filled from a small dictionary.</summary>
public static class Banter
{
    public static readonly IReadOnlyList<string> Placeholders = new[]
    {
        "speaker", "speakerKind", "speakerPersona", "listener", "listenerKind", "listenerPersona", "situation", "line",
    };

    /// <summary>What the built-in creature is, for the prompt.</summary>
    public const string DefaultKind = "a small square creature";

    public const string DefaultSystemPrompt =
        "You are {speaker}, {speakerKind}, living on the edge of a computer screen. {speakerPersona}\n" +
        "You are talking to {listener}, {listenerKind}, who lives on the same edge. {listenerPersona}\n" +
        "Say ONE line to {listener}: a joke, a jab or a tease, at most 20 words, in your own voice.\n" +
        "Output only the line. No quotes, no name prefix, no explanation.";

    public const string DefaultLinePrompt =
        "Right now: {situation}\n" +
        "Say your line to {listener}.";

    public const string DefaultReplyPrompt =
        "Right now: {situation}\n" +
        "{listener} just said to you: \"{line}\"\n" +
        "Answer back in ONE line, in character, at most 20 words.";

    public static readonly IReadOnlyList<Character> DefaultCharacters = new[]
    {
        new Character("Blocky", "Grumpy and proud. Hates the mouse cursor. Thinks the bottom edge is the only respectable edge."),
        new Character("Pip", "Cheerful and easily impressed. Loves the ceiling. Laughs at everything, including insults."),
        new Character("Mortimer", "Old and philosophical. Speaks slowly, quotes wisdom he made up, sighs a lot."),
        new Character("Zed", "Sleepy. Would rather be napping. Every sentence drifts toward bed."),
        new Character("Dot", "Tiny, fast and sarcastic. Brags about speed. Calls everyone else a boulder."),
        new Character("Ruth", "Bossy, organised, keeps count of everything. Disapproves of jumping."),
    };

    /// <summary>How long a bubble stays up for a line of typical length, in seconds.</summary>
    public const double DefaultBubbleSeconds = 14;

    /// <summary>Seconds a bubble stays. <paramref name="baseSeconds"/> is the time for a line of about eight
    /// words; longer lines get a little more, never past twice the base.</summary>
    public static double ShowTime(string text, double baseSeconds)
    {
        double words = text.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length;
        return Math.Min(baseSeconds * 2, baseSeconds / 2 + words * 0.9);
    }

    /// <summary>Replace every <c>{key}</c> in <paramref name="template"/> with its value. Unknown keys are left as they are.</summary>
    public static string Render(string template, IReadOnlyDictionary<string, string> values)
    {
        var text = template;
        foreach (var (key, value) in values) text = text.Replace("{" + key + "}", value);
        return text;
    }

    /// <summary>One line, cleaned up the way a small model needs: first non-empty line,
    /// no wrapping quotes, no "Name:" prefix, no hidden-reasoning tags, capped.</summary>
    public static string CleanLine(string raw, string speaker, int maxLength = 160)
    {
        var text = raw;
        var close = text.IndexOf("</think>", StringComparison.Ordinal);
        if (close >= 0) text = text[(close + "</think>".Length)..];
        var line = text.Split('\n', '\r').Select(l => l.Trim(' ', '\t')).FirstOrDefault(l => l.Length > 0) ?? "";
        foreach (var prefix in new[] { speaker + ":", speaker.ToUpperInvariant() + ":", "*" + speaker + "*:" })
            if (line.StartsWith(prefix, StringComparison.Ordinal)) line = line[prefix.Length..].Trim(' ', '\t');
        var opens = new[] { '"', '\u201c', '\'', '*' };
        var closes = new[] { '"', '\u201d', '\'', '*' };
        while (line.Length > 1 && opens.Contains(line[0]) && closes.Contains(line[^1]))
            line = line[1..^1].Trim(' ', '\t');
        if (line.Length > maxLength) line = line[..maxLength].Trim(' ', '\t') + "\u2026";
        return line;
    }
}

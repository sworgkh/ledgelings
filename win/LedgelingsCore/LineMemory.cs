namespace Ledgelings.Core;

/// <summary>What each character has said lately, so it does not say it again every
/// round: a built-in line is picked from the ones it has not said lately, and
/// a model is shown its recent lines and asked for something new. A line comes
/// back only once everything else has had its turn.</summary>
public sealed class LineMemory
{
    /// <summary>Lines kept per character; 0 remembers nothing.</summary>
    public int Limit { get; private set; }
    private Dictionary<string, List<string>> said = new();

    /// <summary>By character name, oldest first.</summary>
    public IReadOnlyDictionary<string, List<string>> Said => said;

    public LineMemory(int limit) { Limit = Math.Max(0, limit); }

    public void Remember(string text, string name)
    {
        text = text.Trim();
        if (Limit <= 0 || text.Length == 0) return;
        var key = Key(text);
        var lines = (said.TryGetValue(name, out var known) ? known : new List<string>()).Where(l => Key(l) != key).ToList();
        lines.Add(text);
        said[name] = lines.TakeLast(Limit).ToList();
    }

    /// <summary>Every line of <paramref name="exchange"/>, by who said it.</summary>
    public void Remember(ChatLog.Exchange exchange)
    {
        foreach (var line in exchange.Lines) Remember(line.Text, line.Speaker);
    }

    /// <summary><paramref name="name"/>'s last lines, oldest first.</summary>
    public List<string> Recent(string name) => said.TryGetValue(name, out var lines) ? lines.TakeLast(Limit).ToList() : new List<string>();

    /// <summary>Keep only the last <paramref name="limit"/> lines of everyone.</summary>
    public void Trim(int limit)
    {
        Limit = Math.Max(0, limit);
        said = said.ToDictionary(kv => kv.Key, kv => kv.Value.TakeLast(Limit).ToList())
            .Where(kv => kv.Value.Count > 0).ToDictionary(kv => kv.Key, kv => kv.Value);
    }

    /// <summary>Which of <paramref name="candidates"/> <paramref name="name"/> should say: one it has not said lately, at
    /// random; when it has said them all, the one said longest ago.</summary>
    public int? Pick(IReadOnlyList<string> candidates, string name, Random rng)
    {
        if (candidates.Count == 0) return null;
        var recent = Recent(name).Select(Key).ToList();
        var fresh = Enumerable.Range(0, candidates.Count).Where(i => !recent.Contains(Key(candidates[i]))).ToList();
        if (fresh.Count > 0) return rng.Pick(fresh);
        return Enumerable.Range(0, candidates.Count).MinBy(i => recent.LastIndexOf(Key(candidates[i])));
    }

    /// <summary>Two lines are the same if they differ only in case, spacing and punctuation.</summary>
    public static string Key(string text) => string.Concat(text.ToLowerInvariant().Where(char.IsLetterOrDigit));

    /// <summary>The system prompt with <paramref name="lines"/> after it, telling the model not to say them again.</summary>
    public static string WithRecent(string system, IReadOnlyList<string> lines) =>
        lines.Count == 0 ? system : system + "\n" + Note(lines);

    /// <summary>What the model is told about its own recent lines.</summary>
    public static string Note(IReadOnlyList<string> lines) =>
        L10n.Tr("You said these lately. Say something new: do not repeat them, their jokes, or the way they start.") + "\n"
            + string.Join("\n", lines.Select(l => "- " + l));
}

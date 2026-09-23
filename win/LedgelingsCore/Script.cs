namespace Ledgelings.Core;

/// <summary>
/// Conversations written in advance, for a colony with no model behind it.
///
/// The text form is made to be typed by hand or by a chat model: one
/// conversation per block, blocks separated by a blank line, the lines of a
/// block alternating between the one who bumped (first line) and the one who
/// was bumped into. <c>#</c> starts a comment. A block may open with tags in square
/// brackets, <c>[flower]</c> or <c>[night, flower]</c>, and is then only used when the
/// moment matches; an untagged block fits any moment. <c>{speaker}</c>,
/// <c>{listener}</c> and <c>{flower}</c> are filled in when the line is said.
/// </summary>
public sealed partial class Script : IEquatable<Script>
{
    public sealed class Conversation : IEquatable<Conversation>
    {
        public IReadOnlySet<string> Tags { get; }
        public List<string> Lines { get; }
        public Conversation(IEnumerable<string>? tags = null, IEnumerable<string>? lines = null)
        {
            Tags = new HashSet<string>(tags ?? Array.Empty<string>());
            Lines = (lines ?? Array.Empty<string>()).ToList();
        }
        public bool Equals(Conversation? other) => other is not null && Tags.SetEquals(other.Tags) && Lines.SequenceEqual(other.Lines);
        public override bool Equals(object? obj) => Equals(obj as Conversation);
        public override int GetHashCode() => Lines.Count;
    }

    /// <summary>What went wrong, and on which 1-based line of the text (0 when it is the whole text).</summary>
    public sealed class ParseException : Exception
    {
        public int Line { get; }
        public string Problem { get; }
        public ParseException(int line, string problem) : base(line > 0 ? $"line {line}: {problem}" : problem)
        {
            Line = line;
            Problem = problem;
        }
    }

    /// <summary>What a block may be tagged with, and what a moment can be.</summary>
    public static readonly IReadOnlySet<string> Tags = new HashSet<string> { "flower", "night", "day" };
    public static readonly IReadOnlyList<string> Placeholders = new[] { "speaker", "listener", "flower" };

    public IReadOnlyList<Conversation> Conversations { get; }

    public Script(IEnumerable<Conversation> conversations) { Conversations = conversations.ToList(); }

    // MARK: Text form

    public static Script Parse(string text)
    {
        var conversations = new List<Conversation>();
        List<string>? lines = null;
        HashSet<string> tags = new();
        var blockStart = 0;
        void Close()
        {
            if (lines is null) return;
            if (lines.Count == 0) throw new ParseException(blockStart, "a conversation needs at least one line after its tags");
            conversations.Add(new Conversation(tags, lines));
            lines = null;
        }
        var raw = text.Split('\n');
        for (int offset = 0; offset < raw.Length; offset++)
        {
            var number = offset + 1;
            var line = raw[offset].Trim(' ', '\t', '\r');
            if (line.Length == 0) { Close(); continue; }
            if (line.StartsWith('#')) continue;
            if (line.StartsWith('[') && line.EndsWith(']'))
            {
                if (lines is not null) throw new ParseException(number, "tags go on the first line of a conversation");
                var names = line[1..^1].Split(new[] { ',', ' ' }, StringSplitOptions.RemoveEmptyEntries).Select(n => n.ToLowerInvariant()).ToList();
                if (names.FirstOrDefault(n => !Tags.Contains(n)) is string bad)
                    throw new ParseException(number, $"unknown tag \"{bad}\"; the tags are {string.Join(", ", Tags.OrderBy(t => t, StringComparer.Ordinal))}");
                tags = new HashSet<string>(names);
                lines = new List<string>();
                blockStart = number;
                continue;
            }
            if (lines is null) { tags = new HashSet<string>(); lines = new List<string>(); blockStart = number; }
            lines.Add(line);
        }
        Close();
        if (conversations.Count == 0) throw new ParseException(0, "no conversations");
        return new Script(conversations);
    }

    /// <summary>The script written back out in its own format.</summary>
    public string Text() =>
        string.Join("\n\n", Conversations.Select(c =>
            string.Join("\n", (c.Tags.Count == 0 ? Array.Empty<string>() : new[] { "[" + string.Join(", ", c.Tags.OrderBy(t => t, StringComparer.Ordinal)) + "]" })
                .Concat(c.Lines)))) + "\n";

    // MARK: Choosing and saying

    /// <summary>The conversation to use now, by index: from the blocks whose every tag
    /// holds for <paramref name="moment"/>, the most specifically tagged ones, and among those
    /// one not in <paramref name="recent"/> unless they all are. Null when nothing fits.</summary>
    public int? Pick(IReadOnlySet<string> moment, IReadOnlyCollection<int> recent, Random rng)
    {
        var fitting = Enumerable.Range(0, Conversations.Count).Where(i => Conversations[i].Tags.IsSubsetOf(moment)).ToList();
        if (fitting.Count == 0) return null;
        var best = fitting.Max(i => Conversations[i].Tags.Count);
        var pool = fitting.Where(i => Conversations[i].Tags.Count == best).ToList();
        var fresh = pool.Where(i => !recent.Contains(i)).ToList();
        return rng.Pick(fresh.Count == 0 ? pool : fresh);
    }

    public static string Fill(string line, string speaker, string listener, string? flower) =>
        Banter.Render(line, new Dictionary<string, string> { ["speaker"] = speaker, ["listener"] = listener, ["flower"] = flower ?? "flower" });

    public bool Equals(Script? other) => other is not null && Conversations.SequenceEqual(other.Conversations);
    public override bool Equals(object? obj) => Equals(obj as Script);
    public override int GetHashCode() => Conversations.Count;
}

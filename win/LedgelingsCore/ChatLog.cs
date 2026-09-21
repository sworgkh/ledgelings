namespace Ledgelings.Core;

/// <summary>Every conversation the creatures have, kept on disk: one JSON-lines file
/// per local calendar day, <c>YYYY-MM-DD.jsonl</c>, one exchange per line. Plain
/// files on purpose, so Explorer or <c>type</c> is a perfectly good viewer.</summary>
public sealed class ChatLog
{
    public sealed record Line(string Speaker, string Text);

    public sealed class Exchange
    {
        public DateTimeOffset Time { get; set; }
        public string Situation { get; set; } = "";
        public string Provider { get; set; } = "";
        public string Model { get; set; } = "";
        public List<Line> Lines { get; set; } = new();
        /// <summary>What the two calls cost in US dollars and tokens, when the server said.</summary>
        public double? Cost { get; set; }
        public int? Tokens { get; set; }
    }

    public string Directory { get; }

    public ChatLog(string directory) { Directory = directory; }

    /// <summary>The file name's day part, in the local calendar.</summary>
    public static string Day(DateTimeOffset time) => time.ToLocalTime().ToString("yyyy-MM-dd");

    public string File(string day) => Path.Combine(Directory, day + ".jsonl");

    public void Append(Exchange exchange) => JsonLines.Append(File(Day(exchange.Time)), exchange);

    /// <summary>Days that have a log, newest first.</summary>
    public List<string> Days()
    {
        if (!System.IO.Directory.Exists(Directory)) return new List<string>();
        return System.IO.Directory.GetFiles(Directory)
            .Select(Path.GetFileName)
            .Where(f => f is not null && f.EndsWith(".jsonl", StringComparison.Ordinal) && f.Length == 16)
            .Select(f => f![..^6])
            .OrderByDescending(d => d, StringComparer.Ordinal)
            .ToList();
    }

    /// <summary>One day's exchanges in the order they happened. A damaged line is skipped.</summary>
    public List<Exchange> Exchanges(string day) => JsonLines.Read<Exchange>(File(day));
}

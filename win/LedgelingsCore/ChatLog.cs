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
        /// <summary>The story the pair was playing out, and which part of it this was (<see cref="Bonds"/>).</summary>
        public string? Plot { get; set; }
    }

    /// <summary>One line said out loud by a paid voice: what it cost, and whose line it
    /// was, so the Chats tab can put it next to its conversation. Kept in a
    /// side file per day, <c>YYYY-MM-DD.voice.jsonl</c>, because the price only comes
    /// back seconds after the conversation was written down.</summary>
    public sealed class VoiceCharge
    {
        /// <summary>When the line was said, not when its price came back.</summary>
        public DateTimeOffset Time { get; set; }
        public string Speaker { get; set; } = "";
        /// <summary>The words as said (<see cref="Voices.Speakable"/> of the line).</summary>
        public string Text { get; set; } = "";
        public string Model { get; set; } = "";
        /// <summary>Null when OpenRouter never said; 0 for a line played from the voice archive.</summary>
        public double? Cost { get; set; }
        public bool Kept { get; set; }

        public VoiceCharge() { }
        public VoiceCharge(DateTimeOffset time, string speaker, string text, string model, double? cost, bool kept = false)
        {
            Time = time; Speaker = speaker; Text = text; Model = model; Cost = cost; Kept = kept;
        }

        public override bool Equals(object? obj) => obj is VoiceCharge o && o.Time == Time && o.Speaker == Speaker
            && o.Text == Text && o.Model == Model && o.Cost == Cost && o.Kept == Kept;
        public override int GetHashCode() => HashCode.Combine(Time, Speaker, Text);
    }

    /// <summary>What the voice of one conversation cost.</summary>
    public sealed class VoiceTotal
    {
        public double Cost { get; set; }
        /// <summary>Lines said by a paid voice, lines of those without a price, lines replayed free.</summary>
        public int Lines { get; set; }
        public int Unpriced { get; set; }
        public int Kept { get; set; }
        public List<string> Models { get; set; } = new();
    }

    public string Directory { get; }

    public ChatLog(string directory) { Directory = directory; }

    /// <summary>The file name's day part, in the local calendar.</summary>
    public static string Day(DateTimeOffset time) => time.ToLocalTime().ToString("yyyy-MM-dd");

    public string File(string day) => Path.Combine(Directory, day + ".jsonl");

    public void Append(Exchange exchange) => JsonLines.Append(File(Day(exchange.Time)), exchange);

    public string VoiceFile(string day) => Path.Combine(Directory, day + ".voice.jsonl");

    public void AppendVoice(VoiceCharge charge) => JsonLines.Append(VoiceFile(Day(charge.Time)), charge);

    public List<VoiceCharge> VoiceCharges(string day) => JsonLines.Read<VoiceCharge>(VoiceFile(day));

    /// <summary>Which conversation each voice charge belongs to, summed per conversation
    /// (by index into <paramref name="exchanges"/>). A charge goes to the latest conversation
    /// that has the same speaker saying the same words and was written down no
    /// later than a minute after the line was said: scripted conversations are
    /// written as they start, model ones when they end.</summary>
    public static Dictionary<int, VoiceTotal> VoiceTotals(IEnumerable<VoiceCharge> charges, IReadOnlyList<Exchange> exchanges)
    {
        var totals = new Dictionary<int, VoiceTotal>();
        foreach (var charge in charges)
        {
            int? match = null;
            for (int i = 0; i < exchanges.Count; i++)
            {
                if (exchanges[i].Time > charge.Time.AddSeconds(60)) continue;
                if (!exchanges[i].Lines.Any(l => l.Speaker == charge.Speaker && Voices.Speakable(l.Text) == charge.Text)) continue;
                if (match is not int m || exchanges[i].Time > exchanges[m].Time) match = i;
            }
            if (match is not int at) continue;
            if (!totals.TryGetValue(at, out var t)) totals[at] = t = new VoiceTotal();
            if (charge.Kept) t.Kept += 1;
            else
            {
                t.Lines += 1;
                if (charge.Cost is double cost) t.Cost += cost; else t.Unpriced += 1;
            }
            if (!t.Models.Contains(charge.Model)) t.Models.Add(charge.Model);
        }
        return totals;
    }

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

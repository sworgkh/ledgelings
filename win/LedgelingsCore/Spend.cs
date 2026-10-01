using System.Globalization;

namespace Ledgelings.Core;

/// <summary>What the talking costs. One record per model call, kept as JSON lines in
/// one file, summed by day, month, all time, model and feature.</summary>
public static class Spend
{
    /// <summary>What a server reported for one call. <c>Cost</c> is in US dollars and only
    /// OpenRouter sends it; a local server's call is priced at zero by the app.</summary>
    public sealed record Usage(int PromptTokens, int CompletionTokens, double? Cost)
    {
        public int PromptTokens { get; set; } = PromptTokens;
        public int CompletionTokens { get; set; } = CompletionTokens;
        public double? Cost { get; set; } = Cost;
    }

    /// <summary>Which feature made a call. Every model call is recorded with one, so the
    /// Costs tab can say what each feature costs, not just each model.</summary>
    public enum Purpose { Talk, Planes, Voice, Casting, Plots, Reminders, Complaints, TeaParties }

    /// <summary>What records written before features were labelled are shown as.</summary>
    public static string UnlabelledPurpose => L10n.Tr("Earlier, unlabelled");

    /// <summary>The title for a record's stored purpose, which may be missing or from a newer app.</summary>
    public static string PurposeTitle(string? raw)
    {
        if (raw is null) return UnlabelledPurpose;
        foreach (var p in Enum.GetValues<Purpose>()) if (p.Raw() == raw) return p.Title();
        return raw;
    }

    public sealed class Record
    {
        public DateTimeOffset Time { get; set; }
        public string Provider { get; set; } = "";
        public string Model { get; set; } = "";
        public Usage Usage { get; set; } = new(0, 0, null);
        /// <summary>A <see cref="Spend.Purpose"/>'s raw value; absent in records from before v0.18. A string,
        /// not the enum, so a purpose added later does not make older builds drop the line.</summary>
        public string? Purpose { get; set; }

        public Record() { }
        public Record(DateTimeOffset time, string provider, string model, Usage usage, Purpose? purpose = null)
        {
            Time = time; Provider = provider; Model = model; Usage = usage; Purpose = purpose?.Raw();
        }
    }

    /// <summary>A sum of records. <c>Cost</c> adds up the priced ones; <c>Unpriced</c> counts the rest.</summary>
    public sealed record Total
    {
        public int Calls { get; set; }
        public int PromptTokens { get; set; }
        public int CompletionTokens { get; set; }
        public double Cost { get; set; }
        public int Unpriced { get; set; }

        public int Tokens => PromptTokens + CompletionTokens;

        internal void Add(Usage u)
        {
            Calls += 1; PromptTokens += u.PromptTokens; CompletionTokens += u.CompletionTokens;
            if (u.Cost is double c) Cost += c; else Unpriced += 1;
        }
    }

    public sealed class Summary
    {
        public Total Today { get; set; } = new();
        public Total Month { get; set; } = new();
        public Total AllTime { get; set; } = new();
        /// <summary>Dearest first; ties by calls.</summary>
        public List<(string Model, Total Total)> ByModel { get; set; } = new();
        /// <summary>By feature, as <see cref="PurposeTitle"/> names it; dearest first.</summary>
        public List<(string Purpose, Total Total)> ByPurpose { get; set; } = new();
    }

    public static Summary Summarise(IEnumerable<Record> records, DateTimeOffset? now = null)
    {
        var at = (now ?? DateTimeOffset.Now).ToLocalTime();
        var s = new Summary();
        var models = new Dictionary<string, Total>();
        var purposes = new Dictionary<string, Total>();
        foreach (var r in records)
        {
            var title = PurposeTitle(r.Purpose);
            if (!purposes.TryGetValue(title, out var forPurpose)) purposes[title] = forPurpose = new Total();
            forPurpose.Add(r.Usage);
            var local = r.Time.ToLocalTime();
            s.AllTime.Add(r.Usage);
            if (local.Year == at.Year && local.Month == at.Month) s.Month.Add(r.Usage);
            if (local.Date == at.Date) s.Today.Add(r.Usage);
            if (!models.TryGetValue(r.Model, out var total)) models[r.Model] = total = new Total();
            total.Add(r.Usage);
        }
        s.ByModel = models.Select(kv => (kv.Key, kv.Value))
            .OrderByDescending(m => m.Value.Cost).ThenByDescending(m => m.Value.Calls).ThenBy(m => m.Key, StringComparer.Ordinal)
            .ToList();
        s.ByPurpose = purposes.Select(kv => (kv.Key, kv.Value))
            .OrderByDescending(p => p.Value.Cost).ThenByDescending(p => p.Value.Calls).ThenBy(p => p.Key, StringComparer.Ordinal)
            .ToList();
        return s;
    }

    /// <summary>Money for people: cents when there are any, otherwise tenths of a cent.</summary>
    public static string Label(double usd)
    {
        if (usd == 0) return "$0.00";
        if (usd < 0.001) return "<$0.001";
        if (usd < 0.1) return "$" + usd.ToString("0.000", CultureInfo.InvariantCulture);
        return "$" + usd.ToString("0.00", CultureInfo.InvariantCulture);
    }

    /// <summary>The file: <c>spend.jsonl</c> in a folder, one record a line, appended as calls happen.</summary>
    public sealed class Ledger
    {
        public string Directory { get; }
        public Ledger(string directory) { Directory = directory; }
        public string File => Path.Combine(Directory, "spend.jsonl");

        public void Append(Record record) => JsonLines.Append(File, record);

        /// <summary>Every record in the order it was written. A damaged line is skipped.</summary>
        public List<Record> Records() => JsonLines.Read<Record>(File);
    }
}

/// <summary>A purpose's words: the title the Costs tab shows, and the raw value the file keeps (the Mac's).</summary>
public static class SpendPurposeExtensions
{
    public static string Title(this Spend.Purpose purpose) => purpose switch
    {
        Spend.Purpose.Talk => L10n.Tr("Talk"),
        Spend.Purpose.Planes => L10n.Tr("Paper planes"),
        Spend.Purpose.Voice => L10n.Tr("Voice"),
        Spend.Purpose.Casting => L10n.Tr("Voice casting"),
        Spend.Purpose.Plots => L10n.Tr("Relationship plots"),
        Spend.Purpose.Reminders => L10n.Tr("Reminders"),
        Spend.Purpose.Complaints => L10n.Tr("Complaints"),
        _ => L10n.Tr("Tea parties"),
    };

    /// <summary>"talk", "teaParties": the enum's name in camelCase, as the macOS app writes it.</summary>
    public static string Raw(this Spend.Purpose purpose)
    {
        var name = purpose.ToString();
        return char.ToLowerInvariant(name[0]) + name[1..];
    }
}

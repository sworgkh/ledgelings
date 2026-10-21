using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Long-term memory (SPEC §6.5.2.3), from the colony's side: the diary, one model call a pair
/// at the colony's nightfall that writes their memory down (<see cref="Core.Bonds.Diary"/>),
/// priced as <see cref="Core.Spend.Purpose.Memory"/>; the seed, which reads the chat log of the last weeks
/// into each pair's memory once (<see cref="Core.Spend.Purpose.MemorySeed"/>); and the dump the Mac's
/// <c>--memory</c> flag prints. The Mac's <c>Colony+Memory</c>.</summary>
public sealed partial class Colony
{
    /// <summary>Pairs whose memory the model is writing now.</summary>
    private readonly HashSet<string> writingMemory = new();
    private double nextMemoryCheck;
    private bool wasNight;
    /// <summary>Diaries being written now, for whoever waits on them.</summary>
    public int WritingMemoryCount => writingMemory.Count;

    /// <summary>Who <paramref name="name"/> is, for a prompt: its kind and persona if it is on screen, else blanks.</summary>
    private (string Name, string Kind, string Persona) Who(string name)
    {
        for (int i = 0; i < creatures.Count; i++)
            if (CharacterFor(i).Name == name) return (name, KindOf(i), CharacterFor(i).Persona);
        return (name, "", "");
    }

    /// <summary>Every half minute: at the colony's nightfall, the pairs whose memory is
    /// due get their diary; the caps are kept to.</summary>
    private void UpdateMemory()
    {
        if (Elapsed < nextMemoryCheck) return;
        var first = nextMemoryCheck == 0;
        nextMemoryCheck = Elapsed + 30;
        var night = IsNight;
        try
        {
            if (first) Bonds.Change(book => book.KeepMemory(Settings.MemoryFacts, Settings.MemoryDays));
            if (!night || wasNight || first) return;
            WriteDiaries();
        }
        finally { wasNight = night; }
    }

    /// <summary>The diary for every pair due one, most new moments first, up to the night's cap.</summary>
    public int WriteDiaries(bool force = false)
    {
        if (!Settings.MemoryEnabled || !(Settings.DiaryEnabled || force) || Settings.Brain == BrainKind.Script || Settings.ChatClient() is null) return 0;
        var due = Bonds.Book.DiaryDue(force ? 0 : Settings.DiaryEveryHours * 3600)
            .Where(b => !writingMemory.Contains(Core.Bonds.Key(b.Names[0], b.Names[1])))
            .Take(force ? int.MaxValue : Settings.DiaryPairsPerNight).ToList();
        foreach (var bond in due) WriteDiary(bond.Names[0], bond.Names[1]);
        if (due.Count > 0) Bonds.Change(book => book.KeepMemory(Settings.MemoryFacts, Settings.MemoryDays));
        return due.Count;
    }

    /// <summary>What the two said today, their last few exchanges, for the diary.</summary>
    private List<ChatLog.Line> TodaysLines(string a, string b, int limit = 6) =>
        History.Exchanges(Core.Bonds.DayKey(DateTimeOffset.Now))
            .Where(e => e.Lines.Any(l => l.Speaker == a) && e.Lines.Any(l => l.Speaker == b))
            .SelectMany(e => e.Lines).TakeLast(limit).ToList();

    /// <summary>One pair's diary: one call in the background, recorded as <see cref="Core.Spend.Purpose.Memory"/> whatever comes back.</summary>
    private void WriteDiary(string a, string b)
    {
        var key = Core.Bonds.Key(a, b);
        if (Settings.ChatClient() is not ChatClient service || Bonds.Bond(a, b) is not Core.Bonds.Bond bond || writingMemory.Contains(key)) return;
        var values = Core.Bonds.MemoryValues(bond, Who(bond.Names[0]), Who(bond.Names[1]), TodaysLines(a, b), Settings.StoryWords, Settings.MemoryFacts);
        var prompt = Banter.Render(Core.Bonds.DiaryPrompt, values);
        writingMemory.Add(key);
        Trace?.Invoke($"memory {key}: writing the diary, {Core.Bonds.Tokens(prompt)} tokens or so");
        _ = Write();

        async Task Write()
        {
            double? cost = null;
            Core.Bonds.Diary? diary = null;
            try
            {
                var answer = await service.Reply(Core.Bonds.DiarySystemPrompt, prompt, Core.Bonds.DiaryMaxTokens, reasoning: "low");
                if (answer.Usage is Spend.Usage usage)
                {
                    if (service.Kind == ChatClient.Provider.LmStudio) usage.Cost = 0;
                    cost = usage.Cost;
                    Spend.Record(service.Kind, service.Model, usage, Core.Spend.Purpose.Memory);
                }
                diary = Core.Bonds.ParseDiary(answer.Text);
                if (diary is null) Console.Error.WriteLine("Ledgelings memory: nothing in " + System.Text.Json.JsonSerializer.Serialize(answer.Text));
            }
            catch (ChatClient.Failure e)
            {
                Console.Error.WriteLine("Ledgelings memory: " + e.Message);
            }
            writingMemory.Remove(key);
            Bonds.Change(book =>
            {
                if (diary is not null) book.Write(a, b, diary, "diary", Settings.StoryWords, Settings.MemoryFacts, cost);
                else book.WroteMemory(a, b, DateTimeOffset.Now, cost);
            });
            if (diary is null) return;
            Trace?.Invoke($"memory {key}: story: {diary.Story ?? "-"}");
            foreach (var fact in diary.Facts) Trace?.Invoke($"memory {key}: fact: {fact}");
            foreach (var (day, line) in diary.Days.OrderBy(d => d.Key, StringComparer.Ordinal))
                Trace?.Invoke($"memory {key}: day {(day.Length == 0 ? "today" : day)}: {line}");
        }
    }

    // MARK: The seed

    /// <summary>What the seed did, for the tab.</summary>
    public sealed class SeedReport
    {
        public List<(string Key, int Exchanges, int Days, int Lines, int Tokens)> Pairs { get; } = new();
        public int Tokens => Pairs.Sum(p => p.Tokens);
    }

    /// <summary>Every pair who spoke together in the chat log over the last <paramref name="days"/> days,
    /// with how many conversations: at least <paramref name="atLeast"/> of them.</summary>
    private List<(string A, string B, List<ChatLog.Exchange> Exchanges)> SeedPairs(int days, DateTimeOffset now, int atLeast = 3)
    {
        var from = now.AddDays(-days);
        var oldest = Core.Bonds.DayKey(from);
        var exchanges = History.Days().Where(d => string.CompareOrdinal(d, oldest) >= 0).SelectMany(History.Exchanges).Where(e => e.Time >= from).ToList();
        var counts = new Dictionary<string, int>();
        foreach (var e in exchanges)
        {
            var speakers = e.Lines.Select(l => l.Speaker).Distinct().OrderBy(n => n, StringComparer.Ordinal).ToList();
            if (speakers.Count < 2) continue;
            for (int i = 0; i < speakers.Count; i++)
                for (int j = i + 1; j < speakers.Count; j++)
                {
                    var key = Core.Bonds.Key(speakers[i], speakers[j]);
                    counts[key] = counts.GetValueOrDefault(key) + 1;
                }
        }
        return counts.Where(kv => kv.Value >= atLeast)
            .OrderByDescending(kv => kv.Value).ThenBy(kv => kv.Key, StringComparer.Ordinal)
            .Select(kv =>
            {
                var names = kv.Key.Split(" & ");
                return (names[0], names[1], exchanges);
            }).ToList();
    }

    /// <summary>Read the last <see cref="AppSettings.SeedDays"/> days of the chat log into every pair's
    /// memory: their days counted, and with a model one call a pair for their
    /// story, facts and day lines. <paramref name="dryRun"/>: say what would be sent and what it
    /// would cost, send nothing, change nothing. <c>bonds.json</c> is copied to
    /// <c>bonds.before-seed.json</c> first.</summary>
    public async Task<SeedReport> SeedMemory(bool dryRun, Action<string> log)
    {
        var report = new SeedReport();
        var days = Settings.SeedDays;
        var now = DateTimeOffset.Now;
        var from = now.AddDays(-days);
        // A dry run never touches the key: no client, no Credential Manager.
        var service = dryRun || Settings.Brain == BrainKind.Script ? null : Settings.ChatClient();
        if (!dryRun)
        {
            var backup = Path.Combine(Bonds.Store.Directory, "bonds.before-seed.json");
            try
            {
                if (File.Exists(Bonds.File)) File.Copy(Bonds.File, backup, true);
                log("seed: bonds.json copied to " + Path.GetFileName(backup));
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { log("seed: " + e.Message); }
        }
        foreach (var (a, b, exchanges) in SeedPairs(days, now))
        {
            var key = Core.Bonds.Key(a, b);
            var digest = Core.Bonds.Digest(exchanges, a, b, from, now, Settings.SeedLines);
            if (digest.Exchanges == 0) continue;
            var bond = Bonds.Bond(a, b) ?? new Core.Bonds.Bond(new[] { a, b }.OrderBy(n => n, StringComparer.Ordinal));
            var values = Core.Bonds.SeedValues(bond, digest, Who(bond.Names[0]), Who(bond.Names[1]), days, Settings.StoryWords, Settings.MemoryFacts);
            var prompt = Banter.Render(Core.Bonds.SeedPrompt, values);
            var tokens = Core.Bonds.Tokens(prompt);
            report.Pairs.Add((key, digest.Exchanges, digest.Days.Count, digest.Lines.Count, tokens));
            log($"seed {key}: {digest.Exchanges} conversations over {digest.Days.Count} days, {digest.Lines.Count} lines, about {tokens} tokens to send");
            if (dryRun)
            {
                foreach (var k in digest.Days.Keys.OrderBy(k => k, StringComparer.Ordinal)) log($"seed {key}: {k}: {Core.Bonds.Tallied(digest.Days[k])}");
                foreach (var l in digest.Lines.Take(4)) log($"seed {key}: [{l.Day}] {l.Line.Speaker}: {l.Line.Text}");
                continue;
            }
            Bonds.Change(book => book.SeedDays(a, b, digest, now));
            if (service is null) continue;
            try
            {
                var answer = await service.Reply(Core.Bonds.DiarySystemPrompt, prompt, Core.Bonds.DiaryMaxTokens * 2, reasoning: "low");
                double? cost = null;
                if (answer.Usage is Spend.Usage usage)
                {
                    if (service.Kind == ChatClient.Provider.LmStudio) usage.Cost = 0;
                    cost = usage.Cost;
                    Spend.Record(service.Kind, service.Model, usage, Core.Spend.Purpose.MemorySeed);
                }
                if (Core.Bonds.ParseDiary(answer.Text) is Core.Bonds.Diary diary)
                {
                    Bonds.Change(book => book.Write(a, b, diary, "seed", Settings.StoryWords, Settings.MemoryFacts, cost, now));
                    log($"seed {key}: story: {diary.Story ?? "-"}");
                    foreach (var fact in diary.Facts) log($"seed {key}: fact: {fact}");
                    log($"seed {key}: {diary.Days.Count} day lines, cost {(cost is double c ? Core.Spend.Label(c) : "unpriced")}");
                }
                else
                {
                    Bonds.Change(book => book.WroteMemory(a, b, now, cost));
                    log($"seed {key}: the answer had nothing in it: {System.Text.Json.JsonSerializer.Serialize(answer.Text.Length > 200 ? answer.Text[..200] : answer.Text)}");
                }
            }
            catch (ChatClient.Failure e)
            {
                log($"seed {key}: {e.Message}");
            }
        }
        if (!dryRun) Bonds.Change(book => book.KeepMemory(Settings.MemoryFacts, Settings.MemoryDays));
        log($"seed: {report.Pairs.Count} pairs, about {report.Tokens} tokens in all{(dryRun ? " (dry run: nothing sent, nothing changed)" : "")}");
        return report;
    }

    // MARK: The dump

    /// <summary>Each pair's memory as the owner and a prompt see it (the Mac's <c>--memory</c>).</summary>
    public List<string> MemoryDump(string? only = null)
    {
        var output = new List<string>();
        foreach (var bond in Bonds.Book.Closest.Where(b => only is null || string.Join(" & ", b.Names).Contains(only, StringComparison.OrdinalIgnoreCase)))
        {
            var key = Core.Bonds.Key(bond.Names[0], bond.Names[1]);
            output.Add($"memory {key}: bond: {bond.Summary ?? "-"}");
            output.Add($"memory {key}: story: {bond.Chronicle ?? "-"}");
            foreach (var fact in bond.Facts) output.Add($"memory {key}: fact ({fact.Source}, {Core.Bonds.Day(fact.Time)}): {fact.Text}");
            output.Add($"memory {key}: games: {Core.Bonds.RecordLine(bond) ?? "-"}");
            foreach (var day in bond.Days.TakeLast(7)) output.Add($"memory {key}: day {day.Day}: {day.Line ?? Core.Bonds.DayLine(day)}");
            foreach (var (x, y) in new[] { (bond.Names[0], bond.Names[1]), (bond.Names[1], bond.Names[0]) })
            {
                var block = Core.Bonds.Memory(bond, x, y, Settings.MemoryTokens);
                output.Add($"memory {key}: {x} remembers ({Core.Bonds.Tokens(block)} of {Settings.MemoryTokens} tokens): {block}");
            }
        }
        return output;
    }
}

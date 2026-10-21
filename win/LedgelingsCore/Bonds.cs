using System.Text.Json;

namespace Ledgelings.Core;

/// <summary>
/// How two characters who share a screen get on, and the small story playing
/// out between them.
///
/// Every pair of characters on screen at the same time adds up time together.
/// Once a pair has lived side by side long enough, the model writes them a
/// <b>plot</b>: a few words of story (a rivalry, a secret, a favour owed) that
/// colours their next few conversations, and a one-line <b>bond</b> saying how
/// they get on. When the plot has been played out, the next one grows from the
/// bond, from what they said lately and from their <b>storyline</b>: a short
/// chronicle of everything they have lived through together (talks, tea
/// parties, flowers, paper planes, a cursor grab), rewritten with each new
/// story to take in what happened since (<c>Bonds.Storyline.cs</c>). The prompt
/// carries that chronicle and the latest moments, never the raw history, so a
/// long friendship costs only a little more than a new one.
///
/// Pairs are kept by character name: a rename is a new character with no past.
/// </summary>
public static partial class Bonds
{
    /// <summary>The story between two characters, and how far into it they are.</summary>
    public sealed record Plot
    {
        public string Text { get; set; } = "";
        /// <summary>Conversations it is meant to last.</summary>
        public int Length { get; set; } = 1;
        /// <summary>Conversations already had under it.</summary>
        public int Told { get; set; }
        public DateTimeOffset Started { get; set; }

        public Plot() { }
        public Plot(string text, int length, int told = 0, DateTimeOffset started = default)
        {
            Text = text; Length = Math.Max(1, length); Told = told; Started = started;
        }
    }

    public sealed class Bond
    {
        /// <summary>The two names, in order.</summary>
        public List<string> Names { get; set; } = new();
        /// <summary>Seconds both have been on screen at the same time.</summary>
        public double Together { get; set; }
        /// <summary>Conversations with a model between them.</summary>
        public int Talks { get; set; }
        /// <summary>How they get on, as the model last put it.</summary>
        public string? Summary { get; set; }
        public Plot? Plot { get; set; }
        /// <summary>The plot before this one, so the next can follow on.</summary>
        public string? LastPlot { get; set; }
        /// <summary>Plots written for them so far.</summary>
        public int Plots { get; set; }
        /// <summary>The last few lines they said to each other, for the next plot.</summary>
        public List<ChatLog.Line> Recent { get; set; } = new();
        /// <summary>When a plot was last asked for, so a failing model is not asked every conversation.</summary>
        public DateTimeOffset? LastAsked { get; set; }
        /// <summary>What their plots have cost, US dollars, when the server said.</summary>
        public double? Cost { get; set; }
        /// <summary>Their story so far, a few dozen words, rewritten with each new plot.</summary>
        public string? Chronicle { get; set; }
        /// <summary>What they have lived through since the chronicle was last written, oldest first.</summary>
        public List<Moment> Moments { get; set; } = new();
        /// <summary>Everything they ever did together, counted by kind (<see cref="MomentKind"/>).</summary>
        public Dictionary<string, int> Tally { get; set; } = new();
        /// <summary>The first moment they shared.</summary>
        public DateTimeOffset? Met { get; set; }
        /// <summary>Their past in the chat log, from before moments were kept, has been read in.</summary>
        public bool Seeded { get; set; }
        /// <summary>What they remember of each other for weeks: a promise, a debt, a rivalry, newest last.</summary>
        public List<Fact> Facts { get; set; } = new();
        /// <summary>One entry per day they shared anything, oldest first: counts, games, a line.</summary>
        public List<DayEntry> Days { get; set; } = new();
        /// <summary>Games one of them won against the other, by <c>"kind|winner"</c>; <c>"kind|="</c> for a draw.</summary>
        public Dictionary<string, int> Record { get; set; } = new();
        /// <summary>When the model last wrote their memory down (the diary, or the seed).</summary>
        public DateTimeOffset? DiaryAt { get; set; }
        /// <summary>When their memory was last read in from the chat log (the seed).</summary>
        public DateTimeOffset? MemorySeeded { get; set; }
        /// <summary>What their memory has cost, US dollars, when the server said.</summary>
        public double? MemoryCost { get; set; }

        public Bond() { }
        public Bond(IEnumerable<string> names) { Names = names.ToList(); }

        public override bool Equals(object? obj) => obj is Bond o && o.Names.SequenceEqual(Names) && o.Together == Together
            && o.Talks == Talks && o.Summary == Summary && Equals(o.Plot, Plot) && o.LastPlot == LastPlot && o.Plots == Plots
            && o.Recent.SequenceEqual(Recent) && o.LastAsked == LastAsked && o.Cost == Cost
            && o.Chronicle == Chronicle && o.Moments.SequenceEqual(Moments) && o.Met == Met && o.Seeded == Seeded
            && SameCounts(o.Tally, Tally) && o.Facts.SequenceEqual(Facts) && o.Days.SequenceEqual(Days) && SameCounts(o.Record, Record)
            && o.DiaryAt == DiaryAt && o.MemorySeeded == MemorySeeded && o.MemoryCost == MemoryCost;
        internal static bool SameCounts(IReadOnlyDictionary<string, int> a, IReadOnlyDictionary<string, int> b) =>
            a.Count == b.Count && a.All(kv => b.TryGetValue(kv.Key, out var n) && n == kv.Value);
        public override int GetHashCode() => HashCode.Combine(string.Join(" & ", Names), Together);
    }

    /// <summary>Lines kept per pair for the next plot.</summary>
    public const int RecentLines = 4;
    /// <summary>After a plot request that came to nothing, wait this long before asking again, in seconds.</summary>
    public const double RetryAfter = 10 * 60;

    public static string Key(string a, string b) => string.Join(" & ", new[] { a, b }.OrderBy(n => n, StringComparer.Ordinal));

    /// <summary>Every bond, by pair.</summary>
    public sealed partial class Book
    {
        public Dictionary<string, Bond> Bonds { get; set; } = new();

        public Bond? Bond(string a, string b) => Bonds.TryGetValue(Key(a, b), out var bond) ? bond : null;

        public void Update(string a, string b, Action<Bond> change)
        {
            var k = Key(a, b);
            if (!Bonds.TryGetValue(k, out var bond)) bond = new Bond(new[] { a, b }.OrderBy(n => n, StringComparer.Ordinal));
            change(bond);
            Bonds[k] = bond;
        }

        /// <summary><paramref name="seconds"/> passed with all of <paramref name="names"/> on screen: every pair of them was together that long.</summary>
        public void LiveTogether(double seconds, IEnumerable<string> names)
        {
            var unique = names.Distinct().OrderBy(n => n, StringComparer.Ordinal).ToList();
            if (seconds <= 0 || unique.Count < 2) return;
            for (int i = 0; i < unique.Count; i++)
                for (int j = i + 1; j < unique.Count; j++)
                    Update(unique[i], unique[j], b => b.Together += seconds);
        }

        /// <summary>A pair is due a plot when plots are on, it has lived together at least
        /// <paramref name="after"/> seconds, has no story running, and was not asked lately.</summary>
        public bool NeedsPlot(string a, string b, double after, DateTimeOffset now)
        {
            if (a == b || Bond(a, b) is not Bond bond || bond.Together < after || bond.Plot is not null) return false;
            if (bond.LastAsked is DateTimeOffset asked && (now - asked).TotalSeconds < RetryAfter) return false;
            return true;
        }

        /// <summary>A conversation between them ended with <paramref name="lines"/> said: one more part of
        /// the plot is told, and it is over once all its parts are. It is a moment of their
        /// storyline too (<paramref name="kind"/>: <see cref="MomentKind.Tea"/> for a whole tea party).</summary>
        public void Talked(string a, string b, IReadOnlyList<ChatLog.Line> lines, string kind = MomentKind.Talk, DateTimeOffset? at = null)
        {
            if (lines.Count == 0) return;
            Note(a, b, new Moment(at ?? DateTimeOffset.Now, kind, lines[0].Speaker, lines[0].Text));
            Update(a, b, bond =>
            {
                bond.Talks += 1;
                bond.Recent = bond.Recent.Concat(lines).TakeLast(RecentLines).ToList();
                if (bond.Plot is not Plot plot) return;
                var told = plot with { Told = plot.Told + 1 };
                if (told.Told >= told.Length)
                {
                    bond.LastPlot = told.Text;
                    bond.Plot = null;
                }
                else
                {
                    bond.Plot = told;
                }
            });
        }

        /// <summary>The model (or the built-in lines) wrote them a new story. Their storyline
        /// takes in the moments since the last one: the model's rewrite when it sent
        /// one (<c>STORY:</c>), else the moments folded in plainly, at most <paramref name="words"/> words.
        /// <paramref name="keepsStory"/> false (storylines off): the chronicle is left as it was.</summary>
        public void Begin(string a, string b, Written written, int length, DateTimeOffset now,
                          bool keepsStory = true, int words = StoryWords)
        {
            Update(a, b, bond =>
            {
                if (keepsStory)
                {
                    bond.Chronicle = written.Story is string story
                        ? Trimmed(story, words)
                        : Fold(bond.Chronicle, bond.Moments, bond.Names, bond.LastPlot, words);
                    bond.Moments = new();
                }
                if (written.Bond is string summary) bond.Summary = summary;
                bond.Plot = new Plot(written.Plot, length, 0, now);
                bond.Plots += 1;
            });
        }

        /// <summary>A plot call was made (whatever came of it): note when, and what it cost.</summary>
        public void Asked(string a, string b, DateTimeOffset now, double? cost)
        {
            Update(a, b, bond =>
            {
                bond.LastAsked = now;
                if (cost is double c) bond.Cost = (bond.Cost ?? 0) + c;
            });
        }

        /// <summary>Forget one pair.</summary>
        public void Forget(string key) => Bonds.Remove(key);

        /// <summary>Start one pair's storyline over: no chronicle, no moments, no stories, no memory,
        /// as if they had only just met, though their time together stays. The chat
        /// log is not read back in again.</summary>
        public void ResetStory(string key)
        {
            if (!Bonds.TryGetValue(key, out var bond)) return;
            bond.Chronicle = null; bond.Moments = new(); bond.Tally = new(); bond.Met = null; bond.Seeded = true;
            bond.Facts = new(); bond.Days = new(); bond.Record = new(); bond.DiaryAt = null; bond.MemorySeeded = null;
            bond.Summary = null; bond.Plot = null; bond.LastPlot = null; bond.Plots = 0; bond.Recent = new(); bond.LastAsked = null;
        }

        public void ResetAllStories() { foreach (var key in Bonds.Keys.ToList()) ResetStory(key); }

        /// <summary>Pairs with the most time together first.</summary>
        public List<Bond> Closest => Bonds.Values
            .OrderByDescending(b => b.Together).ThenBy(b => string.Concat(b.Names), StringComparer.Ordinal).ToList();

        public override bool Equals(object? obj) => obj is Book o && o.Bonds.Count == Bonds.Count
            && Bonds.All(kv => o.Bonds.TryGetValue(kv.Key, out var other) && other.Equals(kv.Value));
        public override int GetHashCode() => Bonds.Count;
    }

    // MARK: Asking for a plot

    /// <summary>What the model sent back: a new bond line (optional), the plot, and
    /// their storyline rewritten to take in what happened since (optional).</summary>
    public sealed record Written(string? Bond, string Plot, string? Story = null);

    public static readonly IReadOnlyList<string> Placeholders = new[]
    {
        "speaker", "speakerKind", "speakerPersona", "listener", "listenerKind", "listenerPersona",
        "together", "bond", "lastPlot", "recent", "length",
        "today", "story", "since", "storyWords",
    };

    /// <summary>The answer is about 200 tokens; the rest is room for a model that thinks first.</summary>
    public const int PlotMaxTokens = 1000;

    /// <summary>The system side of the plot call: short, so the user prompt carries the work.</summary>
    public static string PlotSystemPrompt => Shared.PromptIn(Languages.Current, "plotSystem", EnglishPlotSystemPrompt);
    public static string PlotPromptIn(Language l) => Shared.PromptIn(l, "plot", EnglishPlotPrompt);
    public static string DefaultPlotPrompt => PlotPromptIn(Languages.Current);

    public const string EnglishPlotSystemPrompt = "You write tiny, playful stories for small characters. Follow the answer format exactly.";

    /// <summary>One call, one small answer: the story for a pair's next few conversations.</summary>
    public const string EnglishPlotPrompt =
        "Do not write their conversations. Write only the three lines described at the end.\n" +
        "\n" +
        "Two small creatures live on the edges of a computer screen and have shared it for {together}.\n" +
        "{speaker}, {speakerKind}: {speakerPersona}\n" +
        "{listener}, {listenerKind}: {listenerPersona}\n" +
        "How they get on so far: {bond}\n" +
        "Their story so far: {story}\n" +
        "Their last story: {lastPlot}\n" +
        "What they have lived through since (today is {today}):\n" +
        "{since}\n" +
        "What they said lately:\n" +
        "{recent}\n" +
        "\n" +
        "Think up what happens between them over their next {length} conversations: a small plot (a rivalry, a secret, " +
        "a favour owed, a shared plan, a misunderstanding, a crush), true to both of them, growing from how they get on " +
        "and from their story so far: it may bring back something that happened, and it never contradicts it.\n" +
        "\n" +
        "Answer with exactly these three lines and nothing else:\n" +
        "BOND: how they get on now, at most 15 words\n" +
        "PLOT: the story to play out, at most 30 words\n" +
        "STORY: their story so far, rewritten to take in what they have lived through since, at most {storyWords} words; " +
        "keep what matters most from before, with dates rather than \"today\" or \"yesterday\"";

    /// <summary>The values for the plot prompt. <paramref name="a"/> and <paramref name="b"/> are (name, kind, persona).
    /// <paramref name="story"/>: how much of their history to tell, from the settings; null when storylines
    /// are off, and the prompt says none is kept.</summary>
    public static Dictionary<string, string> PlotValues(Bond bond, (string Name, string Kind, string Persona) a,
                                                        (string Name, string Kind, string Persona) b, int length,
                                                        Telling? story = null, DateTimeOffset? now = null)
    {
        var at = now ?? DateTimeOffset.Now;
        var told = story is Telling t ? History(bond, t, at) : ((string Story, string Since)?)null;
        var values = BaseValues(bond, a, b, length);
        values["today"] = Day(at);
        values["story"] = told?.Story ?? L10n.Tr("(not kept)");
        values["since"] = told?.Since ?? L10n.Tr("(not kept)");
        values["storyWords"] = (story?.Words ?? StoryWords).ToString(System.Globalization.CultureInfo.InvariantCulture);
        return values;
    }

    private static Dictionary<string, string> BaseValues(Bond bond, (string Name, string Kind, string Persona) a,
                                                        (string Name, string Kind, string Persona) b, int length) => new()
    {
        ["speaker"] = a.Name, ["speakerKind"] = Banter.Spoken(a.Kind), ["speakerPersona"] = Banter.Persona(a.Persona),
        ["listener"] = b.Name, ["listenerKind"] = Banter.Spoken(b.Kind), ["listenerPersona"] = Banter.Persona(b.Persona),
        ["together"] = Duration(bond.Together),
        ["bond"] = bond.Summary ?? L10n.Tr("they have not really made their minds up about each other yet"),
        ["lastPlot"] = bond.LastPlot ?? L10n.Tr("none yet; this is their first"),
        ["recent"] = bond.Recent.Count == 0 ? L10n.Tr("(nothing yet)") : string.Join("\n", bond.Recent.Select(l => $"{l.Speaker}: {l.Text}")),
        ["length"] = length.ToString(System.Globalization.CultureInfo.InvariantCulture),
    };

    /// <summary>The two lines out of the model's answer. Null when there is no plot in it.</summary>
    public static Written? Parse(string raw)
    {
        var text = raw;
        var close = text.IndexOf("</think>", StringComparison.Ordinal);
        if (close >= 0) text = text[(close + "</think>".Length)..];
        var found = new Dictionary<string, string>();
        foreach (var line in text.Split('\n', '\r'))
        {
            var bare = line.Trim(' ', '\t').Trim('*', '#', '-', '_', ' ');
            foreach (var label in new[] { "BOND:", "PLOT:", "STORY:" })
            {
                if (found.ContainsKey(label) || !bare.ToUpperInvariant().StartsWith(label, StringComparison.Ordinal)) continue;
                // The storyline is longer than the other two: room for a few hundred words, trimmed later to the setting.
                var value = Clean(bare[label.Length..], label == "STORY:" ? 2000 : 240);
                if (value.Length > 0) found[label] = value;
            }
        }
        return found.TryGetValue("PLOT:", out var plot)
            ? new Written(found.GetValueOrDefault("BOND:"), plot, found.GetValueOrDefault("STORY:")) : null;
    }

    private static string Clean(string value, int maxLength = 240)
    {
        var v = value.Trim('*', ' ', '\t');
        var opens = new[] { '"', '“', '\'' };
        var closes = new[] { '"', '”', '\'' };
        while (v.Length > 1 && opens.Contains(v[0]) && closes.Contains(v[^1])) v = v[1..^1].Trim(' ', '\t');
        if (v.Length > maxLength) v = v[..maxLength].Trim(' ', '\t') + "…";
        return v;
    }

    // MARK: Using it

    /// <summary>What goes into <paramref name="speaker"/>'s prompt about <paramref name="other"/>: the bond and, if one is
    /// running, the plot and which part of it this is. Empty for strangers.</summary>
    public static string Context(Bond? bond, string speaker, string other)
    {
        if (bond is null || (bond.Summary is null && bond.Plot is null)) return "";
        var parts = new List<string> { L10n.Tr("You and %@ have shared this screen for %@.", other, Duration(bond.Together)) };
        if (bond.Summary is string summary) parts.Add(L10n.Tr("How you get on: %@", summary));
        if (bond.Plot is Plot plot)
        {
            var part = Math.Min(plot.Told + 1, plot.Length);
            parts.Add(L10n.Tr("What is going on between you (part %d of %d): %@", part, plot.Length, plot.Text));
            parts.Add(part == plot.Length
                ? L10n.Tr("This is the last part: let your line bring it to an end.")
                : L10n.Tr("Let it colour your line and move the story on a little; never explain it."));
        }
        return string.Join(" ", parts);
    }

    /// <summary>Put <paramref name="context"/> into a rendered system prompt: where the template says
    /// <c>{relationship}</c>, or after it when the template does not mention it.</summary>
    public static string WithRelationship(string template, IReadOnlyDictionary<string, string> values, string context)
    {
        if (template.Contains("{relationship}", StringComparison.Ordinal))
        {
            var merged = values.ToDictionary(kv => kv.Key, kv => kv.Value);
            merged["relationship"] = context;
            return Banter.Render(template, merged);
        }
        var rendered = Banter.Render(template, values);
        return context.Length == 0 ? rendered : rendered + "\n" + context;
    }

    /// <summary>"40 minutes", "3 hours", "2 days", for people and for prompts.</summary>
    public static string Duration(double seconds)
    {
        var minutes = (int)(seconds / 60);
        if (minutes < 1) return L10n.Tr("a moment");
        if (minutes < 60) return L10n.TrCount(minutes, "minute", "minutes");
        var hours = minutes / 60;
        if (hours < 24) return L10n.TrCount(hours, "hour", "hours");
        return L10n.TrCount(hours / 24, "day", "days");
    }

    /// <summary>The book on disk: <c>bonds.json</c> in a folder, rewritten whole on each save,
    /// in the macOS app's format.</summary>
    public sealed class Store
    {
        private static readonly JsonSerializerOptions Options = new(JsonLines.Options) { WriteIndented = true };

        public string Directory { get; }
        public Store(string directory) { Directory = directory; }
        public string File => Path.Combine(Directory, "bonds.json");

        public Book Load()
        {
            try
            {
                if (!System.IO.File.Exists(File)) return new Book();
                return JsonSerializer.Deserialize<Book>(System.IO.File.ReadAllText(File), Options) ?? new Book();
            }
            catch (Exception e) when (e is JsonException or IOException or NotSupportedException) { return new Book(); }
        }

        public void Save(Book book)
        {
            System.IO.Directory.CreateDirectory(Directory);
            var temp = File + ".tmp";
            System.IO.File.WriteAllText(temp, JsonSerializer.Serialize(book, Options), new System.Text.UTF8Encoding(false));
            System.IO.File.Move(temp, File, true);
        }
    }
}

using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Ledgelings.Core;

/// <summary>
/// Chat with the creatures (SPEC §7.18), the Mac's <c>OwnerChat.swift</c>: the owner writes to one creature, or to
/// everyone on screen, in a paper window on Ctrl+Alt+C, and they answer in their own persona and kind.
///
/// Each character keeps a short memory of these talks: its last few exchanges with the owner word for word and a
/// summary of the older ones, both sent with its next chat prompt. When an exchange falls out of the kept ones the
/// summary is rewritten to take it in (one call, priced as <see cref="Spend.Purpose.Chat"/>). Nothing here calls a model.
/// The prompts are the Mac's, in the shared text (<c>chatSystem</c>, <c>chatMessage</c>, <c>chatSummary</c>).
/// </summary>
public static class OwnerChat
{
    // MARK: How long an answer is

    public enum Length { Short, Medium, Long }

    public static string Code(this Length l) => l switch { Length.Medium => "medium", Length.Long => "long", _ => "short" };
    public static Length? LengthNamed(string? code) => code switch { "short" => Length.Short, "medium" => Length.Medium, "long" => Length.Long, _ => null };

    public static string Title(this Length l) => L10n.Tr(l switch
    {
        Length.Medium => "Medium: a few sentences",
        Length.Long => "Long: a paragraph",
        _ => "Short: a line",
    });

    /// <summary>At most this many words, as the prompt asks.</summary>
    public static int Words(this Length l) => l switch { Length.Medium => 60, Length.Long => 120, _ => 25 };
    /// <summary>Room for the answer, thinking included.</summary>
    public static int MaxTokens(this Length l) => l switch { Length.Medium => 900, Length.Long => 1400, _ => 600 };
    /// <summary>The longest answer shown, in characters; a longer one ends on a whole sentence.</summary>
    public static int MaxCharacters(this Length l) => l switch { Length.Medium => 480, Length.Long => 900, _ => 220 };

    public const int DefaultEveryone = 3, EveryoneMin = 1, EveryoneMax = 8;
    public const int DefaultExchanges = 10, ExchangesMin = 0, ExchangesMax = 50;
    /// <summary>The summary of the older talks is kept to about this many words.</summary>
    public const int SummaryWords = 80, SummaryMaxTokens = 700;

    // MARK: Who answers "Everyone"

    /// <summary>Someone who could answer: a name, and whether it is asleep.</summary>
    public sealed record Candidate(string Name, bool Asleep);

    /// <summary>Who answers a message to everyone, in the order they answer: at most <paramref name="count"/>, each once,
    /// the awake ones in a random order first, then sleepers woken by it.</summary>
    public static IReadOnlyList<string> Answerers(IEnumerable<Candidate> candidates, int count, Random rng)
    {
        var seen = new HashSet<string>();
        var unique = candidates.Where(c => seen.Add(c.Name)).ToList();
        var awake = unique.Where(c => !c.Asleep).OrderBy(_ => rng.Next()).ToList();
        var asleep = unique.Where(c => c.Asleep).OrderBy(_ => rng.Next()).ToList();
        return awake.Concat(asleep).Take(Math.Max(0, count)).Select(c => c.Name).ToList();
    }

    // MARK: Memory

    /// <summary>One message from the owner and the answer it got.</summary>
    public sealed record Exchange
    {
        public DateTimeOffset Time { get; init; }
        /// <summary>What the owner wrote.</summary>
        public string Said { get; init; } = "";
        public string Answer { get; init; } = "";
        /// <summary>Written to everyone, not to this one alone.</summary>
        public bool Everyone { get; init; }
    }

    /// <summary>What one character remembers of talking with the owner.</summary>
    public sealed class Memory
    {
        public List<Exchange> Exchanges { get; set; } = new();
        /// <summary>The older talks in a few sentences, as the model put them.</summary>
        public string? Summary { get; set; }
        public DateTimeOffset? SummaryAt { get; set; }
        /// <summary>What writing the summary has cost, in US dollars.</summary>
        public double? SummaryCost { get; set; }

        [JsonIgnore] public bool IsEmpty => Exchanges.Count == 0 && string.IsNullOrEmpty(Summary);
    }

    /// <summary>Everyone's memory of the owner, by character name.</summary>
    public sealed class Book
    {
        public Dictionary<string, Memory> Memories { get; set; } = new();

        public Memory? MemoryOf(string name) => Memories.GetValueOrDefault(name);

        /// <summary>Keep <paramref name="exchange"/> among <paramref name="name"/>'s last <paramref name="keep"/>; what no
        /// longer fits comes back, oldest first, for the summary to take in.</summary>
        public IReadOnlyList<Exchange> Remember(string name, Exchange exchange, int keep)
        {
            if (!Memories.TryGetValue(name, out var memory)) Memories[name] = memory = new Memory();
            memory.Exchanges.Add(exchange);
            var over = Math.Max(0, memory.Exchanges.Count - Math.Max(0, keep));
            var dropped = memory.Exchanges.Take(over).ToList();
            memory.Exchanges.RemoveRange(0, over);
            return dropped;
        }

        /// <summary>Every character down to its last <paramref name="keep"/> exchanges; what was dropped, by name.</summary>
        public Dictionary<string, List<Exchange>> Keep(int keep)
        {
            var dropped = new Dictionary<string, List<Exchange>>();
            foreach (var (name, memory) in Memories)
            {
                var over = Math.Max(0, memory.Exchanges.Count - Math.Max(0, keep));
                if (over == 0) continue;
                dropped[name] = memory.Exchanges.Take(over).ToList();
                memory.Exchanges.RemoveRange(0, over);
            }
            return dropped;
        }

        /// <summary>The summary rewritten (null: the call came back with nothing; only its cost is kept).</summary>
        public void Summarised(string name, string? summary, DateTimeOffset now, double? cost)
        {
            if (!Memories.TryGetValue(name, out var memory)) Memories[name] = memory = new Memory();
            if (!string.IsNullOrEmpty(summary)) { memory.Summary = summary; memory.SummaryAt = now; }
            if (cost is double c) memory.SummaryCost = (memory.SummaryCost ?? 0) + c;
        }

        public void Forget(string name) => Memories.Remove(name);
        public void ForgetAll() => Memories.Clear();

        /// <summary>Names with something remembered, A to Z.</summary>
        [JsonIgnore] public IReadOnlyList<string> Names => Memories.Where(m => !m.Value.IsEmpty).Select(m => m.Key).OrderBy(n => n, StringComparer.Ordinal).ToList();
    }

    /// <summary>The book on disk: <c>owner-chats.json</c> beside <c>bonds.json</c>, in the Mac's format.</summary>
    public sealed class Store
    {
        private static readonly JsonSerializerOptions Options = new(JsonLines.Options) { WriteIndented = true };

        public string Directory { get; }
        public Store(string directory) { Directory = directory; }
        public string File => Path.Combine(Directory, "owner-chats.json");

        /// <summary>The book as saved; an empty one when there is none, or it cannot be read.</summary>
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

    /// <summary>What a character remembers, for its prompt: the summary, then the kept exchanges oldest first, each
    /// with its day. "" when there is nothing.</summary>
    public static string MemoryBlock(Memory? memory, DateTimeOffset now)
    {
        if (memory is null || memory.IsEmpty) return "";
        var parts = new List<string>();
        if (!string.IsNullOrEmpty(memory.Summary)) parts.Add(L10n.Tr("What you remember of earlier talks with the owner: %@", memory.Summary));
        if (memory.Exchanges.Count > 0)
        {
            var told = memory.Exchanges.Select(e => L10n.Tr("%@, the owner: \"%@\"; you: \"%@\"", When(e.Time, now), e.Said, e.Answer));
            parts.Add(L10n.Tr("Your last talks with the owner, oldest first: %@.", string.Join(" · ", told)));
        }
        return string.Join("\n", parts);
    }

    /// <summary>"today 14:05", "yesterday 09:12", "3 Nov 18:40".</summary>
    public static string When(DateTimeOffset time, DateTimeOffset now)
    {
        var t = time.ToLocalTime();
        var clock = t.ToString("HH:mm", CultureInfo.InvariantCulture);
        var day = t.Date;
        if (day == now.ToLocalTime().Date) return L10n.Tr("today %@", clock);
        if (day == now.ToLocalTime().Date.AddDays(-1)) return L10n.Tr("yesterday %@", clock);
        return Bonds.Day(time) + " " + clock;
    }

    // MARK: The prompts

    public const string EnglishSystemPrompt = """
        You are {speaker}, {speakerKind}, living on the edge of a computer screen. {speakerPersona}
        The person who owns this computer has written to you in a little chat window. Answer them yourself, in your own voice and manner, at most {words} words.
        You may tease them, but you are fond of them. Never say you are an AI, a program or a language model.
        {memory}
        Output only your answer. No quotes, no name prefix, no explanation.
        """;

    public const string EnglishMessagePrompt = """
        Right now: {situation}
        {others}The owner writes {to}: "{message}"
        Your answer:
        """;

    public const string EnglishSummaryPrompt = """
        {speaker}, {speakerKind}, lives on the edge of a computer screen and chats now and then with the person who owns the computer. Keep what {speaker} remembers of those talks short and true.
        What it remembered until now: {summary}
        Older talks to take in, oldest first:
        {talks}

        Write what {speaker} remembers now, in at most {words} words: what the owner told it about themselves and their days, promises, plans, likes, and how they get on. Dates rather than "today". Only the text, nothing else.
        """;

    public static string SystemPrompt => Shared.Prompt("chatSystem", EnglishSystemPrompt);
    public static string MessagePrompt => Shared.Prompt("chatMessage", EnglishMessagePrompt);
    public static string SummaryPrompt => Shared.Prompt("chatSummary", EnglishSummaryPrompt);

    public static readonly IReadOnlyList<string> Placeholders = new[] { "speaker", "speakerKind", "speakerPersona", "words", "memory", "situation", "others", "to", "message" };

    /// <summary>The values for one creature's answer. <paramref name="earlier"/>: what the ones before it said to the
    /// same message (to everyone), so it can react and not repeat.</summary>
    public static Dictionary<string, string> Values(string speaker, string kind, string persona, Length length, string memory,
                                                    string situation, string message, bool everyone, IReadOnlyList<(string Name, string Text)> earlier)
    {
        var others = earlier.Count == 0 ? ""
            : L10n.Tr("The others have answered already: %@. Say something of your own: react to them if you like, never the same answer.",
                      string.Join("; ", earlier.Select(e => $"{e.Name}: \"{e.Text}\""))) + "\n";
        return new Dictionary<string, string>
        {
            ["speaker"] = speaker, ["speakerKind"] = Banter.Spoken(kind.Length == 0 ? Banter.DefaultKind : kind), ["speakerPersona"] = Banter.Persona(persona),
            ["words"] = length.Words().ToString(CultureInfo.InvariantCulture), ["memory"] = memory, ["situation"] = situation,
            ["others"] = others, ["to"] = everyone ? L10n.Tr("to all of you") : L10n.Tr("to you"), ["message"] = message,
        };
    }

    /// <summary>The system and user prompt for one answer, from the shipped templates in the current language.</summary>
    public static (string System, string User) Prompt(IReadOnlyDictionary<string, string> values) =>
        (Banter.Render(SystemPrompt, values).Replace("\n\n", "\n"), Banter.Render(MessagePrompt, values));

    /// <summary>The summary's prompt: the old summary and the exchanges that fell out of memory.</summary>
    public static string SummaryPromptFor(string speaker, string kind, string? summary, IReadOnlyList<Exchange> dropped, DateTimeOffset now)
    {
        var talks = string.Join("\n", dropped.Select(e => "- " + L10n.Tr("%@, the owner: \"%@\"; you: \"%@\"", When(e.Time, now), e.Said, e.Answer)));
        return Banter.Render(SummaryPrompt, new Dictionary<string, string>
        {
            ["speaker"] = speaker, ["speakerKind"] = Banter.Spoken(kind.Length == 0 ? Banter.DefaultKind : kind),
            ["summary"] = string.IsNullOrEmpty(summary) ? L10n.Tr("(nothing yet)") : summary, ["talks"] = talks,
            ["words"] = SummaryWords.ToString(CultureInfo.InvariantCulture),
        });
    }

    /// <summary>A model's answer as the window and the bubble show it: no thinking, no "Name:" prefix, no wrapping
    /// quotes, its lines joined, at most <paramref name="length"/>'s characters ending on a whole sentence.</summary>
    public static string Clean(string raw, string speaker, Length length, bool cut = false)
    {
        var text = raw;
        var close = text.IndexOf("</think>", StringComparison.Ordinal);
        if (close >= 0) text = text[(close + "</think>".Length)..];
        else if (text.Contains("<think>", StringComparison.Ordinal)) return "";
        var joined = string.Join(" ", text.Split('\n', '\r').Select(l => l.Trim()).Where(l => l.Length > 0));
        return Banter.CleanLine(joined, speaker, length.MaxCharacters(), cut);
    }

    /// <summary>The summary as the model wrote it, cleaned; null for nothing.</summary>
    public static string? CleanSummary(string raw)
    {
        var text = raw;
        var close = text.IndexOf("</think>", StringComparison.Ordinal);
        if (close >= 0) text = text[(close + "</think>".Length)..];
        var joined = string.Join(" ", text.Split('\n', '\r').Select(l => l.Trim()).Where(l => l.Length > 0));
        var trimmed = joined.Trim('"', '“', '”', '«', '»', ' ');
        return trimmed.Length == 0 ? null : trimmed[..Math.Min(trimmed.Length, 1200)];
    }

    // MARK: The window's controls

    /// <summary>Every control on the chat window that acts: a pixel picture each, and a tag naming the action and its
    /// key (AGENTS.md §4), Windows' keys.</summary>
    public enum Button { Send, Everyone, Close, Settings }

    public static string Tooltip(this Button b) => b switch
    {
        Button.Send => L10n.Tr("Send (%@)", "Enter"),
        Button.Everyone => L10n.Tr("Write to everyone (%@)", "Ctrl+0"),
        Button.Close => L10n.Tr("Close the chat (%@)", "Esc"),
        _ => L10n.Tr("Chat settings (%@)", "Ctrl+,"),
    };

    /// <summary>11×11, <c>#</c> ink, <c>.</c> paper; the Mac's pictures.</summary>
    public static IReadOnlyList<string> Icon(this Button b) => b switch
    {
        Button.Send => new[] { "...........", "#..........", "###........", "#.###......", "#...###....", "#.....####.", "#...###....", "#.###......", "###........", "#..........", "..........." },
        Button.Everyone => new[] { "...........", "...........", "...........", "...###.....", "...#.#.....", "##.###.##..", "#.#...#.#..", "###...###..", "##.#.#.##..", "...........", "..........." },
        Button.Close => new[] { "...........", ".#.......#.", "..#.....#..", "...#...#...", "....#.#....", ".....#.....", "....#.#....", "...#...#...", "..#.....#..", ".#.......#.", "..........." },
        _ => new[] { "...........", "....###....", ".#.#...#.#.", "..#.....#..", ".#..###..#.", ".#..#.#..#.", ".#..###..#.", "..#.....#..", ".#.#...#.#.", "....###....", "..........." },
    };

    public static IReadOnlyList<Button> Buttons { get; } = Enum.GetValues<Button>();

    /// <summary>A creature's chip in the To: row: its sprite is the picture, this the tag.</summary>
    public static string WriteTo(string name, int? number) =>
        number is int n ? L10n.Tr("Write to %@ (%@)", name, "Ctrl+" + n) : L10n.Tr("Write to %@", name);

    /// <summary>The Tools tile and the Creature Actions button: a speech bubble with three dots.</summary>
    public static readonly IReadOnlyList<string> SheetIcon = new[] { "...........", "#########..", "#.......#..", "#.......#..", "#.#.#.#.#..", "#.......#..", "#.......#..", "####.####..", "...#.#.....", "...##......", "...#......." };

    /// <summary>"Blocky is thinking…".</summary>
    public static string Thinking(string name) => L10n.Tr("%@ is thinking…", name);

    /// <summary>Shown in the window when no model can answer, with a button to the settings.</summary>
    public static string NoModel => L10n.Tr("Nobody can answer: they need a model. Choose LM Studio or OpenRouter as the Brain, with its key, in Settings › Talk.");
}

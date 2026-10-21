using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Ledgelings.Core;

/// <summary>
/// A pair's long-term memory (SPEC §6.5.2.3): what two characters remember of each other in
/// every conversation, kept small enough to send with each line. The Mac's <c>Bonds+Memory.swift</c>.
///
/// Beside the chronicle (their story so far) a pair keeps a few <b>facts</b>
/// (a promise, a debt, a rivalry, each dated), a <b>record</b> of the games one
/// won against the other, and one <b>day</b> entry for each day they shared
/// anything: what they did, counted, the games' results, and a line the model
/// wrote about it. The days are for the owner to read (the Relationships
/// window); a prompt gets only today and yesterday.
///
/// <see cref="Memory"/> builds the block a prompt carries, cut to a budget in tokens:
/// what happened today goes in first, then the facts, the record, yesterday,
/// and the chronicle last, trimmed sentence by sentence. Nothing here calls a
/// model: the <b>diary</b> (<see cref="DiaryPrompt"/>, <see cref="ParseDiary"/>) is the app's one call a
/// pair, at the colony's nightfall, that rewrites the chronicle and the facts
/// and writes the day's line. Without a model the counts and results still
/// accumulate, and facts come from deeds and games.
/// </summary>
public static partial class Bonds
{
    /// <summary>Something worth remembering. <paramref name="Source"/>: who wrote it, <c>note</c> (a line's NOTE:), <c>deed</c>, <c>diary</c>, <c>seed</c>.</summary>
    public sealed record Fact(string Text, DateTimeOffset Time, string Source);

    /// <summary>One day they shared anything: the Mac's <c>Bonds.Day</c> (a C# class cannot share
    /// <see cref="Day(DateTimeOffset)"/>'s name).</summary>
    public sealed class DayEntry
    {
        /// <summary>The user's calendar day, <c>2026-10-20</c>.</summary>
        public string Day { get; set; } = "";
        /// <summary>What they shared, by <see cref="MomentKind"/>.</summary>
        public Dictionary<string, int> Counts { get; set; } = new();
        /// <summary>Each game's result in a few words: "Soccer: won by Boo, 3-2".</summary>
        public List<string> Games { get; set; } = new();
        /// <summary>The day in one line, as the model put it.</summary>
        public string? Line { get; set; }

        public DayEntry() { }
        public DayEntry(string day) { Day = day; }

        public override bool Equals(object? obj) => obj is DayEntry o && o.Day == Day && Bond.SameCounts(o.Counts, Counts)
            && o.Games.SequenceEqual(Games) && o.Line == Line;
        public override int GetHashCode() => Day.GetHashCode(StringComparison.Ordinal);
    }

    /// <summary>The facts a pair keeps by default.</summary>
    public const int MemoryFacts = 5;
    /// <summary>Days of timeline kept by default.</summary>
    public const int MemoryDays = 60;
    /// <summary>Tokens of memory a prompt carries by default.</summary>
    public const int MemoryTokens = 150;

    /// <summary>A rough count of tokens: a token is about four bytes of UTF-8, which is
    /// cautious for Russian, where a letter takes two.</summary>
    public static int Tokens(string text) => (Encoding.UTF8.GetByteCount(text) + 3) / 4;

    /// <summary><c>2026-10-20</c>, on the user's calendar.</summary>
    public static string DayKey(DateTimeOffset date) => date.ToLocalTime().ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

    /// <summary>The day a key names, at its start, or null.</summary>
    public static DateTimeOffset? DateOfDay(string key)
    {
        if (!DateTime.TryParseExact(key, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d)) return null;
        var local = DateTime.SpecifyKind(d, DateTimeKind.Local);
        return new DateTimeOffset(local, TimeZoneInfo.Local.GetUtcOffset(local));
    }

    /// <summary>A moment is counted on its day, and a game's result goes in the record.</summary>
    internal static void Keep(Moment moment, Bond bond)
    {
        var key = DayKey(moment.Time);
        if (!bond.Days.Any(d => d.Day == key))
        {
            bond.Days.Add(new DayEntry(key));
            bond.Days = bond.Days.OrderBy(d => d.Day, StringComparer.Ordinal).ToList();
        }
        if (bond.Days.FirstOrDefault(d => d.Day == key) is not DayEntry day) return;
        day.Counts[moment.Kind] = day.Counts.GetValueOrDefault(moment.Kind) + 1;
        if (moment.Kind != MomentKind.Play) return;
        if (GameLine(moment) is string r) day.Games.Add(r);
        if (moment.Detail is not string kind || moment.Winners is not List<string> winners || bond.Names.Count != 2) return;
        string a = bond.Names[0], b = bond.Names[1];
        bool aWon = winners.Contains(a), bWon = winners.Contains(b);
        if (aWon != bWon)
        {
            var k = $"{kind}|{(aWon ? a : b)}";
            bond.Record[k] = bond.Record.GetValueOrDefault(k) + 1;
        }
        else if (winners.Count == 0)
        {
            var k = $"{kind}|=";
            bond.Record[k] = bond.Record.GetValueOrDefault(k) + 1;
        }
    }

    // MARK: Games in words

    /// <summary>How a game ended: "won by Boo, 3-2", "a draw, 2-2", "Blocky asked for it"; null when there is nothing to say.</summary>
    public static string? Result(Moment moment)
    {
        var parts = new List<string>();
        if (moment.Winners is List<string> winners)
        {
            if (winners.Count == 0) parts.Add(moment.Score is string s ? L10n.Tr("a draw, %@", s) : L10n.Tr("a draw"));
            else
            {
                var who = string.Join(", ", winners);
                parts.Add(moment.Score is string s ? L10n.Tr("won by %@, %@", who, s) : L10n.Tr("won by %@", who));
            }
        }
        else if (moment.Score is string score)
        {
            parts.Add(score);
        }
        if (moment.Asked is string asked) parts.Add(L10n.Tr("%@ asked for it", asked));
        return parts.Count == 0 ? null : string.Join("; ", parts);
    }

    /// <summary>A game for a day's entry: "Soccer: won by Boo, 3-2".</summary>
    internal static string GameLine(Moment moment)
    {
        var game = Plays.FromRaw(moment.Detail) is Plays.Kind k ? Deeds.Offer.Game(k).Word : Plays.Name(moment.Detail);
        return Result(moment) is string r ? L10n.Tr("%@: %@", game, r) : game;
    }

    /// <summary>Their record, game by game: "Soccer: Boo 3, Blocky 1, 1 draw"; null before any game was won.</summary>
    public static string? RecordLine(Bond bond)
    {
        var games = new List<string>();
        foreach (var kind in Plays.AllKinds)
        {
            var wins = bond.Names.Where(n => bond.Record.ContainsKey($"{kind.Raw()}|{n}"))
                .Select(n => (Name: n, Count: bond.Record[$"{kind.Raw()}|{n}"])).OrderByDescending(w => w.Count).ToList();
            var draws = bond.Record.GetValueOrDefault($"{kind.Raw()}|=");
            if (wins.Count == 0 && draws == 0) continue;
            var parts = wins.Select(w => $"{w.Name} {w.Count}").ToList();
            if (draws > 0) parts.Add(L10n.TrCount(draws, "draw", "draws"));
            games.Add(L10n.Tr("%@: %@", Deeds.Offer.Game(kind).Word, string.Join(", ", parts)));
        }
        return games.Count == 0 ? null : string.Join("; ", games);
    }

    /// <summary>The last game <paramref name="name"/> lost to the other of the pair, for a rematch.</summary>
    public static Plays.Kind? LastLost(string name, Bond? bond)
    {
        if (bond?.Names.FirstOrDefault(n => n != name) is not string other) return null;
        var lost = bond.Moments.LastOrDefault(m => m.Kind == MomentKind.Play && m.Winners is { } w && w.Contains(other) && !w.Contains(name));
        return lost is null ? null : Plays.FromRaw(lost.Detail);
    }

    /// <summary>A day in words, without a model: "5 talks, 1 tea party; Soccer: won by Boo, 3-2".</summary>
    public static string DayLine(DayEntry day)
    {
        var counted = Tallied(day.Counts);
        var games = string.Join("; ", day.Games);
        return string.Join("; ", new[] { counted, games }.Where(s => s.Length > 0));
    }

    // MARK: What a prompt carries

    /// <summary>What <paramref name="speaker"/> remembers of <paramref name="other"/>, at most <paramref name="budget"/> tokens: what they did
    /// today, the facts, their games, yesterday, how they met and their story,
    /// in that order of need. Empty for strangers or a budget of 0.</summary>
    public static string Memory(Bond? bond, string speaker, string other, int budget, DateTimeOffset? at = null)
    {
        if (bond is null || budget <= 0) return "";
        var now = at ?? DateTimeOffset.Now;
        var today = DayKey(now);
        var yesterday = DayKey(now.AddDays(-1));
        var parts = new SortedDictionary<int, string>();          // by place in the text
        var used = 0;
        bool Fits(string text) => used + Tokens(text) + 1 <= budget;
        void Take(string? text, int place)
        {
            if (string.IsNullOrEmpty(text) || !Fits(text)) return;
            parts[place] = text;
            used += Tokens(text) + 1;
        }
        var todays = bond.Days.FirstOrDefault(d => d.Day == today);
        Take(todays is null ? null : L10n.Tr("Today together: %@.", DayLine(todays)), 6);
        // The facts, newest first, as many as fit.
        var remembered = new List<string>();
        foreach (var fact in Enumerable.Reverse(bond.Facts))
        {
            // A fact's own full stop would make two with the one the list ends with.
            var bare = fact.Text.Trim('.', ';', '·', ' ', '\t');
            var text = fact.Source is "diary" or "seed" ? bare : bare + " (" + Day(fact.Time) + ")";
            var all = L10n.Tr("You remember: %@.", string.Join(" · ", remembered.Append(text)));
            if (!Fits(all)) break;
            remembered.Add(text);
        }
        if (remembered.Count > 0) Take(L10n.Tr("You remember: %@.", string.Join(" · ", remembered)), 4);
        Take(RecordLine(bond) is string record ? L10n.Tr("Games between you: %@.", record) : null, 3);
        var yesterdays = bond.Days.FirstOrDefault(d => d.Day == yesterday);
        Take(yesterdays is null ? null : L10n.Tr("Yesterday: %@.", yesterdays.Line ?? DayLine(yesterdays)), 5);
        if (bond.Met is DateTimeOffset met && bond.Tally.Count > 0)
            Take(L10n.Tr("You and %@ first met on %@; all told: %@.", other, Day(met), Tallied(bond.Tally)), 1);
        if (bond.Chronicle is string chronicle && chronicle.Length > 0)
        {
            // As many of the story's newest whole sentences as there is room for; a
            // sentence cut short says nothing, so none is sent rather than half of one.
            var room = budget - used - 1;
            var kept = new List<string>();
            foreach (var sentence in Enumerable.Reverse(Sentences(chronicle)))
            {
                var text = L10n.Tr("Your story so far: %@", string.Join(" ", kept.Prepend(sentence)));
                if (Tokens(text) > room) break;
                kept.Insert(0, sentence);
            }
            if (kept.Count > 0) Take(L10n.Tr("Your story so far: %@", string.Join(" ", kept)), 2);
        }
        return string.Join(" ", parts.Values);
    }

    // MARK: Their day, from one side

    /// <summary>What <paramref name="name"/> has done today with everyone, newest first, at most <paramref name="items"/>
    /// things: "played a game of soccer with Boo, Zed at 10:40 (won by Boo, 3-2); had tea
    /// with Unit 7 at 12:05". Talks are left out: there are too many. "" for none.</summary>
    public static string DaySoFar(string name, Book book, int items, DateTimeOffset? at = null)
    {
        if (items <= 0) return "";
        var now = at ?? DateTimeOffset.Now;
        var day = now.ToLocalTime().Date;
        var seen = new List<(Moment Moment, List<string> With)>();
        foreach (var bond in book.Bonds.Values.Where(b => b.Names.Contains(name)))
        {
            if (bond.Names.FirstOrDefault(n => n != name) is not string other) continue;
            foreach (var m in bond.Moments.Where(m => m.Kind != MomentKind.Talk && m.Time.ToLocalTime().Date == day))
            {
                if (m.Kind == MomentKind.Grab && m.Who != name) continue;
                // One game is a moment of every pair that played it: it is told once, with everyone.
                var k = seen.FindIndex(s => s.Moment.Kind == m.Kind && s.Moment.Detail == m.Detail
                                            && Math.Abs((s.Moment.Time - m.Time).TotalSeconds) < 120 && (m.Kind == MomentKind.Play || m.Kind == MomentKind.Grab));
                if (k >= 0)
                {
                    if (!seen[k].With.Contains(other)) seen[k].With.Add(other);
                    continue;
                }
                seen.Add((m, new List<string> { other }));
            }
        }
        var told = seen.OrderByDescending(s => s.Moment.Time).Take(items).Select(s =>
        {
            var m = s.Moment;
            var others = string.Join(", ", s.With);
            var time = m.Time.ToLocalTime().ToString("HH:mm", CultureInfo.InvariantCulture);
            switch (m.Kind)
            {
                case MomentKind.Play:
                    var played = L10n.Tr("played %@ with %@ at %@", Plays.Name(m.Detail), others, time);
                    return Result(m) is string r ? played + " (" + r + ")" : played;
                case MomentKind.Tea: return L10n.Tr("had tea with %@ at %@", others, time);
                case MomentKind.Flower:
                    var flower = Gifts.Name(m.Detail ?? "");
                    return m.Who == name ? L10n.Tr("gave %@ a %@ at %@", others, flower, time) : L10n.Tr("got a %@ from %@ at %@", flower, m.Who, time);
                case MomentKind.Plane:
                    return m.Who == name ? L10n.Tr("sent %@ a paper plane at %@", others, time) : L10n.Tr("got a paper plane from %@ at %@", m.Who, time);
                case MomentKind.Grab: return L10n.Tr("grabbed the cursor at %@", time);
                default: return "";
            }
        }).ToList();
        return told.Count == 0 ? "" : L10n.Tr("Your day so far: %@.", string.Join("; ", told));
    }

    // MARK: The diary

    /// <summary>What the model sends back for a pair's memory: their story rewritten,
    /// the facts worth keeping, and a line for each day (keyed <c>2026-10-20</c>; "" for
    /// a line that named no day).</summary>
    public sealed class Diary
    {
        public string? Story { get; set; }
        public List<string> Facts { get; set; } = new();
        public Dictionary<string, string> Days { get; set; } = new();
    }

    public const int DiaryMaxTokens = 1200;

    public static string DiarySystemPrompt => Shared.Prompt("diarySystem", EnglishDiarySystemPrompt);
    public const string EnglishDiarySystemPrompt = "You keep short, true memories for small characters. Follow the answer format exactly.";

    public static string DiaryPrompt => Shared.Prompt("diary", EnglishDiaryPrompt);
    public const string EnglishDiaryPrompt =
        "Two small creatures live on the edges of a computer screen. Keep their long-term memory of each other short and true.\n" +
        "{speaker}, {speakerKind}: {speakerPersona}\n" +
        "{listener}, {listenerKind}: {listenerPersona}\n" +
        "How they get on: {bond}\n" +
        "Their story so far: {story}\n" +
        "What they remember: {facts}\n" +
        "Games between them: {record}\n" +
        "What happened since their memory was last written (today is {today}):\n" +
        "{since}\n" +
        "Some of what they said:\n" +
        "{lines}\n" +
        "\n" +
        "Answer with these lines and nothing else:\n" +
        "STORY: their story so far, rewritten to take in what happened since, at most {storyWords} words; dates rather than \"today\"\n" +
        "FACT: one thing worth remembering for weeks (a promise, a debt, a secret, a rivalry, a liking), at most 12 words, with its date. Up to {factCount} FACT: lines in all: keep the old facts that still matter, drop what is settled. Events, never catchphrases.\n" +
        "DAY: {todayKey}: today in one line, at most 25 words";

    public static string SeedPrompt => Shared.Prompt("seed", EnglishSeedPrompt);
    public const string EnglishSeedPrompt =
        "Two small creatures live on the edges of a computer screen. Below is what passed between them over the last {days} days. Write their long-term memory of each other: short, true, in their own small world.\n" +
        "{speaker}, {speakerKind}: {speakerPersona}\n" +
        "{listener}, {listenerKind}: {listenerPersona}\n" +
        "How they get on: {bond}\n" +
        "Their story so far, as kept until now: {story}\n" +
        "Day by day, what they shared:\n" +
        "{digest}\n" +
        "Some of what they said, oldest first:\n" +
        "{lines}\n" +
        "\n" +
        "Answer with these lines and nothing else:\n" +
        "STORY: their story so far, at most {storyWords} words, with dates rather than \"today\"\n" +
        "FACT: one thing worth remembering for weeks (a promise, a debt, a secret, a rivalry, a liking), at most 12 words, with its date. Up to {factCount} FACT: lines. Events, never catchphrases.\n" +
        "DAY: one line for each day above, as \"DAY: 2026-10-19: what happened that day\", at most 20 words each";

    public static readonly IReadOnlyList<string> DiaryPlaceholders = new[]
    {
        "speaker", "speakerKind", "speakerPersona", "listener", "listenerKind", "listenerPersona",
        "bond", "story", "facts", "record", "today", "todayKey", "since", "lines",
        "storyWords", "factCount", "days", "digest",
    };

    /// <summary>The values shared by the diary and the seed prompts. <paramref name="a"/> and <paramref name="b"/> are (name, kind, persona).</summary>
    public static Dictionary<string, string> MemoryValues(Bond bond, (string Name, string Kind, string Persona) a,
                                                          (string Name, string Kind, string Persona) b,
                                                          IReadOnlyList<ChatLog.Line> lines, int words, int facts, DateTimeOffset? at = null)
    {
        var now = at ?? DateTimeOffset.Now;
        var shown = bond.Moments.Where(m => bond.DiaryAt is not DateTimeOffset d || m.Time > d).ToList();
        string Nothing() => L10n.Tr("(nothing yet)");
        return new Dictionary<string, string>
        {
            ["speaker"] = a.Name, ["speakerKind"] = Banter.Spoken(a.Kind), ["speakerPersona"] = Banter.Persona(a.Persona),
            ["listener"] = b.Name, ["listenerKind"] = Banter.Spoken(b.Kind), ["listenerPersona"] = Banter.Persona(b.Persona),
            ["bond"] = bond.Summary ?? L10n.Tr("they have not really made their minds up about each other yet"),
            ["story"] = bond.Chronicle ?? L10n.Tr("nothing yet; they have only just met"),
            ["facts"] = bond.Facts.Count == 0 ? Nothing() : string.Join(" · ", bond.Facts.Select(f => f.Text)),
            ["record"] = RecordLine(bond) ?? Nothing(),
            ["today"] = Day(now), ["todayKey"] = DayKey(now),
            ["since"] = shown.Count == 0 ? Nothing() : string.Join("\n", shown.Select(m => "- " + Day(m.Time) + ": " + Describe(m, bond.Names))),
            ["lines"] = lines.Count == 0 ? Nothing() : string.Join("\n", lines.Select(l => $"{l.Speaker}: {l.Text}")),
            ["storyWords"] = words.ToString(CultureInfo.InvariantCulture), ["factCount"] = facts.ToString(CultureInfo.InvariantCulture),
        };
    }

    private static readonly Regex Dated = new(@"^(\d{4}-\d{2}-\d{2})\s*[:—–-]?\s*(.*)$", RegexOptions.CultureInvariant);

    /// <summary>The diary's or the seed's answer; null when it holds none of the three lines.</summary>
    public static Diary? ParseDiary(string raw)
    {
        var text = raw;
        var close = text.IndexOf("</think>", StringComparison.Ordinal);
        if (close >= 0) text = text[(close + "</think>".Length)..];
        var output = new Diary();
        foreach (var line in text.Split(new[] { '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries))
        {
            var bare = line.Trim(' ', '\t').Trim('*', '#', '-', '_', ' ');
            var upper = bare.ToUpperInvariant();
            string Value(string label) => CleanValue(bare[label.Length..]);
            if (upper.StartsWith("STORY:", StringComparison.Ordinal) && output.Story is null)
            {
                var v = Value("STORY:");
                if (v.Length > 0) output.Story = v.Length > 2000 ? v[..2000] : v;
            }
            else if (upper.StartsWith("FACT:", StringComparison.Ordinal) || upper.StartsWith("FACTS:", StringComparison.Ordinal))
            {
                var v = Value(upper.StartsWith("FACTS:", StringComparison.Ordinal) ? "FACTS:" : "FACT:");
                foreach (var one in v.Split('·').Select(CleanValue).Where(o => o.Length > 0))
                    output.Facts.Add(one.Length > 160 ? one[..160] : one);
            }
            else if (upper.StartsWith("DAY:", StringComparison.Ordinal))
            {
                var v = Value("DAY:");
                if (Dated.Match(v) is { Success: true } m)
                {
                    var said = CleanValue(m.Groups[2].Value);
                    if (said.Length > 0) output.Days[m.Groups[1].Value] = said.Length > 240 ? said[..240] : said;
                }
                else if (v.Length > 0)
                {
                    output.Days[""] = v.Length > 240 ? v[..240] : v;
                }
            }
        }
        return output.Story is null && output.Facts.Count == 0 && output.Days.Count == 0 ? null : output;
    }

    private static string CleanValue(string value)
    {
        var v = value.Trim('*', ' ', '\t');
        while (v.Length > 1 && "\"“«".Contains(v[0]) && "\"”»".Contains(v[^1])) v = v[1..^1].Trim(' ', '\t');
        return v;
    }

    public sealed partial class Book
    {
        /// <summary>A fact for the pair to remember, unless they already do; the oldest goes
        /// once there are more than <paramref name="keep"/>. <paramref name="keep"/> 0: no facts are kept at all.</summary>
        public void Remember(string a, string b, string text, string source, int keep, DateTimeOffset? at = null)
        {
            var fact = text.Trim();
            if (a == b || fact.Length == 0) return;
            var now = at ?? DateTimeOffset.Now;
            Update(a, b, bond =>
            {
                if (keep <= 0) { bond.Facts = new(); return; }
                if (bond.Facts.Any(f => string.Equals(f.Text, fact, StringComparison.OrdinalIgnoreCase))) return;
                bond.Facts.Add(new Fact(fact, now, source));
                if (bond.Facts.Count > keep) bond.Facts.RemoveRange(0, bond.Facts.Count - keep);
            });
        }

        /// <summary>The diary's answer, written into their memory: the story, the facts in
        /// place of the old ones (the model saw them all), and the day lines. A line without
        /// a date belongs to the day of <paramref name="at"/>.</summary>
        public void Write(string a, string b, Diary diary, string source, int words, int keep, double? cost = null, DateTimeOffset? at = null)
        {
            var now = at ?? DateTimeOffset.Now;
            Update(a, b, bond =>
            {
                if (diary.Story is string story) bond.Chronicle = Trimmed(story, words);
                if (diary.Facts.Count > 0 || keep == 0)
                    bond.Facts = diary.Facts.TakeLast(Math.Max(0, keep)).Select(f => new Fact(f, now, source)).ToList();
                foreach (var (key, line) in diary.Days)
                {
                    var day = key.Length == 0 ? DayKey(now) : key;
                    if (bond.Days.FirstOrDefault(d => d.Day == day) is DayEntry found) found.Line = line;
                    else bond.Days.Add(new DayEntry(day) { Line = line });
                }
                bond.Days = bond.Days.OrderBy(d => d.Day, StringComparer.Ordinal).ToList();
                bond.DiaryAt = now;
                if (cost is double c) bond.MemoryCost = (bond.MemoryCost ?? 0) + c;
            });
        }

        /// <summary>A pair whose memory call was made, whatever came of it: when, and what it cost.</summary>
        public void WroteMemory(string a, string b, DateTimeOffset at, double? cost)
        {
            Update(a, b, bond =>
            {
                bond.DiaryAt = at;
                if (cost is double c) bond.MemoryCost = (bond.MemoryCost ?? 0) + c;
            });
        }

        /// <summary>Keep every pair within the owner's caps: <paramref name="facts"/> facts, <paramref name="days"/> days of timeline.</summary>
        public void KeepMemory(int facts, int days, DateTimeOffset? at = null)
        {
            var now = at ?? DateTimeOffset.Now;
            var oldest = DayKey(now.AddDays(-Math.Max(0, days)));
            foreach (var bond in Bonds.Values)
            {
                if (bond.Facts.Count > facts) bond.Facts.RemoveRange(0, bond.Facts.Count - Math.Max(0, facts));
                bond.Days.RemoveAll(d => string.CompareOrdinal(d.Day, oldest) < 0 || days == 0);
            }
        }

        /// <summary>Pairs whose memory is due its diary: something new since it was last
        /// written, and that at least <paramref name="every"/> seconds ago. Most new moments first.</summary>
        public List<Bond> DiaryDue(double every, DateTimeOffset? at = null)
        {
            var now = at ?? DateTimeOffset.Now;
            return Bonds.Values
                .Select(bond => (Bond: bond, Fresh: bond.Moments.Count(m => bond.DiaryAt is not DateTimeOffset d || m.Time > d)))
                .Where(x => x.Fresh > 0 && (x.Bond.DiaryAt is not DateTimeOffset d || (now - d).TotalSeconds >= every))
                .OrderByDescending(x => x.Fresh).ThenByDescending(x => string.Concat(x.Bond.Names), StringComparer.Ordinal)
                .Select(x => x.Bond).ToList();
        }
    }
}

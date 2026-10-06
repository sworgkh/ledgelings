using System.Globalization;
using System.Text.Json;

namespace Ledgelings.Core;

/// <summary>
/// How often the user's cursor has hunted each character (SPEC §4.7.2): chased it off its edge
/// or picked it up, the same moments <see cref="Annoyance"/> counts towards a complaint. Kept per
/// character name by the user's own calendar day, so it can say today, yesterday, this week (the
/// week starts where the system's culture starts it) and in all, and it survives a relaunch in
/// <c>hunts.json</c>. The same file shape as the Mac's.
///
/// The creatures use it three ways, none of them a model call of its own: a sentence for
/// <c>{situation}</c> (<see cref="Sentence"/>); built-in lines in each character's voice and mood
/// (<see cref="Line"/>); and, in the bad mood, a much-hunted creature keeps further from the cursor.
/// </summary>
public static partial class Hunts
{
    /// <summary>One character's count: by day (<c>2026-10-06</c>, the user's calendar), and in all.</summary>
    public sealed class Tally
    {
        public Dictionary<string, int> Days { get; set; } = new();
        public int All { get; set; }
    }

    /// <summary>What a creature knows of its own count, as of one moment.</summary>
    public sealed record Numbers(int Today = 0, int Yesterday = 0, int Week = 0, int All = 0, int BestBefore = 0, int DaysBeforeToday = 0)
    {
        /// <summary>This week's days before today, on average; null on the week's first day.</summary>
        public double? WeekAverageBefore => DaysBeforeToday > 0 ? (double)(Week - Today) / DaysBeforeToday : null;
    }

    /// <summary>Where days begin and weeks start: the user's time zone and culture, or a test's.</summary>
    public sealed record Clock(TimeZoneInfo Zone, DayOfWeek FirstDay)
    {
        public static Clock Local => new(TimeZoneInfo.Local, CultureInfo.CurrentCulture.DateTimeFormat.FirstDayOfWeek);
        public DateOnly Day(DateTimeOffset at) => DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(at, Zone).DateTime);
    }

    /// <summary>Days kept per character: enough for a record and any week, small enough to stay a tiny file.</summary>
    public const int DaysKept = 92;

    /// <summary><c>2026-10-06</c>, which sorts as the dates do.</summary>
    public static string Key(DateOnly day) => day.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

    /// <summary>Every character's tally, and since when it has been counting.</summary>
    public sealed class Book
    {
        public Dictionary<string, Tally> Tallies { get; set; } = new();
        /// <summary>The first count after the book was started or reset.</summary>
        public DateTimeOffset? Since { get; set; }

        /// <summary>One more hunt of <paramref name="name"/> at <paramref name="now"/>. Days older than <see cref="DaysKept"/> are let go.</summary>
        public void Count(string name, DateTimeOffset now, Clock clock)
        {
            if (!Tallies.TryGetValue(name, out var tally)) Tallies[name] = tally = new Tally();
            var today = clock.Day(now);
            var key = Key(today);
            tally.Days[key] = tally.Days.GetValueOrDefault(key) + 1;
            tally.All += 1;
            if (tally.Days.Count > DaysKept)
            {
                var cut = Key(today.AddDays(-DaysKept));
                tally.Days = tally.Days.Where(kv => string.CompareOrdinal(kv.Key, cut) > 0).ToDictionary(kv => kv.Key, kv => kv.Value);
            }
            Since ??= now;
        }

        public Numbers NumbersOf(string name, DateTimeOffset now, Clock clock)
        {
            if (!Tallies.TryGetValue(name, out var tally)) return new Numbers();
            var day = clock.Day(now);
            var todayKey = Key(day);
            int Of(DateOnly d) => tally.Days.GetValueOrDefault(Key(d));
            var today = Of(day);
            var before = ((int)day.DayOfWeek - (int)clock.FirstDay + 7) % 7;
            var week = today;
            for (var k = 1; k <= before; k++) week += Of(day.AddDays(-k));
            var best = tally.Days.Where(kv => kv.Key != todayKey).Select(kv => kv.Value).DefaultIfEmpty(0).Max();
            return new Numbers(today, Of(day.AddDays(-1)), week, tally.All, best, before);
        }

        /// <summary>Everyone's together.</summary>
        public Numbers Total(DateTimeOffset now, Clock clock) =>
            Tallies.Keys.Select(n => NumbersOf(n, now, clock)).Aggregate(new Numbers(),
                (sum, n) => sum with { Today = sum.Today + n.Today, Yesterday = sum.Yesterday + n.Yesterday, Week = sum.Week + n.Week, All = sum.All + n.All });

        /// <summary>Start over: one character's count, or everyone's.</summary>
        public void Reset(string? name = null)
        {
            if (name is null) Tallies.Clear(); else Tallies.Remove(name);
            if (Tallies.Count == 0) Since = null;
        }
    }

    /// <summary><c>hunts.json</c> beside the chats and the bonds.</summary>
    public sealed class Store
    {
        private static readonly JsonSerializerOptions Options = new(JsonLines.Options) { WriteIndented = true };

        public string Directory { get; }
        public Store(string directory) { Directory = directory; }
        public string File => Path.Combine(Directory, "hunts.json");

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

    // When it is worth saying

    /// <summary>Today's counts a creature remarks on as it reaches them.</summary>
    public static readonly int[] DayMilestones = { 10, 25, 50, 100, 200, 300, 500 };
    /// <summary>All-time counts likewise.</summary>
    public static readonly int[] AllMilestones = { 100, 250, 500, 1000, 2500, 5000, 10_000 };

    /// <summary>The hunt that just made these numbers is one to remark on: a round number today or in all,
    /// or the first hunt that makes today a record (over a best day of at least five).</summary>
    public static bool IsMilestone(Numbers n) =>
        DayMilestones.Contains(n.Today) || AllMilestones.Contains(n.All) || (n.BestBefore >= 5 && n.Today == n.BestBefore + 1);

    /// <summary>Built-in lines need numbers worth saying: two today at least.</summary>
    public static bool HasLine(Numbers n) => n.Today >= 2;

    /// <summary>In the bad mood, hunted at least <paramref name="after"/> times today, a creature jumps away
    /// from further off: its flee radius times this.</summary>
    public const double WaryFactor = 1.35;
    public static bool IsWary(Numbers n, int after, CursorMood mood) => mood == CursorMood.Bad && n.Today >= after;

    // For a model

    /// <summary>What <paramref name="name"/> knows of its count, for <c>{situation}</c>, in the current language and
    /// <paramref name="mood"/>; "" when the cursor has never hunted it. <paramref name="everyone"/>: today's count of
    /// each character on screen, to know who is the most hunted.</summary>
    public static string Sentence(string name, Numbers n, IReadOnlyDictionary<string, int>? everyone, CursorMood mood)
    {
        if (n.All <= 0) return "";
        static string Times(int k) => L10n.TrCount(k, "time", "times");
        var parts = new List<string>
        {
            L10n.Tr("Today the user's cursor has chased or picked up %@ %@ (yesterday %@), %@ this week and %@ in all.",
                    name, Times(n.Today), Times(n.Yesterday), Times(n.Week), Times(n.All)),
        };
        if (n.Today == 0) parts.Add(L10n.Tr("Today has been quiet so far."));
        else
        {
            if (n.Today > n.Yesterday) parts.Add(L10n.Tr("That is more than yesterday already."));
            else if (n.Today < n.Yesterday) parts.Add(L10n.Tr("That is fewer than yesterday."));
            if (n.WeekAverageBefore is double average && average >= 1 && n.Today >= 2 * average)
                parts.Add(L10n.Tr("Earlier days this week averaged %d.", (int)Math.Round(average, MidpointRounding.AwayFromZero)));
            if (n.BestBefore >= 5 && n.Today > n.BestBefore) parts.Add(L10n.Tr("It is %@'s most hunted day on record.", name));
            var others = (everyone ?? new Dictionary<string, int>()).Where(kv => kv.Key != name).Select(kv => kv.Value).ToList();
            if (others.Count > 0 && n.Today > others.Max()) parts.Add(L10n.Tr("%@ is the most hunted of everyone on screen today.", name));
        }
        parts.Add(mood switch
        {
            CursorMood.Good => L10n.Tr("%@ keeps this score proudly, like a game being won.", name),
            CursorMood.Neutral => L10n.Tr("%@ knows these numbers and is matter-of-fact about them.", name),
            _ => L10n.Tr("%@ keeps it as a tally of grievances.", name),
        });
        parts.Add(L10n.Tr("%@ may bring the numbers up, or compare them, if it fits.", name));
        return string.Join(" ", parts);
    }

    // Built-in lines

    /// <summary>A built-in line about the count, by <paramref name="name"/> in its own voice and <paramref name="mood"/>,
    /// in the current language: <c>{today}</c>, <c>{week}</c> and <c>{all}</c> filled in.</summary>
    public static string Line(string name, Numbers n, CursorMood mood, Random rng)
    {
        IReadOnlyList<string> pool = LinesFor(mood).TryGetValue(name, out var own) ? own : AnyoneFor(mood);
        string S(int k) => k.ToString(CultureInfo.InvariantCulture);
        return Banter.Render(rng.Pick(pool), new Dictionary<string, string> { ["today"] = S(n.Today), ["week"] = S(n.Week), ["all"] = S(n.All) });
    }

    /// <summary>Each built-in character's count lines in <paramref name="mood"/>, in the current language.</summary>
    public static IReadOnlyDictionary<string, string[]> LinesFor(CursorMood mood) => LinesIn(mood, Languages.Current);

    public static IReadOnlyDictionary<string, string[]> LinesIn(CursorMood mood, Language l)
    {
        var english = mood switch { CursorMood.Good => EnglishGoodLines, CursorMood.Neutral => EnglishNeutralLines, _ => EnglishBadLines };
        return Translated.Lists(Shared.In(l)?.HuntLinesByMood.GetValueOrDefault(mood.Code()), english, t => t);
    }

    /// <summary>For a character the user invented.</summary>
    public static IReadOnlyList<string> AnyoneFor(CursorMood mood) => AnyoneIn(mood, Languages.Current);

    public static IReadOnlyList<string> AnyoneIn(CursorMood mood, Language l)
    {
        var english = mood switch { CursorMood.Good => EnglishGoodAnyone, CursorMood.Neutral => EnglishNeutralAnyone, _ => EnglishBadAnyone };
        return Translated.List(Shared.In(l)?.HuntAnyoneByMood.GetValueOrDefault(mood.Code()), english);
    }
}

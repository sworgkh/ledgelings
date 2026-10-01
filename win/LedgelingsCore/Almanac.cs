using System.Globalization;

namespace Ledgelings.Core;

/// <summary>
/// What the creatures know of the world outside the screen: the time of day,
/// the date, and the holidays of the faiths the user ticked. Pure date work
/// on .NET's own calendars (Gregorian, Hebrew, Islamic Umm al-Qura), the same
/// calendars the Mac uses, so it needs no network and is testable with a fixed date.
///
/// Holidays are counted by the civil day: a Jewish or Muslim holiday that
/// begins at sundown is "today" from the morning after, and "begins this
/// evening" the evening before. Islamic dates follow the Umm al-Qura
/// calendar; where the new moon is sighted locally a date can fall a day
/// apart.
///
/// The Mac takes a <c>Calendar</c>; here it is the time zone whose wall clock counts
/// (the local one unless a test says otherwise).
/// </summary>
public static class Almanac
{
    public enum Faith { Jewish, Christian, Muslim }

    public static string Title(this Faith faith) => faith switch
    {
        Faith.Jewish => L10n.Tr("Jewish"),
        Faith.Christian => L10n.Tr("Christian"),
        _ => L10n.Tr("Muslim"),
    };

    /// <summary>"a Jewish holiday", for the sentence.</summary>
    public static string HolidayWord(this Faith faith) => faith switch
    {
        Faith.Jewish => L10n.Tr("a Jewish holiday"),
        Faith.Christian => L10n.Tr("a Christian holiday"),
        _ => L10n.Tr("a Muslim holiday"),
    };

    public static readonly IReadOnlyList<Faith> AllFaiths = new[] { Faith.Jewish, Faith.Christian, Faith.Muslim };

    /// <summary>What the app lets the creatures know.</summary>
    public sealed class Awareness : IEquatable<Awareness>
    {
        public bool TimeOfDay { get; }
        public bool Date { get; }
        public IReadOnlySet<Faith> Faiths { get; }
        /// <summary>Days before a holiday that it starts being mentioned; 0 = only on the day.</summary>
        public int LookAhead { get; }

        public Awareness(bool timeOfDay = true, bool date = true, IEnumerable<Faith>? faiths = null, int lookAhead = 3)
        {
            TimeOfDay = timeOfDay; Date = date; Faiths = new HashSet<Faith>(faiths ?? AllFaiths); LookAhead = Math.Max(0, lookAhead);
        }

        public bool Equals(Awareness? o) => o is not null && o.TimeOfDay == TimeOfDay && o.Date == Date
            && o.Faiths.SetEquals(Faiths) && o.LookAhead == LookAhead;
        public override bool Equals(object? obj) => Equals(obj as Awareness);
        public override int GetHashCode() => HashCode.Combine(TimeOfDay, Date, Faiths.Count, LookAhead);
    }

    /// <summary>A holiday happening on a given day: which day of it, out of how many.</summary>
    public sealed record Holiday(string Name, Faith Faith, int Day = 1, int Length = 1);

    /// <summary>A holiday still to come: <c>Days</c> from today (1 = tomorrow).</summary>
    public sealed record Upcoming(string Name, Faith Faith, int Days);

    // MARK: The sentence for the prompt

    /// <summary>The wall clock of <paramref name="now"/> in <paramref name="zone"/> (local when null).</summary>
    private static DateTime Wall(DateTimeOffset now, TimeZoneInfo? zone) => TimeZoneInfo.ConvertTime(now, zone ?? TimeZoneInfo.Local).DateTime;

    /// <summary>One or two sentences for <c>{situation}</c>, or "" when nothing is switched on.
    /// "For the person at this computer it is Saturday, 26 September 2026, late
    /// evening (22:40). Today is day 1 of Sukkot, a Jewish holiday."</summary>
    public static string Sentence(DateTimeOffset now, Awareness aware, TimeZoneInfo? zone = null)
    {
        var parts = new List<string>();
        var clock = TimePhrase(now, zone);
        if (aware.Date && aware.TimeOfDay) parts.Add(L10n.Tr("For the person at this computer it is %@, %@.", DatePhrase(now, zone), clock));
        else if (aware.Date) parts.Add(L10n.Tr("For the person at this computer it is %@.", DatePhrase(now, zone)));
        else if (aware.TimeOfDay) parts.Add(L10n.Tr("For the person at this computer it is %@.", clock));
        if (aware.Faiths.Count > 0)
        {
            var hour = Wall(now, zone).Hour;
            foreach (var h in Holidays(now, aware.Faiths, zone))
            {
                var what = h.Faith.HolidayWord();
                parts.Add(h.Length > 1 ? L10n.Tr("Today is day %d of %@, %@.", h.Day, h.Name, what) : L10n.Tr("Today is %@, %@.", h.Name, what));
            }
            foreach (var u in UpcomingHolidays(now, aware.LookAhead, aware.Faiths, zone))
            {
                var what = u.Faith.HolidayWord();
                if (u.Days == 1 && u.Faith != Faith.Christian && hour >= 17) parts.Add(L10n.Tr("%@, %@, begins this evening.", u.Name, what));
                else if (u.Days == 1) parts.Add(L10n.Tr("Tomorrow is %@, %@.", u.Name, what));
                else parts.Add(L10n.Tr("%@, %@, is in %@.", u.Name, what, L10n.TrCount(u.Days, "day", "days")));
            }
        }
        return string.Join(" ", parts);
    }

    /// <summary>"Saturday, 26 September 2026", "суббота, 26 сентября 2026".</summary>
    public static string DatePhrase(DateTimeOffset now, TimeZoneInfo? zone = null) =>
        Wall(now, zone).ToString("dddd, d MMMM yyyy", Languages.Current == Language.English ? CultureInfo.InvariantCulture : Languages.Current.Culture());

    /// <summary>"late evening (22:40)".</summary>
    public static string TimePhrase(DateTimeOffset now, TimeZoneInfo? zone = null)
    {
        var wall = Wall(now, zone);
        return $"{PartOfDay(wall.Hour)} ({wall.Hour:00}:{wall.Minute:00})";
    }

    /// <summary>The part of the day an hour falls in, in words.</summary>
    public static string PartOfDay(int hour) => hour switch
    {
        >= 5 and < 8 => L10n.Tr("early morning"),
        >= 8 and < 12 => L10n.Tr("morning"),
        >= 12 and < 14 => L10n.Tr("midday"),
        >= 14 and < 17 => L10n.Tr("afternoon"),
        >= 17 and < 21 => L10n.Tr("evening"),
        >= 21 and < 24 => L10n.Tr("late evening"),
        _ => L10n.Tr("the middle of the night"),
    };

    // MARK: Holidays

    /// <summary>Everything the ticked faiths celebrate on the civil day of <paramref name="date"/>.</summary>
    public static List<Holiday> Holidays(DateTimeOffset date, IReadOnlySet<Faith> faiths, TimeZoneInfo? zone = null)
    {
        var chosen = Feasts.Where(f => faiths.Contains(f.Faith)).ToList();
        if (chosen.Count == 0) return new List<Holiday>();
        var longest = chosen.Max(f => f.Length);
        // The day and the ones before it, each worked out once: days[k] is k days ago.
        var wall = Wall(date, zone);
        var days = Enumerable.Range(0, longest).Select(k => new Day(wall.AddDays(-k))).ToList();
        var found = new List<Holiday>();
        foreach (var feast in chosen)
        {
            var ago = Enumerable.Range(0, feast.Length).Cast<int?>().FirstOrDefault(k => feast.Starts(days[k!.Value]));
            if (ago is not int k) continue;
            if (k > 0 && feast.StillOn is { } still && !still(days[0])) continue;
            found.Add(new Holiday(HolidayName(feast.Name), feast.Faith, k + 1, feast.Length));
        }
        return found;
    }

    /// <summary>Holidays starting in the next <paramref name="days"/> days (tomorrow is 1), nearest first,
    /// leaving out any already under way today. (The Mac's <c>upcoming(from:within:faiths:)</c>.)</summary>
    public static List<Upcoming> UpcomingHolidays(DateTimeOffset date, int days, IReadOnlySet<Faith> faiths, TimeZoneInfo? zone = null)
    {
        var found = new List<Upcoming>();
        if (days <= 0) return found;
        var today = Holidays(date, faiths, zone).Select(h => h.Name).ToHashSet();
        var wall = Wall(date, zone);
        for (int ahead = 1; ahead <= days; ahead++)
        {
            var day = new Day(wall.AddDays(ahead));
            foreach (var feast in Feasts)
            {
                if (!faiths.Contains(feast.Faith) || !feast.Starts(day)) continue;
                var name = HolidayName(feast.Name);
                if (!today.Contains(name) && !found.Any(u => u.Name == name)) found.Add(new Upcoming(name, feast.Faith, ahead));
            }
        }
        return found;
    }

    /// <summary>The first holiday name for today, for a built-in line's <c>{holiday}</c>.</summary>
    public static string? Today(DateTimeOffset date, IReadOnlySet<Faith> faiths, TimeZoneInfo? zone = null) =>
        Holidays(date, faiths, zone).FirstOrDefault()?.Name;

    /// <summary>A holiday's name in the current language (or <paramref name="language"/>); <paramref name="english"/> is how <c>Feasts</c> calls it.</summary>
    public static string HolidayName(string english, Language? language = null) =>
        Shared.In(language ?? Languages.Current)?.Holidays.TryGetValue(english, out var name) == true && name.Length > 0 ? name : english;

    private static readonly HebrewCalendar hebrewCalendar = new();
    private static readonly UmAlQuraCalendar islamicCalendar = new();

    /// <summary>One civil day seen through every calendar a holiday is counted in.</summary>
    internal readonly struct Day
    {
        /// <summary>1 = Sunday … 7 = Saturday.</summary>
        public int Weekday { get; }
        public (int Month, int Day) Civil { get; }
        /// <summary>1 Tishrei … 13 Elul; 6 is Adar I, 7 Adar (Adar II), in every year, as the Mac counts.</summary>
        public (int Month, int Day) Hebrew { get; }
        /// <summary>1 Muharram … 12 Dhu al-Hijjah.</summary>
        public (int Month, int Day) Islamic { get; }
        /// <summary>Days after Western Easter this year (negative before).</summary>
        public int FromEaster { get; }
        public int FromOrthodoxEaster { get; }

        public Day(DateTime wall)
        {
            var date = wall.Date;
            Weekday = (int)date.DayOfWeek + 1;
            Civil = (date.Month, date.Day);
            // .NET numbers a common year's months 1…12 with Adar 6 and Nisan 7; the Mac
            // always counts 13, leaving 6 (Adar I) out of a common year.
            var hYear = hebrewCalendar.GetYear(date);
            var hMonth = hebrewCalendar.GetMonth(date);
            if (!hebrewCalendar.IsLeapYear(hYear) && hMonth >= 6) hMonth += 1;
            Hebrew = (hMonth, hebrewCalendar.GetDayOfMonth(date));
            try { Islamic = (islamicCalendar.GetMonth(date), islamicCalendar.GetDayOfMonth(date)); }
            catch (ArgumentOutOfRangeException) { Islamic = (0, 0); }       // Umm al-Qura's tables end in 2077
            var ordinal = date.DayOfYear;
            var e = WesternEaster(date.Year);
            var o = OrthodoxEaster(date.Year);
            FromEaster = ordinal - DayOfYear(date.Year, e.Month, e.Day);
            FromOrthodoxEaster = ordinal - DayOfYear(date.Year, o.Month, o.Day);
        }
    }

    /// <summary><c>Name</c> is in English; <see cref="HolidayName"/> gives it in the current language.</summary>
    internal sealed record Feast(string Name, Faith Faith, int Length, Func<Day, bool> Starts, Func<Day, bool>? StillOn = null);

    private static Feast HebrewFeast(string name, int month, int day, int length = 1) => new(name, Faith.Jewish, length, d => d.Hebrew == (month, day));
    private static Feast IslamicFeast(string name, int month, int day, int length = 1) => new(name, Faith.Muslim, length, d => d.Islamic == (month, day));
    private static Feast CivilFeast(string name, int month, int day) => new(name, Faith.Christian, 1, d => d.Civil == (month, day));
    private static Feast EasterFeast(string name, int offset) => new(name, Faith.Christian, 1, d => d.FromEaster == offset);

    /// <summary>Every holiday the almanac knows, by its English name.</summary>
    public static IReadOnlyList<string> FeastNames => Feasts.Select(f => f.Name).ToList();

    internal static readonly IReadOnlyList<Feast> Feasts = new[]
    {
        HebrewFeast("Rosh Hashanah", 1, 1, length: 2),
        HebrewFeast("Yom Kippur", 1, 10),
        HebrewFeast("Sukkot", 1, 15, length: 7),
        HebrewFeast("Simchat Torah", 1, 22),
        HebrewFeast("Hanukkah", 3, 25, length: 8),
        HebrewFeast("Tu BiShvat", 5, 15),
        HebrewFeast("Purim", 7, 14),
        HebrewFeast("Passover", 8, 15, length: 7),
        HebrewFeast("Lag BaOmer", 9, 18),
        HebrewFeast("Shavuot", 10, 6),
        // The fast of 9 Av moves to Sunday when the 9th is a Saturday.
        new Feast("Tisha B'Av", Faith.Jewish, 1, d => (d.Hebrew == (12, 9) && d.Weekday != 7) || (d.Hebrew == (12, 10) && d.Weekday == 1)),

        CivilFeast("Epiphany", 1, 6),
        CivilFeast("Orthodox Christmas", 1, 7),
        EasterFeast("Ash Wednesday", -46),
        EasterFeast("Palm Sunday", -7),
        EasterFeast("Good Friday", -2),
        EasterFeast("Easter", 0),
        new Feast("Orthodox Easter", Faith.Christian, 1, d => d.FromOrthodoxEaster == 0 && d.FromEaster != 0),
        EasterFeast("Ascension Day", 39),
        EasterFeast("Pentecost", 49),
        CivilFeast("All Saints' Day", 11, 1),
        CivilFeast("Christmas Eve", 12, 24),
        CivilFeast("Christmas", 12, 25),

        IslamicFeast("Islamic New Year", 1, 1),
        IslamicFeast("Ashura", 1, 10),
        IslamicFeast("the Prophet's Birthday (Mawlid)", 3, 12),
        IslamicFeast("Isra and Mi'raj", 7, 27),
        new Feast("Ramadan", Faith.Muslim, 30, d => d.Islamic == (9, 1), d => d.Islamic.Month == 9),
        IslamicFeast("Laylat al-Qadr", 9, 27),
        IslamicFeast("Eid al-Fitr", 10, 1, length: 3),
        IslamicFeast("the Day of Arafah", 12, 9),
        IslamicFeast("Eid al-Adha", 12, 10, length: 4),
    };

    // MARK: Easter

    /// <summary>Western Easter Sunday (Gregorian computus, the anonymous algorithm).</summary>
    public static (int Month, int Day) WesternEaster(int year)
    {
        int a = year % 19, b = year / 100, c = year % 100;
        int d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3;
        int h = (19 * a + b - d - g + 15) % 30;
        int i = c / 4, k = c % 4;
        int l = (32 + 2 * e + 2 * i - h - k) % 7;
        int m = (a + 11 * h + 22 * l) / 451;
        int month = (h + l - 7 * m + 114) / 31;
        return (month, (h + l - 7 * m + 114) % 31 + 1);
    }

    /// <summary>Orthodox Easter Sunday, as a Gregorian date (Julian computus plus the
    /// calendars' gap, 13 days from 1900 to 2099).</summary>
    public static (int Month, int Day) OrthodoxEaster(int year)
    {
        int a = year % 4, b = year % 7, c = year % 19;
        int d = (19 * c + 15) % 30, e = (2 * a + 4 * b - d + 34) % 7;
        int month = (d + e + 114) / 31, day = (d + e + 114) % 31 + 1;
        var julian = DayOfYear(year, month, day) + (year / 100 - year / 400 - 2);
        return FromDayOfYear(year, julian);
    }

    internal static int DayOfYear(int year, int month, int day)
    {
        var leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
        var lengths = new[] { 31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        return lengths.Take(month - 1).Sum() + day;
    }

    internal static (int Month, int Day) FromDayOfYear(int year, int ordinal)
    {
        int left = ordinal, month = 1;
        while (left > DayOfYear(year, month + 1, 1) - 1 && month < 12) month += 1;
        left -= DayOfYear(year, month, 1) - 1;
        return (month, left);
    }
}

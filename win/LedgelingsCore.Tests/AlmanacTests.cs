namespace Ledgelings.Core.Tests;

/// <summary>The user's clock, date and holidays, from the calendars built into .NET.</summary>
public class AlmanacTests
{
    static readonly TimeZoneInfo Zone = TimeZoneInfo.FindSystemTimeZoneById("Asia/Jerusalem");
    static readonly IReadOnlySet<Almanac.Faith> All = new HashSet<Almanac.Faith>(Almanac.AllFaiths);
    static IReadOnlySet<Almanac.Faith> Only(params Almanac.Faith[] faiths) => new HashSet<Almanac.Faith>(faiths);
    static readonly IReadOnlySet<Almanac.Faith> Jewish = Only(Almanac.Faith.Jewish);
    static readonly IReadOnlySet<Almanac.Faith> Christian = Only(Almanac.Faith.Christian);
    static readonly IReadOnlySet<Almanac.Faith> Muslim = Only(Almanac.Faith.Muslim);

    static DateTimeOffset At(int y, int m, int d, int hour = 12, int minute = 0)
    {
        var wall = new DateTime(y, m, d, hour, minute, 0, DateTimeKind.Unspecified);
        return new DateTimeOffset(wall, Zone.GetUtcOffset(wall));
    }

    static List<string> Names(int y, int m, int d, IReadOnlySet<Almanac.Faith>? faiths = null) =>
        Almanac.Holidays(At(y, m, d), faiths ?? All, Zone).Select(h => h.Name).ToList();

    [Fact]
    public void ThePartOfTheDayFollowsTheClock()
    {
        Assert.Equal("the middle of the night", Almanac.PartOfDay(3));
        Assert.Equal("early morning", Almanac.PartOfDay(6));
        Assert.Equal("morning", Almanac.PartOfDay(9));
        Assert.Equal("midday", Almanac.PartOfDay(13));
        Assert.Equal("afternoon", Almanac.PartOfDay(15));
        Assert.Equal("evening", Almanac.PartOfDay(19));
        Assert.Equal("late evening", Almanac.PartOfDay(23));
    }

    [Fact]
    public void TheSentenceSaysOnlyWhatIsSwitchedOn()
    {
        var now = At(2026, 9, 26, 22, 40);
        Assert.Equal("", Almanac.Sentence(now, new Almanac.Awareness(false, false, Array.Empty<Almanac.Faith>()), Zone));
        Assert.Equal("For the person at this computer it is late evening (22:40).",
            Almanac.Sentence(now, new Almanac.Awareness(true, false, Array.Empty<Almanac.Faith>()), Zone));
        Assert.Equal("For the person at this computer it is Saturday, 26 September 2026.",
            Almanac.Sentence(now, new Almanac.Awareness(false, true, Array.Empty<Almanac.Faith>()), Zone));
        var all = Almanac.Sentence(now, new Almanac.Awareness(), Zone);
        Assert.StartsWith("For the person at this computer it is Saturday, 26 September 2026, late evening (22:40). Today is day 1 of Sukkot, a Jewish holiday.", all);
    }

    [Fact]
    public void JewishHolidaysComeFromTheHebrewCalendar()
    {
        Assert.Equal(new[] { "Rosh Hashanah" }, Names(2026, 9, 12, Jewish));
        Assert.Equal(new[] { "Rosh Hashanah" }, Names(2026, 9, 13, Jewish));
        Assert.Equal(new[] { "Yom Kippur" }, Names(2026, 9, 21, Jewish));
        Assert.Equal(new[] { "Simchat Torah" }, Names(2026, 10, 3, Jewish));
        Assert.Equal(new[] { "Hanukkah" }, Names(2026, 12, 5, Jewish));
        Assert.Equal(new[] { "Hanukkah" }, Names(2026, 12, 12, Jewish));        // the 8th day, in Tevet
        Assert.Empty(Names(2026, 12, 13, Jewish));
        Assert.Equal(new[] { "Purim" }, Names(2026, 3, 3, Jewish));
        Assert.Equal(new[] { "Purim" }, Names(2027, 3, 23, Jewish));            // a leap year: Adar II
        Assert.Empty(Names(2027, 2, 21, Jewish));                                // 14 Adar I is not Purim
        Assert.Equal(new[] { "Passover" }, Names(2026, 4, 2, Jewish));
        Assert.Equal(new[] { "Shavuot" }, Names(2026, 5, 22, Jewish));
        Assert.Equal(new[] { "Tisha B'Av" }, Names(2026, 7, 23, Jewish));
        // 9 Av 5785 was a Sunday already; 9 Av 5782 (6 Aug 2022) a Saturday, kept on the 7th.
        Assert.Empty(Names(2022, 8, 6, Jewish));
        Assert.Equal(new[] { "Tisha B'Av" }, Names(2022, 8, 7, Jewish));
    }

    [Fact]
    public void AHolidayOfSeveralDaysSaysWhichDay()
    {
        var sukkot = Almanac.Holidays(At(2026, 9, 28), Jewish, Zone);
        Assert.Equal(new[] { new Almanac.Holiday("Sukkot", Almanac.Faith.Jewish, 3, 7) }, sukkot);
    }

    [Fact]
    public void ChristianHolidaysIncludeBothEasters()
    {
        Assert.Equal((4, 5), Almanac.WesternEaster(2026));
        Assert.Equal((4, 20), Almanac.WesternEaster(2025));
        Assert.Equal((3, 28), Almanac.WesternEaster(2027));
        Assert.Equal((4, 12), Almanac.OrthodoxEaster(2026));
        Assert.Equal((5, 2), Almanac.OrthodoxEaster(2027));
        Assert.Equal(new[] { "Easter" }, Names(2026, 4, 5, Christian));
        Assert.Equal(new[] { "Good Friday" }, Names(2026, 4, 3, Christian));
        Assert.Equal(new[] { "Orthodox Easter" }, Names(2026, 4, 12, Christian));
        Assert.Equal(new[] { "Easter" }, Names(2025, 4, 20, Christian));        // both on one day: said once
        Assert.Equal(new[] { "Ash Wednesday" }, Names(2026, 2, 18, Christian));
        Assert.Equal(new[] { "Christmas" }, Names(2026, 12, 25, Christian));
        Assert.Equal(new[] { "Orthodox Christmas" }, Names(2027, 1, 7, Christian));
    }

    [Fact]
    public void MuslimHolidaysComeFromTheIslamicCalendar()
    {
        Assert.Equal(new[] { "Ramadan" }, Names(2026, 2, 18, Muslim));
        var tenth = Almanac.Holidays(At(2026, 2, 27), Muslim, Zone);
        Assert.Equal(new Almanac.Holiday("Ramadan", Almanac.Faith.Muslim, 10, 30), tenth.First());
        Assert.Equal(new[] { "Eid al-Fitr" }, Names(2026, 3, 20, Muslim));      // Ramadan is over
        Assert.Equal(new[] { "the Day of Arafah" }, Names(2026, 5, 26, Muslim));
        Assert.Equal(new[] { "Eid al-Adha" }, Names(2026, 5, 27, Muslim));
    }

    [Fact]
    public void OnlyTheTickedFaithsCount()
    {
        Assert.Empty(Names(2026, 2, 18, Only()));
        Assert.True(Names(2026, 2, 18).ToHashSet().SetEquals(new[] { "Ramadan", "Ash Wednesday" }));
    }

    [Fact]
    public void HolidaysAheadAreMentionedWithinTheLookAhead()
    {
        var before = At(2026, 12, 2, 10);
        var soon = Almanac.UpcomingHolidays(before, 3, Jewish, Zone);
        Assert.Equal(new[] { new Almanac.Upcoming("Hanukkah", Almanac.Faith.Jewish, 3) }, soon);
        Assert.Empty(Almanac.UpcomingHolidays(before, 2, Jewish, Zone));
        Assert.Empty(Almanac.UpcomingHolidays(before, 0, Jewish, Zone));
        var aware = new Almanac.Awareness(false, false, Jewish, 3);
        Assert.Equal("Hanukkah, a Jewish holiday, is in 3 days.", Almanac.Sentence(before, aware, Zone));
        // The evening before, a Jewish holiday has already begun; a Christian one is still tomorrow.
        Assert.Equal("Hanukkah, a Jewish holiday, begins this evening.", Almanac.Sentence(At(2026, 12, 4, 19), aware, Zone));
        Assert.Equal("Tomorrow is Hanukkah, a Jewish holiday.", Almanac.Sentence(At(2026, 12, 4, 9), aware, Zone));
        var christian = new Almanac.Awareness(false, false, Christian, 1);
        Assert.Equal("Tomorrow is Christmas Eve, a Christian holiday.", Almanac.Sentence(At(2026, 12, 23, 20), christian, Zone));
    }

    [Fact]
    public void AHolidayUnderWayIsNotAlsoUpcoming()
    {
        var during = Almanac.UpcomingHolidays(At(2026, 9, 26), 7, Jewish, Zone);
        Assert.Equal(new[] { "Simchat Torah" }, during.Select(u => u.Name));
    }
}

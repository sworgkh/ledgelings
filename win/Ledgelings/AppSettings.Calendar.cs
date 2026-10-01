using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The calendar half of the settings: what the creatures know of the user's clock, date and holidays.</summary>
public sealed partial class AppSettings
{
    /// <summary>Days before a holiday that the creatures start mentioning it.</summary>
    public const int HolidayLookAheadMin = 0, HolidayLookAheadMax = 14;

    private bool knowsTimeOfDay, knowsDate, jewishHolidays, christianHolidays, muslimHolidays;
    private int holidayLookAhead;

    private void LoadCalendar()
    {
        knowsTimeOfDay = store.Get<bool?>("knowsTimeOfDay") ?? true;
        knowsDate = store.Get<bool?>("knowsDate") ?? true;
        jewishHolidays = store.Get<bool?>("jewishHolidays") ?? true;
        christianHolidays = store.Get<bool?>("christianHolidays") ?? true;
        muslimHolidays = store.Get<bool?>("muslimHolidays") ?? true;
        // Three days: enough for "Hanukkah is in 3 days" without talking of it all week.
        holidayLookAhead = Math.Clamp(store.Get<int?>("holidayLookAhead") ?? 3, HolidayLookAheadMin, HolidayLookAheadMax);
    }

    /// <summary>The creatures know the part of the day and the time on the user's clock.</summary>
    public bool KnowsTimeOfDay { get => knowsTimeOfDay; set => Put(ref knowsTimeOfDay, value, "knowsTimeOfDay"); }
    /// <summary>They know the weekday and the date.</summary>
    public bool KnowsDate { get => knowsDate; set => Put(ref knowsDate, value, "knowsDate"); }
    /// <summary>The holidays they know of, by faith.</summary>
    public bool JewishHolidays { get => jewishHolidays; set => Put(ref jewishHolidays, value, "jewishHolidays"); }
    public bool ChristianHolidays { get => christianHolidays; set => Put(ref christianHolidays, value, "christianHolidays"); }
    public bool MuslimHolidays { get => muslimHolidays; set => Put(ref muslimHolidays, value, "muslimHolidays"); }
    /// <summary>0: a holiday is only mentioned on the day itself.</summary>
    public int HolidayLookAhead { get => holidayLookAhead; set => Put(ref holidayLookAhead, Math.Clamp(value, HolidayLookAheadMin, HolidayLookAheadMax), "holidayLookAhead"); }

    /// <summary>Everything above, for <see cref="Almanac"/>.</summary>
    public Almanac.Awareness Awareness
    {
        get
        {
            var faiths = new List<Almanac.Faith>();
            if (jewishHolidays) faiths.Add(Almanac.Faith.Jewish);
            if (christianHolidays) faiths.Add(Almanac.Faith.Christian);
            if (muslimHolidays) faiths.Add(Almanac.Faith.Muslim);
            return new Almanac.Awareness(knowsTimeOfDay, knowsDate, faiths, holidayLookAhead);
        }
    }
}

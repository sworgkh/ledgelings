using System.Globalization;
using System.Windows;
using System.Windows.Threading;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Settings › Calendar: what the creatures know of the user's day (the clock, the date,
/// whose holidays); below, what that comes to right now, word for word, and the holidays coming up.</summary>
public sealed partial class SettingsWindow
{
    private sealed record UpcomingRow(string Name, string When);

    /// <summary>The Mac redraws the sentence every 30 seconds while the tab is up.</summary>
    private readonly DispatcherTimer calendarClock = new() { Interval = TimeSpan.FromSeconds(30) };

    private void InitCalendar()
    {
        NeedsModelNote(CalendarNeedsModel);
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.Brain) or nameof(AppSettings.KnowsTimeOfDay) or nameof(AppSettings.KnowsDate)
                or nameof(AppSettings.JewishHolidays) or nameof(AppSettings.ChristianHolidays) or nameof(AppSettings.MuslimHolidays)
                or nameof(AppSettings.HolidayLookAhead)) RefreshCalendar();
        };
        calendarClock.Tick += (_, _) => RefreshCalendar();
        IsVisibleChanged += (_, _) => { if (IsVisible) { RefreshCalendar(); calendarClock.Start(); } else calendarClock.Stop(); };
        RefreshCalendar();
    }

    private void RefreshCalendar()
    {
        var hasModel = settings.HasModel;
        var aware = settings.Awareness;
        // The built-in lines are written ahead of time: they cannot say what time it is.
        KnowsTimeToggle.IsEnabled = hasModel;
        KnowsDateToggle.IsEnabled = hasModel;
        LookAheadRow.IsEnabled = aware.Faiths.Count > 0 && hasModel;
        var ahead = settings.HolidayLookAhead;
        LookAheadValue.Text = ahead == 0 ? L10n.Tr("only on the day") : L10n.TrCount(ahead, "day ahead", "days ahead");

        var now = DateTimeOffset.Now;
        var sentence = Almanac.Sentence(now, aware);
        CalendarNow.Text = sentence.Length == 0 ? L10n.Tr("Nothing: every box is off.") : sentence;
        CalendarNowFooter.Text = hasModel
            ? L10n.Tr("This goes into {situation} in the Talk prompts, and at the top of a paper plane's note.")
            : L10n.Tr("What a model would be told. The built-in lines use only today's holiday, when there is one.");

        var upcoming = Almanac.UpcomingHolidays(now, 60, aware.Faiths);
        CalendarAheadEmpty.Text = aware.Faiths.Count == 0 ? L10n.Tr("No holidays ticked.") : upcoming.Count == 0 ? L10n.Tr("Nothing in the next 60 days.") : "";
        CalendarAheadEmpty.Visibility = CalendarAheadEmpty.Text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        CalendarAhead.ItemsSource = upcoming.Select(u => new UpcomingRow(u.Name, $"{u.Faith.Title()}, {When(u.Days, now)}")).ToList();
    }

    /// <summary>"tomorrow", "in 12 days · Sat 3 Oct", in the current language.</summary>
    private static string When(int days, DateTimeOffset now)
    {
        if (days <= 1) return L10n.Tr("tomorrow");
        return L10n.Tr("in %@", L10n.TrCount(days, "day", "days")) + " · " + now.AddDays(days).ToString("ddd d MMM", Languages.Current.Culture());
    }
}

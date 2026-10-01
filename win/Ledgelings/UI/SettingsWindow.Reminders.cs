using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Settings › Reminders: a new reminder and how they are delivered, then every reminder.</summary>
public sealed partial class SettingsWindow
{
    private sealed record RepeatChoice(Reminders.Repeat Repeat, string Title);
    private sealed record ReminderRow(Guid Id, string Text, string When, double Opacity);

    private ReminderBook? reminderBook;
    /// <summary>Deliver one now: the Send Now buttons and the test letter.</summary>
    private Action<Reminders.Reminder>? sendReminder;
    /// <summary>The "when" being picked; the day and the clock fields show it.</summary>
    private DateTimeOffset reminderTime = NextRoundHour();
    private bool syncingReminderTime;

    /// <summary>Hand the tab its book and a way to deliver a reminder now. Called once, by the app.</summary>
    public void AttachReminders(ReminderBook book, Action<Reminders.Reminder> send)
    {
        reminderBook = book;
        sendReminder = send;
        ReminderRepeat.ItemsSource = Reminders.AllRepeats.Select(r => new RepeatChoice(r, r.Title())).ToList();
        ReminderRepeat.SelectedIndex = 0;
        RemindersPath.Text = book.File;
        ShowReminderTime();
        book.Changed += RefreshReminders;
        settings.PropertyChanged += (_, e) => { if (e.PropertyName is nameof(AppSettings.Brain)) RefreshReminderFooter(); };
        // "Today 14:30" goes stale as the day goes on: refreshed whenever the window comes back.
        IsVisibleChanged += (_, _) => { if (IsVisible) RefreshReminders(); };
        RefreshReminders();
        RefreshReminderFooter();
    }

    /// <summary>The top of the next hour: a sensible first guess for "when".</summary>
    public static DateTimeOffset NextRoundHour()
    {
        var now = DateTimeOffset.Now;
        return new DateTimeOffset(now.Year, now.Month, now.Day, now.Hour, 0, 0, now.Offset).AddHours(1);
    }

    private void RefreshReminders()
    {
        if (reminderBook is null) return;
        var now = DateTimeOffset.Now;
        var all = reminderBook.Book.Sorted;
        ReminderList.ItemsSource = all.Select(r => new ReminderRow(r.Id, r.Text,
            r.IsFinished ? "Sent " + Reminders.When(r.SentAt ?? r.Time, now) : r.Describe(now), r.IsFinished ? 0.5 : 1)).ToList();
        NoReminders.Visibility = all.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        ClearSent.IsEnabled = reminderBook.Book.Reminders.Any(r => r.IsFinished);
    }

    private void RefreshReminderFooter()
    {
        var words = "The plane flies to the middle of the screen your cursor is on, comes at you and opens into a letter: your reminder, a note from whoever threw it, and their signature. Click the letter to fold it away; otherwise it folds itself after this long, counting only while you are at the computer. Off: nothing is delivered, and what came due meanwhile arrives when you turn it back on.";
        if (settings.Brain != BrainKind.Script) words += " With a model, the note is written for the moment (Costs › Reminders).";
        words += $" A paper note: Add a Reminder… ({App.ReminderHotkeyTitle} anywhere, or the tray menu) opens a sheet of the same paper to write a reminder on; off, it opens this tab.";
        ReminderFooter.Text = words;
    }

    private void ShowReminderTime()
    {
        syncingReminderTime = true;
        ReminderDay.SelectedDate = reminderTime.LocalDateTime.Date;
        ReminderClock.Text = reminderTime.LocalDateTime.ToString("HH:mm", CultureInfo.InvariantCulture);
        syncingReminderTime = false;
    }

    private void ReminderDay_Changed(object? sender, SelectionChangedEventArgs e)
    {
        if (syncingReminderTime || ReminderDay.SelectedDate is not DateTime day) return;
        var clock = reminderTime.LocalDateTime.TimeOfDay;
        reminderTime = new DateTimeOffset(day.Date + clock);
    }

    /// <summary>"14:30", "9:05", "930" or "9": anything that reads as a time on the 24-hour clock.</summary>
    public static TimeSpan? ParseClock(string text)
    {
        var t = text.Trim().Replace('.', ':');
        if (t.Length is 3 or 4 && t.All(char.IsDigit)) t = t[..^2] + ":" + t[^2..];
        if (t.All(char.IsDigit) && t.Length is 1 or 2) t += ":00";
        var parts = t.Split(':');
        if (parts.Length != 2 || !int.TryParse(parts[0], out var h) || !int.TryParse(parts[1], out var m)) return null;
        return h is >= 0 and < 24 && m is >= 0 and < 60 ? new TimeSpan(h, m, 0) : null;
    }

    private void ReminderClock_LostFocus(object sender, RoutedEventArgs e)
    {
        if (ParseClock(ReminderClock.Text) is TimeSpan clock)
            reminderTime = new DateTimeOffset(reminderTime.LocalDateTime.Date + clock);
        ShowReminderTime();
    }

    private void ReminderSoon_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string minutes }) return;
        reminderTime = DateTimeOffset.Now.AddMinutes(double.Parse(minutes, CultureInfo.InvariantCulture));
        ShowReminderTime();
    }

    private void ReminderText_Changed(object sender, TextChangedEventArgs e)
    {
        var empty = ReminderText.Text.Trim().Length == 0;
        AddReminder.IsEnabled = !empty;
        ReminderHint.Visibility = ReminderText.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void ReminderText_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter) return;
        e.Handled = true;
        AddFromTab();
    }

    private void AddReminder_Click(object sender, RoutedEventArgs e) => AddFromTab();

    private void AddFromTab()
    {
        var words = ReminderText.Text.Trim();
        if (words.Length == 0 || reminderBook is null) return;
        if (ParseClock(ReminderClock.Text) is TimeSpan clock) reminderTime = new DateTimeOffset(reminderTime.LocalDateTime.Date + clock);
        var repeat = (ReminderRepeat.SelectedItem as RepeatChoice)?.Repeat ?? Reminders.Repeat.Once;
        reminderBook.Add(words, reminderTime, repeat);
        ReminderText.Text = "";
        reminderTime = NextRoundHour();
        ShowReminderTime();
    }

    private Reminders.Reminder? ReminderOf(object sender) =>
        sender is Hyperlink { Tag: Guid id } ? reminderBook?.Book.Reminders.FirstOrDefault(r => r.Id == id) : null;

    private void ReminderSend_Click(object sender, RoutedEventArgs e)
    {
        if (ReminderOf(sender) is { } reminder) sendReminder?.Invoke(reminder with { });
    }

    private void ReminderDelete_Click(object sender, RoutedEventArgs e)
    {
        if (ReminderOf(sender) is { } reminder) reminderBook?.Remove(reminder.Id);
    }

    private void TestLetter_Click(object sender, RoutedEventArgs e) =>
        sendReminder?.Invoke(new Reminders.Reminder("This is what a reminder looks like", DateTimeOffset.Now));

    private void ClearSent_Click(object sender, RoutedEventArgs e) => reminderBook?.ClearFinished();

    private void RevealReminders_Click(object sender, RoutedEventArgs e) => reminderBook?.RevealInExplorer();
}

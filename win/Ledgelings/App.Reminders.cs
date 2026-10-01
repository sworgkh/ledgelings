using Ledgelings.Core;
using Ledgelings.Native;
using Ledgelings.UI;

namespace Ledgelings;

/// <summary>The next reminder in the tray menu, and the key that adds a reminder from anywhere.</summary>
public sealed partial class App
{
    /// <summary>Add a Reminder… from anywhere. The Mac's ⌘R; plain Ctrl+R is every browser's reload, so it is Ctrl+Alt+R here.</summary>
    public const string ReminderHotkeyTitle = "Ctrl+Alt+R";
    private const uint VK_R = 0x52;

    private ReminderBook? reminders;
    private GlobalHotkey? reminderKey;
    private SettingsWindow? remindersShownIn;

    /// <summary>The book the colony delivers from and the settings window lists, and the key.</summary>
    private void StartReminders()
    {
        reminders = new ReminderBook();
        if (colony is not null) colony.ReminderBook = reminders;
        try { reminderKey = new GlobalHotkey(Win32.MOD_CONTROL | Win32.MOD_ALT, VK_R, AddAReminder); }
        catch (InvalidOperationException e) { Console.Error.WriteLine("Ledgelings hotkey: " + e.Message); }
        if (reminderKey is { IsRegistered: false }) Console.Error.WriteLine($"Ledgelings: {ReminderHotkeyTitle} is taken by another app");
    }

    private void StopReminders() => reminderKey?.Dispose();

    /// <summary>The next reminder's line, under Creature Actions… as the Mac has it.</summary>
    private void AddNextReminder(List<TrayIcon.Item> items)
    {
        if (settings is null) return;
        if (reminders?.Book.Upcoming is { } next)
        {
            var text = next.Text.Length > 40 ? next.Text[..40] : next.Text;
            items.Add(new TrayIcon.Item("   " + L10n.Tr("Next: %@, %@", text, Reminders.When(next.Time, DateTimeOffset.Now))
                + (settings.RemindersEnabled ? "" : " " + L10n.Tr("(off)")),
                () => OpenSettings(SettingsTab.Reminders)));
        }
    }

    /// <summary>The paper note, or the Reminders tab with the paper note turned off.</summary>
    private void AddAReminder()
    {
        if (settings is null || reminders is null) return;
        if (settings.ReminderPaperNote) ReminderNote.ShowNote(reminders, colony?.NoteKeeper());
        else OpenSettings(SettingsTab.Reminders);
    }

    /// <summary>The settings window's Reminders tab, handed its book once.</summary>
    private void AttachReminders(SettingsWindow window)
    {
        if (reminders is null || ReferenceEquals(remindersShownIn, window)) return;
        remindersShownIn = window;
        window.AttachReminders(reminders, r => colony?.DeliverNow(r));
    }
}

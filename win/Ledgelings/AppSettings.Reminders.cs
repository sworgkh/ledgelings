namespace Ledgelings;

/// <summary>Reminders: how a reminder the user set is delivered by paper plane.</summary>
public sealed partial class AppSettings
{
    /// <summary>Seconds a reminder's letter stays open in the middle of the screen, unless clicked away first.</summary>
    public const double ReminderLetterMin = 10, ReminderLetterMax = 600;

    private bool remindersEnabled, reminderReadAloud, reminderPaperNote;
    private double reminderLetterSeconds;

    private void LoadReminders()
    {
        remindersEnabled = store.Get<bool?>("remindersEnabled") ?? true;
        // A minute: long enough to read it on your way back to the desk, short enough not to sit there all afternoon.
        reminderLetterSeconds = Math.Clamp(store.Get<double?>("reminderLetterSeconds") ?? 60, ReminderLetterMin, ReminderLetterMax);
        reminderReadAloud = store.Get<bool?>("reminderReadAloud") ?? true;
        // On: writing a reminder should feel like the game that delivers it.
        reminderPaperNote = store.Get<bool?>("reminderPaperNote") ?? true;
    }

    /// <summary>Reminders arrive by paper plane. Off: none is delivered; the ones that
    /// came due meanwhile arrive, late, when it is turned back on.</summary>
    public bool RemindersEnabled { get => remindersEnabled; set => Put(ref remindersEnabled, value, "remindersEnabled"); }
    public double ReminderLetterSeconds
    {
        get => reminderLetterSeconds;
        set => Put(ref reminderLetterSeconds, Math.Clamp(value, ReminderLetterMin, ReminderLetterMax), "reminderLetterSeconds");
    }
    /// <summary>With voice on, the creature who threw it reads its note out loud as the letter opens.</summary>
    public bool ReminderReadAloud { get => reminderReadAloud; set => Put(ref reminderReadAloud, value, "reminderReadAloud"); }
    /// <summary>Add a Reminder… opens a sheet of the letter's paper to write on. Off: it opens the Reminders tab.</summary>
    public bool ReminderPaperNote { get => reminderPaperNote; set => Put(ref reminderPaperNote, value, "reminderPaperNote"); }
}

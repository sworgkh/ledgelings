using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The Creature Actions sheet the tray menu opens, and the ways to it that need no tray icon.</summary>
public sealed partial class AppSettings
{
    private bool actionsStayOpen;
    private bool shortcutEnabled;
    private Shortcut shortcut;
    private bool reopenShowsActions;
    private bool recordingShortcut;
    private string shortcutProblem = "";

    private void LoadActions()
    {
        // On: the sheet is somewhere to play from, so it waits for another go until Done.
        actionsStayOpen = store.Get<bool?>("actionsStayOpen") ?? true;
        shortcutEnabled = store.Get<bool?>("shortcutEnabled") ?? true;
        shortcut = Shortcut.Saved(store.Get<int?>("shortcutKeyCode"), store.Get<int?>("shortcutModifiers"));
        reopenShowsActions = store.Get<bool?>("reopenShowsActions") ?? true;
    }

    /// <summary>The Creature Actions sheet stays up after a tile is pressed, for another go. Off: it folds away.</summary>
    public bool ActionsStayOpen { get => actionsStayOpen; set => Put(ref actionsStayOpen, value, "actionsStayOpen"); }

    /// <summary>A shortcut that works in every app, for when the tray has hidden the icon.</summary>
    public bool ShortcutEnabled { get => shortcutEnabled; set => Put(ref shortcutEnabled, value, "shortcutEnabled"); }

    public Shortcut Shortcut
    {
        get => shortcut;
        set
        {
            if (shortcut == value) return;
            shortcut = value;
            store.Set("shortcutKeyCode", value.KeyCode);
            store.Set("shortcutModifiers", (int)value.Modifiers);
            Raise(nameof(Shortcut));
        }
    }

    /// <summary>Opening the app again while it runs (Start, Explorer) brings the Creature Actions sheet up.</summary>
    public bool ReopenShowsActions { get => reopenShowsActions; set => Put(ref reopenShowsActions, value, "reopenShowsActions"); }

    /// <summary>The settings window is listening for a new shortcut, so the old one is let go. Not saved.</summary>
    public bool RecordingShortcut
    {
        get => recordingShortcut;
        set { if (recordingShortcut == value) return; recordingShortcut = value; Raise(nameof(RecordingShortcut)); }
    }

    /// <summary>Why the shortcut does nothing, when Windows refused it; empty while all is well. Not saved.</summary>
    public string ShortcutProblem
    {
        get => shortcutProblem;
        set { if (shortcutProblem == value) return; shortcutProblem = value; Raise(nameof(ShortcutProblem)); }
    }
}

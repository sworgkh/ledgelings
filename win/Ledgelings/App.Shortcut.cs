using Ledgelings.Core;
using Ledgelings.UI;

namespace Ledgelings;

/// <summary>
/// The ways to the Creature Actions sheet that need no tray icon (SPEC §11): Windows
/// tucks icons away in the overflow, so a shortcut that works in every app brings the
/// sheet up, and so does starting Ledgelings again while it runs.
/// </summary>
public sealed partial class App
{
    /// <summary>The second copy sets this; the running one is waiting on it.</summary>
    private const string ReopenSignal = "Ledgelings.ShowActions";

    private GlobalHotkey? actionsKey;
    private EventWaitHandle? reopened;
    private RegisteredWaitHandle? reopenedWait;

    private void StartShortcut()
    {
        if (settings is null) return;
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.ShortcutEnabled) or nameof(AppSettings.Shortcut) or nameof(AppSettings.RecordingShortcut)) HoldShortcut();
        };
        HoldShortcut();
        reopened = new EventWaitHandle(false, EventResetMode.AutoReset, ReopenSignal);
        reopenedWait = ThreadPool.RegisterWaitForSingleObject(reopened, (_, _) => Dispatcher.BeginInvoke(Reopened), null, Timeout.Infinite, false);
    }

    private void StopShortcut()
    {
        actionsKey?.Dispose();
        if (reopened is not null) reopenedWait?.Unregister(reopened);
        reopened?.Dispose();
    }

    /// <summary>Lets go of the old shortcut and takes the new one, or none: off, or while a new one is recorded.</summary>
    private void HoldShortcut()
    {
        if (settings is null) return;
        actionsKey?.Dispose();
        actionsKey = null;
        var problem = "";
        if (settings.ShortcutEnabled && !settings.RecordingShortcut)
        {
            var shortcut = settings.Shortcut;
            try { actionsKey = new GlobalHotkey(ShortcutKeys.Win32Modifiers(shortcut.Modifiers), (uint)shortcut.KeyCode, ToggleActions); }
            catch (InvalidOperationException e) { Console.Error.WriteLine("Ledgelings hotkey: " + e.Message); }
            if (actionsKey is not { IsRegistered: true })
            {
                actionsKey?.Dispose();
                actionsKey = null;
                problem = L10n.Tr("Windows would not take %@: another app holds it. Record another.", ShortcutKeys.Label(shortcut));
            }
        }
        settings.ShortcutProblem = problem;
    }

    /// <summary>The shortcut as the menu and the sheet show it; empty while it is off or refused.</summary>
    private string ShortcutTitle => settings is { ShortcutEnabled: true } && actionsKey is { IsRegistered: true } ? ShortcutKeys.Label(settings.Shortcut) : "";

    /// <summary>The shortcut from any app: the sheet comes up, or goes away if it is up.</summary>
    private void ToggleActions()
    {
        if (ActionsSheet.IsUp) ActionsSheet.PutAway();
        else OpenActions();
    }

    /// <summary>Started again while running: with the icon tucked away, the way in that needs no keys.</summary>
    private void Reopened()
    {
        if (settings is { ReopenShowsActions: true }) OpenActions();
    }

    /// <summary>Called by a second copy before it leaves: true when the running one was told to show the sheet.</summary>
    private static bool TellTheRunningCopy()
    {
        if (!EventWaitHandle.TryOpenExisting(ReopenSignal, out var signal)) return false;
        using (signal) signal.Set();
        return true;
    }

    /// <summary>Where the sheet's links lead, as the tray menu's items do.</summary>
    private void Follow(ActionsLink link)
    {
        switch (link)
        {
            case ActionsLink.Settings: OpenSettings(null); break;
            case ActionsLink.Chats: OpenSettings(SettingsTab.Chats); break;
            default: Shutdown(); break;
        }
    }
}

using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Stop activity (SPEC §7.17): the registry's entries for the dive and the games, the shortcut from any
/// app (Ctrl+Alt+Esc), the tray's Go Scuba Diving and Stop Activity, and the watch that stops one when the owner
/// uses the computer.</summary>
public sealed partial class App
{
    private GlobalHotkey? stopKey;
    private UseWatch? useWatch;

    private void StartActivities()
    {
        if (settings is null || colony is null) return;
        var c = colony;
        Activities.Shared.Register(Activities.Kind.Dive, () => c.IsDiving, c.StopDive);
        Activities.Shared.Register(Activities.Kind.Game, () => c.CurrentPlay is not null, () => c.EndPlay(false));
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.StopActivityShortcutEnabled) or nameof(AppSettings.StopActivityShortcut)
                or nameof(AppSettings.RecordingShortcut)) HoldStopKey();
        };
        HoldStopKey();
        useWatch = new UseWatch(settings);
    }

    private void StopActivities()
    {
        stopKey?.Dispose();
        useWatch?.Dispose();
    }

    /// <summary>The shortcut from any app, following the settings; none while a new shortcut is recorded.</summary>
    private void HoldStopKey()
    {
        if (settings is null) return;
        stopKey?.Dispose();
        stopKey = null;
        var problem = "";
        if (settings.StopActivityShortcutEnabled && !settings.RecordingShortcut)
        {
            var shortcut = settings.StopActivityShortcut;
            GlobalHotkey? key = null;
            try { key = new GlobalHotkey(ShortcutKeys.Win32Modifiers(shortcut.Modifiers), (uint)shortcut.KeyCode, () => Activities.Shared.StopAll()); }
            catch (InvalidOperationException e) { Console.Error.WriteLine("Ledgelings hotkey: " + e.Message); }
            if (key is { IsRegistered: true }) stopKey = key;
            else
            {
                key?.Dispose();
                problem = L10n.Tr("Windows would not take %@: another app holds it. Record another.", ShortcutKeys.Label(shortcut));
            }
        }
        settings.StopActivityShortcutProblem = problem;
    }

    /// <summary>A dive now, or out of the water if one is on.</summary>
    private void ToggleDive()
    {
        if (colony is null) return;
        if (colony.IsDiving) colony.StopDive();
        else if (!colony.StartDive()) System.Media.SystemSounds.Beep.Play();
    }

    /// <summary>The tray's lines under Activities…: the dive, and Stop Activity with its keys.</summary>
    private void AddActivityItems(List<TrayIcon.Item> items)
    {
        if (colony is null || settings is null) return;
        items.Add(new TrayIcon.Item(colony.IsDiving ? L10n.Tr("Out of the Water") : L10n.Tr("Go Scuba Diving"), ToggleDive));
        var title = settings.StopActivityShortcutEnabled && stopKey is { IsRegistered: true }
            ? L10n.Tr("Stop Activity (%@)", ShortcutKeys.Label(settings.StopActivityShortcut)) : L10n.Tr("Stop Activity");
        items.Add(new TrayIcon.Item(title, () => Activities.Shared.StopAll(), Enabled: Activities.Shared.IsRunning));
    }
}

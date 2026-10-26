using System.Windows.Threading;
using Ledgelings.Core;
using Ledgelings.UI;

namespace Ledgelings;

/// <summary>The Tools screen from the outside (SPEC §7.15): its shortcut from any app, the tray's Tools… item, and
/// what each tile starts. The Mac's <c>setUpToolsScreen</c>.</summary>
public sealed partial class App
{
    private ToolsScreenController? toolsScreen;
    private GlobalHotkey? toolsKey;

    private void StartToolsScreen()
    {
        if (settings is null) return;
        var s = settings;
        toolsScreen = new ToolsScreenController(s)
        {
            Start = tool =>
            {
                switch (tool)
                {
                    case Tools.Tool.Translate: translateSheet?.Show(); break;
                    case Tools.Tool.Dictation: DictationPress(); break;
                    case Tools.Tool.ClipHistory: clipPicker?.Show(ClipPicker.Group.Recent); break;
                    case Tools.Tool.Snippets: clipPicker?.Show(ClipPicker.Group.Snippets); break;
                    default: AddAReminder(); break;
                }
            },
            IsOn = tool => tool switch
            {
                Tools.Tool.Translate => s.TranslateEnabled && translateSheet is not null,
                Tools.Tool.Dictation => s.DictationEnabled,
                Tools.Tool.ClipHistory => s.ClipboardEnabled && s.ClipHistoryEnabled && clipPicker is not null,
                Tools.Tool.Snippets => s.ClipboardEnabled && clipPicker is not null,
                _ => s.RemindersEnabled,
            },
            ShortcutLabel = tool => tool switch
            {
                Tools.Tool.Translate when s.TranslateShortcutEnabled => ShortcutKeys.Label(s.TranslateShortcut),
                Tools.Tool.Dictation when s.DictationShortcutEnabled => ShortcutKeys.Label(s.DictationShortcut),
                Tools.Tool.ClipHistory when s.ClipHistoryShortcutEnabled => ShortcutKeys.Label(s.ClipHistoryShortcut),
                Tools.Tool.Snippets when s.ClipSnippetsShortcutEnabled => ShortcutKeys.Label(s.ClipSnippetsShortcut),
                // Windows' reminder key is fixed, Ctrl+Alt+R, and held only when Windows gave it.
                Tools.Tool.Reminder when reminderKey is { IsRegistered: true } => ReminderHotkeyTitle,
                _ => null,
            },
            OpenSettings = page => OpenSettings(page),
        };
        s.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.ToolsScreenEnabled) or nameof(AppSettings.ToolsScreenShortcutEnabled)
                or nameof(AppSettings.ToolsScreenShortcut) or nameof(AppSettings.RecordingShortcut))
                HoldToolsKey();
        };
        HoldToolsKey();
    }

    private void StopToolsScreen() => toolsKey?.Dispose();

    /// <summary>The shortcut from any app, following the settings; none while a new shortcut is recorded.</summary>
    private void HoldToolsKey()
    {
        if (settings is null) return;
        toolsKey?.Dispose();
        toolsKey = null;
        var problem = "";
        if (settings.ToolsScreenEnabled && settings.ToolsScreenShortcutEnabled && !settings.RecordingShortcut)
        {
            var shortcut = settings.ToolsScreenShortcut;
            GlobalHotkey? key = null;
            try { key = new GlobalHotkey(ShortcutKeys.Win32Modifiers(shortcut.Modifiers), (uint)shortcut.KeyCode, () => toolsScreen?.Toggle()); }
            catch (InvalidOperationException e) { Console.Error.WriteLine("Ledgelings hotkey: " + e.Message); }
            if (key is { IsRegistered: true }) toolsKey = key;
            else
            {
                key?.Dispose();
                problem = L10n.Tr("Windows would not take %@: another app holds it. Record another.", ShortcutKeys.Label(shortcut));
            }
        }
        settings.ToolsScreenShortcutProblem = problem;
    }

    /// <summary>The tray's Tools… line, first of the tools.</summary>
    private void AddToolsItem(List<TrayIcon.Item> items)
    {
        if (settings is not { ToolsScreenEnabled: true }) return;
        var keys = settings.ToolsScreenShortcutEnabled ? "\t" + ShortcutKeys.Label(settings.ToolsScreenShortcut) : "";
        items.Add(new TrayIcon.Item(L10n.Tr("Tools…") + keys, () => toolsScreen?.Show()));
    }

    private static void AfterMs(int ms, Action action)
    {
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(ms) };
        timer.Tick += (_, _) => { timer.Stop(); action(); };
        timer.Start();
    }
}

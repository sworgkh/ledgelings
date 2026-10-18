using Ledgelings.Core;
using Ledgelings.UI;
using Clipboard = Ledgelings.Core.Clipboard;

namespace Ledgelings;

/// <summary>The clipboard manager (SPEC §7.11): the history watcher, the picker, the snippet editor, and the
/// shortcuts from any app: the history's, the snippets', and each snippet's own.</summary>
public sealed partial class App
{
    private ClipBook? clipBook;
    private ClipWatcher? clipWatcher;
    private ClipPickerController? clipPicker;
    private readonly List<GlobalHotkey> clipKeys = new();

    private void StartClipboard()
    {
        if (settings is null) return;
        try { clipBook = new ClipBook(); }
        catch (Exception e) when (e is IOException or InvalidDataException or UnauthorizedAccessException)
        {
            Console.Error.WriteLine("Ledgelings clipboard: " + e.Message);
            return;
        }
        clipPicker = new ClipPickerController(settings, clipBook, () => colony, EditSnippets);
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.ClipboardEnabled) or nameof(AppSettings.ClipHistoryEnabled)) HoldClipWatcher();
            if (e.PropertyName is nameof(AppSettings.ClipboardEnabled) or nameof(AppSettings.ClipHistoryShortcutEnabled) or nameof(AppSettings.ClipHistoryShortcut)
                or nameof(AppSettings.ClipSnippetsShortcutEnabled) or nameof(AppSettings.ClipSnippetsShortcut) or nameof(AppSettings.ClipSnippetShortcutsEnabled)
                or nameof(AppSettings.RecordingShortcut))
                HoldClipKeys();
        };
        // A snippet's own shortcut may have changed.
        clipBook.Changed += () => Dispatcher.BeginInvoke(HoldClipKeys);
        HoldClipWatcher();
        HoldClipKeys();
    }

    private void StopClipboard()
    {
        clipWatcher?.Dispose();
        foreach (var key in clipKeys) key.Dispose();
        clipKeys.Clear();
    }

    /// <summary>Watching the clipboard only while the tool and its history are on.</summary>
    private void HoldClipWatcher()
    {
        if (settings is null || clipBook is null) return;
        var on = settings.ClipboardEnabled && settings.ClipHistoryEnabled;
        if (on && clipWatcher is null) clipWatcher = new ClipWatcher(settings, clipBook);
        else if (!on && clipWatcher is not null) { clipWatcher.Dispose(); clipWatcher = null; }
    }

    /// <summary>Lets go of every clipboard key and takes the ones switched on; none while a new shortcut is recorded.
    /// A key another app holds is named in <see cref="AppSettings.ClipShortcutProblem"/>.</summary>
    private void HoldClipKeys()
    {
        if (settings is null || clipBook is null) return;
        foreach (var key in clipKeys) key.Dispose();
        clipKeys.Clear();
        var refused = new List<string>();
        if (settings.ClipboardEnabled && !settings.RecordingShortcut)
        {
            void Take(Shortcut shortcut, Action pressed)
            {
                GlobalHotkey? key = null;
                try { key = new GlobalHotkey(ShortcutKeys.Win32Modifiers(shortcut.Modifiers), (uint)shortcut.KeyCode, pressed); }
                catch (InvalidOperationException e) { Console.Error.WriteLine("Ledgelings hotkey: " + e.Message); }
                if (key is { IsRegistered: true }) clipKeys.Add(key);
                else { key?.Dispose(); refused.Add(ShortcutKeys.Label(shortcut)); }
            }
            if (settings.ClipHistoryShortcutEnabled) Take(settings.ClipHistoryShortcut, () => OpenClipPicker(ClipPicker.Group.Recent));
            if (settings.ClipSnippetsShortcutEnabled) Take(settings.ClipSnippetsShortcut, () => OpenClipPicker(ClipPicker.Group.Snippets));
            if (settings.ClipSnippetShortcutsEnabled)
                foreach (var (_, snippet) in clipBook.Snippets.All)
                    if (snippet.Shortcut is { } own)
                    {
                        var id = snippet.Id;
                        Take(own, () => { if (clipBook.Snippets.Find(id) is { } s) clipPicker?.PasteNow(s); });
                    }
        }
        settings.ClipShortcutProblem = refused.Count == 0 ? ""
            : L10n.Tr("Windows would not take %@: another app holds it. Record another.", string.Join(", ", refused));
    }

    private void OpenClipPicker(ClipPicker.Group first)
    {
        if (settings is not { ClipboardEnabled: true }) return;
        clipPicker?.Toggle(first);
    }

    /// <summary>The snippet editor, one window.</summary>
    private void EditSnippets()
    {
        if (clipBook is null || settings is null) return;
        SnippetsWindow.ShowEditor(clipBook, settings);
    }

    /// <summary>The tray's clipboard lines, under Activities….</summary>
    private void AddClipboardItems(List<TrayIcon.Item> items)
    {
        if (settings is not { ClipboardEnabled: true } || clipBook is null) return;
        string Keys(bool on, Shortcut shortcut) => on ? "\t" + ShortcutKeys.Label(shortcut) : "";
        items.Add(new TrayIcon.Item(L10n.Tr("Clipboard History…") + Keys(settings.ClipHistoryShortcutEnabled, settings.ClipHistoryShortcut),
                                    () => OpenClipPicker(ClipPicker.Group.Recent)));
        items.Add(new TrayIcon.Item(L10n.Tr("Paste a Snippet…") + Keys(settings.ClipSnippetsShortcutEnabled, settings.ClipSnippetsShortcut),
                                    () => OpenClipPicker(ClipPicker.Group.Snippets)));
        items.Add(new TrayIcon.Item(L10n.Tr("Edit Snippets…"), EditSnippets));
    }

    /// <summary>The settings window's Clipboard tool, handed the book once.</summary>
    private void AttachClipboard(SettingsWindow window)
    {
        if (clipBook is not null) window.AttachClipboard(clipBook, EditSnippets);
    }
}

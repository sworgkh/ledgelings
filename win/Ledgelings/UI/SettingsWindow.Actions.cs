using System.Media;
using System.Windows;
using System.Windows.Input;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>The Actions tab's shortcut button: click it and the next keys pressed become
/// the shortcut from any app. Escape, or a second click, keeps the old one; a key with no
/// Ctrl, Alt or Windows key held is refused with a beep.</summary>
public sealed partial class SettingsWindow
{
    private void InitActions()
    {
        PreviewKeyDown += RecordShortcut;
        // Hidden or switched away from mid-recording: the old shortcut comes back.
        IsVisibleChanged += (_, _) => { if (!IsVisible) settings.RecordingShortcut = false; };
        Deactivated += (_, _) => settings.RecordingShortcut = false;
        ShowShortcut();
    }

    private void ShowShortcut()
    {
        ShortcutButton.Content = settings.RecordingShortcut ? L10n.Tr("Press the keys…") : ShortcutKeys.Label(settings.Shortcut);
        ShortcutProblemText.Visibility = settings.ShortcutProblem.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void ShortcutButton_Click(object sender, RoutedEventArgs e) => settings.RecordingShortcut = !settings.RecordingShortcut;

    private void RecordShortcut(object sender, KeyEventArgs e)
    {
        if (!settings.RecordingShortcut) return;
        e.Handled = true;
        // With Alt held WPF reports the key as System and keeps the real one aside.
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (ShortcutKeys.IsModifier(key)) return;
        var made = new Shortcut(KeyInterop.VirtualKeyFromKey(key), ShortcutKeys.From(Keyboard.Modifiers));
        if (key == Key.Escape && made.Modifiers == ShortcutModifiers.None) { settings.RecordingShortcut = false; return; }
        if (!made.IsUsable) { SystemSounds.Beep.Play(); return; }
        settings.Shortcut = made;
        settings.RecordingShortcut = false;
    }
}

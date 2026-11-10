using System.Windows;
using System.Windows.Media.Imaging;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Settings › Diving (SPEC §7.17): the water and the dive, Stop activity, its shortcut and its button, and the sea life
/// as it is drawn. The Mac's DivingSettingsView.</summary>
public sealed partial class SettingsWindow
{
    /// <summary>Start a dive now; false when nobody is free.</summary>
    public Func<bool>? StartDive { get; set; }

    private void InitDiving()
    {
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.StopActivityShortcut) or nameof(AppSettings.RecordingShortcut)
                or nameof(AppSettings.StopActivityShortcutEnabled)) ShowDiving();
        };
        try
        {
            var sea = SpriteAtlas.Named("sea").MakeFrames();
            SeaList.ItemsSource = new[] { "fish-a", "fish-b", "fish-c", "jelly", "crab", "turtle", "octopus" }
                .Select(name => sea.Frame(name, 0) is { } image ? Bitmaps.ToSource(ActionIcons.Trimmed(image)) : null)
                .OfType<BitmapSource>().ToList();
        }
        catch (Exception e) when (e is IOException or ArgumentException) { }
        ShowDiving();
    }

    private void ShowDiving()
    {
        StopActivityShortcutButton.Content = settings.RecordingShortcut && recordingButton == StopActivityShortcutButton
            ? L10n.Tr("Press the keys…") : ShortcutKeys.Label(settings.StopActivityShortcut);
        // The key in words as well: the symbols alone were not enough to know what to press.
        StopActivitySpoken.Text = settings.StopActivityShortcutEnabled ? L10n.Tr("Press %@", ShortcutKeys.Spoken(settings.StopActivityShortcut)) : "";
    }

    private void StopActivityShortcutButton_Click(object sender, RoutedEventArgs e)
    {
        Record(StopActivityShortcutButton, made => settings.StopActivityShortcut = made);
        ShowDiving();
    }

    private void StartDiveButton_Click(object sender, RoutedEventArgs e)
    {
        if (StartDive?.Invoke() != true) System.Media.SystemSounds.Beep.Play();
    }
}

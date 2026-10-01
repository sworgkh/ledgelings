using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Ledgelings.UI;

/// <summary>What every tab shares about having a model or not: one note, in the same words
/// everywhere, above whatever only a model can do (the Mac's <c>NeedsModelNote</c>).</summary>
public sealed partial class SettingsWindow
{
    private readonly List<TextBlock> needsModelNotes = new();

    /// <summary>Make <paramref name="note"/> the "Needs a model" note: shown, with the reason and where to
    /// choose one, while the brain is the built-in lines. Grey out the controls in the tab's own refresh,
    /// with <see cref="AppSettings.HasModel"/>.</summary>
    private void NeedsModelNote(TextBlock note)
    {
        note.Text = "ⓘ " + AppSettings.NeedsModel;
        note.TextWrapping = TextWrapping.Wrap;
        note.Foreground = Brushes.Gray;
        note.Margin = new Thickness(0, 0, 0, 6);
        needsModelNotes.Add(note);
        note.Visibility = settings.HasModel ? Visibility.Collapsed : Visibility.Visible;
    }

    private void RefreshNeedsModelNotes()
    {
        foreach (var note in needsModelNotes)
        {
            note.Text = "ⓘ " + AppSettings.NeedsModel;
            note.Visibility = settings.HasModel ? Visibility.Collapsed : Visibility.Visible;
        }
    }

    /// <summary>The Talk tab's later rows: how many lines they avoid repeating.</summary>
    private void InitTalkExtras()
    {
        RefreshLineMemory();
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.LineMemory)) RefreshLineMemory();
            if (e.PropertyName is nameof(AppSettings.Brain)) RefreshNeedsModelNotes();
        };
    }
}

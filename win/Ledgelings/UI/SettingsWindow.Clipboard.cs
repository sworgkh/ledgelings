using System.IO;
using System.Windows;
using System.Windows.Controls;
using Ledgelings.Core;
using Microsoft.Win32;

namespace Ledgelings.UI;

/// <summary>Productivity tools › Clipboard (SPEC §7.11): the history's limits, how a pick is pasted and who
/// brings the sheet, the shortcuts, the snippets, and the programs whose copies are never kept.</summary>
public sealed partial class SettingsWindow
{
    private sealed record HelperChoice(string Name, string Title);
    /// <summary>The helper menu's entry for no creature at all: not a name anyone can have.</summary>
    private const string NobodyBrings = "\u0001nobody";

    private ClipBook? clipBook;
    private Action? editSnippets;
    private bool showingClipHelper;

    /// <summary>Hand the tool its book and the way to the snippet editor. Called by the app, once per window.</summary>
    public void AttachClipboard(ClipBook book, Action edit)
    {
        if (ReferenceEquals(clipBook, book)) return;
        clipBook = book;
        editSnippets = edit;
        book.Changed += () => Dispatcher.BeginInvoke(ShowClipboard);
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.ClipKeepDays) or nameof(AppSettings.ClipExcludedApps) or nameof(AppSettings.ClipHistoryShortcut)
                or nameof(AppSettings.ClipSnippetsShortcut) or nameof(AppSettings.RecordingShortcut) or nameof(AppSettings.ClipShortcutProblem)
                or nameof(AppSettings.ClipHelper) or nameof(AppSettings.ClipHelperEnabled) or nameof(AppSettings.Language))
                ShowClipboard();
        };
        IsVisibleChanged += (_, _) => { if (IsVisible) ShowClipboard(); };
        ShowClipboard();
    }

    private void ShowClipboard()
    {
        if (clipBook is null) return;
        ClipKeepDaysValue.Text = settings.ClipKeepDays == 0 ? L10n.Tr("always") : settings.ClipKeepDays + L10n.Tr(" d");
        string Label(Button button, Shortcut shortcut) =>
            settings.RecordingShortcut && recordingButton == button ? L10n.Tr("Press the keys…") : ShortcutKeys.Label(shortcut);
        ClipHistoryShortcutButton.Content = Label(ClipHistoryShortcutButton, settings.ClipHistoryShortcut);
        ClipSnippetsShortcutButton.Content = Label(ClipSnippetsShortcutButton, settings.ClipSnippetsShortcut);
        ClipShortcutProblemText.Visibility = settings.ClipShortcutProblem.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        var snippets = clipBook.Snippets.All.Count();
        ClipSnippetCount.Text = L10n.Tr("%d snippets", snippets);
        ClipExcludedList.ItemsSource = settings.ClipExcludedApps.ToList();
        ClipClearHistory.Content = L10n.Tr("Clear History (%d)", clipBook.History.Clips.Count(c => !c.Pinned));
        ShowClipHelpers();
    }

    /// <summary>Whoever is nearest, everyone on screen by name (a chosen one no longer there kept), or nobody.</summary>
    private void ShowClipHelpers()
    {
        var names = VoiceNames();
        if (settings.ClipHelper.Length > 0 && !names.Contains(settings.ClipHelper)) names.Add(settings.ClipHelper);
        var choices = new List<HelperChoice> { new("", L10n.Tr("Whoever is nearest the middle")) };
        choices.AddRange(names.Select(n => new HelperChoice(n, n)));
        choices.Add(new HelperChoice(NobodyBrings, L10n.Tr("Nobody: it unfolds by itself")));
        showingClipHelper = true;
        ClipHelperBox.ItemsSource = choices;
        ClipHelperBox.SelectedValue = settings.ClipHelperEnabled ? settings.ClipHelper : NobodyBrings;
        showingClipHelper = false;
    }

    private void ClipHelper_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (showingClipHelper || ClipHelperBox.SelectedValue is not string who) return;
        settings.ClipHelperEnabled = who != NobodyBrings;
        if (who != NobodyBrings) settings.ClipHelper = who;
    }

    private void ClipShortcutButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender == ClipHistoryShortcutButton) Record(ClipHistoryShortcutButton, made => settings.ClipHistoryShortcut = made);
        else Record(ClipSnippetsShortcutButton, made => settings.ClipSnippetsShortcut = made);
        ShowClipboard();
    }

    private void EditSnippets_Click(object sender, RoutedEventArgs e) => editSnippets?.Invoke();

    /// <summary>A program by its .exe: its copies are never kept.</summary>
    private void ClipAddApp_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Filter = L10n.Tr("Programs") + " (*.exe)|*.exe",
            InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
        };
        if (dialog.ShowDialog(this) != true) return;
        var name = Path.GetFileName(dialog.FileName);
        if (settings.ClipExcludedApps.Contains(name, StringComparer.OrdinalIgnoreCase)) return;
        settings.ClipExcludedApps = settings.ClipExcludedApps.Append(name).ToList();
    }

    private void ClipRemoveApp_Click(object sender, RoutedEventArgs e)
    {
        if (ClipExcludedList.SelectedItem is not string app) return;
        settings.ClipExcludedApps = settings.ClipExcludedApps.Where(a => a != app).ToList();
    }

    private void ClipClearHistory_Click(object sender, RoutedEventArgs e) => clipBook?.ClearHistory();
}

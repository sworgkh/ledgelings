using System.Windows;
using System.Windows.Controls;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Productivity tools › Dictation (SPEC §7.13): the tool, its shortcut and the microphone; the model that
/// listens, how it writes, and who holds the microphone. The Mac's <c>DictationSettingsView.swift</c>.</summary>
public sealed partial class SettingsWindow
{
    private sealed record ModelChoice(string Id, string Title);
    private sealed record SpokenChoice(Dictation.Spoken Language, string Title);
    private List<Dictation.Model> dictationModels = new();
    private bool showingDictation;

    private void InitDictation()
    {
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.DictationShortcut) or nameof(AppSettings.DictationMaxSeconds) or nameof(AppSettings.RecordingShortcut)
                or nameof(AppSettings.DictationShortcutProblem) or nameof(AppSettings.DictationHelper) or nameof(AppSettings.DictationCreature)
                or nameof(AppSettings.DictationModel) or nameof(AppSettings.DictationLanguage) or nameof(AppSettings.Language))
                ShowDictation();
        };
        IsVisibleChanged += (_, _) => { if (IsVisible) { ShowDictation(); _ = LoadDictationModels(); } };
        ShowDictation();
    }

    private void ShowDictation()
    {
        showingDictation = true;
        DictationShortcutButton.Content = settings.RecordingShortcut && recordingButton == DictationShortcutButton
            ? L10n.Tr("Press the keys…") : ShortcutKeys.Label(settings.DictationShortcut);
        DictationMaxValue.Text = settings.DictationMaxSeconds + L10n.Tr(" s");
        DictationShortcutProblemText.Visibility = settings.DictationShortcutProblem.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        // Asked only of someone using OpenRouter already, as the Mac does.
        DictationKeyNote.Visibility = settings.OpenRouterConnected ? Visibility.Collapsed : Visibility.Visible;
        DictationMicrophoneName.Text = DictationRecorder.MicrophoneName ?? L10n.Tr("none found");

        var models = dictationModels.Select(m => new ModelChoice(m.Id, $"{m.Name} — {m.PriceLabel}")).ToList();
        if (!models.Any(m => m.Id == settings.DictationModel)) models.Insert(0, new ModelChoice(settings.DictationModel, settings.DictationModel));
        DictationModelBox.ItemsSource = models;
        DictationModelBox.SelectedValue = settings.DictationModel;

        DictationLanguageBox.ItemsSource = Enum.GetValues<Dictation.Spoken>().Select(l => new SpokenChoice(l, l.Title())).ToList();
        DictationLanguageBox.SelectedValue = settings.DictationLanguage;

        var names = VoiceNames();
        if (settings.DictationHelper.Length > 0 && !names.Contains(settings.DictationHelper)) names.Add(settings.DictationHelper);
        var helpers = new List<HelperChoice> { new("", L10n.Tr("Anyone free, by chance")) };
        helpers.AddRange(names.Select(n => new HelperChoice(n, n)));
        helpers.Add(new HelperChoice(NobodyBrings, L10n.Tr("Nobody: a note says how it went")));
        DictationHelperBox.ItemsSource = helpers;
        DictationHelperBox.SelectedValue = settings.DictationCreature ? settings.DictationHelper : NobodyBrings;
        showingDictation = false;
    }

    private async Task LoadDictationModels()
    {
        try
        {
            dictationModels = await ChatClient.ListeningModels();
            DictationModelsProblem.Text = "";
        }
        catch (ChatClient.Failure e) { DictationModelsProblem.Text = L10n.Tr("Could not load OpenRouter's models: %@", e.Message); }
        ShowDictation();
    }

    private void DictationShortcutButton_Click(object sender, RoutedEventArgs e)
    {
        Record(DictationShortcutButton, made => settings.DictationShortcut = made);
        ShowDictation();
    }

    private void DictationAllow_Click(object sender, RoutedEventArgs e) => DictationRecorder.OpenPrivacySettings();

    private void DictationModel_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (!showingDictation && DictationModelBox.SelectedValue is string id) settings.DictationModel = id;
    }

    private void DictationLanguage_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (!showingDictation && DictationLanguageBox.SelectedValue is Dictation.Spoken spoken) settings.DictationLanguage = spoken;
    }

    private void DictationHelper_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (showingDictation || DictationHelperBox.SelectedValue is not string who) return;
        settings.DictationCreature = who != NobodyBrings;
        if (who != NobodyBrings) settings.DictationHelper = who;
    }
}

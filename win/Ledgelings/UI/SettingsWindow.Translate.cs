using System.Windows;
using System.Windows.Controls;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Tools › Translate (SPEC §7.14): the shortcuts and the languages, the model and the guessing, the
/// clipboard and who brings the sheet. The Mac's <c>TranslateSettingsView.swift</c>, one column.</summary>
public sealed partial class SettingsWindow
{
    private sealed record ClipModeChoice(Translate.ClipMode Mode, string Title);
    private sealed record LangChoice(string Code, string Title);
    private List<ModelCatalog.Model> translateModels = new();
    private bool showingTranslate;

    private void InitTranslate()
    {
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.TranslateShortcut) or nameof(AppSettings.TranslateClipShortcut) or nameof(AppSettings.RecordingShortcut)
                or nameof(AppSettings.TranslateClipMode) or nameof(AppSettings.TranslateLanguages) or nameof(AppSettings.TranslateTargets)
                or nameof(AppSettings.TranslateModel) or nameof(AppSettings.TranslateHelper) or nameof(AppSettings.TranslateHelperEnabled)
                or nameof(AppSettings.OpenRouterKey) or nameof(AppSettings.Brain))
                ShowTranslate();
        };
        IsVisibleChanged += (_, _) => { if (IsVisible && page == SettingsPage.Translate) LoadTranslateModelsOnce(); };
        ShowTranslate();
    }

    private void RefreshTranslate() => ShowTranslate();

    private void ShowTranslate()
    {
        showingTranslate = true;
        TranslateShortcutButton.Content = settings.RecordingShortcut && recordingButton == TranslateShortcutButton
            ? L10n.Tr("Press the keys…") : ShortcutKeys.Label(settings.TranslateShortcut);
        TranslateClipShortcutButton.Content = settings.RecordingShortcut && recordingButton == TranslateClipShortcutButton
            ? L10n.Tr("Press the keys…") : ShortcutKeys.Label(settings.TranslateClipShortcut);
        TranslateKeyNote.Visibility = settings.OpenRouterKey.Trim().Length > 0 || settings.Brain == BrainKind.LmStudio ? Visibility.Collapsed : Visibility.Visible;
        TranslateClipModeBox.ItemsSource = Enum.GetValues<Translate.ClipMode>().Select(m => new ClipModeChoice(m, m.Title())).ToList();
        TranslateClipModeBox.SelectedValue = settings.TranslateClipMode;

        // A switch per language: at least two stay on, so the last two cannot be switched off.
        var on = settings.TranslateLanguagesOn;
        TranslateLanguageList.Children.Clear();
        foreach (var language in Translate.Languages)
        {
            var box = new CheckBox
            {
                Content = $"{language.Title} ({language.NativeName})",
                IsChecked = on.Contains(language),
                IsEnabled = !(on.Contains(language) && on.Count <= 2),
                Margin = new Thickness(0, 2, 0, 2),
            };
            var code = language.Code;
            box.Click += (_, _) =>
            {
                var codes = settings.TranslateLanguagesOn.Select(l => l.Code).ToList();
                if (box.IsChecked == true) codes.Add(code); else codes.Remove(code);
                if (codes.Count >= 2) settings.TranslateLanguages = codes;
                ShowTranslate();
            };
            TranslateLanguageList.Children.Add(box);
        }
        // Where each language goes when no target is picked.
        TranslateTargetList.Children.Clear();
        foreach (var language in on)
        {
            var row = new DockPanel { Margin = new Thickness(0, 2, 0, 2) };
            row.Children.Add(new TextBlock { Text = L10n.Tr("%@ goes into", language.Title), Width = 160, VerticalAlignment = VerticalAlignment.Center });
            var into = new ComboBox
            {
                ItemsSource = on.Where(l => l != language).Select(l => new LangChoice(l.Code, l.Title)).ToList(),
                DisplayMemberPath = "Title", SelectedValuePath = "Code", Width = 160, HorizontalAlignment = HorizontalAlignment.Left,
                SelectedValue = Translate.Target(language, settings.TranslateTargets, on).Code,
            };
            var from = language.Code;
            into.SelectionChanged += (_, _) =>
            {
                if (showingTranslate || into.SelectedValue is not string to) return;
                settings.TranslateTargets = new Dictionary<string, string>(settings.TranslateTargets) { [from] = to };
            };
            row.Children.Add(into);
            TranslateTargetList.Children.Add(row);
        }

        var models = translateModels.Select(m => new ModelChoice(m.Id, $"{m.Name} — {m.PriceLabel}")).ToList();
        if (!models.Any(m => m.Id == settings.TranslateModel)) models.Insert(0, new ModelChoice(settings.TranslateModel, settings.TranslateModel));
        TranslateModelBox.ItemsSource = models;
        TranslateModelBox.SelectedValue = settings.TranslateModel;

        var names = VoiceNames();
        if (settings.TranslateHelper.Length > 0 && !names.Contains(settings.TranslateHelper)) names.Add(settings.TranslateHelper);
        var helpers = new List<HelperChoice> { new("", L10n.Tr("Whoever is nearest the middle")) };
        helpers.AddRange(names.Select(n => new HelperChoice(n, n)));
        helpers.Add(new HelperChoice(NobodyBrings, L10n.Tr("Nobody: it unfolds by itself")));
        TranslateHelperBox.ItemsSource = helpers;
        TranslateHelperBox.SelectedValue = settings.TranslateHelperEnabled ? settings.TranslateHelper : NobodyBrings;
        showingTranslate = false;
    }

    private bool loadingTranslateModels;

    /// <summary>The list, the first time the page is seen (or after a failed load).</summary>
    private void LoadTranslateModelsOnce()
    {
        if (translateModels.Count > 0 || loadingTranslateModels) return;
        loadingTranslateModels = true;
        _ = LoadTranslateModels().ContinueWith(_ => loadingTranslateModels = false, TaskScheduler.FromCurrentSynchronizationContext());
    }

    /// <summary>OpenRouter's models, cheapest first, for the picker; the Model box above takes an id typed by hand.</summary>
    private async Task LoadTranslateModels()
    {
        try
        {
            translateModels = (await ChatClient.OpenRouterPublic.Catalog()).Search("").Take(300).ToList();
            TranslateModelsProblem.Text = "";
        }
        catch (ChatClient.Failure e) { TranslateModelsProblem.Text = L10n.Tr("Could not load OpenRouter's models: %@", e.Message); }
        ShowTranslate();
    }

    private void TranslateShortcutButton_Click(object sender, RoutedEventArgs e)
    {
        Record(TranslateShortcutButton, made => settings.TranslateShortcut = made);
        ShowTranslate();
    }

    private void TranslateClipShortcutButton_Click(object sender, RoutedEventArgs e)
    {
        Record(TranslateClipShortcutButton, made => settings.TranslateClipShortcut = made);
        ShowTranslate();
    }

    private void TranslateClipMode_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (!showingTranslate && TranslateClipModeBox.SelectedValue is Translate.ClipMode mode) settings.TranslateClipMode = mode;
    }

    private void TranslateModel_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (!showingTranslate && TranslateModelBox.SelectedValue is string id) settings.TranslateModel = id;
    }

    private void TranslateHelper_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (showingTranslate || TranslateHelperBox.SelectedValue is not string who) return;
        settings.TranslateHelperEnabled = who != NobodyBrings;
        if (who != NobodyBrings) settings.TranslateHelper = who;
    }
}

using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;
using Ledgelings.Core;
using R = Ledgelings.Core.ReadAloud;

namespace Ledgelings.UI;

/// <summary>Tools › Read aloud (SPEC §7.16): the shortcut, the presets and the one being edited, the sound file and
/// who brings the sheet. The Mac's <c>ReadAloudSettingsView.swift</c>, one column.</summary>
public sealed partial class SettingsWindow
{
    private sealed record EngineChoice(R.Engine Engine, string Title);
    private sealed record FormatChoice(R.Format Format, string Title);
    private sealed record PickChoice(string Id, string Title);

    /// <summary>The player, for Try it; set once Read aloud is made. Null: Try it is off.</summary>
    public ReadAloudPlayer? ReadAloudPlayer
    {
        get => readAloudPlayer;
        set { readAloudPlayer = value; ShowReadAloud(); }
    }
    private ReadAloudPlayer? readAloudPlayer;
    /// <summary>Every character of every species, for the Reader list.</summary>
    public Func<IReadOnlyList<string>> ReadAloudReaders
    {
        get => readAloudReaders;
        set { readAloudReaders = value; ShowReadAloud(); }
    }
    private Func<IReadOnlyList<string>> readAloudReaders = () => Array.Empty<string>();

    private Guid? editingPreset;
    private bool showingReadAloud, loadingSpeechModels;

    private void InitReadAloud()
    {
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.ReadAloudShortcut) or nameof(AppSettings.RecordingShortcut) or nameof(AppSettings.ReadAloudPresets)
                or nameof(AppSettings.ReadAloudDefaultPreset) or nameof(AppSettings.ReadAloudFormat) or nameof(AppSettings.ReadAloudHelper)
                or nameof(AppSettings.ReadAloudHelperEnabled))
                ShowReadAloud();
        };
        IsVisibleChanged += (_, _) => { if (IsVisible && page == SettingsPage.ReadAloud) LoadSpeechModelsOnce(); };
        ShowReadAloud();
    }

    private void RefreshReadAloud() => ShowReadAloud();

    /// <summary>The preset being edited: the one clicked, else the first.</summary>
    private R.Preset ChosenPreset => settings.ReadAloudPresets.FirstOrDefault(p => p.Id == editingPreset) ?? settings.ReadAloudPresets[0];

    private void ShowReadAloud()
    {
        showingReadAloud = true;
        ReadAloudShortcutButton.Content = settings.RecordingShortcut && recordingButton == ReadAloudShortcutButton
            ? L10n.Tr("Press the keys…") : ShortcutKeys.Label(settings.ReadAloudShortcut);

        var presets = settings.ReadAloudPresets;
        var chosen = ChosenPreset;
        ReadAloudPresetList.Children.Clear();
        foreach (var preset in presets)
        {
            var row = new DockPanel { Margin = new Thickness(0, 1, 0, 1), Background = preset.Id == chosen.Id ? new SolidColorBrush(Color.FromArgb(40, 255, 138, 61)) : Brushes.Transparent, Cursor = System.Windows.Input.Cursors.Hand };
            if (preset.Id == settings.ReadAloudDefault.Id)
            {
                var first = new TextBlock { Text = L10n.Tr("Start with"), Foreground = Brushes.Gray, Margin = new Thickness(8, 2, 4, 2) };
                DockPanel.SetDock(first, Dock.Right);
                row.Children.Add(first);
            }
            row.Children.Add(new TextBlock { Text = preset.Title, FontWeight = preset.Id == chosen.Id ? FontWeights.SemiBold : FontWeights.Normal, Margin = new Thickness(4, 2, 8, 2) });
            row.Children.Add(new TextBlock { Text = Summary(preset), Foreground = Brushes.Gray, TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(0, 2, 0, 2) });
            var id = preset.Id;
            row.MouseLeftButtonUp += (_, _) =>
            {
                // A name typed but not yet left is kept before another preset fills the box.
                ReadAloudName_Changed(this, new RoutedEventArgs());
                editingPreset = id;
                ShowReadAloud();
            };
            ReadAloudPresetList.Children.Add(row);
        }
        ReadAloudAddButton.IsEnabled = presets.Count < R.MostPresets;
        ReadAloudDeleteButton.IsEnabled = presets.Count > 1;
        ReadAloudTryButton.IsEnabled = ReadAloudPlayer is not null;

        // The chosen one's fields.
        ReadAloudNameBox.Text = chosen.Name;
        ReadAloudEngineBox.ItemsSource = Enum.GetValues<R.Engine>().Select(e => new EngineChoice(e, e.Title())).ToList();
        ReadAloudEngineBox.SelectedValue = chosen.Engine;
        ReadAloudModelRow.Visibility = chosen.Engine == R.Engine.OpenRouter ? Visibility.Visible : Visibility.Collapsed;
        var models = voice?.Models ?? Array.Empty<SpeechClient.SpeechModel>();
        var modelChoices = new List<PickChoice> { new("", $"{R.DefaultModel} · {models.FirstOrDefault(m => m.Id == R.DefaultModel)?.PriceLabel ?? L10n.Tr("price unknown")}") };
        if (chosen.Model.Length > 0 && !models.Any(m => m.Id == chosen.Model)) modelChoices.Add(new(chosen.Model, chosen.Model));
        modelChoices.AddRange(models.Where(m => m.Id != R.DefaultModel).Select(m => new PickChoice(m.Id, $"{m.Id} · {m.PriceLabel}")));
        ReadAloudModelBox.ItemsSource = modelChoices;
        ReadAloudModelBox.SelectedValue = chosen.Model;

        var voices = new List<PickChoice> { new("", L10n.Tr("Chosen for the reader")) };
        var all = VoicesFor(chosen);
        if (chosen.Voice.Length > 0 && !all.Any(v => v.Id == chosen.Voice)) voices.Add(new(chosen.Voice, chosen.Voice));
        voices.AddRange(all);
        ReadAloudVoiceBox.ItemsSource = voices;
        ReadAloudVoiceBox.SelectedValue = chosen.Voice;

        var readers = new List<PickChoice> { new("", L10n.Tr("A narrator")) };
        var everyone = ReadAloudReaders();
        if (chosen.Character.Length > 0 && !everyone.Contains(chosen.Character)) readers.Add(new(chosen.Character, chosen.Character));
        readers.AddRange(everyone.Select(n => new PickChoice(n, n)));
        ReadAloudReaderBox.ItemsSource = readers;
        ReadAloudReaderBox.SelectedValue = chosen.Character;

        ReadAloudPaceSlider.Value = chosen.Speed;
        ReadAloudPaceValue.Text = R.SpeedLabel(chosen.Speed);
        ReadAloudRestSlider.Value = chosen.Pause;
        ReadAloudRestValue.Text = chosen.Pause.ToString("0.0", Languages.Current.Culture()) + L10n.Tr(" s");
        var languages = new List<PickChoice> { new("", L10n.Tr("Told by its letters")) };
        languages.AddRange(Translate.Languages.Select(l => new PickChoice(l.Code, l.Title)));
        ReadAloudLanguageBox.ItemsSource = languages;
        ReadAloudLanguageBox.SelectedValue = chosen.Language;

        ReadAloudFormatBox.ItemsSource = Enum.GetValues<R.Format>().Select(f => new FormatChoice(f, f.Title())).ToList();
        ReadAloudFormatBox.SelectedValue = settings.ReadAloudFormat;

        var names = VoiceNames();
        if (settings.ReadAloudHelper.Length > 0 && !names.Contains(settings.ReadAloudHelper)) names.Add(settings.ReadAloudHelper);
        var helpers = new List<HelperChoice> { new("", L10n.Tr("Whoever is nearest the middle")) };
        helpers.AddRange(names.Select(n => new HelperChoice(n, n)));
        helpers.Add(new HelperChoice(NobodyBrings, L10n.Tr("Nobody: it unfolds by itself")));
        ReadAloudHelperBox.ItemsSource = helpers;
        ReadAloudHelperBox.SelectedValue = settings.ReadAloudHelperEnabled ? settings.ReadAloudHelper : NobodyBrings;
        showingReadAloud = false;
    }

    /// <summary>"Zed, 0.8×, Russian": who reads, the pace, the language it forces.</summary>
    private static string Summary(R.Preset preset)
    {
        var who = preset.Character.Length == 0 ? (preset.Voice.Length == 0 ? L10n.Tr("a narrator") : preset.Voice) : preset.Character;
        return $"{who}, {R.SpeedLabel(preset.Speed)}" + (preset.ForcedLanguage is { } l ? ", " + l.Title : "");
    }

    /// <summary>The voices the preset's engine has: the model's, the local server's, or Windows' in the languages it reads.</summary>
    private List<PickChoice> VoicesFor(R.Preset preset)
    {
        switch (preset.Engine)
        {
            case R.Engine.OpenRouter:
                return (voice?.Models.FirstOrDefault(m => m.Id == preset.ModelOrDefault)?.Voices ?? Array.Empty<string>()).Select(v => new PickChoice(v, v)).ToList();
            case R.Engine.Local:
                return (voice?.LocalVoices ?? Array.Empty<string>()).Select(v => new PickChoice(v, v)).ToList();
            default:
                var codes = preset.ForcedLanguage is { } forced ? new[] { forced.Code } : Translate.Languages.Select(l => l.Code).ToArray();
                return Voice.Installed.Where(v => codes.Any(c => v.Culture.StartsWith(c, StringComparison.OrdinalIgnoreCase)))
                    .GroupBy(v => v.Name).Select(g => g.First())
                    .OrderBy(v => v.Culture, StringComparer.Ordinal).ThenBy(v => v.Name, StringComparer.Ordinal)
                    .Select(v => new PickChoice(v.Name, $"{v.Name} · {v.Culture}")).ToList();
        }
    }

    /// <summary>One change to the preset being edited, saved as it is made.</summary>
    private void Change(Func<R.Preset, R.Preset> change)
    {
        if (showingReadAloud) return;
        var chosen = ChosenPreset;
        var changed = change(chosen);
        if (changed == chosen) return;
        settings.ReadAloudPresets = settings.ReadAloudPresets.Select(p => p.Id == chosen.Id ? changed : p).ToList();
    }

    private void ReadAloudName_Changed(object sender, RoutedEventArgs e) => Change(p => p with { Name = ReadAloudNameBox.Text });

    // A voice belongs to its engine and model: a new one starts with the reader's.
    private void ReadAloudEngine_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (ReadAloudEngineBox.SelectedValue is R.Engine engine) Change(p => p.Engine == engine ? p : p with { Engine = engine, Voice = "" });
    }

    private void ReadAloudModel_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (ReadAloudModelBox.SelectedValue is string model) Change(p => p.Model == model ? p : p with { Model = model, Voice = "" });
    }

    private void ReadAloudVoice_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (ReadAloudVoiceBox.SelectedValue is string v) Change(p => p with { Voice = v });
    }

    private void ReadAloudReader_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (ReadAloudReaderBox.SelectedValue is string who) Change(p => p with { Character = who });
    }

    private void ReadAloudPace_Changed(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (showingReadAloud) return;
        ReadAloudPaceValue.Text = R.SpeedLabel(e.NewValue);
        Change(p => p with { Speed = e.NewValue });
    }

    private void ReadAloudRest_Changed(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (showingReadAloud) return;
        Change(p => p with { Pause = e.NewValue });
    }

    private void ReadAloudLanguage_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (ReadAloudLanguageBox.SelectedValue is string code) Change(p => p with { Language = code });
    }

    private void ReadAloudAdd_Click(object sender, RoutedEventArgs e)
    {
        if (settings.ReadAloudPresets.Count >= R.MostPresets) return;
        var made = ChosenPreset with { Id = Guid.NewGuid(), Name = R.FreeName(L10n.Tr("My preset"), settings.ReadAloudPresets) };
        editingPreset = made.Id;
        settings.ReadAloudPresets = settings.ReadAloudPresets.Append(made).ToList();
    }

    private void ReadAloudDelete_Click(object sender, RoutedEventArgs e)
    {
        if (settings.ReadAloudPresets.Count <= 1) return;
        var chosen = ChosenPreset;
        editingPreset = null;
        // The default follows a deleted one to the first (AppSettings does it).
        settings.ReadAloudPresets = settings.ReadAloudPresets.Where(p => p.Id != chosen.Id).ToList();
    }

    private void ReadAloudStartWith_Click(object sender, RoutedEventArgs e) => settings.ReadAloudDefaultPreset = R.IdString(ChosenPreset.Id);

    /// <summary>A line in the preset's voice, so the choice can be heard.</summary>
    private void ReadAloudTry_Click(object sender, RoutedEventArgs e)
    {
        if (ReadAloudPlayer is not { } player) return;
        var chosen = ChosenPreset;
        var line = chosen.ForcedLanguage?.Code switch
        {
            "ru" => "Привет! Так я читаю вслух: спокойно, с паузой в конце абзаца.",
            "he" => "שלום! ככה אני קורא בקול רם.",
            _ => L10n.Tr("Hello! This is how I read aloud, with a rest at the end of each paragraph."),
        };
        player.Read(line, chosen);
    }

    private void ReadAloudFolder_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { InitialDirectory = settings.ReadAloudFolderPath };
        if (dialog.ShowDialog(this) == true) settings.ReadAloudFolder = AppSettings.FolderSaved(dialog.FolderName);
    }

    private void ReadAloudFormat_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (!showingReadAloud && ReadAloudFormatBox.SelectedValue is R.Format format) settings.ReadAloudFormat = format;
    }

    private void ReadAloudHelper_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (showingReadAloud || ReadAloudHelperBox.SelectedValue is not string who) return;
        settings.ReadAloudHelperEnabled = who != NobodyBrings;
        if (who != NobodyBrings) settings.ReadAloudHelper = who;
    }

    private void ReadAloudShortcutButton_Click(object sender, RoutedEventArgs e)
    {
        Record(ReadAloudShortcutButton, made => settings.ReadAloudShortcut = made);
        ShowReadAloud();
    }

    /// <summary>OpenRouter's speech models (and the local server's voices), the first time the page is seen.</summary>
    private void LoadSpeechModelsOnce()
    {
        if (voice is null || loadingSpeechModels || voice.Models.Count > 0) return;
        loadingSpeechModels = true;
        _ = Load();
        async Task Load()
        {
            try
            {
                await voice.LoadModels();
                ReadAloudModelsProblem.Text = "";
            }
            catch (ChatClient.Failure e) { ReadAloudModelsProblem.Text = L10n.Tr("could not load OpenRouter's speech models: %@", e.Message); }
            finally { loadingSpeechModels = false; }
            ShowReadAloud();
        }
    }
}

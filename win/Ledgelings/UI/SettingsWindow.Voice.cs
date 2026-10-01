using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Settings › Voice: how they all sound at the top, each character on screen below.</summary>
public sealed partial class SettingsWindow
{
    private Voice? voice;
    private bool syncingVoice;
    /// <summary>What the last Cast with Model said, per character, until the window closes.</summary>
    private readonly Dictionary<string, string> castNotes = new();
    /// <summary>Characters whose "Custom blend…" was picked; the field shows even before anything is typed.</summary>
    private readonly HashSet<string> blending = new();
    private bool castingAll;
    /// <summary>Characters being cast with the model right now: their button stays greyed through any rebuild.</summary>
    private readonly HashSet<string> castingNames = new();
    private const string CustomBlend = "\u0001custom";

    /// <summary>Kokoro-FastAPI on Windows, for PowerShell: fetch it once, then start it.</summary>
    public const string KokoroSetup = "if (-not (Test-Path ~\\Kokoro-FastAPI)) { git clone https://github.com/remsky/Kokoro-FastAPI.git ~\\Kokoro-FastAPI }; cd ~\\Kokoro-FastAPI; .\\start-cpu.ps1";

    /// <summary>Who speaks; the Voice tab needs it, so it is handed over as the window is made.</summary>
    public Voice? Voice
    {
        get => voice;
        init { voice = value; InitVoice(); }
    }

    private static readonly HashSet<string> VoiceProperties = new()
    {
        nameof(AppSettings.VoiceEngine), nameof(AppSettings.VoicePerCharacter), nameof(AppSettings.SystemVoice), nameof(AppSettings.VoiceModel),
        nameof(AppSettings.OpenRouterVoice), nameof(AppSettings.LocalVoice), nameof(AppSettings.OpenRouterKey), nameof(AppSettings.Brain),
        nameof(AppSettings.CartoonVoices), nameof(AppSettings.CastByPersonality),
    };

    private void InitVoice()
    {
        if (voice is null) return;
        NeedsModelNote(VoiceNeedsModel);
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is not string name || !VoiceProperties.Contains(name)) return;
            RefreshVoice();
            if (name is nameof(AppSettings.VoiceEngine)) LoadForEngine();
            if (name is not (nameof(AppSettings.OpenRouterKey) or nameof(AppSettings.SystemVoice) or nameof(AppSettings.OpenRouterVoice) or nameof(AppSettings.LocalVoice)))
                RefreshCharacterVoices();
        };
        voice.Changed += () => Dispatcher.InvokeAsync(RefreshVoiceStatus);
        Tabs.SelectionChanged += (_, e) =>
        {
            if (e.Source != Tabs || (Tabs.SelectedItem as TabItem)?.Header as string != "Voice") return;
            RefreshVoice();
            RefreshCharacterVoices();
            LoadForEngine();
        };
        RefreshVoice();
        RefreshCharacterVoices();
    }

    /// <summary>What the engine on show needs from the network: OpenRouter's models, or the local server's voices.</summary>
    private void LoadForEngine()
    {
        if (settings.VoiceEngine == VoiceEngine.OpenRouter) _ = LoadVoiceModels();
        if (settings.VoiceEngine == VoiceEngine.Local) _ = CheckLocal();
    }

    private static ComboBoxItem Choice(string title, string value) => new() { Content = title, Tag = value };

    private static void Fill(ComboBox box, IEnumerable<ComboBoxItem> items, string selected)
    {
        box.Items.Clear();
        foreach (var item in items) box.Items.Add(item);
        box.SelectedItem = box.Items.OfType<ComboBoxItem>().FirstOrDefault(i => (string)i.Tag == selected);
    }

    private void RefreshVoice()
    {
        if (voice is null) return;
        syncingVoice = true;
        var engine = settings.VoiceEngine;
        EngineSystem.IsChecked = engine == VoiceEngine.System;
        EngineOr.IsChecked = engine == VoiceEngine.OpenRouter;
        EngineLocal.IsChecked = engine == VoiceEngine.Local;
        SystemVoicePanel.Visibility = engine == VoiceEngine.System ? Visibility.Visible : Visibility.Collapsed;
        OrVoicePanel.Visibility = engine == VoiceEngine.OpenRouter ? Visibility.Visible : Visibility.Collapsed;
        LocalVoicePanel.Visibility = engine == VoiceEngine.Local ? Visibility.Visible : Visibility.Collapsed;
        LineVoicePanel.Visibility = engine == VoiceEngine.System ? Visibility.Collapsed : Visibility.Visible;

        Fill(SystemVoiceBox, new[] { Choice("System default", "") }
            .Concat(Voice.SystemVoices.Select(v => Choice($"{v.Name} · {v.Culture}", v.Name))), settings.SystemVoice);
        SystemVoiceBox.IsEnabled = !settings.VoicePerCharacter;

        // The key field is here unless OpenRouter is the brain too, and so on the Talk tab.
        VoiceKeyRow.Visibility = settings.Brain == BrainKind.OpenRouter ? Visibility.Collapsed : Visibility.Visible;
        if (VoiceKey.Password != settings.OpenRouterKey) VoiceKey.Password = settings.OpenRouterKey;
        var models = new List<ComboBoxItem>();
        if (!voice.Models.Any(m => m.Id == settings.VoiceModel)) models.Add(Choice(settings.VoiceModel, settings.VoiceModel));
        models.AddRange(voice.Models.Select(m => Choice($"{m.Id} · {m.PriceLabel}", m.Id)));
        Fill(VoiceModelBox, models, settings.VoiceModel);
        var modelVoices = voice.ModelVoices;
        var orVoices = new List<ComboBoxItem> { Choice("The model's first", "") };
        if (settings.OpenRouterVoice.Length > 0 && !modelVoices.Contains(settings.OpenRouterVoice)) orVoices.Add(Choice(settings.OpenRouterVoice, settings.OpenRouterVoice));
        orVoices.AddRange(modelVoices.Select(v => Choice(v, v)));
        Fill(OrVoiceBox, orVoices, settings.OpenRouterVoice);
        OrVoiceBox.IsEnabled = !settings.VoicePerCharacter;

        var localVoices = new List<ComboBoxItem> { Choice("The server's first", "") };
        if (settings.LocalVoice.Length > 0 && !voice.LocalVoices.Contains(settings.LocalVoice)) localVoices.Add(Choice(settings.LocalVoice, settings.LocalVoice));
        localVoices.AddRange(voice.LocalVoices.Select(v => Choice(v, v)));
        Fill(LocalVoiceBox, localVoices, settings.LocalVoice);
        LocalVoiceBox.IsEnabled = !settings.VoicePerCharacter;

        CastEveryone.IsEnabled = !castingAll && settings.HasModel && voice.Cast().Count > 0;
        VoiceFooter.Text = VoiceFooterText();
        syncingVoice = false;
        RefreshVoiceStatus();
    }

    private void RefreshVoiceStatus()
    {
        if (voice is null) return;
        VoiceStatus.Text = voice.Status;
        KeptCount.Text = $"{voice.Clips.Count} lines";
        SavedCount.Text = $"{voice.LineClips.Count} lines";
        ClearLineVoices.IsEnabled = voice.LineClips.Count > 0;
    }

    private void Engine_Checked(object sender, RoutedEventArgs e)
    {
        if (syncingVoice) return;
        settings.VoiceEngine = EngineSystem.IsChecked == true ? VoiceEngine.System : EngineOr.IsChecked == true ? VoiceEngine.OpenRouter : VoiceEngine.Local;
    }

    private static string? Picked(ComboBox box) => (box.SelectedItem as ComboBoxItem)?.Tag as string;

    private void SystemVoiceBox_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (!syncingVoice && Picked(SystemVoiceBox) is string v) settings.SystemVoice = v;
    }

    private void VoiceModelBox_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (syncingVoice || Picked(VoiceModelBox) is not string id || id == settings.VoiceModel) return;
        settings.VoiceModel = id;
        settings.OpenRouterVoice = "";
    }

    private void OrVoiceBox_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (!syncingVoice && Picked(OrVoiceBox) is string v) settings.OpenRouterVoice = v;
    }

    private void LocalVoiceBox_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (!syncingVoice && Picked(LocalVoiceBox) is string v) settings.LocalVoice = v;
    }

    private void VoiceKey_Changed(object sender, RoutedEventArgs e)
    {
        if (!syncingVoice) settings.OpenRouterKey = VoiceKey.Password;
    }

    private void RevealVoices_Click(object sender, RoutedEventArgs e) => voice?.RevealArchive();
    private void RevealLineVoices_Click(object sender, RoutedEventArgs e) => voice?.RevealLineArchive();
    private void ClearLineVoices_Click(object sender, RoutedEventArgs e) => voice?.ClearLineArchive();
    private void VoiceTest_Click(object sender, RoutedEventArgs e) => voice?.Introduce();
    private void VoiceStop_Click(object sender, RoutedEventArgs e) => voice?.Stop();

    private void CopySetup_Click(object sender, RoutedEventArgs e)
    {
        try { Clipboard.SetText(KokoroSetup); }
        catch (System.Runtime.InteropServices.ExternalException) { LocalCheckStatus.Text = "the clipboard is busy; try again"; return; }
        LocalCheckStatus.Text = "copied; paste it into PowerShell, wait for \"Uvicorn running\", then Check";
    }

    private void LocalCheck_Click(object sender, RoutedEventArgs e) => _ = CheckLocal();

    private async Task CheckLocal()
    {
        if (voice is null) return;
        LocalCheckStatus.Text = "checking…";
        try
        {
            var found = await voice.LoadLocalVoices(again: true);
            LocalCheckStatus.Text = $"ready: {found.Count} voices";
        }
        catch (Exception ex) { LocalCheckStatus.Text = ex.Message; }
        RefreshVoice();
        RefreshCharacterVoices();
    }

    private async Task LoadVoiceModels()
    {
        if (voice is null) return;
        try
        {
            await voice.LoadModels();
            VoiceListProblem.Visibility = Visibility.Collapsed;
        }
        catch (Exception ex)
        {
            VoiceListProblem.Text = "could not load OpenRouter's speech models: " + ex.Message;
            VoiceListProblem.Visibility = Visibility.Visible;
        }
        RefreshVoice();
        RefreshCharacterVoices();
    }

    private string VoiceFooterText()
    {
        const string lines = "The built-in lines (and the Test lines) are saved once said, in the line-voices folder beside the chats, and played from there the next time the same words come in the same voice and speed, so each is made only once: no wait on the server, nothing paid again. Clear forgets them all; each is made again when next said. ";
        const string shared = "Out loud, each line of a conversation waits for the one before to be said, then follows after the pause set here, its sound fetched while the other was talking; the silent bubble timing is not used. Speed follows pitch: a higher voice also talks a little faster (by the square root of its lift: 1.18× at 1.4×), because a voice asked to talk slowly to make up for the lift smears into an echo. Off keeps the pace exact. Cartoon voices lifts every character's pitch by an amount of its own (1.15 to 1.6 times, on top of Pitch) and picks the playful voices first. Every bubble is read out, in order; when talk runs far ahead of the voice, lines are skipped rather than read late. \"Hear Them Talk\" in the menu turns it on and off.";
        return settings.VoiceEngine switch
        {
            VoiceEngine.System => "Windows' own voices: free, offline, instant. More are added in Windows Settings › Time & language › Speech; the ones Windows offers to desktop programs are listed here. Windows has no character or novelty voices, so Cartoon voices lifts the pitch instead; with a voice each, the voices go round the cast, each at a slightly different pitch. " + shared,
            VoiceEngine.Local => "Any speech server on this PC that answers like OpenAI's /v1/audio/speech and lists voices at /v1/audio/voices, such as Kokoro-FastAPI (port 8880, model \"kokoro\", the same voices as OpenRouter's Kokoro). Free, offline once set up, and nothing is priced. \"Copy Setup Command\" puts Kokoro-FastAPI's install-and-start line on the clipboard, for PowerShell; it needs git and uv, and downloads about a gigabyte the first time. LM Studio cannot speak: its server has no speech endpoint. " + lines + shared,
            _ => "Speech models on OpenRouter sound far more alive, and cost a little per line: Kokoro is about $0.00003 a line. Uses the same key as the brain. What each line cost goes to the spend file a few seconds after it is said. Kept lines are WAV files in the voices folder beside the chats, listed in voices.jsonl with who said what; a line already kept in the same voice and speed is played from there, free. A voice each takes the model's English voices where it says which they are, and with Cartoon voices the playful ones among them (MiniMax's AnimeCharacter or PlayfulGirl, Voxtral's excited and cheerful). The pitch is shifted on this PC as the clip plays, so it costs nothing extra. " + lines + shared,
        };
    }

    // MARK: Characters

    private List<string> VoiceNames()
    {
        var seen = new List<string>();
        foreach (var name in voice?.Cast() ?? Array.Empty<string>()) if (!seen.Contains(name)) seen.Add(name);
        return seen;
    }

    /// <summary>One card per character on screen: its own voice, speed and pitch, and a Test.</summary>
    private void RefreshCharacterVoices()
    {
        if (voice is null) return;
        var names = VoiceNames();
        NoVoiceCharacters.Visibility = names.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        CharacterVoiceList.Children.Clear();
        foreach (var name in names) CharacterVoiceList.Children.Add(CharacterVoiceRow(name));
        CastEveryone.IsEnabled = !castingAll && settings.HasModel && names.Count > 0;
    }

    /// <summary>Rebuild the cards once the change in hand has landed, not inside the event that made it.</summary>
    private void RebuildCharacterVoicesSoon() => Dispatcher.InvokeAsync(RefreshCharacterVoices);

    private UIElement CharacterVoiceRow(string name)
    {
        var v = voice!;
        var own = settings.VoiceOf(name);
        var card = new StackPanel { Margin = new Thickness(0, 4, 0, 10) };

        var head = new DockPanel();
        var buttons = new StackPanel { Orientation = Orientation.Horizontal };
        DockPanel.SetDock(buttons, Dock.Right);
        var test = new Button { Content = "Test", MinWidth = 50 };
        test.Click += (_, _) => v.Introduce(name);
        var casting = castingNames.Contains(name);
        var cast = new Button { Content = casting ? "Casting…" : "Cast with Model", Margin = new Thickness(6, 0, 0, 0), IsEnabled = settings.HasModel && !casting };
        cast.Click += async (_, _) =>
        {
            if (!castingNames.Add(name)) return;
            cast.IsEnabled = false;
            cast.Content = "Casting…";
            try { castNotes[name] = "cast: " + await v.CastWithModel(name); }
            catch (Exception ex) { castNotes[name] = ex.Message; }
            finally { castingNames.Remove(name); }
            RefreshCharacterVoices();
        };
        var auto = new Button { Content = "Auto", Margin = new Thickness(6, 0, 0, 0), IsEnabled = !own.IsAutomatic };
        auto.Click += (_, _) =>
        {
            blending.Remove(name);
            settings.SetVoice(name, c => { c.SystemVoice = null; c.OpenRouterVoice = null; c.LocalVoice = null; c.Speed = null; c.Pitch = null; c.FollowPitch = null; });
            RebuildCharacterVoicesSoon();
        };
        buttons.Children.Add(test);
        buttons.Children.Add(cast);
        buttons.Children.Add(auto);
        head.Children.Add(buttons);
        head.Children.Add(new TextBlock { Text = name, FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center });
        card.Children.Add(head);
        if (castNotes.TryGetValue(name, out var note))
            card.Children.Add(new TextBlock { Text = note, FontSize = 11, Foreground = Brushes.Gray, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 2, 0, 0) });

        // The voice: automatic, or one of the engine's own.
        var engine = settings.VoiceEngine;
        var isBlend = own.LocalVoice is string lv && !v.LocalVoices.Contains(lv);
        var choices = new List<ComboBoxItem> { Choice($"Automatic ({v.AutomaticVoice(name)})", "") };
        string selected;
        switch (engine)
        {
            case VoiceEngine.System:
                choices.AddRange(Voice.SystemVoices.Select(s => Choice($"{s.Name} · {s.Culture}", s.Name)));
                selected = own.SystemVoice ?? "";
                break;
            case VoiceEngine.OpenRouter:
                if (own.OpenRouterVoice is string mine && !v.ModelVoices.Contains(mine)) choices.Add(Choice($"{mine} (not in this model)", mine));
                choices.AddRange(v.ModelVoices.Select(s => Choice(s, s)));
                selected = own.OpenRouterVoice ?? "";
                break;
            default:
                choices.Add(Choice("Custom blend…", CustomBlend));
                choices.AddRange(v.LocalVoices.Select(s => Choice(s, s)));
                selected = blending.Contains(name) || isBlend ? CustomBlend : own.LocalVoice ?? "";
                break;
        }
        var box = new ComboBox();
        Fill(box, choices, selected);
        box.SelectionChanged += (_, _) =>
        {
            if (Picked(box) is not string picked) return;
            if (picked == CustomBlend)
            {
                blending.Add(name);
                // Start from the voice it has now, so the blend begins as something heard.
                if (settings.VoiceOf(name).LocalVoice is null) { var heard = v.AutomaticVoice(name); settings.SetVoice(name, c => c.LocalVoice = heard); }
                RebuildCharacterVoicesSoon();
                return;
            }
            blending.Remove(name);
            var value = picked.Length == 0 ? null : picked;
            settings.SetVoice(name, c =>
            {
                switch (engine)
                {
                    case VoiceEngine.System: c.SystemVoice = value; break;
                    case VoiceEngine.OpenRouter: c.OpenRouterVoice = value; break;
                    default: c.LocalVoice = value; break;
                }
            });
            RebuildCharacterVoicesSoon();
        };
        card.Children.Add(Labelled("Voice", box));

        if (engine == VoiceEngine.Local && (blending.Contains(name) || isBlend))
        {
            var field = new TextBox { Text = own.LocalVoice ?? "", FontFamily = new FontFamily("Consolas"), ToolTip = "af_bella(2)+am_puck(1)" };
            var blendNote = new TextBlock { FontSize = 11, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(70, 2, 0, 0) };
            void ShowNote()
            {
                var typed = settings.VoiceOf(name).LocalVoice;
                var ok = typed is null || Core.Voices.IsUsable(typed, v.LocalVoices);
                blendNote.Foreground = ok ? Brushes.Gray : Brushes.Red;
                if (typed is null) { blendNote.Text = "Voices joined with +, each with an optional weight: af_bella(2)+am_puck(1) is two parts Bella, one part Puck."; return; }
                var parts = Core.Voices.BlendParts(typed);
                var unknown = parts.Where(p => !v.LocalVoices.Contains(p)).ToList();
                blendNote.Text = unknown.Count == 0 || v.LocalVoices.Count == 0
                    ? $"Blends {string.Join(", ", parts)}. Test to hear it."
                    : $"Not on the server: {string.Join(", ", unknown)}. Until fixed, this character uses its automatic voice.";
            }
            field.TextChanged += (_, _) =>
            {
                var clean = field.Text.Trim();
                settings.SetVoice(name, c => c.LocalVoice = clean.Length == 0 ? null : clean);
                ShowNote();
            };
            ShowNote();
            card.Children.Add(Labelled("Blend", field));
            card.Children.Add(blendNote);
        }

        card.Children.Add(VoiceSlider("Speed", Math.Round(v.OwnSpeed(name) * 100) / 100, value => settings.SetVoice(name, c => c.Speed = value)));
        // Shows the automatic pitch until moved, so the slider starts where the voice is.
        card.Children.Add(VoiceSlider("Pitch", Math.Round(v.OwnPitch(name) * 100) / 100, value => settings.SetVoice(name, c => c.Pitch = value)));

        var follow = new ComboBox();
        Fill(follow, new[]
        {
            Choice($"As overall ({(settings.SpeedFollowsPitch ? "on" : "off")})", "0"),
            Choice("On: no echo", "1"),
            Choice("Off: exact pace", "2"),
        }, own.FollowPitch is bool f ? (f ? "1" : "2") : "0");
        follow.SelectionChanged += (_, _) =>
        {
            if (Picked(follow) is not string choice) return;
            settings.SetVoice(name, c => c.FollowPitch = choice == "0" ? null : choice == "1");
            RebuildCharacterVoicesSoon();
        };
        card.Children.Add(Labelled("Speed follows pitch", follow, 130));
        return card;
    }

    private static DockPanel Labelled(string label, UIElement control, double width = 70)
    {
        var row = new DockPanel { Margin = new Thickness(0, 4, 0, 0) };
        row.Children.Add(new TextBlock { Text = label, Width = width, VerticalAlignment = VerticalAlignment.Center });
        row.Children.Add(control);
        return row;
    }

    /// <summary>A character's own Speed or Pitch: times the overall slider, 0.5× to 2× in steps of 0.05.</summary>
    private static DockPanel VoiceSlider(string label, double start, Action<double> changed)
    {
        var row = new DockPanel { Margin = new Thickness(0, 4, 0, 0) };
        row.Children.Add(new TextBlock { Text = label, Width = 70, VerticalAlignment = VerticalAlignment.Center });
        var value = new TextBlock { Width = 60, TextAlignment = TextAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
        DockPanel.SetDock(value, Dock.Right);
        row.Children.Add(value);
        var slider = new Slider { Minimum = AppSettings.VoiceSpeedMin, Maximum = AppSettings.VoiceSpeedMax, TickFrequency = 0.05, Value = start };
        value.Text = start.ToString("0.00", CultureInfo.CurrentCulture) + "×";
        slider.ValueChanged += (_, e) =>
        {
            var v = Math.Round(e.NewValue * 100) / 100;
            value.Text = v.ToString("0.00", CultureInfo.CurrentCulture) + "×";
            changed(v);
        };
        row.Children.Add(slider);
        return row;
    }

    private async void CastEveryone_Click(object sender, RoutedEventArgs e)
    {
        if (voice is null || castingAll) return;
        castingAll = true;
        CastEveryone.IsEnabled = false;
        CastEveryone.Content = "Casting…";
        CastAllNote.Visibility = Visibility.Visible;
        var done = new List<string>();
        try
        {
            foreach (var name in VoiceNames())
            {
                CastAllNote.Text = $"casting {name}…";
                try { done.Add($"{name}: {await voice.CastWithModel(name)}"); }
                catch (Exception ex) { done.Add($"{name}: {ex.Message}"); }
            }
            CastAllNote.Text = string.Join("\n", done);
        }
        finally
        {
            castingAll = false;
            CastEveryone.Content = "Cast Everyone with Model";
            RefreshCharacterVoices();
        }
    }
}

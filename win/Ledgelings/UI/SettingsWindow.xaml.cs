using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>The settings window: a sidebar of pages under five headings, with a search (SettingsWindow.Sidebar.cs), over
/// the settings, the sprite library, the spend ledger and the chat history. Simple bindings for the simple values;
/// the lists are rebuilt in code.</summary>
public sealed partial class SettingsWindow : Window
{
    private readonly AppSettings settings;
    private readonly ChatHistory history;
    private readonly SpriteLibrary library;
    private readonly SpendLedger spend;

    private sealed record ColourRow(int Index, string Hex, Brush Brush);
    private sealed record LanguageChoice(Language Language, string Title);
    private sealed record CursorMoodChoice(CursorMood Mood, string Title);
    private sealed record ScreenOption(string Id, string Title);
    /// <summary>Filling the screen list: its selection changing then is not the user's choice.</summary>
    private bool showingScreens;

    public SettingsWindow(AppSettings settings, ChatHistory history, SpriteLibrary library, SpendLedger spend)
    {
        this.settings = settings;
        this.history = history;
        this.library = library;
        this.spend = spend;
        InitializeComponent();
        LanguageBox.ItemsSource = Languages.All.Select(l => new LanguageChoice(l, l.Title())).ToList();
        ShowCursorMoods();
        ShowScreens();
        DataContext = settings;
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.Colors)) RefreshColours();
            if (e.PropertyName is nameof(AppSettings.Species)) RefreshSpecies();
            if (e.PropertyName is nameof(AppSettings.Brain)) RefreshBrain();
            if (e.PropertyName is nameof(AppSettings.Brain) or nameof(AppSettings.VoiceEngine) or nameof(AppSettings.OpenRouterKey) or nameof(AppSettings.SpriteKitForm)) RefreshSpriteKit();
            if (e.PropertyName is nameof(AppSettings.Script)) RefreshScriptStatus();
            if (e.PropertyName is "Casts") RefreshCast();
            if (e.PropertyName is nameof(AppSettings.Language)) ShowLanguage();
            if (e.PropertyName is nameof(AppSettings.HomeScreenId)) ShowScreens();
            if (e.PropertyName is nameof(AppSettings.Shortcut) or nameof(AppSettings.RecordingShortcut) or nameof(AppSettings.ShortcutProblem) or nameof(AppSettings.Language)) ShowShortcut();
        };
        InitActions();
        library.Changed += RefreshSpecies;
        spend.Changed += RefreshSpend;
        history.Changed += ReloadChats;
        RefreshColours();
        RefreshSpecies();
        RefreshBrain();
        RefreshSpend();
        RefreshCastSpecies();
        InitChats();
        InitFlowers();
        InitSpriteKit();
        ShowFooters();
        LmStatus.Text = OrStatus.Text = LocalCheckStatus.Text = LoginStatus.Text = L10n.Tr("not checked");
        InitTalkExtras();
        InitBonds();
        InitCalendar();
        InitPlay();
        InitDictation();
        InitTranslate();
        InitToolsScreen();
        InitSidebar();
        Closing += (_, e) => { e.Cancel = true; Hide(); };      // the window is reused; the app lives in the tray
    }

    /// <summary>The window up and in front, on whatever page is chosen (<see cref="Show(SettingsPage?)"/>).</summary>
    private void Bring()
    {
        if (!IsVisible) Show();
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
        Topmost = true;      // a tray app is never frontmost on its own
        Topmost = false;
        StartAtLogin.IsChecked = LaunchAtLogin.IsOn;
        LoginStatus.Text = LaunchAtLogin.Status;
    }

    /// <summary>The footers written in code, which name a folder or the placeholders.</summary>
    private void ShowFooters()
    {
        Language = XmlLanguage.GetLanguage(Languages.Current.Culture().IetfLanguageTag);      // dates in the date picker
        SpritesFooter.Text = L10n.Tr("Click a creature to put it in the colony or take it out. Creature 1 wears the first one chosen, creature 2 the second, and so on, starting over when they run out. New ones come from the sprite kit. Imported creatures live in %@.", library.Directory);
        RefreshSpriteKit();
        PromptFooter.Text = L10n.Tr("Placeholders: %@. {situation} is written by the app: your time, date and holidays (Calendar tab), the colony's day or night, and where each creature is. {line} is what was just said, for the reply. {relationship} is how the two get on and the story between them (Bonds tab); left out, it goes at the end of the prompt.",
            string.Join(" ", Banter.Placeholders.Select(p => "{" + p + "}")));
    }

    /// <summary>The cursor moods under their names in the current language, the chosen one kept.</summary>
    private void ShowCursorMoods()
    {
        CursorMoodBox.ItemsSource = CursorMoods.All.Select(m => new CursorMoodChoice(m, m.Title())).ToList();
        CursorMoodBox.SelectedValue = settings.CursorMood;
    }

    /// <summary>All screens, each attached monitor by name, and the chosen one while it is unplugged; the choice kept.
    /// Listed afresh each time it opens, so a monitor plugged in meanwhile is there.</summary>
    private void ShowScreens()
    {
        showingScreens = true;
        var options = new List<ScreenOption> { new(HomeScreen.All, L10n.Tr("All screens")) };
        options.AddRange(ScreenChoice.Attached().Select(m => new ScreenOption(m.Id, m.Name)));
        if (ScreenChoice.IsAway(settings)) options.Add(new(settings.HomeScreenId, L10n.Tr("%@ (unplugged)", settings.HomeScreenName)));
        ScreenBox.ItemsSource = options;
        ScreenBox.SelectedValue = settings.HomeScreenId;
        showingScreens = false;
    }

    private void ScreenBox_Opened(object? sender, EventArgs e) => ShowScreens();

    private void ScreenBox_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (showingScreens || ScreenBox.SelectedValue is not string id || id == settings.HomeScreenId) return;
        settings.LiveOn(ScreenChoice.Attached().FirstOrDefault(m => m.Id == id));
    }

    /// <summary>A new language while the window is open: every label, footer and list again, in it.
    /// The app has chosen it already (<see cref="Languages.Choose"/> runs first, from the launch).</summary>
    private void ShowLanguage()
    {
        Tr.Refresh();
        RefreshSidebar();
        RefreshTranslate();
        RefreshToolsScreen();
        ShowFooters();
        ShowCursorMoods();
        ShowScreens();
        LmStatus.Text = OrStatus.Text = LocalCheckStatus.Text = L10n.Tr("not checked");
        LoginStatus.Text = LaunchAtLogin.Status;
        RefreshBrain();
        RefreshCast();
        RefreshLineMemory();
        RefreshNeedsModelNotes();
        RefreshPlanters();
        RefreshBonds();
        RefreshBondList();
        RefreshCalendar();
        RefreshRepeatChoices();
        RefreshReminders();
        RefreshReminderFooter();
        RefreshVoice();
        RefreshCharacterVoices();
        RefreshSpend();
        ReloadChats();
    }

    // MARK: Creatures

    private void RefreshColours()
    {
        ColourList.ItemsSource = settings.Colors.Select((hex, i) =>
            new ColourRow(i, hex, new SolidColorBrush(Bitmaps.ToMedia(RGB.FromHex(hex) ?? RGB.White)))).ToList();
        AddColour.IsEnabled = settings.Colors.Count < AppSettings.MaxColors;
        RemoveColour.IsEnabled = settings.Colors.Count > 1;
    }

    private void Colour_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: int index } || index >= settings.Colors.Count) return;
        var current = RGB.FromHex(settings.Colors[index]) ?? RGB.White;
        if (ColourDialog.Ask(this, current) is RGB chosen) settings.SetColor(index, chosen.Hex);
    }

    private void AddColour_Click(object sender, RoutedEventArgs e)
    {
        if (settings.Colors.Count >= AppSettings.MaxColors) return;
        settings.Colors = settings.Colors.Append(AppSettings.DefaultColors[settings.Colors.Count % AppSettings.DefaultColors.Count]).ToList();
    }

    private void RemoveColour_Click(object sender, RoutedEventArgs e)
    {
        if (settings.Colors.Count > 1) settings.Colors = settings.Colors.Take(settings.Colors.Count - 1).ToList();
    }

    private void ResetColours_Click(object sender, RoutedEventArgs e) => settings.Colors = AppSettings.DefaultColors;

    private void StartAtLogin_Changed(object sender, RoutedEventArgs e)
    {
        var wanted = StartAtLogin.IsChecked == true;
        if (wanted == LaunchAtLogin.IsOn) return;
        try { LaunchAtLogin.Set(wanted); LoginStatus.Text = LaunchAtLogin.Status; }
        catch (Exception ex) when (ex is InvalidOperationException or UnauthorizedAccessException or IOException)
        {
            LoginStatus.Text = ex.Message;
            StartAtLogin.IsChecked = LaunchAtLogin.IsOn;
        }
    }
}

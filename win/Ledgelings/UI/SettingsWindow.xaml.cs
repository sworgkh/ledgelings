using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>The settings window: four tabs over the settings, the sprite library, the spend
/// ledger and the chat history. Simple bindings for the simple values; the lists are rebuilt in code.</summary>
public sealed partial class SettingsWindow : Window
{
    private readonly AppSettings settings;
    private readonly ChatHistory history;
    private readonly SpriteLibrary library;
    private readonly SpendLedger spend;

    private sealed record ColourRow(int Index, string Hex, Brush Brush);
    private sealed record LanguageChoice(Language Language, string Title);
    private sealed record CursorMoodChoice(CursorMood Mood, string Title);

    public SettingsWindow(AppSettings settings, ChatHistory history, SpriteLibrary library, SpendLedger spend)
    {
        this.settings = settings;
        this.history = history;
        this.library = library;
        this.spend = spend;
        InitializeComponent();
        LanguageBox.ItemsSource = Languages.All.Select(l => new LanguageChoice(l, l.Title())).ToList();
        ShowCursorMoods();
        DataContext = settings;
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.Colors)) RefreshColours();
            if (e.PropertyName is nameof(AppSettings.Species)) RefreshSpecies();
            if (e.PropertyName is nameof(AppSettings.Brain)) RefreshBrain();
            if (e.PropertyName is nameof(AppSettings.Script)) RefreshScriptStatus();
            if (e.PropertyName is "Casts") RefreshCast();
            if (e.PropertyName is nameof(AppSettings.Language)) ShowLanguage();
        };
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
        PromptBox.Text = library.Prompt;
        ShowFooters();
        LmStatus.Text = OrStatus.Text = LocalCheckStatus.Text = LoginStatus.Text = L10n.Tr("not checked");
        InitTalkExtras();
        InitBonds();
        InitCalendar();
        Closing += (_, e) => { e.Cancel = true; Hide(); };      // the window is reused; the app lives in the tray
    }

    /// <summary>Bring the window up, on the given tab if asked.</summary>
    public void Show(SettingsTab? tab)
    {
        // By header, not position: tabs are added feature by feature.
        if (tab is SettingsTab t && Tabs.Items.OfType<TabItem>().FirstOrDefault(i => Tr.GetHeader(i) == t.ToString()) is TabItem item)
            Tabs.SelectedItem = item;
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
        SpritesFooter.Text = L10n.Tr("Click a creature to put it in the colony or take it out. Creature 1 wears the first one chosen, creature 2 the second, and so on, starting over when they run out. Import a text sheet (.txt) from the kit below, or a 288×96 PNG painted on magenta from the template. Sheets live in %@.", library.Directory);
        PromptFooter.Text = L10n.Tr("Placeholders: %@. {situation} is written by the app: your time, date and holidays (Calendar tab), the colony's day or night, and where each creature is. {line} is what was just said, for the reply. {relationship} is how the two get on and the story between them (Bonds tab); left out, it goes at the end of the prompt.",
            string.Join(" ", Banter.Placeholders.Select(p => "{" + p + "}")));
    }

    /// <summary>The cursor moods under their names in the current language, the chosen one kept.</summary>
    private void ShowCursorMoods()
    {
        CursorMoodBox.ItemsSource = CursorMoods.All.Select(m => new CursorMoodChoice(m, m.Title())).ToList();
        CursorMoodBox.SelectedValue = settings.CursorMood;
    }

    /// <summary>A new language while the window is open: every label, footer and list again, in it.
    /// The app has chosen it already (<see cref="Languages.Choose"/> runs first, from the launch).</summary>
    private void ShowLanguage()
    {
        Tr.Refresh();
        ShowFooters();
        ShowCursorMoods();
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

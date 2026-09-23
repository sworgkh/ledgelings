using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

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

    public SettingsWindow(AppSettings settings, ChatHistory history, SpriteLibrary library, SpendLedger spend)
    {
        this.settings = settings;
        this.history = history;
        this.library = library;
        this.spend = spend;
        InitializeComponent();
        DataContext = settings;
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.Colors)) RefreshColours();
            if (e.PropertyName is nameof(AppSettings.Species)) RefreshSpecies();
            if (e.PropertyName is nameof(AppSettings.Brain)) RefreshBrain();
            if (e.PropertyName is nameof(AppSettings.Script)) RefreshScriptStatus();
            if (e.PropertyName is "Casts") RefreshCast();
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
        PromptBox.Text = library.Prompt;
        SpritesFooter.Text = "Click a creature to put it in the colony or take it out. Creature 1 wears the first one chosen, creature 2 the second, and so on, starting over when they run out. Import a text sheet (.txt) from the kit below, or a 288×96 PNG painted on magenta from the template. Sheets live in " + library.Directory + ".";
        PromptFooter.Text = "Placeholders: " + string.Join(" ", Core.Banter.Placeholders.Select(p => "{" + p + "}")) + ". {situation} is written by the app: time of day and where each creature is. {line} is what was just said, for the reply.";
        Closing += (_, e) => { e.Cancel = true; Hide(); };      // the window is reused; the app lives in the tray
    }

    /// <summary>Bring the window up, on the given tab if asked.</summary>
    public void Show(SettingsTab? tab)
    {
        if (tab is SettingsTab t) Tabs.SelectedIndex = (int)t;
        if (!IsVisible) Show();
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
        Topmost = true;      // a tray app is never frontmost on its own
        Topmost = false;
        StartAtLogin.IsChecked = LaunchAtLogin.IsOn;
        LoginStatus.Text = LaunchAtLogin.Status;
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

using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Every aspect of the weather and the sky (SPEC §7.20), the Mac's <c>WeatherSettingsView</c>: shown in the
/// Weather &amp; Sky window, and read by the settings search for the Weather &amp; Sky page.</summary>
public sealed partial class WeatherSkyPanel : UserControl
{
    private sealed record Choice(string Title, int Index);

    private readonly AppSettings settings;
    /// <summary>Starts one now by its code (a weather, <c>winter</c>, <c>night</c>, or <c>stop</c>, <c>pause</c>,
    /// <c>resume</c>); false when it could not.</summary>
    public Func<string, bool>? Play { get; set; }

    public WeatherSkyPanel(AppSettings settings)
    {
        this.settings = settings;
        InitializeComponent();
        DataContext = settings;
        ReduceMotionBox.ItemsSource = Enum.GetValues<Effects.ReduceMotion>().Select(r => new Choice(r.Title(), (int)r)).ToList();
        FrequencyBox.ItemsSource = Weather.Frequencies.Select(f => new Choice(f.Title(), (int)f)).ToList();
        FlakeSizeBox.ItemsSource = Weather.FlakeSizes.Select(f => new Choice(f.Title(), (int)f)).ToList();
        var levels = Weather.Levels.Select(l => new Choice(l.Title(), (int)l)).ToList();
        SnowDepthBox.ItemsSource = levels;
        WindStrengthBox.ItemsSource = levels;
        FirefliesFromBox.ItemsSource = AppSettings.SkyFirefliesHours
            .Select((h, i) => new Choice(h == AppSettings.SkyNightFollowsColony ? L10n.Tr("with the creatures' night") : L10n.Tr("from %d:00", h), i)).ToList();
        foreach (var (button, box, kind) in new (Button, CheckBox, Weather.Kind)[]
                 {
                     (PlaySnow, SnowBox, Weather.Kind.Snow), (PlayRain, RainBox, Weather.Kind.Rain),
                     (PlayWind, WindBox, Weather.Kind.Wind), (PlayStorm, StormBox, Weather.Kind.Storm),
                 })
        {
            button.ToolTip = L10n.Tr("Start %@ now", kind.Title().ToLowerInvariant());
            box.ToolTip = kind.Detail();
        }
        StopNow.ToolTip = L10n.Tr("The weather, the falling leaves and the fireflies fade out now, and the snow lying goes");
        PauseToday.ToolTip = L10n.Tr("No weather, falling leaves, petals or fireflies until tomorrow; what is out now stops");
        ShowPaused();
        // The tray's Pause Weather for Today changes it too: the button follows while the panel is shown.
        PropertyChangedEventHandler changed = (_, e) => { if (e.PropertyName == nameof(AppSettings.WeatherPausedDay)) Dispatcher.BeginInvoke(ShowPaused); };
        Loaded += (_, _) => { settings.PropertyChanged += changed; ShowPaused(); };
        Unloaded += (_, _) => settings.PropertyChanged -= changed;
    }

    private void ShowPaused() => PauseToday.Content = settings.WeatherPausedToday ? L10n.Tr("Resume today") : L10n.Tr("Pause for today");

    private void Play_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: string code } && Play?.Invoke(code) == true) return;
        System.Media.SystemSounds.Beep.Play();
    }

    private void Pause_Click(object sender, RoutedEventArgs e)
    {
        var code = settings.WeatherPausedToday ? "resume" : "pause";
        if (Play?.Invoke(code) != true) settings.PauseWeather(code == "pause", DateTime.Now);
        ShowPaused();
    }
}

using System.Windows;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Settings › Weather &amp; Sky (SPEC §7.20), the Mac's <c>WeatherPageView</c>: the main switch, Open Weather &amp;
/// Sky…, Stop now and Pause for today. Every aspect is in the Weather &amp; Sky window (<see cref="WeatherSkyPanel"/>),
/// which the page opens as it comes up.</summary>
public sealed partial class SettingsWindow
{
    /// <summary>Starts a weather by its code (<c>snow</c>, <c>storm</c>, <c>autumn</c>, <c>night</c>), or <c>stop</c>,
    /// <c>pause</c>, <c>resume</c>; false when it could not.</summary>
    public Func<string, bool>? PlayWeather { get; set; }

    private void InitWeather()
    {
        WeatherStopNow.ToolTip = L10n.Tr("The weather, the falling leaves and the fireflies fade out now, and the snow lying goes");
        WeatherPauseToday.ToolTip = L10n.Tr("No weather, falling leaves, petals or fireflies until tomorrow; what is out now stops");
        ShowWeatherPaused();
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(AppSettings.WeatherPausedDay)) Dispatcher.BeginInvoke(ShowWeatherPaused);
        };
    }

    private void ShowWeatherPaused() =>
        WeatherPauseToday.Content = settings.WeatherPausedToday ? L10n.Tr("Resume today") : L10n.Tr("Pause for today");

    /// <summary>The Weather &amp; Sky window, with every aspect in it.</summary>
    private void OpenWeatherWindow() => WeatherWindow.ShowWindow(settings, PlayWeather);

    private void WeatherOpen_Click(object sender, RoutedEventArgs e) => OpenWeatherWindow();

    private void WeatherPlay_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: string code } && PlayWeather?.Invoke(code) == true) return;
        System.Media.SystemSounds.Beep.Play();
    }

    private void WeatherPause_Click(object sender, RoutedEventArgs e)
    {
        var code = settings.WeatherPausedToday ? "resume" : "pause";
        if (PlayWeather?.Invoke(code) != true) settings.PauseWeather(code == "pause", DateTime.Now);
        ShowWeatherPaused();
    }
}

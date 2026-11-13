using Ledgelings.Core;
using Ledgelings.UI;

namespace Ledgelings;

/// <summary>The tray's Weather submenu (SPEC §7.20): each weather now, the one falling ticked, Clear sky, Pause Weather
/// for Today and the Weather &amp; Sky window; beside it Stop Weather, only while weather, the season's particles or the
/// fireflies are out. A Windows menu shows no tooltips, so what each does is said in the Weather &amp; Sky window and in
/// Creature Actions.</summary>
public sealed partial class App
{
    private void AddWeatherItem(List<TrayIcon.Item> items)
    {
        if (colony is null || settings is null) return;
        var now = colony.WeatherNow;
        var paused = settings.WeatherPausedToday;
        var children = Weather.Kinds
            .Select(kind => new TrayIcon.Item(kind.Title(), () => colony?.PlayWeather(kind.Code()), Checked: now == kind))
            .Append(TrayIcon.Item.Separator)
            .Append(new TrayIcon.Item(L10n.Tr("Clear sky"), () => colony?.PlayWeather("clear"), Checked: now is null))
            .Append(new TrayIcon.Item(L10n.Tr("Pause Weather for Today"), () => colony?.PlayWeather(paused ? "resume" : "pause"), Checked: paused))
            .Append(TrayIcon.Item.Separator)
            .Append(new TrayIcon.Item(L10n.Tr("Weather & Sky Settings…"), OpenWeatherWindow))
            .ToList();
        items.Add(new TrayIcon.Item(L10n.Tr("Weather"), Children: children));
        if (colony.WeatherRunning) items.Add(new TrayIcon.Item(L10n.Tr("Stop Weather"), () => colony?.PlayWeather("stop")));
    }

    /// <summary>The Weather &amp; Sky window, with every aspect of the weather and the sky in it.</summary>
    private void OpenWeatherWindow()
    {
        if (settings is null) return;
        WeatherWindow.ShowWindow(settings, code => colony?.PlayWeather(code) ?? false);
    }
}

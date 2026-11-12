using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The tray's Weather submenu (SPEC §7.20): each weather now, the one falling ticked, and Clear sky.
/// A Windows menu shows no tooltips, so what each does is said on the Weather page and in Creature Actions.</summary>
public sealed partial class App
{
    private void AddWeatherItem(List<TrayIcon.Item> items)
    {
        if (colony is null) return;
        var now = colony.WeatherNow;
        var children = Weather.Kinds
            .Select(kind => new TrayIcon.Item(kind.Title(), () => colony?.PlayWeather(kind.Code()), Checked: now == kind))
            .Append(TrayIcon.Item.Separator)
            .Append(new TrayIcon.Item(L10n.Tr("Clear sky"), () => colony?.PlayWeather("clear"), Checked: now is null))
            .ToList();
        items.Add(new TrayIcon.Item(L10n.Tr("Weather"), Children: children));
    }
}

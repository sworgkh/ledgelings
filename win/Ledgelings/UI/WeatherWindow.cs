using System.Windows;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>The Weather &amp; Sky window, the Mac's <c>WeatherWindowController</c>: every aspect of the weather and the sky
/// in three columns (<see cref="WeatherSkyPanel"/>), too much for one settings page. Opened from its settings page, the
/// tray's Weather submenu and a search.</summary>
public sealed class WeatherWindow : Window
{
    private static WeatherWindow? open;

    public static void ShowWindow(AppSettings settings, Func<string, bool>? play)
    {
        open ??= new WeatherWindow(settings, play);
        open.Show();
        if (open.WindowState == WindowState.Minimized) open.WindowState = WindowState.Normal;
        open.Activate();
    }

    private WeatherWindow(AppSettings settings, Func<string, bool>? play)
    {
        WindowPlacer.Keep(this, WindowPlaces.Window.Weather, settings);
        Title = L10n.Tr("Weather & Sky");
        // Three columns of about 420: everything fits without scrolling on a 1366×768 screen and up.
        Width = 1280; Height = 760; MinWidth = 1000; MinHeight = 600;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Content = new System.Windows.Controls.ScrollViewer
        {
            VerticalScrollBarVisibility = System.Windows.Controls.ScrollBarVisibility.Auto,
            Content = new WeatherSkyPanel(settings) { Play = play },
        };
        Closed += (_, _) => open = null;
    }
}

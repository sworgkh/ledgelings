using System.Windows;
using System.Windows.Controls;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Settings › Weather (SPEC §7.20), the Mac's WeatherSettingsView: the switches and when it comes on the left;
/// how deep, how heavy, how strong, and the umbrellas on the right. Each weather has Play now, which starts it at once,
/// quiet screen or not; Clear sky eases it off.</summary>
public sealed partial class SettingsWindow
{
    /// <summary>Starts a weather by its code (<c>snow</c>, <c>storm</c>), or <c>clear</c>; false when it could not.</summary>
    public Func<string, bool>? PlayWeather { get; set; }

    private sealed record WeatherChoice(string Title, int Index);

    private void InitWeather()
    {
        WeatherReduceMotionBox.ItemsSource = Enum.GetValues<Effects.ReduceMotion>().Select(r => new WeatherChoice(r.Title(), (int)r)).ToList();
        WeatherFrequencyBox.ItemsSource = Weather.Frequencies.Select(f => new WeatherChoice(f.Title(), (int)f)).ToList();
        var levels = Weather.Levels.Select(l => new WeatherChoice(l.Title(), (int)l)).ToList();
        WeatherSnowDepthBox.ItemsSource = levels;
        WeatherRainBox2.ItemsSource = levels;
        WeatherWindBox2.ItemsSource = levels;
        foreach (var (button, box, kind) in new (Button, CheckBox?, Weather.Kind)[]
                 {
                     (WeatherPlaySnow, WeatherSnowBox, Weather.Kind.Snow), (WeatherPlayRain, WeatherRainBox, Weather.Kind.Rain),
                     (WeatherPlayWind, WeatherWindBox, Weather.Kind.Wind), (WeatherPlayStorm, null, Weather.Kind.Storm),
                 })
        {
            button.ToolTip = L10n.Tr("Start %@ now", kind.Title().ToLowerInvariant());
            if (box is not null) box.ToolTip = kind.Detail();
        }
    }

    private void WeatherPlay_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: string code } && PlayWeather?.Invoke(code) == true) return;
        System.Media.SystemSounds.Beep.Play();
    }
}

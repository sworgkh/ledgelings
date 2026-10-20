using System.Windows.Media.Imaging;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Settings › Play (SPEC §7.10): whether they play, which games and how often; how each game goes,
/// and the props it is played with; Settings › Ball games, soccer and baseball. The Mac's PlaySettingsView and
/// BallGamesSettingsView.</summary>
public sealed partial class SettingsWindow
{
    private void InitPlay()
    {
        try
        {
            var props = SpriteAtlas.Named("play").MakeFrames();
            PropList.ItemsSource = new[] { "ball", "hoop", "chute", "hook", "drop" }
                .Select(name => props.Frame(name, 0) is { } image ? Bitmaps.ToSource(ActionIcons.Trimmed(image)) : null)
                .OfType<BitmapSource>().ToList();
            BallPropList.ItemsSource = new[] { "soccer", "net", "bat", "baseball", "base", "base-taken" }
                .Select(name => props.Frame(name, 0) is { } image ? Bitmaps.ToSource(ActionIcons.Trimmed(image)) : null)
                .OfType<BitmapSource>().ToList();
        }
        catch (Exception e) when (e is IOException or ArgumentException) { }
    }
}

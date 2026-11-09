using System.Windows.Media.Imaging;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Settings › Play (SPEC §7.10): whether they play, which games and how often; how each game goes,
/// and the props it is played with; Settings › Ball games, soccer and baseball; Settings › Surfing, its session, waves
/// and boards. The Mac's PlaySettingsView, BallGamesSettingsView and SurfingSettingsView.</summary>
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
            SurfBoardList.ItemsSource = Enumerable.Range(0, Plays.Surf.BoardCount)
                .Select(n => props.Frame($"board-{n}", 0) is { } image ? Bitmaps.ToSource(ActionIcons.Trimmed(image)) : null)
                .OfType<BitmapSource>().ToList();
            SurfSplashList.ItemsSource = new[] { ("splash", 0.15), ("spray", 0.0) }
                .Select(x => props.Frame(x.Item1, x.Item2) is { } image ? Bitmaps.ToSource(ActionIcons.Trimmed(image)) : null)
                .OfType<BitmapSource>().ToList();
        }
        catch (Exception e) when (e is IOException or ArgumentException) { }
    }
}

using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;

namespace Ledgelings.UI;

/// <summary>Settings › Sprites: which creature sheets are in use, importing new ones, and the sprite kit.</summary>
public sealed partial class SettingsWindow
{
    private sealed record SpeciesCard(string Name, BitmapSource? Image, Brush Border, Brush Fill, string Check,
                                      FontWeight Weight, Visibility DeleteVisibility);

    private static readonly Brush Accent = new SolidColorBrush(Color.FromRgb(0, 120, 212));
    private static readonly Brush AccentFill = new SolidColorBrush(Color.FromArgb(36, 0, 120, 212));
    private static readonly Brush QuietFill = new SolidColorBrush(Color.FromArgb(18, 0, 0, 0));

    private void RefreshSpecies()
    {
        SpeciesList.ItemsSource = library.AllSpecies.Select(s =>
        {
            var chosen = settings.Species.Contains(s.Name);
            return new SpeciesCard(s.Name, Bitmaps.Preview(s.Atlas), chosen ? Accent : Brushes.Transparent, chosen ? AccentFill : QuietFill,
                chosen ? "\u2714" : "\u25CB", chosen ? FontWeights.SemiBold : FontWeights.Normal,
                s.IsBuiltIn ? Visibility.Collapsed : Visibility.Visible);
        }).ToList();
        RefreshCastSpecies();
    }

    private void Species_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is Border { Tag: string name }) settings.ToggleSpecies(name);
    }

    private void Species_Delete(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string name }) return;
        library.Remove(name);
        settings.Species = settings.Species.Where(s => s != name).ToList();
    }

    private void ImportSheet_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Title = "A sprite text file from the kit, or a 288×96 PNG on magenta.",
            Filter = "Sprite sheets (*.txt;*.md;*.png)|*.txt;*.md;*.png|All files|*.*",
        };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            var name = library.ImportFile(dialog.FileName);
            if (!settings.Species.Contains(name)) settings.Species = settings.Species.Append(name).ToList();
            SpriteStatus.Text = "imported " + name;
        }
        catch (Exception ex) when (ex is SpriteLibrary.ImportException or IOException or UnauthorizedAccessException)
        {
            SpriteStatus.Text = ex.Message;
        }
    }

    private void OpenSpritesFolder_Click(object sender, RoutedEventArgs e) => library.OpenFolder();

    private async void CopyPrompt_Click(object sender, RoutedEventArgs e)
    {
        try { Clipboard.SetText(library.Prompt); }
        catch (System.Runtime.InteropServices.COMException) { SpriteStatus.Text = "the clipboard is busy; try again"; return; }
        CopyPrompt.Content = "Copied";
        await Task.Delay(2000);
        CopyPrompt.Content = "Copy Prompt";
    }

    private void SaveExample_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new SaveFileDialog { FileName = "blocky.txt", Filter = "Text|*.txt" };
        if (dialog.ShowDialog(this) != true) return;
        try { File.WriteAllText(dialog.FileName, library.ExampleText); SpriteStatus.Text = "saved " + Path.GetFileName(dialog.FileName); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { SpriteStatus.Text = ex.Message; }
    }

    private void SaveTemplate_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new SaveFileDialog { FileName = "ledgelings-template.png", Filter = "PNG|*.png" };
        if (dialog.ShowDialog(this) != true) return;
        try { PngIO.Write(library.TemplateImage(), dialog.FileName); SpriteStatus.Text = "saved " + Path.GetFileName(dialog.FileName); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Runtime.InteropServices.ExternalException) { SpriteStatus.Text = ex.Message; }
    }
}

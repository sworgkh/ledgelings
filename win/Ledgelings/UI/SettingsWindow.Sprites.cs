using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Ledgelings.Core;
using Microsoft.Win32;

namespace Ledgelings.UI;

/// <summary>Settings › Sprites: which creature sheets are in use, and the sprite kit: a small form, a prompt
/// built from it for an image model, the two pictures to attach, and the import that reads back what it paints.</summary>
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
            Title = L10n.Tr("The picture the image model painted, or a hand-written text sheet."),
            Filter = L10n.Tr("Sprite sheets") + " (*.png;*.jpg;*.jpeg;*.webp;*.txt;*.md)|*.png;*.jpg;*.jpeg;*.webp;*.txt;*.md|" + L10n.Tr("All files") + "|*.*",
        };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            var name = library.ImportFile(dialog.FileName, settings.SpriteKitForm);
            if (!settings.Species.Contains(name)) settings.Species = settings.Species.Append(name).ToList();
            SpriteStatus.Text = L10n.Tr("imported %@", name);
        }
        catch (Exception ex) when (ex is SpriteLibrary.ImportException or IOException or UnauthorizedAccessException)
        {
            SpriteStatus.Text = ex.Message;
        }
    }

    private void OpenSpritesFolder_Click(object sender, RoutedEventArgs e) => library.OpenFolder();

    // MARK: The sprite kit

    private bool fillingKit;

    private TextBox[] KitNames => new[] { KitCast0Name, KitCast1Name, KitCast2Name };
    private TextBox[] KitPersonas => new[] { KitCast0Persona, KitCast1Persona, KitCast2Persona };

    private void InitSpriteKit()
    {
        KitPoses.Source = Source(library.KitImages[0].Image);
        KitTemplate.Source = Source(library.KitImages[1].Image);
        KitPoses.ToolTip = library.KitImages[0].Name;
        KitTemplate.ToolTip = library.KitImages[1].Name;
        RefreshSpriteKit();
    }

    /// <summary>The form's fields as a form; the colour comes from the settings, set by the swatch.</summary>
    private SpriteKit.Form FormFromFields() => settings.SpriteKitForm with
    {
        Kind = KitKind.Text,
        Name = KitName.Text,
        Cast = Enumerable.Range(0, SpriteKit.Form.CastSize).Select(i => new Character(KitNames[i].Text, KitPersonas[i].Text)).ToList(),
    };

    /// <summary>The form as the settings have it (after Refine, Clear or a relaunch), the labels in the current language,
    /// and Refine with AI on only with an OpenRouter key.</summary>
    private void RefreshSpriteKit()
    {
        var form = settings.SpriteKitForm;
        if (!FormFromFields().Equals(form))
        {
            fillingKit = true;
            KitKind.Text = form.Kind;
            KitName.Text = form.Name;
            for (var i = 0; i < SpriteKit.Form.CastSize; i++) { KitNames[i].Text = form.Cast[i].Name; KitPersonas[i].Text = form.Cast[i].Persona; }
            fillingKit = false;
        }
        KitOwnColour.IsChecked = form.Tint is not null;
        KitSwatch.IsEnabled = form.Tint is not null;
        var tint = form.Tint ?? SpriteText.Tint.FromHex("#6cbf4a")!.Value;
        KitSwatch.Background = new SolidColorBrush(Color.FromRgb(tint.R, tint.G, tint.B));
        KitCharacter1Label.Text = L10n.Tr("Character %d", 1);
        KitCharacter2Label.Text = L10n.Tr("Character %d", 2);
        KitCharacter3Label.Text = L10n.Tr("Character %d", 3);
        KitRefine.IsEnabled = settings.OpenRouterConnected && !refining;
        KitFormFooter.Text = L10n.Tr("Anything empty is the model's to choose. On import the name, colour and characters come from here; the picture gives only the looks.") + " " +
            (settings.OpenRouterConnected
                ? L10n.Tr("Refine with AI turns your words into a whole creature in Blocky's style, with three characters who say how they sound: one OpenRouter call with the Talk tab's model (Costs › Sprite kit: Refine with AI).")
                : L10n.Tr("Refine with AI needs an OpenRouter key (Settings › Talk), with OpenRouter as the brain or the voice."));
        if (PromptBox.Visibility == Visibility.Visible) PromptBox.Text = library.Prompt(form);
    }

    private void KitField_Changed(object sender, TextChangedEventArgs e)
    {
        if (fillingKit || !IsInitialized) return;
        settings.SpriteKitForm = FormFromFields();
    }

    private void KitOwnColour_Click(object sender, RoutedEventArgs e)
    {
        var form = settings.SpriteKitForm;
        settings.SpriteKitForm = form with { Colour = KitOwnColour.IsChecked == true ? form.Tint?.Hex ?? "#6cbf4a" : "" };
    }

    private void KitColour_Click(object sender, RoutedEventArgs e)
    {
        var now = settings.SpriteKitForm.Tint ?? SpriteText.Tint.FromHex("#6cbf4a")!.Value;
        if (ColourDialog.Ask(this, new RGB(now.R, now.G, now.B)) is RGB picked)
            settings.SpriteKitForm = settings.SpriteKitForm with { Colour = new SpriteText.Tint(picked.R, picked.G, picked.B).Hex };
    }

    private void KitClear_Click(object sender, RoutedEventArgs e)
    {
        settings.SpriteKitForm = new SpriteKit.Form();
        KitRefineNote.Text = "";
    }

    private bool refining;

    private async void KitRefine_Click(object sender, RoutedEventArgs e)
    {
        if (settings.RefineClient() is not ChatClient client)
        {
            KitRefineNote.Text = L10n.Tr("Refine with AI needs an OpenRouter key (Settings › Talk), with OpenRouter as the brain or the voice.");
            return;
        }
        refining = true;
        KitRefine.IsEnabled = false;
        KitRefineNote.Text = "…";
        try
        {
            settings.SpriteKitForm = await SpriteKitRefine.Refine(settings.SpriteKitForm, client, spend);
            KitRefineNote.Text = L10n.Tr("refined; edit anything you like");
        }
        catch (Exception ex) when (ex is ChatClient.Failure or System.Net.Http.HttpRequestException or TaskCanceledException)
        {
            KitRefineNote.Text = ex.Message;
        }
        finally
        {
            refining = false;
            RefreshSpriteKit();
        }
    }

    private async void CopyPrompt_Click(object sender, RoutedEventArgs e)
    {
        try { System.Windows.Clipboard.SetText(library.Prompt(settings.SpriteKitForm)); }
        catch (System.Runtime.InteropServices.COMException) { SpriteStatus.Text = L10n.Tr("the clipboard is busy; try again"); return; }
        CopyPrompt.Content = L10n.Tr("Copied");
        await Task.Delay(2000);
        CopyPrompt.Content = L10n.Tr("Copy Prompt");
    }

    private void ShowPrompt_Click(object sender, RoutedEventArgs e)
    {
        PromptBox.Visibility = ShowPrompt.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        PromptBox.Text = library.Prompt(settings.SpriteKitForm);
    }

    private void SaveImages_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = L10n.Tr("A folder for 1-poses.png and 2-template.png.") };
        if (dialog.ShowDialog(this) != true) return;
        try { library.SaveKitImages(dialog.FolderName); SpriteStatus.Text = L10n.Tr("saved %@", Path.GetFileName(dialog.FolderName)); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Runtime.InteropServices.ExternalException) { SpriteStatus.Text = ex.Message; }
    }

    /// <summary>The two pictures as files, the way Explorer copies them, so a chat in the browser takes both at one paste.</summary>
    private async void CopyImages_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var files = library.SaveKitImages(Path.Combine(Path.GetTempPath(), "ledgelings-sprite-kit"));
            var list = new System.Collections.Specialized.StringCollection();
            list.AddRange(files.ToArray());
            System.Windows.Clipboard.SetFileDropList(list);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Runtime.InteropServices.ExternalException)
        {
            SpriteStatus.Text = ex.Message;
            return;
        }
        CopyImages.Content = L10n.Tr("Copied");
        await Task.Delay(2000);
        CopyImages.Content = L10n.Tr("Copy Images");
    }

    private static BitmapSource Source(SpriteText.Image image)
    {
        var bgra = new byte[image.Rgba.Length];
        for (var i = 0; i < bgra.Length; i += 4)
        {
            bgra[i] = image.Rgba[i + 2]; bgra[i + 1] = image.Rgba[i + 1]; bgra[i + 2] = image.Rgba[i]; bgra[i + 3] = image.Rgba[i + 3];
        }
        var source = BitmapSource.Create(Math.Max(1, image.Width), Math.Max(1, image.Height), 96, 96, PixelFormats.Bgra32, null,
            image.Width == 0 ? new byte[4] : bgra, Math.Max(1, image.Width) * 4);
        source.Freeze();
        return source;
    }
}

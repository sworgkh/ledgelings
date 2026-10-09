using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Imaging;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Settings › Beds (SPEC §7.9): whether they sleep in beds and how they find their place; everyone's
/// bed and favourite place, with a way to forget one character's place or everyone's.</summary>
public sealed partial class SettingsWindow
{
    private sealed record BedRow(string Name, string Bed, string Where, BitmapSource? Picture, bool CanForget);

    private BedBook? bedBook;
    private SpriteAtlas.Frames? bedPictures;

    /// <summary>The colony's favourite places, for the list and the file. Set once, as the window is made.</summary>
    public BedBook? BedBook
    {
        get => bedBook;
        init
        {
            bedBook = value;
            if (value is null) return;
            value.Changed += () => Dispatcher.BeginInvoke(RefreshBeds);
            BedsPath.Text = value.File;
            settings.PropertyChanged += (_, e) =>
            {
                if (e.PropertyName is nameof(AppSettings.CreatureCount) or nameof(AppSettings.Language)) RefreshBeds();
            };
            IsVisibleChanged += (_, _) => { if (IsVisible) RefreshBeds(); };
            RefreshBeds();
        }
    }

    /// <summary>Everyone on screen, once each: its bed's picture and name, and where it likes to sleep.</summary>
    private void RefreshBeds()
    {
        if (bedBook is null) return;
        try { bedPictures ??= SpriteAtlas.Named("beds").MakeFrames(); } catch (Exception e) when (e is IOException or ArgumentException) { }
        var screens = Desktop.Monitors().Select(m => m.Frame).ToList();
        var rows = new List<BedRow>();
        for (int i = 0; i < settings.CreatureCount; i++)
        {
            var who = settings.CharacterFor(i, library);
            if (rows.Any(r => r.Name == who.Name)) continue;
            var kind = Beds.KindOf(who.Name, who.Persona, library.Kind(settings.SpeciesFor(i)));
            var spot = bedBook.SpotOf(who.Name);
            var where = spot is null ? L10n.Tr("no place yet")
                : Beds.Place(spot.Point, screens) + ", " + L10n.TrCount(spot.Nights, "night", "nights");
            var picture = bedPictures?.Frame(kind.Name(), 0) is { } image ? Bitmaps.ToSource(image) : null;
            rows.Add(new BedRow(who.Name, kind.Title(), where, picture, spot is not null));
        }
        BedList.ItemsSource = rows;
        ForgetAllBeds.IsEnabled = bedBook.Book.Spots.Count > 0;
    }

    private void ForgetBed_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string name }) bedBook?.Forget(name);
    }

    private void ForgetAllBeds_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show(this, L10n.Tr("Forget where everyone likes to sleep?"), L10n.Tr("Forget All Places"),
                            MessageBoxButton.OKCancel, MessageBoxImage.Warning) == MessageBoxResult.OK)
            bedBook?.Forget();
    }

    private void RevealBeds_Click(object sender, RoutedEventArgs e) => bedBook?.RevealInExplorer();
}

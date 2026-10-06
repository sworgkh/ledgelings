using System.Windows;
using System.Windows.Controls;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Settings › Chases (SPEC §4.7.2): whether the cursor's hunts are counted and how the creatures use
/// the count; the count itself, per character and in total, with a reset for each and for all.</summary>
public sealed partial class SettingsWindow
{
    private sealed record HuntRow(string Name, int Today, int Week, int All, FontWeight Weight, Visibility ResetVisibility, bool CanReset);

    private HuntBook? huntBook;

    /// <summary>The colony's count, for the list and the file. Set once, as the window is made.</summary>
    public HuntBook? HuntBook
    {
        get => huntBook;
        init
        {
            huntBook = value;
            if (value is null) return;
            value.Changed += () => Dispatcher.BeginInvoke(RefreshHunts);
            HuntsPath.Text = value.File;
            settings.PropertyChanged += (_, e) =>
            {
                if (e.PropertyName is nameof(AppSettings.CreatureCount) or nameof(AppSettings.Language)) RefreshHunts();
            };
            IsVisibleChanged += (_, _) => { if (IsVisible) RefreshHunts(); };       // today may have turned since
            RefreshHunts();
        }
    }

    /// <summary>Everyone on screen, then anyone else ever counted, most hunted first; the total last.</summary>
    private void RefreshHunts()
    {
        if (huntBook is null) return;
        var names = new List<string>();
        for (int i = 0; i < settings.CreatureCount; i++)
        {
            var name = settings.CharacterFor(i, library).Name;
            if (!names.Contains(name)) names.Add(name);
        }
        names.AddRange(huntBook.Book.Tallies.Where(kv => !names.Contains(kv.Key))
            .OrderByDescending(kv => kv.Value.All).ThenBy(kv => kv.Key, StringComparer.Ordinal).Select(kv => kv.Key));
        var rows = names.Select(name =>
        {
            var n = huntBook.NumbersOf(name);
            return new HuntRow(name, n.Today, n.Week, n.All, FontWeights.Normal, Visibility.Visible, huntBook.Book.Tallies.ContainsKey(name));
        }).ToList();
        var total = huntBook.Total;
        rows.Add(new HuntRow(L10n.Tr("Everyone"), total.Today, total.Week, total.All, FontWeights.Bold, Visibility.Hidden, false));
        HuntList.ItemsSource = rows;
        ResetAllHunts.IsEnabled = huntBook.Book.Tallies.Count > 0;
        HuntsSince.Text = huntBook.Book.Since is DateTimeOffset since
            ? L10n.Tr("Counting since %@. Kept by name: rename a character and it starts from zero.",
                      since.ToLocalTime().ToString("f", Languages.Current.Culture()))
            : L10n.Tr("Nothing counted yet. Chase someone with the cursor.");
    }

    private void ResetHunt_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string name }) huntBook?.Reset(name);
    }

    private void ResetAllHunts_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show(this, L10n.Tr("Reset every creature's count to zero?"), L10n.Tr("Reset All"),
                            MessageBoxButton.OKCancel, MessageBoxImage.Warning) == MessageBoxResult.OK)
            huntBook?.Reset();
    }

    private void RevealHunts_Click(object sender, RoutedEventArgs e) => huntBook?.RevealInExplorer();
}

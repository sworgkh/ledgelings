using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Settings › Bonds: when pairs get a story and how long it lasts, with the prompt
/// that writes it; every pair's bond and story below.</summary>
public sealed partial class SettingsWindow
{
    private sealed record BondRow(string Key, string Names, string Details, string Summary, Visibility SummaryVisibility,
                                  string Story, FontStyle StoryStyle, Brush StoryBrush, Visibility StoryVisibility);

    private BondBook? bondBook;

    /// <summary>The colony's bonds, for the list and the file. Set once, as the window is made.</summary>
    public BondBook? BondBook
    {
        get => bondBook;
        init
        {
            bondBook = value;
            if (value is null) return;
            value.Changed += () => Dispatcher.BeginInvoke(RefreshBondList);
            BondsPath.Text = value.File;
            RefreshBondList();
        }
    }

    private void InitBonds()
    {
        NeedsModelNote(BondsNeedsModel);
        PlotPromptFooter.Text = "Placeholders: " + string.Join(" ", Bonds.Placeholders.Select(p => "{" + p + "}"))
            + ". The answer needs a PLOT: line, and may have a BOND: line. {relationship} in the Talk prompt places the story; without it, it goes at the end.";
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.Brain) or nameof(AppSettings.PlotsEnabled)) RefreshBonds();
        };
        RefreshBonds();
        RefreshBondList();
    }

    /// <summary>Greyed out without a model; the prompt hidden like the Talk tab's.</summary>
    private void RefreshBonds()
    {
        var hasModel = settings.HasModel;
        var writes = settings.PlotsEnabled && hasModel;
        PlotsToggle.IsEnabled = hasModel;
        PlotAfterRow.IsEnabled = writes;
        PlotLengthRow.IsEnabled = writes;
        PlotPromptBox.Visibility = hasModel ? Visibility.Visible : Visibility.Collapsed;
        var footer = "Once two characters have shared the screen this long, the model writes them a small story and a line on how they get on. A few dozen words of it go into their prompts; when it has run its course, the next grows from the last. One short call per story (Costs › Relationship plots).";
        if (!hasModel) footer += " Time together is still counted meanwhile: once a model is chosen, a pair that has lived together long enough gets its first story at its next talk.";
        BondsFooter.Text = footer;
    }

    private void RefreshBondList()
    {
        var pairs = bondBook?.Book.Closest ?? new List<Bonds.Bond>();
        BondsEmpty.Visibility = pairs.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        ForgetAllBonds.IsEnabled = pairs.Count > 0;
        BondList.ItemsSource = pairs.Select(bond =>
        {
            string story = "";
            var italic = FontStyles.Normal;
            Brush brush = Brushes.Black;
            if (bond.Plot is Bonds.Plot plot)
            {
                story = $"Part {Math.Min(plot.Told + 1, plot.Length)} of {plot.Length}: {plot.Text}";
                italic = FontStyles.Italic;
            }
            else if (bond.LastPlot is string last)
            {
                story = "Last story: " + last;
                brush = Brushes.Gray;
            }
            return new BondRow(Bonds.Key(bond.Names[0], bond.Names[^1]), string.Join(" & ", bond.Names), Details(bond),
                bond.Summary ?? "", bond.Summary is null ? Visibility.Collapsed : Visibility.Visible,
                story, italic, brush, story.Length == 0 ? Visibility.Collapsed : Visibility.Visible);
        }).ToList();
    }

    private static string Details(Bonds.Bond bond)
    {
        var parts = new List<string> { "together " + Bonds.Duration(bond.Together), $"{bond.Talks} talk{(bond.Talks == 1 ? "" : "s")}" };
        if (bond.Plots > 0) parts.Add($"{bond.Plots} stor{(bond.Plots == 1 ? "y" : "ies")}");
        if (bond.Cost is double cost) parts.Add(Spend.Label(cost));
        return string.Join(" · ", parts);
    }

    private void ResetPlotPrompt_Click(object sender, RoutedEventArgs e) => settings.ResetPlotPrompt();

    private void ForgetBond_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string key }) bondBook?.Forget(key);
    }

    private void ForgetAllBonds_Click(object sender, RoutedEventArgs e) => bondBook?.ForgetAll();

    private void RevealBonds_Click(object sender, RoutedEventArgs e) => bondBook?.RevealInExplorer();
}

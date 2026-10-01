using System.Windows;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>The Flowers tab: wearing, planting, and who on screen plants where.</summary>
public sealed partial class SettingsWindow
{
    /// <summary>Pull up every planted flower; returns how many there were. Set by the app, which owns the colony.</summary>
    public Func<int> ClearGarden { get; set; } = () => 0;

    private sealed record PlanterRow(string Name, string Temper);

    private void InitFlowers()
    {
        // Anything that changes who is on screen, or how they are described.
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.CreatureCount) or nameof(AppSettings.Species) or "Casts") RefreshPlanters();
        };
        library.Changed += RefreshPlanters;
        RefreshPlanters();
    }

    /// <summary>Each creature on screen, with its temper written as a sentence.</summary>
    private void RefreshPlanters()
    {
        PlanterList.ItemsSource = Enumerable.Range(0, settings.CreatureCount).Select(i =>
        {
            var who = settings.CharacterFor(i, library);
            var kind = library.Kind(settings.SpeciesFor(i));
            return new PlanterRow(who.Name, Garden.Describe(Garden.TemperOf(who.Persona, kind)));
        }).ToList();
    }

    private void ClearGarden_Click(object sender, RoutedEventArgs e)
    {
        var n = ClearGarden();
        GardenCleared.Text = n == 0 ? L10n.Tr("Nothing was planted.") : L10n.TrCount(n, "flower pulled up.", "flowers pulled up.");
    }
}

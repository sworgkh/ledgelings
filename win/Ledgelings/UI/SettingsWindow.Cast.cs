using System.Windows;
using System.Windows.Controls;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Settings › Talk › Characters: one cast per species, edited in place.</summary>
public sealed partial class SettingsWindow
{
    private string CastSpeciesName => CastSpecies.SelectedItem as string ?? "blocky";

    private IReadOnlyList<Character> CurrentCast => settings.CastOf(CastSpeciesName, library.Cast(CastSpeciesName));

    private void RefreshCastSpecies()
    {
        if (CastSpecies is null) return;
        var selected = CastSpecies.SelectedItem as string;
        var names = library.AllSpecies.Select(s => s.Name).ToList();
        CastSpecies.ItemsSource = names;
        CastSpecies.SelectedItem = selected is not null && names.Contains(selected) ? selected : names.FirstOrDefault();
        RefreshCast();
    }

    private void CastSpecies_Changed(object sender, SelectionChangedEventArgs e) => RefreshCast();

    private void RefreshCast()
    {
        if (CastSpecies?.SelectedItem is null) return;
        CastKind.Text = library.Kind(CastSpeciesName);
        CastList.ItemsSource = CurrentCast.Select((c, i) => new CastRow(i, c.Name, c.Persona)).ToList();
    }

    private void SetCast(IEnumerable<Character> cast) => settings.SetCast(CastSpeciesName, cast);

    private void CastName_Changed(object sender, RoutedEventArgs e)
    {
        if (sender is not TextBox { Tag: int i } box || i >= CurrentCast.Count || CurrentCast[i].Name == box.Text) return;
        var cast = CurrentCast.ToList();
        cast[i] = cast[i] with { Name = box.Text };
        SetCast(cast);
    }

    private void CastPersona_Changed(object sender, RoutedEventArgs e)
    {
        if (sender is not TextBox { Tag: int i } box || i >= CurrentCast.Count || CurrentCast[i].Persona == box.Text) return;
        var cast = CurrentCast.ToList();
        cast[i] = cast[i] with { Persona = box.Text };
        SetCast(cast);
    }

    private void CastRemove_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: int i } || CurrentCast.Count <= 1 || i >= CurrentCast.Count) return;
        var cast = CurrentCast.ToList();
        cast.RemoveAt(i);
        SetCast(cast);
    }

    private void CastAdd_Click(object sender, RoutedEventArgs e) =>
        SetCast(CurrentCast.Append(new Character("Newcomer", "Describe the personality here.")));

    private void CastReset_Click(object sender, RoutedEventArgs e) => settings.ResetCast(CastSpeciesName);
}

using System.Windows;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Tools › Saved translations (SPEC §7.14.3): the star and the drawer beside the Translate sheet, how many
/// are kept, and Delete All. The Mac's <c>SavedTranslationsSettingsView.swift</c>, one column.</summary>
public sealed partial class SettingsWindow
{
    private SavedTranslations? savedTranslations;

    /// <summary>Hand the page the book it counts and clears. Called by the app, once per window.</summary>
    public void AttachSavedTranslations(SavedTranslations saved)
    {
        if (ReferenceEquals(savedTranslations, saved)) return;
        savedTranslations = saved;
        saved.Changed += () => Dispatcher.BeginInvoke(ShowSavedTranslations);
        settings.PropertyChanged += (_, e) => { if (e.PropertyName is nameof(AppSettings.Language)) ShowSavedTranslations(); };
        IsVisibleChanged += (_, _) => { if (IsVisible) ShowSavedTranslations(); };
        ShowSavedTranslations();
    }

    private void ShowSavedTranslations()
    {
        var count = savedTranslations?.Book.Count ?? 0;
        SavedCountText.Text = L10n.TrCount(count, "saved translation", "saved translations");
        DeleteSavedButton.IsEnabled = count > 0;
    }

    /// <summary>Asks first: they cannot be brought back.</summary>
    private void DeleteSaved_Click(object sender, RoutedEventArgs e)
    {
        if (savedTranslations is null) return;
        var sure = MessageBox.Show(this, L10n.Tr("They cannot be brought back."), L10n.Tr("Delete every saved translation?"), MessageBoxButton.OKCancel, MessageBoxImage.Warning);
        if (sure == MessageBoxResult.OK) savedTranslations.Clear();
    }
}

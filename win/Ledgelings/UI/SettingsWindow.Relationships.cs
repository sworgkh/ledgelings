using System.Windows;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Settings › Relationships, the Mac's <c>RelationshipsSettingsView</c>: deeds from talk on the left
/// (which deeds, how often, the built-in lines' share), long-term memory on the right (what a prompt
/// carries, the nightly diary, the seed from the chat log), and a button to the Relationships window,
/// where each pair's memory can be read. The values are bound in the XAML; this is the seed's buttons.</summary>
public sealed partial class SettingsWindow
{
    /// <summary>Reads the chat log into the memory (true: only says what it would send); returns a summary.</summary>
    public Func<bool, Task<string>> SeedMemory { get; set; } = _ => Task.FromResult("");
    /// <summary>Opens the Relationships window.</summary>
    public Action OpenRelationships { get; set; } = () => { };

    private void SeedCheck_Click(object sender, RoutedEventArgs e) => _ = Seed(dryRun: true);

    private void SeedRead_Click(object sender, RoutedEventArgs e) => _ = Seed(dryRun: false);

    private void OpenRelationships_Click(object sender, RoutedEventArgs e) => OpenRelationships();

    private async Task Seed(bool dryRun)
    {
        SeedCheck.IsEnabled = SeedRead.IsEnabled = false;
        SeedNews.Visibility = Visibility.Visible;
        SeedNews.Text = L10n.Tr("Reading…");
        try { SeedNews.Text = await SeedMemory(dryRun); }
        finally { SeedCheck.IsEnabled = SeedRead.IsEnabled = true; }
    }
}

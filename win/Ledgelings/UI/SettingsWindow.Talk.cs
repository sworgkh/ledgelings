using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Settings › Talk: the brain, its check, the model browser, spend, the cast and the prompts.</summary>
public sealed partial class SettingsWindow
{
    private sealed record ModelRow(string Id, string Name, string Price, Brush PriceBrush, Visibility NameVisibility);
    private sealed record SpendRow(string Model, string Detail);
    private sealed record CastRow(int Index, string Name, string Persona);

    private const int MostModels = 60;
    private ModelCatalog? catalog;
    private bool catalogLoaded;
    private bool syncingBrain;

    private void RefreshBrain()
    {
        syncingBrain = true;
        var lm = settings.BrainProvider == ChatClient.Provider.LmStudio;
        BrainLm.IsChecked = lm;
        BrainOr.IsChecked = !lm;
        LmPanel.Visibility = lm ? Visibility.Visible : Visibility.Collapsed;
        OrPanel.Visibility = lm ? Visibility.Collapsed : Visibility.Visible;
        if (OrKey.Password != settings.OpenRouterKey) OrKey.Password = settings.OpenRouterKey;
        BrainFooter.Text = lm
            ? "LM Studio's local server, started with `lms server start` or from its Developer tab. The model must be one it has installed; \"Check\" lists them."
            : "OpenRouter runs on the internet and charges per word. Make a key at openrouter.ai/keys, ideally with a spending limit; it is kept in the Windows Credential Manager. \"Check\" confirms the key and lists models.";
        syncingBrain = false;
        if (!lm && !catalogLoaded) _ = LoadCatalog();
    }

    private void Brain_Checked(object sender, RoutedEventArgs e)
    {
        if (syncingBrain) return;
        settings.BrainProvider = BrainOr.IsChecked == true ? ChatClient.Provider.OpenRouter : ChatClient.Provider.LmStudio;
    }

    private void OrKey_Changed(object sender, RoutedEventArgs e)
    {
        if (!syncingBrain) settings.OpenRouterKey = OrKey.Password;
    }

    private async void LmCheck_Click(object sender, RoutedEventArgs e)
    {
        if (settings.ChatClient() is not ChatClient client) { LmStatus.Text = settings.BrainProblem; return; }
        LmStatus.Text = "checking\u2026";
        try
        {
            var found = await client.ListModels();
            LmInstalled.ItemsSource = found;
            LmInstalled.Visibility = found.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
            LmStatus.Text = found.Contains(client.Model)
                ? $"ready: {client.Model} is installed"
                : $"server is up, but {client.Model} is not installed. Pick one under \"Installed\".";
        }
        catch (ChatClient.Failure ex) { LmInstalled.Visibility = Visibility.Collapsed; LmStatus.Text = ex.Message; }
    }

    private void LmInstalled_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (LmInstalled.SelectedItem is string id) settings.TalkModel = id;
    }

    private async void OrCheck_Click(object sender, RoutedEventArgs e)
    {
        if (settings.ChatClient() is not ChatClient client) { OrStatus.Text = settings.BrainProblem; return; }
        OrStatus.Text = "checking\u2026";
        try
        {
            var key = await client.DescribeKey();
            var models = await client.ListModels();
            OrStatus.Text = models.Contains(client.Model)
                ? $"ready: {key}; {client.Model} is available"
                : $"{key}, but there is no model {client.Model}. Search below and click one.";
        }
        catch (ChatClient.Failure ex) { OrStatus.Text = ex.Message; }
    }

    private async Task LoadCatalog()
    {
        catalogLoaded = true;
        CatalogStatus.Text = "loading models\u2026";
        try
        {
            catalog = await ChatClient.OpenRouterPublic.Catalog();
            CatalogStatus.Text = $"{catalog.Models.Count} models on OpenRouter, cheapest first. Prices are dollars per million tokens.";
            RefreshModelList();
        }
        catch (ChatClient.Failure ex) { CatalogStatus.Text = "could not load the list: " + ex.Message; catalogLoaded = false; }
    }

    private void ReloadCatalog_Click(object sender, RoutedEventArgs e) => _ = LoadCatalog();
    private void ModelSearch_Changed(object sender, TextChangedEventArgs e) => RefreshModelList();

    private void RefreshModelList()
    {
        if (catalog is null) return;
        var hits = catalog.Search(ModelSearch.Text);
        ModelList.ItemsSource = hits.Take(MostModels).Select(m => new ModelRow(m.Id, m.Name, m.PriceLabel,
            m.IsFree ? Brushes.Green : Brushes.Gray, m.Name == m.Id ? Visibility.Collapsed : Visibility.Visible)).ToList();
        if (hits.Count > MostModels) CatalogStatus.Text = $"{hits.Count - MostModels} more; add a word to narrow it down";
        ModelList.SelectedIndex = hits.Take(MostModels).ToList().FindIndex(m => m.Id == settings.OpenRouterModel);
    }

    private void ModelList_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (ModelList.SelectedItem is ModelRow row && row.Id != settings.OpenRouterModel) settings.OpenRouterModel = row.Id;
    }

    // MARK: Spend

    private void RefreshSpend()
    {
        var s = spend.Summary;
        void Row(Spend.Total t, TextBlock cost, TextBlock calls, TextBlock tokens)
        {
            cost.Text = Spend.Label(t.Cost) + (t.Unpriced > 0 ? "+" : "");
            calls.Text = t.Calls.ToString();
            tokens.Text = t.Tokens.ToString();
        }
        Row(s.Today, TodayCost, TodayCalls, TodayTokens);
        Row(s.Month, MonthCost, MonthCalls, MonthTokens);
        Row(s.AllTime, AllCost, AllCalls, AllTokens);
        SpendModels.ItemsSource = s.ByModel.Take(5).Select(m => new SpendRow(m.Model, $"{Spend.Label(m.Total.Cost)} · {m.Total.Calls} calls")).ToList();
        SpendPath.Text = spend.File;
        var footer = "Every call to the model is written to spend.jsonl with its tokens and, for OpenRouter, the price it reported. LM Studio is free. One conversation is two calls.";
        if (s.AllTime.Unpriced > 0) footer += $" {s.AllTime.Unpriced} calls had no price; a + marks a total that is missing some.";
        SpendFooter.Text = footer;
    }

    private void RevealSpend_Click(object sender, RoutedEventArgs e) => spend.RevealInExplorer();

    private void ResetPrompts_Click(object sender, RoutedEventArgs e) => settings.ResetPrompts();
}

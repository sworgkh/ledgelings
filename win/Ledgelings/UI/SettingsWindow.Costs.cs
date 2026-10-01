using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Settings › Costs: what every model call has cost, by period, by feature and by
/// model; then the latest calls one by one, and the file.</summary>
public sealed partial class SettingsWindow
{
    private sealed record TotalRow(string Name, string Detail);
    private sealed record CallRow(string Model, string Detail, string Cost, Brush CostBrush);

    private void RefreshSpend()
    {
        var s = spend.Summary;
        void Row(Spend.Total t, TextBlock cost, TextBlock calls, TextBlock tokens)
        {
            cost.Text = Spend.Label(t.Cost) + (t.Unpriced > 0 ? "+" : "");
            calls.Text = t.Calls.ToString(Languages.Current.Culture());
            tokens.Text = t.Tokens.ToString(Languages.Current.Culture());
        }
        Row(s.Today, TodayCost, TodayCalls, TodayTokens);
        Row(s.Month, MonthCost, MonthCalls, MonthTokens);
        Row(s.AllTime, AllCost, AllCalls, AllTokens);
        var footer = L10n.Tr("Every call to a model, text or voice, is priced as OpenRouter reports it; LM Studio, a local speech server and Windows' own voices are free.");
        if (s.AllTime.Unpriced > 0) footer += " " + L10n.Tr("%d calls had no price; a + marks a total that is missing some.", s.AllTime.Unpriced);
        SpendFooter.Text = footer;
        NoPurposes.Visibility = s.ByPurpose.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        SpendPurposes.ItemsSource = s.ByPurpose.Select(p => new TotalRow(p.Purpose, Total(p.Total))).ToList();
        SpendModels.ItemsSource = s.ByModel.Take(10).Select(m => new TotalRow(m.Model, Total(m.Total))).ToList();
        NoCalls.Visibility = spend.Recent.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        RecentCalls.ItemsSource = spend.Recent.Select(r => new CallRow(
            r.Model,
            r.Time.ToLocalTime().ToString("g", Languages.Current.Culture()) + " · " + Spend.PurposeTitle(r.Purpose) + " · " + L10n.TrCount(r.Usage.PromptTokens + r.Usage.CompletionTokens, "token", "tokens"),
            r.Usage.Cost is double c ? Spend.Label(c) : L10n.Tr("no price"),
            r.Usage.Cost is null ? Brushes.DarkOrange : Brushes.Black)).ToList();
        RecentFooter.Text = L10n.Tr("The last %d, newest first.", SpendLedger.RecentCount);
        SpendPath.Text = spend.File;
    }

    private static string Total(Spend.Total t) =>
        $"{Spend.Label(t.Cost)}{(t.Unpriced > 0 ? "+" : "")} · " + L10n.TrCount(t.Calls, "call", "calls");

    private void RevealSpend_Click(object sender, RoutedEventArgs e) => spend.RevealInExplorer();
}

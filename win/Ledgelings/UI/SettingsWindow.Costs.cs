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
            calls.Text = t.Calls.ToString(CultureInfo.CurrentCulture);
            tokens.Text = t.Tokens.ToString(CultureInfo.CurrentCulture);
        }
        Row(s.Today, TodayCost, TodayCalls, TodayTokens);
        Row(s.Month, MonthCost, MonthCalls, MonthTokens);
        Row(s.AllTime, AllCost, AllCalls, AllTokens);
        var footer = "Every call to a model, text or voice, is priced as OpenRouter reports it; LM Studio, a local speech server and Windows' own voices are free.";
        if (s.AllTime.Unpriced > 0) footer += $" {s.AllTime.Unpriced} calls had no price; a + marks a total that is missing some.";
        SpendFooter.Text = footer;
        NoPurposes.Visibility = s.ByPurpose.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        SpendPurposes.ItemsSource = s.ByPurpose.Select(p => new TotalRow(p.Purpose, Total(p.Total))).ToList();
        SpendModels.ItemsSource = s.ByModel.Take(10).Select(m => new TotalRow(m.Model, Total(m.Total))).ToList();
        NoCalls.Visibility = spend.Recent.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        RecentCalls.ItemsSource = spend.Recent.Select(r => new CallRow(
            r.Model,
            $"{r.Time.ToLocalTime().ToString("g", CultureInfo.CurrentCulture)} · {Spend.PurposeTitle(r.Purpose)} · {r.Usage.PromptTokens + r.Usage.CompletionTokens} tokens",
            r.Usage.Cost is double c ? Spend.Label(c) : "no price",
            r.Usage.Cost is null ? Brushes.DarkOrange : Brushes.Black)).ToList();
        RecentFooter.Text = $"The last {SpendLedger.RecentCount}, newest first.";
        SpendPath.Text = spend.File;
    }

    private static string Total(Spend.Total t) =>
        $"{Spend.Label(t.Cost)}{(t.Unpriced > 0 ? "+" : "")} · {t.Calls} call{(t.Calls == 1 ? "" : "s")}";

    private void RevealSpend_Click(object sender, RoutedEventArgs e) => spend.RevealInExplorer();
}

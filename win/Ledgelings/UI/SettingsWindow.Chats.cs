using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Settings › Chats: the days down the left, one day's conversations on the right.</summary>
public sealed partial class SettingsWindow
{
    private sealed record DayRow(string Day, string Title);
    private sealed record ExchangeRow(string Time, string Model, string Situation, string Cost, string Tokens, List<ChatLog.Line> Lines,
                                      string Voice = "", string? VoiceModels = null, string? Plot = null)
    {
        public Visibility PlotVisibility => Plot is null ? Visibility.Collapsed : Visibility.Visible;
    }

    private void InitChats()
    {
        ChatsPath.Text = history.Directory;
        ReloadChats();
    }

    private void ReloadChats()
    {
        var selected = (DayList.SelectedItem as DayRow)?.Day;
        var days = history.Days();
        DayList.ItemsSource = days.Select(d => new DayRow(d, Pretty(d))).ToList();
        var index = selected is null ? -1 : days.IndexOf(selected);
        DayList.SelectedIndex = index >= 0 ? index : days.Count > 0 ? 0 : -1;
        ShowDay();
    }

    private void DayList_Changed(object sender, SelectionChangedEventArgs e) => ShowDay();

    private void ShowDay()
    {
        var day = (DayList.SelectedItem as DayRow)?.Day;
        var exchanges = day is null ? new List<ChatLog.Exchange>() : history.Exchanges(day);
        var voices = day is null ? new Dictionary<int, ChatLog.VoiceTotal>() : history.VoiceTotals(day, exchanges);
        ExchangeList.ItemsSource = exchanges.Select((x, i) => new ExchangeRow(
            x.Time.ToLocalTime().ToString("t", CultureInfo.CurrentCulture), x.Model, x.Situation,
            x.Cost is double cost ? Spend.Label(cost) : "", x.Tokens is int tokens ? tokens + " tok" : "", x.Lines,
            voices.TryGetValue(i, out var v) ? VoiceLabel(v) : "", voices.TryGetValue(i, out var w) && w.Models.Count > 0 ? string.Join(", ", w.Models) : null,
            x.Plot is string p ? "Plot: " + p : null)).ToList();
        if (DayList.Items.Count == 0) ChatsEmpty.Text = "No chats yet. They talk when they meet on an edge, or pick \"Make Someone Talk\" in the menu.";
        else if (exchanges.Count == 0) ChatsEmpty.Text = "Nothing on this day.";
        ChatsEmpty.Visibility = exchanges.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    /// <summary>"voice $0.005 (2 lines)", "+" when a price is missing, and lines replayed free.</summary>
    public static string VoiceLabel(ChatLog.VoiceTotal v)
    {
        var parts = new List<string>();
        if (v.Lines > 0) parts.Add($"voice {Spend.Label(v.Cost)}{(v.Unpriced > 0 ? "+" : "")} ({v.Lines} line{(v.Lines == 1 ? "" : "s")})");
        if (v.Kept > 0) parts.Add($"{v.Kept} replayed free");
        return string.Join(" · ", parts);
    }

    private void OpenChats_Click(object sender, RoutedEventArgs e) => history.RevealInExplorer();
    private void OpenTerminal_Click(object sender, RoutedEventArgs e) => history.OpenInTerminal();

    /// <summary>"2026-09-18" as the user would say it, with today and yesterday named.</summary>
    public static string Pretty(string day)
    {
        var today = ChatLog.Day(DateTimeOffset.Now);
        var yesterday = ChatLog.Day(DateTimeOffset.Now.AddDays(-1));
        if (day == today) return "Today";
        if (day == yesterday) return "Yesterday";
        return DateTime.TryParseExact(day, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var date)
            ? date.ToString("ddd d MMM", CultureInfo.CurrentCulture) : day;
    }
}

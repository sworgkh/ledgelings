using System.Windows;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Settings › Plot twists, the Mac's <c>TwistsSettingsView</c>: the settings are bound in the XAML;
/// this is the news still fresh, the gang as the roster knows it, and Forget the News.</summary>
public sealed partial class SettingsWindow
{
    private void RefreshGang()
    {
        if (bondBook is null) return;
        var gang = bondBook.Book.Gang;
        var now = DateTimeOffset.Now;
        var fresh = gang.Fresh(settings.TwistDays, now, settings.TwistDepartures);
        GangNews.Text = fresh.Count == 0 ? L10n.Tr("No news: the gang is as it was.") : string.Join("\n", fresh.Select(e => Describe(e, now)));
        ForgetNews.IsEnabled = gang.Events.Count > 0;
        var members = gang.Members.Values.Where(m => !m.Pending).OrderBy(m => m.Name, StringComparer.Ordinal).ToList();
        if (members.Count == 0) { GangMembers.Text = L10n.Tr("Nobody yet: the gang is counted half a minute after launch."); return; }
        var here = string.Join(", ", members.Where(m => m.Away is null).Select(m => m.Name));
        var away = string.Join(", ", members.Where(m => m.Away is not null).Select(m => m.Name));
        GangMembers.Text = L10n.Tr("On screen") + ": " + here + (away.Length > 0 ? "\n" + L10n.Tr("Gone") + ": " + away : "");
    }

    /// <summary>"Pip joined the gang today", in the current language.</summary>
    internal static string Describe(Gang.Event e, DateTimeOffset now)
    {
        var when = Bonds.Ago(e.Time, now);
        return e.Kind switch
        {
            Gang.EventKind.Joined => L10n.Tr("%@ joined the gang %@", e.Name, when),
            Gang.EventKind.Left => L10n.Tr("%@ left the gang %@", e.Name, when),
            _ => L10n.Tr("%@ came back %@", e.Name, when),
        };
    }

    private void ForgetNews_Click(object sender, RoutedEventArgs e) => bondBook?.Change(book => book.Gang.ForgetNews());
}

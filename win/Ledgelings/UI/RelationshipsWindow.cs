using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>
/// Relationships… (SPEC §6.5.2.3), the Mac's <c>RelationshipsWindow.swift</c>: every pair on the left, closest
/// first, with how close they have grown day by day; the chosen pair on the right: how they get on, what
/// they remember, their games, and their timeline, a line a day. At the bottom, exactly what each of them
/// carries into a conversation. This is where the owner watches relationships emerge.
/// </summary>
public sealed class RelationshipsWindow : Window
{
    private static RelationshipsWindow? open;

    private readonly AppSettings settings;
    private readonly BondBook bonds;
    private readonly ListBox list = new() { BorderThickness = new Thickness(0), HorizontalContentAlignment = HorizontalAlignment.Stretch };
    private readonly StackPanel detail = new() { Margin = new Thickness(16, 12, 16, 16) };
    private string? selected;
    private bool showing;

    public static void ShowWindow(AppSettings settings, BondBook bonds)
    {
        open ??= new RelationshipsWindow(settings, bonds);
        open.Show();
        if (open.WindowState == WindowState.Minimized) open.WindowState = WindowState.Normal;
        open.Activate();
    }

    private RelationshipsWindow(AppSettings settings, BondBook bonds)
    {
        this.settings = settings;
        this.bonds = bonds;
        Title = L10n.Tr("Relationships");
        Width = 980; Height = 640; MinWidth = 760; MinHeight = 460;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        bonds.Changed += Changed;
        settings.PropertyChanged += SettingChanged;
        Closed += (_, _) => { bonds.Changed -= Changed; settings.PropertyChanged -= SettingChanged; open = null; };

        list.SelectionChanged += (_, _) =>
        {
            if (showing || list.SelectedItem is not ListBoxItem { Tag: string key }) return;
            selected = key;
            ShowDetail();
        };
        var body = new Grid();
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(280) });
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1) });
        body.ColumnDefinitions.Add(new ColumnDefinition());
        Grid.SetColumn(list, 0);
        var line = new Border { Background = SystemColors.ControlLightBrush };
        Grid.SetColumn(line, 1);
        var right = new ScrollViewer { Content = detail, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        Grid.SetColumn(right, 2);
        body.Children.Add(list);
        body.Children.Add(line);
        body.Children.Add(right);
        Content = body;
        ShowList();
        ShowDetail();
    }

    private void Changed() => Dispatcher.BeginInvoke(() => { ShowList(); ShowDetail(); });

    private void SettingChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(AppSettings.Language))
        {
            Title = L10n.Tr("Relationships");
            ShowList();
        }
        if (e.PropertyName is nameof(AppSettings.Language) or nameof(AppSettings.MemoryEnabled) or nameof(AppSettings.MemoryTokens)) ShowDetail();
    }

    private List<Bonds.Bond> Pairs => bonds.Book.Closest;

    private static string KeyOf(Bonds.Bond bond) => string.Join(" & ", bond.Names);

    // MARK: The list

    private void ShowList()
    {
        showing = true;
        list.Items.Clear();
        foreach (var bond in Pairs)
        {
            var tally = Bonds.Tallied(bond.Tally);
            var row = new StackPanel { Margin = new Thickness(4, 3, 4, 3) };
            row.Children.Add(new TextBlock { Text = KeyOf(bond), FontWeight = FontWeights.Bold });
            row.Children.Add(new TextBlock
            {
                Text = tally.Length == 0 ? L10n.Tr("only just met") : tally, FontSize = 11, Foreground = Brushes.Gray,
                TextTrimming = TextTrimming.CharacterEllipsis,
            });
            row.Children.Add(Growth(bond.Days));
            var item = new ListBoxItem { Content = row, Tag = KeyOf(bond) };
            list.Items.Add(item);
            if (KeyOf(bond) == (selected ?? Pairs.Select(KeyOf).FirstOrDefault())) item.IsSelected = true;
        }
        showing = false;
    }

    /// <summary>How much a pair shared each day, oldest left: one square bar a day, in the
    /// game's style (square pixels, flat fill).</summary>
    private static FrameworkElement Growth(IReadOnlyList<Bonds.DayEntry> days)
    {
        const double height = 14;
        var shown = days.TakeLast(30).ToList();
        var most = Math.Max(1, shown.Select(d => d.Counts.Values.Sum()).DefaultIfEmpty(1).Max());
        var bars = new StackPanel { Orientation = Orientation.Horizontal, Height = height, Margin = new Thickness(0, 3, 0, 0) };
        var fill = new SolidColorBrush(SystemColors.HighlightColor) { Opacity = 0.75 };
        foreach (var day in shown)
        {
            var n = day.Counts.Values.Sum();
            bars.Children.Add(new Rectangle
            {
                Width = 5, Height = Math.Max(2, height * n / most), Fill = fill, Margin = new Thickness(0, 0, 1, 0),
                VerticalAlignment = VerticalAlignment.Bottom, SnapsToDevicePixels = true,
            });
        }
        return bars;
    }

    // MARK: The pair

    private void ShowDetail()
    {
        detail.Children.Clear();
        var pairs = Pairs;
        var key = selected ?? pairs.Select(KeyOf).FirstOrDefault();
        if (pairs.FirstOrDefault(b => KeyOf(b) == key) is not Bonds.Bond bond)
        {
            detail.Children.Add(new TextBlock { Text = L10n.Tr("Nobody has shared the screen yet."), Foreground = Brushes.Gray, Margin = new Thickness(0, 40, 0, 0), HorizontalAlignment = HorizontalAlignment.Center });
            return;
        }
        TextBlock Text(string text, double size = 13, FontWeight? weight = null, Brush? brush = null, FontStyle? style = null) => new()
        {
            Text = text, FontSize = size, FontWeight = weight ?? FontWeights.Normal, Foreground = brush ?? Brushes.Black,
            FontStyle = style ?? FontStyles.Normal, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 4),
        };
        void Heading(string text)
        {
            var h = Text(text, 14, FontWeights.SemiBold);
            h.Margin = new Thickness(0, 12, 0, 4);
            detail.Children.Add(h);
        }
        detail.Children.Add(Text(KeyOf(bond), 20, FontWeights.Bold));
        if (bond.Met is DateTimeOffset met)
            detail.Children.Add(Text(L10n.Tr("Met on %@ · %@ together on screen", Bonds.Day(met), Bonds.Duration(bond.Together)), brush: Brushes.Gray));
        if (bond.Summary is string summary) detail.Children.Add(Text(summary, style: FontStyles.Italic));
        Heading(L10n.Tr("Their story so far"));
        detail.Children.Add(Text(bond.Chronicle ?? L10n.Tr("nothing yet; they have only just met")));
        Heading(L10n.Tr("What they remember"));
        if (bond.Facts.Count == 0) detail.Children.Add(Text(L10n.Tr("(nothing yet)"), brush: Brushes.Gray));
        foreach (var fact in Enumerable.Reverse(bond.Facts))
        {
            var t = Text("· " + fact.Text + "  ");
            t.Inlines.Add(new System.Windows.Documents.Run(Bonds.Day(fact.Time)) { FontSize = 11, Foreground = Brushes.Gray });
            detail.Children.Add(t);
        }
        Heading(L10n.Tr("Their games"));
        detail.Children.Add(Text(Bonds.RecordLine(bond) ?? L10n.Tr("(nothing yet)")));
        Heading(L10n.Tr("Day by day"));
        if (bond.Days.Count == 0) detail.Children.Add(Text(L10n.Tr("(nothing yet)"), brush: Brushes.Gray));
        foreach (var day in Enumerable.Reverse(bond.Days))
        {
            var row = new DockPanel { Margin = new Thickness(0, 0, 0, 4) };
            var date = Text(Bonds.DateOfDay(day.Day) is DateTimeOffset d ? Bonds.Day(d) : day.Day);
            date.Width = 64;
            DockPanel.SetDock(date, Dock.Left);
            row.Children.Add(date);
            var words = new StackPanel();
            if (day.Line is string said) words.Children.Add(Text(said));
            words.Children.Add(Text(Bonds.DayLine(day), 11, brush: Brushes.Gray));
            row.Children.Add(words);
            detail.Children.Add(row);
        }
        Heading(L10n.Tr("What they carry into a conversation"));
        foreach (var (a, b) in new[] { (bond.Names[0], bond.Names[^1]), (bond.Names[^1], bond.Names[0]) })
        {
            var block = Bonds.Memory(bond, a, b, settings.MemoryEnabled ? settings.MemoryTokens : 0);
            detail.Children.Add(Text(L10n.Tr("%@ (%@):", a, L10n.TrCount(Bonds.Tokens(block), "token", "tokens")), weight: FontWeights.Bold));
            var carried = new TextBox
            {
                Text = block.Length == 0 ? L10n.Tr("(nothing)") : block, IsReadOnly = true, BorderThickness = new Thickness(0), Background = Brushes.Transparent,
                TextWrapping = TextWrapping.Wrap, FontSize = 11, Foreground = Brushes.Gray, Margin = new Thickness(0, 0, 0, 6),
            };
            detail.Children.Add(carried);
        }
        if (bond.MemoryCost is double cost) detail.Children.Add(Text(L10n.Tr("Their memory has cost %@ so far.", Spend.Label(cost)), 11, brush: Brushes.DarkGray));
    }
}

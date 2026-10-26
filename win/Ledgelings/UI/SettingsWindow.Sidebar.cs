using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>
/// The settings window's left side, the Mac's <c>SettingsSidebar</c>: a search box, then every page under its
/// group's heading with the group's pixel picture; while the box holds words, the places they were found
/// instead. Ctrl+F puts the cursor in the box; Enter opens the first place; Esc clears it.
///
/// The search reads the pages themselves: every group box with its <c>Tr.Header</c>, the <c>Tr</c> words of its
/// controls and its footers, in English as the markup writes them (<see cref="SettingsSearch"/> looks each up in
/// the current language too). A new setting is found without being listed anywhere.
/// </summary>
public sealed partial class SettingsWindow
{
    private SettingsPage page = SettingsPage.Creatures;
    private IReadOnlyList<SettingsSearch.Section>? sections;
    private GroupBox? flashed;
    private static readonly Color sidebarInk = Color.FromRgb(92, 86, 120);

    private void InitSidebar()
    {
        SearchIcon.Source = PixelGlyph.Source(SettingsPages.SearchIcon, sidebarInk);
        ClearIcon.Source = PixelGlyph.Source(SettingsPages.ClearIcon, sidebarInk);
        InitSidebarTips();
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.F && Keyboard.Modifiers == ModifierKeys.Control) { SearchBox.Focus(); SearchBox.SelectAll(); e.Handled = true; }
        };
        ShowPage(page);
    }

    /// <summary>The TabItem a page is: found by its header, the page's English title.</summary>
    private TabItem? Item(SettingsPage p) => Tabs.Items.OfType<TabItem>().FirstOrDefault(i => Tr.GetHeader(i) == p.EnglishTitle());

    /// <summary>Bring the window up on <paramref name="p"/>, or where it was.</summary>
    public void Show(SettingsPage? p)
    {
        if (p is SettingsPage chosen) ShowPage(chosen);
        Bring();
    }

    private void ShowPage(SettingsPage p)
    {
        page = p;
        if (Item(p) is TabItem item && !ReferenceEquals(Tabs.SelectedItem, item)) Tabs.SelectedItem = item;
        PageTitle.Text = p.Title();
        PageGroup.Text = p.Group().Title().ToUpper(Languages.Current.Culture());
        if (p == SettingsPage.Translate) LoadTranslateModelsOnce();
        DrawSidebar();
    }

    private void Tabs_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!ReferenceEquals(e.OriginalSource, Tabs) || Tabs.SelectedItem is not TabItem item) return;      // a ComboBox inside a page bubbles this too
        foreach (var p in SettingsPages.All)
            if (p != page && Tr.GetHeader(item) == p.EnglishTitle()) { ShowPage(p); return; }
    }

    // MARK: The list

    private void DrawSidebar()
    {
        Sidebar.Children.Clear();
        var query = SearchBox.Text.Trim();
        SearchHint.Visibility = SearchBox.Text.Length == 0 ? Visibility.Visible : Visibility.Hidden;
        ClearSearch.Visibility = SearchBox.Text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        if (query.Length == 0) DrawPages(); else DrawHits(Found(query));
    }

    private void DrawPages()
    {
        foreach (var group in SettingsPages.Groups)
        {
            Sidebar.Children.Add(Heading(group.Title(), first: group == SettingsPages.Groups[0]));
            foreach (var p in group.Pages())
            {
                var line = new StackPanel { Orientation = Orientation.Horizontal };
                var chosen = p == page;
                line.Children.Add(PixelGlyph.Image(group.Icon(), chosen ? Colors.White : sidebarInk));
                line.Children.Add(new TextBlock { Text = p.Title(), Margin = new Thickness(8, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center });
                Sidebar.Children.Add(Row(line, chosen, () => { ShowPage(p); }));
            }
        }
    }

    private void DrawHits(IReadOnlyList<SettingsSearch.Hit> hits)
    {
        Sidebar.Children.Add(Heading(hits.Count == 0 ? L10n.Tr("Nothing found.") : L10n.TrCount(hits.Count, "place", "places"), first: true));
        foreach (var hit in hits)
        {
            var chosen = hit.Page == page && flashed is not null && Tr.GetHeader(flashed) == hit.Section && hit.Section.Length > 0;
            var where = hit.Section.Length == 0 ? hit.Page.Title() : $"{hit.Page.Title()} › {L10n.Tr(hit.Section)}";
            var words = new StackPanel
            {
                Children =
                {
                    new TextBlock { Text = hit.Text, TextWrapping = TextWrapping.Wrap, MaxHeight = 34 },
                    new TextBlock { Text = where, FontSize = 11, Foreground = chosen ? new SolidColorBrush(Color.FromArgb(204, 255, 255, 255)) : Brushes.Gray, TextTrimming = TextTrimming.CharacterEllipsis },
                },
            };
            Sidebar.Children.Add(Row(words, chosen, () => Open(hit)));
        }
    }

    private static TextBlock Heading(string text, bool first) => new()
    {
        Text = text.ToUpper(Languages.Current.Culture()),
        FontSize = 10, FontWeight = FontWeights.Bold, Foreground = Brushes.Gray,
        Margin = new Thickness(8, first ? 2 : 12, 0, 2),
    };

    /// <summary>A row of the list: the whole width answers a click, the chosen one filled.</summary>
    private static Border Row(UIElement content, bool chosen, Action click)
    {
        var row = new Border
        {
            Child = content,
            Padding = new Thickness(8, 4, 8, 4),
            CornerRadius = new CornerRadius(5),
            Background = chosen ? SystemColors.HighlightBrush : Brushes.Transparent,
            Cursor = Cursors.Hand,
        };
        if (chosen) System.Windows.Documents.TextElement.SetForeground(row, Brushes.White);
        row.MouseLeftButtonUp += (_, e) => { e.Handled = true; click(); };
        return row;
    }

    // MARK: The search

    private IReadOnlyList<SettingsSearch.Hit> Found(string query) => SettingsSearch.Search(query, sections ??= Index());

    /// <summary>Every group box of every page: its heading, the words of its controls, its footers.</summary>
    private IReadOnlyList<SettingsSearch.Section> Index()
    {
        var found = new List<SettingsSearch.Section>();
        foreach (var p in SettingsPages.All)
        {
            if (Item(p) is not TabItem item) continue;
            var boxes = Descendants(item.Content as DependencyObject).OfType<GroupBox>().ToList();
            foreach (var box in boxes)
            {
                if (Tr.GetHeader(box) is not string title) continue;
                var (labels, footer) = Words(box);
                found.Add(new SettingsSearch.Section(p, title, labels, footer));
            }
            // A page's own switches outside any box (Translator, Dictation): a section with no heading.
            var inBoxes = boxes.SelectMany(Descendants).ToHashSet();
            var loose = Descendants(item.Content as DependencyObject)
                .Where(d => d is CheckBox && !inBoxes.Contains(d)).Select(Tr.GetContent).OfType<string>().ToList();
            if (loose.Count > 0) found.Add(new SettingsSearch.Section(p, "", loose));
        }
        return found;
    }

    /// <summary>A box's control words, and its footers joined, in English.</summary>
    private (List<string> Labels, string Footer) Words(GroupBox box)
    {
        var labels = new List<string>();
        var footers = new List<string>();
        foreach (var d in Descendants(box))
        {
            if (d is GroupBox inner && !ReferenceEquals(inner, box)) continue;
            var text = Tr.GetText(d) ?? Tr.GetContent(d);
            if (text is null) continue;
            if (d is TextBlock { Style: Style s } && ReferenceEquals(s, TryFindResource("Footer"))) footers.Add(text);
            else labels.Add(text);
        }
        return (labels, string.Join(" ", footers));
    }

    private static IEnumerable<DependencyObject> Descendants(DependencyObject? root)
    {
        if (root is null) yield break;
        yield return root;
        foreach (var child in LogicalTreeHelper.GetChildren(root).OfType<DependencyObject>())
            foreach (var d in Descendants(child)) yield return d;
    }

    /// <summary>A place found: its page, scrolled to its box, which flashes.</summary>
    private void Open(SettingsSearch.Hit hit)
    {
        ShowPage(hit.Page);
        if (hit.Section.Length == 0 || Item(hit.Page)?.Content is not DependencyObject content) return;
        if (Descendants(content).OfType<GroupBox>().FirstOrDefault(b => Tr.GetHeader(b) == hit.Section) is not GroupBox box) return;
        Dispatcher.BeginInvoke(DispatcherPriority.Loaded, () =>
        {
            box.BringIntoView();
            Flash(box);
            DrawSidebar();
        });
    }

    private void Flash(GroupBox box)
    {
        flashed = box;
        var glow = new SolidColorBrush(Color.FromArgb(0, 255, 138, 61));
        box.Background = glow;
        var pulse = new ColorAnimation(Color.FromArgb(90, 255, 138, 61), TimeSpan.FromSeconds(0.35)) { AutoReverse = true, RepeatBehavior = new RepeatBehavior(2) };
        pulse.Completed += (_, _) => { if (ReferenceEquals(box.Background, glow)) box.ClearValue(BackgroundProperty); };
        glow.BeginAnimation(SolidColorBrush.ColorProperty, pulse);
    }

    private void SearchBox_Changed(object sender, TextChangedEventArgs e)
    {
        flashed = null;
        DrawSidebar();
    }

    private void SearchBox_Key(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape && SearchBox.Text.Length > 0) { SearchBox.Text = ""; e.Handled = true; }
        else if (e.Key == Key.Enter && SearchBox.Text.Trim().Length > 0 && Found(SearchBox.Text.Trim()) is [var first, ..]) { Open(first); e.Handled = true; }
    }

    private void ClearSearch_Click(object sender, RoutedEventArgs e)
    {
        SearchBox.Text = "";
        SearchBox.Focus();
    }

    /// <summary>A new language: the list again, and the search reads the pages afresh.</summary>
    private void RefreshSidebar()
    {
        sections = null;
        InitSidebarTips();
        ShowPage(page);
    }

    private void InitSidebarTips()
    {
        ClearSearch.ToolTip = L10n.Tr("Clear the search (Esc)");
        SearchBox.ToolTip = L10n.Tr("Search every setting (Ctrl+F); Enter opens the first place");
    }
}

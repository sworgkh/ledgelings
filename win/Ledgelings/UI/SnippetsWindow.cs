using System.IO;
using System.Media;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Ledgelings.Core;
using Microsoft.Win32;
using Clipboard = Ledgelings.Core.Clipboard;

namespace Ledgelings.UI;

/// <summary>
/// Edit Snippets (SPEC §7.11), the Mac's <c>SnippetsWindow.swift</c>: folders and their snippets on the left,
/// the chosen one on the right. + Folder, + Snippet, delete, move up and down; Clipy's XML in and out. A snippet
/// has a title, its words, a protected switch (its words then live in Credential Manager, shown as dots until
/// Show…) and its own shortcut from any app.
/// </summary>
public sealed class SnippetsWindow : Window
{
    private static SnippetsWindow? open;

    private readonly ClipBook book;
    private readonly AppSettings settings;
    private readonly TreeView tree = new() { MinWidth = 220 };
    private readonly StackPanel editor = new() { Margin = new Thickness(12) };
    private readonly TextBlock status = new() { Foreground = System.Windows.Media.Brushes.Gray, Margin = new Thickness(0, 6, 0, 0), TextWrapping = TextWrapping.Wrap };
    private Guid? chosen;
    private bool recording;
    private bool showing;

    public static void ShowEditor(ClipBook book, AppSettings settings)
    {
        open ??= new SnippetsWindow(book, settings);
        open.Show();
        if (open.WindowState == WindowState.Minimized) open.WindowState = WindowState.Normal;
        open.Activate();
    }

    private SnippetsWindow(ClipBook book, AppSettings settings)
    {
        this.book = book;
        this.settings = settings;
        Title = L10n.Tr("Snippets");
        Width = 760; Height = 520; MinWidth = 600; MinHeight = 380;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Closed += (_, _) => { StopRecording(); book.Changed -= Changed; open = null; };
        Deactivated += (_, _) => StopRecording();
        PreviewKeyDown += RecordKey;
        book.Changed += Changed;

        Button Tool(string text, string? tip, RoutedEventHandler click)
        {
            var b = new Button { Content = text, Margin = new Thickness(0, 0, 6, 0), Padding = new Thickness(8, 2, 8, 2) };
            if (tip is not null) b.ToolTip = tip;
            b.Click += click;
            return b;
        }
        var bar = new WrapPanel { Margin = new Thickness(12, 10, 12, 6) };
        bar.Children.Add(Tool(L10n.Tr("+ Folder"), null, (_, _) => Choose(book.AddFolder(L10n.Tr("New folder")))));
        bar.Children.Add(Tool(L10n.Tr("+ Snippet"), null, (_, _) => AddSnippet()));
        bar.Children.Add(Tool("−", L10n.Tr("Delete the folder or snippet; a folder goes with everything in it"), (_, _) => Delete()));
        bar.Children.Add(Tool("↑", null, (_, _) => { if (chosen is Guid id) book.Move(id, -1); }));
        bar.Children.Add(Tool("↓", null, (_, _) => { if (chosen is Guid id) book.Move(id, 1); }));
        bar.Children.Add(Tool(L10n.Tr("Import Clipy Snippets…"), null, (_, _) => Import()));
        bar.Children.Add(Tool(L10n.Tr("Export as Clipy XML…"), L10n.Tr("Protected snippets are exported with their titles only."), (_, _) => Export()));

        tree.SelectedItemChanged += (_, e) =>
        {
            if (showing) return;
            StopRecording();
            chosen = (e.NewValue as TreeViewItem)?.Tag as Guid?;
            ShowEditor();
        };
        var left = new DockPanel { Margin = new Thickness(12, 0, 0, 12) };
        DockPanel.SetDock(status, Dock.Bottom);
        left.Children.Add(status);
        left.Children.Add(tree);
        var body = new Grid();
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(260) });
        body.ColumnDefinitions.Add(new ColumnDefinition());
        Grid.SetColumn(left, 0);
        var right = new ScrollViewer { Content = editor, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        Grid.SetColumn(right, 1);
        body.Children.Add(left);
        body.Children.Add(right);
        var all = new DockPanel();
        DockPanel.SetDock(bar, Dock.Top);
        all.Children.Add(bar);
        all.Children.Add(body);
        Content = all;
        ShowTree();
        ShowEditor();
    }

    private void Changed() => Dispatcher.BeginInvoke(() => { ShowTree(); if (!editor.IsKeyboardFocusWithin) ShowEditor(); });

    private void Choose(Guid id)
    {
        chosen = id;
        ShowTree();
        ShowEditor();
    }

    private void AddSnippet()
    {
        // Into the chosen folder, or the chosen snippet's folder, or the first.
        Guid? folder = chosen is Guid id ? book.Snippets.Folders.FirstOrDefault(f => f.Id == id)?.Id ?? book.Snippets.FolderOf(id)?.Id : null;
        Choose(book.AddSnippet(L10n.Tr("New snippet"), "", false, folder));
    }

    private void Delete()
    {
        if (chosen is not Guid id) return;
        book.RemoveSnippetOrFolder(id);
        chosen = null;
        ShowTree();
        ShowEditor();
    }

    private void Import()
    {
        var dialog = new OpenFileDialog { Filter = "Clipy XML (*.xml)|*.xml", Title = L10n.Tr("Choose the XML file Clipy's Snippets editor exported.") };
        if (dialog.ShowDialog(this) != true) return;
        try { status.Text = L10n.Tr("%d snippets imported.", book.ImportClipy(dialog.FileName)); }
        catch (Clipboard.NotClipyXmlException) { status.Text = L10n.Tr("That file is not Clipy's snippets XML."); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { status.Text = e.Message; }
    }

    private void Export()
    {
        var dialog = new SaveFileDialog { Filter = "Clipy XML (*.xml)|*.xml", FileName = "snippets.xml" };
        if (dialog.ShowDialog(this) != true) return;
        try { book.ExportClipy(dialog.FileName); status.Text = L10n.Tr("Exported."); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { status.Text = e.Message; }
    }

    // MARK: The list

    private void ShowTree()
    {
        showing = true;
        tree.Items.Clear();
        foreach (var folder in book.Snippets.Folders)
        {
            var item = new TreeViewItem { Header = folder.Title.Length > 0 ? folder.Title : L10n.Tr("Untitled folder"), Tag = folder.Id, IsExpanded = true, FontWeight = FontWeights.SemiBold };
            foreach (var s in folder.Snippets)
            {
                var title = s.Title.Length > 0 ? s.Title : L10n.Tr("Untitled snippet");
                var keys = s.Shortcut is { } k ? "   " + ShortcutKeys.Label(k) : "";
                var child = new TreeViewItem { Header = (s.Protected ? "\U0001F512 " : "") + title + keys, Tag = s.Id, FontWeight = FontWeights.Normal };
                child.IsSelected = s.Id == chosen;
                item.Items.Add(child);
            }
            item.IsSelected = folder.Id == chosen;
            tree.Items.Add(item);
        }
        showing = false;
    }

    // MARK: The editor

    private void ShowEditor()
    {
        editor.Children.Clear();
        if (chosen is Guid id && book.Snippets.Folders.FirstOrDefault(f => f.Id == id) is { } folder)
        {
            editor.Children.Add(new TextBlock { Text = L10n.Tr("Folder name"), Margin = new Thickness(0, 0, 0, 4) });
            var name = new TextBox { Text = folder.Title };
            name.LostFocus += (_, _) => { if (name.Text != folder.Title) book.RenameFolder(id, name.Text); };
            name.KeyDown += (_, e) => { if (e.Key == Key.Enter) book.RenameFolder(id, name.Text); };
            editor.Children.Add(name);
            return;
        }
        if (chosen is not Guid sid || book.Snippets.Find(sid) is not { } snippet)
        {
            var keys = settings.ClipSnippetsShortcutEnabled ? ShortcutKeys.Label(settings.ClipSnippetsShortcut) : L10n.Tr("Paste a Snippet…");
            editor.Children.Add(new TextBlock { Text = L10n.Tr("Choose a snippet, or add one with + Snippet."), Foreground = System.Windows.Media.Brushes.Gray });
            editor.Children.Add(new TextBlock { Text = L10n.Tr("Paste them from any app with %@: type to search, Enter to paste.", keys), Foreground = System.Windows.Media.Brushes.Gray, Margin = new Thickness(0, 6, 0, 0), TextWrapping = TextWrapping.Wrap });
            return;
        }

        editor.Children.Add(new TextBlock { Text = L10n.Tr("Title"), Margin = new Thickness(0, 0, 0, 4) });
        var title = new TextBox { Text = snippet.Title };
        title.LostFocus += (_, _) => { if (book.Snippets.Find(sid) is { } s && s.Title != title.Text) book.Update(s with { Title = title.Text }); };
        editor.Children.Add(title);

        editor.Children.Add(new TextBlock { Text = L10n.Tr("Words"), Margin = new Thickness(0, 10, 0, 4) });
        var words = new TextBox { AcceptsReturn = true, AcceptsTab = true, TextWrapping = TextWrapping.Wrap, MinHeight = 160, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        if (snippet.Protected)
        {
            // Dots until Show…: nobody reads it over your shoulder. Windows asks for no fingerprint (SPEC §7.11).
            words.Text = Clipboard.Mask;
            words.IsReadOnly = true;
            var show = new Button { Content = L10n.Tr("Show…"), HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 4, 0, 0) };
            show.Click += (_, _) => { words.Text = book.Words(snippet); words.IsReadOnly = false; show.IsEnabled = false; };
            editor.Children.Add(words);
            editor.Children.Add(show);
            words.LostFocus += (_, _) => { if (!words.IsReadOnly && book.Snippets.Find(sid) is { } s) book.Update(s, secret: words.Text); };
        }
        else
        {
            words.Text = snippet.Text;
            words.LostFocus += (_, _) => { if (book.Snippets.Find(sid) is { } s && s.Text != words.Text) book.Update(s with { Text = words.Text }); };
            editor.Children.Add(words);
        }

        var locked = new CheckBox { Content = L10n.Tr("Protected: kept in Windows Credential Manager, shown as dots"), IsChecked = snippet.Protected, Margin = new Thickness(0, 10, 0, 0) };
        locked.Click += (_, _) =>
        {
            // Words being typed are saved first, so the switch carries them.
            if (!snippet.Protected && book.Snippets.Find(sid) is { } s && s.Text != words.Text) book.Update(s with { Text = words.Text });
            book.SetProtected(sid, locked.IsChecked == true);
        };
        editor.Children.Add(locked);

        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 10, 0, 0) };
        row.Children.Add(new TextBlock { Text = L10n.Tr("Shortcut"), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) });
        var record = new Button { MinWidth = 140, Content = recording ? L10n.Tr("Press the keys…") : snippet.Shortcut is { } k ? ShortcutKeys.Label(k) : "—" };
        record.Click += (_, _) => { if (recording) StopRecording(); else { recording = true; settings.RecordingShortcut = true; } ShowEditor(); };
        row.Children.Add(record);
        var clear = new Button { Content = L10n.Tr("Clear"), Margin = new Thickness(6, 0, 0, 0), IsEnabled = snippet.Shortcut is not null };
        clear.Click += (_, _) => { if (book.Snippets.Find(sid) is { } s) book.Update(s with { KeyCode = null, Modifiers = null }); };
        row.Children.Add(clear);
        editor.Children.Add(row);
    }

    private void StopRecording()
    {
        if (!recording) return;
        recording = false;
        settings.RecordingShortcut = false;
    }

    /// <summary>The next keys pressed become the chosen snippet's shortcut; Esc keeps the old one.</summary>
    private void RecordKey(object sender, KeyEventArgs e)
    {
        if (!recording) return;
        e.Handled = true;
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (ShortcutKeys.IsModifier(key)) return;
        var made = new Shortcut(KeyInterop.VirtualKeyFromKey(key), ShortcutKeys.From(Keyboard.Modifiers));
        if (key == Key.Escape && made.Modifiers == ShortcutModifiers.None) { StopRecording(); ShowEditor(); return; }
        if (!made.IsUsable) { SystemSounds.Beep.Play(); return; }
        StopRecording();
        if (chosen is Guid id && book.Snippets.Find(id) is { } s) book.Update(s with { Shortcut = made });
        ShowEditor();
    }
}

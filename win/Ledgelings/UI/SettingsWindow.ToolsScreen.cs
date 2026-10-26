using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Tools › Tools screen (SPEC §7.15): on or off, its shortcut, and which tiles show in what order. The
/// Mac's <c>ToolsScreenSettingsView.swift</c>; its drag to reorder is Move up and Move down here.</summary>
public sealed partial class SettingsWindow
{
    private void InitToolsScreen()
    {
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.ToolsScreenShortcut) or nameof(AppSettings.RecordingShortcut) or nameof(AppSettings.ToolsScreenTools))
                ShowToolsScreen();
        };
        ShowToolsScreen();
    }

    private void RefreshToolsScreen() => ShowToolsScreen();

    private void ShowToolsScreen()
    {
        ToolsScreenShortcutButton.Content = settings.RecordingShortcut && recordingButton == ToolsScreenShortcutButton
            ? L10n.Tr("Press the keys…") : ShortcutKeys.Label(settings.ToolsScreenShortcut);
        var shown = Tools.Shown(settings.ToolsScreenTools).ToList();
        // The ones shown in their order, then the ones switched off.
        var all = shown.Concat(Tools.All.Where(t => !shown.Contains(t))).ToList();
        ToolsScreenList.Children.Clear();
        var ink = Color.FromRgb(40, 34, 58);
        foreach (var tool in all)
        {
            var on = shown.Contains(tool);
            var row = new DockPanel { Margin = new Thickness(0, 2, 0, 2) };
            var at = shown.IndexOf(tool);
            var down = Mover(L10n.Tr("Move down"), on && at < shown.Count - 1, () => Move(shown, at, +1));
            var up = Mover(L10n.Tr("Move up"), on && at > 0, () => Move(shown, at, -1));
            DockPanel.SetDock(down, Dock.Right);
            DockPanel.SetDock(up, Dock.Right);
            row.Children.Add(down);
            row.Children.Add(up);
            var box = new CheckBox { IsChecked = on, VerticalAlignment = VerticalAlignment.Center };
            var label = new StackPanel { Orientation = Orientation.Horizontal };
            label.Children.Add(PixelGlyph.Image(tool.Icon(), ink));
            label.Children.Add(new TextBlock { Text = tool.Does(), Margin = new Thickness(8, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center });
            box.Content = label;
            box.Click += (_, _) =>
            {
                var codes = Tools.Shown(settings.ToolsScreenTools).ToList();
                if (box.IsChecked == true) codes.Add(tool); else codes.Remove(tool);
                settings.ToolsScreenTools = codes.Select(t => t.Code()).ToList();
            };
            row.Children.Add(box);
            ToolsScreenList.Children.Add(row);
        }
    }

    private static Button Mover(string words, bool enabled, Action click)
    {
        var button = new Button { Content = words, IsEnabled = enabled, Margin = new Thickness(4, 0, 0, 0), Padding = new Thickness(6, 0, 6, 0) };
        button.Click += (_, _) => click();
        return button;
    }

    private void Move(List<Tools.Tool> shown, int at, int by)
    {
        var to = at + by;
        if (at < 0 || to < 0 || to >= shown.Count) return;
        (shown[at], shown[to]) = (shown[to], shown[at]);
        settings.ToolsScreenTools = shown.Select(t => t.Code()).ToList();
    }

    private void ToolsScreenShortcutButton_Click(object sender, RoutedEventArgs e)
    {
        Record(ToolsScreenShortcutButton, made => settings.ToolsScreenShortcut = made);
        ShowToolsScreen();
    }
}

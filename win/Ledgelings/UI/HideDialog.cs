using System.Windows;
using System.Windows.Controls;

namespace Ledgelings.UI;

/// <summary>"Hide the creatures for a while": pick how long. Built in code; it is three controls.</summary>
public sealed class HideDialog : Window
{
    private readonly ComboBox choice = new() { Margin = new Thickness(0, 12, 0, 0), MinWidth = 220 };
    private bool accepted;

    private HideDialog()
    {
        Title = "Hide the creatures for a while";
        SizeToContent = SizeToContent.WidthAndHeight;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        ResizeMode = ResizeMode.NoResize;
        Topmost = true;
        ShowInTaskbar = false;
        foreach (var (title, _) in App.HideChoices) choice.Items.Add(title);
        choice.SelectedIndex = 2;
        var hide = new Button { Content = "Hide", IsDefault = true, MinWidth = 80, Margin = new Thickness(0, 0, 8, 0) };
        var cancel = new Button { Content = "Cancel", IsCancel = true, MinWidth = 80 };
        hide.Click += (_, _) => { accepted = true; Close(); };
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0) };
        buttons.Children.Add(hide);
        buttons.Children.Add(cancel);
        var panel = new StackPanel { Margin = new Thickness(20) };
        panel.Children.Add(new TextBlock
        {
            Text = "They run home, the house packs itself away, and when the time is up it comes back and they walk out.",
            TextWrapping = TextWrapping.Wrap, MaxWidth = 360,
        });
        panel.Children.Add(choice);
        panel.Children.Add(buttons);
        Content = panel;
    }

    /// <summary>Seconds to hide for, or null if the user cancelled.</summary>
    public static double? Ask()
    {
        var dialog = new HideDialog();
        dialog.ShowDialog();
        if (!dialog.accepted) return null;
        var minutes = App.HideChoices[Math.Max(0, dialog.choice.SelectedIndex)].Minutes;
        return minutes is double m ? m * 60 : App.SecondsUntilTomorrowMorning();
    }
}

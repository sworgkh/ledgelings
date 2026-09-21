using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Ledgelings.UI;

/// <summary>Pick a colour: three sliders and a hex field, with a swatch. WPF ships no colour picker.</summary>
public sealed class ColourDialog : Window
{
    private readonly Slider[] sliders = new Slider[3];
    private readonly TextBox hex = new() { Width = 90, VerticalAlignment = VerticalAlignment.Center };
    private readonly Border swatch = new() { Width = 64, Height = 64, CornerRadius = new CornerRadius(8), BorderBrush = Brushes.Gray, BorderThickness = new Thickness(1) };
    private bool accepted;
    private bool updating;
    private RGB value;

    private ColourDialog(RGB initial)
    {
        value = initial;
        Title = "Colour";
        SizeToContent = SizeToContent.WidthAndHeight;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        var grid = new Grid { Margin = new Thickness(20) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(220) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var names = new[] { "Red", "Green", "Blue" };
        for (int i = 0; i < 3; i++)
        {
            grid.RowDefinitions.Add(new RowDefinition());
            var label = new TextBlock { Text = names[i], VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 12, 0) };
            var slider = new Slider { Minimum = 0, Maximum = 255, SmallChange = 1, IsSnapToTickEnabled = true, TickFrequency = 1, VerticalAlignment = VerticalAlignment.Center };
            slider.ValueChanged += (_, _) => FromSliders();
            sliders[i] = slider;
            Grid.SetRow(label, i); Grid.SetColumn(label, 0);
            Grid.SetRow(slider, i); Grid.SetColumn(slider, 1);
            grid.Children.Add(label);
            grid.Children.Add(slider);
        }
        grid.RowDefinitions.Add(new RowDefinition());
        var hexRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 12, 0, 0) };
        hexRow.Children.Add(new TextBlock { Text = "Hex", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 12, 0) });
        hexRow.Children.Add(hex);
        hex.TextChanged += (_, _) => FromHex();
        Grid.SetRow(hexRow, 3); Grid.SetColumn(hexRow, 0); Grid.SetColumnSpan(hexRow, 2);
        grid.Children.Add(hexRow);
        Grid.SetRow(swatch, 0); Grid.SetRowSpan(swatch, 4); Grid.SetColumn(swatch, 2);
        swatch.Margin = new Thickness(16, 0, 0, 0);
        grid.Children.Add(swatch);

        var ok = new Button { Content = "OK", IsDefault = true, MinWidth = 80, Margin = new Thickness(0, 0, 8, 0) };
        var cancel = new Button { Content = "Cancel", IsCancel = true, MinWidth = 80 };
        ok.Click += (_, _) => { accepted = true; Close(); };
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(20, 0, 20, 20) };
        buttons.Children.Add(ok);
        buttons.Children.Add(cancel);
        var panel = new StackPanel();
        panel.Children.Add(grid);
        panel.Children.Add(buttons);
        Content = panel;
        Show(initial);
    }

    private void Show(RGB rgb)
    {
        updating = true;
        sliders[0].Value = rgb.R; sliders[1].Value = rgb.G; sliders[2].Value = rgb.B;
        hex.Text = rgb.Hex;
        swatch.Background = new SolidColorBrush(Bitmaps.ToMedia(rgb));
        updating = false;
    }

    private void FromSliders()
    {
        if (updating) return;
        value = new RGB((byte)sliders[0].Value, (byte)sliders[1].Value, (byte)sliders[2].Value);
        Show(value);
    }

    private void FromHex()
    {
        if (updating || RGB.FromHex(hex.Text.Trim()) is not RGB rgb) return;
        value = rgb;
        updating = true;
        sliders[0].Value = rgb.R; sliders[1].Value = rgb.G; sliders[2].Value = rgb.B;
        swatch.Background = new SolidColorBrush(Bitmaps.ToMedia(rgb));
        updating = false;
    }

    public static RGB? Ask(Window owner, RGB initial)
    {
        var dialog = new ColourDialog(initial) { Owner = owner };
        dialog.ShowDialog();
        return dialog.accepted ? dialog.value : null;
    }
}

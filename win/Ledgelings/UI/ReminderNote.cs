using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using Rect = System.Windows.Rect;
using Ledgelings.Core;
using Ledgelings.Native;

namespace Ledgelings.UI;

/// <summary>
/// Add a Reminder… as the game draws it: a sheet of the letter's pixel paper
/// with a creature peeking over the top edge. You write what to be reminded of,
/// step the day and the time with pixel arrows, pick a repeat, and fold it
/// into a plane. The Reminders tab keeps the list and the delivery settings.
///
/// A borderless, see-through WPF window that takes the keyboard, moved by dragging the paper.
/// </summary>
public sealed class ReminderNote : Window
{
    /// <summary>The sheet, in device-independent pixels; the paper is drawn at <see cref="Pixel"/> per paper pixel.</summary>
    public const double SheetWidth = 564, SheetHeight = 414;
    public const double Pixel = 3;
    /// <summary>Room above the paper for the creature peeking over it.</summary>
    private const double Headroom = 54;

    private static readonly Brush ink = Frozen(40, 34, 58), softInk = Frozen(92, 86, 120), faintInk = Frozen(150, 146, 170);
    private static readonly FontFamily mono = new("Consolas");

    private static ReminderNote? open;

    private readonly ReminderBook reminders;
    private readonly string? keeper;
    private DateTimeOffset time = SettingsWindow.NextRoundHour();
    private Reminders.Repeat repeats = Reminders.Repeat.Once;
    private bool folding;

    private readonly TextBox writing = new();
    private readonly TextBlock placeholder = new();
    private readonly TextBlock dayText = new(), clockText = new(), pastNote = new(), summary = new();
    private readonly List<(Reminders.Repeat Repeat, PixelButton Button)> repeatButtons = new();
    private readonly PixelButton foldButton = new() { Content = "FOLD IT INTO A PLANE", Chosen = true };
    private readonly Grid root = new() { Width = SheetWidth, Height = SheetHeight };

    /// <summary>Show the paper note, closing any open one first. <paramref name="keeper"/>: someone on screen to
    /// peek over its top edge, a name and an idle frame.</summary>
    public static void ShowNote(ReminderBook reminders, (string Name, System.Drawing.Bitmap? Face)? keeper)
    {
        open?.Close();
        open = new ReminderNote(reminders, keeper);
        open.Closed += (s, _) => { if (ReferenceEquals(open, s)) open = null; };
        open.Show();
        open.Activate();
    }

    private ReminderNote(ReminderBook reminders, (string Name, System.Drawing.Bitmap? Face)? who)
    {
        this.reminders = reminders;
        keeper = who?.Name;
        Title = "Add a Reminder";
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        SizeToContent = SizeToContent.WidthAndHeight;
        Topmost = true;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.Manual;
        Content = root;
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;
        // At 150 % a paper pixel is 4.5 screen pixels: square edges, not smoothed ones.
        RenderOptions.SetEdgeMode(root, EdgeMode.Aliased);

        var paper = new Image
        {
            Source = Bitmaps.ToSource(ScreenOverlay.PaperImage((int)(SheetWidth / Pixel), (int)((SheetHeight - Headroom) / Pixel))),
            Width = SheetWidth, Height = SheetHeight - Headroom, Stretch = Stretch.Fill,
            HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, Headroom, 0, 0),
        };
        RenderOptions.SetBitmapScalingMode(paper, BitmapScalingMode.NearestNeighbor);
        paper.MouseLeftButtonDown += (_, e) => { if (e.ButtonState == MouseButtonState.Pressed) DragMove(); };
        root.Children.Add(paper);
        if (who?.Face is System.Drawing.Bitmap face) root.Children.Add(Peeker(face));
        root.Children.Add(Sheet());

        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape) { e.Handled = true; Close(); }
            else if (e.Key == Key.Enter) { e.Handled = true; Send(); }
        };
        Loaded += (_, _) => { CentreOnCursorScreen(); writing.Focus(); };
        Refresh();
    }

    private static SolidColorBrush Frozen(byte r, byte g, byte b)
    {
        var brush = new SolidColorBrush(Color.FromRgb(r, g, b));
        brush.Freeze();
        return brush;
    }

    /// <summary>The middle of the screen the cursor is on, where the letters open too.</summary>
    private void CentreOnCursorScreen()
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        var cursor = Desktop.Cursor();
        var monitors = Desktop.Monitors();
        if (hwnd == IntPtr.Zero || (monitors.FirstOrDefault(m => m.Frame.Contains(cursor)) ?? Desktop.Primary(monitors)) is not Monitor m) return;
        var dpi = VisualTreeHelper.GetDpi(this);
        int w = (int)Math.Round(ActualWidth * dpi.DpiScaleX), h = (int)Math.Round(ActualHeight * dpi.DpiScaleY);
        Win32.SetWindowPos(hwnd, IntPtr.Zero, m.Left + (m.Width - w) / 2, m.Top + (m.Height - h) / 2, 0, 0,
            Win32.SWP_NOSIZE | Win32.SWP_NOACTIVATE | 0x0004 /* SWP_NOZORDER */);
    }

    /// <summary>The creature, its feet hidden behind the paper's top edge, eyes over it.</summary>
    private static FrameworkElement Peeker(System.Drawing.Bitmap face)
    {
        const double scale = 3;
        double w = face.Width * scale, h = face.Height * scale;
        var image = new Image
        {
            Source = Bitmaps.ToSource(face), Width = w, Height = h, Stretch = Stretch.Fill,
            HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top,
            IsHitTestVisible = false,
        };
        RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.NearestNeighbor);
        var top = Headroom + Pixel * 2 - Math.Min(h, Headroom + 6);
        image.Margin = new Thickness(SheetWidth - w - 60, top, 0, 0);
        // Only what shows over the paper's edge.
        image.Clip = new RectangleGeometry(new Rect(0, 0, w, Headroom + Pixel * 2 - top));
        return image;
    }

    private string TitleLine => keeper is string name
        ? $"A NOTE FOR THE LEDGELINGS · {name.ToUpperInvariant()} IS READING OVER THE EDGE"
        : "A NOTE FOR THE LEDGELINGS";

    private static TextBlock Text(string words, double size, Brush colour, FontWeight? weight = null) => new()
    {
        Text = words, FontFamily = mono, FontSize = size, FontWeight = weight ?? FontWeights.Bold, Foreground = colour,
        VerticalAlignment = VerticalAlignment.Center,
    };

    private static TextBlock Label(string words, double width = double.NaN)
    {
        var label = Text(words, 11, softInk);
        label.Width = width;
        return label;
    }

    private static StackPanel Row(double bottom, params UIElement[] children)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, bottom) };
        foreach (var child in children) row.Children.Add(child);
        return row;
    }

    private UIElement Sheet()
    {
        var sheet = new StackPanel
        {
            Margin = new Thickness(33, Headroom + 27, 33, 0), Width = SheetWidth - 66,
            HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top,
        };
        var title = Text(TitleLine, 11, faintInk);
        title.Margin = new Thickness(0, 0, 0, 10);
        sheet.Children.Add(title);

        // What
        var what = new StackPanel { Margin = new Thickness(0, 0, 0, 18) };
        what.Children.Add(Label("REMIND ME TO"));
        writing.FontFamily = mono;
        writing.FontSize = 22;
        writing.FontWeight = FontWeights.Bold;
        writing.Foreground = ink;
        writing.CaretBrush = ink;
        writing.Background = Brushes.Transparent;
        writing.BorderThickness = new Thickness(0);
        writing.TextChanged += (_, _) => Refresh();
        placeholder.Text = "stretch, call mom, stand-up…";
        placeholder.FontFamily = mono;
        placeholder.FontSize = 22;
        placeholder.FontWeight = FontWeights.Bold;
        placeholder.Foreground = faintInk;
        placeholder.IsHitTestVisible = false;
        var inside = new Grid { Margin = new Thickness(12, 10, 12, 10) };
        inside.Children.Add(placeholder);
        inside.Children.Add(writing);
        what.Children.Add(new PixelBox { Look = PixelBox.Finish.Well, Child = inside, Margin = new Thickness(0, 6, 0, 0) });
        sheet.Children.Add(what);

        // When
        pastNote.Text = "past: it comes\nstraight away";
        pastNote.FontFamily = mono;
        pastNote.FontSize = 10;
        pastNote.FontWeight = FontWeights.SemiBold;
        pastNote.Foreground = faintInk;
        pastNote.VerticalAlignment = VerticalAlignment.Center;
        sheet.Children.Add(Row(8, Label("WHEN", 62),
            Stepper(dayText, 150, () => Shift(-1), () => Shift(1)),
            Spacer(10),
            Stepper(clockText, 128, () => { time = Reminders.Step(time, -15); Refresh(); }, () => { time = Reminders.Step(time, 15); Refresh(); }),
            Spacer(10),
            pastNote));
        var soon = Row(14, Spacer(62 + 10));
        foreach (var (words, minutes) in new[] { ("IN 5 MIN", 5.0), ("IN 30 MIN", 30.0), ("IN 1 HOUR", 60.0) })
        {
            var button = new PixelButton { Content = words, Small = true, Margin = new Thickness(0, 0, 8, 0) };
            button.Click += (_, _) => { time = DateTimeOffset.Now.AddMinutes(minutes); Refresh(); };
            soon.Children.Add(button);
        }
        var tomorrow = new PixelButton { Content = "TOMORROW 9:00", Small = true };
        tomorrow.Click += (_, _) => { time = TomorrowMorning(); Refresh(); };
        soon.Children.Add(tomorrow);
        sheet.Children.Add(soon);

        // Repeat
        var repeat = Row(18, Label("REPEAT", 62 + 10));
        foreach (var choice in Reminders.AllRepeats)
        {
            var button = new PixelButton { Content = choice.Title().ToUpperInvariant(), Small = true, Margin = new Thickness(0, 0, 8, 0) };
            button.Click += (_, _) => { repeats = choice; Refresh(); };
            repeatButtons.Add((choice, button));
            repeat.Children.Add(button);
        }
        sheet.Children.Add(repeat);

        // Fold or not, clear of the paper's folded-down corner.
        var buttons = new DockPanel { Margin = new Thickness(0, 0, 24, 0), LastChildFill = true };
        var cancel = new PixelButton { Content = "NEVER MIND", Margin = new Thickness(0, 0, 8, 0) };
        cancel.Click += (_, _) => Close();
        foldButton.Click += (_, _) => Send();
        DockPanel.SetDock(foldButton, Dock.Right);
        DockPanel.SetDock(cancel, Dock.Right);
        buttons.Children.Add(foldButton);
        buttons.Children.Add(cancel);
        summary.FontFamily = mono;
        summary.FontSize = 11;
        summary.FontWeight = FontWeights.SemiBold;
        summary.Foreground = softInk;
        summary.VerticalAlignment = VerticalAlignment.Bottom;
        buttons.Children.Add(summary);
        sheet.Children.Add(buttons);
        return sheet;
    }

    private static FrameworkElement Spacer(double width) => new Border { Width = width };

    private FrameworkElement Stepper(TextBlock value, double width, Action back, Action on)
    {
        var left = new PixelButton { Content = "◀", Small = true };
        var right = new PixelButton { Content = "▶", Small = true };
        left.Click += (_, _) => back();
        right.Click += (_, _) => on();
        value.FontFamily = mono;
        value.FontSize = 15;
        value.FontWeight = FontWeights.Bold;
        value.Foreground = ink;
        value.HorizontalAlignment = HorizontalAlignment.Center;
        value.VerticalAlignment = VerticalAlignment.Center;
        var well = new PixelBox { Look = PixelBox.Finish.Well, Child = value, Width = width - 60, Height = 30, Margin = new Thickness(4, 0, 4, 0) };
        return Row(0, left, well, right);
    }

    private void Shift(int days)
    {
        time = time.AddDays(days);
        Refresh();
    }

    private static DateTimeOffset TomorrowMorning()
    {
        var tomorrow = DateTime.Today.AddDays(1);
        return new DateTimeOffset(tomorrow.AddHours(9));
    }

    private string Words => writing.Text.Trim();

    private void Refresh()
    {
        var now = DateTimeOffset.Now;
        placeholder.Visibility = writing.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        dayText.Text = Reminders.Day(time, now);
        clockText.Text = Reminders.Clock(time);
        pastNote.Visibility = time <= now ? Visibility.Visible : Visibility.Hidden;
        foreach (var (choice, button) in repeatButtons) button.Chosen = repeats == choice;
        summary.Text = Words.Length == 0 ? "write something first"
            : Reminders.When(time, now) + (repeats == Reminders.Repeat.Once ? "" : ", " + repeats.Title().ToLowerInvariant());
        foldButton.IsEnabled = Words.Length > 0;
        foldButton.Opacity = Words.Length > 0 ? 1 : 0.5;
    }

    private void Send()
    {
        if (Words.Length == 0 || folding) return;
        reminders.Add(Words, time, repeats);
        FoldAway();
    }

    /// <summary>Folded: the sheet shrinks up and away, as the plane will fly.</summary>
    private void FoldAway()
    {
        folding = true;
        IsHitTestVisible = false;
        var shrink = new ScaleTransform(1, 1, SheetWidth / 2, 0);
        var rise = new TranslateTransform();
        root.RenderTransform = new TransformGroup { Children = { shrink, rise } };
        var duration = new Duration(TimeSpan.FromSeconds(0.28));
        var ease = new QuadraticEase { EasingMode = EasingMode.EaseIn };
        shrink.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(40 / SheetWidth, duration) { EasingFunction = ease });
        shrink.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(30 / SheetHeight, duration) { EasingFunction = ease });
        rise.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(-40, duration) { EasingFunction = ease });
        var fade = new DoubleAnimation(0, duration);
        fade.Completed += (_, _) => Close();
        root.BeginAnimation(OpacityProperty, fade);
    }
}

/// <summary>A box in blocky's rules at the paper's pixel size: a flat fill, a dark rim,
/// a light line top-left and a shade line bottom-right, the rim's corner pixels cut
/// away (stepped, never rounded). A well (a field) is lit the other way round, so it
/// reads as pressed into the paper.</summary>
public sealed class PixelBox : Decorator
{
    public enum Finish { Raised, Pressed, Chosen, Well }

    private Finish look = Finish.Raised;
    public Finish Look { get => look; set { look = value; InvalidateVisual(); } }

    private static SolidColorBrush Rgb(byte r, byte g, byte b)
    {
        var brush = new SolidColorBrush(Color.FromRgb(r, g, b));
        brush.Freeze();
        return brush;
    }

    public static readonly SolidColorBrush Rim = Rgb(40, 34, 58);
    private static readonly SolidColorBrush white = Rgb(255, 255, 255);

    private static (Brush Fill, Brush TopLeft, Brush BottomRight) Colours(Finish style) => style switch
    {
        Finish.Raised => (Rgb(250, 248, 240), white, Rgb(196, 192, 206)),
        Finish.Pressed => (Rgb(226, 222, 212), Rgb(196, 192, 206), white),
        // Blocky's own orange, for the choice made and the button that does it.
        Finish.Chosen => (Rgb(255, 138, 61), Rgb(255, 178, 122), Rgb(214, 98, 32)),
        _ => (Rgb(234, 230, 218), Rgb(196, 192, 206), Rgb(250, 248, 240)),
    };

    public static void Draw(DrawingContext dc, Size size, Finish style)
    {
        double p = ReminderNote.Pixel, w = size.Width, h = size.Height;
        if (w < 3 * p || h < 3 * p) return;
        var (fill, light, shade) = Colours(style);
        // The rim, its four corner pixels left out.
        dc.DrawRectangle(Rim, null, new Rect(p, 0, w - 2 * p, h));
        dc.DrawRectangle(Rim, null, new Rect(0, p, p, h - 2 * p));
        dc.DrawRectangle(Rim, null, new Rect(w - p, p, p, h - 2 * p));
        dc.DrawRectangle(fill, null, new Rect(p, p, w - 2 * p, h - 2 * p));
        dc.DrawRectangle(light, null, new Rect(p, p, w - 2 * p, p));
        dc.DrawRectangle(light, null, new Rect(p, p, p, h - 2 * p));
        dc.DrawRectangle(shade, null, new Rect(p, h - 2 * p, w - 2 * p, p));
        dc.DrawRectangle(shade, null, new Rect(w - 2 * p, p, p, h - 2 * p));
    }

    protected override void OnRender(DrawingContext dc) => Draw(dc, RenderSize, look);
}

/// <summary>A button drawn as a <see cref="PixelBox"/> that sinks a pixel while pressed.</summary>
public sealed class PixelButton : Button
{
    private static readonly ControlTemplate template = MakeTemplate();
    private bool chosen;
    private bool small;

    private static ControlTemplate MakeTemplate()
    {
        var presenter = new FrameworkElementFactory(typeof(ContentPresenter));
        presenter.SetValue(HorizontalAlignmentProperty, HorizontalAlignment.Center);
        presenter.SetValue(VerticalAlignmentProperty, VerticalAlignment.Center);
        presenter.SetValue(ContentPresenter.MarginProperty, new TemplateBindingExtension(PaddingProperty));
        var template = new ControlTemplate(typeof(PixelButton)) { VisualTree = presenter };
        template.Seal();
        return template;
    }

    public PixelButton()
    {
        Template = template;
        FontFamily = new FontFamily("Consolas");
        FontWeight = FontWeights.Bold;
        Foreground = PixelBox.Rim;
        Background = Brushes.Transparent;
        Focusable = false;
        Cursor = Cursors.Hand;
        Apply();
    }

    public bool Chosen { get => chosen; set { chosen = value; InvalidateVisual(); } }
    public bool Small { get => small; set { small = value; Apply(); } }

    private void Apply()
    {
        FontSize = small ? 11 : 13;
        Padding = new Thickness(small ? 9 : 14, 0, small ? 9 : 14, 0);
        MinWidth = small ? 30 : 0;
        MinHeight = small ? 30 : 38;
    }

    protected override void OnIsPressedChanged(DependencyPropertyChangedEventArgs e)
    {
        base.OnIsPressedChanged(e);
        RenderTransform = IsPressed ? new TranslateTransform(0, ReminderNote.Pixel) : Transform.Identity;
        InvalidateVisual();
    }

    protected override void OnRender(DrawingContext dc) =>
        PixelBox.Draw(dc, RenderSize, IsPressed ? PixelBox.Finish.Pressed : chosen ? PixelBox.Finish.Chosen : PixelBox.Finish.Raised);
}

using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Ledgelings.Core;
using Ledgelings.Native;

namespace Ledgelings.UI;

/// <summary>
/// The Tools screen (SPEC §7.15), the Mac's <c>ToolsScreen.swift</c>: every tool the creatures run for you on one
/// sheet of the letter's pixel paper, a tile each. Ctrl+Alt+K from any app, the tray's Tools… item, or the
/// Creature Actions sheet's wrench (K). A click, its number, or the arrows and Enter start one; Esc closes.
/// The window you were in is put back in front before a tool starts, so a tool that pastes pastes there.
/// </summary>
public sealed class ToolsScreenController
{
    public const double TileWidth = 124, TileHeight = 128, Gap = 10;

    /// <summary>One tile as drawn: the tool, its number, whether it is on, and its shortcut from any app.</summary>
    public sealed record Tile(Tools.Tool Tool, int Number, bool On, string? Shortcut)
    {
        public string Tooltip => Tool.Tooltip(Number, Shortcut, On);
    }

    private readonly AppSettings settings;
    private ToolsScreenWindow? window;
    private IntPtr previous;

    /// <summary>Starts a tool, once the screen is gone.</summary>
    public Action<Tools.Tool> Start { get; set; } = _ => { };
    /// <summary>Whether a tool is switched on, and its shortcut from any app as written.</summary>
    public Func<Tools.Tool, bool> IsOn { get; set; } = _ => true;
    public Func<Tools.Tool, string?> ShortcutLabel { get; set; } = _ => null;
    /// <summary>A greyed tile opens the settings page that switches it on.</summary>
    public Action<SettingsPage> OpenSettings { get; set; } = _ => { };
    public Action<string>? Trace { get; set; }

    public IReadOnlyList<Tile> Tiles { get; private set; } = Array.Empty<Tile>();
    public int Chosen { get; set; }

    public ToolsScreenController(AppSettings settings) { this.settings = settings; }

    public bool IsUp => window is not null;

    public static Size SheetSize(int tiles)
    {
        var rows = Math.Max(1, (tiles + Tools.Columns - 1) / Tools.Columns);
        return new Size(Tools.Columns * TileWidth + (Tools.Columns - 1) * Gap + 2 * 33,
                        rows * TileHeight + (rows - 1) * Gap + 24 + 34 + 40 + 20);
    }

    public void Toggle() { if (IsUp) Close(); else Show(); }

    public void Show()
    {
        if (window is not null) { window.Activate(); return; }
        previous = ClipboardNative.GetForegroundWindow();
        var tools = Tools.Shown(settings.ToolsScreenTools);
        Tiles = tools.Select((tool, i) => new Tile(tool, i + 1, IsOn(tool), ShortcutLabel(tool))).ToList();
        Chosen = Math.Max(0, Tiles.ToList().FindIndex(t => t.On));
        var caret = previous == IntPtr.Zero ? null : ClipboardNative.Caret(previous);
        var monitor = ClipPickerController.Screen(caret, previous);
        window = new ToolsScreenWindow(this, monitor);
        window.Closed += (s, _) => { if (ReferenceEquals(window, s)) window = null; };      // Alt+F4: nothing else to undo
        window.Show();
        window.Activate();
        Trace?.Invoke("tools open: " + string.Join(", ", tools.Select(t => t.Code())));
    }

    public void Close() => Close(putBack: true);

    private void Close(bool putBack)
    {
        if (window is not { } w) return;
        window = null;
        if (!w.IsClosing) w.Close();
        if (putBack && previous != IntPtr.Zero && ClipboardNative.IsWindow(previous)) Win32.SetForegroundWindow(previous);
    }

    /// <summary>A key on the screen: its number, an arrow, Enter, Esc.</summary>
    internal bool Key(Key key, ModifierKeys modifiers)
    {
        if ((modifiers & (ModifierKeys.Control | ModifierKeys.Alt | ModifierKeys.Windows)) != 0) return false;
        Tools.Arrow? arrow = key switch
        {
            System.Windows.Input.Key.Left => Tools.Arrow.Left,
            System.Windows.Input.Key.Right => Tools.Arrow.Right,
            System.Windows.Input.Key.Up => Tools.Arrow.Up,
            System.Windows.Input.Key.Down => Tools.Arrow.Down,
            _ => null,
        };
        if (arrow is Tools.Arrow a) { Chosen = Tools.Step(Chosen, a, Tiles.Count); window?.Redraw(); return true; }
        switch (key)
        {
            case System.Windows.Input.Key.Escape: Close(); return true;
            case System.Windows.Input.Key.Enter: Choose(Chosen); return true;
            case >= System.Windows.Input.Key.D1 and <= System.Windows.Input.Key.D9:
                Choose(key - System.Windows.Input.Key.D1);
                return true;
            case >= System.Windows.Input.Key.NumPad1 and <= System.Windows.Input.Key.NumPad9:
                Choose(key - System.Windows.Input.Key.NumPad1);
                return true;
            default: return false;
        }
    }

    /// <summary>Tile <paramref name="index"/>: the screen goes, then the tool starts; a greyed one opens where to switch it on.</summary>
    internal void Choose(int index)
    {
        if (index < 0 || index >= Tiles.Count) return;
        var tile = Tiles[index];
        if (!tile.On)
        {
            Close(putBack: false);
            Trace?.Invoke($"tools: {tile.Tool.Code()} is off, opening its settings");
            OpenSettings(tile.Tool.Page());
            return;
        }
        Close(putBack: true);
        Trace?.Invoke("tools: start " + tile.Tool.Code());
        // A beat for the window you were in to have the keyboard back: the picker and the sheet note who it was.
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(150) };
        timer.Tick += (_, _) => { timer.Stop(); Start(tile.Tool); };
        timer.Start();
    }

    /// <summary>The paper as a PNG: <c>--tools --snapshot out.png</c>.</summary>
    public void Snapshot(string path)
    {
        if (window?.Picture() is not { } picture) return;
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(picture));
        using var file = File.Create(path);
        encoder.Save(file);
    }
}

/// <summary>The screen's window: see-through over the whole monitor, a click off the paper closes it.</summary>
internal sealed class ToolsScreenWindow : Window
{
    private static readonly Brush softInk = Frozen(92, 86, 120), faintInk = Frozen(150, 146, 170);
    private static readonly Color inkColour = Color.FromRgb(40, 34, 58);
    private static readonly FontFamily mono = new("Consolas");

    private readonly ToolsScreenController controller;
    private readonly Monitor monitor;
    private readonly Grid paper;
    private readonly StackPanel grid = new();
    /// <summary>On its way out: closing it again would throw.</summary>
    public bool IsClosing { get; private set; }

    public ToolsScreenWindow(ToolsScreenController controller, Monitor monitor)
    {
        this.controller = controller;
        this.monitor = monitor;
        var size = ToolsScreenController.SheetSize(controller.Tiles.Count);
        paper = new Grid { Width = size.Width, Height = size.Height, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        Title = L10n.Tr("Tools screen");
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0));
        ResizeMode = ResizeMode.NoResize;
        Topmost = true;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.Manual;
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;
        paper.MouseLeftButtonDown += (_, e) => e.Handled = true;
        var image = new Image
        {
            Source = Bitmaps.ToSource(ScreenOverlay.PaperImage((int)(size.Width / ReminderNote.Pixel), (int)(size.Height / ReminderNote.Pixel))),
            Stretch = Stretch.Fill,
        };
        RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.NearestNeighbor);
        paper.Children.Add(image);
        paper.Children.Add(Sheet());
        Content = new Grid { Children = { paper } };
        MouseLeftButtonDown += (_, _) => controller.Close();
        PreviewKeyDown += (_, e) =>
        {
            var key = e.Key == System.Windows.Input.Key.System ? e.SystemKey : e.Key;
            if (controller.Key(key, Keyboard.Modifiers)) e.Handled = true;
        };
        SourceInitialized += (_, _) =>
        {
            var hwnd = new WindowInteropHelper(this).Handle;
            Win32.SetWindowPos(hwnd, IntPtr.Zero, monitor.Left, monitor.Top, monitor.Width, monitor.Height, Win32.SWP_NOACTIVATE | 0x0004 /* SWP_NOZORDER */);
        };
        Loaded += (_, _) => Redraw();
        Closing += (_, _) => IsClosing = true;
        // Losing the keyboard closes it, but never from inside its own closing (Alt+F4): WPF would throw.
        Deactivated += (_, _) => { if (IsVisible && !IsClosing) Dispatcher.BeginInvoke(controller.Close); };
    }

    private static SolidColorBrush Frozen(byte r, byte g, byte b)
    {
        var brush = new SolidColorBrush(Color.FromRgb(r, g, b));
        brush.Freeze();
        return brush;
    }

    public BitmapSource Picture()
    {
        var dpi = VisualTreeHelper.GetDpi(this);
        var bitmap = new RenderTargetBitmap((int)Math.Round(paper.ActualWidth * dpi.DpiScaleX), (int)Math.Round(paper.ActualHeight * dpi.DpiScaleY),
                                            dpi.PixelsPerInchX, dpi.PixelsPerInchY, PixelFormats.Pbgra32);
        bitmap.Render(paper);
        bitmap.Freeze();
        return bitmap;
    }

    private UIElement Sheet()
    {
        var stack = new DockPanel { Margin = new Thickness(33, 24, 33, 20), LastChildFill = true };
        var top = new TextBlock { Text = L10n.Tr("TOOLS"), FontFamily = mono, FontSize = 11, FontWeight = FontWeights.Bold, Foreground = faintInk, Height = 24 };
        DockPanel.SetDock(top, Dock.Top);
        stack.Children.Add(top);
        var count = controller.Tiles.Count;
        var footer = new TextBlock
        {
            Text = count == 0 ? L10n.Tr("No tools chosen: Settings › Tools › Tools screen.")
                : L10n.Tr("1–%d START  ←→↑↓ CHOOSE  ENTER START  ESC CLOSE", Math.Min(count, 9)),
            FontFamily = mono, FontSize = 9, FontWeight = FontWeights.Heavy, Foreground = faintInk, Margin = new Thickness(0, 8, 60, 0),
        };
        DockPanel.SetDock(footer, Dock.Bottom);
        stack.Children.Add(footer);
        DockPanel.SetDock(grid, Dock.Top);
        stack.Children.Add(grid);
        stack.Children.Add(new Border());
        return stack;
    }

    public void Redraw()
    {
        grid.Children.Clear();
        var tiles = controller.Tiles;
        for (var r = 0; r < tiles.Count; r += Tools.Columns)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, r == 0 ? 0 : ToolsScreenController.Gap, 0, 0) };
            for (var i = r; i < Math.Min(r + Tools.Columns, tiles.Count); i++)
                row.Children.Add(TileView(i, row.Children.Count == 0 ? 0 : ToolsScreenController.Gap));
            grid.Children.Add(row);
        }
    }

    /// <summary>A tile: its picture big, its name, its shortcut under it, its number in the corner (AGENTS rule 4).</summary>
    private FrameworkElement TileView(int index, double left)
    {
        var tile = controller.Tiles[index];
        var chosen = index == controller.Chosen;
        var face = new Grid();
        var words = new StackPanel { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
        var picture = PixelGlyph.Image(tile.Tool.Icon(), inkColour, 4);
        picture.Margin = new Thickness(0, 0, 0, 6);
        words.Children.Add(picture);
        words.Children.Add(new TextBlock
        {
            Text = tile.Tool.Title(), FontFamily = mono, FontSize = 10, FontWeight = FontWeights.Heavy, Foreground = PixelBox.Rim,
            TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap, Width = ToolsScreenController.TileWidth - 16,
        });
        words.Children.Add(new TextBlock
        {
            Text = tile.On ? tile.Shortcut ?? " " : L10n.Tr("off"), FontFamily = mono, FontSize = 9, FontWeight = FontWeights.SemiBold, Foreground = softInk,
            TextAlignment = TextAlignment.Center, Margin = new Thickness(0, 2, 0, 0),
        });
        face.Children.Add(words);
        face.Children.Add(new TextBlock
        {
            Text = tile.Number <= 9 ? tile.Number.ToString() : " ", FontFamily = mono, FontSize = 9, FontWeight = FontWeights.Heavy, Foreground = faintInk,
            HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 8, 9, 0),
        });
        var box = new PixelBox
        {
            Look = chosen ? PixelBox.Finish.Chosen : PixelBox.Finish.Raised, Child = face,
            Width = ToolsScreenController.TileWidth, Height = ToolsScreenController.TileHeight, Margin = new Thickness(left, 0, 0, 0),
            Opacity = tile.On ? 1 : 0.45, Cursor = Cursors.Hand, ToolTip = tile.Tooltip,
        };
        System.Windows.Automation.AutomationProperties.SetName(box, tile.Tooltip);
        box.MouseEnter += (_, _) => { if (controller.Chosen != index) { controller.Chosen = index; Redraw(); } };
        box.MouseLeftButtonUp += (_, e) => { e.Handled = true; controller.Choose(index); };
        return box;
    }
}

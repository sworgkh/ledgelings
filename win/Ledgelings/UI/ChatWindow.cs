using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using Ledgelings.Core;
using Ledgelings.Native;

namespace Ledgelings.UI;

/// <summary>
/// Chat with the creatures (SPEC §7.18.1), the Mac's <c>ChatWindow.swift</c>: the letter's pixel paper with a To: row
/// (Everyone, then each creature on screen by its sprite and name), the talk so far and a text box. The creatures stay on
/// their edges and turn to face it while they answer.
///
/// Keys, Windows' way round: Enter sends, Shift+Enter is a new line, Ctrl+0 writes to everyone, Ctrl+1–9 to one,
/// Ctrl+, opens the settings, Esc closes. Like the other sheets it takes the keyboard and puts the window you were in
/// back in front when it closes.
/// </summary>
public sealed class ChatController
{
    public const double SheetWidth = 760, SheetHeight = 470;

    private readonly AppSettings settings;
    internal AppSettings Settings => settings;
    private readonly Func<Colony?> colony;
    private ChatSheetWindow? window;
    private IntPtr previous;
    private Task? answering;

    /// <summary>A line of the talk: the owner's (<see cref="Speaker"/> "") or a creature's.</summary>
    public sealed record Line(string Speaker, string Text, string? To = null, double? Cost = null)
    {
        public bool IsOwner => Speaker.Length == 0;
    }

    public IReadOnlyList<Colony.ChatTarget> Targets { get; private set; } = Array.Empty<Colony.ChatTarget>();
    /// <summary>Whom the next message goes to; null is everyone.</summary>
    public string? Chosen { get; private set; }
    public List<Line> Lines { get; } = new();
    /// <summary>Who is writing an answer now.</summary>
    public string? ThinkingName { get; private set; }
    public string Status { get; private set; } = "";
    public bool HasModel { get; private set; } = true;
    public bool IsUp => window is not null;
    public bool IsAnswering => answering is not null;

    public Action<string>? Trace { get; set; }
    /// <summary>Answers without a model (<c>LEDGELINGS_FAKE_CHAT</c>, the tests).</summary>
    public Colony.ChatFake? Fake { get; set; }
    /// <summary>Opens Settings at a page.</summary>
    public Action<SettingsPage> OpenSettings { get; set; } = _ => { };

    public ChatController(AppSettings settings, Func<Colony?> colony)
    {
        this.settings = settings;
        this.colony = colony;
    }

    /// <summary>The shortcut: up, or away if it is up.</summary>
    public void Toggle() { if (IsUp) Close(); else Show(); }

    /// <summary>Up, written to <paramref name="to"/> (a name; null keeps the last choice, Everyone at first).</summary>
    public void Show(string? to = null)
    {
        settings.RetryOpenRouterKey();
        Refresh();
        if (to is not null) Chosen = Targets.Any(t => t.Name == to) ? to : null;
        if (window is not null) { window.Redraw(); return; }
        previous = ClipboardNative.GetForegroundWindow();
        var monitor = WindowPlacer.SheetMonitor(WindowPlaces.Window.Chat, settings, ClipPickerController.Screen(null, previous));
        window = new ChatSheetWindow(this, monitor);
        window.Closed += (s, _) => { if (ReferenceEquals(window, s)) { window = null; Gone(); } };
        window.Show();
        window.Activate();
        window.Unfold(settings.ClipAnimate ? ClipHelper.UnfoldSeconds / settings.ClipAnimationSpeed : 0);
        Trace?.Invoke($"chat open on {monitor.Name}, to {Chosen ?? "everyone"}, {Targets.Count} on screen");
    }

    /// <summary>Who is on screen, and whether anyone can answer.</summary>
    public void Refresh()
    {
        Targets = colony()?.ChatTargets() ?? Array.Empty<Colony.ChatTarget>();
        if (Chosen is not null && !Targets.Any(t => t.Name == Chosen)) Chosen = null;
        HasModel = Fake is not null || settings.Brain != BrainKind.Script;
    }

    public void Close()
    {
        if (window is not { } w) return;
        window = null;
        if (!w.IsClosing) w.Close();
        Gone();
        if (previous != IntPtr.Zero && ClipboardNative.IsWindow(previous)) Win32.SetForegroundWindow(previous);
    }

    /// <summary>Gone; answers already asked for still come, on screen and in the log.</summary>
    private void Gone() => Trace?.Invoke("chat close" + (IsAnswering ? ", still answering" : ""));

    // MARK: Keys

    /// <summary>A key pressed on the window; false lets it through to the text box.</summary>
    internal bool Key(Key key, ModifierKeys modifiers)
    {
        bool ctrl = modifiers.HasFlag(ModifierKeys.Control), alt = modifiers.HasFlag(ModifierKeys.Alt), shift = modifiers.HasFlag(ModifierKeys.Shift);
        switch (key)
        {
            case System.Windows.Input.Key.Escape: Close(); return true;
            case System.Windows.Input.Key.Enter:
                if (shift) return false;
                Send(window?.Typed ?? "");
                return true;
            case System.Windows.Input.Key.D0 or System.Windows.Input.Key.NumPad0 when ctrl && !alt: Choose(null); return true;
            case System.Windows.Input.Key.OemComma when ctrl && !alt: Act(OwnerChat.Button.Settings); return true;
            case >= System.Windows.Input.Key.D1 and <= System.Windows.Input.Key.D9 when ctrl && !alt:
                var n = key - System.Windows.Input.Key.D1;
                if (n < Targets.Count) Choose(Targets[n].Name); else System.Media.SystemSounds.Beep.Play();
                return true;
            default: return false;
        }
    }

    public void Act(OwnerChat.Button button)
    {
        switch (button)
        {
            case OwnerChat.Button.Send: Send(window?.Typed ?? ""); break;
            case OwnerChat.Button.Everyone: Choose(null); break;
            case OwnerChat.Button.Close: Close(); break;
            default:
                Close();
                OpenSettings(HasModel ? SettingsPage.ChatWithYou : SettingsPage.Talk);
                break;
        }
    }

    /// <summary>Who the next message goes to: a name, or null for everyone.</summary>
    public void Choose(string? name)
    {
        Chosen = name;
        Trace?.Invoke($"chat to {name ?? "everyone"}");
        window?.Redraw();
    }

    // MARK: Sending

    /// <summary>Enter: the text goes to whoever is chosen, and they answer in turn.</summary>
    public void Send(string typed)
    {
        var text = typed.Trim();
        if (text.Length == 0) { System.Media.SystemSounds.Beep.Play(); return; }
        if (answering is not null) { Tell(L10n.Tr("Wait for them to finish answering.")); System.Media.SystemSounds.Beep.Play(); return; }
        if (colony() is not { } c) { Tell(L10n.Tr("The creatures are not on screen.")); return; }
        Refresh();
        if (!HasModel) { window?.Redraw(); System.Media.SystemSounds.Beep.Play(); return; }
        var to = Chosen;
        Lines.Add(new Line("", text, to));
        Status = "";
        window?.Clear();
        Trace?.Invoke($"chat sent to {to ?? "everyone"}: {text}");
        // The colony counts y up from the primary screen's top, as the sheets hand it the paper.
        var paper = window?.PaperOnScreen();
        var centre = paper is { } p ? new Pt(p.Left + p.Width / 2.0, -(p.Top + p.Height / 2.0)) : new Pt(0, 0);
        answering = Run();
        window?.Redraw();

        async Task Run()
        {
            try { await c.AnswerOwner(text, to, centre, Fake, Heard); }
            finally
            {
                ThinkingName = null;
                answering = null;
                Trace?.Invoke("chat done");
                window?.Redraw();
            }
        }
    }

    private void Heard(Colony.ChatEvent e)
    {
        switch (e)
        {
            case Colony.ChatEvent.Thinking t: ThinkingName = t.Name; break;
            case Colony.ChatEvent.Answer a:
                ThinkingName = null;
                Lines.Add(new Line(a.Name, a.Text, Cost: a.Cost));
                break;
            case Colony.ChatEvent.Quiet q:
                ThinkingName = null;
                Status = q.Why;
                Trace?.Invoke($"chat {q.Name} quiet: {q.Why}");
                break;
            case Colony.ChatEvent.Trouble t:
                ThinkingName = null;
                Status = t.Why;
                Trace?.Invoke($"chat trouble: {t.Why}");
                break;
        }
        window?.Redraw();
    }

    private void Tell(string line)
    {
        Status = line;
        window?.Redraw();
    }

    /// <summary>Wait until every answer to the last message is in and said.</summary>
    public async Task Finished()
    {
        while (answering is { } task) await task;
    }

    public System.Drawing.Bitmap? Portrait(string name) => Targets.FirstOrDefault(t => t.Name == name)?.Portrait;

    /// <summary>The paper as it looks now, for <c>--chat-window --snapshot</c>.</summary>
    public BitmapSource? Picture() => window?.Picture();
}

/// <summary>The chat's window: see-through over the whole monitor, so a click off the paper closes it, with the paper in
/// the middle. Its buttons are made once and only their look changes, so a hover tag stays up while they answer.</summary>
internal sealed class ChatSheetWindow : Window
{
    private static readonly Brush ink = Frozen(40, 34, 58), softInk = Frozen(92, 86, 120), faintInk = Frozen(150, 146, 170);
    private static readonly Color inkColour = Color.FromRgb(40, 34, 58);
    private static readonly FontFamily mono = new("Consolas");

    private readonly ChatController controller;
    private readonly SheetDrag drag;
    private readonly Grid paper = new() { Width = ChatController.SheetWidth, Height = ChatController.SheetHeight };
    private readonly ScaleTransform scale = new(1, 1);
    private readonly TextBox box = new();
    private readonly TextBlock status = new();
    private readonly StackPanel to = new() { Orientation = Orientation.Horizontal }, talk = new();
    private readonly ScrollViewer talkScroll = new() { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    private readonly Dictionary<OwnerChat.Button, PixelBox> buttons = new();
    private readonly PixelBox everyoneChip = new();
    private readonly DockPanel noModel = new();
    private string toShown = "";
    private int linesShown = -1;
    private string? thinkingShown = "";
    public bool IsClosing { get; private set; }

    public ChatSheetWindow(ChatController controller, Monitor monitor)
    {
        this.controller = controller;
        Title = L10n.Tr("Chat with the creatures");
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0));
        ResizeMode = ResizeMode.NoResize;
        Topmost = true;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.Manual;
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;
        paper.HorizontalAlignment = HorizontalAlignment.Center;
        paper.VerticalAlignment = VerticalAlignment.Center;
        paper.RenderTransform = scale;
        paper.Opacity = 0;
        drag = new SheetDrag(this, paper, monitor, ChatController.SheetWidth, ChatController.SheetHeight, WindowPlaces.Window.Chat, controller.Settings);
        var image = new Image
        {
            Source = Bitmaps.ToSource(ScreenOverlay.PaperImage((int)(ChatController.SheetWidth / ReminderNote.Pixel), (int)(ChatController.SheetHeight / ReminderNote.Pixel))),
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
        Loaded += (_, _) => { box.Focus(); Redraw(); };
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

    public string Typed => box.Text;
    public void Clear() => box.Clear();

    /// <summary>The paper's bounds in screen pixels.</summary>
    public System.Drawing.Rectangle PaperOnScreen() => drag.OnScreen();

    /// <summary>The window opens out of its middle.</summary>
    public void Unfold(double seconds)
    {
        paper.RenderTransformOrigin = new Point(0.5, 0.5);
        if (seconds <= 0) { paper.Opacity = 1; scale.ScaleX = scale.ScaleY = 1; return; }
        var ease = new QuadraticEase { EasingMode = EasingMode.EaseOut };
        var grow = new DoubleAnimation(0.06, 1, TimeSpan.FromSeconds(seconds)) { EasingFunction = ease };
        scale.BeginAnimation(ScaleTransform.ScaleXProperty, grow);
        scale.BeginAnimation(ScaleTransform.ScaleYProperty, grow);
        paper.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromSeconds(seconds)) { EasingFunction = ease });
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

    private TextBlock Words(string text, double size, Brush brush, FontWeight? weight = null) =>
        new() { Text = text, FontFamily = mono, FontSize = size, FontWeight = weight ?? FontWeights.Heavy, Foreground = brush, TextWrapping = TextWrapping.Wrap };

    private UIElement Sheet()
    {
        var stack = new DockPanel { Margin = new Thickness(27, 22, 27, 18), LastChildFill = true };

        var footer = Words(L10n.Tr("ENTER SEND  SHIFT+ENTER NEW LINE  CTRL+1–9 TO ONE  CTRL+0 EVERYONE  CTRL+, SETTINGS  ESC CLOSE"), 9, faintInk);
        footer.Margin = new Thickness(0, 8, 0, 0);
        Pixel.AsHints(footer);
        DockPanel.SetDock(footer, Dock.Bottom);
        stack.Children.Add(footer);

        // The text box and Send, clear of the paper's folded corner.
        box.FontFamily = mono; box.FontSize = Pixel.SmallField; box.FontWeight = FontWeights.SemiBold; box.Foreground = ink; box.CaretBrush = ink;
        box.Background = Brushes.Transparent; box.BorderThickness = new Thickness(0);
        box.AcceptsReturn = true; box.TextWrapping = TextWrapping.Wrap; box.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        box.TextChanged += (_, _) =>
        {
            box.FlowDirection = Translate.Detect(box.Text)?.RightToLeft == true ? FlowDirection.RightToLeft : FlowDirection.LeftToRight;
            buttons[OwnerChat.Button.Send].Look = box.Text.Trim().Length > 0 ? PixelBox.Finish.Chosen : PixelBox.Finish.Raised;
        };
        var input = new DockPanel { Margin = new Thickness(0, 6, 46, 0), Height = 58 };
        var send = Button(OwnerChat.Button.Send);
        send.VerticalAlignment = VerticalAlignment.Bottom;
        send.Margin = new Thickness(8, 0, 0, 0);
        DockPanel.SetDock(send, Dock.Right);
        input.Children.Add(send);
        input.Children.Add(new PixelBox { Look = PixelBox.Finish.Well, Child = new Border { Margin = new Thickness(8, 5, 8, 5), Child = box } });
        DockPanel.SetDock(input, Dock.Bottom);
        stack.Children.Add(input);

        // One line under the talk: why nothing was sent, or (with no model) the way to the settings.
        status.FontFamily = mono; status.FontSize = Pixel.Label; status.FontWeight = FontWeights.Heavy; status.Foreground = PixelBox.Rim;
        status.TextTrimming = TextTrimming.CharacterEllipsis; status.Margin = new Thickness(0, 6, 0, 0);
        var open = new PixelBox
        {
            Look = PixelBox.Finish.Chosen, Cursor = Cursors.Hand, ToolTip = OwnerChat.Button.Settings.Tooltip(), Margin = new Thickness(8, 0, 0, 0),
            Child = Words(L10n.Tr("OPEN SETTINGS"), 11, PixelBox.Rim),
        };
        ((TextBlock)open.Child).Margin = new Thickness(9, 6, 9, 6);
        open.MouseLeftButtonUp += (_, e) => { e.Handled = true; controller.Act(OwnerChat.Button.Settings); };
        DockPanel.SetDock(open, Dock.Right);
        noModel.Margin = new Thickness(0, 8, 0, 0);
        noModel.Children.Add(open);
        noModel.Children.Add(Words(OwnerChat.NoModel, 11, PixelBox.Rim));
        var under = new Grid { Children = { status, noModel } };
        DockPanel.SetDock(under, Dock.Bottom);
        stack.Children.Add(under);

        var top = new DockPanel { Margin = new Thickness(0, 0, 0, 6) };
        var close = Button(OwnerChat.Button.Close);
        var settingsButton = Button(OwnerChat.Button.Settings);
        settingsButton.Margin = new Thickness(0, 0, 6, 0);
        DockPanel.SetDock(close, Dock.Right);
        DockPanel.SetDock(settingsButton, Dock.Right);
        top.Children.Add(close);
        top.Children.Add(settingsButton);
        top.Children.Add(Words(L10n.Tr("CHAT WITH THE CREATURES"), 11, faintInk, FontWeights.Bold));
        DockPanel.SetDock(top, Dock.Top);
        stack.Children.Add(top);

        var row = new DockPanel { Margin = new Thickness(0, 0, 0, 8) };
        var label = Words(L10n.Tr("TO:"), 11, softInk);
        label.VerticalAlignment = VerticalAlignment.Center;
        label.Margin = new Thickness(0, 0, 6, 0);
        DockPanel.SetDock(label, Dock.Left);
        row.Children.Add(label);
        everyoneChip.Cursor = Cursors.Hand;
        everyoneChip.Margin = new Thickness(0, 0, 6, 0);
        everyoneChip.Child = new StackPanel
        {
            Orientation = Orientation.Horizontal, Margin = new Thickness(8, 5, 9, 5),
            Children = { PixelGlyph.Image(OwnerChat.Button.Everyone.Icon(), inkColour, 1.5), Words(" " + L10n.Tr("EVERYONE"), 11, PixelBox.Rim) },
        };
        Tag(everyoneChip, OwnerChat.Button.Everyone.Tooltip());
        everyoneChip.MouseLeftButtonUp += (_, e) => { e.Handled = true; controller.Choose(null); };
        DockPanel.SetDock(everyoneChip, Dock.Left);
        row.Children.Add(everyoneChip);
        row.Children.Add(new ScrollViewer { HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled, Content = to });
        DockPanel.SetDock(row, Dock.Top);
        stack.Children.Add(row);

        talk.Margin = new Thickness(10);
        talkScroll.Content = talk;
        stack.Children.Add(new PixelBox { Look = PixelBox.Finish.Well, Child = new Border { Margin = new Thickness(4), Child = talkScroll } });
        return stack;
    }

    private PixelBox Button(OwnerChat.Button button)
    {
        var face = new PixelBox { Look = PixelBox.Finish.Raised, Child = new Border { Child = PixelGlyph.Image(button.Icon(), inkColour, 2), Margin = new Thickness(6) }, Cursor = Cursors.Hand };
        Tag(face, button.Tooltip());
        face.MouseLeftButtonUp += (_, e) => { e.Handled = true; controller.Act(button); };
        buttons[button] = face;
        return face;
    }

    /// <summary>On hover its name and key (AGENTS rule 4); read out by a screen reader.</summary>
    private static void Tag(FrameworkElement face, string tip)
    {
        face.ToolTip = tip;
        System.Windows.Automation.AutomationProperties.SetName(face, tip);
    }

    private static Image PortraitImage(System.Drawing.Bitmap? bitmap, double size)
    {
        var image = new Image { Width = size, Height = size, Source = bitmap is null ? null : Bitmaps.ToSource(bitmap) };
        RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.NearestNeighbor);
        return image;
    }

    /// <summary>Everything again from the controller; the chips and the talk only when they changed, so a tag stays up.</summary>
    public void Redraw()
    {
        var c = controller;
        var culture = Languages.Current.Culture();
        var key = string.Join("|", c.Targets.Select(t => t.Name)) + "#" + c.Chosen + "#" + Languages.Current;
        if (key != toShown)
        {
            toShown = key;
            everyoneChip.Look = c.Chosen is null ? PixelBox.Finish.Chosen : PixelBox.Finish.Raised;
            to.Children.Clear();
            for (var i = 0; i < c.Targets.Count; i++)
            {
                var t = c.Targets[i];
                var chip = new PixelBox
                {
                    Look = t.Name == c.Chosen ? PixelBox.Finish.Chosen : PixelBox.Finish.Raised, Cursor = Cursors.Hand, Margin = new Thickness(0, 0, 6, 0),
                    Child = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(6, 3, 9, 3), Children = { PortraitImage(t.Portrait, 20), Words(" " + t.Name.ToUpper(culture), 11, PixelBox.Rim) } },
                };
                Tag(chip, OwnerChat.WriteTo(t.Name, i < 9 ? i + 1 : null));
                var name = t.Name;
                chip.MouseLeftButtonUp += (_, e) => { e.Handled = true; controller.Choose(name); };
                to.Children.Add(chip);
            }
        }
        if (c.Lines.Count != linesShown || c.ThinkingName != thinkingShown)
        {
            linesShown = c.Lines.Count;
            thinkingShown = c.ThinkingName;
            DrawTalk();
        }
        var trouble = !c.HasModel;
        noModel.Visibility = trouble ? Visibility.Visible : Visibility.Collapsed;
        status.Visibility = trouble ? Visibility.Collapsed : Visibility.Visible;
        status.Text = c.Status;
        buttons[OwnerChat.Button.Send].Opacity = c.HasModel ? 1 : 0.45;
    }

    private void DrawTalk()
    {
        var c = controller;
        var culture = Languages.Current.Culture();
        talk.Children.Clear();
        if (c.Lines.Count == 0)
            talk.Children.Add(Words(c.Chosen is { } who ? L10n.Tr("Write to %@ and press Enter.", who) : L10n.Tr("Write to all of them and press Enter: a few will answer, one after another."), 13, faintInk, FontWeights.SemiBold));
        foreach (var line in c.Lines)
        {
            var words = Words(line.Text, 13, ink, FontWeights.SemiBold);
            words.Margin = new Thickness(9, 6, 9, 6);
            var bubble = new PixelBox { Look = line.IsOwner ? PixelBox.Finish.Chosen : PixelBox.Finish.Raised, Child = words };
            if (line.IsOwner)
            {
                var head = Words(line.To is { } t ? L10n.Tr("YOU → %@", t.ToUpper(culture)) : L10n.Tr("YOU → EVERYONE"), 9, faintInk);
                head.HorizontalAlignment = HorizontalAlignment.Right;
                talk.Children.Add(new StackPanel { HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(80, 0, 0, 8), Children = { head, bubble } });
            }
            else
            {
                var column = new StackPanel { Children = { Words(line.Speaker.ToUpper(culture), 9, faintInk), bubble } };
                var face = PortraitImage(c.Portrait(line.Speaker), 26);
                face.VerticalAlignment = VerticalAlignment.Top;
                face.Margin = new Thickness(0, 0, 8, 0);
                talk.Children.Add(new DockPanel { Margin = new Thickness(0, 0, 80, 8), HorizontalAlignment = HorizontalAlignment.Left, Children = { face, column } });
            }
        }
        if (c.ThinkingName is { } thinking)
        {
            var face = PortraitImage(c.Portrait(thinking), 22);
            face.Margin = new Thickness(0, 0, 6, 0);
            talk.Children.Add(new StackPanel { Orientation = Orientation.Horizontal, Children = { face, Words("•••  " + OwnerChat.Thinking(thinking), 13, softInk, FontWeights.SemiBold) } });
        }
        // The newest line stays in sight.
        talkScroll.ScrollToEnd();
    }
}

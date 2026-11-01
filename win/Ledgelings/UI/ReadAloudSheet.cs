using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;
using Ledgelings.Core;
using Ledgelings.Native;
using R = Ledgelings.Core.ReadAloud;
using Rect = Ledgelings.Core.Rect;
using WpfClipboard = System.Windows.Clipboard;

namespace Ledgelings.UI;

/// <summary>
/// The Read aloud sheet (SPEC §7.16.1), the Mac's <c>ReadAloudSheet.swift</c>: the clipboard picker's pixel paper, the
/// presets as chips, the text to read, and the controls of the reading under it. A creature brings it and reads
/// beside it, nodding over the page with a dot running along its bubble.
///
/// Keys, Windows' way round: Enter reads, pauses and goes on, Shift+Enter is a new line, Ctrl+. stops, Ctrl+S saves the
/// sound, Ctrl+Shift+C copies it as a file, Ctrl+- and Ctrl+= the pace (from the next part), Ctrl+1–9 a preset, Ctrl+R
/// the next reader, Ctrl+Shift+Backspace clears, Esc closes. Like the Translate sheet it takes the keyboard (Windows
/// gives it only to the active window) and puts the window you were in back in front when it closes.
/// </summary>
public sealed class ReadAloudSheetController
{
    public const double SheetWidth = 760, SheetHeight = 470;

    private readonly AppSettings settings;
    private readonly ClipBook book;
    private readonly Func<Colony?> colony;
    private ReadAloudSheetWindow? window;
    private IntPtr previous;
    private Win32.RECT? caret;
    private bool helped;

    public ReadAloudPlayer Player { get; }

    // What the sheet shows.
    public string Text { get; private set; } = "";
    public IReadOnlyList<R.Preset> Presets { get; private set; } = R.DefaultPresets;
    public Guid? PresetId { get; private set; }
    /// <summary>The preset as it was handed to the sheet, when it was; wins over the saved one of the same id.</summary>
    private R.Preset? given;
    /// <summary>The character reading, chosen on the sheet; "" is the narrator.</summary>
    public string Reader { get; private set; } = "";
    public IReadOnlyList<string> Readers { get; private set; } = new[] { "" };
    /// <summary>The pace, chosen on the sheet: the preset's to begin with.</summary>
    public double Speed { get; private set; } = 1;
    /// <summary>A long paid text shows its price and waits for a second Enter.</summary>
    public bool WaitingForEnter { get; private set; }
    /// <summary>Why nothing is read, or what happened to the file; over the player's own status.</summary>
    public string Note { get; private set; } = "";
    public bool NoteIsTrouble { get; private set; }

    /// <summary>Everyone who can read, by name, every species' cast; the narrator is added first.</summary>
    public Func<IReadOnlyList<string>> AllReaders { get; set; } = () => Array.Empty<string>();
    public Action<string>? Trace { get; set; }

    public ReadAloudSheetController(AppSettings settings, ReadAloudPlayer player, ClipBook book, Func<Colony?> colony)
    {
        this.settings = settings;
        Player = player;
        this.book = book;
        this.colony = colony;
        player.Changed += () => window?.Redraw();
        player.PhaseChanged += PhaseChanged;
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName != nameof(AppSettings.ReadAloudPresets)) return;
            Presets = settings.ReadAloudPresets;
            if (!Presets.Any(p => p.Id == PresetId)) PresetId = Presets.FirstOrDefault()?.Id;
            window?.Redraw();
        };
    }

    public bool IsUp => window is not null;

    /// <summary>The preset chosen, with the reader and pace chosen on the sheet.</summary>
    public R.Preset CurrentPreset
    {
        get
        {
            var chosen = given is { } g && g.Id == PresetId ? g : Presets.FirstOrDefault(p => p.Id == PresetId) ?? Presets.FirstOrDefault() ?? R.DefaultPresets[0];
            return R.Chosen(chosen, Reader, Speed);
        }
    }

    public string ReaderTitle => Reader.Length == 0 ? L10n.Tr("NARRATOR") : Reader.ToUpper(Languages.Current.Culture());

    private void Tell(string line, bool trouble)
    {
        Note = line;
        NoteIsTrouble = trouble;
        window?.Redraw();
    }

    // MARK: Opening and closing

    /// <summary>The shortcut: up with the clipboard's text (and reading it, as the settings say); pressed again while
    /// up, it closes; while a reading the sheet let go goes on, it comes back showing it.</summary>
    public void Toggle()
    {
        if (IsUp) { Close(); return; }
        if (Player.IsActive) { Show(null, start: false); return; }
        var copied = settings.ReadAloudFromClipboard ? ClipboardText() : null;
        if (copied is not null && R.RefusalOf(copied, book.Snippets) == R.Refusal.Protected)
        {
            Show("", start: false);
            Tell(R.Refusal.Protected.Line(), trouble: true);
            return;
        }
        Show(copied ?? "", start: settings.ReadAloudStartAtOnce && copied is not null);
    }

    private static string? ClipboardText()
    {
        var text = ClipPaster.Retry<string>(() => WpfClipboard.ContainsText() ? WpfClipboard.GetText() : "");
        return string.IsNullOrEmpty(text) ? null : text;
    }

    /// <summary>Up holding <paramref name="text"/> (null: what is being read now); <paramref name="start"/> reads it at
    /// once. <paramref name="preset"/>: one handed in as it is, not looked up again by its id.</summary>
    public void Show(string? text, bool start, R.Preset? preset = null)
    {
        settings.RetryOpenRouterKey();
        if (window is null)
        {
            previous = ClipboardNative.GetForegroundWindow();
            caret = previous == IntPtr.Zero ? null : ClipboardNative.Caret(previous);
        }
        Presets = settings.ReadAloudPresets;
        if (text is not null)
        {
            Text = text;
            var chosen = preset ?? settings.ReadAloudDefault;
            PresetId = chosen.Id;
            given = preset;
            Reader = chosen.Character;
            Speed = chosen.Speed;
            Note = "";
            WaitingForEnter = false;
        }
        else Text = Player.Text;
        Readers = new[] { "" }.Concat(AllReaders().Where(n => n.Length > 0)).Distinct().ToList();
        if (window is not null)
        {
            window.SetText(Text);
            window.Redraw();
            if (start) ReadNow();
            return;
        }
        var monitor = ClipPickerController.Screen(caret, previous);
        window = new ReadAloudSheetWindow(this, monitor);
        // Closed some other way (Alt+F4): the same clean-up as Esc.
        window.Closed += (s, _) => { if (ReferenceEquals(window, s)) { window = null; Gone(); } };
        window.SetText(Text);
        window.Show();
        window.Activate();
        Trace?.Invoke($"read sheet open on {monitor.Name}, {Text.Length} characters");
        var paper = window.PaperOnScreen();
        double? leap = settings.ReadAloudHelperEnabled
            ? colony()?.ClipHelperCome(new Rect(paper.Left, -(paper.Top + paper.Height), paper.Width, paper.Height),
                                       new Pt(monitor.Left + monitor.Width / 2.0, -(monitor.Top + monitor.Height / 2.0)), settings.ReadAloudHelper)
            : null;
        helped = leap is not null;
        if (!settings.ClipAnimate) window.Unfold(0, helped);
        else if (leap is double w) After(w, () => window?.Unfold(ClipHelper.UnfoldSeconds / settings.ClipAnimationSpeed, true));
        else window.Unfold(ClipHelper.UnfoldSeconds / settings.ClipAnimationSpeed, false);
        PhaseChanged(Player.Now);
        window.Redraw();
        if (start) ReadNow();
    }

    public void Close() => Close(putBack: true);

    private void Close(bool putBack)
    {
        if (window is not { } w) return;
        window = null;
        if (!w.IsClosing) w.Close();
        Gone();
        if (putBack && previous != IntPtr.Zero && ClipboardNative.IsWindow(previous)) Win32.SetForegroundWindow(previous);
    }

    /// <summary>The sheet is gone, however it went: the reading goes on if the settings say so (the tray's Stop Reading
    /// ends it), else it stops; a paused one always stops. The creature goes home.</summary>
    private void Gone()
    {
        if (!settings.ReadAloudKeepReading || Player.Now == ReadAloudPlayer.Phase.Paused) Player.Stop();
        if (helped) { colony()?.ClipHelperMoodTo(Colony.ClipHelperMood.Calm); colony()?.ClipHelperGoHome(); }
        helped = false;
        Trace?.Invoke("read sheet close" + (Player.IsActive ? ", still reading" : ""));
    }

    private void PhaseChanged(ReadAloudPlayer.Phase phase)
    {
        if (!helped) return;
        colony()?.ClipHelperMoodTo(phase switch
        {
            ReadAloudPlayer.Phase.Preparing => Colony.ClipHelperMood.Thinking,
            ReadAloudPlayer.Phase.Playing => Colony.ClipHelperMood.Reading,
            ReadAloudPlayer.Phase.Trouble => Colony.ClipHelperMood.Puzzled,
            _ => Colony.ClipHelperMood.Calm,
        });
    }

    private static void After(double seconds, Action action)
    {
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(Math.Max(seconds, 0.001)) };
        timer.Tick += (_, _) => { timer.Stop(); action(); };
        timer.Start();
    }

    // MARK: Keys

    /// <summary>A key pressed on the sheet; false lets it through to the text box.</summary>
    internal bool Key(Key key, ModifierKeys modifiers)
    {
        bool ctrl = modifiers.HasFlag(ModifierKeys.Control), alt = modifiers.HasFlag(ModifierKeys.Alt), shift = modifiers.HasFlag(ModifierKeys.Shift);
        switch (key)
        {
            case System.Windows.Input.Key.Escape: Close(); return true;
            case System.Windows.Input.Key.Enter:
                if (shift) return false;
                Act(R.Button.Play);
                return true;
            case System.Windows.Input.Key.OemPeriod or System.Windows.Input.Key.Decimal when ctrl && !alt: Act(R.Button.Stop); return true;
            case System.Windows.Input.Key.S when ctrl && !alt: Act(R.Button.Save); return true;
            case System.Windows.Input.Key.C when ctrl && shift && !alt: Act(R.Button.Copy); return true;
            case System.Windows.Input.Key.OemMinus or System.Windows.Input.Key.Subtract when ctrl && !alt: Act(R.Button.Slower); return true;
            case System.Windows.Input.Key.OemPlus or System.Windows.Input.Key.Add when ctrl && !alt: Act(R.Button.Faster); return true;
            case System.Windows.Input.Key.R when ctrl && !alt: Act(R.Button.Reader); return true;
            // Ctrl+Backspace deletes a word in every Windows text box: Clear takes Shift too.
            case System.Windows.Input.Key.Back when ctrl && shift: Clear(); return true;
            case >= System.Windows.Input.Key.D1 and <= System.Windows.Input.Key.D9 when ctrl && !alt: ChoosePreset(key - System.Windows.Input.Key.D1); return true;
            case >= System.Windows.Input.Key.NumPad1 and <= System.Windows.Input.Key.NumPad9 when ctrl && !alt: ChoosePreset(key - System.Windows.Input.Key.NumPad1); return true;
            default: return false;
        }
    }

    internal void Act(R.Button button)
    {
        switch (button)
        {
            case R.Button.Play or R.Button.Pause:
                switch (Player.Now)
                {
                    case ReadAloudPlayer.Phase.Playing: Player.Pause(); break;
                    case ReadAloudPlayer.Phase.Paused: Player.Resume(); break;
                    case ReadAloudPlayer.Phase.Preparing: Player.Stop(); break;
                    default: ReadNow(confirmed: WaitingForEnter); break;
                }
                break;
            case R.Button.Stop: Player.Stop(); break;
            case R.Button.Save: Save(); break;
            case R.Button.Copy: Copy(); break;
            case R.Button.Slower: Pace(-1); break;
            case R.Button.Faster: Pace(1); break;
            case R.Button.Reader: NextReader(); break;
        }
        window?.Redraw();
    }

    /// <summary>Ctrl+1…: that preset, its reader and pace with it.</summary>
    internal void ChoosePreset(int n)
    {
        if (n < 0 || n >= Presets.Count) { System.Media.SystemSounds.Beep.Play(); return; }
        var preset = Presets[n];
        PresetId = preset.Id;
        given = null;
        Reader = preset.Character;
        Speed = preset.Speed;
        WaitingForEnter = false;
        Note = "";
        Trace?.Invoke("read preset " + preset.Name);
        if (Player.IsActive)
        {
            Player.SetPace(Speed);
            Tell(L10n.Tr("%@ from the next part", R.SpeedLabel(Speed)), trouble: false);
        }
        window?.Redraw();
    }

    /// <summary>Windows cannot stretch a part already here: the new pace is asked of the parts still to come.</summary>
    private void Pace(int steps)
    {
        Speed = R.Step(Speed, steps);
        if (Player.IsActive)
        {
            Player.SetPace(Speed);
            Tell(L10n.Tr("%@ from the next part", R.SpeedLabel(Speed)), trouble: false);
        }
        Trace?.Invoke("read pace " + R.SpeedLabel(Speed));
    }

    /// <summary>Ctrl+R: the next reader, the narrator first, then every character of every species; for the next reading.</summary>
    private void NextReader()
    {
        Reader = R.NextReader(Readers, Reader);
        WaitingForEnter = false;
        Trace?.Invoke("read reader " + (Reader.Length == 0 ? "narrator" : Reader));
    }

    private void Clear()
    {
        Text = "";
        window?.SetText("");
        Edited();
        window?.Redraw();
    }

    /// <summary>What the text box reports as you type: Enter will read it afresh; a long text asks again.</summary>
    internal void Typed(string text)
    {
        Text = text;
        var waited = WaitingForEnter || Note.Length > 0;
        Edited();
        if (waited) window?.Redraw();
    }

    private void Edited()
    {
        WaitingForEnter = false;
        Note = "";
    }

    // MARK: Reading

    /// <summary>Enter: read the text with the chosen preset. Above the long-text limit a paid reading first shows its
    /// parts and price, and reads on the next Enter.</summary>
    internal void ReadNow(bool confirmed = false)
    {
        var text = Text;
        if (R.RefusalOf(text, book.Snippets) is { } refusal)
        {
            Tell(refusal.Line(), trouble: true);
            System.Media.SystemSounds.Beep.Play();
            Trace?.Invoke("read refused: " + refusal.Line());
            return;
        }
        var preset = CurrentPreset;
        if (!confirmed && text.Length > settings.ReadAloudLongLimit && Player.PlanFor(preset).Engine.IsPaid())
        {
            var parts = R.Parts(text, forced: preset.ForcedLanguage).Count;
            var characters = L10n.TrCount(text.Length, "character", "characters");
            WaitingForEnter = true;
            Tell(Player.Estimate(text, preset) is double cost
                ? L10n.Tr("%@ · %@ · about %@ · Enter reads", characters, L10n.TrCount(parts, "part", "parts"), Spend.Label(cost))
                : L10n.Tr("%@ · %@ · Enter reads", characters, L10n.TrCount(parts, "part", "parts")), trouble: false);
            Trace?.Invoke("read waits for Enter: " + Note);
            return;
        }
        WaitingForEnter = false;
        Note = "";
        Player.Read(text, preset);
    }

    // MARK: The sound out

    /// <summary>Ctrl+S: the reading as one WAV in the save folder, named by its time and first words.</summary>
    internal void Save()
    {
        if (!Player.HasSound) { Tell(L10n.Tr("Nothing read yet: Enter reads it first"), trouble: true); System.Media.SystemSounds.Beep.Play(); return; }
        var folder = settings.ReadAloudFolderPath;
        var path = System.IO.Path.Combine(folder, R.FileName(Player.Text, DateTime.Now, ReadAloudPlayer.SavedFormat));
        try
        {
            Directory.CreateDirectory(folder);
            Player.Write(path);
            var name = System.IO.Path.GetFileName(path);
            Tell(Player.IsComplete ? L10n.Tr("Saved: %@", name) : L10n.Tr("Saved what is read so far: %@", name), trouble: false);
            Trace?.Invoke("read saved " + path);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or InvalidOperationException or ArgumentException or NotSupportedException)
        {
            Tell(L10n.Tr("Could not save in %@: %@", folder, e.Message), trouble: true);
            Trace?.Invoke("read save trouble: " + e.Message);
        }
    }

    /// <summary>Ctrl+Shift+C: the reading as a file on the clipboard, to drop into a chat or a mail.</summary>
    internal void Copy()
    {
        if (!Player.HasSound) { Tell(L10n.Tr("Nothing read yet: Enter reads it first"), trouble: true); System.Media.SystemSounds.Beep.Play(); return; }
        var folder = ReadAloudPlayer.CopyFolder;
        try
        {
            // The last copy goes; one still open in a chat app (Windows locks it) is left.
            Directory.CreateDirectory(folder);
            foreach (var old in Directory.EnumerateFiles(folder))
            {
                try { File.Delete(old); }
                catch (Exception gone) when (gone is IOException or UnauthorizedAccessException) { }
            }
            var path = System.IO.Path.Combine(folder, R.FileName(Player.Text, DateTime.Now, ReadAloudPlayer.SavedFormat));
            Player.Write(path);
            // Marked as ours, so the clipboard history does not keep it.
            if (!ClipPaster.PutFiles(new[] { path })) throw new IOException(L10n.Tr("the clipboard is busy; try again"));
            Tell(L10n.Tr("The sound file is on the clipboard: Ctrl+V drops it into a chat or a mail"), trouble: false);
            Trace?.Invoke("read copied " + System.IO.Path.GetFileName(path));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or InvalidOperationException or System.Runtime.InteropServices.ExternalException)
        {
            Tell(L10n.Tr("Could not copy the sound: %@", e.Message), trouble: true);
        }
    }
}

/// <summary>The sheet's window: see-through over the whole monitor, so a click off the paper closes it, with the paper
/// in the middle. The buttons are made once and only their state changes, so a hover tag stays up while it reads.</summary>
internal sealed class ReadAloudSheetWindow : Window
{
    private static readonly Brush ink = Frozen(40, 34, 58), softInk = Frozen(92, 86, 120), faintInk = Frozen(150, 146, 170);
    private static readonly Brush orange = Frozen(255, 138, 61), come = new SolidColorBrush(Color.FromArgb(89, 150, 146, 170));
    private static readonly Color inkColour = Color.FromRgb(40, 34, 58);
    private static readonly FontFamily mono = new("Consolas");

    private readonly ReadAloudSheetController controller;
    private readonly Monitor monitor;
    private readonly Grid paper = new() { Width = ReadAloudSheetController.SheetWidth, Height = ReadAloudSheetController.SheetHeight };
    private readonly ScaleTransform scale = new(1, 1);
    private readonly TextBox box = new();
    private readonly TextBlock hint = new(), status = new(), dots = new(), pace = new(), reader = new(), clock = new();
    private readonly StackPanel chips = new() { Orientation = Orientation.Horizontal };
    private readonly Grid heard = new(), arrived = new();
    private readonly Dictionary<R.Button, PixelBox> buttons = new();
    private string chipsShown = "";
    private bool settingText;
    /// <summary>On its way out: closing it again would throw.</summary>
    public bool IsClosing { get; private set; }

    public ReadAloudSheetWindow(ReadAloudSheetController controller, Monitor monitor)
    {
        this.controller = controller;
        this.monitor = monitor;
        Title = L10n.Tr("Read aloud");
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
        paper.MouseLeftButtonDown += (_, e) => e.Handled = true;
        var image = new Image
        {
            Source = Bitmaps.ToSource(ScreenOverlay.PaperImage((int)(ReadAloudSheetController.SheetWidth / ReminderNote.Pixel), (int)(ReadAloudSheetController.SheetHeight / ReminderNote.Pixel))),
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
        Loaded += (_, _) => { box.Focus(); box.CaretIndex = box.Text.Length; Redraw(); };
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

    /// <summary>The paper's bounds in screen pixels.</summary>
    public System.Drawing.Rectangle PaperOnScreen()
    {
        UpdateLayout();
        var dpi = VisualTreeHelper.GetDpi(this);
        int w = (int)Math.Round(ReadAloudSheetController.SheetWidth * dpi.DpiScaleX), h = (int)Math.Round(ReadAloudSheetController.SheetHeight * dpi.DpiScaleY);
        return new System.Drawing.Rectangle(monitor.Left + (monitor.Width - w) / 2, monitor.Top + (monitor.Height - h) / 2, w, h);
    }

    /// <summary>The sheet opens: out of its top-left corner, held by a creature, or out of its middle.</summary>
    public void Unfold(double seconds, bool fromCorner)
    {
        paper.RenderTransformOrigin = fromCorner ? new Point(0, 0) : new Point(0.5, 0.5);
        if (seconds <= 0) { paper.Opacity = 1; scale.ScaleX = scale.ScaleY = 1; return; }
        var ease = new QuadraticEase { EasingMode = EasingMode.EaseOut };
        var grow = new DoubleAnimation(0.06, 1, TimeSpan.FromSeconds(seconds)) { EasingFunction = ease };
        scale.BeginAnimation(ScaleTransform.ScaleXProperty, grow);
        scale.BeginAnimation(ScaleTransform.ScaleYProperty, grow);
        paper.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromSeconds(seconds)) { EasingFunction = ease });
    }

    /// <summary>The paper as it looks now.</summary>
    public BitmapSource Picture()
    {
        var dpi = VisualTreeHelper.GetDpi(this);
        var bitmap = new RenderTargetBitmap((int)Math.Round(paper.ActualWidth * dpi.DpiScaleX), (int)Math.Round(paper.ActualHeight * dpi.DpiScaleY),
                                            dpi.PixelsPerInchX, dpi.PixelsPerInchY, PixelFormats.Pbgra32);
        bitmap.Render(paper);
        bitmap.Freeze();
        return bitmap;
    }

    /// <summary>The text box holds <paramref name="text"/>, the cursor at its end; not reported back as typing.</summary>
    public void SetText(string text)
    {
        settingText = true;
        box.Text = text;
        box.CaretIndex = text.Length;
        settingText = false;
    }

    private UIElement Sheet()
    {
        var stack = new DockPanel { Margin = new Thickness(27, 24, 27, 20), LastChildFill = true };
        var footer = new TextBlock
        {
            Text = L10n.Tr("ENTER READ · PAUSE  SHIFT+ENTER NEW LINE  CTRL+. STOP  CTRL+- CTRL+= PACE  CTRL+1–9 PRESET  CTRL+R READER  CTRL+S SAVE  CTRL+SHIFT+C COPY  ESC CLOSE"),
            FontFamily = mono, FontSize = 9, FontWeight = FontWeights.Heavy, Foreground = faintInk, Margin = new Thickness(0, 8, 60, 0),
            TextTrimming = TextTrimming.CharacterEllipsis,
        };
        DockPanel.SetDock(footer, Dock.Bottom);
        stack.Children.Add(footer);

        var column = new StackPanel();
        column.Children.Add(new TextBlock { Text = L10n.Tr("READ ALOUD"), FontFamily = mono, FontSize = 11, FontWeight = FontWeights.Bold, Foreground = faintInk, Margin = new Thickness(0, 0, 0, 8) });
        chips.Margin = new Thickness(0, 0, 0, 8);
        column.Children.Add(chips);

        // The text to read: a real text box, so Hebrew runs right to left and the usual keys work.
        box.FontFamily = mono; box.FontSize = 15; box.FontWeight = FontWeights.SemiBold; box.Foreground = ink; box.CaretBrush = ink;
        box.Background = Brushes.Transparent; box.BorderThickness = new Thickness(0);
        box.AcceptsReturn = true; box.AcceptsTab = false; box.TextWrapping = TextWrapping.Wrap;
        box.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        box.TextChanged += (_, _) =>
        {
            if (!settingText) controller.Typed(box.Text);
            hint.Visibility = box.Text.Length == 0 ? Visibility.Visible : Visibility.Hidden;
            box.FlowDirection = Translate.Detect(box.Text)?.RightToLeft == true ? FlowDirection.RightToLeft : FlowDirection.LeftToRight;
        };
        hint.Text = L10n.Tr("Paste or type, choose a preset, and Enter reads it.");
        hint.FontFamily = mono; hint.FontSize = 15; hint.FontWeight = FontWeights.SemiBold; hint.Foreground = faintInk; hint.IsHitTestVisible = false; hint.TextWrapping = TextWrapping.Wrap;
        column.Children.Add(new PixelBox { Look = PixelBox.Finish.Well, Height = 210, Child = new Grid { Margin = new Thickness(10, 8, 10, 8), Children = { hint, box } } });

        column.Children.Add(Controls());
        column.Children.Add(Progress());

        dots.Text = "•••"; dots.Foreground = softInk; dots.Margin = new Thickness(0, 0, 8, 0);
        status.TextWrapping = TextWrapping.Wrap; status.MaxHeight = 30;
        foreach (var t in new[] { dots, status }) { t.FontFamily = mono; t.FontSize = 11; t.FontWeight = FontWeights.Heavy; }
        var line = new DockPanel { Margin = new Thickness(0, 8, 0, 0) };
        DockPanel.SetDock(dots, Dock.Left);
        line.Children.Add(dots);
        line.Children.Add(status);
        column.Children.Add(line);
        stack.Children.Add(column);
        return stack;
    }

    /// <summary>Read or pause, stop; slower, the pace, faster; the next reader and its name; save, copy.</summary>
    private UIElement Controls()
    {
        var row = new DockPanel { Margin = new Thickness(0, 10, 0, 0), LastChildFill = false };
        var left = new StackPanel { Orientation = Orientation.Horizontal };
        left.Children.Add(Button(R.Button.Play));
        left.Children.Add(Gap(6));
        left.Children.Add(Button(R.Button.Stop));
        left.Children.Add(Gap(20));
        left.Children.Add(Button(R.Button.Slower));
        pace.Width = 48; pace.TextAlignment = TextAlignment.Center;
        left.Children.Add(pace);
        left.Children.Add(Button(R.Button.Faster));
        left.Children.Add(Gap(20));
        left.Children.Add(Button(R.Button.Reader));
        reader.Margin = new Thickness(8, 0, 0, 0); reader.MaxWidth = 220; reader.TextTrimming = TextTrimming.CharacterEllipsis;
        left.Children.Add(reader);
        foreach (var t in new[] { pace, reader }) { t.FontFamily = mono; t.FontSize = 12; t.FontWeight = FontWeights.Heavy; t.Foreground = ink; t.VerticalAlignment = VerticalAlignment.Center; }
        var right = new StackPanel { Orientation = Orientation.Horizontal };
        right.Children.Add(Button(R.Button.Save));
        right.Children.Add(Gap(6));
        right.Children.Add(Button(R.Button.Copy));
        DockPanel.SetDock(left, Dock.Left);
        DockPanel.SetDock(right, Dock.Right);
        row.Children.Add(left);
        row.Children.Add(right);
        return row;
    }

    private static Border Gap(double width) => new() { Width = width };

    /// <summary>The bar (heard in orange over come in grey) and the clock, <c>~</c> until every part is in.</summary>
    private UIElement Progress()
    {
        var row = new DockPanel { Margin = new Thickness(0, 10, 0, 0) };
        clock.FontFamily = mono; clock.FontSize = 11; clock.FontWeight = FontWeights.Heavy; clock.Foreground = softInk;
        clock.Width = 104; clock.TextAlignment = TextAlignment.Right; clock.VerticalAlignment = VerticalAlignment.Center;
        DockPanel.SetDock(clock, Dock.Right);
        row.Children.Add(clock);
        foreach (var (bar, brush) in new[] { (arrived, come), (heard, orange) })
        {
            bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0, GridUnitType.Star) });
            bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            bar.Children.Add(new Rectangle { Fill = brush, Height = 10 });
        }
        var well = new PixelBox { Look = PixelBox.Finish.Well, Height = 18, Margin = new Thickness(0, 0, 10, 0), Child = new Grid { Margin = new Thickness(4, 4, 4, 4), Children = { arrived, heard } } };
        row.Children.Add(well);
        return row;
    }

    private PixelBox Button(R.Button button)
    {
        var face = new PixelBox { Look = PixelBox.Finish.Raised, Child = new Border { Child = PixelGlyph.Image(button.Icon(), inkColour, 2), Margin = new Thickness(6) }, Cursor = Cursors.Hand };
        Label(face, button);
        // Read stands for pause while it plays: the one button acts for both.
        face.MouseLeftButtonUp += (_, e) => { e.Handled = true; controller.Act(button); };
        buttons[button] = face;
        return face;
    }

    /// <summary>On hover its name and key (AGENTS rule 4); read out by a screen reader.</summary>
    private static void Label(FrameworkElement face, R.Button button)
    {
        var tip = button.Tooltip();
        face.ToolTip = tip;
        System.Windows.Automation.AutomationProperties.SetName(face, tip);
    }

    /// <summary>Everything again from the controller and the player.</summary>
    public void Redraw()
    {
        var c = controller;
        var player = c.Player;
        DrawChips();
        // Read becomes pause while it plays.
        var play = buttons[R.Button.Play];
        var shownButton = player.Now == ReadAloudPlayer.Phase.Playing ? R.Button.Pause : R.Button.Play;
        if (play.Child is Border face && !Equals(face.Tag, shownButton))
        {
            face.Tag = shownButton;
            face.Child = PixelGlyph.Image(shownButton.Icon(), inkColour, 2);
            Label(play, shownButton);
        }
        play.Look = player.Now == ReadAloudPlayer.Phase.Playing ? PixelBox.Finish.Chosen : PixelBox.Finish.Raised;
        buttons[R.Button.Stop].Opacity = player.IsActive ? 1 : 0.45;
        buttons[R.Button.Save].Opacity = buttons[R.Button.Copy].Opacity = player.HasSound ? 1 : 0.45;
        pace.Text = R.SpeedLabel(c.Speed);
        reader.Text = c.ReaderTitle;

        var ready = player.PartsTotal > 0 ? (double)player.PartsReady / player.PartsTotal : 0;
        var shown = player.Length > 0 ? Math.Min(player.Played / player.Length, 1) : 0;
        Fill(arrived, ready);
        Fill(heard, shown);
        clock.Text = player.PartsTotal == 0 ? "0:00 / 0:00"
            : $"{R.Clock(player.Played)} / {(player.IsComplete ? "" : "~")}{R.Clock(player.Length)}";

        var trouble = c.Note.Length == 0 ? player.Now == ReadAloudPlayer.Phase.Trouble : c.NoteIsTrouble;
        status.Text = c.Note.Length > 0 ? c.Note : player.Status.Length > 0 ? player.Status : L10n.Tr("Paste or type, choose a preset, and Enter reads it.");
        status.Foreground = trouble ? PixelBox.Rim : softInk;
        dots.Visibility = player.Now == ReadAloudPlayer.Phase.Preparing ? Visibility.Visible : Visibility.Collapsed;
        hint.Visibility = box.Text.Length == 0 ? Visibility.Visible : Visibility.Hidden;
    }

    private static void Fill(Grid bar, double share)
    {
        share = Math.Clamp(share, 0, 1);
        bar.ColumnDefinitions[0].Width = new GridLength(share, GridUnitType.Star);
        bar.ColumnDefinitions[1].Width = new GridLength(1 - share, GridUnitType.Star);
        bar.Visibility = share > 0 ? Visibility.Visible : Visibility.Hidden;
    }

    /// <summary>The preset chips, made again only when the presets or the chosen one change, so a tag stays up.</summary>
    private void DrawChips()
    {
        var c = controller;
        var key = string.Join("|", c.Presets.Select(p => $"{p.Id}:{p.Title}:{p.Character}:{p.Voice}:{p.Speed}")) + "#" + c.PresetId + "#" + Languages.Current;
        if (key == chipsShown) return;
        chipsShown = key;
        chips.Children.Clear();
        var culture = Languages.Current.Culture();
        for (var i = 0; i < c.Presets.Count; i++)
        {
            var n = i;
            var preset = c.Presets[i];
            var chip = new PixelBox
            {
                Look = preset.Id == c.PresetId ? PixelBox.Finish.Chosen : PixelBox.Finish.Raised,
                Child = new TextBlock { Text = preset.Title.ToUpper(culture), FontFamily = mono, FontSize = 10, FontWeight = FontWeights.Heavy, Foreground = PixelBox.Rim, Margin = new Thickness(9, 5, 9, 5) },
                Margin = new Thickness(0, 0, 6, 0), Cursor = Cursors.Hand, ToolTip = R.Tag(preset, i + 1),
            };
            chip.MouseLeftButtonUp += (_, e) => { e.Handled = true; c.ChoosePreset(n); };
            chips.Children.Add(chip);
        }
    }
}

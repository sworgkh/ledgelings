using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Ledgelings.Core;
using Ledgelings.Native;
using Clipboard = Ledgelings.Core.Clipboard;
using Rect = Ledgelings.Core.Rect;
using T = Ledgelings.Core.Translate;

namespace Ledgelings.UI;

/// <summary>
/// The Translate sheet (SPEC §7.14.1), the Mac's <c>TranslateSheet.swift</c>: the clipboard picker's pixel paper,
/// the text you type on the left and its translation on the right, live, the rest of the phrase guessed in grey.
/// A creature brings it and thinks (dots) while the model answers, shrugs (?) at trouble.
///
/// Keys, Windows' way round: Enter copies the translation, Ctrl+Enter pastes it into the app you were in,
/// Shift+Enter is a new line, Tab takes the guess, Ctrl+S swaps, Ctrl+1–4 the source (1 Detect), Alt+1–3 the
/// target, Ctrl+Shift+Backspace clears, Esc closes. Like the picker, the sheet takes the keyboard (Windows gives
/// it only to the active window) and puts the window you were in back in front before Ctrl+V is pressed for it.
/// A newer keystroke never cancels a call: the answer to old text is only dropped (AGENTS rule 1).
/// </summary>
public sealed class TranslateSheetController
{
    public const double SheetWidth = 760, SheetHeight = 470;

    public enum State { Idle, Waiting, Done, WaitingForEnter, Trouble, Refused }

    private readonly AppSettings settings;
    private readonly Translator translator;
    private readonly ClipBook book;
    private readonly Func<Colony?> colony;
    private TranslateSheetWindow? window;
    private IntPtr previous;
    private Win32.RECT? caret;
    private bool helped;
    /// <summary>Counts every change of the text or the languages: an answer for an older count is dropped.</summary>
    private int generation;
    private DispatcherTimer? wait;

    // What the sheet shows.
    public string Text { get; private set; } = "";
    public string Guess { get; private set; } = "";
    public string Result { get; private set; } = "";
    public T.Lang? ResultLanguage { get; private set; }
    public State Now { get; private set; } = State.Idle;
    public string Status { get; private set; } = "";
    public IReadOnlyList<T.Lang> Languages { get; private set; } = T.Languages;
    /// <summary>Picked by hand; null: detected.</summary>
    public T.Lang? SourceChoice { get; private set; }
    /// <summary>Picked by hand; null: the source's "goes into" rule.</summary>
    public T.Lang? TargetChoice { get; private set; }
    public T.Lang? Detected { get; private set; }
    public string? AppName { get; private set; }
    public bool CursorAtEnd { get; set; } = true;

    public T.Lang? Source => SourceChoice ?? Detected;
    public T.Lang Target => Source is { } source
        ? T.Target(source, settings.TranslateTargets, Languages, TargetChoice)
        : TargetChoice ?? Languages.FirstOrDefault() ?? T.English;

    public Action<string>? Trace { get; set; }

    public TranslateSheetController(AppSettings settings, Translator translator, ClipBook book, Func<Colony?> colony)
    {
        this.settings = settings;
        this.translator = translator;
        this.book = book;
        this.colony = colony;
    }

    public bool IsUp => window is not null;

    // MARK: Opening and closing

    /// <summary>Up, empty or holding <paramref name="text"/>, which is translated at once. Pressed again while up, it closes.</summary>
    public void Toggle(string? text = null)
    {
        if (IsUp && text is null) { Close(); return; }
        Show(text);
    }

    public void Show(string? text = null, T.Lang? into = null)
    {
        translator.Refresh();
        if (window is null)
        {
            previous = ClipboardNative.GetForegroundWindow();
            caret = previous == IntPtr.Zero ? null : ClipboardNative.Caret(previous);
            AppName = previous == IntPtr.Zero ? null : ClipboardNative.ProcessName(previous);
        }
        Languages = settings.TranslateLanguagesOn;
        SourceChoice = null;
        TargetChoice = into;
        Text = text ?? "";
        Result = Guess = Status = "";
        Now = State.Idle;
        if (window is not null) { window.SetText(Text); Edited(now: true); return; }
        var monitor = ClipPickerController.Screen(caret, previous);
        window = new TranslateSheetWindow(this, monitor);
        // Closed some other way (Alt+F4): the same clean-up as Esc.
        window.Closed += (s, _) => { if (ReferenceEquals(window, s)) { window = null; Gone(); } };
        window.SetText(Text);
        window.Show();
        window.Activate();
        Trace?.Invoke($"translate open on {monitor.Name}{(text is null ? "" : $", {text.Length} characters")}");
        var paper = window.PaperOnScreen();
        double? leap = settings.TranslateHelperEnabled
            ? colony()?.ClipHelperCome(new Rect(paper.Left, -(paper.Top + paper.Height), paper.Width, paper.Height),
                                       new Pt(monitor.Left + monitor.Width / 2.0, -(monitor.Top + monitor.Height / 2.0)), settings.TranslateHelper)
            : null;
        helped = leap is not null;
        if (!settings.ClipAnimate) window.Unfold(0, helped);
        else if (leap is double w) After(w, () => window?.Unfold(ClipHelper.UnfoldSeconds / settings.ClipAnimationSpeed, true));
        else window.Unfold(ClipHelper.UnfoldSeconds / settings.ClipAnimationSpeed, false);
        if (text is not null) Edited(now: true); else window.Redraw();
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

    /// <summary>The sheet is gone, however it went: no answer is waited for, the creature goes home.</summary>
    private void Gone()
    {
        generation++;
        wait?.Stop();
        if (helped) { colony()?.ClipHelperMoodTo(Colony.ClipHelperMood.Calm); colony()?.ClipHelperGoHome(); }
        helped = false;
        Trace?.Invoke("translate close");
    }

    private void Mood(Colony.ClipHelperMood mood) { if (helped) colony()?.ClipHelperMoodTo(mood); }

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
                Act(ctrl ? T.Button.Paste : T.Button.Copy);
                return true;
            case System.Windows.Input.Key.Tab:
                if (Guess.Length == 0) return !shift;      // no focus wandering off the box
                TakeGuess();
                return true;
            case System.Windows.Input.Key.S when ctrl && !alt: Act(T.Button.Swap); return true;
            case System.Windows.Input.Key.Back when ctrl && shift: Act(T.Button.Clear); return true;
            case >= System.Windows.Input.Key.D1 and <= System.Windows.Input.Key.D5:
                var n = key - System.Windows.Input.Key.D1;
                if (ctrl && !alt) { ChooseSource(n); return true; }
                if (alt && !ctrl) { ChooseTarget(n); return true; }
                return false;
            default: return false;
        }
    }

    /// <summary>Ctrl+1 Detect, Ctrl+2… each language on.</summary>
    internal void ChooseSource(int n)
    {
        if (n > Languages.Count) { System.Media.SystemSounds.Beep.Play(); return; }
        SourceChoice = n == 0 ? null : Languages[n - 1];
        Edited(now: true);
    }

    /// <summary>Alt+1… each language on.</summary>
    internal void ChooseTarget(int n)
    {
        if (n >= Languages.Count) { System.Media.SystemSounds.Beep.Play(); return; }
        TargetChoice = Languages[n];
        Edited(now: true);
    }

    internal void Act(T.Button button)
    {
        switch (button)
        {
            case T.Button.Copy:
                // Enter on a long text, or after trouble, translates; with a translation, it copies.
                if (Now is State.WaitingForEnter or State.Trouble) { TranslateNow(); return; }
                if (Result.Length == 0 || Now != State.Done) { System.Media.SystemSounds.Beep.Play(); return; }
                Deliver(paste: false);
                break;
            case T.Button.Paste:
                if (Result.Length == 0 || Now != State.Done) { System.Media.SystemSounds.Beep.Play(); return; }
                Deliver(paste: true);
                break;
            case T.Button.Swap: Swap(); break;
            case T.Button.Clear:
                Text = "";
                window?.SetText("");
                Edited(now: true);
                break;
        }
    }

    // MARK: Typing

    /// <summary>What the text box reports as you type: typing the guess's own next letters keeps the rest of it.</summary>
    internal void Typed(string typed, bool cursorAtEnd)
    {
        var old = Text;
        CursorAtEnd = cursorAtEnd;
        if (typed.Length > old.Length && typed.StartsWith(old, StringComparison.Ordinal) && cursorAtEnd)
        {
            var added = typed[old.Length..];
            Guess = Guess.StartsWith(added, StringComparison.Ordinal) ? Guess[added.Length..] : "";
        }
        else Guess = "";
        Text = typed;
        Edited();
    }

    /// <summary>The text changed (or a language did): the translation asked for after the wait.</summary>
    internal void Edited(bool now = false)
    {
        var mine = ++generation;
        wait?.Stop();
        var text = Text;
        Detected = T.Detect(T.Protect(text).Text, Languages);
        if (text.Trim().Length == 0)
        {
            Result = Status = "";
            Now = State.Idle;
            Mood(Colony.ClipHelperMood.Calm);
            window?.Redraw();
            return;
        }
        if (T.RefusalOf(text, book.Snippets) is { } refusal)
        {
            Result = "";
            Now = State.Refused;
            Status = refusal.Line();
            Mood(Colony.ClipHelperMood.Calm);
            window?.Redraw();
            return;
        }
        if (!translator.HasModel)
        {
            Now = State.Trouble;
            Status = new Translator.Trouble(Translator.TroubleKind.NoModel).Line;
            Mood(Colony.ClipHelperMood.Puzzled);
            window?.Redraw();
            return;
        }
        if (text.Length > settings.TranslateLiveLimit && !now)
        {
            var parts = T.Parts(text).Count;
            Now = State.WaitingForEnter;
            Status = settings.TranslateModel == T.DefaultModel
                ? L10n.Tr("%@ · about %@ · Enter translates", L10n.TrCount(parts, "part", "parts"),
                          Spend.Label(T.Estimate(text.Length, parts, 0.0000001, 0.0000004)))
                : L10n.Tr("%@ · Enter translates", L10n.TrCount(parts, "part", "parts"));
            Mood(Colony.ClipHelperMood.Calm);
            window?.Redraw();
            return;
        }
        // The translation on show is of the old text now: faded, and Enter will not copy it.
        Now = State.Waiting;
        window?.Redraw();
        var guessToo = settings.TranslateAutocomplete && CursorAtEnd && Source is { RightToLeft: false } && !text.EndsWith('\n') && text.Length < 2_000;
        void Go()
        {
            if (mine != generation) return;
            Watch(TranslateText(text, mine), mine);
            if (guessToo) Watch(GuessFor(text, mine), mine);
        }
        if (now) { Go(); return; }
        wait = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(settings.TranslateDelayMs) };
        wait.Tick += (_, _) => { wait?.Stop(); Go(); };
        wait.Start();
    }

    private void TranslateNow()
    {
        var mine = ++generation;
        Watch(TranslateText(Text, mine), mine);
    }

    /// <summary>A task that throws something unforeseen shows it as trouble, rather than leaving the dots up.</summary>
    private void Watch(Task task, int mine) => task.ContinueWith(t =>
    {
        var why = t.Exception?.GetBaseException().Message ?? "";
        Trace?.Invoke("translate failed: " + why);
        if (mine != generation || window is null) return;
        Now = State.Trouble;
        Status = new Translator.Trouble(Translator.TroubleKind.Network, why).Line;
        Mood(Colony.ClipHelperMood.Puzzled);
        window?.Redraw();
    }, CancellationToken.None, TaskContinuationOptions.OnlyOnFaulted, TaskScheduler.FromCurrentSynchronizationContext());

    private async Task TranslateText(string text, int mine)
    {
        if (Source is not { } source)
        {
            Now = State.Refused;
            Status = T.Refusal.NothingToTranslate.Line();
            window?.Redraw();
            return;
        }
        var target = Target;
        Now = State.Waiting;
        var culture = Ledgelings.Core.Languages.Current.Culture();
        Status = L10n.Tr("%@ → %@ · translating…", source.Title.ToUpper(culture), target.Title.ToUpper(culture));
        Mood(Colony.ClipHelperMood.Thinking);
        window?.Redraw();
        var (done, trouble) = await translator.Translate(text, source, target);
        if (mine != generation || Text != text || window is null) return;
        if (done is not null)
        {
            Result = done.Text;
            ResultLanguage = target;
            Now = State.Done;
            var status = T.Status(source, target, done.Seconds);
            if (SourceChoice is null && TargetChoice == source) status += " · " + L10n.Tr("already in %@", source.Title);
            if (done.MarkersLost) status += " · " + L10n.Tr("links may be changed");
            Status = status;
            Mood(Colony.ClipHelperMood.Calm);
            Trace?.Invoke($"translated {source.Code}→{target.Code}: {(done.Text.Length <= 80 ? done.Text : done.Text[..80])}");
        }
        else if (trouble is not null)
        {
            Now = State.Trouble;
            Status = trouble.Line;
            Mood(Colony.ClipHelperMood.Puzzled);
            Trace?.Invoke("translate trouble: " + trouble.Line);
        }
        window?.Redraw();
    }

    private async Task GuessFor(string text, int mine)
    {
        if (Source is not { } source) return;
        var guess = await translator.Guess(text, source);
        // Only for the text and cursor it was asked about.
        if (mine != generation || Text != text || !CursorAtEnd || guess.Length == 0) return;
        Guess = guess;
        window?.Redraw();
        Trace?.Invoke("guess: " + guess);
    }

    /// <summary>Tab: the grey words become typed ones.</summary>
    private void TakeGuess()
    {
        if (Guess.Length == 0) return;
        var taken = Guess;
        Guess = "";
        Text += taken;
        window?.SetText(Text);
        Trace?.Invoke("took the guess: " + taken);
        Edited();
    }

    /// <summary>The languages change places, and the translation becomes the text, to check it backwards.</summary>
    private void Swap()
    {
        if (Source is not { } source) { System.Media.SystemSounds.Beep.Play(); return; }
        var target = Target;
        var back = Now == State.Done ? Result : Text;
        SourceChoice = target;
        TargetChoice = source;
        Text = back;
        window?.SetText(back);
        Result = "";
        Trace?.Invoke($"swap: {target.Code}→{source.Code}");
        Edited(now: true);
    }

    // MARK: Delivering

    private void Deliver(bool paste)
    {
        var text = Result;
        // Marked as ours, so the watcher does not keep it a second time under another app's name.
        ClipPaster.Put(new ClipPaster.Item(text), plain: true);
        KeepInHistory(text, book, settings);
        var front = previous;
        var near = caret;
        Close(putBack: false);
        if (front != IntPtr.Zero && ClipboardNative.IsWindow(front)) Win32.SetForegroundWindow(front);
        if (!paste)
        {
            ClipToast.Show(L10n.Tr("Copied the translation"), near);
            Trace?.Invoke("copied the translation");
            return;
        }
        After(ClipPickerController.PasteDelay / 1000.0, () =>
        {
            ClipboardNative.PressPaste();
            Trace?.Invoke("pasted the translation into " + (AppName ?? "the app in front"));
        });
    }

    /// <summary>A translation copied or pasted goes into the clipboard history from "Translate", when the history is
    /// on and the setting says so; the watcher skips the app's own writes, so it is added here on purpose.</summary>
    public static void KeepInHistory(string text, ClipBook book, AppSettings settings)
    {
        if (!settings.TranslateKeepInHistory || !settings.ClipboardEnabled || !settings.ClipHistoryEnabled) return;
        book.Add(new Clipboard.Clip { Text = text, CopiedAt = DateTimeOffset.Now, App = L10n.Tr("Translate") }, settings.ClipHistoryLimit, settings.ClipKeepDays);
    }
}

/// <summary>The sheet's window: see-through over the whole monitor, so a click off the paper closes it, with the
/// paper in the middle.</summary>
internal sealed class TranslateSheetWindow : Window
{
    private static readonly Brush ink = Frozen(40, 34, 58), softInk = Frozen(92, 86, 120), faintInk = Frozen(150, 146, 170);
    private static readonly Color inkColour = Color.FromRgb(40, 34, 58);
    private static readonly FontFamily mono = new("Consolas");
    private const double FontSize15 = 15;

    private readonly TranslateSheetController controller;
    private readonly Monitor monitor;
    private readonly Grid paper = new() { Width = TranslateSheetController.SheetWidth, Height = TranslateSheetController.SheetHeight };
    private readonly ScaleTransform scale = new(1, 1);
    private readonly TextBox box = new();
    private readonly TextBlock guess = new(), hint = new(), result = new(), status = new(), dots = new();
    private readonly StackPanel chips = new() { Orientation = Orientation.Horizontal };
    private readonly StackPanel resultButtons = new() { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
    private readonly Canvas guessLayer = new() { IsHitTestVisible = false, ClipToBounds = true };
    private bool settingText;
    /// <summary>On its way out: closing it again would throw.</summary>
    public bool IsClosing { get; private set; }

    public TranslateSheetWindow(TranslateSheetController controller, Monitor monitor)
    {
        this.controller = controller;
        this.monitor = monitor;
        Title = L10n.Tr("Translate");
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
            Source = Bitmaps.ToSource(ScreenOverlay.PaperImage((int)(TranslateSheetController.SheetWidth / ReminderNote.Pixel), (int)(TranslateSheetController.SheetHeight / ReminderNote.Pixel))),
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
        int w = (int)Math.Round(TranslateSheetController.SheetWidth * dpi.DpiScaleX), h = (int)Math.Round(TranslateSheetController.SheetHeight * dpi.DpiScaleY);
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

    /// <summary>The paper as it looks now, for <c>--translate-sheet --snapshot</c>.</summary>
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
        var top = new TextBlock { Text = L10n.Tr("TRANSLATE"), FontFamily = mono, FontSize = 11, FontWeight = FontWeights.Bold, Foreground = faintInk, Margin = new Thickness(0, 0, 0, 8) };
        DockPanel.SetDock(top, Dock.Top);
        stack.Children.Add(top);
        chips.Margin = new Thickness(0, 0, 0, 8);
        DockPanel.SetDock(chips, Dock.Top);
        stack.Children.Add(chips);

        var footer = new TextBlock
        {
            Text = L10n.Tr("ENTER COPY  CTRL+ENTER PASTE  SHIFT+ENTER NEW LINE  TAB GUESS  CTRL+S SWAP  CTRL+1–4 FROM  ALT+1–3 INTO  ESC CLOSE"),
            FontFamily = mono, FontSize = 9, FontWeight = FontWeights.Heavy, Foreground = faintInk, Margin = new Thickness(0, 8, 60, 0),
            TextTrimming = TextTrimming.CharacterEllipsis,
        };
        DockPanel.SetDock(footer, Dock.Bottom);
        stack.Children.Add(footer);

        dots.Text = "•••"; dots.Foreground = softInk; dots.Margin = new Thickness(0, 0, 8, 0);
        status.TextWrapping = TextWrapping.Wrap; status.MaxHeight = 30;
        var line = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 8, 0, 0), Children = { dots, status } };
        foreach (var t in new[] { dots, status }) { t.FontFamily = mono; t.FontSize = 11; t.FontWeight = FontWeights.Heavy; }
        DockPanel.SetDock(line, Dock.Bottom);
        stack.Children.Add(line);

        // The left box: what you type, with the guess in grey after the last letter.
        box.FontFamily = mono; box.FontSize = FontSize15; box.FontWeight = FontWeights.SemiBold; box.Foreground = ink; box.CaretBrush = ink;
        box.Background = Brushes.Transparent; box.BorderThickness = new Thickness(0);
        box.AcceptsReturn = true; box.AcceptsTab = false; box.TextWrapping = TextWrapping.Wrap;
        box.VerticalScrollBarVisibility = ScrollBarVisibility.Hidden;
        box.TextChanged += (_, _) => { if (!settingText) controller.Typed(box.Text, box.CaretIndex == box.Text.Length); };
        box.SelectionChanged += (_, _) =>
        {
            var atEnd = box.CaretIndex == box.Text.Length && box.SelectionLength == 0;
            controller.CursorAtEnd = atEnd;
            PlaceGuess();
        };
        hint.Text = L10n.Tr("Type, or paste, in any language that is on.");
        hint.FontFamily = mono; hint.FontSize = FontSize15; hint.FontWeight = FontWeights.SemiBold; hint.Foreground = faintInk; hint.IsHitTestVisible = false; hint.TextWrapping = TextWrapping.Wrap;
        guess.FontFamily = mono; guess.FontSize = FontSize15; guess.FontWeight = FontWeights.SemiBold; guess.Foreground = faintInk;
        guessLayer.Children.Add(guess);
        var left = new PixelBox { Look = PixelBox.Finish.Well, Child = new Grid { Margin = new Thickness(10, 8, 10, 8), Children = { hint, box, guessLayer } } };

        // The right box: the translation, and its copy and paste pictures.
        result.FontFamily = mono; result.FontSize = FontSize15; result.FontWeight = FontWeights.SemiBold; result.TextWrapping = TextWrapping.Wrap;
        var words = new ScrollViewer { Content = result, VerticalScrollBarVisibility = ScrollBarVisibility.Hidden };
        DockPanel.SetDock(resultButtons, Dock.Bottom);
        var right = new PixelBox { Look = PixelBox.Finish.Raised, Child = new DockPanel { Margin = new Thickness(10, 8, 10, 8), Children = { resultButtons, words } } };

        var boxes = new Grid { Height = 300 };
        boxes.ColumnDefinitions.Add(new ColumnDefinition());
        boxes.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(14) });
        boxes.ColumnDefinitions.Add(new ColumnDefinition());
        Grid.SetColumn(right, 2);
        boxes.Children.Add(left);
        boxes.Children.Add(right);
        DockPanel.SetDock(boxes, Dock.Top);
        stack.Children.Add(boxes);
        stack.Children.Add(new Border());
        return stack;
    }

    /// <summary>Everything again from the controller.</summary>
    public void Redraw()
    {
        var c = controller;
        var culture = Ledgelings.Core.Languages.Current.Culture();
        chips.Children.Clear();
        chips.Children.Add(Chip(c.SourceChoice is null && c.Detected is { } d ? L10n.Tr("DETECT · %@", d.Title.ToUpper(culture)) : L10n.Tr("DETECT"),
                                c.SourceChoice is null, L10n.Tr("Tell the language by its letters (%@)", "Ctrl+1"), () => c.ChooseSource(0)));
        for (var i = 0; i < c.Languages.Count; i++)
        {
            var n = i + 1;
            var language = c.Languages[i];
            chips.Children.Add(Chip(language.Title.ToUpper(culture), c.SourceChoice == language, L10n.Tr("From %@ (%@)", language.Title, $"Ctrl+{n + 1}"), () => c.ChooseSource(n)));
        }
        chips.Children.Add(new Border { Width = 14 });
        chips.Children.Add(IconButton(T.Button.Swap, null, () => c.Act(T.Button.Swap)));
        chips.Children.Add(new Border { Width = 14 });
        var target = c.Target;
        for (var i = 0; i < c.Languages.Count; i++)
        {
            var n = i;
            var language = c.Languages[i];
            chips.Children.Add(Chip(language.Title.ToUpper(culture), target == language && c.Source is not null, L10n.Tr("Into %@ (%@)", language.Title, $"Alt+{n + 1}"), () => c.ChooseTarget(n)));
        }

        // Hebrew runs right to left, in the box and in the answer.
        box.FlowDirection = c.Source?.RightToLeft == true ? FlowDirection.RightToLeft : FlowDirection.LeftToRight;
        hint.Visibility = box.Text.Length == 0 ? Visibility.Visible : Visibility.Hidden;
        result.Text = c.Result.Length == 0 ? " " : c.Result;
        result.Foreground = c.Now == TranslateSheetController.State.Done ? ink : softInk;
        result.FlowDirection = c.ResultLanguage?.RightToLeft == true ? FlowDirection.RightToLeft : FlowDirection.LeftToRight;
        resultButtons.Children.Clear();
        resultButtons.Children.Add(IconButton(T.Button.Copy, null, () => c.Act(T.Button.Copy)));
        resultButtons.Children.Add(new Border { Width = 6 });
        resultButtons.Children.Add(IconButton(T.Button.Paste, c.AppName, () => c.Act(T.Button.Paste)));
        resultButtons.Opacity = c.Now == TranslateSheetController.State.Done ? 1 : 0.45;
        dots.Visibility = c.Now == TranslateSheetController.State.Waiting ? Visibility.Visible : Visibility.Collapsed;
        status.Text = c.Status.Length == 0 ? L10n.Tr("Type, or paste, in any language that is on.") : c.Status;
        status.Foreground = c.Now is TranslateSheetController.State.Trouble or TranslateSheetController.State.Refused ? PixelBox.Rim : softInk;
        guess.Text = c.Guess;
        PlaceGuess();
    }

    /// <summary>The guess straight after the last letter, as many of its words as fit on the line.</summary>
    private void PlaceGuess()
    {
        var shown = controller.Guess;
        if (shown.Length == 0 || box.Text.Length == 0 || box.Text.EndsWith('\n') || !controller.CursorAtEnd) { guess.Visibility = Visibility.Hidden; return; }
        box.UpdateLayout();
        var last = box.GetRectFromCharacterIndex(box.Text.Length - 1, trailingEdge: true);
        if (last.IsEmpty) { guess.Visibility = Visibility.Hidden; return; }
        var room = guessLayer.ActualWidth - last.Right;
        string Fit(string text)
        {
            while (text.Length > 0 && Measure(text) > room)
            {
                var words = text.TrimEnd();
                var space = words.LastIndexOf(' ');
                if (space <= 0) return "";
                text = words[..space];
            }
            return text;
        }
        guess.Text = Fit(shown);
        guess.Visibility = guess.Text.Length == 0 ? Visibility.Hidden : Visibility.Visible;
        Canvas.SetLeft(guess, last.Right);
        Canvas.SetTop(guess, last.Top);
    }

    private double Measure(string text)
    {
        var formatted = new FormattedText(text, System.Globalization.CultureInfo.CurrentCulture, FlowDirection.LeftToRight,
                                          new Typeface(mono, FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal), FontSize15, faintInk,
                                          VisualTreeHelper.GetDpi(this).PixelsPerDip);
        return formatted.WidthIncludingTrailingWhitespace;
    }

    private static FrameworkElement Chip(string title, bool chosen, string tip, Action click)
    {
        var chip = new PixelBox
        {
            Look = chosen ? PixelBox.Finish.Chosen : PixelBox.Finish.Raised,
            Child = new TextBlock { Text = title, FontFamily = mono, FontSize = 10, FontWeight = FontWeights.Heavy, Foreground = PixelBox.Rim, Margin = new Thickness(9, 5, 9, 5) },
            Margin = new Thickness(0, 0, 6, 0), Cursor = Cursors.Hand, ToolTip = tip,
        };
        chip.MouseLeftButtonUp += (_, e) => { e.Handled = true; click(); };
        return chip;
    }

    /// <summary>One of the translator's pixel buttons: its picture, and its name and key on hover (AGENTS rule 4).</summary>
    private static FrameworkElement IconButton(T.Button button, string? app, Action click)
    {
        var tip = button.Tooltip(app);
        var picture = PixelGlyph.Image(button.Icon(), inkColour, 2);
        var face = new PixelBox { Look = PixelBox.Finish.Raised, Child = new Border { Child = picture, Margin = new Thickness(6) }, Cursor = Cursors.Hand, ToolTip = tip };
        AutomationName(face, tip);
        face.MouseLeftButtonUp += (_, e) => { e.Handled = true; click(); };
        return face;
    }

    private static void AutomationName(DependencyObject d, string name) => System.Windows.Automation.AutomationProperties.SetName(d, name);
}

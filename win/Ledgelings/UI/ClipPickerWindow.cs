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

namespace Ledgelings.UI;

/// <summary>
/// The clipboard picker (SPEC §7.11), the Mac's <c>ClipPicker.swift</c>: a sheet of the letter's pixel paper with
/// one search field over the recent copies and the snippets at once, run from the keyboard. Type to filter,
/// ↑↓ to choose, Enter to paste (Alt+Enter the other way round: plain or formatted), Ctrl+1–9 for the first
/// nine, Tab to jump between the groups, Ctrl+P to pin, Delete (or Backspace with nothing typed) to forget a
/// copy, Ctrl+E to edit the snippets, Esc to close. The mouse works too.
///
/// Windows gives the keyboard only to the active window, so the picker is activated, and the window that was
/// in front is put back in front before Ctrl+V is pressed for it. A creature brings the sheet and holds its
/// top-left corner (<see cref="Colony.ClipHelperCome"/>); once something is chosen the window goes at once and
/// a picture of the sheet collapses into the text caret, or into the creature, in a window of its own: the
/// paste never waits for the animation.
/// </summary>
public sealed class ClipPickerController
{
    /// <summary>The sheet, in device-independent pixels.</summary>
    public const double SheetWidth = 600, SheetHeight = 484;
    /// <summary>Milliseconds between the window going and Ctrl+V: the app in front needs its keyboard back first.</summary>
    public const int PasteDelay = 40;
    /// <summary>Rows drawn at most; a longer history is narrowed by typing.</summary>
    public const int MostRows = 300;

    private readonly AppSettings settings;
    private readonly ClipBook book;
    private readonly Func<Colony?> colony;
    private readonly Action editSnippets;
    private readonly ClipPicker model;
    private ClipPickerWindow? window;
    private IntPtr previous;
    private Win32.RECT? caret;
    private bool helped;

    public Action<string>? Trace { get; set; }

    // The translator (SPEC §7.14): a row's words into another language, under it.
    private Func<string, Translate.Lang?, Task<(Translate.Lang? Target, string? Text, string? Trouble)>>? translateRow;
    private Action<string, Translate.Lang?>? openInSheet;
    private Func<bool> translateOn = () => false;
    private int translating;

    /// <summary>A row's translation, open under it: waiting (dots), done (its words), or the trouble.</summary>
    internal sealed record RowTranslation(Guid Id, Translate.Lang? Target, string? Words, string? Trouble);
    internal RowTranslation? Translation { get; private set; }
    /// <summary>Rows get a translate picture (Ctrl+T): the translator is on and so is its button.</summary>
    internal bool TranslateOn => translateRow is not null && translateOn();

    // Read aloud (SPEC §7.16): a row's words read out in the Read aloud sheet.
    private Action<string>? readRow;
    private Func<bool> readOn = () => false;

    /// <summary>Rows get a loudspeaker picture (Ctrl+R): Read aloud is on and so is its button.</summary>
    internal bool ReadOn => readRow is not null && readOn();

    /// <summary>Handed Read aloud once it is made.</summary>
    public void UseReader(Action<string> read, Func<bool> on)
    {
        readRow = read;
        readOn = on;
    }

    /// <summary>Handed the translator once it is made.</summary>
    public void UseTranslator(Func<string, Translate.Lang?, Task<(Translate.Lang? Target, string? Text, string? Trouble)>> row,
                              Action<string, Translate.Lang?> sheet, Func<bool> on)
    {
        translateRow = row;
        openInSheet = sheet;
        translateOn = on;
    }

    public ClipPickerController(AppSettings settings, ClipBook book, Func<Colony?> colony, Action editSnippets)
    {
        this.settings = settings;
        this.book = book;
        this.colony = colony;
        this.editSnippets = editSnippets;
        model = new ClipPicker(() => (book.History, book.Snippets));
    }

    public bool IsUp => window is not null;

    /// <summary>Up with <paramref name="first"/> on top; pressed again while up, it switches group, or closes when already there.</summary>
    public void Toggle(ClipPicker.Group first)
    {
        if (window is not null)
        {
            if (model.First == first) Close();
            else { model.First = first; model.Refresh(selectFirst: true); window.Redraw(); }
            return;
        }
        Show(first);
    }

    public void Show(ClipPicker.Group first)
    {
        previous = ClipboardNative.GetForegroundWindow();
        caret = previous == IntPtr.Zero ? null : ClipboardNative.Caret(previous);
        model.First = first;
        model.Search("");
        model.Refresh(selectFirst: true);
        Translation = null;
        var monitor = Screen(caret, previous);
        window = new ClipPickerWindow(this, model, settings, monitor);
        window.Closed += (s, _) => { if (ReferenceEquals(window, s)) window = null; };
        window.Show();
        window.Activate();
        Trace?.Invoke($"open {(first == ClipPicker.Group.Recent ? "history" : "snippets")} on {monitor.Name}, {model.Rows.Count} rows, caret {(caret is { } c ? $"at {c.Left},{c.Top}" : "unknown")}");
        // The keyboard is the sheet's at once; the creature's leap only delays how it looks.
        var paper = window.PaperOnScreen();
        double? wait = settings.ClipAnimate && settings.ClipHelperEnabled
            ? colony()?.ClipHelperCome(new Rect(paper.Left, -(paper.Top + paper.Height), paper.Width, paper.Height),
                                       new Pt(monitor.Left + monitor.Width / 2.0, -(monitor.Top + monitor.Height / 2.0)))
            : null;
        helped = wait is not null;
        if (!settings.ClipAnimate) window.Unfold(0, helped);
        else if (wait is double w)
        {
            var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(w) };
            timer.Tick += (_, _) => { timer.Stop(); window?.Unfold(ClipHelper.UnfoldSeconds / settings.ClipAnimationSpeed, true); };
            timer.Start();
        }
        else window.Unfold(ClipHelper.UnfoldSeconds / settings.ClipAnimationSpeed, false);
    }

    /// <summary>The monitor with the text caret, else with the front window, else with the pointer.</summary>
    internal static Monitor Screen(Win32.RECT? caret, IntPtr front)
    {
        var monitors = Desktop.Monitors();
        bool On(Monitor m, int x, int y) => x >= m.Left && x < m.Left + m.Width && y >= m.Top && y < m.Top + m.Height;
        if (caret is { } c && monitors.FirstOrDefault(m => On(m, c.Left, c.Top)) is { } byCaret) return byCaret;
        if (front != IntPtr.Zero && Win32Window.Bounds(front) is { } b && monitors.FirstOrDefault(m => On(m, (b.Left + b.Right) / 2, (b.Top + b.Bottom) / 2)) is { } byWindow)
            return byWindow;
        var cursor = Desktop.Cursor();
        return monitors.FirstOrDefault(m => m.Frame.Contains(cursor)) ?? Desktop.Primary(monitors)!;
    }

    // MARK: Keys

    /// <summary>Handles a key pressed on the picker; false lets it through to the search field.</summary>
    internal bool Key(Key key, ModifierKeys modifiers, bool fieldEmpty)
    {
        bool ctrl = modifiers.HasFlag(ModifierKeys.Control), alt = modifiers.HasFlag(ModifierKeys.Alt);
        switch (key)
        {
            // A translation open under a row closes first, the picker after.
            case System.Windows.Input.Key.Escape:
                if (Translation is not null) { Translation = null; translating++; break; }
                Close();
                return true;
            case System.Windows.Input.Key.T when ctrl && modifiers.HasFlag(ModifierKeys.Shift) && TranslateOn: OpenInSheet(); return true;
            case System.Windows.Input.Key.T when ctrl && TranslateOn: if (model.SelectedRow is { } t) ToggleTranslation(t); break;
            case System.Windows.Input.Key.Tab when ctrl && Translation is not null: NextTarget(); break;
            case System.Windows.Input.Key.R when ctrl && ReadOn: if (model.SelectedRow is { } toRead) Read(toRead); return true;
            case System.Windows.Input.Key.Down: model.Step(1); break;
            case System.Windows.Input.Key.Up: model.Step(-1); break;
            case System.Windows.Input.Key.PageDown: model.Step(8); break;
            case System.Windows.Input.Key.PageUp: model.Step(-8); break;
            case System.Windows.Input.Key.N when ctrl: model.Step(1); break;
            case System.Windows.Input.Key.P when ctrl: if (model.SelectedRow is { } p) Pin(p); break;
            case System.Windows.Input.Key.Enter:
                // With its translation open, Enter pastes the translation; Alt+Enter the original.
                if (model.SelectedRow is { } r && Translation is { } open && open.Id == r.Id && !alt)
                {
                    if (open.Words is string words) PasteTranslation(words, r); else System.Media.SystemSounds.Beep.Play();
                }
                else if (model.SelectedRow is { } row) Choose(row, alt && Translation?.Id != row.Id);
                return true;
            case System.Windows.Input.Key.Tab: model.JumpGroup(); break;
            case System.Windows.Input.Key.E when ctrl: Close(); editSnippets(); return true;
            case System.Windows.Input.Key.Delete when fieldEmpty:
            case System.Windows.Input.Key.Back when fieldEmpty || ctrl:
                if (model.SelectedRow is { } f) Forget(f);
                break;
            default:
                if (ctrl && key is >= System.Windows.Input.Key.D1 and <= System.Windows.Input.Key.D9 && model.Numbered(key - System.Windows.Input.Key.D0) is { } n)
                {
                    Choose(n, alt);
                    return true;
                }
                return false;
        }
        window?.Redraw();
        return true;
    }

    internal void Search(string query)
    {
        model.Search(query);
        window?.Redraw();
    }

    internal void Select(Guid id)
    {
        if (model.Selected == id) return;
        model.Selected = id;
        window?.Redraw(scroll: false);
    }

    private void Pin(ClipPicker.Row row)
    {
        if (row.Group != ClipPicker.Group.Recent) { System.Media.SystemSounds.Beep.Play(); return; }
        book.TogglePin(row.Id);
        model.Refresh();
        Trace?.Invoke("pin " + row.Text);
    }

    /// <summary>A copy is forgotten; a snippet is edited in Edit Snippets, never deleted from here by a stray key.</summary>
    private void Forget(ClipPicker.Row row)
    {
        if (row.Group != ClipPicker.Group.Recent) { System.Media.SystemSounds.Beep.Play(); return; }
        var at = model.Rows.ToList().FindIndex(r => r.Id == row.Id);
        book.Remove(row.Id);
        model.Refresh(keeping: at);
        Trace?.Invoke("forget " + row.Text);
    }

    // MARK: Translating a row

    /// <summary>The words a row would be translated from, or null when it may not be (a picture, a protected snippet or
    /// a copy of its words, nothing but links and numbers).</summary>
    internal string? Words(ClipPicker.Row row)
    {
        if (!TranslateOn) return null;
        if (row.Group == ClipPicker.Group.Recent)
            return book.History.Clips.FirstOrDefault(c => c.Id == row.Id) is { } clip && Translate.MayTranslate(clip, book.Snippets) ? clip.Text : null;
        return book.Snippets.Find(row.Id) is { } snippet && Translate.RefusalOf(snippet, book.Snippets) is null ? snippet.Text : null;
    }

    /// <summary>The words a row would be read from, or null when it may not be (a picture, a protected snippet or a copy
    /// of its words, nothing sayable).</summary>
    internal string? ReadWords(ClipPicker.Row row)
    {
        if (!ReadOn) return null;
        if (row.Group == ClipPicker.Group.Recent)
            return book.History.Clips.FirstOrDefault(c => c.Id == row.Id) is { } clip && ReadAloud.RefusalOf(clip, book.Snippets) is null ? clip.Text : null;
        return book.Snippets.Find(row.Id) is { } snippet && ReadAloud.RefusalOf(snippet, book.Snippets) is null ? snippet.Text : null;
    }

    /// <summary>Ctrl+R or the row's loudspeaker: the picker goes, the row's words are read aloud in the Read aloud sheet.</summary>
    internal void Read(ClipPicker.Row row)
    {
        if (ReadWords(row) is not { } words || readRow is null) { System.Media.SystemSounds.Beep.Play(); return; }
        Trace?.Invoke("read row " + (row.Text.Length <= 40 ? row.Text : row.Text[..40]));
        Close();
        readRow(words);
    }

    /// <summary>Ctrl+T or the row's picture: its translation opens under it, or closes.</summary>
    internal void ToggleTranslation(ClipPicker.Row row)
    {
        if (Translation?.Id == row.Id) { Translation = null; translating++; window?.Redraw(scroll: false); return; }
        model.Selected = row.Id;
        TranslateSelected(null);
    }

    /// <summary>Ctrl+Tab: the same row into the next language that is on.</summary>
    private void NextTarget()
    {
        if (Translation is { } t && model.Selected == t.Id) TranslateSelected(t.Target);
    }

    private void TranslateSelected(Translate.Lang? after)
    {
        if (model.SelectedRow is not { } row || Words(row) is not { } words || translateRow is null) { System.Media.SystemSounds.Beep.Play(); return; }
        var mine = ++translating;
        Translation = new RowTranslation(row.Id, after, null, null);
        Trace?.Invoke("translate row " + (row.Text.Length <= 40 ? row.Text : row.Text[..40]));
        window?.Redraw(scroll: false);
        _ = Run();
        async Task Run()
        {
            var (target, text, trouble) = await translateRow(words, after);
            if (mine != translating || Translation?.Id != row.Id) return;
            Translation = new RowTranslation(row.Id, target, text, text is null ? trouble ?? Translate.Refusal.NothingToTranslate.Line() : null);
            if (text is not null) Trace?.Invoke($"row translated into {target?.Code ?? "?"}: {(text.Length <= 60 ? text : text[..60])}");
            window?.Redraw(scroll: false);
        }
    }

    /// <summary>Ctrl+Shift+T: the row's words in the Translate sheet; the picker goes.</summary>
    internal void OpenInSheet()
    {
        if (model.SelectedRow is not { } row || Words(row) is not { } words || openInSheet is null) { System.Media.SystemSounds.Beep.Play(); return; }
        var into = Translation?.Id == row.Id ? Translation.Target : null;
        Close();
        openInSheet(words, into);
    }

    /// <summary>The translation pasted as plain text into the app that was in front, and kept in the history.</summary>
    private void PasteTranslation(string words, ClipPicker.Row row)
    {
        Paste(new ClipPaster.Item(words), plain: true, row);
        TranslateSheetController.KeepInHistory(words, book, settings);
    }

    // MARK: Choosing

    /// <summary>Pastes <paramref name="row"/>: written to the clipboard, the window gone, the app that was in front put back
    /// in front and Ctrl+V pressed for it. <paramref name="otherWay"/> swaps plain text and formatting for this once.
    /// A protected snippet is pasted like any other here: Windows has no fingerprint guard (SPEC §7.11).</summary>
    internal void Choose(ClipPicker.Row row, bool otherWay = false)
    {
        var plain = settings.ClipPlainText != otherWay;
        if (row.Group == ClipPicker.Group.Recent)
        {
            if (book.History.Clips.FirstOrDefault(c => c.Id == row.Id) is not { } clip) return;
            var images = clip.Kind == Clipboard.Kind.Image ? book.ImageData(clip) : null;
            if (images is { Count: 0 })
            {
                // Its files went missing: nothing to paste, so the copy goes too.
                Trace?.Invoke(clip.Text + ": its picture is gone");
                System.Media.SystemSounds.Beep.Play();
                Forget(row);
                return;
            }
            Paste(new ClipPaster.Item(clip.Text, clip.Rtf, clip.Paths, Images: images), plain, row);
            book.Bump(clip.Id);
            return;
        }
        if (book.Snippets.Find(row.Id) is not { } snippet) return;
        Paste(new ClipPaster.Item(book.Words(snippet), Secret: snippet.Protected), plain: true, row);
    }

    /// <summary>A recent copy's thumbnail, when it is a picture.</summary>
    internal BitmapSource? Thumbnail(Guid id) =>
        book.History.Clips.FirstOrDefault(c => c.Id == id) is { Kind: Clipboard.Kind.Image } clip ? book.Thumbnail(clip) : null;

    /// <summary>Pastes a snippet straight from its own shortcut, with no picker.</summary>
    public void PasteNow(Clipboard.Snippet snippet)
    {
        previous = ClipboardNative.GetForegroundWindow();
        caret = previous == IntPtr.Zero ? null : ClipboardNative.Caret(previous);
        Choose(new ClipPicker.Row(snippet.Id, ClipPicker.Group.Snippets, snippet.Preview(), "", snippet.Title, false, snippet.Protected));
    }

    private void Paste(ClipPaster.Item item, bool plain, ClipPicker.Row row)
    {
        var before = item.Secret ? ClipPaster.Saved() : null;
        ClipPaster.Put(item, plain);
        var started = DateTime.Now;
        Collapse(toCaret: true);
        var name = row.Title ?? row.Text;
        if (!settings.ClipAutoPaste)
        {
            Trace?.Invoke("copied " + name);
            ClipToast.Show(L10n.Tr("Copied. Press Ctrl+V to paste."), caret);
            return;
        }
        if (previous != IntPtr.Zero && ClipboardNative.IsWindow(previous)) Win32.SetForegroundWindow(previous);
        After(PasteDelay / 1000.0, () =>
        {
            ClipboardNative.PressPaste();
            Trace?.Invoke($"paste {name} after {(DateTime.Now - started).TotalMilliseconds:F0} ms{(item.Secret ? ", concealed" : "")}");
            // The secret leaves the clipboard again, and what was there before comes back.
            if (item.Secret) After(1, () => { ClipPaster.Restore(before); Trace?.Invoke("clipboard put back"); });
        });
    }

    private static void After(double seconds, Action action)
    {
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(seconds) };
        timer.Tick += (_, _) => { timer.Stop(); action(); };
        timer.Start();
    }

    /// <summary>Closes with nothing pasted: the sheet folds back into the creature (or the middle) and is gone.</summary>
    public void Close()
    {
        if (window is null) return;
        Trace?.Invoke("close");
        Collapse(toCaret: false);
        if (previous != IntPtr.Zero && ClipboardNative.IsWindow(previous)) Win32.SetForegroundWindow(previous);
    }

    /// <summary>The window goes now; a picture of the paper shrinks into the caret, else the creature's corner, else the middle.</summary>
    private void Collapse(bool toCaret)
    {
        if (window is not { } w) return;
        var paper = w.PaperOnScreen();
        var picture = settings.ClipAnimate ? w.Picture() : null;
        window = null;
        w.Close();
        var seconds = ClipHelper.CollapseSeconds / settings.ClipAnimationSpeed;
        if (helped) After(picture is null ? 0 : seconds, () => colony()?.ClipHelperGoHome());
        System.Drawing.Point? to = toCaret && caret is { } c ? new(c.Left, (c.Top + c.Bottom) / 2)
            : helped ? new(paper.Left, paper.Top) : null;
        helped = false;
        if (picture is null) return;
        ClipGhost.Fly(picture, paper, to, seconds);
        Trace?.Invoke(to is { } p ? $"collapse into {(toCaret && caret is not null ? "the caret" : "the creature's corner")} at {p.X},{p.Y}" : "collapse to the middle");
    }
}

/// <summary>A window's bounds in screen pixels.</summary>
internal static class Win32Window
{
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hwnd, out Win32.RECT rect);

    public static Win32.RECT? Bounds(IntPtr hwnd) => GetWindowRect(hwnd, out var r) ? r : null;
}

/// <summary>The picker's window: see-through over the whole monitor, so a click off the paper closes it, with the paper
/// in the middle.</summary>
internal sealed class ClipPickerWindow : Window
{
    private static readonly Brush ink = Frozen(40, 34, 58), softInk = Frozen(92, 86, 120), faintInk = Frozen(150, 146, 170);
    private static readonly FontFamily mono = new("Consolas");
    /// <summary>A copy holding a protected snippet's words: the soft ink, faint on the paper, as on the Mac.</summary>
    private static readonly Brush maskTint = MaskTint();
    private static Brush MaskTint() { var b = new SolidColorBrush(Color.FromArgb(31, 92, 86, 120)); b.Freeze(); return b; }
    private const double RowHeight = 36;

    private readonly ClipPickerController controller;
    private readonly ClipPicker model;
    private readonly AppSettings settings;
    private readonly Monitor monitor;
    private readonly Grid paper = new() { Width = ClipPickerController.SheetWidth, Height = ClipPickerController.SheetHeight };
    private readonly ScaleTransform scale = new(1, 1);
    private readonly TextBox field = new();
    private readonly TextBlock hint = new(), counts = new(), footer = new();
    private readonly StackPanel rows = new();
    private readonly ScrollViewer scroller = new() { VerticalScrollBarVisibility = ScrollBarVisibility.Hidden };
    private readonly Dictionary<Guid, FrameworkElement> lines = new();

    public ClipPickerWindow(ClipPickerController controller, ClipPicker model, AppSettings settings, Monitor monitor)
    {
        this.controller = controller;
        this.model = model;
        this.settings = settings;
        this.monitor = monitor;
        Title = L10n.Tr("Clipboard");
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        // Nearly clear, so a click anywhere off the paper reaches the window and closes it.
        Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0));
        ResizeMode = ResizeMode.NoResize;
        Topmost = true;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.Manual;
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;
        RenderOptions.SetEdgeMode(paper, EdgeMode.Aliased);
        paper.HorizontalAlignment = HorizontalAlignment.Center;
        paper.VerticalAlignment = VerticalAlignment.Center;
        paper.RenderTransform = scale;
        paper.Opacity = 0;
        paper.MouseLeftButtonDown += (_, e) => e.Handled = true;
        var image = new Image
        {
            Source = Bitmaps.ToSource(ScreenOverlay.PaperImage((int)(ClipPickerController.SheetWidth / ReminderNote.Pixel), (int)(ClipPickerController.SheetHeight / ReminderNote.Pixel))),
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
            if (controller.Key(key, Keyboard.Modifiers, field.Text.Length == 0)) e.Handled = true;
        };
        SourceInitialized += (_, _) => Cover();
        Loaded += (_, _) => { field.Focus(); Redraw(); };
        Deactivated += (_, _) => { if (IsVisible) controller.Close(); };
    }

    private static SolidColorBrush Frozen(byte r, byte g, byte b)
    {
        var brush = new SolidColorBrush(Color.FromRgb(r, g, b));
        brush.Freeze();
        return brush;
    }

    /// <summary>Over the whole monitor, in its pixels.</summary>
    private void Cover()
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        Win32.SetWindowPos(hwnd, IntPtr.Zero, monitor.Left, monitor.Top, monitor.Width, monitor.Height, Win32.SWP_NOACTIVATE | 0x0004 /* SWP_NOZORDER */);
    }

    /// <summary>The paper's bounds in screen pixels.</summary>
    public System.Drawing.Rectangle PaperOnScreen()
    {
        UpdateLayout();
        var dpi = VisualTreeHelper.GetDpi(this);
        int w = (int)Math.Round(ClipPickerController.SheetWidth * dpi.DpiScaleX), h = (int)Math.Round(ClipPickerController.SheetHeight * dpi.DpiScaleY);
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

    /// <summary>The paper as it looks now, at the screen's pixels.</summary>
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
        var stack = new DockPanel { Margin = new Thickness(27, 24, 27, 20), LastChildFill = true };
        var top = new DockPanel { Margin = new Thickness(0, 0, 0, 8) };
        counts.FontFamily = mono; counts.FontSize = 10; counts.FontWeight = FontWeights.Bold; counts.Foreground = faintInk;
        DockPanel.SetDock(counts, Dock.Right);
        top.Children.Add(counts);
        top.Children.Add(new TextBlock { Text = L10n.Tr("CLIPBOARD"), FontFamily = mono, FontSize = 11, FontWeight = FontWeights.Bold, Foreground = faintInk });
        DockPanel.SetDock(top, Dock.Top);
        stack.Children.Add(top);

        field.FontFamily = mono; field.FontSize = 18; field.FontWeight = FontWeights.Heavy; field.Foreground = ink;
        field.Background = Brushes.Transparent; field.BorderThickness = new Thickness(0); field.CaretBrush = ink;
        field.TextChanged += (_, _) => { hint.Visibility = field.Text.Length == 0 ? Visibility.Visible : Visibility.Hidden; controller.Search(field.Text); };
        hint.Text = L10n.Tr("search copies and snippets…");
        hint.FontFamily = mono; hint.FontSize = 18; hint.FontWeight = FontWeights.Heavy; hint.Foreground = faintInk; hint.IsHitTestVisible = false;
        var well = new PixelBox { Look = PixelBox.Finish.Well, Child = new Grid { Margin = new Thickness(12, 9, 12, 9), Children = { hint, field } }, Margin = new Thickness(0, 0, 0, 10) };
        DockPanel.SetDock(well, Dock.Top);
        stack.Children.Add(well);

        footer.FontFamily = mono; footer.FontSize = 9; footer.FontWeight = FontWeights.Heavy; footer.Foreground = faintInk;
        footer.Margin = new Thickness(0, 8, 60, 0);   // clear of the paper's folded-down corner
        footer.TextTrimming = TextTrimming.CharacterEllipsis;
        var other = settings.ClipPlainText ? L10n.Tr("FORMATTED") : L10n.Tr("PLAIN");
        footer.Text = (controller.TranslateOn, controller.ReadOn) switch
        {
            (true, true) => L10n.Tr("ENTER PASTE  ALT+ENTER %@  CTRL+1–9 PICK  TAB GROUP  CTRL+T TRANSLATE  CTRL+R READ  CTRL+P PIN  DEL FORGET  CTRL+E EDIT  ESC CLOSE", other),
            (true, false) => L10n.Tr("ENTER PASTE  ALT+ENTER %@  CTRL+1–9 PICK  TAB GROUP  CTRL+T TRANSLATE  CTRL+P PIN  DEL FORGET  CTRL+E EDIT  ESC CLOSE", other),
            (false, true) => L10n.Tr("ENTER PASTE  ALT+ENTER %@  CTRL+1–9 PICK  TAB GROUP  CTRL+R READ  CTRL+P PIN  DEL FORGET  CTRL+E EDIT  ESC CLOSE", other),
            _ => L10n.Tr("ENTER PASTE  ALT+ENTER %@  CTRL+1–9 PICK  TAB GROUP  CTRL+P PIN  DEL FORGET  CTRL+E EDIT  ESC CLOSE", other),
        };
        DockPanel.SetDock(footer, Dock.Bottom);
        stack.Children.Add(footer);

        scroller.Content = rows;
        stack.Children.Add(scroller);
        return stack;
    }

    /// <summary>The rows again from the model; <paramref name="scroll"/> brings the chosen one into view.</summary>
    public void Redraw(bool scroll = true)
    {
        counts.Text = L10n.Tr("%d RECENT · %d SNIPPETS", model.Counts.Recent, model.Counts.Snippets);
        rows.Children.Clear();
        lines.Clear();
        if (model.Rows.Count == 0)
            rows.Children.Add(new TextBlock
            {
                Text = model.Query.Length == 0 ? L10n.Tr("Nothing yet: copy something, or add a snippet (Ctrl+E).") : L10n.Tr("Nothing matches."),
                FontFamily = mono, FontSize = 12, FontWeight = FontWeights.SemiBold, Foreground = softInk,
                HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 20, 0, 0),
            });
        var shown = model.Rows.Take(ClipPickerController.MostRows).ToList();
        for (var i = 0; i < shown.Count; i++)
        {
            var row = shown[i];
            if (i == 0 || shown[i - 1].Group != row.Group)
                rows.Children.Add(new TextBlock
                {
                    Text = row.Group == ClipPicker.Group.Recent ? L10n.Tr("RECENT") : L10n.Tr("SNIPPETS"),
                    FontFamily = mono, FontSize = 10, FontWeight = FontWeights.Heavy, Foreground = softInk, Margin = new Thickness(0, 6, 0, 2),
                });
            var line = Line(row, i < 9 ? i + 1 : null);
            lines[row.Id] = line;
            rows.Children.Add(line);
            if (controller.Translation is { } t && t.Id == row.Id) rows.Children.Add(Translation(t));
        }
        if (model.Rows.Count > shown.Count)
            rows.Children.Add(new TextBlock { Text = L10n.Tr("%d more: type to narrow", model.Rows.Count - shown.Count), FontFamily = mono, FontSize = 10, Foreground = faintInk });
        if (scroll && model.Selected is Guid id && lines.TryGetValue(id, out var chosen)) chosen.BringIntoView();
    }

    private FrameworkElement Line(ClipPicker.Row row, int? number)
    {
        var chosen = row.Id == model.Selected;
        var panel = new DockPanel { Height = RowHeight, Margin = new Thickness(9, 0, 9, 0), LastChildFill = true };
        TextBlock Text(string text, double size, FontWeight weight, Brush brush) =>
            new() { Text = text, FontFamily = mono, FontSize = size, FontWeight = weight, Foreground = brush, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis };
        var num = Text(number?.ToString() ?? " ", 10, FontWeights.Heavy, chosen ? PixelBox.Rim : faintInk);
        num.Width = 20;
        DockPanel.SetDock(num, Dock.Left);
        panel.Children.Add(num);
        if (controller.Words(row) is not null)
        {
            // The translate picture: on hover its name and key; a click opens the translation under the row.
            var tip = Translate.Button.Translate.Tooltip();
            var picture = PixelGlyph.Image(Translate.Button.Translate.Icon(), Color.FromRgb(40, 34, 58), 1.5);
            picture.Opacity = chosen ? 1 : 0.55;
            var button = new Border { Child = picture, Margin = new Thickness(8, 0, 0, 0), Padding = new Thickness(3), Background = Brushes.Transparent, Cursor = Cursors.Hand, ToolTip = tip, VerticalAlignment = VerticalAlignment.Center };
            System.Windows.Automation.AutomationProperties.SetName(button, tip);
            button.MouseLeftButtonUp += (_, e) => { e.Handled = true; controller.ToggleTranslation(row); };
            DockPanel.SetDock(button, Dock.Right);
            panel.Children.Add(button);
        }
        if (controller.ReadWords(row) is not null)
        {
            // The loudspeaker: on hover its name and key; a click reads the row aloud in the Read aloud sheet.
            var tip = ReadAloud.Button.ReadRow.Tooltip();
            var picture = PixelGlyph.Image(ReadAloud.Button.ReadRow.Icon(), Color.FromRgb(40, 34, 58), 1.5);
            picture.Opacity = chosen ? 1 : 0.55;
            var button = new Border { Child = picture, Margin = new Thickness(8, 0, 0, 0), Padding = new Thickness(3), Background = Brushes.Transparent, Cursor = Cursors.Hand, ToolTip = tip, VerticalAlignment = VerticalAlignment.Center };
            System.Windows.Automation.AutomationProperties.SetName(button, tip);
            button.MouseLeftButtonUp += (_, e) => { e.Handled = true; controller.Read(row); };
            DockPanel.SetDock(button, Dock.Right);
            panel.Children.Add(button);
        }
        var detail = Text(row.Protected ? L10n.Tr("LOCKED · %@", row.Detail) : row.Detail, 10, FontWeights.SemiBold, chosen ? PixelBox.Rim : faintInk);
        detail.Margin = new Thickness(8, 0, 0, 0);
        DockPanel.SetDock(detail, Dock.Right);
        panel.Children.Add(detail);
        var words = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        if (row.Group == ClipPicker.Group.Recent && controller.Thumbnail(row.Id) is { } thumbnail) words.Children.Add(Picture(thumbnail));
        if (row.Pinned) words.Children.Add(Text("▲ ", 9, FontWeights.Heavy, PixelBox.Rim));
        if (row.Title is string title) words.Children.Add(Text(title + "  ", 12, FontWeights.Heavy, PixelBox.Rim));
        words.Children.Add(Text(row.Text, 12, row.Title is null ? FontWeights.SemiBold : FontWeights.Normal, row.Title is null && !row.Masked ? PixelBox.Rim : softInk));
        panel.Children.Add(words);
        // Unchosen rows are bare paper: only the chosen one is a box. The panel gets one parent only:
        // WPF throws if it is handed to a second before the first lets go.
        if (!chosen)
            return Hook(new Border { Child = panel, Margin = new Thickness(0, 1, 6, 1), Background = row.Masked ? maskTint : Brushes.Transparent }, row);
        return Hook(new PixelBox { Look = PixelBox.Finish.Chosen, Child = panel, Margin = new Thickness(0, 1, 6, 1) }, row);
    }

    /// <summary>A row's translation, under it: where it went, the words (or dots, or the trouble), and the sheet.</summary>
    private FrameworkElement Translation(ClipPickerController.RowTranslation t)
    {
        var culture = Languages.Current.Culture();
        var head = new DockPanel();
        var tip = Translate.Button.OpenSheet.Tooltip();
        var sheet = new Border
        {
            Child = PixelGlyph.Image(Translate.Button.OpenSheet.Icon(), Color.FromRgb(40, 34, 58), 1.5),
            Background = Brushes.Transparent, Cursor = Cursors.Hand, ToolTip = tip, Padding = new Thickness(3),
        };
        System.Windows.Automation.AutomationProperties.SetName(sheet, tip);
        sheet.MouseLeftButtonUp += (_, e) => { e.Handled = true; controller.OpenInSheet(); };
        DockPanel.SetDock(sheet, Dock.Right);
        head.Children.Add(sheet);
        head.Children.Add(new TextBlock
        {
            Text = t.Target is { } into ? L10n.Tr("INTO %@ · CTRL+TAB NEXT · ENTER PASTES IT", into.Title.ToUpper(culture)) : L10n.Tr("TRANSLATING…"),
            FontFamily = mono, FontSize = 9, FontWeight = FontWeights.Heavy, Foreground = faintInk, VerticalAlignment = VerticalAlignment.Center,
        });
        var words = new TextBlock
        {
            Text = t.Words ?? t.Trouble ?? "•••",
            FontFamily = mono, FontSize = 12, FontWeight = FontWeights.SemiBold, Foreground = t.Words is null ? softInk : PixelBox.Rim,
            TextWrapping = TextWrapping.Wrap, MaxHeight = 64, Margin = new Thickness(0, 4, 0, 0),
            FlowDirection = t.Target?.RightToLeft == true && t.Words is not null ? FlowDirection.RightToLeft : FlowDirection.LeftToRight,
        };
        return new Border { Child = new StackPanel { Children = { head, words } }, Padding = new Thickness(30, 6, 12, 6), Margin = new Thickness(0, 0, 6, 2), Background = maskTint };
    }

    /// <summary>A picture's thumbnail, its few pixels drawn big, square and sharp, in a 1-pixel rim like the creatures'.</summary>
    private static FrameworkElement Picture(BitmapSource thumbnail)
    {
        const double boxWidth = 40, boxHeight = RowHeight - 10;
        var scale = Math.Min(boxWidth / Math.Max(thumbnail.PixelWidth, 1), boxHeight / Math.Max(thumbnail.PixelHeight, 1));
        var image = new Image
        {
            Source = thumbnail, Stretch = Stretch.Fill,
            Width = Math.Round(thumbnail.PixelWidth * scale), Height = Math.Round(thumbnail.PixelHeight * scale),
        };
        RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.NearestNeighbor);
        var rim = new Border { Child = image, BorderBrush = PixelBox.Rim, BorderThickness = new Thickness(1),
                              HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center };
        return new Border { Child = rim, Width = boxWidth + 2, Margin = new Thickness(0, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center };
    }

    private FrameworkElement Hook(FrameworkElement element, ClipPicker.Row row)
    {
        element.Cursor = Cursors.Hand;
        element.MouseEnter += (_, _) => controller.Select(row.Id);
        element.MouseLeftButtonUp += (_, e) => { e.Handled = true; controller.Choose(row, Keyboard.Modifiers.HasFlag(ModifierKeys.Alt)); };
        return element;
    }
}

/// <summary>A picture of the paper flying into a point and fading, in a window that never takes the keyboard.</summary>
internal static class ClipGhost
{
    public static void Fly(BitmapSource picture, System.Drawing.Rectangle from, System.Drawing.Point? to, double seconds)
    {
        var image = new Image { Source = picture, Stretch = Stretch.Fill };
        RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.NearestNeighbor);
        var window = new Window
        {
            WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = Brushes.Transparent, Topmost = true,
            ShowInTaskbar = false, ShowActivated = false, IsHitTestVisible = false, ResizeMode = ResizeMode.NoResize,
            WindowStartupLocation = WindowStartupLocation.Manual, Content = image,
        };
        var end = to ?? new System.Drawing.Point(from.Left + from.Width / 2, from.Top + from.Height / 2);
        var started = DateTime.Now;
        IntPtr hwnd = IntPtr.Zero;
        void Place(double share)
        {
            var e = share * share;
            int w = Math.Max(12, (int)(from.Width * (1 - e))), h = Math.Max(9, (int)(from.Height * (1 - e)));
            int x = (int)(from.Left + (end.X - from.Left) * e), y = (int)(from.Top + (end.Y - from.Top) * e);
            Win32.SetWindowPos(hwnd, IntPtr.Zero, x, y, w, h, Win32.SWP_NOACTIVATE | 0x0004 /* SWP_NOZORDER */);
            window.Opacity = 1 - 0.8 * e;
        }
        window.SourceInitialized += (_, _) => { hwnd = new WindowInteropHelper(window).Handle; Place(0); };
        window.Show();
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(15) };
        timer.Tick += (_, _) =>
        {
            var share = Math.Min((DateTime.Now - started).TotalSeconds / Math.Max(seconds, 0.01), 1);
            Place(share);
            if (share >= 1) { timer.Stop(); window.Close(); }
        };
        timer.Start();
    }
}

/// <summary>A one-line note on the paper's pixel box near the caret, gone in two seconds.</summary>
internal static class ClipToast
{
    private static Window? open;

    public static void Show(string text, Win32.RECT? caret)
    {
        open?.Close();
        var label = new PixelBox
        {
            Look = PixelBox.Finish.Raised,
            Child = new TextBlock { Text = text, FontFamily = new FontFamily("Consolas"), FontSize = 13, FontWeight = FontWeights.Heavy, Foreground = PixelBox.Rim, Margin = new Thickness(14, 10, 14, 10) },
        };
        var window = new Window
        {
            WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = Brushes.Transparent, Topmost = true, ShowInTaskbar = false,
            ShowActivated = false, IsHitTestVisible = false, SizeToContent = SizeToContent.WidthAndHeight, Content = label,
            WindowStartupLocation = caret is null ? WindowStartupLocation.CenterScreen : WindowStartupLocation.Manual,
        };
        if (caret is { } c)
            window.SourceInitialized += (_, _) =>
                Win32.SetWindowPos(new WindowInteropHelper(window).Handle, IntPtr.Zero, c.Left, c.Bottom + 6, 0, 0, Win32.SWP_NOSIZE | Win32.SWP_NOACTIVATE | 0x0004);
        window.Show();
        open = window;
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        timer.Tick += (_, _) => { timer.Stop(); window.Close(); if (ReferenceEquals(open, window)) open = null; };
        timer.Start();
    }
}

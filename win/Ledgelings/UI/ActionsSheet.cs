using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>The colony as the tiles see it.</summary>
public sealed record ActionsState(
    bool IsNight = false, bool NightOff = false, int PhaseLeft = 0,
    bool TeaEnabled = true, bool TeaOn = false, bool PlaneInAir = false,
    int Planted = 0, bool Hiding = false, int HideLeft = 0);

/// <summary>One tile on the sheet, in the order they are laid out, four to a row.</summary>
public enum ActionsTile { Jump, Talk, Tea, Plane, Reminder, Hide, Sleep, Flowers }

/// <summary>What each tile says and whether it can be pressed, as the Mac's sheet has it (SPEC §11).</summary>
public static class ActionsTiles
{
    public static readonly IReadOnlyList<ActionsTile> All = Enum.GetValues<ActionsTile>();

    /// <summary>The key that presses it while the sheet is up.</summary>
    public static Key Key(this ActionsTile tile) => tile switch
    {
        ActionsTile.Jump => System.Windows.Input.Key.J,
        ActionsTile.Talk => System.Windows.Input.Key.T,
        ActionsTile.Tea => System.Windows.Input.Key.E,
        ActionsTile.Plane => System.Windows.Input.Key.P,
        ActionsTile.Reminder => System.Windows.Input.Key.R,
        ActionsTile.Hide => System.Windows.Input.Key.H,
        ActionsTile.Sleep => System.Windows.Input.Key.S,
        _ => System.Windows.Input.Key.F,
    };

    public static string Title(this ActionsTile tile, ActionsState s) => tile switch
    {
        ActionsTile.Jump => L10n.Tr("MAKE THEM JUMP"),
        ActionsTile.Talk => L10n.Tr("MAKE SOMEONE TALK"),
        ActionsTile.Tea => s.TeaOn ? L10n.Tr("TEA PARTY ON") : L10n.Tr("HAVE A TEA PARTY"),
        ActionsTile.Plane => L10n.Tr("SEND A PAPER PLANE"),
        ActionsTile.Reminder => L10n.Tr("ADD A REMINDER"),
        ActionsTile.Hide => s.Hiding ? L10n.Tr("BRING THEM BACK") : L10n.Tr("HIDE THEM FOR A WHILE"),
        ActionsTile.Sleep => s.IsNight && !s.NightOff ? L10n.Tr("WAKE THEM UP") : L10n.Tr("PUT THEM TO SLEEP"),
        _ => s.Planted switch { 0 => L10n.Tr("CLEAR FLOWERS"), 1 => L10n.Tr("CLEAR THE FLOWER"), var n => L10n.TrCount(n, "CLEAR %d FLOWER", "CLEAR %d FLOWERS") },
    };

    /// <summary>A small line under the title: why it is greyed out, or a clock.</summary>
    public static string? Detail(this ActionsTile tile, ActionsState s)
    {
        var hiding = s.Hiding ? L10n.Tr("they are hiding") : null;
        return tile switch
        {
            ActionsTile.Jump or ActionsTile.Talk => hiding,
            ActionsTile.Tea => hiding ?? (!s.TeaEnabled ? L10n.Tr("off in settings") : s.TeaOn ? L10n.Tr("one at a time") : null),
            ActionsTile.Plane => hiding ?? (s.PlaneInAir ? L10n.Tr("one is in the air") : null),
            ActionsTile.Reminder => null,
            ActionsTile.Hide => s.Hiding ? L10n.Tr("%@ left", Clock(s.HideLeft)) : null,
            ActionsTile.Sleep => s.NightOff ? L10n.Tr("night is set to 0") : s.IsNight ? L10n.Tr("dawn in %@", Clock(s.PhaseLeft)) : L10n.Tr("dusk in %@", Clock(s.PhaseLeft)),
            _ => s.Planted == 0 ? L10n.Tr("none planted") : null,
        };
    }

    public static bool IsEnabled(this ActionsTile tile, ActionsState s) => tile switch
    {
        ActionsTile.Jump or ActionsTile.Talk => !s.Hiding,
        ActionsTile.Tea => !s.Hiding && s.TeaEnabled && !s.TeaOn,
        ActionsTile.Plane => !s.Hiding && !s.PlaneInAir,
        ActionsTile.Reminder or ActionsTile.Hide => true,
        ActionsTile.Sleep => !s.NightOff,
        _ => s.Planted > 0,
    };

    private static string Clock(int seconds)
    {
        var s = Math.Max(0, seconds);
        return s >= 3600 ? $"{s / 3600}:{s / 60 % 60:00}:{s % 60:00}" : $"{s / 60}:{s % 60:00}";
    }
}

/// <summary>
/// Creature Actions…: everything you can ask of the creatures, on one sheet of the
/// letter's pixel paper. Each action is a tile with its picture cut from the game's own
/// sprites and a letter key; pressing one does it at once. With <c>actionsStayOpen</c>
/// the sheet stays up for another go, else it folds away.
/// </summary>
public sealed class ActionsSheet : Window
{
    public const double SheetWidth = 564, SheetHeight = 506;
    private const double Headroom = 54, TileWidth = 114, TileHeight = 126, Gap = 10;

    /// <summary>What the hide row offers, in minutes; null means "until tomorrow at eight". In the current language.</summary>
    public static IReadOnlyList<(string Title, double? Minutes)> HideChoices => new (string, double?)[]
    {
        (L10n.Tr("5 MIN"), 5), (L10n.Tr("15 MIN"), 15), (L10n.Tr("30 MIN"), 30), (L10n.Tr("1 H"), 60), (L10n.Tr("2 H"), 120), (L10n.Tr("4 H"), 240), (L10n.Tr("TILL 8:00"), null),
    };

    private static readonly Brush softInk = Frozen(92, 86, 120), faintInk = Frozen(150, 146, 170);
    private static readonly FontFamily mono = new("Consolas");
    private static ActionsSheet? open;

    private readonly AppSettings settings;
    private readonly Colony colony;
    private readonly Action addReminder;
    private readonly Grid root = new() { Width = SheetWidth, Height = SheetHeight };
    private readonly List<(ActionsTile Tile, PixelButton Button, TextBlock Title, TextBlock Detail)> tiles = new();
    private readonly ContentControl line = new() { Height = 30, Margin = new Thickness(0, 0, 0, 12) };
    private readonly TextBlock said = new() { FontFamily = mono, FontSize = 12, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center };
    private readonly StackPanel hideRow = new() { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(0.5) };
    private ActionsState state = new();
    private bool choosingHide, folding;
    /// <summary>What the last press did, shown for a few seconds.</summary>
    private string message = "";
    private DateTime? saidAt;

    /// <summary>Show the sheet, or bring the open one to the front.</summary>
    public static void ShowSheet(AppSettings settings, Colony colony, Action addReminder)
    {
        if (open is not null) { open.Activate(); return; }
        open = new ActionsSheet(settings, colony, addReminder);
        open.Closed += (s, _) => { if (ReferenceEquals(open, s)) open = null; };
        open.Show();
        open.Activate();
    }

    private ActionsSheet(AppSettings settings, Colony colony, Action addReminder)
    {
        this.settings = settings;
        this.colony = colony;
        this.addReminder = addReminder;
        var keeper = colony.NoteKeeper();
        Title = L10n.Tr("Creature Actions");
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
        RenderOptions.SetEdgeMode(root, EdgeMode.Aliased);

        var paper = new Image
        {
            Source = Bitmaps.ToSource(ScreenOverlay.PaperImage((int)(SheetWidth / ReminderNote.Pixel), (int)((SheetHeight - Headroom) / ReminderNote.Pixel))),
            Width = SheetWidth, Height = SheetHeight - Headroom, Stretch = Stretch.Fill,
            HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, Headroom, 0, 0),
        };
        RenderOptions.SetBitmapScalingMode(paper, BitmapScalingMode.NearestNeighbor);
        paper.MouseLeftButtonDown += (_, e) => { if (e.ButtonState == MouseButtonState.Pressed) DragMove(); };
        root.Children.Add(paper);
        if (keeper?.Face is System.Drawing.Bitmap face) root.Children.Add(ReminderNote.Peeker(face, SheetWidth, Headroom));
        root.Children.Add(Sheet(keeper?.Name));

        foreach (var (title, minutes) in HideChoices)
        {
            var button = new PixelButton { Content = title, Small = true, Chosen = minutes == 30, Margin = new Thickness(0, 0, 6, 0) };
            button.Click += (_, _) => Hide(minutes);
            hideRow.Children.Add(button);
        }
        hideRow.Children.Insert(0, new TextBlock
        {
            Text = L10n.Tr("HIDE FOR"), FontFamily = mono, FontSize = 11, FontWeight = FontWeights.Bold, Foreground = softInk,
            VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0),
        });

        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == System.Windows.Input.Key.Escape) { e.Handled = true; Close(); return; }
            if (Keyboard.Modifiers != ModifierKeys.None) return;
            foreach (var tile in ActionsTiles.All)
                if (tile.Key() == e.Key && tile.IsEnabled(state)) { e.Handled = true; Press(tile); return; }
        };
        timer.Tick += (_, _) => Refresh();
        Loaded += (_, _) => { ReminderNote.CentreOnCursorScreen(this); timer.Start(); };
        Closed += (_, _) => timer.Stop();
        Refresh();
    }

    private static SolidColorBrush Frozen(byte r, byte g, byte b)
    {
        var brush = new SolidColorBrush(Color.FromRgb(r, g, b));
        brush.Freeze();
        return brush;
    }

    private UIElement Sheet(string? keeper)
    {
        var sheet = new StackPanel
        {
            Margin = new Thickness(33, Headroom + 27, 33, 0), Width = SheetWidth - 66,
            HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top,
        };
        sheet.Children.Add(new TextBlock
        {
            Text = keeper is string name ? L10n.Tr("WHAT SHOULD THEY DO? · %@ IS WAITING", name.ToUpperInvariant()) : L10n.Tr("WHAT SHOULD THEY DO?"),
            FontFamily = mono, FontSize = 11, FontWeight = FontWeights.Bold, Foreground = faintInk, Margin = new Thickness(0, 0, 0, 14),
        });
        var grid = new StackPanel { Margin = new Thickness(0, 0, 0, 14) };
        for (int r = 0; r < ActionsTiles.All.Count; r += 4)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, r == 0 ? 0 : Gap, 0, 0) };
            foreach (var tile in ActionsTiles.All.Skip(r).Take(4))
                row.Children.Add(Tile(tile, row.Children.Count == 0 ? 0 : Gap));
            grid.Children.Add(row);
        }
        sheet.Children.Add(grid);
        sheet.Children.Add(line);
        var done = new PixelButton { Content = L10n.Tr("DONE"), HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 0, 24, 0) };
        done.Click += (_, _) => Close();
        sheet.Children.Add(done);
        return sheet;
    }

    private PixelButton Tile(ActionsTile tile, double left)
    {
        var title = new TextBlock
        {
            FontFamily = mono, FontSize = 10, FontWeight = FontWeights.Bold, Foreground = PixelBox.Rim,
            TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap, Width = TileWidth - 16, MaxHeight = 28,
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        var detail = new TextBlock
        {
            FontFamily = mono, FontSize = 9, FontWeight = FontWeights.SemiBold, Foreground = softInk,
            HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 4, 0, 0),
        };
        var body = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        var holder = new Grid { Width = 76, Height = 62, Margin = new Thickness(0, 0, 0, 5) };
        if (ActionIcons.Picture(tile) is System.Drawing.Bitmap picture)
        {
            var scale = Math.Max(1, Math.Floor(Math.Min(76.0 / picture.Width, 62.0 / picture.Height)));
            var image = new Image
            {
                Source = Bitmaps.ToSource(picture), Width = picture.Width * scale, Height = picture.Height * scale, Stretch = Stretch.Fill,
                HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
            };
            RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.NearestNeighbor);
            holder.Children.Add(image);
        }
        body.Children.Add(holder);
        body.Children.Add(title);
        body.Children.Add(detail);
        var face = new Grid { Width = TileWidth, Height = TileHeight };
        face.Children.Add(body);
        face.Children.Add(new TextBlock
        {
            Text = tile.Key().ToString(), FontFamily = mono, FontSize = 9, FontWeight = FontWeights.Bold, Foreground = faintInk,
            HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 8, 9, 0),
        });
        var button = new PixelButton { Content = face, Padding = new Thickness(0), Margin = new Thickness(left, 0, 0, 0) };
        button.Click += (_, _) => Press(tile);
        tiles.Add((tile, button, title, detail));
        return button;
    }

    /// <summary>What the tiles need to know, read from the colony twice a second.</summary>
    private void Refresh()
    {
        state = new ActionsState(
            IsNight: colony.IsNight, NightOff: settings.NightMinutes == 0, PhaseLeft: (int)Math.Ceiling(colony.SecondsLeftInPhase),
            TeaEnabled: settings.TeaPartiesEnabled, TeaOn: colony.IsTeaOn, PlaneInAir: colony.IsPlaneInAir,
            Planted: colony.Garden.Beds.Count, Hiding: colony.IsHiding,
            HideLeft: colony.IsHiding ? (int)Math.Ceiling(colony.Hideout.Remaining(colony.Elapsed)) : 0);
        if (state.Hiding) choosingHide = false;
        if (saidAt is DateTime at && (DateTime.Now - at).TotalSeconds > 5) { message = ""; saidAt = null; }
        foreach (var (tile, button, title, detail) in tiles)
        {
            var enabled = tile.IsEnabled(state);
            title.Text = tile.Title(state);
            detail.Text = tile.Detail(state) ?? " ";
            button.IsEnabled = enabled;
            button.Opacity = enabled ? 1 : 0.45;
            button.Chosen = tile == ActionsTile.Hide && (choosingHide || state.Hiding);
        }
        if (choosingHide) line.Content = hideRow;
        else
        {
            said.Text = message.Length == 0 ? L10n.Tr("click a picture, or press its letter") : message;
            said.Foreground = message.Length == 0 ? faintInk : softInk;
            line.Content = said;
        }
    }

    private void Press(ActionsTile tile)
    {
        if (folding) return;
        choosingHide = false;
        string words;
        switch (tile)
        {
            case ActionsTile.Jump:
                colony.StartleEveryone();
                words = L10n.Tr("Everyone jumps.");
                break;
            case ActionsTile.Talk:
                var before = colony.BusyCount;
                colony.TalkNow();
                words = colony.BusyCount > before ? L10n.Tr("Someone has something to say.") : L10n.Tr("Nobody talks: %@.", colony.TalkStatus);
                break;
            case ActionsTile.Tea:
                colony.TeaNow();
                words = colony.IsTeaOn ? L10n.Tr("Two of them sit down to tea.") : L10n.Tr("No tea: %@.", colony.TalkStatus);
                break;
            case ActionsTile.Plane:
                words = colony.SendPlane() ? L10n.Tr("A paper plane goes up.") : L10n.Tr("No plane: %@.", colony.TalkStatus);
                break;
            case ActionsTile.Reminder:
                Close();
                addReminder();
                return;
            case ActionsTile.Hide:
                if (!colony.IsHiding) { choosingHide = true; Refresh(); return; }
                colony.BringThemBack();
                words = L10n.Tr("They come back out.");
                break;
            case ActionsTile.Sleep:
                var night = colony.IsNight;
                colony.SkipPhase();
                words = night ? L10n.Tr("Good morning.") : L10n.Tr("Good night.");
                break;
            default:
                var pulled = colony.ClearGarden();
                words = pulled == 1 ? L10n.Tr("Pulled up the flower.") : L10n.Tr("Pulled up %@.", L10n.TrCount(pulled, "flower", "flowers"));
                break;
        }
        After(words);
    }

    private void Hide(double? minutes)
    {
        choosingHide = false;
        colony.Hide(minutes is double m ? m * 60 : App.SecondsUntilTomorrowMorning());
        After(L10n.Tr("They run home."));
    }

    private void After(string words)
    {
        if (!settings.ActionsStayOpen) { FoldAway(); return; }
        message = words;
        saidAt = DateTime.Now;
        Refresh();
    }

    /// <summary>Done: the sheet shrinks up and away, as the note does when folded.</summary>
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

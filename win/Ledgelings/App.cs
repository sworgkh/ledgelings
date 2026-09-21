using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows;
using Ledgelings.Core;
using Ledgelings.UI;

namespace Ledgelings;

/// <summary>A tray-only application: no main window, quits only from the menu.</summary>
public sealed class App : Application
{
    private AppSettings? settings;
    private ChatHistory? history;
    private SpriteLibrary? library;
    private SpendLedger? spend;
    private Colony? colony;
    private TrayIcon? tray;
    private SettingsWindow? settingsWindow;
    private Mutex? single;

    /// <summary>What the dialog offers, in minutes; null means "until tomorrow at eight".</summary>
    public static readonly IReadOnlyList<(string Title, double? Minutes)> HideChoices = new (string, double?)[]
    {
        ("5 minutes", 5), ("15 minutes", 15), ("30 minutes", 30), ("1 hour", 60), ("2 hours", 120), ("4 hours", 240),
        ("Until tomorrow morning", null),
    };

    public App()
    {
        ShutdownMode = ShutdownMode.OnExplicitShutdown;
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        single = new Mutex(true, "Ledgelings.SingleInstance", out var first);
        if (!first)
        {
            MessageBox.Show("Ledgelings is already running. Look for the square in the notification area.", "Ledgelings");
            Shutdown();
            return;
        }
        settings = new AppSettings();
        history = new ChatHistory();
        library = new SpriteLibrary();
        spend = new SpendLedger();
        try
        {
            colony = new Colony(settings, history, library, spend);
        }
        catch (Exception ex) when (ex is IOException or InvalidDataException or InvalidOperationException)
        {
            MessageBox.Show("Ledgelings could not start: " + ex.Message, "Ledgelings");
            Shutdown(1);
            return;
        }
        tray = new TrayIcon(TrayImage(), "Ledgelings") { MenuBuilder = BuildMenu };
    }

    /// <summary>The icon is the creature itself: its idle pose, cropped to its body.</summary>
    private static Bitmap TrayImage()
    {
        var icon = new Bitmap(32, 32, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        try
        {
            var frame = SpriteAtlas.Named("blocky").MakeFrames().Frame("idle", 0);
            if (frame is null) return icon;
            using var g = Graphics.FromImage(icon);
            g.InterpolationMode = InterpolationMode.NearestNeighbor;
            g.PixelOffsetMode = PixelOffsetMode.Half;
            g.DrawImage(frame, new Rectangle(0, 0, 32, 32), new Rectangle(5, 5, 22, 22), GraphicsUnit.Pixel);
        }
        catch (Exception ex) when (ex is IOException or InvalidDataException) { }
        return icon;
    }

    private IReadOnlyList<TrayIcon.Item> BuildMenu()
    {
        var items = new List<TrayIcon.Item>();
        if (colony is null || settings is null || spend is null) return items;
        var left = (int)Math.Ceiling(colony.SecondsLeftInPhase);
        var clock = $"{left / 60}:{left % 60:00}";
        var phase = settings.NightMinutes == 0 ? "Always day \u2014 night is set to 0"
            : colony.IsNight ? $"Night \u2014 they wake in {clock}" : $"Day \u2014 they sleep in {clock}";
        items.Add(new TrayIcon.Item(phase, Enabled: false));
        if (settings.NightMinutes > 0) items.Add(new TrayIcon.Item(colony.IsNight ? "Wake Them Up Now" : "Put Them to Sleep Now", colony.SkipPhase));
        items.Add(TrayIcon.Item.Separator);
        items.Add(new TrayIcon.Item("Make Them Jump", colony.StartleEveryone));
        string hide;
        if (colony.IsHiding)
        {
            var back = (int)Math.Ceiling(colony.Hideout.Remaining(colony.Elapsed));
            hide = back > 0 ? $"Bring Them Back Now ({back / 60}:{back % 60:00} left)" : "Coming home\u2026";
        }
        else hide = "Hide Them for a While\u2026";
        items.Add(new TrayIcon.Item(hide, HideThem));
        items.Add(new TrayIcon.Item("Make Someone Talk", () => colony.TalkNow()));
        var status = colony.TalkStatus;
        items.Add(new TrayIcon.Item("   " + (status.Length > 70 ? status[..70] : status), Enabled: false));
        items.Add(new TrayIcon.Item("Chat History\u2026", () => OpenSettings(SettingsTab.Chats)));
        var s = spend.Summary;
        if (s.AllTime.Calls > 0)
            items.Add(new TrayIcon.Item($"Spent: {Spend.Label(s.Today.Cost)} today, {Spend.Label(s.Month.Cost)} this month", () => OpenSettings(SettingsTab.Talk)));
        items.Add(new TrayIcon.Item("Settings\u2026", () => OpenSettings(null)));
        items.Add(TrayIcon.Item.Separator);
        items.Add(new TrayIcon.Item("Quit Ledgelings", Shutdown));
        return items;
    }

    /// <summary>A small dialog: how long should they stay in the house?</summary>
    private void HideThem()
    {
        if (colony is null) return;
        if (colony.IsHiding) { colony.BringThemBack(); return; }
        if (HideDialog.Ask() is not double seconds) return;
        colony.Hide(seconds);
    }

    /// <summary>Seconds until 08:00 tomorrow, local time.</summary>
    public static double SecondsUntilTomorrowMorning()
    {
        var eight = DateTime.Today.AddDays(1).AddHours(8);
        return Math.Max(60, (eight - DateTime.Now).TotalSeconds);
    }

    private void OpenSettings(SettingsTab? tab)
    {
        if (settings is null || history is null || library is null || spend is null) return;
        settingsWindow ??= new SettingsWindow(settings, history, library, spend);
        settingsWindow.Show(tab);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        tray?.Dispose();
        colony?.Dispose();
        single?.Dispose();
        base.OnExit(e);
    }
}

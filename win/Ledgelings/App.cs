using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows;
using Ledgelings.Core;
using Ledgelings.UI;

namespace Ledgelings;

/// <summary>A tray-only application: no main window, quits only from the menu.</summary>
public sealed partial class App : Application
{
    private AppSettings? settings;
    private ChatHistory? history;
    private SpriteLibrary? library;
    private SpendLedger? spend;
    private Voice? voice;
    private Colony? colony;
    private TrayIcon? tray;
    private SettingsWindow? settingsWindow;
    private Mutex? single;

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
            // The running copy's settings, read without writing them.
            var saved = new JsonSettingsStore(AppFolders.SettingsFile);
            // With the icon tucked away this is a way in: the running copy shows its sheet, and this one leaves quietly.
            if ((saved.Get<bool?>("reopenShowsActions") ?? true) && TellTheRunningCopy()) { Shutdown(); return; }
            Languages.Choose(Languages.FromCode(saved.Get<string>("language")) ?? Languages.System);
            MessageBox.Show(L10n.Tr("Ledgelings is already running. Look for the square in the notification area."), "Ledgelings");
            Shutdown();
            return;
        }
        settings = new AppSettings();
        // Before anything is drawn or said: the language everything looks its words up in.
        Languages.Choose(settings.Language);
        settings.PropertyChanged += (_, e) => { if (e.PropertyName == nameof(AppSettings.Language)) Languages.Choose(settings.Language); };
        CursorMoods.Choose(settings.CursorMood);
        settings.PropertyChanged += (_, e) => { if (e.PropertyName == nameof(AppSettings.CursorMood)) CursorMoods.Choose(settings.CursorMood); };
        history = new ChatHistory();
        library = new SpriteLibrary();
        spend = new SpendLedger();
        try
        {
            colony = new Colony(settings, history, library, spend);
            voice = new Voice(settings, spend, history);
            colony.Voice = voice;
        }
        catch (Exception ex) when (ex is IOException or InvalidDataException or InvalidOperationException)
        {
            MessageBox.Show(L10n.Tr("Ledgelings could not start: %@", ex.Message), "Ledgelings");
            Shutdown(1);
            return;
        }
        StartReminders();
        StartShortcut();
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
        var phase = settings.NightMinutes == 0 ? L10n.Tr("Always day \u2014 night is set to 0")
            : colony.IsNight ? L10n.Tr("Night \u2014 they wake in %@", clock) : L10n.Tr("Day \u2014 they sleep in %@", clock);
        if (colony.IsHiding)
        {
            var back = (int)Math.Ceiling(colony.Hideout.Remaining(colony.Elapsed));
            phase = back > 0 ? L10n.Tr("Hiding in the house \u2014 out in %@", $"{back / 60}:{back % 60:00}") : L10n.Tr("Coming home\u2026");
        }
        items.Add(new TrayIcon.Item(phase, Enabled: false));
        items.Add(TrayIcon.Item.Separator);
        // After a tab a menu draws the rest at the right, as it does for any shortcut.
        var keys = ShortcutTitle;
        items.Add(new TrayIcon.Item(L10n.Tr("Creature Actions\u2026") + (keys.Length > 0 ? "\t" + keys : ""), OpenActions));
        AddNextReminder(items);
        items.Add(new TrayIcon.Item(L10n.Tr("Hear Them Talk"), () => settings.VoiceEnabled = !settings.VoiceEnabled, Checked: settings.VoiceEnabled));
        items.Add(new TrayIcon.Item(L10n.Tr("Cursor Revenge"), () => settings.RevengeEnabled = !settings.RevengeEnabled, Checked: settings.RevengeEnabled));
        var status = colony.TalkStatus;
        items.Add(new TrayIcon.Item("   " + (status.Length > 70 ? status[..70] : status), Enabled: false));
        items.Add(new TrayIcon.Item(L10n.Tr("Chat History\u2026"), () => OpenSettings(SettingsTab.Chats)));
        var s = spend.Summary;
        if (s.AllTime.Calls > 0)
            items.Add(new TrayIcon.Item(L10n.Tr("Spent: %@ today, %@ this month", Spend.Label(s.Today.Cost), Spend.Label(s.Month.Cost)), () => OpenSettings(SettingsTab.Costs)));
        // Each language under its own name, so whoever cannot read the current one still finds theirs.
        items.Add(new TrayIcon.Item(L10n.Tr("Language"), Children: Languages.All
            .Select(l => new TrayIcon.Item(l.Title(), () => settings.Language = l, Checked: settings.Language == l)).ToList()));
        items.Add(new TrayIcon.Item(L10n.Tr("The Cursor Is"), Children: CursorMoods.All
            .Select(m => new TrayIcon.Item(m.Title(), () => settings.CursorMood = m, Checked: settings.CursorMood == m)).ToList()));
        items.Add(new TrayIcon.Item(L10n.Tr("Settings\u2026"), () => OpenSettings(null)));
        items.Add(TrayIcon.Item.Separator);
        items.Add(new TrayIcon.Item(L10n.Tr("Quit Ledgelings"), Shutdown));
        return items;
    }

    /// <summary>The sheet of picture tiles for everything you can ask of them.</summary>
    private void OpenActions()
    {
        if (colony is null || settings is null) return;
        ActionsSheet.ShowSheet(settings, colony, AddAReminder, Follow, () => ShortcutTitle);
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
        settingsWindow ??= new SettingsWindow(settings, history, library, spend) { ClearGarden = () => colony?.ClearGarden() ?? 0, BondBook = colony?.Bonds, HuntBook = colony?.Hunts, Voice = voice };
        AttachReminders(settingsWindow);
        settingsWindow.Show(tab);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        tray?.Dispose();
        StopReminders();
        StopShortcut();
        colony?.Dispose();
        single?.Dispose();
        base.OnExit(e);
    }
}

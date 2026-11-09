using System.Windows.Threading;
using Ledgelings.Core;
using Ledgelings.Native;

namespace Ledgelings;

/// <summary>Everything big that runs on the screen for a while and must stop the moment the owner needs the
/// computer (SPEC §7.17): a dive, a surf, a game. Each registers how to tell it is running and how to stop it;
/// Stop activity (Ctrl+Alt+Esc, the tray) calls <see cref="StopAll"/>, and so does a real key press or click
/// while "Stop when I use the computer" is on (<see cref="UseWatch"/>).</summary>
public sealed class Activities
{
    public enum Kind { Surf, Dive, Game }

    public static Activities Shared { get; } = new();

    private readonly List<(Kind Kind, Func<bool> IsRunning, Action Stop)> entries = new();
    /// <summary>Each stop, as it happens.</summary>
    public Action<string>? Trace { get; set; }

    /// <summary><paramref name="kind"/> is running while <paramref name="isRunning"/> says so; <paramref name="stop"/>
    /// clears it off the screen at once. Registering a kind again replaces it.</summary>
    public void Register(Kind kind, Func<bool> isRunning, Action stop)
    {
        entries.RemoveAll(e => e.Kind == kind);
        entries.Add((kind, isRunning, stop));
    }

    public void Unregister(Kind kind) => entries.RemoveAll(e => e.Kind == kind);

    public bool IsKindRunning(Kind kind) => entries.Any(e => e.Kind == kind && e.IsRunning());

    /// <summary>Whether anything at all is running.</summary>
    public bool IsRunning => entries.Any(e => e.IsRunning());

    public IReadOnlyList<Kind> Running => entries.Where(e => e.IsRunning()).Select(e => e.Kind).ToList();

    /// <summary>Stop everything that runs. Returns what was stopped.</summary>
    public IReadOnlyList<Kind> StopAll(string why = "stop activity")
    {
        var stopped = Running;
        foreach (var e in entries.ToList()) if (e.IsRunning()) e.Stop();
        if (stopped.Count > 0) Trace?.Invoke($"activity stopped: {string.Join(", ", stopped.Select(k => k.ToString().ToLowerInvariant()))} ({why})");
        return stopped;
    }
}

/// <summary>"Stop when I use the computer": while an activity runs, a real key press or a click anywhere but on a
/// creature stops it; moving the mouse does not. Ten times a second it asks Windows which keys and buttons went
/// down since it last looked (<c>GetAsyncKeyState</c>, no permission needed); a click the creatures took
/// themselves is told apart by its time (<see cref="OwnClick"/>), and the decision is <see cref="UsePolicy"/>'s.</summary>
public sealed class UseWatch : IDisposable
{
    private readonly AppSettings settings;
    private readonly DispatcherTimer timer;
    private DateTime? started;
    private DateTime lastKey = DateTime.MinValue, lastClick = DateTime.MinValue;
    /// <summary>When the overlay (a creature, a bubble) last took a click; that click is no reason to stop.</summary>
    public static DateTime OwnClick { get; set; } = DateTime.MinValue;
    private static readonly int[] Buttons = { Win32.VK_LBUTTON, Win32.VK_RBUTTON, Win32.VK_MBUTTON, 0x05, 0x06 };

    /// <summary>Whether a key, and a mouse button, went down since the last look; tests set it.</summary>
    public Func<(bool Key, bool Click)> Pressed { get; set; } = ReadPresses;

    public UseWatch(AppSettings settings)
    {
        this.settings = settings;
        timer = new DispatcherTimer(TimeSpan.FromMilliseconds(100), DispatcherPriority.Background, (_, _) => Check(DateTime.Now), Dispatcher.CurrentDispatcher);
        timer.Start();
    }

    private static (bool, bool) ReadPresses()
    {
        static bool Down(int vk) => (Win32.GetAsyncKeyState(vk) & 0x8001) != 0;
        var click = Buttons.Any(Down);
        var key = false;
        for (int vk = 0x08; vk <= 0xFE; vk++) if (!Buttons.Contains(vk) && Down(vk)) key = true;
        return (key, click);
    }

    public void Check(DateTime now)
    {
        var activities = Activities.Shared;
        var (key, click) = Pressed();
        if (key) lastKey = now;
        if (click) lastClick = now;
        if (!activities.IsRunning) { started = null; return; }
        if (started is not DateTime since) { started = now; return; }
        if (!settings.StopOnUse) return;
        static double Ago(DateTime now, DateTime then) => then == DateTime.MinValue ? 1e9 : (now - then).TotalSeconds;
        double sinceKey = Ago(now, lastKey), sinceClick = Ago(now, lastClick);
        if (UsePolicy.Stops((now - since).TotalSeconds, sinceKey, sinceClick, Ago(now, OwnClick)))
        {
            activities.StopAll(sinceKey < sinceClick ? "a key was pressed" : "a click outside the creatures");
            started = null;
        }
    }

    public void Dispose() => timer.Stop();
}

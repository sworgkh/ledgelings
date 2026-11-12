using System.Runtime.InteropServices;
using System.Text;
using Ledgelings.Core;
using Microsoft.Win32;

namespace Ledgelings;

/// <summary>
/// What the weather needs to know about the PC (SPEC §7.20), the Mac's <c>WeatherWatch</c>, read without asking for
/// any permission: the other apps' windows (only their frames, for the snow on their tops and for a full-screen app),
/// whether a microphone is in use (a call), and how long since a key was pressed.
/// </summary>
internal static class WeatherWatch
{
    /// <summary>Another app's window on screen, front first: its handle and frame in the colony's points (y up).</summary>
    public readonly record struct Window(long Id, Rect Frame);

    private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr data);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc proc, IntPtr data);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern IntPtr GetWindowLongPtrW(IntPtr hwnd, int index);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassNameW(IntPtr hwnd, StringBuilder name, int max);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out RECT value, int size);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out int value, int size);

    [StructLayout(LayoutKind.Sequential)] private struct RECT { public int Left, Top, Right, Bottom; }

    private const int GWL_EXSTYLE = -20, WS_EX_TOOLWINDOW = 0x80, WS_EX_TRANSPARENT = 0x20;
    private const int DWMWA_EXTENDED_FRAME_BOUNDS = 9, DWMWA_CLOAKED = 14;

    /// <summary>The ordinary windows of every other app on screen now, front to back (EnumWindows goes in z-order).</summary>
    public static List<Window> Windows()
    {
        var found = new List<Window>();
        if (!OperatingSystem.IsWindows()) return found;
        var me = (uint)Environment.ProcessId;
        var name = new StringBuilder(64);
        EnumWindows((hwnd, _) =>
        {
            if (!IsWindowVisible(hwnd) || IsIconic(hwnd)) return true;
            GetWindowThreadProcessId(hwnd, out var pid);
            if (pid == me) return true;
            var ex = (long)GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
            if ((ex & WS_EX_TOOLWINDOW) != 0 || (ex & WS_EX_TRANSPARENT) != 0) return true;
            // Hidden by the shell (another virtual desktop, a suspended Store app): there, but not on screen.
            if (DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, out int cloaked, sizeof(int)) == 0 && cloaked != 0) return true;
            name.Clear();
            GetClassNameW(hwnd, name, name.Capacity);
            var cls = name.ToString();
            if (cls is "Progman" or "WorkerW" or "Shell_TrayWnd" or "Shell_SecondaryTrayWnd") return true;      // the desktop and the taskbar
            // Its visible frame, without the invisible resizing border Windows 10 and 11 put around it.
            RECT r;
            if (DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, out r, Marshal.SizeOf<RECT>()) != 0 && !GetWindowRect(hwnd, out r)) return true;
            int w = r.Right - r.Left, h = r.Bottom - r.Top;
            if (w < 80 || h < 40) return true;
            found.Add(new Window(hwnd.ToInt64(), new Rect(r.Left, -r.Bottom, w, h)));
            return true;
        }, IntPtr.Zero);
        return found;
    }

    /// <summary>A window fills one of <paramref name="screens"/> whole: a full-screen app, a game, a presentation.
    /// Windows reads only the window in front, as a borderless maximised window counts too.</summary>
    public static bool FullScreen(IReadOnlyList<Window> windows, IReadOnlyList<Rect> screens)
    {
        if (!OperatingSystem.IsWindows()) return false;
        var front = GetForegroundWindow().ToInt64();
        return windows.Any(w => w.Id == front && screens.Any(s => Covers(w.Frame, s)));
    }

    /// <summary><paramref name="frame"/> covers <paramref name="screen"/> to within a pixel.</summary>
    public static bool Covers(Rect frame, Rect screen) =>
        frame.MinX <= screen.MinX + 1 && frame.MaxX >= screen.MaxX - 1 && frame.MinY <= screen.MinY + 1 && frame.MaxY >= screen.MaxY - 1;

    /// <summary>Seconds since a key was last pressed anywhere: the keyboard counter's when it has seen one, else
    /// Windows' own idle time (mouse and keys together, so stricter).</summary>
    public static double KeyIdle(Native.KeyCounter? keys) => keys?.KeyIdle ?? Desktop.IdleSeconds();

    /// <summary>An app is using a microphone now: a call, a meeting. Windows keeps, for its privacy page, when each
    /// app last started and stopped using it; one started and not stopped is using it now. Read from the registry,
    /// so it needs no permission.</summary>
    public static bool MicrophoneInUse
    {
        get
        {
            if (!OperatingSystem.IsWindows()) return false;
            try
            {
                using var store = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone");
                return store is not null && InUse(store);
            }
            catch (Exception e) when (e is System.Security.SecurityException or UnauthorizedAccessException or IOException) { return false; }
        }
    }

    private static bool InUse(RegistryKey key)
    {
        if (!OperatingSystem.IsWindows()) return false;
        foreach (var name in key.GetSubKeyNames())
        {
            using var sub = key.OpenSubKey(name);
            if (sub is null) continue;
            if (sub.GetValue("LastUsedTimeStart") is long start && start > 0 && sub.GetValue("LastUsedTimeStop") is long stop && stop == 0) return true;
            if (name == "NonPackaged" && InUse(sub)) return true;       // desktop apps, one key per program
        }
        return false;
    }

    /// <summary>The windows' tops as the sky of the monitor at <paramref name="display"/> sees them, in its art pixels
    /// (<paramref name="scale"/> points each, y down from its top): the columns under a window further front are left out.</summary>
    public static Dictionary<int, Weather.Ledge> Ledges(IReadOnlyList<Window> windows, Rect display, double scale, double topInset)
    {
        var made = new Dictionary<int, Weather.Ledge>();
        for (int k = 0; k < windows.Count; k++)
        {
            var w = windows[k];
            var top = w.Frame.MaxY;
            // Its top on this monitor, below a taskbar along the top, and not the monitor's own bottom.
            if (!(top <= display.MaxY - topInset && top > display.MinY + 40 && w.Frame.MaxX > display.MinX && w.Frame.MinX < display.MaxX)) continue;
            double x0 = Math.Max(w.Frame.MinX, display.MinX), x1 = Math.Min(w.Frame.MaxX, display.MaxX);
            var ax = (int)Math.Ceiling((x0 - display.MinX) / scale);
            var width = (int)Math.Floor((x1 - display.MinX) / scale) - ax;
            if (width <= 4) continue;
            var y = (int)Math.Round((display.MaxY - top) / scale, MidpointRounding.AwayFromZero);
            var open = new bool[width];
            for (int c = 0; c < width; c++)
            {
                var p = new Pt(display.MinX + (ax + c + 0.5) * scale, top + scale);
                var covered = false;
                for (int f = 0; f < k && !covered; f++) covered = windows[f].Frame.Contains(p);
                open[c] = !covered;
            }
            if (!open.Contains(true)) continue;
            made[(int)(w.Id & 0x7fffffff)] = new Weather.Ledge(ax, y, open);
        }
        return made;
    }
}

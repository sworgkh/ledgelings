using Ledgelings.Core;
using Ledgelings.Native;
using Microsoft.Win32;

namespace Ledgelings;

/// <summary>One monitor, in Windows' own pixels (origin top-left, y down) and in the
/// simulation's points (origin bottom-left, y up). <c>Id</c> survives relaunching and re-plugging
/// (the monitor's device interface path, which carries its make and the port it is on); <c>Name</c>
/// is what the menus show (its model when Windows knows it, else "Display 2").</summary>
public sealed record Monitor(IntPtr Handle, int Left, int Top, int Width, int Height, bool IsPrimary, double DpiScale,
                             string Id = "", string Name = "")
{
    /// <summary>As <see cref="HomeScreen"/> sees it.</summary>
    public HomeScreen.Monitor Home => new(Id, Name, Frame);

    /// <summary>The rectangle in simulation coordinates: y up.</summary>
    public Rect Frame => new(Left, -(Top + Height), Width, Height);
    public int Bottom => Top + Height;
    public int Right => Left + Width;
}

/// <summary>
/// The desktop as the colony sees it: the monitors, the cursor and the modifier keys,
/// polled each frame, and a notice when the monitors change.
///
/// The simulation is written in AppKit's coordinates (y up). Windows counts y
/// downwards from the top of the primary monitor, so everything crossing this
/// boundary is flipped once: <c>yUp = -yDown</c>.
/// </summary>
public static class Desktop
{
    public static event Action? MonitorsChanged;

    static Desktop()
    {
        SystemEvents.DisplaySettingsChanged += (_, _) => MonitorsChanged?.Invoke();
    }

    public static List<Monitor> Monitors()
    {
        var found = new List<Monitor>();
        Win32.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr hMonitor, IntPtr _, ref Win32.RECT _, IntPtr _) =>
        {
            var info = new Win32.MONITORINFOEXW { cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf<Win32.MONITORINFOEXW>() };
            if (!Win32.GetMonitorInfoEx(hMonitor, ref info)) return true;
            var r = info.rcMonitor;
            double scale = 1;
            if (Win32.GetDpiForMonitor(hMonitor, Win32.MDT_EFFECTIVE_DPI, out var dpi, out _) == 0 && dpi > 0) scale = dpi / 96.0;
            var (id, model) = Identify(info.szDevice);
            found.Add(new Monitor(hMonitor, r.Left, r.Top, r.Width, r.Height, (info.dwFlags & Win32.MONITORINFOF_PRIMARY) != 0, scale, id, model));
            return true;
        }, IntPtr.Zero);
        found = Named(found);
        // The primary first, then left to right, top to bottom: a stable order for the overlays.
        return found.OrderByDescending(m => m.IsPrimary).ThenBy(m => m.Left).ThenBy(m => m.Top).ToList();
    }

    /// <summary>The monitor attached to the GDI device <paramref name="device"/> ("\\.\DISPLAY2"): its
    /// interface path as the id (the device name when there is none), and its model, or "Display 2".</summary>
    private static (string Id, string Name) Identify(string device)
    {
        var number = new string(device.Reverse().TakeWhile(char.IsDigit).Reverse().ToArray());
        var fallback = L10n.Tr("Display %@", number.Length > 0 ? number : "?");
        var dd = new Win32.DISPLAY_DEVICEW { cb = (uint)System.Runtime.InteropServices.Marshal.SizeOf<Win32.DISPLAY_DEVICEW>() };
        if (!Win32.EnumDisplayDevicesW(device, 0, ref dd, Win32.EDD_GET_DEVICE_INTERFACE_NAME)) return (device, fallback);
        var id = string.IsNullOrWhiteSpace(dd.DeviceID) ? device : dd.DeviceID;
        var model = dd.DeviceString?.Trim() ?? "";
        // "Generic PnP Monitor" says nothing about which one it is.
        var generic = model.Length == 0 || model.StartsWith("Generic", StringComparison.OrdinalIgnoreCase);
        return (id, generic ? fallback : model);
    }

    /// <summary>Two of one model get "(1)", "(2)" left to right, as the Mac names them.</summary>
    internal static List<Monitor> Named(List<Monitor> monitors)
    {
        var twins = monitors.GroupBy(m => m.Name).Where(g => g.Count() > 1).ToList();
        foreach (var g in twins)
        {
            int n = 1;
            foreach (var m in g.OrderBy(m => m.Left).ThenBy(m => m.Top).ToList())
                monitors[monitors.IndexOf(m)] = m with { Name = $"{m.Name} ({n++})" };
        }
        return monitors;
    }

    public static Monitor? Primary(IReadOnlyList<Monitor> monitors) => monitors.FirstOrDefault(m => m.IsPrimary) ?? monitors.FirstOrDefault();

    /// <summary>Global cursor position in simulation coordinates. Needs no permission.</summary>
    public static Pt Cursor()
    {
        Win32.GetCursorPos(out var p);
        return ToUp(p.X, p.Y);
    }

    public static Pt ToUp(double x, double yDown) => new(x, -yDown);

    public static bool IsShiftDown => (Win32.GetAsyncKeyState(Win32.VK_SHIFT) & 0x8000) != 0;
    public static bool IsControlDown => (Win32.GetAsyncKeyState(Win32.VK_CONTROL) & 0x8000) != 0;

    /// <summary>Seconds since the user last touched the mouse or keyboard, in this session.</summary>
    public static double IdleSeconds()
    {
        var info = new Win32.LASTINPUTINFO { cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf<Win32.LASTINPUTINFO>() };
        if (!Win32.GetLastInputInfo(ref info)) return 0;
        return unchecked(Win32.GetTickCount() - info.dwTime) / 1000.0;      // both wrap every 49 days; the difference does not
    }

    /// <summary>Pixels per point on the primary monitor, in half steps, so that "3×" on a
    /// 150 % display draws each sheet pixel as 4.5 screen pixels and a creature is the
    /// size it is on a Mac. 1 on a plain 96 dpi monitor.</summary>
    public static double PixelScale
    {
        get
        {
            var primary = Primary(Monitors());
            var raw = primary?.DpiScale ?? 1;
            return Math.Max(1, Math.Round(raw * 2) / 2);
        }
    }
}

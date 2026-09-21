using Ledgelings.Core;
using Ledgelings.Native;
using Microsoft.Win32;

namespace Ledgelings;

/// <summary>One monitor, in Windows' own pixels (origin top-left, y down) and in the
/// simulation's points (origin bottom-left, y up).</summary>
public sealed record Monitor(IntPtr Handle, int Left, int Top, int Width, int Height, bool IsPrimary, double DpiScale)
{
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
            var info = new Win32.MONITORINFO { cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf<Win32.MONITORINFO>() };
            if (!Win32.GetMonitorInfoW(hMonitor, ref info)) return true;
            var r = info.rcMonitor;
            double scale = 1;
            if (Win32.GetDpiForMonitor(hMonitor, Win32.MDT_EFFECTIVE_DPI, out var dpi, out _) == 0 && dpi > 0) scale = dpi / 96.0;
            found.Add(new Monitor(hMonitor, r.Left, r.Top, r.Width, r.Height, (info.dwFlags & Win32.MONITORINFOF_PRIMARY) != 0, scale));
            return true;
        }, IntPtr.Zero);
        // The primary first, then left to right, top to bottom: a stable order for the overlays.
        return found.OrderByDescending(m => m.IsPrimary).ThenBy(m => m.Left).ThenBy(m => m.Top).ToList();
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

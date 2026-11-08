using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using Ledgelings.Core;
using Ledgelings.Native;
using Rect = Ledgelings.Core.Rect;

namespace Ledgelings.UI;

/// <summary>Puts a window back where the owner last dragged it, and keeps the place each time they
/// drag it again (<see cref="AppSettings.PlaceOf"/>, <see cref="WindowPlaces"/>), the Mac's <c>WindowPlacer</c>.</summary>
internal static class WindowPlacer
{
    /// <summary>Once <paramref name="window"/> is laid out where it always opens, moves it to its saved place when
    /// that is on a screen now; and saves where it goes each time the owner drags it. A move made by the app
    /// (a sheet folding away) happens with no button down and is not kept.</summary>
    public static void Keep(Window window, WindowPlaces.Window name, AppSettings settings)
    {
        window.Loaded += (_, _) =>
        {
            var hwnd = new WindowInteropHelper(window).Handle;
            if (hwnd == IntPtr.Zero || settings.PlaceOf(name) is not { } top || !Win32.GetWindowRect(hwnd, out var r)) return;
            var screens = Desktop.Monitors().Select(m => new Rect(m.Left, m.Top, m.Width, m.Height)).ToList();
            if (WindowPlaces.Frame(top.Left, top.Top, r.Right - r.Left, r.Bottom - r.Top, screens) is not { } frame) return;
            Win32.SetWindowPos(hwnd, IntPtr.Zero, (int)frame.X, (int)frame.Y, 0, 0, Win32.SWP_NOSIZE | Win32.SWP_NOACTIVATE | 0x0004 /* SWP_NOZORDER */);
        };
        window.LocationChanged += (_, _) =>
        {
            if (Mouse.LeftButton != MouseButtonState.Pressed) return;
            var hwnd = new WindowInteropHelper(window).Handle;
            if (hwnd != IntPtr.Zero && Win32.GetWindowRect(hwnd, out var r)) settings.Moved(name, r.Left, r.Top);
        };
    }

    /// <summary>The monitor a paper sheet opens on: the one its saved place is on, else <paramref name="otherwise"/>.</summary>
    public static Monitor SheetMonitor(WindowPlaces.Window name, AppSettings settings, Monitor otherwise)
    {
        if (settings.PlaceOf(name) is not { } top) return otherwise;
        return Desktop.Monitors().FirstOrDefault(m => top.Left >= m.Left && top.Left < m.Right && top.Top >= m.Top && top.Top < m.Bottom) ?? otherwise;
    }
}

/// <summary>
/// A paper sheet (the Tools screen, Translate, Read aloud, the clipboard picker) is drawn inside a
/// see-through window over one monitor. This puts the paper at its saved place on that monitor, or in
/// the middle, and lets a drag that starts on it where no control takes the click move it inside the
/// window. Pressing the paper never reaches the window, which would close it.
/// </summary>
internal sealed class SheetDrag
{
    private readonly FrameworkElement paper;
    private readonly Monitor monitor;
    private readonly WindowPlaces.Window name;
    private readonly AppSettings settings;
    private readonly double width, height, roomWidth, roomHeight;
    /// <summary>The paper's top-left in the window, in device-independent points.</summary>
    private Point at;
    private Point? grabbed;
    private Point grabbedAt;

    public SheetDrag(Window window, FrameworkElement paper, Monitor monitor, double width, double height, WindowPlaces.Window name, AppSettings settings)
    {
        this.paper = paper;
        this.monitor = monitor;
        this.name = name;
        this.settings = settings;
        this.width = width;
        this.height = height;
        roomWidth = monitor.Width / monitor.DpiScale;
        roomHeight = monitor.Height / monitor.DpiScale;
        var centre = new Rect(Math.Round((roomWidth - width) / 2), Math.Round((roomHeight - height) / 2), width, height);
        var saved = settings.PlaceOf(name) is { } top && top.Left >= monitor.Left && top.Left < monitor.Right && top.Top >= monitor.Top && top.Top < monitor.Bottom
            ? WindowPlaces.Paper(new Rect((top.Left - monitor.Left) / monitor.DpiScale, (top.Top - monitor.Top) / monitor.DpiScale, width, height), roomWidth, roomHeight)
            : centre;
        Put(new Point(saved.X, saved.Y));
        paper.MouseLeftButtonDown += (_, e) =>
        {
            e.Handled = true;
            grabbed = e.GetPosition(window);
            grabbedAt = at;
            paper.CaptureMouse();
        };
        paper.MouseMove += (_, e) =>
        {
            if (grabbed is not { } from || e.LeftButton != MouseButtonState.Pressed) return;
            var now = e.GetPosition(window);
            var to = WindowPlaces.Paper(new Rect(grabbedAt.X + now.X - from.X, grabbedAt.Y + now.Y - from.Y, width, height), roomWidth, roomHeight);
            Put(new Point(to.X, to.Y));
        };
        paper.MouseLeftButtonUp += (_, e) =>
        {
            if (grabbed is null) return;
            grabbed = null;
            paper.ReleaseMouseCapture();
            e.Handled = true;
            if (at != grabbedAt) settings.Moved(name, monitor.Left + at.X * monitor.DpiScale, monitor.Top + at.Y * monitor.DpiScale);
        };
    }

    private void Put(Point to)
    {
        at = to;
        paper.HorizontalAlignment = HorizontalAlignment.Left;
        paper.VerticalAlignment = VerticalAlignment.Top;
        paper.Margin = new Thickness(to.X, to.Y, 0, 0);
    }

    /// <summary>The paper's bounds in screen pixels, where it is now.</summary>
    public System.Drawing.Rectangle OnScreen() => new(
        monitor.Left + (int)Math.Round(at.X * monitor.DpiScale), monitor.Top + (int)Math.Round(at.Y * monitor.DpiScale),
        (int)Math.Round(width * monitor.DpiScale), (int)Math.Round(height * monitor.DpiScale));
}

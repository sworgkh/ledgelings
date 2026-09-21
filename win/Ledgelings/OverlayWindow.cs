using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using Ledgelings.Core;
using Ledgelings.Native;

namespace Ledgelings;

/// <summary>What the user's hand did, in GLOBAL simulation coordinates (y up).</summary>
public abstract record HandEvent
{
    public sealed record Down(Pt Point, bool Shift) : HandEvent;
    public sealed record Dragged(Pt Point) : HandEvent;
    public sealed record Up(Pt Point) : HandEvent;
    /// <summary>Right button, or Control held: the "other" click.</summary>
    public sealed record SecondaryDown(Pt Point) : HandEvent;
}

/// <summary>
/// A transparent sheet of glass over one whole monitor: a layered window with
/// per-pixel alpha, drawn into by GDI+ and pushed to the compositor one dirty
/// rectangle at a time.
///
/// It is click-through by default (<c>WS_EX_TRANSPARENT</c>). The colony clears that
/// style only while the cursor is on a creature the user can act on, so a click
/// anywhere else always reaches whatever is underneath. It never activates, so a
/// click on a creature does not pull focus from the app the user is working in.
/// </summary>
public sealed class OverlayWindow : IDisposable
{
    private static readonly Win32.WindowClass windowClass = new("LedgelingsOverlay");

    public Monitor Monitor { get; }
    public IntPtr Hwnd { get; private set; }
    /// <summary>The whole monitor's pixels, premultiplied BGRA, top row first.</summary>
    public Bitmap Surface { get; }
    public Graphics Graphics { get; }
    public event Action<HandEvent>? Hand;

    private readonly IntPtr memoryDc;
    private readonly IntPtr dib;
    private readonly IntPtr previousBitmap;
    private readonly IntPtr scratch;      // pptDst, psize, pptSrc, pblend, prcDirty, packed
    private bool clickable;
    private bool capturing;
    private bool presented;

    public OverlayWindow(Monitor monitor)
    {
        Monitor = monitor;
        var info = new Win32.BITMAPINFO
        {
            bmiHeader = new Win32.BITMAPINFOHEADER
            {
                biSize = (uint)Marshal.SizeOf<Win32.BITMAPINFOHEADER>(),
                biWidth = monitor.Width, biHeight = -monitor.Height,      // top-down
                biPlanes = 1, biBitCount = 32, biCompression = 0,
            },
        };
        memoryDc = Win32.CreateCompatibleDC(IntPtr.Zero);
        dib = Win32.CreateDIBSection(IntPtr.Zero, ref info, 0, out var bits, IntPtr.Zero, 0);
        if (dib == IntPtr.Zero) throw new InvalidOperationException("CreateDIBSection failed");
        previousBitmap = Win32.SelectObject(memoryDc, dib);
        Surface = new Bitmap(monitor.Width, monitor.Height, monitor.Width * 4, PixelFormat.Format32bppPArgb, bits);
        Graphics = Graphics.FromImage(Surface);
        scratch = Marshal.AllocHGlobal(64);

        Hwnd = windowClass.Create(
            Win32.WS_EX_LAYERED | Win32.WS_EX_TRANSPARENT | Win32.WS_EX_TOPMOST | Win32.WS_EX_NOACTIVATE | Win32.WS_EX_TOOLWINDOW,
            Win32.WS_POPUP, monitor.Left, monitor.Top, monitor.Width, monitor.Height, WndProc);
        Present(Array.Empty<Rectangle>());
        Win32.SetWindowPos(Hwnd, Win32.HWND_TOPMOST, monitor.Left, monitor.Top, monitor.Width, monitor.Height,
            Win32.SWP_NOACTIVATE | Win32.SWP_SHOWWINDOW);
    }

    /// <summary>Push the surface to the screen. Only <paramref name="dirty"/> is copied, except the
    /// first time, when the whole window must be handed over.</summary>
    public void Present(IReadOnlyList<Rectangle> dirty)
    {
        var rects = presented ? dirty : new[] { new Rectangle(0, 0, Monitor.Width, Monitor.Height) };
        presented = true;
        if (rects.Count == 0) return;
        var dst = scratch;                 // POINT
        var size = scratch + 8;            // SIZE
        var src = scratch + 16;            // POINT
        var blend = scratch + 24;          // BLENDFUNCTION
        var rect = scratch + 32;           // RECT
        Marshal.StructureToPtr(new Win32.POINT(Monitor.Left, Monitor.Top), dst, false);
        Marshal.StructureToPtr(new Win32.SIZE(Monitor.Width, Monitor.Height), size, false);
        Marshal.StructureToPtr(new Win32.POINT(0, 0), src, false);
        Marshal.StructureToPtr(new Win32.BLENDFUNCTION { BlendOp = Win32.AC_SRC_OVER, SourceConstantAlpha = 255, AlphaFormat = Win32.AC_SRC_ALPHA }, blend, false);
        foreach (var r in rects)
        {
            Marshal.StructureToPtr(new Win32.RECT(r.Left, r.Top, r.Right, r.Bottom), rect, false);
            var info = new Win32.UPDATELAYEREDWINDOWINFO
            {
                cbSize = (uint)Marshal.SizeOf<Win32.UPDATELAYEREDWINDOWINFO>(),
                pptDst = dst, psize = size, hdcSrc = memoryDc, pptSrc = src, pblend = blend, dwFlags = Win32.ULW_ALPHA,
                prcDirty = dirty.Count == 0 ? IntPtr.Zero : rect,
            };
            Win32.UpdateLayeredWindowIndirect(Hwnd, ref info);
        }
    }

    /// <summary>Clickable only while there is something under the cursor worth clicking.</summary>
    public void SetClickable(bool wanted)
    {
        if (clickable == wanted) return;
        clickable = wanted;
        var style = (uint)(long)Win32.GetWindowLongPtr(Hwnd, Win32.GWL_EXSTYLE);
        style = wanted ? style & ~Win32.WS_EX_TRANSPARENT : style | Win32.WS_EX_TRANSPARENT;
        Win32.SetWindowLongPtr(Hwnd, Win32.GWL_EXSTYLE, (IntPtr)(long)style);
    }

    private IntPtr? WndProc(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        switch (msg)
        {
            case Win32.WM_MOUSEACTIVATE:
                return (IntPtr)Win32.MA_NOACTIVATE;
            case Win32.WM_LBUTTONDOWN:
                Win32.SetCapture(hwnd);
                capturing = true;
                if (Desktop.IsControlDown) Hand?.Invoke(new HandEvent.SecondaryDown(Desktop.Cursor()));
                else Hand?.Invoke(new HandEvent.Down(Desktop.Cursor(), Desktop.IsShiftDown));
                return IntPtr.Zero;
            case Win32.WM_MOUSEMOVE:
                if (capturing) Hand?.Invoke(new HandEvent.Dragged(Desktop.Cursor()));
                return IntPtr.Zero;
            case Win32.WM_LBUTTONUP:
                if (capturing) { capturing = false; Win32.ReleaseCapture(); }
                Hand?.Invoke(new HandEvent.Up(Desktop.Cursor()));
                return IntPtr.Zero;
            case Win32.WM_RBUTTONDOWN:
                Hand?.Invoke(new HandEvent.SecondaryDown(Desktop.Cursor()));
                return IntPtr.Zero;
        }
        return null;
    }

    public void Dispose()
    {
        if (Hwnd != IntPtr.Zero) { Win32.WindowClass.Destroy(Hwnd); Hwnd = IntPtr.Zero; }
        Graphics.Dispose();
        Surface.Dispose();
        Win32.SelectObject(memoryDc, previousBitmap);
        Win32.DeleteObject(dib);
        Win32.DeleteDC(memoryDc);
        Marshal.FreeHGlobal(scratch);
    }
}

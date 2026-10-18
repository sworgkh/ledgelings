using System.Runtime.InteropServices;

namespace Ledgelings.Native;

/// <summary>The few Win32 calls the clipboard manager needs: being told of copies, who made them, the caret,
/// and pressing Ctrl+V for the app in front.</summary>
internal static class ClipboardNative
{
    public const uint WM_CLIPBOARDUPDATE = 0x031D;
    public const byte VK_CONTROL = 0x11, VK_V = 0x56;
    public const uint KEYEVENTF_KEYUP = 0x0002;

    [StructLayout(LayoutKind.Sequential)]
    public struct GUITHREADINFO
    {
        public int cbSize;
        public uint flags;
        public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret;
        public Win32.RECT rcCaret;
    }

    [DllImport("user32.dll", SetLastError = true)] public static extern bool AddClipboardFormatListener(IntPtr hwnd);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool RemoveClipboardFormatListener(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern IntPtr GetClipboardOwner();
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint threadId, ref GUITHREADINFO info);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hwnd, ref Win32.POINT point);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);

    /// <summary>The process name of the window's owner, with ".exe": "KeePassXC.exe"; null when it cannot be told.</summary>
    public static string? ProcessName(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return null;
        GetWindowThreadProcessId(hwnd, out var pid);
        try { using var p = System.Diagnostics.Process.GetProcessById((int)pid); return p.ProcessName + ".exe"; }
        catch (Exception e) when (e is ArgumentException or InvalidOperationException) { return null; }
    }

    /// <summary>The app's own name for the picker ("Notepad"), else its process name.</summary>
    public static string? AppTitle(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return null;
        GetWindowThreadProcessId(hwnd, out var pid);
        try
        {
            using var p = System.Diagnostics.Process.GetProcessById((int)pid);
            var described = p.MainModule?.FileVersionInfo.FileDescription;
            return string.IsNullOrWhiteSpace(described) ? p.ProcessName : described;
        }
        catch (Exception e) when (e is ArgumentException or InvalidOperationException or System.ComponentModel.Win32Exception) { return null; }
    }

    /// <summary>Ctrl+V, pressed and let go, for whatever window has the keyboard.</summary>
    public static void PressPaste()
    {
        keybd_event(VK_CONTROL, 0, 0, UIntPtr.Zero);
        keybd_event(VK_V, 0, 0, UIntPtr.Zero);
        keybd_event(VK_V, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }

    /// <summary>The text caret of the window <paramref name="hwnd"/>'s thread, in screen pixels, when it has one.</summary>
    public static Win32.RECT? Caret(IntPtr hwnd)
    {
        var thread = GetWindowThreadProcessId(hwnd, out _);
        var info = new GUITHREADINFO { cbSize = Marshal.SizeOf<GUITHREADINFO>() };
        if (thread == 0 || !GetGUIThreadInfo(thread, ref info) || info.hwndCaret == IntPtr.Zero) return null;
        var r = info.rcCaret;
        var topLeft = new Win32.POINT(r.Left, r.Top);
        var bottomRight = new Win32.POINT(r.Right, r.Bottom);
        if (!ClientToScreen(info.hwndCaret, ref topLeft) || !ClientToScreen(info.hwndCaret, ref bottomRight)) return null;
        return new Win32.RECT(topLeft.X, topLeft.Y, Math.Max(bottomRight.X, topLeft.X + 1), Math.Max(bottomRight.Y, topLeft.Y + 1));
    }
}

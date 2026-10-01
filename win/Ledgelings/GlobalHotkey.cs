using Ledgelings.Native;

namespace Ledgelings;

/// <summary>One system-wide key combination (<c>RegisterHotKey</c>) and what it does. Registering
/// fails quietly when another app already owns the combination: <see cref="IsRegistered"/> says so.</summary>
public sealed class GlobalHotkey : IDisposable
{
    private static readonly Win32.WindowClass windowClass = new("LedgelingsHotkey");
    private const int Id = 1;
    private readonly IntPtr hwnd;
    private readonly Action pressed;

    public bool IsRegistered { get; }

    public GlobalHotkey(uint modifiers, uint key, Action pressed)
    {
        this.pressed = pressed;
        hwnd = windowClass.Create(0, Win32.WS_POPUP, 0, 0, 0, 0, WndProc);
        IsRegistered = Win32.RegisterHotKey(hwnd, Id, modifiers | Win32.MOD_NOREPEAT, key);
    }

    private IntPtr? WndProc(IntPtr window, uint msg, IntPtr wParam, IntPtr lParam)
    {
        if (msg != Win32.WM_HOTKEY || (int)wParam != Id) return null;
        pressed();
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        if (IsRegistered) Win32.UnregisterHotKey(hwnd, Id);
        Win32.WindowClass.Destroy(hwnd);
    }
}

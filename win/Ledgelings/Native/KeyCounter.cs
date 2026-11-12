using System.Runtime.InteropServices;

namespace Ledgelings.Native;

/// <summary>
/// How many keys have been pressed since it started, for a fast hour of typing (SPEC §7.19). The Mac reads the
/// system's own running count; Windows keeps none, so a low-level keyboard hook adds one per key down. It never
/// looks at which key: nothing is recorded but the number. Needs no permission; on the UI thread, whose message
/// loop the hook runs on.
/// </summary>
internal sealed class KeyCounter : IDisposable
{
    private const int WH_KEYBOARD_LL = 13, WM_KEYDOWN = 0x0100, WM_SYSKEYDOWN = 0x0104;
    private delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, HookProc proc, IntPtr hMod, uint threadId);
    [DllImport("user32.dll")] private static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr GetModuleHandle(string? name);

    private readonly HookProc proc;      // kept alive: the system calls it for as long as the hook stands
    private IntPtr hook;

    /// <summary>Keys pressed since it started.</summary>
    public double Count { get; private set; }
    /// <summary>When the last key went down (<see cref="Environment.TickCount64"/>), null before the first.</summary>
    public long? LastKey { get; private set; }
    /// <summary>Seconds since a key was last pressed, as the Mac's own count says it; null before the first.</summary>
    public double? KeyIdle => LastKey is long at ? (Environment.TickCount64 - at) / 1000.0 : null;

    private KeyCounter()
    {
        proc = Hooked;
        hook = SetWindowsHookEx(WH_KEYBOARD_LL, proc, GetModuleHandle(null), 0);
    }

    /// <summary>A counter, or null where the hook was refused (or off Windows).</summary>
    public static KeyCounter? Start()
    {
        if (!OperatingSystem.IsWindows()) return null;
        var counter = new KeyCounter();
        if (counter.hook != IntPtr.Zero) return counter;
        counter.Dispose();
        return null;
    }

    private IntPtr Hooked(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code >= 0 && (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN)) { Count += 1; LastKey = Environment.TickCount64; }
        return CallNextHookEx(hook, code, wParam, lParam);
    }

    public void Dispose()
    {
        if (hook != IntPtr.Zero) UnhookWindowsHookEx(hook);
        hook = IntPtr.Zero;
    }
}

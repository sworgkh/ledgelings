using System.Drawing;
using System.Runtime.InteropServices;
using Ledgelings.Native;

namespace Ledgelings;

/// <summary>The icon in the notification area and its menu, rebuilt every time it opens
/// so the clock lines and the talk status are current.</summary>
public sealed class TrayIcon : IDisposable
{
    public sealed record Item(string Text, Action? Action = null, bool Enabled = true, bool IsSeparator = false)
    {
        public static readonly Item Separator = new("", null, false, true);
    }

    private static readonly Win32.WindowClass windowClass = new("LedgelingsTray");
    private const uint CallbackMessage = Win32.WM_USER + 1;
    private const uint NIN_SELECT = Win32.WM_USER + 0;
    private const uint NIN_KEYSELECT = Win32.WM_USER + 1;

    /// <summary>Called when the menu is about to open; returns its items, top to bottom.</summary>
    public Func<IReadOnlyList<Item>>? MenuBuilder { get; set; }

    private readonly IntPtr hwnd;
    private readonly IntPtr icon;
    private readonly string tip;
    private readonly uint taskbarCreated;
    private bool menuOpen;

    public TrayIcon(Bitmap image, string tip)
    {
        this.tip = tip;
        icon = image.GetHicon();
        taskbarCreated = RegisterWindowMessageW("TaskbarCreated");
        hwnd = windowClass.Create(0, Win32.WS_POPUP, 0, 0, 0, 0, WndProc);
        Notify(Win32.NIM_ADD);
        var data = Data();
        data.uTimeoutOrVersion = Win32.NOTIFYICON_VERSION_4;
        Win32.Shell_NotifyIconW(Win32.NIM_SETVERSION, ref data);
    }

    private Win32.NOTIFYICONDATAW Data() => new()
    {
        cbSize = (uint)Marshal.SizeOf<Win32.NOTIFYICONDATAW>(),
        hWnd = hwnd,
        uID = 1,
        uFlags = Win32.NIF_MESSAGE | Win32.NIF_ICON | Win32.NIF_TIP,
        uCallbackMessage = CallbackMessage,
        hIcon = icon,
        szTip = tip,
        szInfo = "",
        szInfoTitle = "",
    };

    private void Notify(uint message)
    {
        var data = Data();
        Win32.Shell_NotifyIconW(message, ref data);
    }

    private IntPtr? WndProc(IntPtr window, uint msg, IntPtr wParam, IntPtr lParam)
    {
        if (msg == CallbackMessage)
        {
            var what = (uint)((long)lParam & 0xFFFF);
            if (what is Win32.WM_CONTEXTMENU or Win32.WM_LBUTTONUP or Win32.WM_RBUTTONUP or NIN_SELECT or NIN_KEYSELECT) ShowMenu();
            return IntPtr.Zero;
        }
        if (msg == taskbarCreated)
        {
            Notify(Win32.NIM_ADD);       // Explorer restarted: put the icon back
            return IntPtr.Zero;
        }
        return null;
    }

    private void ShowMenu()
    {
        if (menuOpen) return;
        var items = MenuBuilder?.Invoke() ?? Array.Empty<Item>();
        if (items.Count == 0) return;
        var menu = Win32.CreatePopupMenu();
        for (int i = 0; i < items.Count; i++)
        {
            var item = items[i];
            if (item.IsSeparator) { Win32.AppendMenuW(menu, Win32.MF_SEPARATOR, UIntPtr.Zero, null); continue; }
            var flags = Win32.MF_STRING | (item.Enabled ? 0 : Win32.MF_GRAYED);
            Win32.AppendMenuW(menu, flags, (UIntPtr)(i + 1), item.Text.Replace("&", "&&"));
        }
        menuOpen = true;
        try
        {
            // The menu closes when the user clicks elsewhere only if its window is in front.
            Win32.SetForegroundWindow(hwnd);
            Win32.GetCursorPos(out var at);
            var chosen = Win32.TrackPopupMenuEx(menu, Win32.TPM_RETURNCMD | Win32.TPM_RIGHTBUTTON | Win32.TPM_BOTTOMALIGN, at.X, at.Y, hwnd, IntPtr.Zero);
            Win32.PostMessageW(hwnd, 0, IntPtr.Zero, IntPtr.Zero);
            if (chosen > 0 && chosen <= items.Count) items[chosen - 1].Action?.Invoke();
        }
        finally
        {
            menuOpen = false;
            Win32.DestroyMenu(menu);
        }
    }

    public void Dispose()
    {
        Notify(Win32.NIM_DELETE);
        Win32.DestroyIcon(icon);
        Win32.WindowClass.Destroy(hwnd);
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern uint RegisterWindowMessageW(string name);
}

using Ledgelings.Core;
using Ledgelings.Native;

namespace Ledgelings;

/// <summary>The real mouse pointer, for a creature that has grabbed it (<c>Colony.Revenge</c>).
/// Points are simulation points, like <see cref="Desktop.Cursor"/>.</summary>
public interface IPointerHold
{
    /// <summary>Keep the pointer at <paramref name="point"/> and start listening for Escape. False when the
    /// pointer cannot be moved: the creature then only clings to it.</summary>
    bool Pin(Pt point);
    /// <summary>Put the pointer back on <paramref name="point"/> after the user moved it.</summary>
    void Hold(Pt point);
    /// <summary>Stop holding and listening.</summary>
    void Release();
    /// <summary>The user pressed Escape.</summary>
    Action? OnEscape { get; set; }
}

/// <summary>Holds the pointer by moving it back each frame the user moves it (<c>SetCursorPos</c>), which needs
/// no permission. Nothing is ever clipped or detached, so if the app stops for any reason the pointer is simply
/// free. While it holds, Escape is a system-wide hotkey (<c>RegisterHotKey</c>, no permission either), so it
/// lets go whichever app is in front; for those few seconds Escape goes to Ledgelings, not to that app. If
/// another app already owns a bare Escape hotkey, shaking or the longest hold still let go.</summary>
public sealed class SystemPointer : IPointerHold
{
    private GlobalHotkey? escape;
    public Action? OnEscape { get; set; }

    public bool Pin(Pt point)
    {
        if (!Warp(point)) return false;      // the secure desktop (a UAC prompt, the lock screen) refuses
        Release();
        try { escape = new GlobalHotkey(0, Win32.VK_ESCAPE, () => OnEscape?.Invoke()); }
        catch (Exception) { escape = null; }      // no Escape this time; shaking and the longest hold still work
        return true;
    }

    public void Hold(Pt point) => Warp(point);

    public void Release()
    {
        escape?.Dispose();
        escape = null;
    }

    private static bool Warp(Pt point) => Win32.SetCursorPos((int)Math.Round(point.X), (int)Math.Round(-point.Y));

    /// <summary>Whether a mouse button is down: nobody grabs the cursor mid-drag.</summary>
    public static bool AnyButtonDown =>
        new[] { Win32.VK_LBUTTON, Win32.VK_RBUTTON, Win32.VK_MBUTTON }.Any(k => (Win32.GetAsyncKeyState(k) & 0x8000) != 0);
}

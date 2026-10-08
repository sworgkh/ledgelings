using System.Windows.Input;
using Ledgelings.Core;
using Ledgelings.Native;

namespace Ledgelings;

/// <summary>The shortcut from any app between its three worlds: our saved bits, Win32's
/// <c>RegisterHotKey</c>, and the keys WPF reports while one is recorded.</summary>
public static class ShortcutKeys
{
    public static uint Win32Modifiers(ShortcutModifiers m) =>
        (m.HasFlag(ShortcutModifiers.Option) ? Win32.MOD_ALT : 0) | (m.HasFlag(ShortcutModifiers.Control) ? Win32.MOD_CONTROL : 0)
        | (m.HasFlag(ShortcutModifiers.Shift) ? Win32.MOD_SHIFT : 0) | (m.HasFlag(ShortcutModifiers.Command) ? Win32.MOD_WIN : 0);

    public static ShortcutModifiers From(ModifierKeys keys) =>
        (keys.HasFlag(ModifierKeys.Alt) ? ShortcutModifiers.Option : 0) | (keys.HasFlag(ModifierKeys.Control) ? ShortcutModifiers.Control : 0)
        | (keys.HasFlag(ModifierKeys.Shift) ? ShortcutModifiers.Shift : 0) | (keys.HasFlag(ModifierKeys.Windows) ? ShortcutModifiers.Command : 0);

    /// <summary>A key that is only a modifier being held: not yet a shortcut, nothing to beep about.</summary>
    public static bool IsModifier(Key key) => key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt
        or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin or Key.System or Key.None;

    /// <summary>What is printed on the key: "L", "7", "F12", "Space".</summary>
    public static string KeyName(int keyCode)
    {
        var key = KeyInterop.KeyFromVirtualKey(keyCode);
        return key switch
        {
            >= Key.A and <= Key.Z => key.ToString(),
            >= Key.D0 and <= Key.D9 => ((int)(key - Key.D0)).ToString(),
            Key.None => L10n.Tr("key %d", keyCode),
            Key.Return => "Enter",
            Key.Back => "Backspace",
            Key.OemComma => ",",
            Key.OemPeriod => ".",
            Key.OemMinus => "-",
            Key.OemPlus => "=",
            _ => key.ToString(),
        };
    }

    public static string Label(Shortcut shortcut) => shortcut.Label(KeyName(shortcut.KeyCode));
}

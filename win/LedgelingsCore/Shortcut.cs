namespace Ledgelings.Core;

/// <summary>The modifier keys of a shortcut, in bits of our own (the Mac's too), so a saved
/// shortcut means the same whichever toolkit registers it. Command is the Windows key here, Option is Alt.</summary>
[Flags]
public enum ShortcutModifiers { None = 0, Command = 1, Shift = 2, Option = 4, Control = 8 }

/// <summary>
/// The system-wide keyboard shortcut (SPEC §11): a key and the modifier keys held with it.
/// It is how the owner reaches the creatures when the tray has no room for the icon. The
/// key is the platform's own key number: a virtual-key code here.
/// </summary>
public readonly record struct Shortcut(int KeyCode, ShortcutModifiers Modifiers)
{
    public const int MinKeyCode = 1, MaxKeyCode = 254;
    private const ShortcutModifiers All = ShortcutModifiers.Command | ShortcutModifiers.Shift | ShortcutModifiers.Option | ShortcutModifiers.Control;

    /// <summary>Ctrl+Alt+L, L for Ledgelings, beside Ctrl+Alt+R for a reminder: Windows itself uses neither.</summary>
    public static readonly Shortcut Standard = new(0x4C, ShortcutModifiers.Control | ShortcutModifiers.Option);

    /// <summary>As it was saved, or the standard one when what was saved cannot be a shortcut.</summary>
    public static Shortcut Saved(int? keyCode, int? modifiers)
    {
        var made = new Shortcut(keyCode ?? Standard.KeyCode, (ShortcutModifiers)(modifiers ?? (int)Standard.Modifiers) & All);
        return made.IsUsable ? made : Standard;
    }

    /// <summary>A shortcut taken from every app must not be a key someone types: it needs
    /// Ctrl, Alt or the Windows key held. Shift alone is a capital letter.</summary>
    public bool IsUsable => KeyCode is >= MinKeyCode and <= MaxKeyCode
        && (Modifiers & (ShortcutModifiers.Command | ShortcutModifiers.Control | ShortcutModifiers.Option)) != 0;

    /// <summary>The modifiers as Windows writes them, in its order: "Ctrl+Alt+Shift+Win+".</summary>
    public string Names =>
        (Modifiers.HasFlag(ShortcutModifiers.Control) ? "Ctrl+" : "") + (Modifiers.HasFlag(ShortcutModifiers.Option) ? "Alt+" : "")
        + (Modifiers.HasFlag(ShortcutModifiers.Shift) ? "Shift+" : "") + (Modifiers.HasFlag(ShortcutModifiers.Command) ? "Win+" : "");

    /// <summary>The whole shortcut for a label, given the key's name: "Ctrl+Alt+L".</summary>
    public string Label(string key) => Names + key;
}

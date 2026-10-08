namespace Ledgelings.Core.Tests;

/// <summary>The shortcut from any app (§11): what can be one, and how it reads.</summary>
public class ShortcutTests
{
    private const ShortcutModifiers Win = ShortcutModifiers.Command, Shift = ShortcutModifiers.Shift, Alt = ShortcutModifiers.Option, Ctrl = ShortcutModifiers.Control;

    [Fact]
    public void AShortcutNeedsCommandControlOrOptionHeld()
    {
        Assert.True(Shortcut.Standard.IsUsable);
        Assert.True(new Shortcut(0x41, Win).IsUsable);
        Assert.True(new Shortcut(0x41, Alt | Shift).IsUsable);
        Assert.False(new Shortcut(0x41, ShortcutModifiers.None).IsUsable);
        Assert.False(new Shortcut(0x41, Shift).IsUsable);
        Assert.False(new Shortcut(255, Ctrl).IsUsable);
        Assert.False(new Shortcut(0, Ctrl).IsUsable);
    }

    [Fact]
    public void WhatWasSavedIsKeptWhenItCanBeAShortcutElseTheStandardOne()
    {
        Assert.Equal(Shortcut.Standard, Shortcut.Saved(null, null));
        Assert.Equal(new Shortcut(0x20, Win | Shift), Shortcut.Saved(0x20, 1 | 2));
        Assert.Equal(Shortcut.Standard, Shortcut.Saved(0x20, 2));
        Assert.Equal(Shortcut.Standard, Shortcut.Saved(400, 1));
        // Bits that are no modifier of ours are dropped, not kept to confuse a later version.
        Assert.Equal(Win, Shortcut.Saved(0x20, 1 | 64).Modifiers);
    }

    [Fact]
    public void ModifiersAreWrittenInWindowsOrder()
    {
        Assert.Equal(new Shortcut(0x4C, Ctrl | Alt), Shortcut.Standard);
        Assert.Equal("Ctrl+Alt+L", Shortcut.Standard.Label("L"));
        Assert.Equal("Ctrl+Alt+Shift+Win+", new Shortcut(0x41, Win | Shift | Alt | Ctrl).Names);
    }
}

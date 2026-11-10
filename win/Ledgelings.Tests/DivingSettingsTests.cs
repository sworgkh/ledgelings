using Ledgelings.Core;
using Ledgelings.Native;
using Ledgelings.UI;

namespace Ledgelings.Tests;

/// <summary>Settings › Diving and Stop activity (SPEC §7.17): the defaults, a change surviving a relaunch, clamping, the
/// shortcut's key and the Activities row. The Mac's DivingSettingsTests; the colony's dive is the core's DiveTests.</summary>
public class DivingSettingsTests
{
    [Fact]
    public void TheDefaultsAndAChangeSurviveARelaunch()
    {
        var store = new MemorySettingsStore();
        var secrets = new MemorySecretStore();
        var s = new AppSettings(store, secrets);
        Assert.True(Math.Abs(s.DiveWaterShare - 1.0 / 3) < 1e-9 && s.DiveWaterOpacity == 0.3 && s.DiveMinutes == 3);
        Assert.True(s.DiveDivers == 3 && s.DiveSeaLife == 12 && !s.DiveAllScreens && s.DiveHomeOnly && s.DiveTalk);
        Assert.True(s.StopActivityShortcutEnabled && s.StopActivityShortcut == Shortcut.StopActivity && s.StopButtonShown);
        Assert.Equal(33, s.DiveWaterPercent);
        s.DiveWaterPercent = 50; s.DiveWaterOpacityPercent = 60; s.DiveMinutes = 8; s.DiveDivers = 6; s.DiveSeaLife = 30;
        s.DiveHomeOnly = false; s.DiveTalk = false; s.StopButtonShown = false; s.StopActivityShortcutEnabled = false;
        s.StopActivityShortcut = new Shortcut(0x50, ShortcutModifiers.Control | ShortcutModifiers.Option);
        var again = new AppSettings(store, secrets);
        Assert.True(again.DiveWaterShare == 0.5 && again.DiveWaterOpacity == 0.6 && again.DiveMinutes == 8);
        Assert.True(again.DiveDivers == 6 && again.DiveSeaLife == 30 && again.DiveAllScreens && !again.DiveTalk);
        Assert.True(!again.StopButtonShown && !again.StopActivityShortcutEnabled);
        Assert.Equal(new Shortcut(0x50, ShortcutModifiers.Control | ShortcutModifiers.Option), again.StopActivityShortcut);
        foreach (var (key, value) in new[] { ("diveWaterShare", 0.99), ("diveWaterOpacity", 1.0), ("diveMinutes", 999.0) }) store.Set(key, value);
        store.Set("diveDivers", 50); store.Set("diveSeaLife", 0);
        var clamped = new AppSettings(store, secrets);
        Assert.True(clamped.DiveWaterShare == 0.6 && clamped.DiveWaterOpacity == 0.7 && clamped.DiveMinutes == 15);      // clamped on load
        Assert.True(clamped.DiveDivers == 8 && clamped.DiveSeaLife == 3);
    }

    [Fact]
    public void StopActivityIsCtrlAltQAndTheDiveRowSaysHowToStartAndStopItInWords()
    {
        Assert.Equal(new Shortcut(0x51, ShortcutModifiers.Control | ShortcutModifiers.Option), Shortcut.StopActivity);
        Assert.Equal("Ctrl+Alt+Q", ShortcutKeys.Label(Shortcut.StopActivity));
        Assert.Equal("Ctrl + Alt + Q", ShortcutKeys.Spoken(Shortcut.StopActivity));
        Assert.Equal("Ctrl + Win + Escape", ShortcutKeys.Spoken(new Shortcut(0x1B, ShortcutModifiers.Control | ShortcutModifiers.Command)));
        foreach (var activity in HandActivities.All)
        {
            var key = activity.ActivityKey().ToString();
            Assert.EndsWith($"({key})", activity.ActivityTip(new ActionsState()));
            Assert.Equal($"Stop now ({key} · Ctrl + Alt + Q)", activity.ActivityTip(new ActionsState(Diving: true, StopShortcut: "Ctrl + Alt + Q")));
            Assert.Equal("they are hiding", activity.ActivityDetail(new ActionsState(Hiding: true)));
        }
    }

    [Fact]
    public void TheOldDefaultKeyBecomesCtrlAltQButAKeyOfTheOwnersStays()
    {
        var store = new MemorySettingsStore();
        var secrets = new MemorySecretStore();
        store.Set("stopActivityShortcutKeyCode", 0x1B); store.Set("stopActivityShortcutModifiers", (int)(ShortcutModifiers.Control | ShortcutModifiers.Option));
        Assert.Equal(Shortcut.StopActivity, new AppSettings(store, secrets).StopActivityShortcut);
        store.Set("stopActivityShortcutModifiers", (int)(ShortcutModifiers.Control | ShortcutModifiers.Option | ShortcutModifiers.Shift));
        Assert.Equal(new Shortcut(0x1B, ShortcutModifiers.Control | ShortcutModifiers.Option | ShortcutModifiers.Shift), new AppSettings(store, secrets).StopActivityShortcut);
    }

    [Fact]
    public void StopWhenIUseTheComputerIsGoneAndItsSavedKeyWithIt()
    {
        var store = new MemorySettingsStore();
        store.Set("stopOnUse", true);
        _ = new AppSettings(store, new MemorySecretStore());
        Assert.Null(store.Get<bool?>("stopOnUse"));
    }

    /// <summary>As the screenshot toolbar's: the button is a picture of what it does and names its key on hover.</summary>
    [Fact]
    public void TheStopButtonHasItsPictureAndItsTag()
    {
        using var plain = StopButtonPainter.Button("Stop · Ctrl + Alt + Q", hovered: false);
        using var hovered = StopButtonPainter.Button("Stop · Ctrl + Alt + Q", hovered: true);
        Assert.NotNull(plain);
        Assert.True(plain!.Width > plain.Height * 4 && hovered!.Width == plain.Width);
        Assert.NotEqual(plain.GetPixel(plain.Width - 4, 3), hovered.GetPixel(hovered.Width - 4, 3));      // lighter under the pointer
        using var tag = StopButtonPainter.Tag(StopButton.Tag("Ctrl + Alt + Q"));
        Assert.NotNull(tag);
    }
}

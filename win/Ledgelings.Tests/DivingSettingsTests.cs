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
        Assert.True(s.StopActivityShortcutEnabled && s.StopActivityShortcut == Shortcut.StopActivity && s.StopOnUse);
        Assert.Equal(33, s.DiveWaterPercent);
        s.DiveWaterPercent = 50; s.DiveWaterOpacityPercent = 60; s.DiveMinutes = 8; s.DiveDivers = 6; s.DiveSeaLife = 30;
        s.DiveHomeOnly = false; s.DiveTalk = false; s.StopOnUse = false; s.StopActivityShortcutEnabled = false;
        s.StopActivityShortcut = new Shortcut(0x51, ShortcutModifiers.Control | ShortcutModifiers.Option);
        var again = new AppSettings(store, secrets);
        Assert.True(again.DiveWaterShare == 0.5 && again.DiveWaterOpacity == 0.6 && again.DiveMinutes == 8);
        Assert.True(again.DiveDivers == 6 && again.DiveSeaLife == 30 && again.DiveAllScreens && !again.DiveTalk);
        Assert.True(!again.StopOnUse && !again.StopActivityShortcutEnabled);
        Assert.Equal(new Shortcut(0x51, ShortcutModifiers.Control | ShortcutModifiers.Option), again.StopActivityShortcut);
        foreach (var (key, value) in new[] { ("diveWaterShare", 0.99), ("diveWaterOpacity", 1.0), ("diveMinutes", 999.0) }) store.Set(key, value);
        store.Set("diveDivers", 50); store.Set("diveSeaLife", 0);
        var clamped = new AppSettings(store, secrets);
        Assert.True(clamped.DiveWaterShare == 0.6 && clamped.DiveWaterOpacity == 0.7 && clamped.DiveMinutes == 15);      // clamped on load
        Assert.True(clamped.DiveDivers == 8 && clamped.DiveSeaLife == 3);
    }

    [Fact]
    public void StopActivityIsCtrlAltEscAndTheDiveRowSaysHowToStartAndStopIt()
    {
        Assert.Equal(new Shortcut(0x1B, ShortcutModifiers.Control | ShortcutModifiers.Option), Shortcut.StopActivity);
        foreach (var activity in HandActivities.All)
        {
            var key = activity.ActivityKey().ToString();
            Assert.EndsWith($"({key})", activity.ActivityTip(new ActionsState()));
            Assert.Equal($"Stop now ({key} · Ctrl+Alt+Esc)", activity.ActivityTip(new ActionsState(Diving: true, StopShortcut: "Ctrl+Alt+Esc")));
            Assert.Equal("they are hiding", activity.ActivityDetail(new ActionsState(Hiding: true)));
        }
    }

    [Fact]
    public void UsingTheComputerStopsARunningActivityOnlyWhenThatIsOn()
    {
        var s = new AppSettings(new MemorySettingsStore(), new MemorySecretStore());
        var running = true;
        var stops = 0;
        Activities.Shared.Register(Activities.Kind.Dive, () => running, () => { running = false; stops++; });
        try
        {
            using var watch = new UseWatch(s);
            var pressed = (Key: false, Click: false);
            watch.Pressed = () => pressed;
            var t = DateTime.Now;
            watch.Check(t);
            watch.Check(t.AddSeconds(3));
            Assert.True(running);                   // nothing pressed: moving the mouse is not using it
            s.StopOnUse = false;
            pressed = (true, false);
            watch.Check(t.AddSeconds(4));
            Assert.True(running);                   // off: a key does not stop it
            s.StopOnUse = true;
            watch.Check(t.AddSeconds(5));
            Assert.False(running);                  // on: a key stops it
            Assert.Equal(1, stops);
        }
        finally { Activities.Shared.Unregister(Activities.Kind.Dive); }
    }
}

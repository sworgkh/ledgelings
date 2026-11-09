using Ledgelings.Core;
using Ledgelings.Native;
using Ledgelings.UI;

namespace Ledgelings.Tests;

/// <summary>Settings › Surfing (SPEC §7.10): the defaults, a change surviving a relaunch, clamping, its row on the
/// Activities page and Stop activity. The Mac's PlaySettingsTests for surfing; the game itself is the core's SurfTests.</summary>
public class SurfingSettingsTests
{
    [Fact]
    public void TheSurfingSettingsHaveDefaultsSurviveARelaunchAndAreClamped()
    {
        var store = new MemorySettingsStore();
        var secrets = new MemorySecretStore();
        var s = new AppSettings(store, secrets);
        Assert.True(s.PlaySurfEnabled && s.EnabledPlays.Contains(Plays.Kind.Surf));
        Assert.True(s.SurfEveryMinutes == 30 && s.SurfMinutes == 2 && s.SurfWaves == 5 && s.SurfWaveHeight == 2 && s.SurfPlayers == 5);
        Assert.True(s.SurfWaterOpacity == 55 && s.BallGameEvery(Plays.Kind.Surf) == 30 && s.BallGamePlayers[Plays.Kind.Surf] == 5);
        s.PlaySurfEnabled = false; s.SurfEveryMinutes = 60; s.SurfMinutes = 3.5; s.SurfWaves = 9; s.SurfWaveHeight = 3; s.SurfPlayers = 2;
        s.SurfWaterOpacity = 40;
        var again = new AppSettings(store, secrets);
        Assert.True(!again.PlaySurfEnabled && !again.EnabledPlays.Contains(Plays.Kind.Surf));
        Assert.True(again.SurfEveryMinutes == 60 && again.SurfMinutes == 3.5 && again.SurfWaves == 9 && again.SurfWaveHeight == 3 && again.SurfPlayers == 2);
        Assert.Equal(40, again.SurfWaterOpacity);
        foreach (var (key, value) in new[] { ("surfEveryMinutes", 0.0), ("surfMinutes", 99.0), ("surfWaveHeight", 0.1), ("surfWaterOpacity", 100.0) }) store.Set(key, value);
        foreach (var (key, value) in new[] { ("surfWaves", 0), ("surfPlayers", 40) }) store.Set(key, value);
        var clamped = new AppSettings(store, secrets);
        Assert.True(clamped.SurfEveryMinutes == 2 && clamped.SurfMinutes == 10 && clamped.SurfWaveHeight == 1 && clamped.SurfWaterOpacity == 90);      // clamped on load
        Assert.True(clamped.SurfWaves == 1 && clamped.SurfPlayers == 10);
        clamped.SurfWaterOpacity = 5;
        Assert.Equal(20, clamped.SurfWaterOpacity);                                                                     // and on change
    }

    [Fact]
    public void SurfingHasItsRowOnTheActivitiesPageAsAGame()
    {
        Languages.With(Language.English, () =>
        {
            Assert.Equal("SURFING", Plays.Kind.Surf.ActivityTitle());
            Assert.Equal(System.Windows.Input.Key.V, Plays.Kind.Surf.ActivityKey());
            Assert.Equal("Start now: surfing on a wave along the bottom edge (V)", Plays.Kind.Surf.ActivityTip());
            Assert.Equal("The tide comes in along the bottom edge: waves to ride, tricks, wipe-outs, a score.", Plays.Kind.Surf.ActivityLine());
        });
        Assert.NotNull(ActionIcons.Game(Plays.Kind.Surf));                                     // Blocky's board
        Assert.Equal(Plays.AllKinds.Count + HandActivities.All.Count, ActionsSheet.ActivityRows);   // a game, not a hand activity: listed once
        Languages.With(Language.Russian, () => Assert.Equal("СЕРФИНГ", Plays.Kind.Surf.ActivityTitle()));
    }

    [Fact]
    public void StopActivityStopsASurfAtOnce()
    {
        var running = true;
        Activities.Shared.Register(Activities.Kind.Surf, () => running, () => running = false);
        try
        {
            Assert.Contains(Activities.Kind.Surf, Activities.Shared.Running);
            Assert.Contains(Activities.Kind.Surf, Activities.Shared.StopAll());
            Assert.False(running);
            Assert.False(Activities.Shared.IsKindRunning(Activities.Kind.Surf));
        }
        finally { Activities.Shared.Unregister(Activities.Kind.Surf); }
    }
}

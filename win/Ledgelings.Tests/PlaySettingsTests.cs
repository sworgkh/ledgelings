using Ledgelings.Native;
using Ledgelings.UI;

namespace Ledgelings.Tests;

/// <summary>The Play tab's settings, and the Activities page of the Creature Actions sheet. The Mac's PlaySettingsTests.</summary>
public class PlaySettingsTests
{
    [Fact]
    public void TheDefaultsAndAChangeSurviveARelaunch()
    {
        var store = new MemorySettingsStore();
        var secrets = new MemorySecretStore();
        var s = new AppSettings(store, secrets);
        Assert.True(s.PlayEnabled && s.PlayTagEnabled && s.PlayRopeEnabled && s.PlayParachuteEnabled && s.PlayBasketballEnabled && s.PlayTalk);
        Assert.True(s.PlayEveryMinutes == 5 && s.PlayBondBoost == 100 && s.TagSeconds == 25);
        Assert.True(s.ParachuteFallSpeed == 70 && s.BallBounce == 60 && s.BasketballThrows == 3);
        Assert.True(s.EnabledPlays.SetEquals(Plays.AllKinds));
        s.PlayEnabled = false; s.PlayTagEnabled = false; s.PlayRopeEnabled = false; s.PlayParachuteEnabled = false;
        s.PlayBasketballEnabled = false; s.PlayTalk = false;
        s.PlayEveryMinutes = 12; s.PlayBondBoost = 250; s.TagSeconds = 60;
        s.ParachuteFallSpeed = 40; s.BallBounce = 80; s.BasketballThrows = 7;
        var again = new AppSettings(store, secrets);
        Assert.True(!again.PlayEnabled && !again.PlayTagEnabled && !again.PlayRopeEnabled && !again.PlayParachuteEnabled);
        Assert.True(!again.PlayBasketballEnabled && !again.PlayTalk && again.EnabledPlays.Count == 0);
        Assert.True(again.PlayEveryMinutes == 12 && again.PlayBondBoost == 250 && again.TagSeconds == 60);
        Assert.True(again.ParachuteFallSpeed == 40 && again.BallBounce == 80 && again.BasketballThrows == 7);
        foreach (var (key, value) in new[] { ("playEveryMinutes", 0.0), ("playBondBoost", 999.0), ("tagSeconds", 1.0), ("parachuteFallSpeed", 5000.0), ("ballBounce", 100.0) })
            store.Set(key, value);
        store.Set("basketballThrows", 50);
        var clamped = new AppSettings(store, secrets);
        Assert.True(clamped.PlayEveryMinutes == 1 && clamped.PlayBondBoost == 300 && clamped.TagSeconds == 10);      // clamped on load
        Assert.True(clamped.ParachuteFallSpeed == 200 && clamped.BallBounce == 90 && clamped.BasketballThrows == 10);
    }

    [Fact]
    public void TheActivitiesPageHasARowForEveryGameAndTheSheetStaysLean()
    {
        Assert.Equal(8, ActionsTiles.All.Count);                                               // no game tiles on the sheet itself
        var s = new ActionsState();
        Assert.All(Plays.AllKinds, k => Assert.True(k.ActivityDetail(s) is null && k.ActivityLine().Length > 0 && ActionIcons.Game(k) is not null));
        s = s with { PlaysOff = new HashSet<Plays.Kind> { Plays.Kind.Rope } };
        Assert.True(Plays.Kind.Rope.ActivityDetail(s) == "off in settings" && Plays.Kind.Tag.ActivityDetail(s) is null);
        s = s with { PlaysOff = null, Playing = true };
        Assert.Equal("one at a time", Plays.Kind.Tag.ActivityDetail(s));
        s = s with { Hiding = true };
        Assert.Equal("they are hiding", Plays.Kind.Tag.ActivityDetail(s));
        var keys = Plays.AllKinds.Select(k => k.ActivityKey()).ToList();
        Assert.Equal(4, keys.Distinct().Count());
        Assert.Empty(keys.Intersect(ActionsTiles.All.Select(t => t.Key()).Append(System.Windows.Input.Key.A)));   // its own keys
        Assert.Equal("PLAY ON", ActionsSwitch.Play.Title(new ActionsState()));
        Assert.True(ActionsSwitch.Play.Title(s) == "PLAY ON" && ActionsSwitch.Play.Said(s) == "They play now and then.");
        Assert.Equal("PLAY OFF", ActionsSwitch.Play.Title(s with { PlayOn = false }));
    }
}

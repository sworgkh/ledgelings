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
        s.PlayBasketballEnabled = false; s.PlayTalk = false; s.PlaySoccerEnabled = false; s.PlayBaseballEnabled = false;
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
    public void TheBallGamesSettingsHaveDefaultsSurviveARelaunchAndAreClamped()
    {
        var store = new MemorySettingsStore();
        var secrets = new MemorySecretStore();
        var s = new AppSettings(store, secrets);
        Assert.True(s.PlaySoccerEnabled && s.PlayBaseballEnabled);
        Assert.True(s.SoccerEveryMinutes == 20 && s.BaseballEveryMinutes == 20 && s.SoccerMinutes == 2 && s.SoccerGoals == 3);
        Assert.True(s.BaseballInnings == 2 && s.SoccerPlayers == 6 && s.BaseballPlayers == 6);
        Assert.True(s.BallGamePlayers[Plays.Kind.Soccer] == 6 && s.BallGamePlayers[Plays.Kind.Baseball] == 6 && s.BallGameEvery(Plays.Kind.Baseball) == 20);
        s.PlaySoccerEnabled = false; s.PlayBaseballEnabled = false;
        s.SoccerEveryMinutes = 45; s.BaseballEveryMinutes = 90; s.SoccerMinutes = 4.5; s.SoccerGoals = 5;
        s.BaseballInnings = 4; s.SoccerPlayers = 3; s.BaseballPlayers = 9;
        var again = new AppSettings(store, secrets);
        Assert.True(!again.PlaySoccerEnabled && !again.PlayBaseballEnabled && !again.EnabledPlays.Contains(Plays.Kind.Soccer));
        Assert.True(again.SoccerEveryMinutes == 45 && again.BaseballEveryMinutes == 90 && again.SoccerMinutes == 4.5 && again.SoccerGoals == 5);
        Assert.True(again.BaseballInnings == 4 && again.SoccerPlayers == 3 && again.BaseballPlayers == 9);
        foreach (var (key, value) in new[] { ("soccerEveryMinutes", 0.0), ("baseballEveryMinutes", 9999.0), ("soccerMinutes", 99.0) }) store.Set(key, value);
        foreach (var (key, value) in new[] { ("soccerGoals", 0), ("baseballInnings", 50), ("soccerPlayers", 0), ("baseballPlayers", 40) }) store.Set(key, value);
        var clamped = new AppSettings(store, secrets);
        Assert.True(clamped.SoccerEveryMinutes == 2 && clamped.BaseballEveryMinutes == 240 && clamped.SoccerMinutes == 10);      // clamped on load
        Assert.True(clamped.SoccerGoals == 1 && clamped.BaseballInnings == 9 && clamped.SoccerPlayers == 1 && clamped.BaseballPlayers == 10);
    }

    [Fact]
    public void ABallGameWaitsItsTurn()
    {
        var s = new AppSettings(new MemorySettingsStore(), new MemorySecretStore());
        var ended = new Dictionary<Plays.Kind, double>();
        Assert.True(Colony.BallGamesDueAt(s, ended, 0).SetEquals(new[] { Plays.Kind.Soccer, Plays.Kind.Baseball }));
        ended[Plays.Kind.Soccer] = 100;
        Assert.True(Colony.BallGamesDueAt(s, ended, 100).SetEquals(new[] { Plays.Kind.Baseball }), "soccer only every so often");
        Assert.Contains(Plays.Kind.Soccer, Colony.BallGamesDueAt(s, ended, 100 + 20 * 60));
        s.PlayBaseballEnabled = false;
        Assert.DoesNotContain(Plays.Kind.Baseball, Colony.BallGamesDueAt(s, ended, 0));
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
        Assert.Equal(Plays.AllKinds.Count, keys.Distinct().Count());
        Assert.Empty(keys.Intersect(ActionsTiles.All.Select(t => t.Key()).Append(System.Windows.Input.Key.A)));   // its own keys
        Assert.Equal("PLAY ON", ActionsSwitch.Play.Title(new ActionsState()));
        Assert.True(ActionsSwitch.Play.Title(s) == "PLAY ON" && ActionsSwitch.Play.Said(s) == "They play now and then.");
        Assert.Equal("PLAY OFF", ActionsSwitch.Play.Title(s with { PlayOn = false }));
    }
}

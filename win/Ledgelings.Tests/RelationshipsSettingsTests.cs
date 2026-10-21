using Ledgelings.Native;
using Ledgelings.UI;

namespace Ledgelings.Tests;

/// <summary>The Relationships tab's settings: the Mac's RelationshipsSettingsTests. Its colony tests (a built-in
/// invitation starting the game, a no remembered, what a prompt carries) need a colony on screen, which the
/// Windows tests never make (README › Not on Windows).</summary>
public class RelationshipsSettingsTests
{
    [Fact]
    public void TheOldDefaultMovesToTheNewOnceAndAChosenValueStays()
    {
        var store = new MemorySettingsStore();
        var secrets = new MemorySecretStore();
        store.Set("memoryTokens", 150);
        Assert.Equal(600, new AppSettings(store, secrets).MemoryTokens);
        // Chosen by hand after the move, 150 stays.
        new AppSettings(store, secrets).MemoryTokens = 150;
        Assert.Equal(150, new AppSettings(store, secrets).MemoryTokens);
        // Any other saved value was the owner's choice and is never moved.
        var other = new MemorySettingsStore();
        other.Set("memoryTokens", 300);
        Assert.Equal(300, new AppSettings(other, secrets).MemoryTokens);
    }

    [Fact]
    public void TheDefaultsAndAChangeSurviveARelaunchAndAreClamped()
    {
        var store = new MemorySettingsStore();
        var secrets = new MemorySecretStore();
        var s = new AppSettings(store, secrets);
        Assert.True(s.DeedsEnabled && s.DeedGames && s.DeedTea && s.DeedFlower && s.DeedLetter && s.DeedVisit && s.DeedFollow && s.DeedSleep);
        Assert.True(s.DeedGapMinutes == 4 && s.DeedsPerHour == 8 && s.DeedPairGapMinutes == 20 && s.InviteOpenMinutes == 10);
        Assert.True(s.DeedWaitMinutes == 3 && s.BuiltInInviteShare == 20 && s.BuiltInAcceptChance == 65 && s.FollowSeconds == 30);
        Assert.True(s.MemoryEnabled && s.MemoryTokens == 600 && s.MemoryFacts == 5 && s.MemoryDays == 60 && s.MemoryNotes);
        Assert.True(s.DiaryEnabled && s.DiaryEveryHours == 8 && s.DiaryPairsPerNight == 8 && s.DayContextEnabled && s.DayContextItems == 4);
        Assert.True(s.SeedDays == 14 && s.SeedLines == 40);
        Assert.Equal(new Deeds.Limits(240, 8, 1200), s.DeedLimits);
        s.DeedsEnabled = false; s.DeedGames = false; s.DeedTea = false; s.DeedFlower = false; s.DeedLetter = false;
        s.DeedVisit = false; s.DeedFollow = false; s.DeedSleep = false;
        s.DeedGapMinutes = 0; s.DeedsPerHour = 0; s.DeedPairGapMinutes = 0; s.InviteOpenMinutes = 2; s.DeedWaitMinutes = 1;
        s.BuiltInInviteShare = 100; s.BuiltInAcceptChance = 0; s.FollowSeconds = 90;
        s.MemoryEnabled = false; s.MemoryTokens = 0; s.MemoryFacts = 0; s.MemoryDays = 7; s.MemoryNotes = false;
        s.DiaryEnabled = false; s.DiaryEveryHours = 24; s.DiaryPairsPerNight = 0; s.DayContextEnabled = false; s.DayContextItems = 10;
        s.SeedDays = 3; s.SeedLines = 100;
        var again = new AppSettings(store, secrets);
        Assert.True(!again.DeedsEnabled && !again.DeedGames && !again.DeedTea && !again.DeedFlower && !again.DeedLetter);
        Assert.True(!again.DeedVisit && !again.DeedFollow && !again.DeedSleep);
        Assert.True(again.DeedGapMinutes == 0 && again.DeedsPerHour == 0 && again.DeedPairGapMinutes == 0 && again.InviteOpenMinutes == 2);
        Assert.True(again.DeedWaitMinutes == 1 && again.BuiltInInviteShare == 100 && again.BuiltInAcceptChance == 0 && again.FollowSeconds == 90);
        Assert.True(!again.MemoryEnabled && again.MemoryTokens == 0 && again.MemoryFacts == 0 && again.MemoryDays == 7 && !again.MemoryNotes);
        Assert.True(!again.DiaryEnabled && again.DiaryEveryHours == 24 && again.DiaryPairsPerNight == 0 && !again.DayContextEnabled && again.DayContextItems == 10);
        Assert.True(again.SeedDays == 3 && again.SeedLines == 100);
        foreach (var (key, value) in new[] { ("deedGapMinutes", -5.0), ("deedPairGapMinutes", 9999.0), ("inviteOpenMinutes", 0.0), ("deedWaitMinutes", 99.0),
                                             ("builtInInviteShare", 250.0), ("followSeconds", 1.0), ("diaryEveryHours", 0.0) }) store.Set(key, value);
        foreach (var (key, value) in new[] { ("deedsPerHour", 500), ("memoryTokens", 5000), ("memoryFacts", -1), ("memoryDays", 1000),
                                             ("diaryPairsPerNight", 99), ("dayContextItems", 50), ("seedDays", 0), ("seedLines", 1) }) store.Set(key, value);
        var clamped = new AppSettings(store, secrets);
        Assert.True(clamped.DeedGapMinutes == 0 && clamped.DeedPairGapMinutes == 240 && clamped.InviteOpenMinutes == 1 && clamped.DeedWaitMinutes == 15);      // clamped on load
        Assert.True(clamped.BuiltInInviteShare == 100 && clamped.FollowSeconds == 5 && clamped.DiaryEveryHours == 1);
        Assert.True(clamped.DeedsPerHour == 120 && clamped.MemoryTokens == 2000 && clamped.MemoryFacts == 0 && clamped.MemoryDays == 365);
        Assert.True(clamped.DiaryPairsPerNight == 50 && clamped.DayContextItems == 10 && clamped.SeedDays == 1 && clamped.SeedLines == 5);
    }

    [Fact]
    public void TheTabIsNamedForScripts() => Assert.Equal("Relationships", SettingsTabs.Header(SettingsTab.Relationships));
}

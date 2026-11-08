using Ledgelings.Native;
using Ledgelings.Core;

namespace Ledgelings.Tests;

/// <summary>The Plot twists page's settings: the Mac's TwistsSettingsTests. Its colony tests (a first meeting, a
/// leaver missed, the news in a prompt) need a colony on screen, which the Windows tests never make (README › Not on Windows).</summary>
public class TwistsSettingsTests
{
    [Fact]
    public void TheDefaultsAndAChangeSurviveARelaunchAndAreClamped()
    {
        var store = new MemorySettingsStore();
        var secrets = new MemorySecretStore();
        var s = new AppSettings(store, secrets);
        Assert.True(s.TwistsEnabled && s.TwistDays == 3 && s.TwistChance == 35 && s.TwistDepartures);
        s.TwistsEnabled = false; s.TwistDays = 10; s.TwistChance = 80; s.TwistDepartures = false;
        var again = new AppSettings(store, secrets);
        Assert.True(!again.TwistsEnabled && again.TwistDays == 10 && again.TwistChance == 80 && !again.TwistDepartures);
        store.Set("twistDays", 99); store.Set("twistChance", 0.0);
        var clamped = new AppSettings(store, secrets);
        Assert.True(clamped.TwistDays == 14 && clamped.TwistChance == 5);
        store.Set("twistDays", 0); store.Set("twistChance", 500.0);
        var low = new AppSettings(store, secrets);
        Assert.True(low.TwistDays == 1 && low.TwistChance == 100);
    }

    [Fact]
    public void ThePageIsNamedForScripts()
    {
        Assert.Equal(SettingsPage.Twists, SettingsPages.Named("twists"));
        Assert.Equal(SettingsGroup.TalkAndFriends, SettingsPage.Twists.Group());
        Assert.Equal("Plot twists", SettingsPage.Twists.EnglishTitle());
    }
}

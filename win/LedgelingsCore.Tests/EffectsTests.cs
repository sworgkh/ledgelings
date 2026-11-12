namespace Ledgelings.Core.Tests;

using static Effects;

/// <summary>The effects' rules (SPEC §7.19), as on the Mac: which moment plays which effect, cooldowns, the
/// switches, Reduce motion, the seasons (December to February across the new year), friendship and typing.</summary>
public class EffectsTests
{
    static DateTime D(int y, int m, int d) => new(y, m, d, 12, 0, 0);

    [Fact]
    public void TheMomentsPlayWhatTheOwnerPicked()
    {
        Assert.Equal("ui/confetti", Moment.Goal.Effect());
        Assert.Equal("arcane/blink-out", Moment.LeaveScreen.Effect());
        Assert.Equal("arcane/blink-in", Moment.ArriveScreen.Effect());
        Assert.Equal("status/sleep", Moment.Asleep.Effect());
        Assert.Equal("status/slowed", Moment.ClockTicking.Effect());
        Assert.Equal("arcane/magic-circle-cast", Moment.Translating.Effect());
        Assert.Equal("spawn/coin-drop", Moment.MoneySpent.Effect());
        Assert.Equal("weather/snow", Moment.Winter.Effect());
        Assert.Equal("status/charmed", Style.Smitten.Effect());
        Assert.Equal("status/cursed", Style.Haunted.Effect());
        // Every feature has at least one moment, every moment its own effect.
        Assert.Equal(Features.ToHashSet(), Moments.Select(m => m.FeatureOf()).ToHashSet());
        Assert.Equal(20, Moments.Select(m => m.Effect()).Distinct().Count());
        // The codes saved are the Mac's; the printed steps name a style in English whatever the language.
        Assert.Equal("effectStyle.firedUp", Style.FiredUp.Key());
        Assert.Equal("effectMoment.heyLook", Moment.HeyLook.Key());
        Assert.Equal(["Frost", "Smitten", "Charged", "Fired up", "Haunted"], Styles.Select(s => s.Name()));
    }

    [Fact]
    public void EachTriggerPutsOnItsStyle()
    {
        Assert.Equal(Style.Smitten, Trigger.FriendsMeet.StyleOf());
        Assert.Equal(Style.Smitten, Trigger.InvitationAccepted.StyleOf());
        Assert.Equal(Style.Charged, Trigger.CursorGrab.StyleOf());
        Assert.Equal(Style.Charged, Trigger.FastTyping.StyleOf());
        Assert.Equal(Style.FiredUp, Trigger.Grumpy.StyleOf());
        Assert.Equal(Style.FiredUp, Trigger.LostGame.StyleOf());
        Assert.Equal(Style.Frost, Trigger.Winter.StyleOf());
        Assert.Equal(Style.Frost, Trigger.LeftAlone.StyleOf());
        Assert.Equal(Style.Haunted, Trigger.Halloween.StyleOf());
        Assert.Equal(Style.Haunted, Trigger.BooSpooks.StyleOf());
        Assert.Equal(Styles.ToHashSet(), Enum.GetValues<Trigger>().Select(t => t.StyleOf()).ToHashSet());
    }

    [Fact]
    public void AMomentWaitsOutItsCooldownPerCreature()
    {
        var rules = new Rules();
        Assert.True(rules.TakeMoment(Moment.Dizzy, 0, 100));
        Assert.False(rules.TakeMoment(Moment.Dizzy, 0, 100 + Moment.Dizzy.Cooldown() - 1));
        Assert.True(rules.TakeMoment(Moment.Dizzy, 1, 101));
        Assert.True(rules.TakeMoment(Moment.Dizzy, 0, 100 + Moment.Dizzy.Cooldown()));
        // Each moment has its own clock.
        Assert.True(rules.TakeMoment(Moment.Goal, 0, 101));
        Assert.True(Moments.Count(m => !m.Held() && !m.Ambient() && m.Cooldown() > 0) >= 8);
    }

    [Fact]
    public void AStyleComesByChanceAndThenWaits()
    {
        var rules = new Rules { Switches = new Switches { Frequency = Frequency.Sometimes } };
        Assert.Null(rules.TakeStyle(Trigger.FriendsMeet, 0, 0, 0.9));                 // unlucky
        Assert.Equal(Style.Smitten, rules.TakeStyle(Trigger.FriendsMeet, 0, 0, 0.1));
        Assert.Null(rules.TakeStyle(Trigger.InvitationAccepted, 0, 60, 0));          // the same style, too soon
        Assert.Equal(Style.Charged, rules.TakeStyle(Trigger.CursorGrab, 0, 60, 0));   // another style may
        Assert.Equal(Style.Smitten, rules.TakeStyle(Trigger.FriendsMeet, 0, 10 * 60, 0));
        // Often never rolls against it; a now-and-then style always takes.
        rules.Switches = rules.Switches with { Frequency = Frequency.Often };
        Assert.Equal(Style.FiredUp, rules.TakeStyle(Trigger.Grumpy, 2, 0, 0.99));
        rules.Switches = rules.Switches with { Frequency = Frequency.Rarely };
        Assert.Equal(Style.Frost, rules.TakeStyle(Trigger.Winter, 3, 0, 0.99));
        Assert.True(Frequency.Rarely.CooldownMinutes() > Frequency.Often.CooldownMinutes());
        Assert.True(rules.NowAndThenChance(30) < new Rules(new Switches { Frequency = Frequency.Often }).NowAndThenChance(30));
    }

    [Fact]
    public void EachSwitchTurnsItsEffectOff()
    {
        foreach (var m in Moments)
        {
            var rules = new Rules(new Switches { MomentsOn = Moments.Where(o => o != m).ToHashSet() });
            Assert.False(rules.TakeMoment(m, 0, 1e6));
            Assert.All(Moments.Where(o => o != m), o => Assert.True(rules.Switches.Allows(o)));
        }
        foreach (var s in Styles)
        {
            var rules = new Rules(new Switches { On = Styles.Where(o => o != s).ToHashSet() });
            foreach (var t in Enum.GetValues<Trigger>().Where(t => t.StyleOf() == s)) Assert.Null(rules.TakeStyle(t, 0, 0, 0));
            Assert.Equal(4, Styles.Count(rules.Switches.Allows));
        }
    }

    [Fact]
    public void TheMasterSwitchTurnsEverythingOff()
    {
        var rules = new Rules(new Switches { Enabled = false });
        Assert.All(Moments, m => Assert.False(rules.TakeMoment(m, 0, 0)));
        Assert.All(Enum.GetValues<Trigger>(), t => Assert.Null(rules.TakeStyle(t, 0, 0, 0)));
        Assert.Null(AmbientAt(D(2026, 1, 5), true, rules.Switches));
    }

    [Fact]
    public void ReduceMotionTurnsOnlyTheBusyOnesOff()
    {
        var s = new Switches { ReduceMotion = true };
        Assert.False(s.Allows(Style.Charged) || s.Allows(Style.FiredUp));
        Assert.True(s.Allows(Style.Frost) && s.Allows(Style.Smitten) && s.Allows(Style.Haunted));
        Assert.False(s.Allows(Moment.Goal) || s.Allows(Moment.Winter) || s.Allows(Moment.Night));
        Assert.True(s.Allows(Moment.Asleep) && s.Allows(Moment.HeyLook) && s.Allows(Moment.ClockTicking));
        // The setting follows the system unless chosen.
        Assert.True(ReduceMotion.System.IsOn(true));
        Assert.False(ReduceMotion.System.IsOn(false));
        Assert.True(ReduceMotion.On.IsOn(false));
        Assert.False(ReduceMotion.Off.IsOn(true));
    }

    [Fact]
    public void WinterIsDecemberToFebruaryAcrossTheNewYear()
    {
        Assert.Equal(Season.Autumn, SeasonOf(D(2026, 11, 30)));
        Assert.Equal(Season.Winter, SeasonOf(D(2026, 12, 1)));
        Assert.Equal(Season.Winter, SeasonOf(D(2026, 12, 31)));
        Assert.Equal(Season.Winter, SeasonOf(D(2027, 1, 1)));
        Assert.Equal(Season.Winter, SeasonOf(D(2028, 2, 29)));
        Assert.Equal(Season.Spring, SeasonOf(D(2027, 3, 1)));
        Assert.Equal(Season.Spring, SeasonOf(D(2027, 5, 31)));
        Assert.Equal(Season.Summer, SeasonOf(D(2027, 7, 15)));
        Assert.Equal(Season.Autumn, SeasonOf(D(2027, 9, 1)));
        Assert.Null(Season.Summer.MomentOf());
        Assert.True(AroundHalloween(D(2026, 10, 31)));
        Assert.True(AroundHalloween(D(2026, 11, 1)));
        Assert.False(AroundHalloween(D(2026, 11, 2)));
        Assert.False(AroundHalloween(D(2026, 10, 24)));
    }

    [Fact]
    public void TheAmbientParticlesFollowTheSeasonAndTheNight()
    {
        var s = new Switches();
        Assert.Equal(Moment.Winter, AmbientAt(D(2027, 1, 10), false, s));
        Assert.Equal(Moment.Night, AmbientAt(D(2027, 1, 10), true, s));
        Assert.Equal(Moment.Spring, AmbientAt(D(2027, 4, 10), false, s));
        Assert.Equal(Moment.Autumn, AmbientAt(D(2027, 10, 10), false, s));
        Assert.Null(AmbientAt(D(2027, 7, 10), false, s));
        var off = s with { MomentsOn = Moments.Where(m => m != Moment.Night).ToHashSet() };
        Assert.Equal(Moment.Winter, AmbientAt(D(2027, 1, 10), true, off));
        // A minute out of every ten, the first ten minutes after launch.
        Assert.False(AmbientShowing(30, 60, 10));
        Assert.True(AmbientShowing(630, 60, 10));
        Assert.False(AmbientShowing(661, 60, 10));
        Assert.True(AmbientShowing(1205, 60, 10));
    }

    [Fact]
    public void AFriendshipGrowsInStages()
    {
        var bond = new Bonds.Bond(new[] { "A", "B" });
        Assert.Equal(0, FriendshipStage(null));
        Assert.Equal(0, FriendshipStage(bond));
        bond.Talks = Plays.FriendsAt;
        Assert.Equal(1, FriendshipStage(bond));
        bond.Talks = 20;
        Assert.Equal(4, FriendshipStage(bond));
    }

    [Fact]
    public void AFastHourNeedsAWholeHourOfKeys()
    {
        var w = new TypingWatch();
        for (var minute = 0; minute <= 60; minute++) w.Add(minute * 100, minute * 60);
        Assert.Equal(6000, w.KeysInLastHour);
        Assert.True(w.Fast(5000));
        Assert.False(w.Fast(7000));
        var shortOne = new TypingWatch();
        for (var minute = 0; minute <= 20; minute++) shortOne.Add(minute * 1000, minute * 60);
        Assert.False(shortOne.Fast(5000));   // not an hour yet
    }
}

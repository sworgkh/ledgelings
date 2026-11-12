using Ledgelings.Core;
using Ledgelings.Native;
using Ledgelings.UI;

namespace Ledgelings.Tests;

/// <summary>Settings › Effects and Moments (SPEC §7.19): the defaults, a change surviving a relaunch, clamping and the
/// switches as the rules read them; the Styles page of Creature Actions. The Mac's EffectsSettingsTests; the rules
/// are the core's EffectsTests, the drawing its EffectsPixelTests.</summary>
public class EffectsSettingsTests
{
    [Fact]
    public void TheDefaultsAndAChangeSurviveARelaunch()
    {
        var store = new MemorySettingsStore();
        var secrets = new MemorySecretStore();
        var s = new AppSettings(store, secrets);
        Assert.True(s.EffectsEnabled && s.EffectsOff.Count == 0);
        Assert.Equal(Effects.Frequency.Sometimes, s.EffectsFrequency);
        Assert.Equal(Effects.ReduceMotion.System, s.EffectsReduceMotion);
        Assert.True(s.EffectStyleSeconds == 12 && s.EffectsAmbientSeconds == 60 && s.EffectsAmbientEveryMinutes == 10);
        Assert.True(s.EffectsAloneMinutes == 30 && s.EffectsTypingKeys == 5000 && s.EffectsDailyBudget == 1);
        var switches = s.EffectSwitches(systemReduceMotion: false);
        Assert.True(Effects.Styles.All(switches.Allows) && Effects.Moments.All(switches.Allows));

        s.EffectsEnabled = false;
        s.SetEffect(Effects.Style.Haunted.Key(), false);
        s.SetEffect(Effects.Moment.Goal.Key(), false);
        s.EffectsFrequency = Effects.Frequency.Often;
        s.EffectsReduceMotion = Effects.ReduceMotion.On;
        s.EffectStyleSeconds = 30; s.EffectsAmbientSeconds = 120; s.EffectsAmbientEveryMinutes = 5;
        s.EffectsAloneMinutes = 60; s.EffectsTypingKeys = 8000; s.EffectsDailyBudget = 2.5;
        var again = new AppSettings(store, secrets);
        Assert.False(again.EffectsEnabled);
        Assert.False(again.EffectOn(Effects.Style.Haunted.Key()) || again.EffectOn(Effects.Moment.Goal.Key()));
        Assert.True(again.EffectOn(Effects.Style.Frost.Key()));
        Assert.True(again.EffectsFrequency == Effects.Frequency.Often && again.EffectsReduceMotion == Effects.ReduceMotion.On);
        Assert.True(again.EffectStyleSeconds == 30 && again.EffectsAmbientSeconds == 120 && again.EffectsAmbientEveryMinutes == 5);
        Assert.True(again.EffectsAloneMinutes == 60 && again.EffectsTypingKeys == 8000 && again.EffectsDailyBudget == 2.5);
        // The Mac's codes on disk, so one settings file reads the same on both.
        Assert.Equal("often", store.Get<string>("effectsFrequency"));
        Assert.Equal("on", store.Get<string>("effectsReduceMotion"));

        // Out of range on disk is clamped on load; an unknown key is dropped.
        store.Set("effectStyleSeconds", 1000.0);
        store.Set("effectsOff", new List<string> { "effectMoment.nonsense" });
        var clamped = new AppSettings(store, secrets);
        Assert.Equal(AppSettings.EffectStyleSecondsMax, clamped.EffectStyleSeconds);
        Assert.Empty(clamped.EffectsOff);
    }

    [Fact]
    public void ReduceMotionAndTheSwitchesReachTheRules()
    {
        var s = new AppSettings(new MemorySettingsStore(), new MemorySecretStore());
        s.SetEffect(Effects.Moment.Dizzy.Key(), false);
        var switches = s.EffectSwitches(systemReduceMotion: true);
        Assert.False(switches.Allows(Effects.Moment.Dizzy));
        Assert.False(switches.Allows(Effects.Style.Charged));        // busy, and the system asks for less motion
        Assert.True(switches.Allows(Effects.Style.Frost));
        s.EffectsReduceMotion = Effects.ReduceMotion.Off;
        Assert.True(s.EffectSwitches(systemReduceMotion: true).Allows(Effects.Style.Charged));
    }

    [Fact]
    public void TheStylesPageHasItsKeyAndItsTags()
    {
        Assert.Contains("(Y)", ActivitiesTips.Styles);
        Assert.Contains("(Tab)", ActivitiesTips.Who);
        Assert.All(Effects.Styles, st => Assert.False(string.IsNullOrWhiteSpace(st.Detail())));
    }
}

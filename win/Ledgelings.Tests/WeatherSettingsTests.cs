using Ledgelings.Core;
using Ledgelings.Native;
using Ledgelings.UI;

namespace Ledgelings.Tests;

/// <summary>Settings › Weather &amp; Sky (SPEC §7.20): the defaults, a change surviving a relaunch, clamping and the switches as
/// the weather reads them; the Weather page of Creature Actions and the window tops. The Mac's WeatherSettingsTests;
/// the rules are the core's WeatherTests.</summary>
public class WeatherSettingsTests
{
    [Fact]
    public void TheDefaultsAndAChangeSurviveARelaunch()
    {
        var store = new MemorySettingsStore();
        var secrets = new MemorySecretStore();
        var s = new AppSettings(store, secrets);
        Assert.True(s.WeatherEnabled && s.WeatherSnow && s.WeatherRain && s.WeatherWind);
        Assert.True(s.WeatherQuietMinutes == 5 && s.WeatherMinutes == 3 && s.WeatherShareDistance == 40);
        Assert.Equal(Weather.Frequency.Sometimes, s.WeatherFrequency);
        Assert.True(s.WeatherSnowDepth == Weather.Level.Medium && s.WeatherWindStrength == Weather.Level.Medium);
        // Very sparse: two dozen flakes and forty drops on a whole monitor at once.
        Assert.True(s.WeatherSnowCount == 24 && s.WeatherRainCount == 40);
        Assert.True(s.WeatherFlakeSize == Weather.FlakeSize.Medium && s.WeatherSnowSpeed == 1 && s.WeatherRainSpeed == 1);
        Assert.True(s.WeatherSnowPiles && s.WeatherPuddles && s.WeatherUmbrellas && s.WeatherMenuBarUmbrella && s.WeatherWindPushes && s.WeatherStorm);
        Assert.Equal(9, s.WeatherGustSeconds);
        Assert.True(s.WeatherPausedDay.Length == 0 && !s.WeatherPausedToday);
        Assert.True(s.SkyWinterSnow && s.SkyAutumnLeaves && s.SkySpringPetals && s.SkyFireflies);
        Assert.True(s.SkyWinterCount == 10 && s.SkyAutumnCount == 10 && s.SkySpringCount == 10);
        Assert.True(s.SkyFirefliesCount == 6 && s.SkyFirefliesFrom == AppSettings.SkyNightFollowsColony);
        Assert.True(s.WeatherFollowSeason && s.WeatherWindowTops && s.WeatherTalk);
        Assert.Equal(Effects.ReduceMotion.System, s.WeatherReduceMotion);

        s.WeatherEnabled = false; s.WeatherSnow = false; s.WeatherRain = false; s.WeatherWind = false;
        s.WeatherQuietMinutes = 12; s.WeatherMinutes = 7; s.WeatherShareDistance = 90;
        s.WeatherFrequency = Weather.Frequency.Often;
        s.WeatherSnowDepth = Weather.Level.High; s.WeatherWindStrength = Weather.Level.High;
        s.WeatherSnowCount = 80; s.WeatherFlakeSize = Weather.FlakeSize.Large; s.WeatherSnowSpeed = 1.5; s.WeatherSnowPiles = false;
        s.WeatherRainCount = 120; s.WeatherRainSpeed = 0.7; s.WeatherPuddles = false; s.WeatherUmbrellas = false; s.WeatherMenuBarUmbrella = false;
        s.WeatherGustSeconds = 20; s.WeatherWindPushes = false; s.WeatherStorm = false;
        s.SkyWinterSnow = false; s.SkyWinterCount = 30; s.SkyAutumnLeaves = false; s.SkyAutumnCount = 5;
        s.SkySpringPetals = false; s.SkySpringCount = 40; s.SkyFireflies = false; s.SkyFirefliesCount = 12; s.SkyFirefliesFrom = 21;
        s.PauseWeather(true, DateTime.Now);
        s.WeatherFollowSeason = false; s.WeatherWindowTops = false; s.WeatherTalk = false;
        s.WeatherReduceMotion = Effects.ReduceMotion.On;
        var again = new AppSettings(store, secrets);
        Assert.False(again.WeatherEnabled || again.WeatherSnow || again.WeatherRain || again.WeatherWind);
        Assert.True(again.WeatherQuietMinutes == 12 && again.WeatherMinutes == 7 && again.WeatherShareDistance == 90);
        Assert.Equal(Weather.Frequency.Often, again.WeatherFrequency);
        Assert.True(again.WeatherSnowDepth == Weather.Level.High && again.WeatherWindStrength == Weather.Level.High);
        Assert.True(again.WeatherSnowCount == 80 && again.WeatherFlakeSize == Weather.FlakeSize.Large && again.WeatherSnowSpeed == 1.5 && !again.WeatherSnowPiles);
        Assert.True(again.WeatherRainCount == 120 && again.WeatherRainSpeed == 0.7 && !again.WeatherPuddles && !again.WeatherUmbrellas && !again.WeatherMenuBarUmbrella);
        Assert.True(again.WeatherGustSeconds == 20 && !again.WeatherWindPushes && !again.WeatherStorm);
        Assert.True(!again.SkyWinterSnow && again.SkyWinterCount == 30 && !again.SkyAutumnLeaves && again.SkyAutumnCount == 5);
        Assert.True(!again.SkySpringPetals && again.SkySpringCount == 40 && !again.SkyFireflies && again.SkyFirefliesCount == 12 && again.SkyFirefliesFrom == 21);
        Assert.True(again.WeatherPausedToday, "paused for today, still today");
        Assert.Equal("large", store.Get<string>("weatherFlakeSize"));
        Assert.False(again.WeatherFollowSeason || again.WeatherWindowTops || again.WeatherTalk);
        Assert.Equal(Effects.ReduceMotion.On, again.WeatherReduceMotion);
        // The Mac's codes on disk, so one settings file reads the same on both.
        Assert.Equal("often", store.Get<string>("weatherFrequency"));
        Assert.Equal("high", store.Get<string>("weatherSnowDepth"));
        Assert.Equal("on", store.Get<string>("weatherReduceMotion"));
    }

    [Fact]
    public void OutOfRangeIsClampedOnLoadAndAnUnknownCodeFallsBack()
    {
        var store = new MemorySettingsStore();
        store.Set("weatherQuietMinutes", 500.0);
        store.Set("weatherMinutes", 0.0);
        store.Set("weatherShareDistance", -5.0);
        store.Set("weatherFrequency", "hourly");
        store.Set("weatherSnowDepth", "enormous");
        store.Set("weatherSnowCount", 5000.0);
        store.Set("weatherRainSpeed", 0.0);
        store.Set("skyFirefliesFrom", 14);
        var s = new AppSettings(store, new MemorySecretStore());
        Assert.Equal(AppSettings.WeatherQuietMax, s.WeatherQuietMinutes);
        Assert.Equal(AppSettings.WeatherMinutesMin, s.WeatherMinutes);
        Assert.Equal(AppSettings.WeatherShareMin, s.WeatherShareDistance);
        Assert.Equal(Weather.Frequency.Sometimes, s.WeatherFrequency);
        Assert.Equal(Weather.Level.Medium, s.WeatherSnowDepth);
        Assert.Equal(Weather.SnowCountRange.Max, s.WeatherSnowCount);
        Assert.Equal(Weather.SpeedRange.Min, s.WeatherRainSpeed);
        Assert.Equal(AppSettings.SkyNightFollowsColony, s.SkyFirefliesFrom);      // not an hour on offer
        s.WeatherMinutes = 99;
        Assert.Equal(AppSettings.WeatherMinutesMax, s.WeatherMinutes);
    }

    [Fact]
    public void TheSwitchesReachTheWeather()
    {
        var s = new AppSettings(new MemorySettingsStore(), new MemorySecretStore());
        var on = s.WeatherSwitches(systemReduceMotion: false);
        Assert.True(Weather.Kinds.All(on.Allows));
        Assert.False(on.ReduceMotion);
        Assert.True(s.WeatherSwitches(systemReduceMotion: true).ReduceMotion);      // follows Windows' Show animations
        s.WeatherReduceMotion = Effects.ReduceMotion.Off;
        Assert.False(s.WeatherSwitches(systemReduceMotion: true).ReduceMotion);
        s.WeatherRain = false;
        var dry = s.WeatherSwitches(systemReduceMotion: false);
        Assert.False(dry.Allows(Weather.Kind.Rain) || dry.Allows(Weather.Kind.Storm));      // a storm rains
        Assert.True(dry.Allows(Weather.Kind.Snow) && dry.Allows(Weather.Kind.Wind));
        s.WeatherEnabled = false;
        Assert.False(Weather.Kinds.Any(s.WeatherSwitches(systemReduceMotion: false).Allows));
    }

    [Fact]
    public void TheMomentsSwitchesMoveToTheSky()
    {
        // As an older version saved them: fireflies and autumn switched off on the Moments page, with a style.
        var store = new MemorySettingsStore();
        store.Set("effectsOff", new List<string> { "effectMoment.night", "effectMoment.autumn", "effectStyle.frost" });
        var s = new AppSettings(store, new MemorySecretStore());
        Assert.True(!s.SkyFireflies && !s.SkyAutumnLeaves && s.SkySpringPetals && s.SkyWinterSnow);
        Assert.Equal(new[] { "effectStyle.frost" }, s.EffectsOff);       // the moved ones leave the Moments list
        Assert.False(store.Get<bool?>("skyFireflies"));
        var again = new AppSettings(store, new MemorySecretStore());
        Assert.True(!again.SkyFireflies && !again.SkyAutumnLeaves);         // and stay off
        Assert.False(again.EffectSwitches(systemReduceMotion: false).Allows(Effects.Moment.Night));
        again.SkyAutumnLeaves = true;
        Assert.True(again.EffectSwitches(systemReduceMotion: false).Allows(Effects.Moment.Autumn));
    }

    [Fact]
    public void PausedForTodayIsOnlyToday()
    {
        var s = new AppSettings(new MemorySettingsStore(), new MemorySecretStore());
        var today = new DateTime(2026, 11, 13, 15, 0, 0);
        s.PauseWeather(true, today);
        Assert.True(s.WeatherPaused(today));
        Assert.True(s.WeatherPaused(today.Date.AddHours(23.9)));
        Assert.False(s.WeatherPaused(today.AddDays(1)));
        s.PauseWeather(false, today);
        Assert.False(s.WeatherPaused(today));
    }

    [Fact]
    public void TheWeatherPageHasItsKeyAndEveryRowItsPicture()
    {
        Assert.Contains("(W)", ActivitiesTips.Weather);
        Assert.All(Weather.Kinds, k => Assert.False(string.IsNullOrWhiteSpace(k.Detail())));
        Assert.All(Weather.Kinds.Select(k => (Weather.Kind?)k).Append(null), k => Assert.NotNull(ActionIcons.Weather(k)));
    }

    [Fact]
    public void AWindowInFrontHidesTheTopOfOneBehind()
    {
        // A 1000 × 600 monitor at the origin, y up; art pixels of 2 points.
        var display = new Rect(0, 0, 1000, 600);
        var front = new WeatherWatch.Window(1, new Rect(100, 200, 300, 300));      // top at 500
        var behind = new WeatherWatch.Window(2, new Rect(300, 100, 400, 300));     // top at 400, its left part under the front one
        var ledges = WeatherWatch.Ledges(new[] { front, behind }, display, 2, topInset: 0);
        Assert.Equal(50, ledges[1].X);
        Assert.Equal(50, ledges[1].Y);
        Assert.True(ledges[1].Open.All(o => o));
        Assert.Equal(150, ledges[2].X);
        Assert.Equal(100, ledges[2].Y);
        Assert.False(ledges[2].Open[0]);                  // under the front window
        Assert.True(ledges[2].Open[^1]);
        // A window covering the monitor is full screen; one an inch short is not.
        Assert.True(WeatherWatch.Covers(new Rect(0, 0, 1000, 600), display));
        Assert.False(WeatherWatch.Covers(new Rect(0, 0, 1000, 500), display));
        // A window whose top is under a taskbar along the top has no ledge.
        Assert.Empty(WeatherWatch.Ledges(new[] { new WeatherWatch.Window(3, new Rect(0, 100, 600, 480)) }, display, 2, topInset: 40));
    }
}

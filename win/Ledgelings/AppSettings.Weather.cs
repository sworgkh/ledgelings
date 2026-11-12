using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Weather on a quiet screen (SPEC §7.20): snow, rain and wind, the Mac's keys, defaults and ranges.</summary>
public sealed partial class AppSettings
{
    public const double WeatherQuietMin = 1, WeatherQuietMax = 60;
    public const double WeatherMinutesMin = 1, WeatherMinutesMax = 20;
    public const double WeatherShareMin = 0, WeatherShareMax = 200;

    private bool weatherEnabled, weatherSnow, weatherRain, weatherWind, weatherFollowSeason, weatherWindowTops, weatherTalk;
    private double weatherQuietMinutes, weatherMinutes, weatherShareDistance;
    private Weather.Frequency weatherFrequency;
    private Weather.Level weatherSnowDepth, weatherRainHeaviness, weatherWindStrength;
    private Effects.ReduceMotion weatherReduceMotion;

    private void LoadWeather()
    {
        // Weather: all on, sometimes, after five quiet minutes, for three.
        weatherEnabled = store.Get<bool?>("weatherEnabled") ?? true;
        weatherSnow = store.Get<bool?>("weatherSnow") ?? true;
        weatherRain = store.Get<bool?>("weatherRain") ?? true;
        weatherWind = store.Get<bool?>("weatherWind") ?? true;
        weatherQuietMinutes = Math.Clamp(store.Get<double?>("weatherQuietMinutes") ?? 5, WeatherQuietMin, WeatherQuietMax);
        weatherFrequency = Weather.FrequencyNamed(store.Get<string>("weatherFrequency")) ?? Weather.Frequency.Sometimes;
        weatherMinutes = Math.Clamp(store.Get<double?>("weatherMinutes") ?? 3, WeatherMinutesMin, WeatherMinutesMax);
        weatherSnowDepth = Weather.LevelNamed(store.Get<string>("weatherSnowDepth")) ?? Weather.Level.Medium;
        weatherRainHeaviness = Weather.LevelNamed(store.Get<string>("weatherRainHeaviness")) ?? Weather.Level.Medium;
        weatherWindStrength = Weather.LevelNamed(store.Get<string>("weatherWindStrength")) ?? Weather.Level.Medium;
        weatherShareDistance = Math.Clamp(store.Get<double?>("weatherShareDistance") ?? 40, WeatherShareMin, WeatherShareMax);
        weatherFollowSeason = store.Get<bool?>("weatherFollowSeason") ?? true;
        weatherWindowTops = store.Get<bool?>("weatherWindowTops") ?? true;
        weatherReduceMotion = Effects.ReduceMotionNamed(store.Get<string>("weatherReduceMotion")) ?? Effects.ReduceMotion.System;
        weatherTalk = store.Get<bool?>("weatherTalk") ?? true;
    }

    public bool WeatherEnabled { get => weatherEnabled; set => Put(ref weatherEnabled, value, "weatherEnabled"); }
    public bool WeatherSnow { get => weatherSnow; set => Put(ref weatherSnow, value, "weatherSnow"); }
    public bool WeatherRain { get => weatherRain; set => Put(ref weatherRain, value, "weatherRain"); }
    public bool WeatherWind { get => weatherWind; set => Put(ref weatherWind, value, "weatherWind"); }
    /// <summary>Minutes with no typing and the cursor barely moving before weather may come.</summary>
    public double WeatherQuietMinutes { get => weatherQuietMinutes; set => Put(ref weatherQuietMinutes, Math.Clamp(value, WeatherQuietMin, WeatherQuietMax), "weatherQuietMinutes"); }
    /// <summary>Minutes a spell lasts before it eases off.</summary>
    public double WeatherMinutes { get => weatherMinutes; set => Put(ref weatherMinutes, Math.Clamp(value, WeatherMinutesMin, WeatherMinutesMax), "weatherMinutes"); }
    /// <summary>Creatures closer than this many points share one umbrella; 0: everyone has its own.</summary>
    public double WeatherShareDistance { get => weatherShareDistance; set => Put(ref weatherShareDistance, Math.Clamp(value, WeatherShareMin, WeatherShareMax), "weatherShareDistance"); }
    public bool WeatherFollowSeason { get => weatherFollowSeason; set => Put(ref weatherFollowSeason, value, "weatherFollowSeason"); }
    public bool WeatherWindowTops { get => weatherWindowTops; set => Put(ref weatherWindowTops, value, "weatherWindowTops"); }
    /// <summary>The creatures say a line about it now and then.</summary>
    public bool WeatherTalk { get => weatherTalk; set => Put(ref weatherTalk, value, "weatherTalk"); }

    public Weather.Frequency WeatherFrequency
    {
        get => weatherFrequency;
        set { if (weatherFrequency == value) return; weatherFrequency = value; store.Set("weatherFrequency", value.Code()); Raise(nameof(WeatherFrequency)); Raise(nameof(WeatherFrequencyIndex)); }
    }
    public Weather.Level WeatherSnowDepth
    {
        get => weatherSnowDepth;
        set { if (weatherSnowDepth == value) return; weatherSnowDepth = value; store.Set("weatherSnowDepth", value.Code()); Raise(nameof(WeatherSnowDepth)); Raise(nameof(WeatherSnowDepthIndex)); }
    }
    public Weather.Level WeatherRainHeaviness
    {
        get => weatherRainHeaviness;
        set { if (weatherRainHeaviness == value) return; weatherRainHeaviness = value; store.Set("weatherRainHeaviness", value.Code()); Raise(nameof(WeatherRainHeaviness)); Raise(nameof(WeatherRainHeavinessIndex)); }
    }
    public Weather.Level WeatherWindStrength
    {
        get => weatherWindStrength;
        set { if (weatherWindStrength == value) return; weatherWindStrength = value; store.Set("weatherWindStrength", value.Code()); Raise(nameof(WeatherWindStrength)); Raise(nameof(WeatherWindStrengthIndex)); }
    }
    /// <summary>Reduce motion: half the particles, nobody pushed by the wind. As the system says, or always, or never.</summary>
    public Effects.ReduceMotion WeatherReduceMotion
    {
        get => weatherReduceMotion;
        set { if (weatherReduceMotion == value) return; weatherReduceMotion = value; store.Set("weatherReduceMotion", value.Code()); Raise(nameof(WeatherReduceMotion)); Raise(nameof(WeatherReduceMotionIndex)); }
    }

    /// <summary>The choices as the page's lists have them, in order.</summary>
    public int WeatherFrequencyIndex { get => (int)weatherFrequency; set => WeatherFrequency = (Weather.Frequency)Math.Clamp(value, 0, 2); }
    public int WeatherSnowDepthIndex { get => (int)weatherSnowDepth; set => WeatherSnowDepth = (Weather.Level)Math.Clamp(value, 0, 2); }
    public int WeatherRainHeavinessIndex { get => (int)weatherRainHeaviness; set => WeatherRainHeaviness = (Weather.Level)Math.Clamp(value, 0, 2); }
    public int WeatherWindStrengthIndex { get => (int)weatherWindStrength; set => WeatherWindStrength = (Weather.Level)Math.Clamp(value, 0, 2); }
    public int WeatherReduceMotionIndex { get => (int)weatherReduceMotion; set => WeatherReduceMotion = (Effects.ReduceMotion)Math.Clamp(value, 0, 2); }

    /// <summary>Every weather setting at once, Reduce motion read from the system when it follows it.</summary>
    public Weather.Switches WeatherSwitches(bool systemReduceMotion) => new()
    {
        Enabled = weatherEnabled,
        Snow = weatherSnow,
        Rain = weatherRain,
        Wind = weatherWind,
        QuietMinutes = weatherQuietMinutes,
        Frequency = weatherFrequency,
        LastsMinutes = weatherMinutes,
        SnowDepth = weatherSnowDepth,
        RainHeaviness = weatherRainHeaviness,
        WindStrength = weatherWindStrength,
        ShareDistance = weatherShareDistance,
        FollowSeason = weatherFollowSeason,
        WindowTops = weatherWindowTops,
        ReduceMotion = weatherReduceMotion.IsOn(systemReduceMotion),
    };
}

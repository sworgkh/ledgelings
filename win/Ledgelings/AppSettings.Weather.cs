using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Weather on a quiet screen and the sky (SPEC §7.20, Settings › Weather &amp; Sky): snow, rain and wind, the
/// season's light particles and the fireflies, the Mac's keys, defaults and ranges.</summary>
public sealed partial class AppSettings
{
    public const double WeatherQuietMin = 1, WeatherQuietMax = 60;
    public const double WeatherMinutesMin = 1, WeatherMinutesMax = 20;
    public const double WeatherShareMin = 0, WeatherShareMax = 200;

    public const double SkyCountMin = 2, SkyCountMax = 100;
    public const int SkyFirefliesMin = 1, SkyFirefliesMax = 32;
    /// <summary>The hours fireflies may come out from; <see cref="SkyNightFollowsColony"/> is the creatures' night.</summary>
    public static IReadOnlyList<int> SkyFirefliesHours { get; } = new[] { -1 }.Concat(Enumerable.Range(17, 7)).ToList();
    public const int SkyNightFollowsColony = -1;
    /// <summary>A handful at once: very sparse.</summary>
    public const double SkyDefaultCount = 10;
    public const int SkyDefaultFireflies = 6;

    private bool weatherEnabled, weatherSnow, weatherRain, weatherWind, weatherFollowSeason, weatherWindowTops, weatherTalk;
    private bool weatherSnowPiles, weatherPuddles, weatherUmbrellas, weatherMenuBarUmbrella, weatherWindPushes, weatherStorm;
    private double weatherQuietMinutes, weatherMinutes, weatherShareDistance;
    private double weatherSnowCount, weatherSnowSpeed, weatherRainCount, weatherRainSpeed, weatherGustSeconds;
    private string weatherPausedDay = "";
    private bool skyWinterSnow, skyAutumnLeaves, skySpringPetals, skyFireflies;
    private double skyWinterCount, skyAutumnCount, skySpringCount;
    private int skyFirefliesCount, skyFirefliesFrom;
    private Weather.Frequency weatherFrequency;
    private Weather.FlakeSize weatherFlakeSize;
    private Weather.Level weatherSnowDepth, weatherWindStrength;
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
        // Very sparse: a couple of dozen flakes, forty drops on a whole monitor (it was over a thousand flakes).
        double Clamped(string key, double fallback, (double Min, double Max) range) => Math.Clamp(store.Get<double?>(key) ?? fallback, range.Min, range.Max);
        weatherSnowCount = Clamped("weatherSnowCount", Weather.DefaultSnowCount, Weather.SnowCountRange);
        weatherFlakeSize = Weather.FlakeSizeNamed(store.Get<string>("weatherFlakeSize")) ?? Weather.FlakeSize.Medium;
        weatherSnowSpeed = Clamped("weatherSnowSpeed", 1, Weather.SpeedRange);
        weatherSnowPiles = store.Get<bool?>("weatherSnowPiles") ?? true;
        weatherRainCount = Clamped("weatherRainCount", Weather.DefaultRainCount, Weather.RainCountRange);
        weatherRainSpeed = Clamped("weatherRainSpeed", 1, Weather.SpeedRange);
        weatherPuddles = store.Get<bool?>("weatherPuddles") ?? true;
        weatherUmbrellas = store.Get<bool?>("weatherUmbrellas") ?? true;
        weatherMenuBarUmbrella = store.Get<bool?>("weatherMenuBarUmbrella") ?? true;
        weatherGustSeconds = Clamped("weatherGustSeconds", 9, Weather.GustRange);
        weatherWindPushes = store.Get<bool?>("weatherWindPushes") ?? true;
        weatherStorm = store.Get<bool?>("weatherStorm") ?? true;
        weatherPausedDay = store.Get<string>("weatherPausedDay") ?? "";
        // The sky's switches were the Moments page's: a moment switched off there stays off here, once, and leaves
        // effectsOff (loaded just before).
        var movedOff = effectsOff.Where(k => Effects.Moments.Any(m => m.Ambient() && m.Key() == k)).ToHashSet();
        bool Moved(string key, Effects.Moment moment) => store.Get<bool?>(key) ?? !movedOff.Contains(moment.Key());
        skyFireflies = Moved("skyFireflies", Effects.Moment.Night);
        skyWinterSnow = Moved("skyWinterSnow", Effects.Moment.Winter);
        skyAutumnLeaves = Moved("skyAutumnLeaves", Effects.Moment.Autumn);
        skySpringPetals = Moved("skySpringPetals", Effects.Moment.Spring);
        if (movedOff.Count > 0)
        {
            store.Set("skyFireflies", skyFireflies);
            store.Set("skyWinterSnow", skyWinterSnow);
            store.Set("skyAutumnLeaves", skyAutumnLeaves);
            store.Set("skySpringPetals", skySpringPetals);
            effectsOff = effectsOff.Where(k => !movedOff.Contains(k)).ToList();
            store.Set("effectsOff", effectsOff.ToList());
        }
        skyWinterCount = Clamped("skyWinterCount", SkyDefaultCount, (SkyCountMin, SkyCountMax));
        skyAutumnCount = Clamped("skyAutumnCount", SkyDefaultCount, (SkyCountMin, SkyCountMax));
        skySpringCount = Clamped("skySpringCount", SkyDefaultCount, (SkyCountMin, SkyCountMax));
        skyFirefliesCount = Math.Clamp(store.Get<int?>("skyFirefliesCount") ?? SkyDefaultFireflies, SkyFirefliesMin, SkyFirefliesMax);
        var from = store.Get<int?>("skyFirefliesFrom") ?? SkyNightFollowsColony;
        skyFirefliesFrom = SkyFirefliesHours.Contains(from) ? from : SkyNightFollowsColony;
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
    public Weather.FlakeSize WeatherFlakeSize
    {
        get => weatherFlakeSize;
        set { if (weatherFlakeSize == value) return; weatherFlakeSize = value; store.Set("weatherFlakeSize", value.Code()); Raise(nameof(WeatherFlakeSize)); Raise(nameof(WeatherFlakeSizeIndex)); }
    }

    /// <summary>Flakes on a monitor at once, how fast, whether they pile up.</summary>
    public double WeatherSnowCount { get => weatherSnowCount; set => Put(ref weatherSnowCount, Math.Clamp(value, Weather.SnowCountRange.Min, Weather.SnowCountRange.Max), "weatherSnowCount"); }
    public double WeatherSnowSpeed { get => weatherSnowSpeed; set => Put(ref weatherSnowSpeed, Math.Clamp(value, Weather.SpeedRange.Min, Weather.SpeedRange.Max), "weatherSnowSpeed"); }
    public bool WeatherSnowPiles { get => weatherSnowPiles; set => Put(ref weatherSnowPiles, value, "weatherSnowPiles"); }
    /// <summary>Drops on a monitor at once and how fast; puddles, umbrellas, and the umbrella on the top edge that fills.</summary>
    public double WeatherRainCount { get => weatherRainCount; set => Put(ref weatherRainCount, Math.Clamp(value, Weather.RainCountRange.Min, Weather.RainCountRange.Max), "weatherRainCount"); }
    public double WeatherRainSpeed { get => weatherRainSpeed; set => Put(ref weatherRainSpeed, Math.Clamp(value, Weather.SpeedRange.Min, Weather.SpeedRange.Max), "weatherRainSpeed"); }
    public bool WeatherPuddles { get => weatherPuddles; set => Put(ref weatherPuddles, value, "weatherPuddles"); }
    public bool WeatherUmbrellas { get => weatherUmbrellas; set => Put(ref weatherUmbrellas, value, "weatherUmbrellas"); }
    public bool WeatherMenuBarUmbrella { get => weatherMenuBarUmbrella; set => Put(ref weatherMenuBarUmbrella, value, "weatherMenuBarUmbrella"); }
    /// <summary>Seconds between gusts; whether a gust pushes the light ones.</summary>
    public double WeatherGustSeconds { get => weatherGustSeconds; set => Put(ref weatherGustSeconds, Math.Clamp(value, Weather.GustRange.Min, Weather.GustRange.Max), "weatherGustSeconds"); }
    public bool WeatherWindPushes { get => weatherWindPushes; set => Put(ref weatherWindPushes, value, "weatherWindPushes"); }
    public bool WeatherStorm { get => weatherStorm; set => Put(ref weatherStorm, value, "weatherStorm"); }
    /// <summary>The day (yyyy-MM-dd) the weather and the sky were paused for; empty when not paused.</summary>
    public string WeatherPausedDay
    {
        get => weatherPausedDay;
        set { if (Put(ref weatherPausedDay, value, "weatherPausedDay")) Raise(nameof(WeatherPausedToday)); }
    }
    /// <summary>Paused for today: no weather comes on its own and the sky stays clear until tomorrow.</summary>
    public bool WeatherPaused(DateTime date) => weatherPausedDay == date.ToString("yyyy-MM-dd");
    public void PauseWeather(bool on, DateTime date) => WeatherPausedDay = on ? date.ToString("yyyy-MM-dd") : "";
    public bool WeatherPausedToday => WeatherPaused(DateTime.Now);

    // The sky: each season's light particles on or off and how many on a monitor at once (they were the Moments page's
    // Winter, Autumn and Spring), the fireflies (Night falls), how many, and from what hour until six in the morning.
    public bool SkyWinterSnow { get => skyWinterSnow; set => Put(ref skyWinterSnow, value, "skyWinterSnow"); }
    public bool SkyAutumnLeaves { get => skyAutumnLeaves; set => Put(ref skyAutumnLeaves, value, "skyAutumnLeaves"); }
    public bool SkySpringPetals { get => skySpringPetals; set => Put(ref skySpringPetals, value, "skySpringPetals"); }
    public bool SkyFireflies { get => skyFireflies; set => Put(ref skyFireflies, value, "skyFireflies"); }
    public double SkyWinterCount { get => skyWinterCount; set => Put(ref skyWinterCount, Math.Clamp(value, SkyCountMin, SkyCountMax), "skyWinterCount"); }
    public double SkyAutumnCount { get => skyAutumnCount; set => Put(ref skyAutumnCount, Math.Clamp(value, SkyCountMin, SkyCountMax), "skyAutumnCount"); }
    public double SkySpringCount { get => skySpringCount; set => Put(ref skySpringCount, Math.Clamp(value, SkyCountMin, SkyCountMax), "skySpringCount"); }
    public int SkyFirefliesCount { get => skyFirefliesCount; set => Put(ref skyFirefliesCount, Math.Clamp(value, SkyFirefliesMin, SkyFirefliesMax), "skyFirefliesCount"); }
    public int SkyFirefliesFrom
    {
        get => skyFirefliesFrom;
        set
        {
            var v = SkyFirefliesHours.Contains(value) ? value : SkyNightFollowsColony;
            if (Put(ref skyFirefliesFrom, v, "skyFirefliesFrom")) Raise(nameof(SkyFirefliesFromIndex));
        }
    }
    /// <summary>The fireflies' hour as the page's list has it.</summary>
    public int SkyFirefliesFromIndex
    {
        get => SkyFirefliesHours.ToList().IndexOf(skyFirefliesFrom);
        set => SkyFirefliesFrom = SkyFirefliesHours[Math.Clamp(value, 0, SkyFirefliesHours.Count - 1)];
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
    public int WeatherFlakeSizeIndex { get => (int)weatherFlakeSize; set => WeatherFlakeSize = (Weather.FlakeSize)Math.Clamp(value, 0, 2); }
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
        SnowCount = weatherSnowCount,
        FlakeSize = weatherFlakeSize,
        SnowSpeed = weatherSnowSpeed,
        SnowPiles = weatherSnowPiles,
        RainCount = weatherRainCount,
        RainSpeed = weatherRainSpeed,
        Puddles = weatherPuddles,
        Umbrellas = weatherUmbrellas,
        MenuBarUmbrella = weatherMenuBarUmbrella,
        GustSeconds = weatherGustSeconds,
        WindPushes = weatherWindPushes,
        Storm = weatherStorm,
        WindStrength = weatherWindStrength,
        ShareDistance = weatherShareDistance,
        FollowSeason = weatherFollowSeason,
        WindowTops = weatherWindowTops,
        ReduceMotion = weatherReduceMotion.IsOn(systemReduceMotion),
    };
}

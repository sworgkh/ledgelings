using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The effects (SPEC §7.19): the styles the creatures wear and the moments they mark, the Mac's keys and
/// defaults. Windows has no calendar to read, so it has no <c>effectsCalendar</c>: Clock ticking plays by hand only.</summary>
public sealed partial class AppSettings
{
    public const double EffectStyleSecondsMin = 4, EffectStyleSecondsMax = 60;
    public const double EffectsAmbientSecondsMin = 10, EffectsAmbientSecondsMax = 600;
    public const double EffectsAmbientEveryMin = 1, EffectsAmbientEveryMax = 120;
    public const double EffectsAloneMinutesMin = 5, EffectsAloneMinutesMax = 240;
    public const int EffectsTypingKeysMin = 1000, EffectsTypingKeysMax = 20000;
    public const double EffectsDailyBudgetMin = 0.1, EffectsDailyBudgetMax = 50;

    private bool effectsEnabled;
    private IReadOnlyList<string> effectsOff = Array.Empty<string>();
    private Effects.Frequency effectsFrequency;
    private Effects.ReduceMotion effectsReduceMotion;
    private double effectStyleSeconds, effectsAmbientSeconds, effectsAmbientEveryMinutes, effectsAloneMinutes, effectsDailyBudget;
    private int effectsTypingKeys;

    /// <summary>Every key a switch can have: a style's or a moment's.</summary>
    public static IReadOnlyList<string> EffectKeys { get; } =
        Effects.Styles.Select(s => s.Key()).Concat(Effects.Moments.Select(m => m.Key())).ToList();

    private void LoadEffects()
    {
        effectsEnabled = store.Get<bool?>("effectsEnabled") ?? true;
        // Only keys that are a style or a moment: an old or mistyped one is dropped.
        effectsOff = (store.Get<List<string>>("effectsOff") ?? new()).Where(EffectKeys.Contains).Distinct().ToList();
        // Sometimes: a style every now and then, never a costume party.
        effectsFrequency = Effects.FrequencyNamed(store.Get<string>("effectsFrequency")) ?? Effects.Frequency.Sometimes;
        effectsReduceMotion = Effects.ReduceMotionNamed(store.Get<string>("effectsReduceMotion")) ?? Effects.ReduceMotion.System;
        // Twelve seconds: long enough to notice, short enough not to become the creature's look.
        effectStyleSeconds = Math.Clamp(store.Get<double?>("effectStyleSeconds") ?? 12, EffectStyleSecondsMin, EffectStyleSecondsMax);
        // A minute of snow or fireflies every ten: a moment, not wallpaper.
        effectsAmbientSeconds = Math.Clamp(store.Get<double?>("effectsAmbientSeconds") ?? 60, EffectsAmbientSecondsMin, EffectsAmbientSecondsMax);
        effectsAmbientEveryMinutes = Math.Clamp(store.Get<double?>("effectsAmbientEveryMinutes") ?? 10, EffectsAmbientEveryMin, EffectsAmbientEveryMax);
        // Half an hour without anyone: lonely enough to frost over.
        effectsAloneMinutes = Math.Clamp(store.Get<double?>("effectsAloneMinutes") ?? 30, EffectsAloneMinutesMin, EffectsAloneMinutesMax);
        // Five thousand keys an hour: a busy hour of writing, not a normal one.
        effectsTypingKeys = Math.Clamp(store.Get<int?>("effectsTypingKeys") ?? 5000, EffectsTypingKeysMin, EffectsTypingKeysMax);
        // A dollar a day: past it, the coins drop once.
        effectsDailyBudget = Math.Clamp(store.Get<double?>("effectsDailyBudget") ?? 1, EffectsDailyBudgetMin, EffectsDailyBudgetMax);
    }

    /// <summary>Every effect at once: the styles the creatures wear and the moments they mark.</summary>
    public bool EffectsEnabled { get => effectsEnabled; set => Put(ref effectsEnabled, value, "effectsEnabled"); }
    /// <summary>The styles and moments switched off, by their keys: all on is empty.</summary>
    public IReadOnlyList<string> EffectsOff { get => effectsOff; set => Put(ref effectsOff, value.Where(EffectKeys.Contains).Distinct().ToList(), "effectsOff"); }
    /// <summary>How often styles play on their own.</summary>
    public Effects.Frequency EffectsFrequency
    {
        get => effectsFrequency;
        set { if (effectsFrequency == value) return; effectsFrequency = value; store.Set("effectsFrequency", value.Code()); Raise(nameof(EffectsFrequency)); Raise(nameof(EffectsFrequencyIndex)); }
    }
    /// <summary>Reduce motion turns the busy effects off: as the system says, or always, or never.</summary>
    public Effects.ReduceMotion EffectsReduceMotion
    {
        get => effectsReduceMotion;
        set { if (effectsReduceMotion == value) return; effectsReduceMotion = value; store.Set("effectsReduceMotion", value.Code()); Raise(nameof(EffectsReduceMotion)); Raise(nameof(EffectsReduceMotionIndex)); }
    }
    /// <summary>The two choices as the page's lists have them, in order.</summary>
    public int EffectsFrequencyIndex { get => (int)effectsFrequency; set => EffectsFrequency = (Effects.Frequency)Math.Clamp(value, 0, 2); }
    public int EffectsReduceMotionIndex { get => (int)effectsReduceMotion; set => EffectsReduceMotion = (Effects.ReduceMotion)Math.Clamp(value, 0, 2); }
    /// <summary>How long a creature wears a style.</summary>
    public double EffectStyleSeconds { get => effectStyleSeconds; set => Put(ref effectStyleSeconds, Math.Clamp(value, EffectStyleSecondsMin, EffectStyleSecondsMax), "effectStyleSeconds"); }
    /// <summary>The season's particles and the fireflies come out for this long...</summary>
    public double EffectsAmbientSeconds { get => effectsAmbientSeconds; set => Put(ref effectsAmbientSeconds, Math.Clamp(value, EffectsAmbientSecondsMin, EffectsAmbientSecondsMax), "effectsAmbientSeconds"); }
    /// <summary>...once in this many minutes, the first time one whole wait after launch.</summary>
    public double EffectsAmbientEveryMinutes { get => effectsAmbientEveryMinutes; set => Put(ref effectsAmbientEveryMinutes, Math.Clamp(value, EffectsAmbientEveryMin, EffectsAmbientEveryMax), "effectsAmbientEveryMinutes"); }
    /// <summary>A creature nobody has met for this long may frost over.</summary>
    public double EffectsAloneMinutes { get => effectsAloneMinutes; set => Put(ref effectsAloneMinutes, Math.Clamp(value, EffectsAloneMinutesMin, EffectsAloneMinutesMax), "effectsAloneMinutes"); }
    /// <summary>Keys in an hour that count as a fast hour of typing.</summary>
    public int EffectsTypingKeys { get => effectsTypingKeys; set => Put(ref effectsTypingKeys, Math.Clamp(value, EffectsTypingKeysMin, EffectsTypingKeysMax), "effectsTypingKeys"); }
    /// <summary>Money spent: the day's spend past this many dollars drops the coins, once a day.</summary>
    public double EffectsDailyBudget { get => effectsDailyBudget; set => Put(ref effectsDailyBudget, Math.Clamp(value, EffectsDailyBudgetMin, EffectsDailyBudgetMax), "effectsDailyBudget"); }

    /// <summary>One style's or moment's switch, by its key.</summary>
    public bool EffectOn(string key) => !effectsOff.Contains(key);

    public void SetEffect(string key, bool on)
    {
        if (on == EffectOn(key)) return;
        EffectsOff = on ? effectsOff.Where(k => k != key).ToList() : effectsOff.Append(key).ToList();
    }

    /// <summary>The switches as the rules read them, Reduce motion resolved against the system's.</summary>
    public Effects.Switches EffectSwitches(bool systemReduceMotion) => new()
    {
        Enabled = effectsEnabled,
        On = Effects.Styles.Where(s => EffectOn(s.Key())).ToHashSet(),
        // The fireflies and the season's particles have their own switches on Weather & Sky.
        MomentsOn = Effects.Moments.Where(m => !m.Ambient() && EffectOn(m.Key()))
            .Concat(new (bool On, Effects.Moment M)[] { (skyFireflies, Effects.Moment.Night), (skyWinterSnow, Effects.Moment.Winter),
                                                        (skyAutumnLeaves, Effects.Moment.Autumn), (skySpringPetals, Effects.Moment.Spring) }
                    .Where(x => x.On).Select(x => x.M))
            .ToHashSet(),
        Frequency = effectsFrequency,
        ReduceMotion = effectsReduceMotion.IsOn(systemReduceMotion),
    };
}

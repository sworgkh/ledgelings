namespace Ledgelings;

/// <summary>The Plot twists page's settings (SPEC §6.5.2.4): whether a newcomer or a departure is news, for how
/// many days, and how often it comes up. The Mac's keys, defaults and ranges.</summary>
public sealed partial class AppSettings
{
    public const int TwistDaysMin = 1, TwistDaysMax = 14;
    public const double TwistChanceMin = 5, TwistChanceMax = 100;

    private bool twistsEnabled, twistDepartures;
    private int twistDays;
    private double twistChance;

    private void LoadTwists()
    {
        twistsEnabled = store.Get<bool?>("twistsEnabled") ?? true;
        // Three days: long enough to be gossip, short enough to be over by next week.
        twistDays = Math.Clamp(store.Get<int?>("twistDays") ?? 3, TwistDaysMin, TwistDaysMax);
        // About one conversation in three on the first day, fading to none by the last.
        twistChance = Math.Clamp(store.Get<double?>("twistChance") ?? 35, TwistChanceMin, TwistChanceMax);
        twistDepartures = store.Get<bool?>("twistDepartures") ?? true;
    }

    /// <summary>When a newcomer joins the gang or someone leaves, the others talk about it for a while (<see cref="Core.Gang"/>).</summary>
    public bool TwistsEnabled { get => twistsEnabled; set => Put(ref twistsEnabled, value, "twistsEnabled"); }
    /// <summary>Days the news stays a topic.</summary>
    public int TwistDays { get => twistDays; set => Put(ref twistDays, Math.Clamp(value, TwistDaysMin, TwistDaysMax), "twistDays"); }
    /// <summary>Percent of conversations that bring the news up while it is new; it fades over the days.</summary>
    public double TwistChance { get => twistChance; set => Put(ref twistChance, Math.Clamp(value, TwistChanceMin, TwistChanceMax), "twistChance"); }
    /// <summary>Someone leaving (and coming back) is news too, not only a newcomer.</summary>
    public bool TwistDepartures { get => twistDepartures; set => Put(ref twistDepartures, value, "twistDepartures"); }
}

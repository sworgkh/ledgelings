namespace Ledgelings;

/// <summary>Tea parties: two creatures who bump into each other now and then sit down to tea
/// and tell each other their life stories.</summary>
public sealed partial class AppSettings
{
    /// <summary>Share of bumps, in percent, that become a tea party instead of a quick word.</summary>
    public const double TeaChanceMin = 1, TeaChanceMax = 100;
    /// <summary>Minutes a tea party lasts.</summary>
    public const double TeaMinutesMin = 1, TeaMinutesMax = 10;
    /// <summary>Seconds of quiet sipping between one story and the next.</summary>
    public const double TeaSipMin = 0, TeaSipMax = 30;

    private bool teaPartiesEnabled;
    private double teaPartyChance, teaPartyMinutes, teaSipSeconds;

    private void LoadTeaParties()
    {
        teaPartiesEnabled = store.Get<bool?>("teaPartiesEnabled") ?? true;
        // One bump in ten: with a few creatures that is a party every quarter of an hour or so, a treat, not the routine.
        teaPartyChance = Math.Clamp(store.Get<double?>("teaPartyChance") ?? 10, TeaChanceMin, TeaChanceMax);
        // Three minutes: six or so stories, long enough to learn something about each other.
        teaPartyMinutes = Math.Clamp(store.Get<double?>("teaPartyMinutes") ?? 3, TeaMinutesMin, TeaMinutesMax);
        // Six seconds: a sip and a look round before the next story, so it reads as a chat, not a recital.
        teaSipSeconds = Math.Clamp(store.Get<double?>("teaSipSeconds") ?? 6, TeaSipMin, TeaSipMax);
    }

    /// <summary>Two creatures who bump into each other now and then sit down to tea and tell each other their life stories.</summary>
    public bool TeaPartiesEnabled { get => teaPartiesEnabled; set => Put(ref teaPartiesEnabled, value, "teaPartiesEnabled"); }
    public double TeaPartyChance { get => teaPartyChance; set => Put(ref teaPartyChance, Math.Clamp(value, TeaChanceMin, TeaChanceMax), "teaPartyChance"); }
    public double TeaPartyMinutes { get => teaPartyMinutes; set => Put(ref teaPartyMinutes, Math.Clamp(value, TeaMinutesMin, TeaMinutesMax), "teaPartyMinutes"); }
    public double TeaSipSeconds { get => teaSipSeconds; set => Put(ref teaSipSeconds, Math.Clamp(value, TeaSipMin, TeaSipMax), "teaSipSeconds"); }
}

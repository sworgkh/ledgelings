using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Plays (SPEC §7.10): now and then, and more between friends, they play: tag, a rope swing,
/// a parachute jump, basketball.</summary>
public sealed partial class AppSettings
{
    /// <summary>Average minutes between games, before close friends shorten it.</summary>
    public const double PlayEveryMin = 1, PlayEveryMax = 60;
    /// <summary>How much a close pair speeds the games up, in percent: 100 halves the wait.</summary>
    public const double PlayBondBoostMin = 0, PlayBondBoostMax = 300;
    /// <summary>Seconds a game of tag lasts.</summary>
    public const double TagSecondsMin = 10, TagSecondsMax = 120;
    /// <summary>Points per second a parachute comes down at.</summary>
    public const double ParachuteFallMin = 30, ParachuteFallMax = 200;
    /// <summary>Percent of its speed the ball keeps on each bounce.</summary>
    public const double BallBounceMin = 0, BallBounceMax = 90;
    /// <summary>Throws each player has at the hoop.</summary>
    public const int BasketballThrowsMin = 1, BasketballThrowsMax = 10;

    private bool playEnabled, playTagEnabled, playRopeEnabled, playParachuteEnabled, playBasketballEnabled, playTalk;
    private double playEveryMinutes, playBondBoost, tagSeconds, parachuteFallSpeed, ballBounce;
    private int basketballThrows;

    private void LoadPlay()
    {
        playEnabled = store.Get<bool?>("playEnabled") ?? true;
        playTagEnabled = store.Get<bool?>("playTagEnabled") ?? true;
        playRopeEnabled = store.Get<bool?>("playRopeEnabled") ?? true;
        playParachuteEnabled = store.Get<bool?>("playParachuteEnabled") ?? true;
        playBasketballEnabled = store.Get<bool?>("playBasketballEnabled") ?? true;
        // Five minutes: a game now and then in a working hour, not a circus.
        playEveryMinutes = Math.Clamp(store.Get<double?>("playEveryMinutes") ?? 5, PlayEveryMin, PlayEveryMax);
        // 100 %: the closest friends play twice as often as strangers.
        playBondBoost = Math.Clamp(store.Get<double?>("playBondBoost") ?? 100, PlayBondBoostMin, PlayBondBoostMax);
        // Long enough for a few touches round a screen, short enough to watch to the end.
        tagSeconds = Math.Clamp(store.Get<double?>("tagSeconds") ?? 25, TagSecondsMin, TagSecondsMax);
        // About ten seconds down a laptop screen: slow enough to sway, quick enough to land.
        parachuteFallSpeed = Math.Clamp(store.Get<double?>("parachuteFallSpeed") ?? 70, ParachuteFallMin, ParachuteFallMax);
        // 60 %: two or three bounces, then it rolls to a stop.
        ballBounce = Math.Clamp(store.Get<double?>("ballBounce") ?? 60, BallBounceMin, BallBounceMax);
        basketballThrows = Math.Clamp(store.Get<int?>("basketballThrows") ?? 3, BasketballThrowsMin, BasketballThrowsMax);
        playTalk = store.Get<bool?>("playTalk") ?? true;
    }

    /// <summary>Now and then, and more between friends, they play.</summary>
    public bool PlayEnabled { get => playEnabled; set => Put(ref playEnabled, value, "playEnabled"); }
    public bool PlayTagEnabled { get => playTagEnabled; set => Put(ref playTagEnabled, value, "playTagEnabled"); }
    public bool PlayRopeEnabled { get => playRopeEnabled; set => Put(ref playRopeEnabled, value, "playRopeEnabled"); }
    public bool PlayParachuteEnabled { get => playParachuteEnabled; set => Put(ref playParachuteEnabled, value, "playParachuteEnabled"); }
    public bool PlayBasketballEnabled { get => playBasketballEnabled; set => Put(ref playBasketballEnabled, value, "playBasketballEnabled"); }
    public double PlayEveryMinutes { get => playEveryMinutes; set => Put(ref playEveryMinutes, Math.Clamp(value, PlayEveryMin, PlayEveryMax), "playEveryMinutes"); }
    public double PlayBondBoost { get => playBondBoost; set => Put(ref playBondBoost, Math.Clamp(value, PlayBondBoostMin, PlayBondBoostMax), "playBondBoost"); }
    public double TagSeconds { get => tagSeconds; set => Put(ref tagSeconds, Math.Clamp(value, TagSecondsMin, TagSecondsMax), "tagSeconds"); }
    public double ParachuteFallSpeed { get => parachuteFallSpeed; set => Put(ref parachuteFallSpeed, Math.Clamp(value, ParachuteFallMin, ParachuteFallMax), "parachuteFallSpeed"); }
    public double BallBounce { get => ballBounce; set => Put(ref ballBounce, Math.Clamp(value, BallBounceMin, BallBounceMax), "ballBounce"); }
    public int BasketballThrows { get => basketballThrows; set => Put(ref basketballThrows, Math.Clamp(value, BasketballThrowsMin, BasketballThrowsMax), "basketballThrows"); }
    /// <summary>A line as a game starts and once it is over, in the character's own voice.</summary>
    public bool PlayTalk { get => playTalk; set => Put(ref playTalk, value, "playTalk"); }

    /// <summary>The games switched on, whether or not play itself is.</summary>
    public IReadOnlySet<Plays.Kind> EnabledPlays
    {
        get
        {
            var on = new HashSet<Plays.Kind>();
            if (playTagEnabled) on.Add(Plays.Kind.Tag);
            if (playRopeEnabled) on.Add(Plays.Kind.Rope);
            if (playParachuteEnabled) on.Add(Plays.Kind.Parachute);
            if (playBasketballEnabled) on.Add(Plays.Kind.Basketball);
            return on;
        }
    }
}

using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Plays (SPEC §7.10): now and then, and more between friends, they play: tag, a rope swing,
/// a parachute jump, basketball; soccer and baseball for whoever is free.</summary>
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
    /// <summary>The fewest minutes between two matches of soccer, or two games of baseball.</summary>
    public const double BallGameEveryMin = 2, BallGameEveryMax = 240;
    /// <summary>Minutes a soccer match lasts at most.</summary>
    public const double SoccerMinutesMin = 0.5, SoccerMinutesMax = 10;
    /// <summary>Goals that win a soccer match.</summary>
    public const int SoccerGoalsMin = 1, SoccerGoalsMax = 10;
    /// <summary>Innings in a game of baseball.</summary>
    public const int BaseballInningsMin = 1, BaseballInningsMax = 9;
    /// <summary>The most who join a soccer match or a baseball game.</summary>
    public const int BallPlayersMin = Plays.TeamPlayersMin, BallPlayersMax = Plays.TeamPlayersMax;

    private bool playEnabled, playTagEnabled, playRopeEnabled, playParachuteEnabled, playBasketballEnabled, playTalk;
    private double playEveryMinutes, playBondBoost, tagSeconds, parachuteFallSpeed, ballBounce;
    private int basketballThrows;
    private bool playSoccerEnabled, playBaseballEnabled;
    private double soccerEveryMinutes, baseballEveryMinutes, soccerMinutes;
    private int soccerGoals, baseballInnings, soccerPlayers, baseballPlayers;

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
        playSoccerEnabled = store.Get<bool?>("playSoccerEnabled") ?? true;
        playBaseballEnabled = store.Get<bool?>("playBaseballEnabled") ?? true;
        // 20 minutes: a match is a big event, a few times a working day, not every other game.
        soccerEveryMinutes = Math.Clamp(store.Get<double?>("soccerEveryMinutes") ?? 20, BallGameEveryMin, BallGameEveryMax);
        baseballEveryMinutes = Math.Clamp(store.Get<double?>("baseballEveryMinutes") ?? 20, BallGameEveryMin, BallGameEveryMax);
        // Two minutes, or first to three: long enough for a few goals, short enough to watch to the end.
        soccerMinutes = Math.Clamp(store.Get<double?>("soccerMinutes") ?? 2, SoccerMinutesMin, SoccerMinutesMax);
        soccerGoals = Math.Clamp(store.Get<int?>("soccerGoals") ?? 3, SoccerGoalsMin, SoccerGoalsMax);
        // Two innings: two to four minutes for a crowd.
        baseballInnings = Math.Clamp(store.Get<int?>("baseballInnings") ?? 2, BaseballInningsMin, BaseballInningsMax);
        // Six: three a side, a keeper each, and still room to run.
        soccerPlayers = Math.Clamp(store.Get<int?>("soccerPlayers") ?? 6, BallPlayersMin, BallPlayersMax);
        baseballPlayers = Math.Clamp(store.Get<int?>("baseballPlayers") ?? 6, BallPlayersMin, BallPlayersMax);
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

    /// <summary>Soccer on the widest floor, for however many are free (<c>Plays.Soccer</c>).</summary>
    public bool PlaySoccerEnabled { get => playSoccerEnabled; set => Put(ref playSoccerEnabled, value, "playSoccerEnabled"); }
    public double SoccerEveryMinutes { get => soccerEveryMinutes; set => Put(ref soccerEveryMinutes, Math.Clamp(value, BallGameEveryMin, BallGameEveryMax), "soccerEveryMinutes"); }
    public double SoccerMinutes { get => soccerMinutes; set => Put(ref soccerMinutes, Math.Clamp(value, SoccerMinutesMin, SoccerMinutesMax), "soccerMinutes"); }
    public int SoccerGoals { get => soccerGoals; set => Put(ref soccerGoals, Math.Clamp(value, SoccerGoalsMin, SoccerGoalsMax), "soccerGoals"); }
    public int SoccerPlayers { get => soccerPlayers; set => Put(ref soccerPlayers, Math.Clamp(value, BallPlayersMin, BallPlayersMax), "soccerPlayers"); }
    /// <summary>Baseball across every edge, for however many are free (<c>Plays.Baseball</c>).</summary>
    public bool PlayBaseballEnabled { get => playBaseballEnabled; set => Put(ref playBaseballEnabled, value, "playBaseballEnabled"); }
    public double BaseballEveryMinutes { get => baseballEveryMinutes; set => Put(ref baseballEveryMinutes, Math.Clamp(value, BallGameEveryMin, BallGameEveryMax), "baseballEveryMinutes"); }
    public int BaseballInnings { get => baseballInnings; set => Put(ref baseballInnings, Math.Clamp(value, BaseballInningsMin, BaseballInningsMax), "baseballInnings"); }
    public int BaseballPlayers { get => baseballPlayers; set => Put(ref baseballPlayers, Math.Clamp(value, BallPlayersMin, BallPlayersMax), "baseballPlayers"); }

    /// <summary>The most who may join each ball game.</summary>
    public IReadOnlyDictionary<Plays.Kind, int> BallGamePlayers =>
        new Dictionary<Plays.Kind, int> { [Plays.Kind.Soccer] = soccerPlayers, [Plays.Kind.Baseball] = baseballPlayers };

    /// <summary>The fewest minutes between two of <paramref name="kind"/>, a ball game.</summary>
    public double BallGameEvery(Plays.Kind kind) => kind == Plays.Kind.Baseball ? baseballEveryMinutes : soccerEveryMinutes;

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
            if (playSoccerEnabled) on.Add(Plays.Kind.Soccer);
            if (playBaseballEnabled) on.Add(Plays.Kind.Baseball);
            return on;
        }
    }
}

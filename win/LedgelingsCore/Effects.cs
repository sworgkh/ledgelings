namespace Ledgelings.Core;

/// <summary>
/// The effects the creatures wear and the moments they mark (SPEC §7.19), the Mac's <c>Effects.swift</c>: which
/// style or moment plays which pixelfx effect, when one may play again, which switches turn it off, and the
/// seasons. The drawing itself is <c>FXInstance</c> (<c>PixelFX/</c>); the colony asks <see cref="Rules"/> before
/// starting one. The codes saved are the Mac's (<c>effectStyle.frost</c>, <c>effectMoment.goal</c>).
/// </summary>
public static class Effects
{
    /// <summary>A style a creature wears for a while, then takes off.</summary>
    public enum Style { Frost, Smitten, Charged, FiredUp, Haunted }

    /// <summary>The features a moment belongs to, which is how the settings page groups them.</summary>
    public enum Feature
    {
        Screens, MovingAbout, CursorGrab, BallGames, Bonds, SpriteKit, Creatures, Garden, Beds, Night, Seasons,
        Reminders, Calendar, Dictation, Translate, Clipboard, Costs,
    }

    /// <summary>A moment in a feature the app already has, marked by an effect on the creature it happens to.</summary>
    public enum Moment
    {
        LeaveScreen, ArriveScreen, HardLanding, Dizzy, Goal, Friends, NewArrival, Poof, Bloom, Asleep,
        Night, Winter, Autumn, Spring, HeyLook, ClockTicking, Listening, Translating, Copied, MoneySpent,
    }

    /// <summary>How often styles play on their own.</summary>
    public enum Frequency { Rarely, Sometimes, Often }

    /// <summary>Reduce motion: as the system says, or always on, or always off.</summary>
    public enum ReduceMotion { System, On, Off }

    /// <summary>What can put a style on a creature.</summary>
    public enum Trigger { Winter, LeftAlone, FriendsMeet, InvitationAccepted, CursorGrab, FastTyping, Grumpy, LostGame, Halloween, BooSpooks }

    public enum Season { Winter, Spring, Summer, Autumn }

    public static IReadOnlyList<Style> Styles { get; } = Enum.GetValues<Style>();
    public static IReadOnlyList<Moment> Moments { get; } = Enum.GetValues<Moment>();
    public static IReadOnlyList<Feature> Features { get; } = Enum.GetValues<Feature>();

    /// <summary>The Mac's raw value: the case name with a small first letter (<c>firedUp</c>, <c>heyLook</c>).</summary>
    static string Code(Enum e) { var s = e.ToString(); return char.ToLowerInvariant(s[0]) + s[1..]; }

    // MARK: Styles

    public static string Code(this Style s) => Code((Enum)s);

    /// <summary>Its English name, untranslated, for the printed steps (<c>fx 3.20 Smitten on Boo</c>).</summary>
    public static string Name(this Style s) => s switch
    {
        Style.Frost => "Frost",
        Style.Smitten => "Smitten",
        Style.Charged => "Charged",
        Style.FiredUp => "Fired up",
        _ => "Haunted",
    };

    /// <summary>The pixelfx effect that draws it.</summary>
    public static string Effect(this Style s) => s switch
    {
        Style.Frost => "status/frozen",
        Style.Smitten => "status/charmed",
        Style.Charged => "lightning/electrified",
        Style.FiredUp => "status/burning",
        _ => "status/cursed",
    };

    public static string Title(this Style s) => L10n.Tr(s.Name());

    /// <summary>What it shows and when it plays, for its row.</summary>
    public static string Detail(this Style s) => L10n.Tr(s switch
    {
        Style.Frost => "Frost, icicles, a shiver: in winter now and then, or left alone too long",
        Style.Smitten => "A heart overhead, pink eyes: two friends meet, an invitation is accepted",
        Style.Charged => "Sparks and arcs: grabbing the cursor, or a fast hour of typing",
        Style.FiredUp => "Small flames and scorch marks: grumpy at the cursor, or losing a game",
        _ => "Violet smoke, glowing eyes, a skull: around Halloween, or Boo spooking a friend",
    });

    /// <summary>Busy enough that Reduce motion turns it off.</summary>
    public static bool Busy(this Style s) => s is Style.Charged or Style.FiredUp;

    /// <summary>The settings key of its switch.</summary>
    public static string Key(this Style s) => "effectStyle." + s.Code();

    // MARK: Features

    public static string Title(this Feature f) => L10n.Tr(f switch
    {
        Feature.Screens => "Screens",
        Feature.MovingAbout => "Moving about",
        Feature.CursorGrab => "Cursor grab",
        Feature.BallGames => "Ball games",
        Feature.Bonds => "Bonds",
        Feature.SpriteKit => "Sprite kit",
        Feature.Creatures => "Creatures",
        Feature.Garden => "Garden",
        Feature.Beds => "Beds",
        Feature.Night => "Night",
        Feature.Seasons => "Seasons",
        Feature.Reminders => "Reminders",
        Feature.Calendar => "Calendar",
        Feature.Dictation => "Dictation",
        Feature.Translate => "Translate",
        Feature.Clipboard => "Clipboard",
        _ => "Costs",
    });

    // MARK: Moments

    public static string Code(this Moment m) => Code((Enum)m);

    public static Feature FeatureOf(this Moment m) => m switch
    {
        Moment.LeaveScreen or Moment.ArriveScreen => Feature.Screens,
        Moment.HardLanding => Feature.MovingAbout,
        Moment.Dizzy => Feature.CursorGrab,
        Moment.Goal => Feature.BallGames,
        Moment.Friends => Feature.Bonds,
        Moment.NewArrival => Feature.SpriteKit,
        Moment.Poof => Feature.Creatures,
        Moment.Bloom => Feature.Garden,
        Moment.Asleep => Feature.Beds,
        Moment.Night => Feature.Night,
        Moment.Winter or Moment.Autumn or Moment.Spring => Feature.Seasons,
        Moment.HeyLook => Feature.Reminders,
        Moment.ClockTicking => Feature.Calendar,
        Moment.Listening => Feature.Dictation,
        Moment.Translating => Feature.Translate,
        Moment.Copied => Feature.Clipboard,
        _ => Feature.Costs,
    };

    /// <summary>The pixelfx effect that marks it.</summary>
    public static string Effect(this Moment m) => m switch
    {
        Moment.LeaveScreen => "arcane/blink-out",
        Moment.ArriveScreen => "arcane/blink-in",
        Moment.HardLanding => "impacts/heavy-landing",
        Moment.Dizzy => "status/stunned",
        Moment.Goal => "ui/confetti",
        Moment.Friends => "ui/level-up",
        Moment.NewArrival => "spawn/egg-hatch",
        Moment.Poof => "spawn/poof",
        Moment.Bloom => "nature/healing-bloom",
        Moment.Asleep => "status/sleep",
        Moment.Night => "weather/fireflies",
        Moment.Winter => "weather/snow",
        Moment.Autumn => "weather/falling-leaves",
        Moment.Spring => "weather/cherry-blossoms",
        Moment.HeyLook => "ui/exclamation",
        // The dial the owner picked from the pictures, ticking round; the magic circle is Translate's.
        Moment.ClockTicking => "status/slowed",
        Moment.Listening => "lightning/charge-up",
        Moment.Translating => "arcane/magic-circle-cast",
        Moment.Copied => "pickups/collect-burst",
        _ => "spawn/coin-drop",
    };

    public static string Title(this Moment m) => L10n.Tr(m switch
    {
        Moment.LeaveScreen => "Leaving a monitor",
        Moment.ArriveScreen => "Arriving on a monitor",
        Moment.HardLanding => "A hard landing",
        Moment.Dizzy => "Dizzy",
        Moment.Goal => "Goal!",
        Moment.Friends => "Friends for real",
        Moment.NewArrival => "A new arrival",
        Moment.Poof => "Poof, gone",
        Moment.Bloom => "A flower comes up",
        Moment.Asleep => "Fast asleep",
        Moment.Night => "Night falls",
        Moment.Winter => "Winter",
        Moment.Autumn => "Autumn",
        Moment.Spring => "Spring",
        Moment.HeyLook => "Hey, look!",
        Moment.ClockTicking => "Clock ticking",
        Moment.Listening => "Listening",
        Moment.Translating => "Translating",
        Moment.Copied => "Copied!",
        _ => "Money spent",
    });

    /// <summary>When it plays and what it shows, for its row's tooltip.</summary>
    public static string Detail(this Moment m) => L10n.Tr(m switch
    {
        Moment.LeaveScreen => "It blinks out when it moves to another monitor",
        Moment.ArriveScreen => "It blinks in on the monitor it moved to",
        Moment.HardLanding => "Dust flies when it drops from high up",
        Moment.Dizzy => "Stars spin round its head after the cursor shakes it about",
        Moment.Goal => "Confetti on a goal, a basket or a home run",
        Moment.Friends => "A level-up when a friendship grows a stage",
        Moment.NewArrival => "An egg hatches when a new species joins",
        Moment.Poof => "A poof when a creature is removed",
        Moment.Bloom => "Leaves and sparkles when a flower is planted",
        Moment.Asleep => "Floating Zs and a nightcap, in place of the plain Zs",
        Moment.Night => "Fireflies along the bottom of the screen after dark",
        Moment.Winter => "Snow drifting down, December to February",
        Moment.Autumn => "Leaves falling, September to November",
        Moment.Spring => "Petals drifting, March to May",
        Moment.HeyLook => "An exclamation mark when a reminder is due",
        Moment.ClockTicking => "A ticking clock five minutes before a meeting in your calendar",
        Moment.Listening => "Charging up while you dictate",
        Moment.Translating => "A magic circle while a translation is on its way",
        Moment.Copied => "A burst when something lands on the clipboard",
        _ => "Coins drop when the day's spend passes your budget",
    });

    /// <summary>Plays over the screen's bottom edge for a while rather than on one creature.</summary>
    public static bool Ambient(this Moment m) => m is Moment.Night or Moment.Winter or Moment.Autumn or Moment.Spring;

    /// <summary>Plays for as long as something lasts (asleep, listening, translating), not once.</summary>
    public static bool Held(this Moment m) => m is Moment.Asleep or Moment.Listening or Moment.Translating;

    /// <summary>Busy enough that Reduce motion turns it off.</summary>
    public static bool Busy(this Moment m) => m is not (Moment.HardLanding or Moment.Dizzy or Moment.Bloom or Moment.Asleep
        or Moment.HeyLook or Moment.ClockTicking);

    /// <summary>The fewest seconds between two of it on one creature.</summary>
    public static double Cooldown(this Moment m) => m switch
    {
        Moment.LeaveScreen or Moment.ArriveScreen => 5,
        Moment.HardLanding => 45,
        Moment.Dizzy => 60,
        Moment.Goal => 6,
        Moment.Bloom => 20,
        Moment.ClockTicking => 120,
        Moment.Copied => 8,
        _ => 0,
    };

    /// <summary>The settings key of its switch.</summary>
    public static string Key(this Moment m) => "effectMoment." + m.Code();

    // MARK: Frequency and Reduce motion

    public static string Code(this Frequency f) => Code((Enum)f);
    public static string Title(this Frequency f) => L10n.Tr(f switch { Frequency.Rarely => "Rarely", Frequency.Sometimes => "Sometimes", _ => "Often" });

    /// <summary>The chance a trigger (two friends meeting, a grab) puts a style on.</summary>
    public static double Chance(this Frequency f) => f switch { Frequency.Rarely => 0.25, Frequency.Sometimes => 0.5, _ => 1 };

    /// <summary>The fewest minutes before one creature wears the same style again.</summary>
    public static double CooldownMinutes(this Frequency f) => f switch { Frequency.Rarely => 30, Frequency.Sometimes => 10, _ => 3 };

    /// <summary>About how many minutes apart a style comes now and then on its own (winter frost, Halloween).</summary>
    public static double EveryMinutes(this Frequency f) => f switch { Frequency.Rarely => 60, Frequency.Sometimes => 20, _ => 6 };

    public static string Code(this ReduceMotion r) => Code((Enum)r);
    public static string Title(this ReduceMotion r) => L10n.Tr(r switch { ReduceMotion.System => "As the system", ReduceMotion.On => "On", _ => "Off" });
    public static bool IsOn(this ReduceMotion r, bool system) => r switch { ReduceMotion.System => system, ReduceMotion.On => true, _ => false };

    public static Frequency? FrequencyNamed(string? code) => Enum.GetValues<Frequency>().Cast<Frequency?>().FirstOrDefault(f => f!.Value.Code() == code);
    public static ReduceMotion? ReduceMotionNamed(string? code) => Enum.GetValues<ReduceMotion>().Cast<ReduceMotion?>().FirstOrDefault(r => r!.Value.Code() == code);

    // MARK: Triggers

    public static Style StyleOf(this Trigger t) => t switch
    {
        Trigger.Winter or Trigger.LeftAlone => Style.Frost,
        Trigger.FriendsMeet or Trigger.InvitationAccepted => Style.Smitten,
        Trigger.CursorGrab or Trigger.FastTyping => Style.Charged,
        Trigger.Grumpy or Trigger.LostGame => Style.FiredUp,
        _ => Style.Haunted,
    };

    /// <summary>Comes on its own now and then (in season), rather than from something that happened.</summary>
    public static bool NowAndThen(this Trigger t) => t is Trigger.Winter or Trigger.Halloween;

    // MARK: Friendship

    /// <summary>Moments shared at which a friendship grows a stage: friends, good friends, close, as close as can be.</summary>
    public static IReadOnlyList<int> FriendshipStages { get; } = [Plays.FriendsAt, 8, 14, (int)Plays.CloseAt];

    /// <summary>How far a pair's friendship has grown: 0 before they are friends, up to 4.</summary>
    public static int FriendshipStage(Bonds.Bond? bond)
    {
        if (bond is null) return 0;
        var moments = Math.Max(bond.Tally.Values.Sum(), bond.Talks);
        return FriendshipStages.Count(s => moments >= s);
    }

    // MARK: The seasons

    /// <summary>Northern-hemisphere months: December to February is winter, across the new year.</summary>
    public static Season SeasonOf(DateTime date) => date.Month switch
    {
        12 or 1 or 2 => Season.Winter,
        3 or 4 or 5 => Season.Spring,
        6 or 7 or 8 => Season.Summer,
        _ => Season.Autumn,
    };

    /// <summary>Its moment, if it has one: summer has none.</summary>
    public static Moment? MomentOf(this Season s) => s switch
    {
        Season.Winter => Moment.Winter,
        Season.Spring => Moment.Spring,
        Season.Autumn => Moment.Autumn,
        _ => null,
    };

    /// <summary>The week round Halloween: 25 October to 1 November.</summary>
    public static bool AroundHalloween(DateTime date) => (date.Month == 10 && date.Day >= 25) || (date.Month == 11 && date.Day == 1);

    // MARK: The switches

    /// <summary>Every switch at once, as the settings hold them.</summary>
    public sealed record Switches
    {
        public bool Enabled { get; init; } = true;
        public IReadOnlySet<Style> On { get; init; } = new HashSet<Style>(Styles);
        public IReadOnlySet<Moment> MomentsOn { get; init; } = new HashSet<Moment>(Moments);
        public Frequency Frequency { get; init; } = Frequency.Sometimes;
        /// <summary>Reduce motion as it stands now, the system's setting already read.</summary>
        public bool ReduceMotion { get; init; }

        public bool Allows(Style style) => Enabled && On.Contains(style) && !(ReduceMotion && style.Busy());
        public bool Allows(Moment moment) => Enabled && MomentsOn.Contains(moment) && !(ReduceMotion && moment.Busy());
    }

    // MARK: When one may play

    /// <summary>Who last wore or marked what, and when, on the colony's clock (seconds).</summary>
    public sealed class Cooldowns
    {
        readonly Dictionary<string, double> last = new();

        static string KeyOf(string what, int? creature) => $"{what}#{creature ?? -1}";

        /// <summary>Whether <paramref name="what"/> may play on <paramref name="creature"/> at <paramref name="now"/>,
        /// <paramref name="every"/> seconds after the last; if so, it counts as played.</summary>
        public bool Take(string what, int? creature, double now, double every)
        {
            var k = KeyOf(what, creature);
            if (last.TryGetValue(k, out var was) && now - was < every) return false;
            last[k] = now;
            return true;
        }

        public double? LastPlayed(string what, int? creature) => last.TryGetValue(KeyOf(what, creature), out var t) ? t : null;

        public void Forget(int creaturesFrom)
        {
            foreach (var k in last.Keys.ToList())
                if (int.TryParse(k[(k.LastIndexOf('#') + 1)..], out var i) && i >= creaturesFrom) last.Remove(k);
        }
    }

    /// <summary>The rules in one place: what the switches allow, the chance of a style and the cooldowns.</summary>
    public sealed class Rules(Switches? switches = null)
    {
        public Switches Switches { get; set; } = switches ?? new Switches();
        public Cooldowns Cooldowns { get; } = new();

        /// <summary>A moment happened to <paramref name="creature"/> (null for the whole screen): whether its effect plays now.</summary>
        public bool TakeMoment(Moment m, int? creature, double now) =>
            Switches.Allows(m) && Cooldowns.Take(m.Code(), creature, now, m.Cooldown());

        /// <summary>Something that can put a style on <paramref name="creature"/> happened; <paramref name="roll"/> is a random
        /// number in [0, 1). The style it puts on, if any: switched on, past its cooldown, and lucky enough for the frequency.
        /// Things that come now and then on their own are rolled by <see cref="NowAndThenChance"/> and always take here.</summary>
        public Style? TakeStyle(Trigger trigger, int creature, double now, double roll)
        {
            var style = trigger.StyleOf();
            if (!Switches.Allows(style)) return null;
            if (!trigger.NowAndThen() && roll >= Switches.Frequency.Chance()) return null;
            var every = Switches.Frequency.CooldownMinutes() * 60;
            return Cooldowns.Take("style." + style.Code(), creature, now, every) ? style : null;
        }

        /// <summary>The chance per check that a now-and-then style comes, checked every <paramref name="step"/> seconds,
        /// so it comes about every <see cref="EveryMinutes"/>.</summary>
        public double NowAndThenChance(double step) => 1 - Math.Exp(-step / (Switches.Frequency.EveryMinutes() * 60));
    }

    /// <summary>The ambient moment (fireflies or the season's particles) to show at <paramref name="date"/>, or null:
    /// fireflies after dark come before the season.</summary>
    public static Moment? AmbientAt(DateTime date, bool isNight, Switches switches)
    {
        if (isNight && switches.Allows(Moment.Night)) return Moment.Night;
        return SeasonOf(date).MomentOf() is { } m && switches.Allows(m) ? m : null;
    }

    /// <summary>Whether the ambient particles are out at <paramref name="elapsed"/> seconds: for <paramref name="seconds"/>
    /// out of every <paramref name="everyMinutes"/>, the first time one whole wait after launch (not at every relaunch).</summary>
    public static bool AmbientShowing(double elapsed, double seconds, double everyMinutes)
    {
        var period = Math.Max(everyMinutes * 60, seconds);
        return elapsed >= period && elapsed % period < seconds;
    }

    /// <summary>Keys pressed in the last hour, from samples of the system's running count: fast typing is over a threshold.</summary>
    public sealed class TypingWatch
    {
        readonly List<(double At, double Count)> samples = new();

        public void Add(double count, double now)
        {
            samples.Add((now, count));
            samples.RemoveAll(s => now - s.At > 3600);
        }

        /// <summary>Keys in the window the samples cover (an hour once there is one).</summary>
        public double KeysInLastHour => samples.Count == 0 ? 0 : Math.Max(0, samples[^1].Count - samples[0].Count);

        /// <summary>How long the samples go back.</summary>
        public double Span => samples.Count == 0 ? 0 : samples[^1].At - samples[0].At;

        /// <summary>A whole hour watched and more than <paramref name="threshold"/> keys in it.</summary>
        public bool Fast(double threshold) => Span >= 3540 && KeysInLastHour >= threshold;

        public void Reset() => samples.Clear();
    }
}

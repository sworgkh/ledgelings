using System.Globalization;

namespace Ledgelings.Core;

/// <summary>
/// Revenge (SPEC §4.7.3): chase a creature with the cursor, or pick it up, too often in a short time
/// and it jumps on the cursor and hangs on to it, telling the user what it thinks of them, until the
/// user shakes it off. What it says follows the cursor mood: a real telling-off in the bad mood, a
/// gleeful turn of the game in the good one, a deadpan remark in the neutral. The same as the Mac's.
///
/// The pieces here have no screen in them: when it is due (<see cref="Fuse"/>), when the cursor has
/// been shaken hard enough (<see cref="Shake"/>), and the words.
/// </summary>
public static partial class Revenge
{
    /// <summary>Counts each creature's hunts over the last <see cref="Window"/> seconds. The
    /// <see cref="After"/>th inside the window makes revenge due, unless the last grab was less than
    /// <see cref="Cooldown"/> seconds ago. Times are the colony's clock.</summary>
    public sealed class Fuse
    {
        public int After { get; set; } = 10;
        public double Window { get; set; } = 120;
        public double Cooldown { get; set; } = 600;
        private readonly Dictionary<int, List<double>> times = new();
        /// <summary>When a creature last grabbed the cursor; nobody grabs again for <see cref="Cooldown"/>.</summary>
        public double LastGrab { get; private set; } = double.NegativeInfinity;

        /// <summary>Creature <paramref name="index"/> was chased or picked up at <paramref name="time"/>.
        /// True when it has had enough and may grab.</summary>
        public bool Hunted(int index, double time)
        {
            var list = (times.GetValueOrDefault(index) ?? new List<double>()).Where(t => time - t <= Window).ToList();
            list.Add(time);
            times[index] = list;
            return list.Count >= After && time - LastGrab >= Cooldown;
        }

        /// <summary>Hunts of <paramref name="index"/> inside the window, as of <paramref name="time"/>.</summary>
        public int Recent(int index, double time) => (times.GetValueOrDefault(index) ?? new List<double>()).Count(t => time - t <= Window);

        /// <summary>A creature grabbed the cursor at <paramref name="time"/>: every count starts over, and the cooldown runs.</summary>
        public void Grabbed(double time)
        {
            LastGrab = time;
            times.Clear();
        }

        /// <summary>Creatures from <paramref name="count"/> on are gone.</summary>
        public void Forget(int count)
        {
            foreach (var k in times.Keys.Where(k => k >= count).ToList()) times.Remove(k);
        }
    }

    /// <summary>Whether the user is shaking the cursor: strokes back and forth. A stroke counts
    /// once it has travelled <see cref="Stroke"/> points one way; turning back after one is a reversal.
    /// <see cref="Needed"/> reversals within <see cref="Window"/> seconds, on either axis, shake the
    /// creature off. Slow drifting and small jitters never add up.</summary>
    public sealed class Shake
    {
        public int Needed { get; }
        public double Stroke { get; }
        public double Window { get; }
        private readonly double[] sign = new double[2], travel = new double[2];
        private readonly List<double> reversals = new();

        public Shake(int needed = 4, double stroke = 20, double window = 2)
        {
            Needed = needed;
            Stroke = stroke;
            Window = window;
        }

        /// <summary>The cursor tried to move by <paramref name="dx"/>, <paramref name="dy"/> points at
        /// <paramref name="time"/>. True once it is shaken off.</summary>
        public bool Moved(double dx, double dy, double time)
        {
            var d = new[] { dx, dy };
            for (int axis = 0; axis < 2; axis++)
            {
                if (d[axis] == 0) continue;
                var s = d[axis] > 0 ? 1.0 : -1.0;
                if (s == sign[axis]) travel[axis] += Math.Abs(d[axis]);
                else
                {
                    if (sign[axis] != 0 && travel[axis] >= Stroke) reversals.Add(time);
                    sign[axis] = s;
                    travel[axis] = Math.Abs(d[axis]);
                }
            }
            reversals.RemoveAll(t => time - t > Window);
            return reversals.Count >= Needed;
        }

        /// <summary>How close to shaken off, 0...1, as of <paramref name="time"/>: how hard the creature wobbles.</summary>
        public double Vigour(double time) =>
            Needed <= 0 ? 1 : Math.Min(1, (double)reversals.Count(t => time - t <= Window) / Needed);
    }

    /// <summary>Holding the pointer still with no limit set, a creature still lets go after this many seconds.</summary>
    public const double PinnedHoldCap = 10;

    /// <summary>How long a grab may last: <paramref name="limit"/> seconds, 0 for until shaken off; never past
    /// <see cref="PinnedHoldCap"/> when the pointer is held still.</summary>
    public static double LongestHold(double limit, bool pinned)
    {
        var l = limit > 0 ? limit : double.PositiveInfinity;
        return pinned ? Math.Min(l, PinnedHoldCap) : l;
    }

    /// <summary>Why a creature let go of the cursor.</summary>
    public enum Release
    {
        /// <summary>Shaken off: it tumbles down and has a last word.</summary>
        Shaken,
        /// <summary>Held as long as it may: it drops, done with the lesson.</summary>
        Tired,
        /// <summary>The Escape key, or the app losing track of the screen (locked, asleep, changed, quitting).</summary>
        Escape,
    }

    // Built-in lines

    /// <summary>What <paramref name="name"/> says as it grabs the cursor, in its own voice, the current language and
    /// <paramref name="mood"/>; <c>{today}</c> and <c>{all}</c> are its hunt count.</summary>
    public static string Line(string name, int today, int all, CursorMood mood, Random rng)
    {
        IReadOnlyList<string> pool = LinesFor(mood).TryGetValue(name, out var own) ? own : AnyoneFor(mood);
        string S(int k) => k.ToString(CultureInfo.InvariantCulture);
        return Banter.Render(rng.Pick(pool), new Dictionary<string, string> { ["today"] = S(today), ["all"] = S(all) });
    }

    /// <summary>What <paramref name="name"/> says as it is shaken off.</summary>
    public static string LastWord(string name, CursorMood mood, Random rng) =>
        rng.Pick(LastWordsFor(mood).TryGetValue(name, out var own) ? own : AnyoneLastWordsFor(mood));

    public static IReadOnlyDictionary<string, string[]> LinesFor(CursorMood mood) => LinesIn(mood, Languages.Current);
    public static IReadOnlyDictionary<string, string[]> LinesIn(CursorMood mood, Language l)
    {
        var english = mood switch { CursorMood.Good => EnglishGoodLines, CursorMood.Neutral => EnglishNeutralLines, _ => EnglishBadLines };
        return Translated.Lists(Shared.In(l)?.RevengeLinesByMood.GetValueOrDefault(mood.Code()), english, t => t);
    }

    public static IReadOnlyList<string> AnyoneFor(CursorMood mood) => AnyoneIn(mood, Languages.Current);
    public static IReadOnlyList<string> AnyoneIn(CursorMood mood, Language l)
    {
        var english = mood switch { CursorMood.Good => EnglishGoodAnyone, CursorMood.Neutral => EnglishNeutralAnyone, _ => EnglishBadAnyone };
        return Translated.List(Shared.In(l)?.RevengeAnyoneByMood.GetValueOrDefault(mood.Code()), english);
    }

    public static IReadOnlyDictionary<string, string[]> LastWordsFor(CursorMood mood) => LastWordsIn(mood, Languages.Current);
    public static IReadOnlyDictionary<string, string[]> LastWordsIn(CursorMood mood, Language l)
    {
        var english = mood switch { CursorMood.Good => EnglishGoodLastWords, CursorMood.Neutral => EnglishNeutralLastWords, _ => EnglishBadLastWords };
        return Translated.Lists(Shared.In(l)?.RevengeLastWordsByMood.GetValueOrDefault(mood.Code()), english, t => t);
    }

    public static IReadOnlyList<string> AnyoneLastWordsFor(CursorMood mood) => AnyoneLastWordsIn(mood, Languages.Current);
    public static IReadOnlyList<string> AnyoneLastWordsIn(CursorMood mood, Language l)
    {
        var english = mood switch
        {
            CursorMood.Good => EnglishGoodAnyoneLastWords, CursorMood.Neutral => EnglishNeutralAnyoneLastWords, _ => EnglishBadAnyoneLastWords,
        };
        return Translated.List(Shared.In(l)?.RevengeAnyoneLastWordsByMood.GetValueOrDefault(mood.Code()), english);
    }

    // For a model

    /// <summary>The model writes the line said while holding the cursor, in the current language and mood.</summary>
    public static string Prompt(CursorMood mood) => PromptIn(mood, Languages.Current);
    public static string PromptIn(CursorMood mood, Language l)
    {
        var english = mood switch { CursorMood.Good => EnglishGoodPrompt, CursorMood.Neutral => EnglishNeutralPrompt, _ => EnglishBadPrompt };
        var translated = Shared.In(l)?.RevengePromptByMood.GetValueOrDefault(mood.Code());
        return string.IsNullOrEmpty(translated) ? english : translated;
    }

    public const string EnglishBadPrompt =
        "{situation}\n" +
        "The person whose screen you live on has chased you with the mouse cursor and picked you up far too often: " +
        "{times} times in the last few minutes. So you took revenge: you jumped on their cursor and are hanging on to it, " +
        "so they cannot use it until they shake you off. Say ONE line to them, shaming them for how they treat you, " +
        "in your own voice. At most 20 words. Output only the line: no quotes, no name.";

    public const string EnglishGoodPrompt =
        "{situation}\n" +
        "The person whose screen you live on plays tag with you with the mouse cursor, and has chased you " +
        "{times} times in the last few minutes. So you turned the game round: you jumped on their cursor and are " +
        "clinging to it, gleefully, until they shake you off. Say ONE line to them, teasing and delighted, " +
        "in your own voice. At most 20 words. Output only the line: no quotes, no name.";

    public const string EnglishNeutralPrompt =
        "{situation}\n" +
        "The person whose screen you live on has chased you with the mouse cursor and picked you up " +
        "{times} times in the last few minutes. So you grabbed their cursor and are holding on to it until they " +
        "shake you off. Say ONE line to them about it, deadpan and matter-of-fact, in your own voice. " +
        "At most 20 words. Output only the line: no quotes, no name.";
}

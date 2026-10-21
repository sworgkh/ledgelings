using System.Globalization;

namespace Ledgelings.Core;

/// <summary>
/// A pair's storyline: everything two characters have lived through together,
/// kept small enough to send with every new story.
///
/// Each thing they share is a <b>moment</b> (a talk, a tea party, a flower, a paper
/// plane, a cursor grab one of them pulled off with the other there). Moments
/// pile up until the next story is written; then they are folded into the
/// pair's <b>chronicle</b>, a few dozen words of "their story so far", and start
/// again. The model rewrites the chronicle itself in the same call that writes
/// the plot (<c>STORY:</c>); without a model, or when it sends none, the moments are
/// folded in plainly, a sentence per kind, the oldest sentences dropping off
/// once it is too long. A <b>tally</b> counts every moment ever. The macOS app's
/// <c>Bonds+Storyline.swift</c>, the same file format.
/// </summary>
public static partial class Bonds
{
    /// <summary>The kinds of moment, as written in <c>bonds.json</c>.</summary>
    public static class MomentKind
    {
        public const string Talk = "talk", Tea = "tea", Flower = "flower", Plane = "plane", Grab = "grab", Play = "play";
        /// <summary>In the order the tally and the folding list them.</summary>
        public static readonly IReadOnlyList<string> All = new[] { Talk, Tea, Flower, Plane, Grab, Play };
    }

    public sealed record Moment
    {
        public DateTimeOffset Time { get; set; }
        public string Kind { get; set; } = MomentKind.Talk;
        /// <summary>Who did it: the first to speak, the giver, the thrower, the grabber.</summary>
        public string Who { get; set; } = "";
        /// <summary>The first line said, the flower given, the note sent, the game played (<see cref="Plays.Kind"/>); null for a grab.</summary>
        public string? Detail { get; set; }
        /// <summary>A game's score as its board showed it: "3-2".</summary>
        public string? Score { get; set; }
        /// <summary>A game's winners; empty for a draw, null when the game has no winner (the rope).</summary>
        public List<string>? Winners { get; set; }
        /// <summary>Who asked for it: the one whose invitation started the game.</summary>
        public string? Asked { get; set; }

        public Moment() { }
        public Moment(DateTimeOffset time, string kind, string who, string? detail = null,
                      string? score = null, IEnumerable<string>? winners = null, string? asked = null)
        {
            Time = time; Kind = kind; Who = who; Detail = detail;
            Score = score; Winners = winners?.ToList(); Asked = asked;
        }

        public bool Equals(Moment? o) => o is not null && o.Time == Time && o.Kind == Kind && o.Who == Who && o.Detail == Detail
            && o.Score == Score && o.Asked == Asked && (o.Winners is null ? Winners is null : Winners is not null && o.Winners.SequenceEqual(Winners));
        public override int GetHashCode() => HashCode.Combine(Time, Kind, Who, Detail);
    }

    /// <summary>Moments kept per pair between stories; the prompt shows the last few of them.</summary>
    public const int MomentsKept = 20;
    /// <summary>The chronicle's length by default, in words.</summary>
    public const int StoryWords = 80;
    /// <summary>Moments the prompt shows one by one by default; any older are folded first.</summary>
    public const int StoryMoments = 8;

    /// <summary>How much of their history a new story is told with.</summary>
    public readonly record struct Telling(int Words = StoryWords, int Moments = StoryMoments)
    {
        public Telling() : this(StoryWords, StoryMoments) { }
    }

    public sealed partial class Book
    {
        /// <summary>Something the two lived through together: a moment of their storyline.</summary>
        public void Note(string a, string b, Moment moment)
        {
            if (a == b) return;
            Update(a, b, bond =>
            {
                bond.Moments = bond.Moments.Append(moment).TakeLast(MomentsKept).ToList();
                bond.Tally[moment.Kind] = bond.Tally.GetValueOrDefault(moment.Kind) + 1;
                if (bond.Met is not DateTimeOffset met || moment.Time < met) bond.Met = moment.Time;
                Keep(moment, bond);
            });
        }

        /// <summary>Their past in the chat log, from before moments were kept: every
        /// conversation both spoke in, older than the first moment kept, read in
        /// once. The newest become moments, all of them count.</summary>
        public void Seed(string a, string b, IEnumerable<ChatLog.Exchange> exchanges)
        {
            if (a == b || Bond(a, b)?.Seeded == true) return;
            Update(a, b, bond =>
            {
                bond.Seeded = true;
                var before = bond.Moments.FirstOrDefault()?.Time ?? DateTimeOffset.MaxValue;
                var shared = exchanges.Where(e => e.Time < before && e.Lines.Any(l => l.Speaker == a) && e.Lines.Any(l => l.Speaker == b))
                    .OrderBy(e => e.Time).ToList();
                if (shared.Count == 0) return;
                var old = shared.Select(e => new Moment(e.Time, MomentKind.Talk, e.Lines[0].Speaker, e.Lines[0].Text));
                bond.Moments = old.Concat(bond.Moments).TakeLast(MomentsKept).ToList();
                bond.Tally[MomentKind.Talk] = bond.Tally.GetValueOrDefault(MomentKind.Talk) + shared.Count;
                if (bond.Met is not DateTimeOffset met || shared[0].Time < met) bond.Met = shared[0].Time;
            });
        }
    }

    // MARK: For the prompt

    /// <summary>Their story so far and what has happened since, as the plot prompt has
    /// them: moments beyond the last <see cref="Telling.Moments"/> are folded into the
    /// chronicle first, so nothing kept is left out and the prompt stays small.</summary>
    public static (string Story, string Since) History(Bond bond, Telling telling, DateTimeOffset now)
    {
        var shown = bond.Moments.TakeLast(Math.Max(1, telling.Moments)).ToList();
        var older = bond.Moments.Take(bond.Moments.Count - shown.Count).ToList();
        var story = older.Count == 0 ? bond.Chronicle : Fold(bond.Chronicle, older, bond.Names, null, telling.Words);
        var opening = story ?? "";
        if (bond.Met is DateTimeOffset met && bond.Tally.Count > 0)
        {
            var since = L10n.Tr("They first met on %@; all told: %@.", Day(met), Tallied(bond.Tally));
            opening = opening.Length == 0 ? since : since + " " + opening;
        }
        var lines = shown.Select(m => "- " + Day(m.Time) + ": " + Describe(m, bond.Names)).ToList();
        return (opening.Length == 0 ? L10n.Tr("nothing yet; they have only just met") : opening,
                lines.Count == 0 ? L10n.Tr("(nothing yet)") : string.Join("\n", lines));
    }

    /// <summary>"14 Oct", in the current language: the chronicle keeps dates, never "today".</summary>
    public static string Day(DateTimeOffset date)
    {
        var culture = CultureInfo.GetCultureInfo(Languages.Current == Language.Russian ? "ru-RU" : "en-GB");
        return date.ToLocalTime().ToString("d MMM", culture);
    }

    /// <summary>"5 talks, 2 tea parties, 1 flower": everything they ever did together.</summary>
    public static string Tallied(IReadOnlyDictionary<string, int> tally) =>
        string.Join(", ", MomentKind.All.Where(k => tally.TryGetValue(k, out var n) && n > 0).Select(k => Count(tally[k], k)));

    internal static string Count(int n, string kind) => kind switch
    {
        MomentKind.Tea => L10n.TrCount(n, "tea party", "tea parties"),
        MomentKind.Flower => L10n.TrCount(n, "flower", "flowers"),
        MomentKind.Plane => L10n.TrCount(n, "paper plane", "paper planes"),
        MomentKind.Grab => L10n.TrCount(n, "cursor grab", "cursor grabs"),
        MomentKind.Play => L10n.TrCount(n, "game", "games"),
        _ => L10n.TrCount(n, "talk", "talks"),
    };

    /// <summary>One moment in a few words: <c>Pip and Blocky talked; Pip said: "Hi!"</c>.</summary>
    public static string Describe(Moment moment, IReadOnlyList<string> names)
    {
        var other = names.FirstOrDefault(n => n != moment.Who) ?? moment.Who;
        var said = moment.Detail is string d ? Short(d) : "";
        return moment.Kind switch
        {
            MomentKind.Tea => L10n.Tr("%1$@ and %2$@ had a tea party; %1$@ told a story: \"%3$@\"", moment.Who, other, said),
            MomentKind.Flower => L10n.Tr("%1$@ gave %2$@ a %3$@", moment.Who, other, Gifts.Name(moment.Detail ?? "")),
            MomentKind.Plane => L10n.Tr("%1$@ sent %2$@ a paper plane: \"%3$@\"", moment.Who, other, said),
            MomentKind.Grab => L10n.Tr("%1$@ grabbed the cursor while %2$@ looked on", moment.Who, other),
            MomentKind.Play => Result(moment) is string r
                ? L10n.Tr("%1$@ and %2$@ played: %3$@", moment.Who, other, Plays.Name(moment.Detail)) + " (" + r + ")"
                : L10n.Tr("%1$@ and %2$@ played: %3$@", moment.Who, other, Plays.Name(moment.Detail)),
            _ => L10n.Tr("%1$@ and %2$@ talked; %1$@ said: \"%3$@\"", moment.Who, other, said),
        };
    }

    /// <summary>A line cut to its first dozen words, for a moment.</summary>
    internal static string Short(string text, int words = 12)
    {
        var all = text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        return all.Length <= words ? string.Join(" ", all) : string.Join(" ", all.Take(words)) + "…";
    }

    // MARK: Folding, without a model

    /// <summary>The chronicle with <paramref name="moments"/> folded in plainly: a sentence per kind of
    /// moment (how many, between which days, the latest of them), then the story
    /// that just ended, all kept to <paramref name="words"/> words by dropping the oldest sentences.</summary>
    public static string? Fold(string? chronicle, IReadOnlyList<Moment> moments, IReadOnlyList<string> names, string? lastPlot, int words)
    {
        var sentences = chronicle is null ? new List<string>() : Sentences(chronicle);
        foreach (var kind in MomentKind.All)
        {
            var these = moments.Where(m => m.Kind == kind).ToList();
            if (these.Count == 0) continue;
            Moment first = these[0], last = these[^1];
            var when = Day(first.Time) == Day(last.Time) ? L10n.Tr("On %@", Day(last.Time))
                : L10n.Tr("Between %@ and %@", Day(first.Time), Day(last.Time));
            var what = these.Count == 1 ? Describe(last, names)
                : L10n.Tr("%@ in all, the last: %@", Count(these.Count, kind), Describe(last, names));
            var sentence = L10n.Tr("%@, %@", when, what);
            // A quoted line that ends its own sentence needs no second full stop.
            var bare = sentence.TrimEnd('"', '»', '”');
            sentences.Add(bare.Length > 0 && ".!?…".Contains(bare[^1]) ? sentence : sentence + ".");
        }
        if (lastPlot is not null) sentences.Add(L10n.Tr("Then this story played out: %@", lastPlot));
        if (sentences.Count == 0) return chronicle;
        return Trimmed(string.Join(" ", sentences), words);
    }

    /// <summary><paramref name="text"/> kept to <paramref name="words"/> words: whole sentences from the end, newest kept;
    /// a single sentence longer than that is cut with "…".</summary>
    public static string Trimmed(string text, int words)
    {
        var limit = Math.Max(1, words);
        var kept = new List<string>();
        var count = 0;
        foreach (var sentence in Enumerable.Reverse(Sentences(text)))
        {
            var n = sentence.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;
            if (count + n > limit) break;
            kept.Insert(0, sentence);
            count += n;
        }
        return kept.Count == 0 ? Short(text, limit) : string.Join(" ", kept);
    }

    /// <summary><paramref name="text"/> cut into sentences; a quoted line ("Tea? I baked a pixel.") stays whole.</summary>
    internal static List<string> Sentences(string text)
    {
        var output = new List<string>();
        var current = new System.Text.StringBuilder();
        var quoted = false;
        for (int i = 0; i < text.Length; i++)
        {
            var c = text[i];
            current.Append(c);
            if (c == '"') quoted = !quoted;
            else if (c == '«' || c == '“') quoted = true;
            else if (c == '»' || c == '”') quoted = false;
            var stop = ".!?…".Contains(c);
            var closes = "\"»”".Contains(c) && i > 0 && ".!?…".Contains(text[i - 1]);
            var ends = !quoted && (stop || closes) && (i + 1 == text.Length || char.IsWhiteSpace(text[i + 1]));
            if (!ends) continue;
            var s = current.ToString().Trim();
            if (s.Length > 0) output.Add(s);
            current.Clear();
        }
        var rest = current.ToString().Trim();
        if (rest.Length > 0) output.Add(rest);
        return output;
    }

    // MARK: A story without a model

    /// <summary>The next story from the built-in lines, no network: it grows from the
    /// most telling thing they lived through since the last one (a flower over a
    /// tea party over a plane over a grab over a talk), with when it was, and a
    /// bond line from everything they ever did together, unless they already have one.</summary>
    public static Written BuiltInPlot(Bond bond, DateTimeOffset now, Random rng)
    {
        var order = new[] { MomentKind.Flower, MomentKind.Tea, MomentKind.Play, MomentKind.Plane, MomentKind.Grab, MomentKind.Talk };
        var moment = order.Select(k => bond.Moments.LastOrDefault(m => m.Kind == k)).FirstOrDefault(m => m is not null);
        var names = bond.Names;
        string a = names.FirstOrDefault() ?? "", b = names.LastOrDefault() ?? "";
        string[] choices;
        if (moment is not null)
        {
            var who = moment.Who;
            var other = names.FirstOrDefault(n => n != who) ?? who;
            var when = Ago(moment.Time, now);
            var said = moment.Detail is string d ? Short(d, 8) : "";
            choices = moment.Kind switch
            {
                MomentKind.Flower => new[]
                {
                    L10n.Tr("Since %1$@ gave %2$@ the %3$@ %4$@, %2$@ has been looking for a gift to give back.", who, other, Gifts.Name(moment.Detail ?? ""), when),
                    L10n.Tr("%2$@ has kept the %3$@ %1$@ gave %4$@, and wants to know what it means.", who, other, Gifts.Name(moment.Detail ?? ""), when),
                },
                MomentKind.Tea => new[]
                {
                    L10n.Tr("Ever since the tea party %3$@, %2$@ wants to hear how %1$@'s story ends.", who, other, when),
                    L10n.Tr("%1$@ is planning another tea party for %2$@, better than the one %3$@.", who, other, when),
                },
                MomentKind.Plane => new[]
                {
                    L10n.Tr("%2$@ still has the paper plane %1$@ sent %3$@ (\"%4$@\") and is writing an answer.", who, other, when, said),
                    L10n.Tr("%1$@ waits for %2$@ to answer the paper plane from %3$@.", who, other, when),
                },
                MomentKind.Play => new[]
                {
                    L10n.Tr("%2$@ wants a rematch of %3$@ with %1$@, after %4$@.", who, other, Plays.Name(moment.Detail), when),
                    L10n.Tr("%1$@ has been practising since %3$@ with %2$@ %4$@, and means to win next time.", who, other, Plays.Name(moment.Detail), when),
                },
                MomentKind.Grab => new[]
                {
                    L10n.Tr("%2$@ cannot decide whether %1$@ grabbing the cursor %3$@ was brave or silly.", who, other, when),
                    L10n.Tr("%1$@ wants %2$@ to help grab the cursor next time, after %3$@.", who, other, when),
                },
                _ => new[]
                {
                    L10n.Tr("%2$@ keeps coming back to what %1$@ said %3$@: \"%4$@\"", who, other, when, said),
                    L10n.Tr("%1$@ and %2$@ have not settled what they talked about %3$@.", who, other, when),
                },
            };
        }
        else
        {
            choices = new[]
            {
                L10n.Tr("%@ and %@ take turns guarding their favourite corner of the screen.", a, b),
                L10n.Tr("%@ and %@ share a secret about the bottom edge.", a, b),
            };
        }
        var plot = rng.Pick(choices);
        // A bond line a model once wrote says more than a count: it stays.
        var total = bond.Tally.Values.Sum();
        var summary = bond.Summary is not null || total == 0 ? bond.Summary
            : total >= 10 ? L10n.Tr("After %@, they know each other well.", Tallied(bond.Tally))
            : L10n.Tr("After %@, they are getting to know each other.", Tallied(bond.Tally));
        return new Written(summary, plot);
    }

    /// <summary>"today", "yesterday", "3 days ago": when a moment was, from now.</summary>
    public static string Ago(DateTimeOffset time, DateTimeOffset now)
    {
        var days = (int)(now.ToLocalTime().Date - time.ToLocalTime().Date).TotalDays;
        if (days <= 0) return L10n.Tr("today");
        if (days == 1) return L10n.Tr("yesterday");
        if (days < 14) return L10n.Tr("%@ ago", L10n.TrCount(days, "day", "days"));
        return L10n.Tr("%@ ago", L10n.TrCount(days / 7, "week", "weeks"));
    }

    /// <summary>The shipped plot prompt from before storylines, word for word: a saved copy of
    /// it was never edited, so it loads as the current prompt rather than staying the user's.</summary>
    public const string EnglishPlotPromptV1 =
        "Do not write their conversations. Write only the two lines described at the end.\n" +
        "\n" +
        "Two small creatures live on the edges of a computer screen and have shared it for {together}.\n" +
        "{speaker}, {speakerKind}: {speakerPersona}\n" +
        "{listener}, {listenerKind}: {listenerPersona}\n" +
        "How they get on so far: {bond}\n" +
        "Their last story: {lastPlot}\n" +
        "What they said lately:\n" +
        "{recent}\n" +
        "\n" +
        "Think up what happens between them over their next {length} conversations: a small plot (a rivalry, a secret, " +
        "a favour owed, a shared plan, a misunderstanding, a crush), true to both of them and growing from how they get on.\n" +
        "\n" +
        "Answer with exactly these two lines and nothing else:\n" +
        "BOND: how they get on now, at most 15 words\n" +
        "PLOT: the story to play out, at most 30 words";

    /// <summary>The Russian of <see cref="EnglishPlotPromptV1"/>, as the Mac shipped it.</summary>
    public const string RussianPlotPromptV1 =
        "Не пиши их разговоры. Напиши только две строки, описанные в конце.\n" +
        "\n" +
        "Два маленьких существа живут на краях экрана компьютера. Сколько они уже делят его: {together}.\n" +
        "{speaker}, {speakerKind}: {speakerPersona}\n" +
        "{listener}, {listenerKind}: {listenerPersona}\n" +
        "Как они ладят до сих пор: {bond}\n" +
        "Их прошлая история: {lastPlot}\n" +
        "Что они говорили недавно:\n" +
        "{recent}\n" +
        "\n" +
        "Придумай, что произойдёт между ними в ближайших разговорах (их будет столько: {length}): маленький сюжет (соперничество, секрет, " +
        "должок, общий план, недоразумение, влюблённость), верный им обоим и вырастающий из того, как они ладят.\n" +
        "\n" +
        "Ответь ровно этими двумя строками и ничем больше. Метки BOND: и PLOT: оставь как есть, латиницей; текст после них — по-русски:\n" +
        "BOND: как они ладят теперь, не больше 15 слов\n" +
        "PLOT: история, которую им предстоит разыграть, не больше 30 слов";

    public static readonly IReadOnlyList<string> EarlierPlotPrompts = new[] { EnglishPlotPromptV1, RussianPlotPromptV1 };
}

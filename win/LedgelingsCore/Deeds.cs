using System.Text.RegularExpressions;

namespace Ledgelings.Core;

/// <summary>
/// Deeds: what a creature does because of what it said or read (SPEC §6.5.2.2). The Mac's <c>Deeds.swift</c>.
///
/// A conversation used to be words only: a letter saying "soccer?" changed
/// nothing on screen. Now the line a creature says may end with a tag,
/// <c>DO: invite soccer</c>, the way a story's answer carries <c>BOND:</c> and <c>PLOT:</c>.
/// The list of deeds is closed and small (an invitation to a game or to tea,
/// an answer to one, a flower, a letter, a visit, following someone, going to
/// sleep), and each prompt offers only the ones possible right now (<see cref="Options"/>).
/// Whatever comes back is checked against what was offered (<see cref="Check"/>) and
/// against the limits the owner set (<see cref="Ledger"/>), so an unknown, impossible or
/// too-frequent deed is simply ignored: the words stay, nothing moves.
///
/// The tag never reaches a bubble or a voice: <see cref="Split"/> takes it off the line.
/// Without a model, the built-in lines invite and answer in each character's
/// own voice (<c>Deeds.Lines.cs</c>), and chance decides the answer.
/// </summary>
public static partial class Deeds
{
    /// <summary>What one creature can invite another to: a game they play together (<paramref name="Kind"/>), or tea (no kind).</summary>
    public readonly record struct Offer(Plays.Kind? Kind)
    {
        public static Offer Game(Plays.Kind kind) => new(kind);
        public static Offer Tea => new(null);
        public bool IsTea => Kind is null;

        /// <summary>As the tag says it: <c>soccer</c>, <c>tea</c>.</summary>
        public string Tag => Kind is Plays.Kind k ? k.Raw() : "tea";

        /// <summary>From a tag word, English or Russian: <c>soccer</c>, <c>футбол</c>, <c>tea</c>, <c>чай</c>.</summary>
        public static Offer? FromWord(string word)
        {
            var w = word.ToLowerInvariant();
            if (w is "tea" or "чай" or "чаепитие" or "чаю") return Tea;
            if (Plays.FromRaw(w) is Plays.Kind kind && Invitable.Contains(kind)) return Game(kind);
            Plays.Kind? alias = w switch
            {
                "catch" or "салки" or "догонялки" => Plays.Kind.Tag,
                "football" or "футбол" => Plays.Kind.Soccer,
                "баскетбол" or "hoops" => Plays.Kind.Basketball,
                "бейсбол" => Plays.Kind.Baseball,
                _ => null,
            };
            return alias is Plays.Kind a ? Game(a) : null;
        }

        /// <summary>In a word, as a line says it: "Soccer", "Tea together".</summary>
        public string Word => Kind switch
        {
            Plays.Kind.Tag => L10n.Tr("Catch-me-if-you-can"),
            Plays.Kind.Basketball => L10n.Tr("Basketball"),
            Plays.Kind.Soccer => L10n.Tr("Soccer"),
            Plays.Kind.Baseball => L10n.Tr("Baseball"),
            Plays.Kind k => k.Title(),
            null => L10n.Tr("Tea together"),
        };

        /// <summary>For a prompt or a fact: "a game of soccer", "tea together".</summary>
        public string Title => Kind is Plays.Kind k ? k.Title() : L10n.Tr("tea together");
    }

    /// <summary>The games one can be invited to: the ones two or more play. The rope and
    /// the parachute are played alone.</summary>
    public static readonly IReadOnlyList<Plays.Kind> Invitable = new[] { Plays.Kind.Tag, Plays.Kind.Basketball, Plays.Kind.Soccer, Plays.Kind.Baseball };

    /// <summary>One deed. A proposal to play or have tea is an invitation: it happens only
    /// once the other says yes. <paramref name="Verb"/> is the kind of deed, for limits and for the trace;
    /// <paramref name="Offered"/> what an invitation is to; <paramref name="Name"/> whom a visit is to.</summary>
    public sealed record Deed(string Verb, Offer? Offered = null, string? Name = null)
    {
        public static Deed Invite(Offer offer) => new("invite", offer);
        public static readonly Deed Accept = new("accept");
        public static readonly Deed Decline = new("decline");
        public static readonly Deed Flower = new("flower");
        public static readonly Deed Letter = new("letter");
        public static Deed Visit(string name) => new("visit", null, name);
        public static readonly Deed Follow = new("follow");
        public static readonly Deed Sleep = new("sleep");

        /// <summary>As the tag writes it: <c>invite soccer</c>, <c>visit Boo</c>.</summary>
        public string Tag => Verb switch
        {
            "invite" => "invite " + Offered?.Tag,
            "visit" => "visit " + Name,
            _ => Verb,
        };
    }

    // MARK: Reading the tag

    /// <summary>A line as the model wrote it, taken apart: the words to say, the deed, and
    /// a fact to remember (<c>NOTE:</c>). <paramref name="Unknown"/>: a <c>DO:</c> that named no deed.</summary>
    public sealed record Tagged(string Text, Deed? Deed = null, string? Note = null, string? Unknown = null);

    private static readonly Regex Tags = new(@"(?:\bDO|\bNOTE|(?m:^)\s*[\[*(]*\s*(?i:do|note))\s*:", RegexOptions.CultureInvariant);

    private static string Trimmed(string s, string extra)
    {
        bool Off(char c) => char.IsWhiteSpace(c) || extra.Contains(c);
        int start = 0, end = s.Length;
        while (start < end && Off(s[start])) start++;
        while (end > start && Off(s[end - 1])) end--;
        return s[start..end];
    }

    /// <summary><paramref name="raw"/> with its <c>DO:</c> and <c>NOTE:</c> tags taken off, wherever they are: on a
    /// line of their own, at the end of the line, in brackets or stars. A model's
    /// thinking (<c>&lt;think&gt;…&lt;/think&gt;</c>) is left in place for <see cref="Banter.CleanLine"/>.</summary>
    public static Tagged Split(string raw)
    {
        // Only what comes after the thinking can carry a tag.
        var close = raw.IndexOf("</think>", StringComparison.Ordinal);
        var start = close >= 0 ? close + "</think>".Length : 0;
        var after = raw[start..];
        var matches = Tags.Matches(after);
        if (matches.Count == 0) return new Tagged(raw);
        var text = Trimmed(raw[..(start + matches[0].Index)], "[(*");
        Deed? deed = null;
        string? note = null, unknown = null;
        for (int n = 0; n < matches.Count; n++)
        {
            var match = matches[n];
            var end = n + 1 < matches.Count ? matches[n + 1].Index : after.Length;
            var label = match.Value.ToUpperInvariant();
            var rest = after[(match.Index + match.Length)..end];
            var first = rest.Split(new[] { '\n', '\r', '\u2028', '\u2029', '\u0085' }, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? "";
            var value = Trimmed(first, "[]()*\"'`«».");
            if (label.Contains("NOTE"))
            {
                if (note is null && value.Length > 0) note = value.Length > 160 ? value[..160] : value;
            }
            else if (deed is null && unknown is null)
            {
                var (known, read) = Parse(value);
                if (!known) unknown = value;
                else if (read is not null) deed = read;          // known and null: "none"
            }
        }
        return new Tagged(text, deed, note, unknown);
    }

    /// <summary>One tag's value: known with a deed, known with none ("none"), or not known at all.</summary>
    public static (bool Known, Deed? Deed) Parse(string value)
    {
        var words = value.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)
            .SelectMany(w => w.Split(new[] { ',', ':' }, StringSplitOptions.RemoveEmptyEntries)).ToList();
        if (words.Count == 0) return (true, null);
        var head = words[0].ToLowerInvariant();
        var rest = words.Skip(1).ToList();
        switch (head)
        {
            case "none" or "nothing" or "-" or "—" or "ничего":
                return (true, null);
            case "invite" or "play" or "ask" or "propose" or "пригласить" or "играть":
            {
                var word = rest.FirstOrDefault(w => w.ToLowerInvariant() is not ("to" or "a" or "game" or "of" or "в"));
                return word is not null && Offer.FromWord(word) is Offer offer ? (true, Deed.Invite(offer)) : (false, null);
            }
            case "accept" or "yes" or "agree" or "ok" or "okay" or "да" or "принять":
                return (true, Deed.Accept);
            case "decline" or "no" or "refuse" or "нет" or "отказ" or "отказать":
                return (true, Deed.Decline);
            case "flower" or "give" or "gift" or "цветок":
                return (true, Deed.Flower);
            case "letter" or "write" or "plane" or "письмо":
                return (true, Deed.Letter);
            case "visit" or "go" or "walk":
            {
                var name = string.Join(" ", rest.Where(w => w.ToLowerInvariant() is not ("to" or "see")));
                if (name.ToLowerInvariant() is "sleep" or "bed") return (true, Deed.Sleep);
                return name.Length == 0 ? (false, null) : (true, Deed.Visit(name));
            }
            case "follow" or "следовать":
                return (true, Deed.Follow);
            case "sleep" or "nap" or "bed" or "спать":
                return (true, Deed.Sleep);
            default:
                return Offer.FromWord(head) is Offer o ? (true, Deed.Invite(o)) : (false, null);
        }
    }

    // MARK: What is offered

    /// <summary>An invitation waiting for its answer. Times are the colony's clock.
    /// <paramref name="ByLetter"/>: sent in a paper plane, so the answer comes in the plane back.</summary>
    public sealed record Invitation(string From, string To, Offer Offer, double At, bool ByLetter);

    /// <summary>The deeds one creature may take right now, with the one it is speaking to.</summary>
    public sealed class Options
    {
        public List<Plays.Kind> Games { get; set; } = new();
        public bool Tea { get; set; }
        public bool Flower { get; set; }
        public bool Letter { get; set; }
        /// <summary>Who it could walk over to: on screen, awake, not the one it is talking to.</summary>
        public List<string> Visit { get; set; } = new();
        public bool Follow { get; set; }
        public bool Sleep { get; set; }
        /// <summary>The invitation it is answering, if any.</summary>
        public Invitation? Answering { get; set; }

        public bool IsEmpty => Games.Count == 0 && !Tea && !Flower && !Letter && Visit.Count == 0 && !Follow && !Sleep && Answering is null;

        /// <summary>Each offered deed as its tag says it.</summary>
        public List<string> Tags
        {
            get
            {
                var output = Games.Select(g => "invite " + g.Raw()).ToList();
                if (Tea) output.Add("invite tea");
                if (Flower) output.Add("flower");
                if (Letter) output.Add("letter");
                output.AddRange(Visit.Select(v => "visit " + v));
                if (Follow) output.Add("follow");
                if (Sleep) output.Add("sleep");
                return output;
            }
        }
    }

    /// <summary>Why a deed is not done. Traced, never shown.</summary>
    public enum Refusal { NotOffered, NothingToAnswer, TooSoon, TooMany, PairTooSoon, LoopGuard, NotFree, Lapsed }

    /// <summary>The reason in words, as the trace writes it.</summary>
    public static string Text(this Refusal r) => r switch
    {
        Refusal.NotOffered => "not offered",
        Refusal.NothingToAnswer => "nothing to answer",
        Refusal.TooSoon => "too soon after the last deed",
        Refusal.TooMany => "too many deeds this hour",
        Refusal.PairTooSoon => "this pair did that lately",
        Refusal.LoopGuard => "this pair just did something",
        Refusal.NotFree => "not free",
        _ => "waited too long",
    };

    /// <summary>Whether <paramref name="deed"/> was one of the <paramref name="options"/>.</summary>
    public static Refusal? Check(Deed deed, Options options) => deed.Verb switch
    {
        "invite" when deed.Offered is { Kind: Plays.Kind kind } => options.Games.Contains(kind) ? null : Refusal.NotOffered,
        "invite" => options.Tea ? null : Refusal.NotOffered,
        "accept" or "decline" => options.Answering is null ? Refusal.NothingToAnswer : null,
        "flower" => options.Flower ? null : Refusal.NotOffered,
        "letter" => options.Letter ? null : Refusal.NotOffered,
        "visit" => options.Visit.Any(v => string.Equals(v, deed.Name, StringComparison.OrdinalIgnoreCase)) ? null : Refusal.NotOffered,
        "follow" => options.Follow ? null : Refusal.NotOffered,
        "sleep" => options.Sleep ? null : Refusal.NotOffered,
        _ => Refusal.NotOffered,
    };

    // MARK: How often

    /// <summary>The owner's limits, in seconds and counts. Zero turns a limit off; the
    /// loop guard stays, so two creatures can never set each other off forever.
    /// <paramref name="Gap"/>: after a deed, the next one anywhere waits this long. <paramref name="PerHour"/>: most
    /// deeds started in an hour; 0: no limit. <paramref name="PairGap"/>: the same pair takes the same deed again only after this.</summary>
    public readonly record struct Limits(double Gap, int PerHour, double PairGap);

    /// <summary>Seconds the same pair waits between any two deeds, whatever the settings say.</summary>
    public const double LoopGuard = 15.0;

    /// <summary>The deeds done lately, to keep them within the limits.</summary>
    public sealed class Ledger
    {
        public sealed record Entry(double At, string Pair, string Verb);
        public List<Entry> Done { get; } = new();

        /// <summary>Why <paramref name="verb"/> between <paramref name="a"/> and <paramref name="b"/> may not start now, or null when it may.
        /// Answers (accept, decline) are free: the invitation was counted.</summary>
        public Refusal? RefusalFor(string verb, string a, string b, double now, Limits limits)
        {
            if (verb is "accept" or "decline") return null;
            var pair = Bonds.Key(a, b);
            if (Done.Any(e => e.Pair == pair && now - e.At < LoopGuard)) return Refusal.LoopGuard;
            if (Done.LastOrDefault() is { } last && limits.Gap > 0 && now - last.At < limits.Gap) return Refusal.TooSoon;
            if (limits.PerHour > 0 && Done.Count(e => now - e.At < 3600) >= limits.PerHour) return Refusal.TooMany;
            if (limits.PairGap > 0 && Done.Any(e => e.Pair == pair && e.Verb == verb && now - e.At < limits.PairGap)) return Refusal.PairTooSoon;
            return null;
        }

        public void Record(string verb, string a, string b, double now)
        {
            Done.Add(new Entry(now, Bonds.Key(a, b), verb));
            // Four hours: the longest pair gap the settings allow.
            Done.RemoveAll(e => now - e.At > 4 * 3600);
        }
    }

    // MARK: The prompt

    public static string MenuText => Shared.Prompt("deedMenu", EnglishMenu);
    public const string EnglishMenu =
        "If what you say means you really do something, end your answer with one more line: DO: and one of these: {deeds} | none. " +
        "Most lines need no deed: then write DO: none, or nothing.";
    public static string AnswerText => Shared.Prompt("deedAnswer", EnglishAnswer);
    public const string EnglishAnswer = "{inviter} has invited you to {offer}. End your answer with DO: accept or DO: decline, as you would really answer.";
    public static string NoteText => Shared.Prompt("deedNote", EnglishNote);
    public const string EnglishNote =
        "If you learn something about {listener} worth remembering for weeks (a promise, a debt, a secret, a rivalry, something they love or hate), " +
        "you may add a line NOTE: and it, in at most 12 words.";

    /// <summary>What the prompt says about deeds for <paramref name="options"/>; "" when nothing is offered.
    /// <paramref name="notes"/>: the model may also write a fact down (<c>NOTE:</c>), about <paramref name="listener"/>.</summary>
    public static string Prompt(Options options, bool notes = false, string listener = "")
    {
        var parts = new List<string>();
        if (options.Answering is { } invitation)
            parts.Add(Banter.Render(AnswerText, new Dictionary<string, string> { ["inviter"] = invitation.From, ["offer"] = invitation.Offer.Title }));
        var tags = options.Tags;
        if (tags.Count > 0) parts.Add(Banter.Render(MenuText, new Dictionary<string, string> { ["deeds"] = string.Join(" | ", tags) }));
        if (notes) parts.Add(Banter.Render(NoteText, new Dictionary<string, string> { ["listener"] = listener }));
        return string.Join(" ", parts);
    }

    // MARK: Without a model

    /// <summary>Whether a built-in answer is yes: <paramref name="chance"/> percent for a pair who barely
    /// know each other, up to half again as likely for the closest friends.</summary>
    public static bool BuiltInYes(double closeness, double chance, Random rng)
    {
        var p = Math.Min(1, Math.Max(0, chance / 100) * (0.75 + 0.5 * Math.Min(Math.Max(closeness, 0), 1)));
        return rng.NextDouble() < p;
    }

    /// <summary>What a built-in invitation is to: a rematch of the game the inviter last
    /// lost to this one if it is offered, else any offered game or tea.</summary>
    public static Offer? BuiltInOffer(Options options, Random rng, Plays.Kind? rematch = null)
    {
        if (rematch is Plays.Kind r && options.Games.Contains(r)) return Offer.Game(r);
        var all = options.Games.Select(Offer.Game).ToList();
        if (options.Tea) all.Add(Offer.Tea);
        return all.Count == 0 ? null : rng.Pick(all);
    }

    // MARK: The built-in lines

    /// <summary>A character's invitation and its yes and no. <c>{reader}</c> is the one spoken to, <c>{game}</c> the offer in a word.</summary>
    public sealed record Voice(string Invite, string Yes, string No);

    /// <summary>For a character the user made, in <paramref name="l"/>.</summary>
    public static Voice AnyoneIn(Language l) =>
        Shared.In(l)?.DeedsAnyone is { } v && v.Invite.Length > 0 ? new Voice(v.Invite, v.Yes, v.No) : EnglishAnyone;

    /// <summary>Every built-in character's lines in <paramref name="l"/>.</summary>
    public static IReadOnlyDictionary<string, Voice> VoicesIn(Language l) =>
        Shared.In(l) is { } shared ? shared.DeedVoices.ToDictionary(kv => kv.Key, kv => new Voice(kv.Value.Invite, kv.Value.Yes, kv.Value.No)) : EnglishVoices;

    public static Voice VoiceOf(string name) =>
        VoicesIn(Languages.Current).TryGetValue(name, out var v) ? v : AnyoneIn(Languages.Current);

    /// <summary><paramref name="sender"/>'s invitation to <paramref name="reader"/>.</summary>
    public static string InviteLine(string sender, string reader, Offer offer) =>
        CursorMoods.Current.Adjust(Banter.Render(VoiceOf(sender).Invite, new Dictionary<string, string> { ["reader"] = reader, ["game"] = offer.Word }));

    /// <summary><paramref name="writer"/>'s answer to <paramref name="inviter"/>'s invitation.</summary>
    public static string AnswerLine(string writer, string inviter, Offer offer, bool yes)
    {
        var v = VoiceOf(writer);
        return CursorMoods.Current.Adjust(Banter.Render(yes ? v.Yes : v.No, new Dictionary<string, string> { ["reader"] = inviter, ["game"] = offer.Word }));
    }
}

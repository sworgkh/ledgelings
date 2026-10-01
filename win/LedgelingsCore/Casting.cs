using System.Globalization;
using System.Text.Json;

namespace Ledgelings.Core;

/// <summary>
/// Voices that fit personalities. A character's description and species are
/// read for words that say how it should sound (old, slow, tiny, cheerful,
/// grumpy, robot, ghost, he or she); every voice is tagged from what its name
/// or id says about it (Grandpa, <c>af_</c> for a female Kokoro voice,
/// <c>ManWithDeepVoice</c>); each character then gets the free voice that fits best.
///
/// Rules, not understanding: a description in words the rules do not know gets
/// a neutral profile. The brain model can cast instead (Settings › Voice).
/// </summary>
public static class Casting
{
    public enum Tag { Female, Male, Old, Young, Deep, Bright, Soft, Robot, Whisper }

    /// <summary>"female", "robot": the Mac's raw value, as the model is shown it.</summary>
    public static string Raw(this Tag tag) => tag.ToString().ToLowerInvariant();

    /// <summary>How a character should sound: how much each kind of voice suits it, and
    /// its pitch and speed as multipliers (1 is neutral).</summary>
    public sealed class Traits : IEquatable<Traits>
    {
        public Dictionary<Tag, double> Wants { get; set; } = new();
        public double Pitch { get; set; } = 1;
        public double Speed { get; set; } = 1;

        public double Want(Tag tag) => Wants.TryGetValue(tag, out var w) ? w : 0;

        public static Traits Neutral => new();

        public bool Equals(Traits? other) => other is not null && other.Pitch == Pitch && other.Speed == Speed
            && other.Wants.Count == Wants.Count && Wants.All(kv => other.Wants.TryGetValue(kv.Key, out var w) && w == kv.Value);
        public override bool Equals(object? obj) => Equals(obj as Traits);
        public override int GetHashCode() => HashCode.Combine(Pitch, Speed, Wants.Count);
    }

    public const double PitchMin = 0.7, PitchMax = 1.5;
    public const double SpeedMin = 0.75, SpeedMax = 1.3;

    /// <summary>One rule: any of these word starts (or phrases) in the text, and the
    /// character wants these voices, a bit higher or lower, faster or slower.</summary>
    private sealed record Rule(string[] Words, Dictionary<Tag, double> Wants, double Pitch = 1, double Speed = 1);

    private static Dictionary<Tag, double> W(params (Tag, double)[] wants) => wants.ToDictionary(w => w.Item1, w => w.Item2);

    private static readonly Rule[] Rules =
    {
        new(new[] { "old", "ancient", "elder", "wise", "grand", "sage", "philosoph", "in my day", "proverb" },
            W((Tag.Old, 2), (Tag.Deep, 0.5)), 0.88, 0.88),
        new(new[] { "slow", "sleep", "nap", "drows", "yawn", "lazy", "patien", "calm", "damp", "purr" },
            W((Tag.Soft, 1)), 0.95, 0.85),
        new(new[] { "fast", "quick", "speed", "hyper", "zipp", "rush" }, W((Tag.Young, 1)), Speed: 1.2),
        new(new[] { "tiny", "small", "little", "wee" }, W((Tag.Young, 1)), 1.12),
        new(new[] { "cheer", "gigg", "laugh", "bounc", "excit", "enthus", "happy", "sweet", "ador", "playful",
                    "silly", "simple", "pleased" },
            W((Tag.Bright, 2)), 1.08, 1.05),
        new(new[] { "grump", "gruff", "stubborn", "stable", "stern", "disapprov", "proud", "fat", "big", "huge" },
            W((Tag.Deep, 1.5)), 0.88),
        new(new[] { "boss", "organis", "organiz", "precise", "count" }, W(), Speed: 1.05),
        new(new[] { "loud", "dramat", "announc", "brag", "boast" }, W((Tag.Bright, 0.5)), Speed: 1.05),
        new(new[] { "anxi", "worr", "nerv", "scared", "afraid" }, W((Tag.Soft, 0.5)), 1.05, 1.12),
        new(new[] { "whisper", "wistful", "poet", "quiet", "soft", "dream", "earthy", "hush" },
            W((Tag.Soft, 1.5), (Tag.Whisper, 0.5))),
        new(new[] { "robot", "machine", "antenna", "rivet", "bolt", "status", "literal", "beep", "glitch", "virus",
                    "maintenance" },
            W((Tag.Robot, 3))),
        new(new[] { "ghost", "spirit", "phantom", "haunt", "hover" }, W((Tag.Whisper, 2.5), (Tag.Soft, 0.5))),
        new(new[] { "he", "him", "his", "sir", "man", "boy", "grandpa", "king", "mister", "gentleman" }, W((Tag.Male, 2))),
        new(new[] { "she", "her", "hers", "lady", "girl", "grandma", "queen", "madam", "woman" }, W((Tag.Female, 2))),
    };

    /// <summary>Words in <paramref name="text"/>, lowercased: letters and apostrophes only.</summary>
    public static List<string> Words(string text)
    {
        var words = new List<string>();
        var word = new System.Text.StringBuilder();
        foreach (var ch in text.ToLowerInvariant())
        {
            if (char.IsLetter(ch) || ch == '\'') { word.Append(ch); continue; }
            if (word.Length > 0) { words.Add(word.ToString()); word.Clear(); }
        }
        if (word.Length > 0) words.Add(word.ToString());
        return words;
    }

    /// <summary>What <paramref name="persona"/> and <paramref name="kind"/> (the species, "a boxy little robot…") say about the voice.</summary>
    public static Traits TraitsOf(string persona, string kind)
    {
        var tokens = Words(persona + " " + kind);
        var lower = " " + string.Join(" ", tokens) + " ";
        var t = new Traits();
        foreach (var rule in Rules)
        {
            var hit = rule.Words.Any(stem => stem.Contains(' ')
                ? lower.Contains(" " + stem + " ", StringComparison.Ordinal)
                // Short words (he, her, man) must match whole, or "the" would be male.
                : tokens.Any(word => stem.Length <= 3 ? word == stem : word.StartsWith(stem, StringComparison.Ordinal)));
            if (!hit) continue;
            foreach (var (tag, weight) in rule.Wants) t.Wants[tag] = t.Want(tag) + weight;
            t.Pitch *= rule.Pitch;
            t.Speed *= rule.Speed;
        }
        t.Pitch = Math.Min(Math.Max(t.Pitch, PitchMin), PitchMax);
        t.Speed = Math.Min(Math.Max(t.Speed, SpeedMin), SpeedMax);
        return t;
    }

    private static HashSet<Tag> S(params Tag[] tags) => tags.ToHashSet();

    /// <summary>Voices known by name: the Mac's character and novelty voices, Kokoro's
    /// and Orpheus's that say more than their sex.</summary>
    private static readonly Dictionary<string, HashSet<Tag>> Known = new()
    {
        // Mac
        ["grandma"] = S(Tag.Old, Tag.Female), ["grandpa"] = S(Tag.Old, Tag.Male, Tag.Deep), ["zarvox"] = S(Tag.Robot), ["trinoids"] = S(Tag.Robot),
        ["fred"] = S(Tag.Robot, Tag.Male), ["albert"] = S(Tag.Robot, Tag.Male, Tag.Old), ["whisper"] = S(Tag.Whisper, Tag.Soft), ["ralph"] = S(Tag.Deep, Tag.Male),
        ["rocko"] = S(Tag.Deep, Tag.Male), ["reed"] = S(Tag.Male), ["eddy"] = S(Tag.Male, Tag.Young), ["flo"] = S(Tag.Female, Tag.Bright),
        ["sandy"] = S(Tag.Female), ["shelley"] = S(Tag.Female), ["junior"] = S(Tag.Young, Tag.Male, Tag.Bright), ["kathy"] = S(Tag.Female),
        ["bubbles"] = S(Tag.Bright, Tag.Young), ["boing"] = S(Tag.Bright), ["bahh"] = S(Tag.Bright), ["wobble"] = S(Tag.Soft), ["jester"] = S(Tag.Bright),
        // Kokoro
        ["am_santa"] = S(Tag.Old, Tag.Deep), ["bm_george"] = S(Tag.Old), ["bm_lewis"] = S(Tag.Old, Tag.Deep), ["bm_fable"] = S(Tag.Old),
        ["am_onyx"] = S(Tag.Deep), ["am_fenrir"] = S(Tag.Deep), ["af_nicole"] = S(Tag.Whisper, Tag.Soft), ["af_sky"] = S(Tag.Bright, Tag.Young),
        ["af_bella"] = S(Tag.Bright), ["af_heart"] = S(Tag.Bright), ["am_puck"] = S(Tag.Bright, Tag.Young), ["am_echo"] = S(Tag.Soft),
        ["af_river"] = S(Tag.Soft), ["bf_lily"] = S(Tag.Young),
        // Orpheus
        ["tara"] = S(Tag.Female), ["leah"] = S(Tag.Female, Tag.Bright), ["jess"] = S(Tag.Female, Tag.Bright), ["mia"] = S(Tag.Female, Tag.Young),
        ["zoe"] = S(Tag.Female, Tag.Young), ["leo"] = S(Tag.Male), ["dan"] = S(Tag.Male, Tag.Deep), ["zac"] = S(Tag.Male, Tag.Young),
    };

    /// <summary>What a voice's id (and display name, if it has one) says about it.</summary>
    public static HashSet<Tag> TagsOfVoice(string id, string? name = null)
    {
        var tags = new HashSet<Tag>();
        var keys = new List<string> { id.ToLowerInvariant() };
        if (name is not null) keys.Add(name.ToLowerInvariant());
        foreach (var key in keys) if (Known.TryGetValue(key, out var known)) tags.UnionWith(known);
        var text = string.Join(" ", keys);
        // Kokoro: af_ am_ bf_ bm_ … the second letter is the sex.
        var first = keys[0];
        if (first.Length > 3 && first[2] == '_')
        {
            if (first[1] == 'f') tags.Add(Tag.Female); else if (first[1] == 'm') tags.Add(Tag.Male);
        }
        // Names that describe themselves: MiniMax's English_ManWithDeepVoice, Voxtral's gb_jane_sad.
        bool Has(params string[] words) => words.Any(w => text.Contains(w, StringComparison.Ordinal));
        if (Has("girl", "lady", "woman", "queen", "female", "jane", "marie")) tags.Add(Tag.Female);
        else if (Has("man", "boy", "gentleman", "bloke", "guy", "male", "paul", "oliver", "king")) tags.Add(Tag.Male);
        if (Has("deep", "angry", "frustrated", "bossy", "imposing")) tags.Add(Tag.Deep);
        if (Has("wise", "mature", "scholar", "mentor", "elder", "narrator", "storyteller")) tags.Add(Tag.Old);
        if (Has("whisper")) tags.Add(Tag.Whisper);
        if (Has("soft", "calm", "serene", "gentle", "sad", "patient")) tags.Add(Tag.Soft);
        if (Has("playful", "anime", "whimsical", "lovely", "upbeat", "radiant", "excited", "cheerful", "happy",
                "jovial", "comedian")) tags.Add(Tag.Bright);
        if (Has("boy", "girl", "teen", "young", "kid", "child")) tags.Add(Tag.Young);
        if (Has("robot")) tags.Add(Tag.Robot);
        return tags;
    }

    /// <summary>How well a voice with <paramref name="tags"/> fits <paramref name="traits"/>: wanted kinds add, the wrong
    /// sex takes away, and voices that are one strong thing (a robot, a whisper,
    /// an old voice) count against a character that did not ask for it.</summary>
    public static double Score(IReadOnlySet<Tag> tags, Traits traits)
    {
        var s = 0.0;
        foreach (var (tag, weight) in traits.Wants) if (tags.Contains(tag)) s += weight;
        var wantsFemale = traits.Want(Tag.Female);
        var wantsMale = traits.Want(Tag.Male);
        if (wantsFemale > 0 && tags.Contains(Tag.Male)) s -= wantsFemale;
        if (wantsMale > 0 && tags.Contains(Tag.Female)) s -= wantsMale;
        if (tags.Contains(Tag.Robot) && traits.Want(Tag.Robot) == 0) s -= 3;
        // Only a character that really calls for it (a ghost) gets a whisper; a
        // poetic streak alone does not.
        if (tags.Contains(Tag.Whisper) && traits.Want(Tag.Whisper) < 2) s -= 3;
        if (tags.Contains(Tag.Old) && traits.Want(Tag.Old) == 0) s -= 0.7;
        return s;
    }

    // MARK: Casting by the brain model

    /// <summary>What the model answers: a voice from the list, and pitch and speed multipliers.</summary>
    public sealed record Pick(string Voice, double? Pitch = null, double? Speed = null, string? Why = null);

    public const string ModelSystem = "You cast voices for small cartoon creatures that live on the edges of a computer screen. You answer with one JSON object and nothing else.";

    /// <summary>The request: who the character is, and the voices to choose from, each
    /// with what is known about it.</summary>
    public static string ModelPrompt(string name, string persona, string kind, IEnumerable<(string Id, string Hints)> voices, bool cartoon)
    {
        var list = string.Join("\n", voices.Select(v => v.Hints.Length == 0 ? $"- {v.Id}" : $"- {v.Id}: {v.Hints}"));
        return $"Character: {name}, {(kind.Length == 0 ? "a small creature" : kind)}.\n"
            + $"Personality: {(persona.Length == 0 ? "not described" : persona)}\n\n"
            + "Pick the voice that fits this personality best, and how high and how fast it should speak.\n"
            + "pitch and speed are multipliers: 1 is the voice as it is, 0.7 much lower or slower, 1.5 much higher or faster."
            + (cartoon ? " This is a cartoon: voices usually sit a little high, 1.1 to 1.4." : "") + "\n\n"
            + "Voices:\n"
            + list + "\n\n"
            + "Answer with JSON only: {\"voice\": \"<an id from the list>\", \"pitch\": <0.7-1.6>, \"speed\": <0.75-1.3>, \"why\": \"<a few words>\"}";
    }

    /// <summary>The model's answer, from the first <c>{</c> to the last <c>}</c>, pitch and speed
    /// clamped; null if there is no such object or it names no voice.</summary>
    public static Pick? ParsePick(string text)
    {
        // A thinking model's reasoning comes first and may hold braces of its own.
        var think = text.IndexOf("</think>", StringComparison.Ordinal);
        if (think >= 0) text = text[(think + "</think>".Length)..];
        var open = text.IndexOf('{');
        var close = text.LastIndexOf('}');
        if (open < 0 || close < 0 || open >= close) return null;
        try
        {
            using var doc = JsonDocument.Parse(text[open..(close + 1)]);
            var o = doc.RootElement;
            if (o.ValueKind != JsonValueKind.Object) return null;
            if (!o.TryGetProperty("voice", out var v) || v.ValueKind != JsonValueKind.String) return null;
            var voice = (v.GetString() ?? "").Trim();
            if (voice.Length == 0) return null;
            double? Number(string key)
            {
                if (!o.TryGetProperty(key, out var n)) return null;
                if (n.ValueKind == JsonValueKind.Number) return n.GetDouble();
                if (n.ValueKind == JsonValueKind.String && double.TryParse(n.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var d)) return d;
                return null;
            }
            string? why = o.TryGetProperty("why", out var w) && w.ValueKind == JsonValueKind.String ? w.GetString() : null;
            return new Pick(voice,
                Number("pitch") is double p ? Math.Min(Math.Max(p, 0.5), 2) : null,
                Number("speed") is double s ? Math.Min(Math.Max(s, 0.5), 2) : null,
                why);
        }
        catch (JsonException) { return null; }
    }

    /// <summary>A voice from <paramref name="pool"/> for every name, the best fit for its <paramref name="traits"/> that is
    /// still free; hand-picked voices (<paramref name="fixedVoices"/>) are kept and not handed out.
    /// The characters with the strongest wishes choose first; ties go round the
    /// pool from a spot hashed from the name, so equal fits still differ.</summary>
    public static Dictionary<string, string> Assign(IEnumerable<string> names, IReadOnlyDictionary<string, Traits> traits, IReadOnlyList<string> pool,
                                                    IReadOnlyDictionary<string, HashSet<Tag>> tags, IReadOnlyDictionary<string, string>? fixedVoices = null)
    {
        if (pool.Count == 0) return new Dictionary<string, string>();
        var everyone = names.ToHashSet();
        var result = (fixedVoices ?? new Dictionary<string, string>()).Where(kv => everyone.Contains(kv.Key)).ToDictionary(kv => kv.Key, kv => kv.Value);
        var taken = result.Values.ToHashSet();
        double Strength(string n) => traits.TryGetValue(n, out var t) && t.Wants.Count > 0 ? t.Wants.Values.Max() : 0;
        IReadOnlySet<Tag> TagsOf(string v) => tags.TryGetValue(v, out var set) ? set : new HashSet<Tag>();
        var order = everyone.Where(n => !result.ContainsKey(n))
            .OrderByDescending(Strength).ThenBy(n => n, StringComparer.Ordinal).ToList();
        foreach (var name in order)
        {
            var t = traits.TryGetValue(name, out var own) ? own : Traits.Neutral;
            var start = (int)(Voices.StableHash(name) % (ulong)pool.Count);
            var rotated = Enumerable.Range(0, pool.Count).Select(k => pool[(start + k) % pool.Count]).ToList();
            var free = rotated.Where(v => !taken.Contains(v)).ToList();
            var choices = free.Count == 0 ? rotated : free;
            // The first in rotated order of the best fits.
            var top = choices.Max(v => Score(TagsOf(v), t));
            var pick = choices.First(v => Score(TagsOf(v), t) == top);
            result[name] = pick;
            taken.Add(pick);
        }
        return result;
    }
}

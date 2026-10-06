using System.Globalization;
using System.Reflection;
using System.Text;
using System.Text.Json;

namespace Ledgelings.Core;

/// <summary>
/// The language the app speaks: its menus and settings, the creatures' built-in
/// lines, and the prompts that ask a model for new ones (SPEC §1.2).
///
/// Short text is written in English at the call site and passed through
/// <see cref="L10n.Tr"/>, which looks it up in the language's table and falls back
/// to the English. Long text written per language (the built-in script, letters,
/// tea stories, prompts) comes from <see cref="Shared"/>. Both are the Mac app's own
/// words: <c>Sources/LedgelingsCore/l10n/ru.json</c>, exported there by a Mac test
/// and linked into this assembly, so the two apps say the same thing.
/// </summary>
public enum Language { English, Russian }

public static class Languages
{
    public static IReadOnlyList<Language> All { get; } = new[] { Language.English, Language.Russian };

    /// <summary>The ISO 639-1 code: <c>en</c>, <c>ru</c>; what the settings file stores.</summary>
    public static string Code(this Language l) => l switch { Language.Russian => "ru", _ => "en" };

    /// <summary>The language's name in itself, as the menu shows it.</summary>
    public static string Title(this Language l) => l switch { Language.Russian => "Русский", _ => "English" };

    public static Language? FromCode(string? code) => code?.ToLowerInvariant() switch
    {
        "en" => Language.English,
        "ru" => Language.Russian,
        _ => null,
    };

    /// <summary>The first of <paramref name="cultures"/> the app speaks; English otherwise.</summary>
    public static Language Preferred(IEnumerable<string> cultures)
    {
        foreach (var c in cultures)
        {
            var code = c.Split('-', '_')[0];
            if (FromCode(code) is { } l) return l;
        }
        return Language.English;
    }

    /// <summary>The system's UI language, when the app has it.</summary>
    public static Language System => Preferred(new[] { CultureInfo.CurrentUICulture.Name });

    /// <summary>How many forms a counted noun has. English: one, other. Russian: one (1, 21), few (2–4), many (5–20, 0).</summary>
    public static int PluralForms(this Language l) => l == Language.Russian ? 3 : 2;

    public static int PluralIndex(this Language l, int n)
    {
        n = Math.Abs(n);
        if (l != Language.Russian) return n == 1 ? 0 : 1;
        if (n % 10 == 1 && n % 100 != 11) return 0;
        if (n % 10 is >= 2 and <= 4 && n % 100 is not (>= 12 and <= 14)) return 1;
        return 2;
    }

    public static CultureInfo Culture(this Language l) => CultureInfo.GetCultureInfo(l == Language.Russian ? "ru-RU" : "en-GB");

    private static volatile int chosen;
    private static readonly AsyncLocal<Language?> overriding = new();

    /// <summary>What everything speaks right now.</summary>
    public static Language Current => overriding.Value ?? (Language)chosen;

    /// <summary>Set by the app from its settings, at launch and on every change.</summary>
    public static void Choose(Language l) => chosen = (int)l;

    /// <summary>A language for the code inside <paramref name="body"/>, whatever the app chose: how tests ask for Russian.</summary>
    public static T With<T>(Language l, Func<T> body)
    {
        var before = overriding.Value;
        overriding.Value = l;
        try { return body(); }
        finally { overriding.Value = before; }
    }

    public static void With(Language l, Action body) => With(l, () => { body(); return 0; });
}

/// <summary>The lookups, named short because every label goes through them.</summary>
public static class L10n
{
    /// <summary><paramref name="english"/> in the current language, formatted with the Mac's marks:
    /// <c>%@</c> any value, <c>%d</c> a number, <c>%.1f</c> a decimal, <c>%1$@</c> the first argument.</summary>
    public static string Tr(string english, params object[] args)
    {
        var text = Lookup(english, Languages.Current);
        return args.Length == 0 ? text : Format(text, args);
    }

    /// <summary><paramref name="n"/> and its noun: <c>TrCount(3, "minute", "minutes")</c> is "3 minutes", or "3 минуты".</summary>
    public static string TrCount(int n, string one, string other)
    {
        var language = Languages.Current;
        var forms = Lookup(one + "|" + other, language).Split('|');
        var index = forms.Length == language.PluralForms() ? language.PluralIndex(n) : Language.English.PluralIndex(n);
        var form = index < forms.Length ? forms[index] : (n == 1 ? one : other);
        return form.Contains("%d") ? Format(form, new object[] { n }) : $"{n} {form}";
    }

    public static string Lookup(string english, Language language)
    {
        if (language == Language.English) return english;
        var shared = Shared.In(language);
        if (shared?.Strings.TryGetValue(english, out var found) == true && found.Length > 0) return found;
        if (WindowsStrings.In(language).TryGetValue(english, out found) && found.Length > 0) return found;
        return english;
    }

    /// <summary>Fills a format written with the Mac's marks.</summary>
    public static string Format(string template, object[] args)
    {
        var sb = new StringBuilder();
        var next = 0;
        for (var i = 0; i < template.Length; i++)
        {
            var c = template[i];
            if (c != '%' || i + 1 >= template.Length) { sb.Append(c); continue; }
            if (template[i + 1] == '%') { sb.Append('%'); i++; continue; }
            var j = i + 1;
            int? position = null;
            var digits = j;
            while (digits < template.Length && char.IsDigit(template[digits])) digits++;
            if (digits > j && digits < template.Length && template[digits] == '$')
            {
                position = int.Parse(template[j..digits], CultureInfo.InvariantCulture) - 1;
                j = digits + 1;
            }
            int? decimals = null;
            if (j + 1 < template.Length && template[j] == '.' && char.IsDigit(template[j + 1]))
            {
                decimals = template[j + 1] - '0';
                j += 2;
            }
            if (j < template.Length && template[j] == 'l') j++;
            if (j >= template.Length || "@dif".IndexOf(template[j]) < 0) { sb.Append(c); continue; }
            var index = position ?? next++;
            var value = index < args.Length ? args[index] : "";
            sb.Append(template[j] switch
            {
                'f' => Convert.ToDouble(value, CultureInfo.InvariantCulture).ToString("F" + (decimals ?? 6), CultureInfo.InvariantCulture),
                'd' or 'i' => Convert.ToInt64(value, CultureInfo.InvariantCulture).ToString(CultureInfo.InvariantCulture),
                _ => Convert.ToString(value, CultureInfo.InvariantCulture) ?? "",
            });
            i = j;
        }
        return sb.ToString();
    }
}

/// <summary>Everything written per language, as the Mac app exported it.</summary>
public sealed class Shared
{
    public sealed record LetterVoice(string[] Topics, string[] Notes, string[] Musings, string[] Replies);

    public Dictionary<string, string> Strings { get; init; } = new();
    public string Script { get; init; } = "";
    public LetterVoice LettersAnyone { get; init; } = new(Array.Empty<string>(), Array.Empty<string>(), Array.Empty<string>(), Array.Empty<string>());
    public Dictionary<string, LetterVoice> LetterVoices { get; init; } = new();
    public Dictionary<string, string[]> TeaStories { get; init; } = new();
    public Dictionary<string, string[]> TeaReplies { get; init; } = new();
    public string[] TeaAnyoneStories { get; init; } = Array.Empty<string>();
    public string[] TeaAnyoneReplies { get; init; } = Array.Empty<string>();
    public string[] ComplaintsAnyone { get; init; } = Array.Empty<string>();
    public Dictionary<string, string[]> ComplaintLines { get; init; } = new();
    public string[] RemindersAnyone { get; init; } = Array.Empty<string>();
    public Dictionary<string, string[]> ReminderNotes { get; init; } = new();
    public Dictionary<string, string> Holidays { get; init; } = new();
    public Dictionary<string, string> Flowers { get; init; } = new();
    /// <summary>The cursor mood's text (SPEC §6.1.2): shipped lines and what the good and neutral moods say
    /// instead, the lines that fit every mood, each mood's persona note and script-prompt phrase (keyed
    /// <c>good</c>/<c>neutral</c>/<c>bad</c>), and the good and neutral complaints and their prompts.</summary>
    public Dictionary<string, Rewrite> CursorRewrites { get; init; } = new();
    public HashSet<string> CursorFitsEveryMood { get; init; } = new();
    public Dictionary<string, string> CursorNotes { get; init; } = new();
    public Dictionary<string, string> CursorAgentPhrases { get; init; } = new();
    public Dictionary<string, string[]> ComplaintsAnyoneByMood { get; init; } = new();
    public Dictionary<string, Dictionary<string, string[]>> ComplaintLinesByMood { get; init; } = new();
    public Dictionary<string, string> ComplaintPromptsByMood { get; init; } = new();
    /// <summary>The count lines (SPEC §4.7.2) per cursor mood (<c>good</c>/<c>neutral</c>/<c>bad</c>): by character, and for anyone.</summary>
    public Dictionary<string, Dictionary<string, string[]>> HuntLinesByMood { get; init; } = new();
    public Dictionary<string, string[]> HuntAnyoneByMood { get; init; } = new();
    /// <summary>Keys: system, line, reply, plot, plotSystem, planeNote, planeReply, planeMusing, teaSystem, teaStory, teaReply, complaint, reminder.</summary>
    public Dictionary<string, string> Prompts { get; init; } = new();

    private static readonly Dictionary<Language, Shared?> loaded = new();

    /// <summary>The language's text; null for English, which is written in the code.</summary>
    public static Shared? In(Language language)
    {
        if (language == Language.English) return null;
        lock (loaded)
        {
            if (!loaded.TryGetValue(language, out var s)) loaded[language] = s = Load(language);
            return s;
        }
    }

    /// <summary>The current language's text, or null in English.</summary>
    public static Shared? Current => In(Languages.Current);

    /// <summary><paramref name="l"/>'s version of prompt <paramref name="key"/>, or <paramref name="english"/>.</summary>
    public static string PromptIn(Language l, string key, string english) =>
        In(l)?.Prompts.TryGetValue(key, out var p) == true && p.Length > 0 ? p : english;

    /// <summary>The current language's version of prompt <paramref name="key"/>, or <paramref name="english"/>.</summary>
    public static string Prompt(string key, string english) => PromptIn(Languages.Current, key, english);

    private static Shared? Load(Language language)
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("l10n." + language.Code() + ".json");
        return stream is null ? null : Parse(JsonDocument.Parse(stream).RootElement);
    }

    public static Shared Parse(JsonElement root)
    {
        static string[] List(JsonElement e) => e.ValueKind == JsonValueKind.Array ? e.EnumerateArray().Select(x => x.GetString() ?? "").ToArray() : Array.Empty<string>();
        static Dictionary<string, string> Map(JsonElement e) => e.ValueKind == JsonValueKind.Object
            ? e.EnumerateObject().ToDictionary(p => p.Name, p => p.Value.GetString() ?? "") : new();
        static Dictionary<string, string[]> Lists(JsonElement e) => e.ValueKind == JsonValueKind.Object
            ? e.EnumerateObject().ToDictionary(p => p.Name, p => List(p.Value)) : new();
        static JsonElement Get(JsonElement e, string name) => e.ValueKind == JsonValueKind.Object && e.TryGetProperty(name, out var v) ? v : default;
        static LetterVoice Letter(JsonElement e) => new(List(Get(e, "topics")), List(Get(e, "notes")), List(Get(e, "musings")), List(Get(e, "replies")));

        var letters = Get(root, "letters");
        var tea = Get(root, "tea");
        var complaints = Get(root, "complaints");
        var reminders = Get(root, "reminders");
        var voices = Get(letters, "voices");
        var mood = Get(root, "cursorMood");
        var rewrites = Get(mood, "rewrites");
        var moodComplaints = Get(mood, "complaints");
        string[] moods = { "good", "neutral" };
        var hunts = Get(root, "hunts");
        string[] allMoods = { "good", "neutral", "bad" };
        return new Shared
        {
            Strings = Map(Get(root, "strings")),
            Script = Get(root, "script").ValueKind == JsonValueKind.String ? Get(root, "script").GetString() ?? "" : "",
            LettersAnyone = Letter(Get(letters, "anyone")),
            LetterVoices = voices.ValueKind == JsonValueKind.Object ? voices.EnumerateObject().ToDictionary(p => p.Name, p => Letter(p.Value)) : new(),
            TeaStories = Lists(Get(tea, "stories")),
            TeaReplies = Lists(Get(tea, "replies")),
            TeaAnyoneStories = List(Get(tea, "anyoneStories")),
            TeaAnyoneReplies = List(Get(tea, "anyoneReplies")),
            ComplaintsAnyone = List(Get(complaints, "anyone")),
            ComplaintLines = Lists(Get(complaints, "lines")),
            RemindersAnyone = List(Get(reminders, "anyone")),
            ReminderNotes = Lists(Get(reminders, "notes")),
            Holidays = Map(Get(root, "holidays")),
            Flowers = Map(Get(root, "flowers")),
            Prompts = Map(Get(root, "prompts")),
            CursorRewrites = rewrites.ValueKind == JsonValueKind.Object
                ? rewrites.EnumerateObject().ToDictionary(p => p.Name,
                    p => new Rewrite(Get(p.Value, "good").GetString() ?? "", Get(p.Value, "neutral").GetString() ?? ""))
                : new(),
            CursorFitsEveryMood = List(Get(mood, "fitsEveryMood")).ToHashSet(),
            CursorNotes = Map(Get(mood, "notes")),
            CursorAgentPhrases = Map(Get(mood, "agentPhrases")),
            ComplaintsAnyoneByMood = moods.ToDictionary(m => m, m => List(Get(Get(moodComplaints, m), "anyone"))),
            ComplaintLinesByMood = moods.ToDictionary(m => m, m => Lists(Get(Get(moodComplaints, m), "lines"))),
            ComplaintPromptsByMood = Map(Get(mood, "complaintPrompts")),
            HuntLinesByMood = allMoods.ToDictionary(m => m, m => Lists(Get(Get(hunts, m), "lines"))),
            HuntAnyoneByMood = allMoods.ToDictionary(m => m, m => List(Get(Get(hunts, m), "anyone"))),
        };
    }
}

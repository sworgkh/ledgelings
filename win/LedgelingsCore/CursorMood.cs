namespace Ledgelings.Core;

/// <summary>
/// How the creatures take the mouse cursor that chases them about the edges (SPEC §6.1.2).
///
/// The cursor itself does the same in every mood: a creature still jumps out of its
/// way and can still be picked up. What changes is what they make of it:
/// <see cref="CursorMood.Good"/>, a playmate, and being chased is a game of tag;
/// <see cref="CursorMood.Neutral"/>, it just happens, like weather;
/// <see cref="CursorMood.Bad"/>, a menace, as the creatures were first written.
///
/// A model hears the mood through <c>{speakerPersona}</c> (<see cref="Banter.Persona"/>);
/// a shipped line or conversation about the cursor is swapped for the mood's version
/// (<see cref="CursorMoods.Adjust(CursorMood, string)"/>); complaints have their own lines
/// and prompt per mood (<see cref="Complaints"/>).
/// </summary>
public enum CursorMood { Good, Neutral, Bad }

/// <summary>A shipped line about the cursor and the line said instead in each other mood.</summary>
public sealed record Rewrite(string Good, string Neutral);

public static partial class CursorMoods
{
    public static IReadOnlyList<CursorMood> All { get; } = new[] { CursorMood.Good, CursorMood.Neutral, CursorMood.Bad };

    /// <summary>What the settings file stores: <c>good</c>, <c>neutral</c>, <c>bad</c>, as the Mac's.</summary>
    public static string Code(this CursorMood m) => m switch { CursorMood.Good => "good", CursorMood.Neutral => "neutral", _ => "bad" };

    public static CursorMood? FromCode(string? code) => code switch
    {
        "good" => CursorMood.Good,
        "neutral" => CursorMood.Neutral,
        "bad" => CursorMood.Bad,
        _ => null,
    };

    /// <summary>What the creatures think the cursor is, as the settings and the tray menu show it.</summary>
    public static string Title(this CursorMood m) => m switch
    {
        CursorMood.Good => L10n.Tr("A playmate"),
        CursorMood.Neutral => L10n.Tr("Just there"),
        _ => L10n.Tr("A menace"),
    };

    /// <summary>The tray's status while a model writes what a chased creature says.</summary>
    public static string SpeakingUp(this CursorMood m) => m switch
    {
        CursorMood.Good => L10n.Tr("%@ is teasing you via %@…"),
        CursorMood.Neutral => L10n.Tr("%@ is talking to you via %@…"),
        _ => L10n.Tr("%@ is complaining via %@…"),
    };

    /// <summary>The tray's status once it has said it.</summary>
    public static string SpokeUp(this CursorMood m) => m switch
    {
        CursorMood.Good => L10n.Tr("%@ teased you: %@"),
        CursorMood.Neutral => L10n.Tr("%@ said to you: %@"),
        _ => L10n.Tr("%@ complained: %@"),
    };

    private static volatile int chosen = (int)CursorMood.Bad;
    private static readonly AsyncLocal<CursorMood?> overriding = new();

    /// <summary>How the creatures take the cursor right now.</summary>
    public static CursorMood Current => overriding.Value ?? (CursorMood)chosen;

    /// <summary>Set by the app from its settings, at launch and on every change.</summary>
    public static void Choose(CursorMood m) => chosen = (int)m;

    /// <summary>A mood for the code inside <paramref name="body"/>, whatever the app chose: how tests ask for one.</summary>
    public static T With<T>(CursorMood m, Func<T> body)
    {
        var before = overriding.Value;
        overriding.Value = m;
        try { return body(); }
        finally { overriding.Value = before; }
    }

    public static void With(CursorMood m, Action body) => With(m, () => { body(); return 0; });

    // For a model

    /// <summary>The sentence every persona gains in this mood, in the current language. Bad adds none.</summary>
    public static string Note(this CursorMood m) => NoteIn(m, Languages.Current);

    public static string NoteIn(CursorMood m, Language l)
    {
        if (m == CursorMood.Bad) return "";
        var english = m == CursorMood.Good ? EnglishGoodNote : EnglishNeutralNote;
        return Shared.In(l)?.CursorNotes.TryGetValue(m.Code(), out var t) == true && t.Length > 0 ? t : english;
    }

    public const string EnglishGoodNote = "To them the mouse cursor is a playmate: being chased by it is a game of tag, and they love to win it.";
    public const string EnglishNeutralNote = "The mouse cursor means nothing to them: it comes and goes like the weather, and they hop out of its way without a thought.";

    /// <summary>What the creatures do about the cursor, as the prompt for writing more built-in lines says it.</summary>
    public static string AgentPhrase(this CursorMood m)
    {
        var english = m switch
        {
            CursorMood.Good => "play tag with the mouse cursor",
            CursorMood.Neutral => "hop out of the mouse cursor's way",
            _ => "flee the mouse cursor",
        };
        return Shared.Current?.CursorAgentPhrases.TryGetValue(m.Code(), out var t) == true && t.Length > 0 ? t : english;
    }

    /// <summary><paramref name="persona"/> as this mood has it, still in English: a shipped persona that talks
    /// about the cursor becomes the mood's version; any other stays itself.</summary>
    public static string Persona(this CursorMood m, string persona) =>
        m == CursorMood.Bad || !Personas.TryGetValue(persona, out var r) ? persona : m == CursorMood.Good ? r.Good : r.Neutral;

    // Built-in lines

    /// <summary>The rewrites in <paramref name="l"/>: the English here, another language's from <see cref="Shared"/>.</summary>
    public static IReadOnlyDictionary<string, Rewrite> Rewrites(Language l) =>
        l == Language.English ? EnglishRewrites : Shared.In(l)?.CursorRewrites ?? (IReadOnlyDictionary<string, Rewrite>)new Dictionary<string, Rewrite>();

    /// <summary>Shipped lines about the cursor that read right in every mood as they are.</summary>
    public static IReadOnlySet<string> FitsEveryMood(Language l) =>
        l == Language.English ? EnglishFitsEveryMood : Shared.In(l)?.CursorFitsEveryMood ?? (IReadOnlySet<string>)new HashSet<string>();

    /// <summary><paramref name="text"/> as this mood says it: a shipped line (or a whole conversation, its lines
    /// joined by newlines) about the cursor becomes the mood's version, in the current language. Anything else,
    /// and everything in the bad mood, is left as it is.</summary>
    public static string Adjust(this CursorMood m, string text) =>
        m == CursorMood.Bad || !Rewrites(Languages.Current).TryGetValue(text, out var r) ? text : m == CursorMood.Good ? r.Good : r.Neutral;

    /// <summary>A conversation as this mood has it: rewritten whole, so its lines still answer each other.</summary>
    public static IReadOnlyList<string> Adjust(this CursorMood m, IReadOnlyList<string> lines)
    {
        var joined = string.Join("\n", lines);
        var said = m.Adjust(joined);
        return said == joined ? lines : said.Split('\n');
    }

    public static IReadOnlyList<string> AdjustEach(this CursorMood m, IReadOnlyList<string> lines) =>
        m == CursorMood.Bad ? lines : lines.Select(l => m.Adjust(l)).ToArray();
}

namespace Ledgelings.Core;

/// <summary>
/// Long text in the current language: the Mac's <c>Translated</c>. The English is
/// written in the code (<c>EnglishX</c>); another language's comes from <see cref="Shared"/>,
/// and whatever it lacks (a character with no lines of its own there) stays English.
/// </summary>
internal static class Translated
{
    /// <summary><paramref name="translated"/> when it has anything in it, else <paramref name="english"/>.</summary>
    public static IReadOnlyList<string> List(string[]? translated, IReadOnlyList<string> english) =>
        translated is { Length: > 0 } ? translated : english;

    /// <summary>Every character of <paramref name="english"/>, each with its lines from
    /// <paramref name="translated"/> when it has some there.</summary>
    public static IReadOnlyDictionary<string, TList> Lists<TList>(IReadOnlyDictionary<string, string[]>? translated,
                                                                IReadOnlyDictionary<string, TList> english, Func<string[], TList> wrap)
        where TList : IReadOnlyCollection<string>
    {
        if (translated is null || translated.Count == 0) return english;
        return english.ToDictionary(kv => kv.Key, kv => translated.TryGetValue(kv.Key, out var t) && t.Length > 0 ? wrap(t) : kv.Value);
    }
}

namespace Ledgelings.Core;

/// <summary>
/// Text only the Windows app shows (its own wording, tray and dialog words), per
/// language, keyed by the English. Everything the Mac app also says comes from the
/// shared export instead; a key in both is a mistake the tests catch.
/// One part per area, each in its own file.
/// </summary>
public static partial class WindowsStrings
{
    // Built on first use: the parts are fields of other files, whose initialisation order C# does not promise.
    public static IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>> RussianParts => parts.Value;

    private static readonly Lazy<Dictionary<string, IReadOnlyDictionary<string, string>>> parts = new(() =>
        new Dictionary<string, IReadOnlyDictionary<string, string>>
        {
            ["app"] = RuApp,
            ["settings"] = RuSettings,
            ["runtime"] = RuRuntime,
            ["core"] = RuCore,
        });

    private static readonly Lazy<Dictionary<string, string>> russian = new(() =>
        RussianParts.Values.SelectMany(p => p).GroupBy(p => p.Key).ToDictionary(g => g.Key, g => g.First().Value));

    private static readonly Dictionary<string, string> none = new();

    public static IReadOnlyDictionary<string, string> In(Language language) => language == Language.Russian ? russian.Value : none;
}

using System.Runtime.CompilerServices;
using System.Text.RegularExpressions;

namespace Ledgelings.Core.Tests;

/// <summary>SPEC §1.2: the lookup, the plurals, the Mac's shared Russian, and a sweep
/// of the Windows sources that every <c>Tr("…")</c> has its Russian.</summary>
public class LanguageTests
{
    [Fact]
    public void EnglishIsTheTextItself()
    {
        Languages.With(Language.English, () =>
        {
            Assert.Equal("Settings…", L10n.Tr("Settings…"));
            Assert.Equal("never heard 3", L10n.Tr("never heard %d", 3));
        });
    }

    [Fact]
    public void RussianComesFromTheMacsTable()
    {
        Languages.With(Language.Russian, () =>
        {
            Assert.Equal("Настройки…", L10n.Tr("Settings…"));
            Assert.Equal("never heard of this", L10n.Tr("never heard of this"));
            Assert.Equal("Потрачено: $1 сегодня, $2 за месяц", L10n.Tr("Spent: %@ today, %@ this month", "$1", "$2"));
        });
    }

    [Fact]
    public void RussianPluralsHaveThreeForms()
    {
        Assert.All(new[] { 1, 21, 101 }, n => Assert.Equal(0, Language.Russian.PluralIndex(n)));
        Assert.All(new[] { 2, 3, 4, 22, 34 }, n => Assert.Equal(1, Language.Russian.PluralIndex(n)));
        Assert.All(new[] { 0, 5, 11, 12, 14, 20, 25, 111 }, n => Assert.Equal(2, Language.Russian.PluralIndex(n)));
        Languages.With(Language.Russian, () =>
        {
            Assert.Equal("1 минута", L10n.TrCount(1, "minute", "minutes"));
            Assert.Equal("3 минуты", L10n.TrCount(3, "minute", "minutes"));
            Assert.Equal("11 минут", L10n.TrCount(11, "minute", "minutes"));
        });
        Languages.With(Language.English, () => Assert.Equal("2 minutes", L10n.TrCount(2, "minute", "minutes")));
    }

    [Fact]
    public void FormatsReadTheMacsMarks()
    {
        Assert.Equal("b then a", L10n.Format("%2$@ then %1$@", new object[] { "a", "b" }));
        Assert.Equal("3 at 1.5 and 100%", L10n.Format("%d at %.1f and 100%%", new object[] { 3, 1.5 }));
        Assert.Equal("x %z", L10n.Format("%@ %z", new object[] { "x" }));
    }

    [Fact]
    public void ThePreferredLanguageFollowsTheSystem()
    {
        Assert.Equal(Language.Russian, Languages.Preferred(new[] { "ru-RU" }));
        Assert.Equal(Language.Russian, Languages.Preferred(new[] { "he-IL", "ru" }));
        Assert.Equal(Language.English, Languages.Preferred(new[] { "fr-FR" }));
        Assert.Equal(Language.English, Languages.Preferred(Array.Empty<string>()));
    }

    [Fact]
    public void TheSharedRussianIsLinkedIn()
    {
        var ru = Shared.In(Language.Russian)!;
        Assert.NotNull(ru);
        Assert.Null(Shared.In(Language.English));
        Assert.True(ru.Strings.Count > 500);
        Assert.Contains("[flower]", ru.Script);
        Assert.Equal(13, ru.Prompts.Count);
        Assert.Contains("Blocky", ru.LetterVoices.Keys);
        Assert.NotEmpty(ru.TeaStories["Blocky"]);
        Assert.NotEmpty(ru.Holidays);
        Assert.NotEmpty(ru.Flowers);
    }

    // The sweep

    private static string Root([CallerFilePath] string here = "") => Path.GetFullPath(Path.Combine(Path.GetDirectoryName(here)!, ".."));

    private static IEnumerable<(string File, string Text)> Sources() =>
        new[] { "Ledgelings", "LedgelingsCore" }
            .SelectMany(d => Directory.EnumerateFiles(Path.Combine(Root(), d), "*.*", SearchOption.AllDirectories))
            .Where(f => (f.EndsWith(".cs") || f.EndsWith(".xaml")) && !f.Contains($"{Path.DirectorySeparatorChar}Russian{Path.DirectorySeparatorChar}")
                        && !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}") && !f.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}"))
            .Select(f => (Path.GetFileName(f), File.ReadAllText(f)));

    private const string Literal = "\"((?:[^\"\\\\\\n]|\\\\.)*)\"";

    private static string Unescape(string s) => Regex.Unescape(s);

    /// <summary>Every key the sources look up: <c>Tr("…")</c>, <c>TrCount(n, "…", "…")</c>, and
    /// XAML text marked for translation (<c>l:Tr.Text</c> and the like take their English as written).</summary>
    public static List<(string File, string Key)> Keys()
    {
        var single = new Regex(@"\bTr\(\s*" + Literal);
        var counted = new Regex(@"\bTrCount\([^,]+,\s*" + Literal + @"\s*,\s*" + Literal + @"\s*\)");
        var marked = new Regex(@"\bTr\.(?:Text|Content|Header|ToolTip|Title|Unit|Format|Zero|Count)=""([^""]*)""");
        var keys = new List<(string, string)>();
        foreach (var (file, text) in Sources())
        {
            foreach (Match m in single.Matches(text)) keys.Add((file, Unescape(m.Groups[1].Value)));
            foreach (Match m in counted.Matches(text)) keys.Add((file, Unescape(m.Groups[1].Value) + "|" + Unescape(m.Groups[2].Value)));
            if (file.EndsWith(".xaml"))
                foreach (Match m in marked.Matches(text)) keys.Add((file, System.Net.WebUtility.HtmlDecode(m.Groups[1].Value)));
        }
        return keys;
    }

    [Fact]
    public void TheSweepFindsKeys() => Assert.True(Keys().Count > 100, $"only {Keys().Count} keys");

    [Fact]
    public void NoKeyIsInterpolated()
    {
        var bad = Sources().SelectMany(f => Regex.Matches(f.Text, @"\bTr(?:Count)?\([^""\n]*\$""").Select(m => $"{f.File}: {m.Value}")).ToList();
        Assert.True(bad.Count == 0, "an interpolated key never matches its entry: use %@ and arguments:\n" + string.Join("\n", bad));
    }

    [Fact]
    public void EveryKeyIsTranslated()
    {
        var missing = Keys().Where(k => L10n.Lookup(k.Key, Language.Russian) == k.Key && !Untranslatable(k.Key))
            .Select(k => $"{k.File}: {k.Key}").Distinct().OrderBy(s => s).ToList();
        Assert.True(missing.Count == 0, $"Russian is missing {missing.Count}:\n" + string.Join("\n", missing));
    }

    /// <summary>Keys that read the same in Russian (a brand, a symbol).</summary>
    private static bool Untranslatable(string key) => !Regex.IsMatch(key, "[A-Za-z]{2}") || key is "OpenRouter" or "LM Studio" or "Ledgelings";

    [Fact]
    public void NoWindowsKeyRepeatsASharedOne()
    {
        var shared = Shared.In(Language.Russian)!.Strings;
        var both = WindowsStrings.RussianParts.SelectMany(p => p.Value.Keys.Select(k => (p.Key, k))).Where(x => shared.ContainsKey(x.k)).ToList();
        Assert.True(both.Count == 0, "already in the shared Russian (drop it from the Windows part): " + string.Join("\n", both));
        var twice = WindowsStrings.RussianParts.SelectMany(p => p.Value.Keys).GroupBy(k => k).Where(g => g.Count() > 1).Select(g => g.Key).ToList();
        Assert.True(twice.Count == 0, "in two Windows parts: " + string.Join("\n", twice));
    }

    [Fact]
    public void WindowsFormatsMatch()
    {
        var spec = new Regex(@"%(?:\d+\$)?(?:\.\d+)?l?[@dif]");
        string Kinds(string s) => string.Join(",", spec.Matches(s).Select(m => Regex.Replace(m.Value, @"\d+\$", "")).OrderBy(x => x));
        foreach (var (english, russian) in WindowsStrings.In(Language.Russian).Where(p => !p.Key.Contains('|')))
            Assert.True(Kinds(english) == Kinds(russian), $"{english} → {russian}");
        foreach (var (english, russian) in WindowsStrings.In(Language.Russian).Where(p => p.Key.Contains('|')))
            Assert.Equal(3, russian.Split('|').Length);
    }
}

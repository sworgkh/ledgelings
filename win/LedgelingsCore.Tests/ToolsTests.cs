namespace Ledgelings.Core.Tests;

/// <summary>SPEC §7.15 and the settings sidebar: the Tools screen's tiles and keys, the pages and their
/// groups, and the settings search, as the Mac's <c>ToolsScreenTests</c> and <c>SettingsIndexTests</c>.</summary>
public class ToolsTests
{
    // AGENTS rule 4: every tile is a picture, and its tag names its keys.
    [Fact]
    public void EveryTileHasItsPictureAndATooltipNamingItsKey()
    {
        for (var i = 0; i < Tools.All.Count; i++)
        {
            var tool = Tools.All[i];
            Assert.Equal(11, tool.Icon().Count);
            Assert.All(tool.Icon(), row => Assert.Matches("^[.#]{11}$", row));
            Assert.Contains("#", string.Concat(tool.Icon()));
            Assert.Contains($"{i + 1} · Ctrl+Alt+T", tool.Tooltip(i + 1, "Ctrl+Alt+T", on: true));
            Assert.Contains($"({i + 1})", tool.Tooltip(i + 1, null, on: true));
            Assert.Contains(tool.Page().Title(), tool.Tooltip(i + 1, null, on: false));
            Assert.NotEmpty(tool.Title());
            Assert.NotEmpty(tool.Does());
        }
        Assert.Equal(Tools.All.Count, Tools.All.Select(t => string.Concat(t.Icon())).Distinct().Count());
        Assert.Equal(11, Tools.SheetIcon.Count);
    }

    [Fact]
    public void TheCodesAreTheMacsAndUnknownOnesAreDropped()
    {
        Assert.Equal(new[] { "translate", "dictation", "clipHistory", "snippets", "reminder", "readAloud" }, Tools.DefaultShown);
        // A Mac's screenshot tile has no Windows tool: dropped; a doubled one is kept once.
        Assert.Equal(new[] { Tools.Tool.Snippets, Tools.Tool.Translate },
                     Tools.Shown(new[] { "snippets", "screenshot", "translate", "snippets", "nonsense" }));
    }

    [Fact]
    public void TheArrowsMoveInsideTheGrid()
    {
        Assert.Equal(1, Tools.Step(0, Tools.Arrow.Right, 5));
        Assert.Equal(0, Tools.Step(0, Tools.Arrow.Left, 5));
        Assert.Equal(4, Tools.Step(0, Tools.Arrow.Down, 5));
        Assert.Equal(1, Tools.Step(1, Tools.Arrow.Down, 5));
        Assert.Equal(0, Tools.Step(4, Tools.Arrow.Up, 5));
        Assert.Equal(0, Tools.Step(3, Tools.Arrow.Right, 0));
    }

    [Fact]
    public void EveryWordOfTheScreenSpeaksRussian() => Languages.With(Language.Russian, () =>
    {
        foreach (var tool in Tools.All)
        {
            Assert.NotEqual(Languages.With(Language.English, () => tool.Title()), tool.Title());
            Assert.NotEqual(Languages.With(Language.English, () => tool.Does()), tool.Does());
        }
        Assert.DoesNotContain("Off:", Tools.Tool.Translate.Tooltip(1, null, on: false));
    });

    // The sidebar

    [Fact]
    public void ThePagesSitUnderTheMacsFiveGroups()
    {
        Assert.Equal(new[] { SettingsPage.Tools, SettingsPage.Reminders, SettingsPage.Clipboard, SettingsPage.Dictation, SettingsPage.Translate, SettingsPage.ReadAloud },
                     SettingsGroup.Tools.Pages());
        Assert.Equal(new[] { SettingsPage.Costs, SettingsPage.Chats }, SettingsGroup.MoneyAndHistory.Pages());
        Assert.Equal(SettingsPages.All.Count, SettingsPages.Groups.Sum(g => g.Pages().Count));
        Assert.All(SettingsPages.Groups, g => Assert.Equal(11, g.Icon().Count));
    }

    [Fact]
    public void ScriptsNameAPageByItsOwnNameOrAnOldTabs()
    {
        Assert.Equal(SettingsPage.BallGames, SettingsPages.Named("ballgames"));
        Assert.Equal(SettingsPage.Translate, SettingsPages.Named("Translate"));
        Assert.Equal(SettingsPage.Reminders, SettingsPages.Named("productivity"));
        Assert.Equal(SettingsPage.Tools, SettingsPages.Named("tools"));
        Assert.Null(SettingsPages.Named("screenshots"));
    }

    /// <summary>The sidebar finds each page's tab by its header: every page has one, and no tab is left out of the sidebar.</summary>
    [Fact]
    public void EveryPageIsATabOfTheSettingsWindowFoundByItsTitle()
    {
        var root = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(Here())!, ".."));
        var xaml = File.ReadAllText(Path.Combine(root, "Ledgelings", "UI", "SettingsWindow.xaml"));
        var headers = System.Text.RegularExpressions.Regex.Matches(xaml, "<TabItem ui:Tr.Header=\"([^\"]+)\"").Select(m => m.Groups[1].Value).ToList();
        Assert.Equal(SettingsPages.All.Select(p => p.EnglishTitle()).OrderBy(t => t), headers.OrderBy(t => t));
    }

    private static string Here([System.Runtime.CompilerServices.CallerFilePath] string file = "") => file;

    [Fact]
    public void EveryPageAndGroupSpeaksRussian() => Languages.With(Language.Russian, () =>
    {
        foreach (var page in SettingsPages.All) Assert.NotEqual(page.EnglishTitle(), page.Title());
        foreach (var group in SettingsPages.Groups) Assert.NotEqual(Languages.With(Language.English, () => group.Title()), group.Title());
    });

    // The search

    private static readonly SettingsSearch.Section[] Sections =
    {
        new(SettingsPage.Talk, "Talking", new[] { "How often", "Model" }, "They talk when they meet."),
        new(SettingsPage.Translate, "Model", new[] { "Guess the rest of the phrase" }, "Every call shows on Costs as Translation."),
        new(SettingsPage.Voice, "Voice", new[] { "Hear them talk" }),
    };

    [Fact]
    public void ALabelHoldingTheWholeQueryComesBeforeAFooterThatMentionsIt()
    {
        var hits = Languages.With(Language.English, () => SettingsSearch.Search("talk", Sections));
        Assert.Equal(new[] { SettingsPage.Voice, SettingsPage.Talk }, hits.Select(h => h.Page));
        Assert.Equal("Hear them talk", hits[0].Text);
    }

    [Fact]
    public void EveryWordMustBeFoundAndCaseDoesNotMatter()
    {
        Languages.With(Language.English, () =>
        {
            Assert.Equal(SettingsPage.Translate, Assert.Single(SettingsSearch.Search("GUESS phrase", Sections)).Page);
            Assert.Empty(SettingsSearch.Search("guess banana", Sections));
            Assert.Empty(SettingsSearch.Search("   ", Sections));
        });
        Assert.Equal("cafe", SettingsSearch.Fold("Café"));
    }

    [Fact]
    public void ASearchInRussianFindsTheRussianWordsAndTheEnglishStillWorks() => Languages.With(Language.Russian, () =>
    {
        var russian = L10n.Tr("Guess the rest of the phrase");
        Assert.NotEqual("Guess the rest of the phrase", russian);
        var word = russian.Split(' ')[0];
        Assert.Contains(SettingsSearch.Search(word, Sections), h => h.Page == SettingsPage.Translate && h.Text == russian);
        Assert.Contains(SettingsSearch.Search("guess", Sections), h => h.Page == SettingsPage.Translate);
    });
}

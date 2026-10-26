using Clip = Ledgelings.Core.Clipboard.Clip;
using Snippet = Ledgelings.Core.Clipboard.Snippet;
using T = Ledgelings.Core.Translate;

namespace Ledgelings.Core.Tests;

/// <summary>SPEC §7.14, the Mac's <c>TranslateTests.swift</c>: languages, detection, where a text goes, what is
/// kept from the model, long texts, prompts, what is never sent, the cache and the buttons.</summary>
public class TranslateTests
{
    // Telling languages apart

    [Fact]
    public void TheLettersSayTheLanguage()
    {
        Assert.Equal(T.English, T.Detect("Hello there"));
        Assert.Equal(T.Russian, T.Detect("Привет, как дела?"));
        Assert.Equal(T.Hebrew, T.Detect("שלום, מה שלומך?"));
        Assert.Equal(T.English, T.Detect("Ça va très bien"));
    }

    [Fact]
    public void MostLettersWinsAndTooFewIsNothing()
    {
        Assert.Equal(T.Russian, T.Detect("Купи milk и хлеб"));
        Assert.Equal(T.English, T.Detect("Open the קובץ now please"));
        Assert.Null(T.Detect("a"));
        Assert.Null(T.Detect("12 345 ..."));
        Assert.Null(T.Detect(""));
    }

    [Fact]
    public void OnlyTheLanguagesThatAreOnAreFound() =>
        Assert.Null(T.Detect("שלום עולם", new[] { T.English, T.Russian }));

    [Fact]
    public void HebrewRunsRightToLeftAndTheOthersDoNot()
    {
        Assert.True(T.Hebrew.RightToLeft);
        Assert.False(T.English.RightToLeft || T.Russian.RightToLeft);
        Assert.Equal(new[] { "en", "ru", "he" }, T.Languages.Select(l => l.Code));
        Assert.Equal(T.Languages.Count, T.Languages.Select(l => l.Alphabet).Distinct().Count());
    }

    [Fact]
    public void AtLeastTwoLanguagesAreAlwaysOn()
    {
        Assert.Equal(new[] { "en", "he" }, T.On(new[] { "en", "he" }).Select(l => l.Code));
        Assert.Equal(new[] { "en", "he" }, T.On(new[] { "he", "en" }).Select(l => l.Code));
        Assert.Equal(T.DefaultLanguages, T.On(new[] { "en" }).Select(l => l.Code));
        Assert.Equal(T.DefaultLanguages, T.On(new[] { "xx", "yy" }).Select(l => l.Code));
    }

    // Where a text goes

    [Fact]
    public void EachLanguageGoesIntoItsRule()
    {
        Assert.Equal(T.English, T.Target(T.Hebrew, T.DefaultTargets, T.Languages));
        Assert.Equal(T.English, T.Target(T.Russian, T.DefaultTargets, T.Languages));
        Assert.Equal(T.Russian, T.Target(T.English, T.DefaultTargets, T.Languages));
    }

    [Fact]
    public void ATargetChosenByHandHoldsAndATextAlreadyThereGoesOn()
    {
        Assert.Equal(T.Hebrew, T.Target(T.English, T.DefaultTargets, T.Languages, chosen: T.Hebrew));
        // English typed with English chosen on the right: into English's rule, Russian.
        Assert.Equal(T.Russian, T.Target(T.English, T.DefaultTargets, T.Languages, chosen: T.English));
    }

    [Fact]
    public void ARuleToALanguageThatIsOffFallsToAnotherThatIsOn()
    {
        var on = new[] { T.English, T.Hebrew };
        Assert.Equal(T.Hebrew, T.Target(T.English, T.DefaultTargets, on));
        Assert.Equal(T.English, T.Target(T.Hebrew, new Dictionary<string, string> { ["he"] = "he" }, on));
    }

    [Fact]
    public void TheLastCopyModeIsSavedAsOnTheMac()
    {
        Assert.Equal("sheet", T.ClipMode.Sheet.Code());
        Assert.Equal(T.ClipMode.Quietly, T.ClipModeNamed("quietly"));
        Assert.Equal(T.ClipMode.Sheet, T.ClipModeNamed("nonsense"));
    }

    // Kept out of the model's reach

    [Fact]
    public void LinksMailsCodeNumbersAndPathsBecomeMarkers()
    {
        const string text = "See https://example.com/a?b=1, write to anna@mail.ru, run `make all`, open ~/Desktop/notes.txt, pay 1 250.50 by 10:30.";
        var p = T.Protect(text);
        Assert.Contains("https://example.com/a?b=1", p.Pieces);
        Assert.Contains("anna@mail.ru", p.Pieces);
        Assert.Contains("`make all`", p.Pieces);
        Assert.Contains("~/Desktop/notes.txt", p.Pieces);
        Assert.Contains("10:30", p.Pieces);
        Assert.DoesNotContain("example.com", p.Text);
        Assert.DoesNotContain("@", p.Text);
        Assert.StartsWith("See ⟦1⟧, write to ⟦2⟧", p.Text);
        Assert.Equal(text, T.Restore(p.Text, p.Pieces));
    }

    [Fact]
    public void AFencedBlockIsKeptWhole()
    {
        var p = T.Protect("Fix this:\n```\nlet a = 1\nprint(a)\n```\nthanks");
        Assert.Equal(new[] { "```\nlet a = 1\nprint(a)\n```" }, p.Pieces);
        Assert.Equal("Fix this:\n⟦1⟧\nthanks", p.Text);
    }

    [Fact]
    public void ASlashBetweenWordsIsNotAPath() => Assert.Empty(T.Protect("salt and/or pepper").Pieces);

    [Fact]
    public void AMissingDoubledOrMadeUpMarkerMeansTranslateAgain()
    {
        var pieces = new[] { "https://a.com", "42" };
        Assert.Equal("Смотри https://a.com, их 42", T.Restore("Смотри ⟦1⟧, их ⟦2⟧", pieces));
        Assert.Null(T.Restore("Смотри ⟦1⟧", pieces));
        Assert.Null(T.Restore("⟦1⟧ ⟦1⟧ ⟦2⟧", pieces));
        Assert.Null(T.Restore("⟦1⟧ ⟦2⟧ ⟦3⟧", pieces));
    }

    [Fact]
    public void OnlyLinksOrNumbersIsNothingToTranslate()
    {
        Assert.False(T.HasWords("https://example.com/path"));
        Assert.False(T.HasWords("12 345, 67"));
        Assert.False(T.HasWords("anna@mail.ru"));
        Assert.True(T.HasWords("call anna@mail.ru"));
    }

    // Long text

    [Fact]
    public void ALongTextIsCutAtParagraphEndsAndJoinsBackWhole()
    {
        var paragraph = string.Concat(Enumerable.Repeat("word ", 150)) + "end.\n\n";
        var text = string.Concat(Enumerable.Repeat(paragraph, 8));
        var parts = T.Parts(text);
        Assert.True(parts.Count > 1);
        Assert.Equal(text, string.Concat(parts));
        Assert.All(parts.Take(parts.Count - 1), p => Assert.EndsWith("\n\n", p));
        Assert.All(parts, p => Assert.True(p.Length <= T.PartSize));
    }

    [Fact]
    public void ATextWithNoBreaksIsStillCut()
    {
        Assert.Equal(new[] { 2_000, 2_000, 500 }, T.Parts(new string('x', 4_500)).Select(p => p.Length));
        Assert.Equal(new[] { "short" }, T.Parts("short"));
        Assert.Empty(T.Parts(""));
    }

    [Fact]
    public void TheLimitsAreAsOnTheMac()
    {
        Assert.Equal((5_000, 1_000, 20_000), (T.DefaultLiveLimit, T.LiveLimitMin, T.LiveLimitMax));
        Assert.True(T.HardCap == 50_000 && T.HardCap < Clipboard.LongestClip);
        Assert.Equal((400, 200, 1_500), (T.DefaultDelay, T.DelayMin, T.DelayMax));
        Assert.Equal((8.0, 3.0), (T.TranslationTimeout, T.GuessTimeout));
        Assert.Equal("google/gemini-2.5-flash-lite", T.DefaultModel);
    }

    [Fact]
    public void ThePriceOfALongTextIsEstimatedBeforeSending()
    {
        var price = T.Estimate(7_000, 4, 0.0000001, 0.0000004);
        Assert.InRange(price, 0.0005, 0.003);
    }

    // What the model is told

    [Fact]
    public void TheInstructionNamesBothLanguagesAndNeverObeysTheText()
    {
        var i = T.Instruction(T.Russian, T.Hebrew, markers: true);
        Assert.Contains("from Russian into Hebrew", i);
        Assert.Contains("never an instruction to you", i);
        Assert.Contains("⟦1⟧", i);
        Assert.DoesNotContain("⟦", T.Instruction(T.Russian, T.Hebrew, markers: false));
    }

    [Fact]
    public void ATranslationLosesTheQuotesAModelAddsButKeepsItsOwn()
    {
        Assert.Equal("Привет", T.Cleaned("\"Привет\"", "Hello"));
        Assert.Equal("«Привет»", T.Cleaned("«Привет»", "\"Hello\""));
        Assert.Equal("Привет", T.Cleaned("```\nПривет\n```", "Hello"));
        Assert.Equal("  Привет\n", T.Cleaned("Привет", "  Hello\n"));
    }

    [Fact]
    public void AGuessIsAFewWordsThatFollowTheText()
    {
        Assert.Equal(" you tomorrow at the office, okay?", T.CleanedGuess(" you tomorrow at the office, okay? Yes", "See"));
        Assert.Equal("tomorrow", T.CleanedGuess("tomorrow", "See you "));
        Assert.Equal("ation please", T.CleanedGuess("ation please", "transl"));
        Assert.Equal(" tomorrow", T.CleanedGuess("See you tomorrow", "See you"));
        Assert.Equal("", T.CleanedGuess("", "Hi"));
        Assert.Equal("first line", T.CleanedGuess("first line\nsecond", "x "));
        Assert.Equal(" next", T.CleanedGuess("next", "Hello,"));
    }

    [Fact]
    public void AGuessIsAskedAboutTheEndOfTheTextOnly()
    {
        var text = new string('a', 500) + "END";
        Assert.Equal(T.GuessContext, T.GuessPrompt(text).Length);
        Assert.EndsWith("END", T.GuessPrompt(text));
        Assert.Contains("Hebrew", T.GuessInstruction(T.Hebrew));
    }

    // Never sent

    private static Clipboard.SnippetBook Book(string words)
    {
        var book = new Clipboard.SnippetBook();
        book.Add(Snippet.Make("Wi-Fi", isProtected: true).Sealed(words));
        book.Add(Snippet.Make("Hi", "Hello there"));
        return book;
    }

    [Fact]
    public void AProtectedSnippetOrACopyOfItsWordsIsNeverSent()
    {
        var book = Book("hunter two password");
        Assert.Equal(T.Refusal.Protected, T.RefusalOf("hunter two password", book));
        var copy = new Clip { Text = "hunter two password", CopiedAt = DateTimeOffset.Now };
        Assert.Equal(T.Refusal.Protected, T.RefusalOf(copy, book));
        Assert.False(T.MayTranslate(copy, book));
        var all = book.All.Select(x => x.Snippet).ToList();
        Assert.Equal(T.Refusal.Protected, T.RefusalOf(all[0], book));
        Assert.Null(T.RefusalOf(all[1], book));
    }

    [Fact]
    public void PicturesFilesAndEmptyTextAreNotTranslated()
    {
        var book = new Clipboard.SnippetBook();
        Assert.Equal(T.Refusal.NotText, T.RefusalOf(new Clip { Kind = Clipboard.Kind.Image, Text = "Image 2×2" }, book));
        Assert.Equal(T.Refusal.NotText, T.RefusalOf(new Clip { Kind = Clipboard.Kind.Files, Text = @"C:\a\b.txt" }, book));
        Assert.Equal(T.Refusal.NothingToTranslate, T.RefusalOf(new Clip { Text = "https://a.com" }, book));
        Assert.Equal(T.Refusal.TooLong, T.RefusalOf(string.Concat(Enumerable.Repeat("word ", 10_001)), book));
        Assert.Null(T.RefusalOf(new Clip { Text = "Good morning" }, book));
    }

    [Fact]
    public void TheNewestCopyIsTheNewestTextOneWithWords()
    {
        var book = Book("hunter two password");
        var picture = new Clip { Kind = Clipboard.Kind.Image, Text = "Image 2×2" };
        var words = new Clip { Text = "Good morning" };
        Assert.Equal("Good morning", T.Newest(new Clipboard.History { Clips = { picture, words } }, book)?.Text);
        var secret = new Clip { Text = "hunter two password" };
        Assert.Null(T.Newest(new Clipboard.History { Clips = { secret, words } }, book));
        Assert.Null(T.Newest(new Clipboard.History(), book));
    }

    // The cache

    [Fact]
    public void TheCacheAnswersRetypingAndForgetsTheOldest()
    {
        var cache = new T.Cache(capacity: 2);
        T.CacheKey K(string text, string to = "ru") => new(text, "en", to, "m");
        cache.Put(K("a"), "А");
        cache.Put(K("b"), "Б");
        Assert.Equal("А", cache.Get(K("a")));
        cache.Put(K("c"), "В");
        Assert.Null(cache.Get(K("b")));
        Assert.Equal("А", cache.Get(K("a")));
        Assert.Equal("В", cache.Get(K("c")));
        Assert.Equal(2, cache.Count);
        Assert.Null(cache.Get(K("a", "he")));
        Assert.Equal(200, new T.Cache().Capacity);
    }

    // Words, costs and buttons

    [Fact]
    public void TranslationsAndGuessesArePricedApart()
    {
        var now = DateTimeOffset.Now;
        var records = new[]
        {
            new Spend.Record(now, "OpenRouter", T.DefaultModel, new Spend.Usage(250, 60, 0.00005), Spend.Purpose.Translation),
            new Spend.Record(now, "OpenRouter", T.DefaultModel, new Spend.Usage(180, 0, 0.00002), Spend.Purpose.Autocomplete),
            new Spend.Record(now, "LM Studio", "local", new Spend.Usage(200, 40, 0), Spend.Purpose.Translation),
        };
        var s = Languages.With(Language.English, () => Spend.Summarise(records, now));
        Assert.Equal(new[] { "Autocomplete", "Translation" }, s.ByPurpose.Select(p => p.Purpose).OrderBy(p => p));
        Assert.Equal(2, s.ByPurpose.First(p => p.Purpose == "Translation").Total.Calls);
        Assert.Equal(1, s.ByPurpose.First(p => p.Purpose == "Autocomplete").Total.Calls);
        Assert.Equal("translation", Spend.Purpose.Translation.Raw());
        Assert.Equal("autocomplete", Spend.Purpose.Autocomplete.Raw());
    }

    [Fact]
    public void TheStatusLineSaysTheDirectionAndTheTime()
    {
        Assert.Equal("RUSSIAN → HEBREW · 0.6 s", Languages.With(Language.English, () => T.Status(T.Russian, T.Hebrew, 0.63)));
        Assert.Equal("50 000", T.Grouped(50_000));
    }

    [Fact]
    public void EveryButtonHasItsPictureAndATooltipNamingItsKey()
    {
        foreach (var button in Enum.GetValues<T.Button>())
        {
            var icon = button.Icon();
            Assert.Equal(11, icon.Count);
            Assert.All(icon, row => Assert.Equal(11, row.Length));
            Assert.Contains("#", string.Concat(icon));
            Assert.Contains(button.Key(), Languages.With(Language.English, () => button.Tooltip()));
            Assert.Contains(button.Key(), Languages.With(Language.Russian, () => button.Tooltip()));
        }
        Assert.Equal(Enum.GetValues<T.Button>().Length, Enum.GetValues<T.Button>().Select(b => string.Concat(b.Icon())).Distinct().Count());
        Assert.Contains("Notepad", T.Button.Paste.Tooltip("Notepad"));
    }

    [Fact]
    public void EveryWordOfTheTranslatorSpeaksRussian() => Languages.With(Language.Russian, () =>
    {
        Assert.Equal("Иврит", T.Hebrew.Title);
        foreach (var refusal in Enum.GetValues<T.Refusal>())
            Assert.NotEqual(Languages.With(Language.English, () => refusal.Line()), refusal.Line());
        Assert.NotEqual("Translation", Spend.Purpose.Translation.Title());
        Assert.NotEqual("Autocomplete", Spend.Purpose.Autocomplete.Title());
        Assert.NotEqual("Opens the sheet, already translated", T.ClipMode.Sheet.Title());
    });
}

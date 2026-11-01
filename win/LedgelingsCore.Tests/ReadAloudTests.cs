using System.Text.Json;
using Clip = Ledgelings.Core.Clipboard.Clip;
using Snippet = Ledgelings.Core.Clipboard.Snippet;
using R = Ledgelings.Core.ReadAloud;

namespace Ledgelings.Core.Tests;

/// <summary>SPEC §7.16, the Mac's <c>ReadAloudTests.swift</c>: read aloud's part with no sound. The parts and their
/// languages, the presets, what is never sent, the price before sending, the voices that speak a language, the
/// buttons, the file name, the Tools screen tile and the costs line.</summary>
public class ReadAloudTests
{
    // Parts

    [Fact]
    public void AShortTextIsOnePartAndParagraphsEndWithARest()
    {
        var one = R.Parts("Hello there. How are you?");
        Assert.Equal(new[] { new R.Part("Hello there. How are you?", Translate.English, true) }, one);
        var three = R.Parts("First line.\n\nSecond line.\nThird line.");
        Assert.Equal(new[] { "First line.", "Second line.", "Third line." }, three.Select(p => p.Text));
        Assert.True(three.All(p => p.ParagraphEnd), "a line with words on it is a paragraph");
        Assert.Empty(R.Parts("   \n\n  "));
        Assert.Equal(new[] { "Bold and heading" }, R.Parts("**Bold** and *sighs* 🎉 # heading").Select(p => p.Text));     // markdown and emoji are not read out
        Assert.Equal(new[] { "One.", "Two." }, R.Parts("One.\r\nTwo.").Select(p => p.Text));
    }

    [Fact]
    public void ALongParagraphIsCutAfterASentenceAndTheFirstPartIsShort()
    {
        const string sentence = "This sentence is about forty-five letters long. ";
        var text = string.Concat(Enumerable.Repeat(sentence, 60)).Trim();
        var parts = R.Parts(text);
        Assert.True(parts.Count > 3);
        Assert.True(parts[0].Text.Length <= R.FirstPartSize, "the first sound comes quickly");
        Assert.All(parts.Skip(1), p => Assert.True(p.Text.Length <= R.PartSize));
        Assert.All(parts, p => Assert.EndsWith(".", p.Text));                      // cut after a sentence, never inside one
        Assert.True(parts.SkipLast(1).All(p => !p.ParagraphEnd) && parts[^1].ParagraphEnd, "the rest only at the paragraph's end");
        Assert.Equal(text, string.Join(" ", parts.Select(p => p.Text)));          // nothing lost, nothing doubled
    }

    [Fact]
    public void NoSentenceEndMeansACommaThenASpace()
    {
        var words = string.Concat(Enumerable.Repeat("word ", 120)).Trim();
        var parts = R.Parts(words, first: 100, size: 200);
        Assert.All(parts, p => Assert.True(!p.Text.StartsWith(' ') && !p.Text.EndsWith(' ') && !p.Text.EndsWith("wor"), p.Text));
        Assert.Equal(words, string.Join(" ", parts.Select(p => p.Text)));
        var commas = R.Parts(string.Concat(Enumerable.Repeat("one, two, three, four ", 20)), first: 60, size: 120);
        Assert.All(commas.SkipLast(1), p => Assert.EndsWith(",", p.Text));
    }

    [Fact]
    public void EachPartsLanguageIsToldByItsLetters()
    {
        var parts = R.Parts("Good morning, everyone.\nДоброе утро всем.\nבוקר טוב לכולם.\n42 / 17\nAnd back to English.");
        Assert.Equal(new[] { "en", "ru", "he", "he", "en" }, parts.Select(p => p.Language?.Code));      // a part with no letters keeps the language before it
        var forced = R.Parts("Good morning.\nДоброе утро.", forced: Translate.Russian);
        Assert.All(forced, p => Assert.Equal(Translate.Russian, p.Language));                        // a preset's language reads everything as it
    }

    // Never sent

    [Fact]
    public void EmptyProtectedAndTooLongAreRefused()
    {
        var book = Book("hunter two password");
        Assert.Equal(R.Refusal.Empty, R.RefusalOf("", book));
        Assert.Equal(R.Refusal.Empty, R.RefusalOf("  \n\t ", book));
        Assert.Equal(R.Refusal.Empty, R.RefusalOf("🎉🎉", book));                     // nothing sayable left
        Assert.Equal(R.Refusal.Protected, R.RefusalOf("hunter two password", book));  // typed by hand
        var copy = new Clip { Text = "hunter two password", CopiedAt = DateTimeOffset.Now };
        Assert.Equal(R.Refusal.Protected, R.RefusalOf(copy, book));                   // a copy of its words
        var all = book.All.Select(x => x.Snippet).ToList();
        Assert.Equal(R.Refusal.Protected, R.RefusalOf(all[0], book));
        Assert.Null(R.RefusalOf(all[1], book));                                       // an ordinary snippet may be read
        Assert.Equal(R.Refusal.TooLong, R.RefusalOf(new string('a', R.HardCap + 1), book));
        Assert.Null(R.RefusalOf("Read me, please.", book));
        Assert.Null(R.RefusalOf("42", book));                                         // a number can be read
        Assert.Equal(R.Refusal.Empty, R.RefusalOf(new Clip { Kind = Clipboard.Kind.Image, Text = "Image 2×2" }, book));
    }

    private static Clipboard.SnippetBook Book(string words)
    {
        var book = new Clipboard.SnippetBook();
        book.Add(Snippet.Make("Wi-Fi", isProtected: true).Sealed(words));
        book.Add(Snippet.Make("Hi", "Hello there"));
        return book;
    }

    // Presets

    [Fact]
    public void TheShippedPresetsAreTheOnesAskedFor()
    {
        var p = R.DefaultPresets;
        Assert.Equal(new[] { "Narrator", "Quick skim", "Bedtime", "Robot", "Russian" }, p.Select(x => x.Name));
        Assert.True(p[0].Character.Length == 0 && p[0].Speed == 1 && p[0].Id == R.DefaultPresetId, "the narrator, calm, 1×, is the default");
        Assert.Equal(1.6, p[1].Speed);
        Assert.True(p[2].Character == "Zed" && p[2].Speed == 0.8 && p[2].Voice.Length == 0, "Zed's sleepy voice, cast from his persona");
        Assert.True(p[3].Character == "Unit 7" && p[3].Speed == 1.1);
        Assert.True(p[4].Language == "ru" && p[4].ForcedLanguage == Translate.Russian);
        Assert.All(p, x => Assert.True(x.Engine == R.Engine.OpenRouter && x.ModelOrDefault == R.DefaultModel));
        Assert.Equal(p.Count, p.Select(x => x.Id).Distinct().Count());
        // The Mac's ids, so a preset is the same one on both.
        Assert.Equal("6E61722D-0000-4000-8000-000000000001", R.IdString(R.DefaultPresetId));
        Assert.Equal("6E61722D-0000-4000-8000-000000000005", R.IdString(p[4].Id));
    }

    [Fact]
    public void ASavedPresetIsReadLenientlyAndClamped()
    {
        const string json = """[{"id":"6E61722D-0000-4000-8000-0000000000AA","name":"  Fast ","engine":"warp","speed":9,"pause":-1,"language":"xx"},{"name":"Bare"}]""";
        var presets = JsonSerializer.Deserialize<List<R.Preset>>(json)!;
        Assert.True(presets[0].Name == "Fast" && presets[0].Engine == R.Engine.OpenRouter && presets[0].Speed == 2 && presets[0].Pause == 0 && presets[0].Language.Length == 0);
        Assert.Equal("6E61722D-0000-4000-8000-0000000000AA", R.IdString(presets[0].Id));
        Assert.True(presets[1].Speed == 1 && presets[1].Pause == R.DefaultPause && presets[1].Character.Length == 0);
        var written = JsonSerializer.Serialize(presets);
        Assert.Equal(presets, JsonSerializer.Deserialize<List<R.Preset>>(written));       // what is saved is read back the same
        // The Mac's field names, so a preset reads the same on both.
        Assert.Contains("\"id\":\"6E61722D-0000-4000-8000-0000000000AA\"", written);
        foreach (var key in new[] { "name", "engine", "model", "voice", "character", "speed", "pause", "language" }) Assert.Contains($"\"{key}\":", written);
        Assert.Contains("\"engine\":\"openRouter\"", written);
        Assert.Equal(R.Engine.System, JsonSerializer.Deserialize<R.Preset>("""{"engine":"system"}""")!.Engine);
        Assert.Throws<JsonException>(() => JsonSerializer.Deserialize<List<R.Preset>>("[42]"));
    }

    [Fact]
    public void CleanedKeepsEachPresetOnceAndNeverNone()
    {
        Assert.Equal(R.DefaultPresets, R.Cleaned(Array.Empty<R.Preset>()));
        var one = R.DefaultPresets[0];
        Assert.Single(R.Cleaned(new[] { one, one }));
        var many = Enumerable.Range(0, 14).Select(i => new R.Preset { Name = $"P{i}" });
        Assert.Equal(R.MostPresets, R.Cleaned(many).Count);                     // each keeps a number key
        Assert.Equal("My preset", R.FreeName("My preset", R.DefaultPresets));
        Assert.Equal("Narrator 2", R.FreeName("Narrator", R.DefaultPresets));
    }

    [Fact]
    public void ThePaceStepsAndLabels()
    {
        Assert.True(R.Step(1, 1) == 1.1 && R.Step(1, -1) == 0.9);
        Assert.True(R.Step(1.95, 1) == 2 && R.Step(0.5, -1) == 0.5, "inside the range");
        Assert.True(R.SpeedLabel(1) == "1×" && R.SpeedLabel(1.6) == "1.6×");
        Assert.True(R.Clock(65.9) == "1:05" && R.Clock(0) == "0:00" && R.Clock(-3) == "0:00");
    }

    [Fact]
    public void TheSheetsReaderAndPaceGoIntoThePreset()
    {
        var narrator = R.Chosen(R.DefaultPresets[0], "", 1.3);
        Assert.True(narrator.Voice == "Charon" && narrator.Speed == 1.3);
        var blorp = R.Chosen(R.DefaultPresets[0], "Blorp", 1.3);
        Assert.True(blorp.Character == "Blorp" && blorp.Voice.Length == 0, "another reader gets a voice cast for it");
        Assert.Equal("Zed", R.NextReader(new[] { "", "Zed", "Mossy" }, ""));
        Assert.Equal("", R.NextReader(new[] { "", "Zed", "Mossy" }, "Mossy"));
        Assert.Equal("", R.NextReader(Array.Empty<string>(), "Gone"));
        var tag = Languages.With(Language.English, () => R.Tag(R.DefaultPresets[2], 3));
        Assert.Equal("Bedtime: Zed, 0.8× (Ctrl+3)", tag);
        Assert.Equal("Narrator: Charon, 1× (Ctrl+1)", Languages.With(Language.English, () => R.Tag(R.DefaultPresets[0], 1)));
    }

    // The price before sending

    [Fact]
    public void ThePriceIsEstimatedFromTheListPrice()
    {
        // Gemini 3.8 Flash Lite TTS: $0.50 per M in, $6 per M of sound out, 25 sound tokens a second.
        var gemini = R.Estimate(1_500, 0.5e-6, 6e-6)!.Value;
        Assert.True(gemini > 0.01 && gemini < 0.02, "about a cent for a page");
        var kokoro = R.Estimate(1_500, 0.62e-6, 0)!.Value;
        Assert.True(Math.Abs(kokoro - 0.00093) < 0.00001, "per character only");
        Assert.Null(R.Estimate(100, null, null));
        Assert.True(Math.Abs(R.Seconds(150) - 10) < 0.001 && Math.Abs(R.Seconds(150, 2) - 5) < 0.001);
    }

    // Voices that speak a language

    [Fact]
    public void AVoiceIsFoundForEachLanguageOrNone()
    {
        var gemini = new[] { "Kore", "Puck", "Charon" };
        foreach (var language in Translate.Languages) Assert.Equal(gemini, R.VoicesSpeaking(gemini, language));      // unmarked voices speak every language
        var kokoro = new[] { "af_bella", "am_adam", "bf_emma", "ef_dora", "jf_alpha" };
        Assert.Equal(new[] { "af_bella", "am_adam", "bf_emma" }, R.VoicesSpeaking(kokoro, Translate.English));
        Assert.Empty(R.VoicesSpeaking(kokoro, Translate.Russian));                                                   // Kokoro has no Russian: Windows reads it
        var mai = new[] { "en-US-Harper:MAI-Voice-2.1-Flash", "ru-RU-Lev:MAI-Voice-2.1-Flash", "de-DE-Klaus:MAI-Voice-2.1-Flash" };
        Assert.Equal(new[] { "ru-RU-Lev:MAI-Voice-2.1-Flash" }, R.VoicesSpeaking(mai, Translate.Russian));
        Assert.Empty(R.VoicesSpeaking(mai, Translate.Hebrew));
        Assert.Equal(new[] { "he-IL-Avri:X" }, R.VoicesSpeaking(new[] { "he-IL-Avri:X", "en-US-Ava:X" }, Translate.Hebrew));
    }

    // Buttons, the file, the tile, the costs

    /// <summary>AGENTS rule 4: every control is a picture, and its tag names its key.</summary>
    [Fact]
    public void EveryButtonHasItsPictureAndATooltipNamingItsKey()
    {
        foreach (var button in R.Buttons)
        {
            Assert.Equal(11, button.Icon().Count);
            Assert.All(button.Icon(), row => Assert.Matches("^[.#]{11}$", row));
            Assert.Contains("#", string.Concat(button.Icon()));
            Assert.False(string.IsNullOrEmpty(button.Key()));
            Assert.Contains($"({button.Key()})", Languages.With(Language.English, () => button.Tooltip()));
            Assert.Contains($"({button.Key()})", Languages.With(Language.Russian, () => button.Tooltip()));
        }
        var sheet = R.Buttons.Where(b => b != R.Button.ReadRow).ToList();
        Assert.Equal(sheet.Count, sheet.Select(b => string.Concat(b.Icon())).Distinct().Count());     // each its own picture
        Assert.Equal(sheet.Count, sheet.Select(b => b.Tooltip()).Distinct().Count());
        Assert.Equal(R.Speaker, R.Button.ReadRow.Icon());
    }

    [Fact]
    public void TheFileIsNamedByItsTimeAndFirstWords() => Languages.With(Language.English, () =>
    {
        var date = new DateTime(2026, 11, 1, 14, 32, 5);
        Assert.Equal("Read aloud 2026-11-01 14.32.05 – Hello the world said Zed softly.m4a",
                     R.FileName("Hello: the/world? said \"Zed\" softly and then slept", date, R.Format.M4a));
        Assert.Equal("Read aloud 2026-11-01 14.32.05.wav", R.FileName("🎉", date, R.Format.Wav));
        Assert.Equal(R.Format.Wav, R.FormatNamed("wav"));
        Assert.Null(R.FormatNamed("ogg"));
    });

    [Fact]
    public void TheToolsScreenHasReadAloudAndAnArrangedListGetsItOnce()
    {
        Assert.True(Tools.Tool.ReadAloud.Page() == SettingsPage.ReadAloud && Tools.Tool.ReadAloud.Icon().SequenceEqual(R.Speaker));
        Assert.Contains("readAloud", Tools.DefaultShown);
        Assert.Equal(Tools.Tool.ReadAloud, Tools.All[^1]);                         // last, so every older tile keeps its number key
        Assert.Equal(new[] { "dictation", "translate", "readAloud" }, Tools.WithNew(new[] { "dictation", "translate" }, known: null));     // at the end of an arranged list
        Assert.Equal(new[] { "dictation" }.Concat(Tools.DefaultShown.Where(c => c != "dictation")),
                     Tools.WithNew(new[] { "dictation", "nonsense" }, known: new[] { "dictation" }));                                     // every tool not known then
        Assert.Equal(new[] { "dictation" }, Tools.WithNew(new[] { "dictation" }, known: Tools.DefaultShown));                            // switched off after it was known, it stays off
        Assert.True(SettingsPage.ReadAloud.Group() == SettingsGroup.Tools && SettingsPages.Named("readaloud") == SettingsPage.ReadAloud);
        // Ctrl+Alt+Shift+R: Ctrl+Alt+R is Windows' Add a Reminder.
        Assert.Equal(new Shortcut(0x52, ShortcutModifiers.Control | ShortcutModifiers.Option | ShortcutModifiers.Shift), Shortcut.ReadAloud);
    }

    [Fact]
    public void EveryReadingIsPricedUnderReadAloud()
    {
        var now = DateTimeOffset.Now;
        var records = new[]
        {
            new Spend.Record(now, "OpenRouter", R.DefaultModel, new Spend.Usage(80, 300, 0.0019), Spend.Purpose.ReadAloud),
            new Spend.Record(now, "OpenRouter", R.DefaultModel, new Spend.Usage(0, 0, null), Spend.Purpose.ReadAloud),
        };
        var s = Languages.With(Language.English, () => Spend.Summarise(records, now));
        Assert.Equal(new[] { "Read aloud" }, s.ByPurpose.Select(p => p.Purpose));
        Assert.Equal(2, s.ByPurpose[0].Total.Calls);         // a call whose price never came is still counted
        Assert.Equal("readAloud", Spend.Purpose.ReadAloud.Raw());
    }

    [Fact]
    public void ReadAloudSpeaksRussian() => Languages.With(Language.Russian, () =>
    {
        Assert.True(Spend.Purpose.ReadAloud.Title() != "Read aloud" && SettingsPage.ReadAloud.Title() != "Read aloud");
        Assert.True(Tools.Tool.ReadAloud.Title() != "READ ALOUD" && Tools.Tool.ReadAloud.Does() != "Paste text and hear it read");
        foreach (var button in R.Buttons) Assert.NotEqual(Languages.With(Language.English, () => button.Tooltip()), button.Tooltip());
        Assert.All(R.DefaultPresets, p => Assert.NotEqual(p.Name, p.Title));            // the shipped names are translated
        foreach (var refusal in Enum.GetValues<R.Refusal>()) Assert.NotEqual(Languages.With(Language.English, () => refusal.Line()), refusal.Line());
        foreach (var engine in Enum.GetValues<R.Engine>()) Assert.NotEqual(Languages.With(Language.English, () => engine.Title()), engine.Title());
        Assert.Contains("Ctrl+3", R.Tag(R.DefaultPresets[2], 3));
        Assert.DoesNotContain("заготов", R.Tag(R.DefaultPresets[2], 3) + L10n.Tr("Preset") + L10n.Tr("My preset"));   // a preset is a пресет, never a snippet
    });
}

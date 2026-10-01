using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Ledgelings.Core.Tests;

/// <summary>SPEC §1.2: the characters in Russian, as the Mac's LinesRussianTests,
/// LettersRussianTests, TeaGardenRussianTests, CastingRussianTests, VoicesLanguageTests
/// and PromptsRussianTests check them: the same structure as the English, every
/// placeholder and parser label kept, and each part following the current language.</summary>
public class RussianTests
{
    private static readonly Shared Ru = Shared.In(Language.Russian)!;

    private static HashSet<string> Placeholders(string text) => Regex.Matches(text, @"\{[A-Za-z]+\}").Select(m => m.Value).ToHashSet();
    private static List<string> PlaceholderList(string text) => Regex.Matches(text, @"\{[A-Za-z]+\}").Select(m => m.Value).OrderBy(s => s, StringComparer.Ordinal).ToList();
    private static bool Cyrillic(string text) => Regex.IsMatch(text, "[А-Яа-яЁё]");
    private static T Ru_<T>(Func<T> body) => Languages.With(Language.Russian, body);
    private static T En<T>(Func<T> body) => Languages.With(Language.English, body);

    // MARK: Lines

    private static Dictionary<string, int> TagCounts(Script script) =>
        script.Conversations.GroupBy(c => string.Join(",", c.Tags.OrderBy(t => t, StringComparer.Ordinal))).ToDictionary(g => g.Key, g => g.Count());

    [Fact]
    public void TheRussianScriptParsesWithTheSameKindsOfTags()
    {
        var english = Script.Parse(Script.EnglishBuiltInText);
        var russian = Script.Parse(Script.BuiltInTextIn(Language.Russian));
        var en = TagCounts(english);
        var ru = TagCounts(russian);
        Assert.True(en.Keys.ToHashSet().SetEquals(ru.Keys));
        foreach (var (tags, count) in en)
            Assert.True(ru.GetValueOrDefault(tags) >= count * 3 / 4, $"{tags}: {ru.GetValueOrDefault(tags)} Russian blocks for {count} English");
        foreach (var c in russian.Conversations)
        {
            Assert.InRange(c.Lines.Count, 2, 4);
            foreach (var line in c.Lines)
            {
                Assert.True(line.Length <= 120, line);
                Assert.DoesNotContain("{", Script.Fill(line, "x", "y", "z", "w"));
                if (line.Contains("{flower}")) Assert.Contains("flower", c.Tags);
                if (line.Contains("{holiday}")) Assert.Contains("holiday", c.Tags);
            }
        }
        Assert.Equal(Ru.Script, Ru_(() => Script.BuiltInText));
    }

    [Fact]
    public void AGivenFlowerIsNamedInTheLanguage()
    {
        Assert.Equal("Держи: мак.", Ru_(() => Script.Fill("Держи: {flower}.", "a", "b", "poppy")));
        Assert.Equal("Here: poppy.", En(() => Script.Fill("Here: {flower}.", "a", "b", "poppy")));
        Assert.Equal("цветок", Ru_(() => Script.Fill("{flower}", "a", "b", null)));
    }

    [Fact]
    public void ParseErrorsReadInRussian()
    {
        var e = Assert.Throws<Script.ParseException>(() => Ru_(() => Script.Parse("[mood]\nhi")));
        Assert.True(Cyrillic(e.Message) && e.Message.Contains("mood"), e.Message);
        var none = Assert.Throws<Script.ParseException>(() => Ru_(() => Script.Parse("# only a comment")));
        Assert.True(Cyrillic(none.Message), none.Message);
    }

    [Fact]
    public void TheRussianAgentPromptKeepsTheFormat()
    {
        var cast = new[] { new Character("Blocky", "Grumpy."), new Character("Pip", "Cheerful.") };
        var english = En(() => Script.AgentPrompt(cast, 30));
        var russian = Ru_(() => Script.AgentPrompt(cast, 30));
        Assert.NotEqual(english, russian);
        Assert.True(russian.Contains("30") && russian.Contains("Blocky") && russian.Contains("Grumpy."));
        Assert.True(Placeholders(russian).SetEquals(Placeholders(english)));
        foreach (var tag in new[] { "[flower]", "[night]", "[holiday]", "[night, flower]" }) Assert.Contains(tag, russian);
        Assert.Contains("по-русски", russian);
        Assert.False(Cyrillic(En(() => Script.AgentPrompt(Array.Empty<Character>()))));
    }

    /// <summary>Every prompt the shared export carries, with the English it stands for.</summary>
    public static IEnumerable<object[]> Prompts() => new (string Key, string English, Func<string> Current)[]
    {
        ("system", Banter.EnglishSystemPrompt, () => Banter.DefaultSystemPrompt),
        ("line", Banter.EnglishLinePrompt, () => Banter.DefaultLinePrompt),
        ("reply", Banter.EnglishReplyPrompt, () => Banter.DefaultReplyPrompt),
        ("plot", Bonds.EnglishPlotPrompt, () => Bonds.DefaultPlotPrompt),
        ("plotSystem", Bonds.EnglishPlotSystemPrompt, () => Bonds.PlotSystemPrompt),
        ("planeNote", Letters.EnglishNotePrompt, () => Letters.NotePrompt),
        ("planeReply", Letters.EnglishReplyPrompt, () => Letters.ReplyPrompt),
        ("planeMusing", Letters.EnglishMusingPrompt, () => Letters.MusingPrompt),
        ("teaSystem", Tea.EnglishSystemPrompt, () => Tea.SystemPrompt),
        ("teaStory", Tea.EnglishStoryPrompt, () => Tea.StoryPrompt),
        ("teaReply", Tea.EnglishReplyPrompt, () => Tea.ReplyPrompt),
        ("complaint", Complaints.EnglishPrompt, () => Complaints.Prompt),
        ("reminder", Reminders.EnglishNotePrompt, () => Reminders.NotePrompt),
    }.Select(p => new object[] { p.Key, p.English, p.Current });

    [Theory]
    [MemberData(nameof(Prompts))]
    public void EveryPromptFollowsTheLanguageAndKeepsItsPlaceholders(string key, string english, Func<string> current)
    {
        var russian = Ru_(current);
        Assert.Equal(Ru.Prompts[key], russian);
        Assert.NotEqual(english, russian);
        Assert.True(Cyrillic(russian), key);
        Assert.True(Placeholders(russian).SetEquals(Placeholders(english)), key);
        Assert.Equal(english, En(current));
    }

    [Fact]
    public void TheRussianPlotPromptKeepsTheLabelsTheParserReads()
    {
        var prompt = Bonds.PlotPromptIn(Language.Russian);
        Assert.True(prompt.Contains("\nBOND: ") && prompt.Contains("\nPLOT: "));
        Assert.StartsWith("Не пиши их разговоры", prompt);
        Assert.Equal(new Bonds.Written("давние соперники", "спорят, чей угол"), Bonds.Parse("BOND: давние соперники\nPLOT: спорят, чей угол"));
    }

    [Fact]
    public void TheRelationshipAndDurationsReadInRussian()
    {
        var bond = new Bonds.Bond(new[] { "Blocky", "Pip" }) { Together = 3 * 3600, Summary = "друзья", Plot = new Bonds.Plot("секрет", 2) };
        Languages.With(Language.Russian, () =>
        {
            Assert.Equal("совсем недолго", Bonds.Duration(20));
            Assert.Equal("1 минута", Bonds.Duration(60));
            Assert.Equal("3 минуты", Bonds.Duration(3 * 60));
            Assert.Equal("5 часов", Bonds.Duration(3600 * 5));
            Assert.Equal("22 часа", Bonds.Duration(3600 * 22));
            Assert.Equal("21 день", Bonds.Duration(86400 * 21));
            var context = Bonds.Context(bond, "Blocky", "Pip");
            Assert.True(context.Contains("Pip") && context.Contains("3 часа") && context.Contains("часть 1 из 2"), context);
            var values = Bonds.PlotValues(new Bonds.Bond(new[] { "A", "B" }), ("A", "k", "p"), ("B", "k", "p"), 3);
            Assert.Equal("(пока ничего)", values["recent"]);
            Assert.True(Cyrillic(values["bond"]) && Cyrillic(values["lastPlot"]));
            var blocky = Banter.DefaultCharacters[0];
            var spoken = Bonds.PlotValues(new Bonds.Bond(new[] { "A", "B" }), ("A", Banter.DefaultKind, blocky.Persona), ("B", "k", "My own words."), 3);
            Assert.Equal("маленькое квадратное существо", spoken["speakerKind"]);
            Assert.True(Cyrillic(spoken["speakerPersona"]));
            Assert.Equal("My own words.", spoken["listenerPersona"]);
        });
        Assert.Equal("3 minutes", En(() => Bonds.Duration(180)));
        Assert.Equal("1 day", En(() => Bonds.Duration(86400)));
    }

    [Fact]
    public void EveryCharacterComplainsAndRemindsInRussian()
    {
        Assert.True(Ru.ComplaintLines.Keys.ToHashSet().SetEquals(Complaints.EnglishLines.Keys));
        Assert.True(Ru.ReminderNotes.Keys.ToHashSet().SetEquals(Reminders.EnglishNotes.Keys));
        foreach (var (name, lines) in Complaints.EnglishLines)
        {
            Assert.Equal(lines.Length, Ru.ComplaintLines[name].Length);
            Assert.True(Ru.ComplaintLines[name].Any(l => l.Contains("{times}")), $"{name} never says how many times");
        }
        foreach (var (name, notes) in Reminders.EnglishNotes)
        {
            Assert.Equal(notes.Count, Ru.ReminderNotes[name].Length);
            Assert.All(Ru.ReminderNotes[name], n => Assert.Contains("{reminder}", n));
        }
        Assert.All(Ru.RemindersAnyone, n => Assert.Contains("{reminder}", n));
        Languages.With(Language.Russian, () =>
        {
            var rng = new Random(1);
            Assert.True(Cyrillic(Complaints.Line("Ruth", 5, rng)));
            Assert.True(Cyrillic(Complaints.Line("Someone New", 5, rng)));
            Assert.Contains("Размяться", Reminders.Note("Unit 7", "Размяться", rng));
            Assert.Same(Ru.ComplaintsAnyone, Complaints.Anyone);
            Assert.Equal(Ru.ReminderNotes["Blocky"], Reminders.Notes["Blocky"]);
        });
        Languages.With(Language.English, () =>
        {
            Assert.Same(Complaints.EnglishLines, Complaints.Lines);
            Assert.Same(Reminders.EnglishAnyone, Reminders.Anyone);
        });
    }

    [Fact]
    public void RemindersSayWhenInRussian()
    {
        var zone = TimeZoneInfo.FindSystemTimeZoneById("Europe/Moscow");
        DateTimeOffset At(int d, int h, int m = 5) => new(new DateTime(2026, 9, d, h, m, 0), TimeSpan.FromHours(3));
        var now = At(26, 12, 0);
        Languages.With(Language.Russian, () =>
        {
            Assert.Equal("Сегодня 14:05", Reminders.When(At(26, 14), now, zone));
            Assert.Equal("Завтра 09:05", Reminders.When(At(27, 9), now, zone));
            Assert.Equal("Вчера 18:05", Reminders.When(At(25, 18), now, zone));
            var later = Reminders.Day(At(30, 9), now, zone);
            Assert.True(later.Contains("30") && later.Contains("сент"), later);
            var daily = new Reminders.Reminder("x", At(27, 9), Reminders.Repeat.Daily);
            Assert.Equal("Каждый день, следующее: Завтра 09:05", daily.Describe(now, zone));
        });
        Assert.StartsWith("Wed 30 Sep", En(() => Reminders.Day(At(30, 9), now, zone)));
    }

    // MARK: The almanac

    [Fact]
    public void EveryHolidayHasARussianName()
    {
        foreach (var feast in Almanac.FeastNames)
        {
            var russian = Almanac.HolidayName(feast, Language.Russian);
            Assert.True(russian != feast && Cyrillic(russian), feast);
            Assert.Equal(feast, Almanac.HolidayName(feast, Language.English));
        }
        Assert.True(Ru.Holidays.Keys.ToHashSet().SetEquals(Almanac.FeastNames), "a name for a holiday that does not exist");
    }

    [Fact]
    public void TheAlmanacSpeaksRussian()
    {
        var zone = TimeZoneInfo.FindSystemTimeZoneById("Asia/Jerusalem");
        DateTimeOffset At(int m, int d, int h, int min = 0)
        {
            var wall = new DateTime(2026, m, d, h, min, 0, DateTimeKind.Unspecified);
            return new DateTimeOffset(wall, zone.GetUtcOffset(wall));
        }
        var jewish = new[] { Almanac.Faith.Jewish };
        Languages.With(Language.Russian, () =>
        {
            var evening = At(9, 28, 22, 40);
            var sentence = Almanac.Sentence(evening, new Almanac.Awareness(faiths: jewish, lookAhead: 0), zone);
            Assert.StartsWith("У человека за этим компьютером сейчас понедельник, 28 сентября 2026, поздний вечер (22:40).", sentence);
            Assert.True(sentence.Contains("Суккот") && sentence.Contains("3-й день"), sentence);
            Assert.Equal("Суккот", Almanac.Today(evening, jewish.ToHashSet(), zone));
            var ahead = Almanac.Sentence(At(12, 2, 10), new Almanac.Awareness(false, false, jewish, 3), zone);
            Assert.Equal("Ханука (иудейский праздник) — через 3 дня.", ahead);
            Assert.Equal("Иудейский", Almanac.Faith.Jewish.Title());
        });
        Assert.Equal("Sukkot", En(() => Almanac.Today(At(9, 28, 22, 40), jewish.ToHashSet(), zone)));
    }

    // MARK: Letters

    private static void SameShape(Letters.Voice english, Shared.LetterVoice russian, string name)
    {
        Assert.Equal(english.Topics.Count, russian.Topics.Length);
        foreach (var (kind, en, ru) in new[] { ("notes", english.Notes, russian.Notes), ("musings", english.Musings, russian.Musings), ("replies", english.Replies, russian.Replies) })
        {
            Assert.True(en.Count == ru.Length, $"{name}: {kind}");
            foreach (var (e, r) in en.Zip(ru))
            {
                Assert.True(Placeholders(r).SetEquals(Placeholders(e)), $"{name} {kind}: {r}");
                Assert.True(r != e, $"{name} {kind} is still English: {r}");
                Assert.True(r.Split(' ').Length <= 22, $"{name} is too wordy: {r}");
            }
        }
    }

    [Fact]
    public void EveryCharacterWithEnglishLettersHasRussianOnes()
    {
        Assert.True(Ru.LetterVoices.Keys.ToHashSet().SetEquals(Letters.EnglishVoices.Keys));
        foreach (var (name, english) in Letters.EnglishVoices) SameShape(english, Ru.LetterVoices[name], name);
        SameShape(Letters.EnglishAnyone, Ru.LettersAnyone, "anyone");
    }

    [Fact]
    public void TheLettersFollowTheLanguage()
    {
        Languages.With(Language.Russian, () =>
        {
            Assert.Equal(Ru.LetterVoices["Blocky"].Notes, Letters.VoiceOf("Blocky").Notes);
            Assert.Equal(Ru.LettersAnyone.Musings, Letters.VoiceOf("Nobody we know").Musings);
            Assert.Same(Letters.Anyone, Letters.VoiceOf("Nobody we know"));
            Assert.True(Cyrillic(Letters.Note("Zed", "Pip", new Random(2))));
            Assert.Equal("*читает* «Привет.» — Dot", Letters.Reading("Привет.", "Dot"));
        });
        Languages.With(Language.English, () =>
        {
            Assert.Same(Letters.EnglishVoices, Letters.Voices);
            Assert.Same(Letters.EnglishAnyone, Letters.Anyone);
        });
    }

    // MARK: Tea, the garden, the flowers

    [Fact]
    public void EveryCharacterTellsAndAnswersAsOftenInRussian()
    {
        foreach (var (english, russian, what) in new[] { (Tea.EnglishStories, Ru.TeaStories, "stories"), (Tea.EnglishReplies, Ru.TeaReplies, "replies") })
        {
            Assert.True(russian.Keys.ToHashSet().SetEquals(english.Keys), what);
            foreach (var (name, en) in english)
            {
                var ru = russian[name];
                Assert.True(ru.Length == en.Length, $"{name} {what}");
                Assert.True(ru.Distinct().Count() == ru.Length, $"{name} tells one twice");
                foreach (var (e, r) in en.Zip(ru)) Assert.True(PlaceholderList(e).SequenceEqual(PlaceholderList(r)), $"{name}: {r}");
            }
        }
        Assert.Equal(Tea.EnglishAnyoneStories.Count, Ru.TeaAnyoneStories.Length);
        Assert.Equal(Tea.EnglishAnyoneReplies.Count, Ru.TeaAnyoneReplies.Length);
        foreach (var (e, r) in Tea.EnglishAnyoneReplies.Zip(Ru.TeaAnyoneReplies)) Assert.True(PlaceholderList(e).SequenceEqual(PlaceholderList(r)), r);
    }

    [Fact]
    public void TheRussianIsWhatTheyTellInRussian()
    {
        Languages.With(Language.Russian, () =>
        {
            var rng = new Random(3);
            Assert.Contains(Tea.Story("Blocky", new HashSet<string>(), rng), Ru.TeaStories["Blocky"]);
            Assert.Contains(Tea.Story("Someone New", new HashSet<string>(), rng), Ru.TeaAnyoneStories);
            var reply = Tea.Reply("Pip", "Zed", rng);
            Assert.Contains(Ru.TeaReplies["Pip"], r => Banter.Render(r, new Dictionary<string, string> { ["other"] = "Zed" }) == reply);
            Assert.Contains("чай", Tea.Transcript(Array.Empty<ChatLog.Line>()));
        });
        Languages.With(Language.English, () =>
        {
            Assert.Equal(Tea.EnglishStories["Blocky"], Tea.Stories["Blocky"]);
            Assert.Contains("just been poured", Tea.Transcript(Array.Empty<ChatLog.Line>()));
        });
    }

    [Fact]
    public void TheTeaPromptsAskOnlyForWhatTheyFill()
    {
        foreach (var key in new[] { "teaSystem", "teaStory", "teaReply" })
            foreach (var name in Placeholders(Ru.Prompts[key])) Assert.Contains(name[1..^1], Tea.Placeholders);
        Assert.Contains("по-русски", Ru.Prompts["teaSystem"]);
    }

    [Fact]
    public void EveryFlowerHasARussianName()
    {
        foreach (var flower in Gifts.Flowers)
            Assert.True(Ru.Flowers.TryGetValue(flower, out var name) && name.Length > 0 && name != flower, flower);
        Assert.True(Ru.Flowers.Keys.ToHashSet().SetEquals(Gifts.Flowers));
        Assert.Equal(Gifts.Flowers.Count, Ru.Flowers.Values.Distinct().Count());
        Assert.Equal("мак", Ru_(() => Gifts.Name("poppy")));
        Languages.With(Language.English, () => Assert.All(Gifts.Flowers, f => Assert.Equal(f, Gifts.Name(f))));
    }

    [Fact]
    public void ThePlantingSentenceIsRussianButTheRulesStillReadEnglish()
    {
        var blocky = Banter.DefaultCharacters.First(c => c.Name == "Blocky");
        var temper = En(() => Garden.TemperOf(blocky.Persona, Banter.DefaultKind));
        // The persona stays English data: the rules read it the same in either language.
        var russian = Ru_(() => Garden.TemperOf(blocky.Persona, Banter.DefaultKind));
        Assert.True(russian.Equals(temper) && temper.Likes[0] == Garden.Place.Floor);
        Languages.With(Language.Russian, () =>
        {
            foreach (var place in Enum.GetValues<Garden.Place>()) Assert.True(Cyrillic(Garden.Phrase(place)), place.ToString());
            var described = Garden.Describe(temper);
            Assert.True(described.Contains("на нижнем краю") && described.Contains(" или "), described);
            Assert.Equal("Сразу, там, где стоит.", Garden.Describe(new Garden.Temper(0, Array.Empty<Garden.Place>())));
        });
    }

    // MARK: Casting and voices

    [Fact]
    public void RussianWordsSayHowSomeoneSounds()
    {
        var old = Casting.TraitsOf("Старый философ. Говорит медленно, часто вздыхает.", "маленькое квадратное существо");
        Assert.True(old.Want(Casting.Tag.Old) > 0 && old.Speed < 1);
        Assert.True(Casting.TraitsOf("Буквальный и точный.", "маленький угловатый робот с антенной").Want(Casting.Tag.Robot) > 0);
        Assert.True(Casting.TraitsOf("Она весёлая и быстрая.", "").Want(Casting.Tag.Female) > 0);
        Assert.True(Casting.TraitsOf("Он ворчит.", "").Want(Casting.Tag.Male) > 0);
        Assert.Equal(Casting.Traits.Neutral, Casting.TraitsOf("Обычный.", ""));
    }

    private static string Root([CallerFilePath] string here = "") => Path.GetFullPath(Path.Combine(Path.GetDirectoryName(here)!, "..", ".."));

    /// <summary>Every persona and species kind the app ships: the built-in cast and every sheet's.</summary>
    private static List<string> ShippedPersonas()
    {
        var texts = Banter.DefaultCharacters.Select(c => c.Persona).Append(Banter.DefaultKind).ToList();
        foreach (var file in Directory.EnumerateFiles(Path.Combine(Root(), "Sources", "Ledgelings", "Resources", "sprites"), "*.json"))
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(file));
            if (doc.RootElement.TryGetProperty("kind", out var kind)) texts.Add(kind.GetString()!);
            if (doc.RootElement.TryGetProperty("cast", out var cast))
                texts.AddRange(cast.EnumerateArray().Select(c => c.GetProperty("persona").GetString()!));
        }
        return texts.Distinct().ToList();
    }

    [Fact]
    public void EveryShippedPersonaIsSpokenInRussian()
    {
        var shipped = ShippedPersonas();
        Assert.True(shipped.Count > 20);
        Languages.With(Language.Russian, () =>
        {
            foreach (var text in shipped) Assert.True(Cyrillic(Banter.Spoken(text)), text);
            Assert.Equal("маленькое квадратное существо", Banter.Spoken(Banter.DefaultKind));
            Assert.Equal("My own words.", Banter.Spoken("My own words."));
        });
        Assert.Equal(shipped[0], En(() => Banter.Spoken(shipped[0])));
    }

    /// <summary>The Russian of a shipped persona gives the same voice as its English, near enough:
    /// the same kinds of voice wanted, robot and old on both or neither.</summary>
    [Fact]
    public void RussianPersonasCastLikeTheirEnglish()
    {
        var loose = new[] { Casting.Tag.Male, Casting.Tag.Female, Casting.Tag.Deep, Casting.Tag.Young, Casting.Tag.Bright, Casting.Tag.Soft, Casting.Tag.Whisper };
        foreach (var english in ShippedPersonas().Where(p => p != Banter.DefaultKind))
        {
            var russian = L10n.Lookup(english, Language.Russian);
            var en = Casting.TraitsOf(english, "");
            var ru = Casting.TraitsOf(russian, "");
            Assert.True(en.Wants.Keys.All(k => ru.Wants.ContainsKey(k) || loose.Contains(k)), $"{english} → {russian}");
            Assert.True(en.Wants.ContainsKey(Casting.Tag.Robot) == ru.Wants.ContainsKey(Casting.Tag.Robot), russian);
            Assert.True(en.Wants.ContainsKey(Casting.Tag.Old) == ru.Wants.ContainsKey(Casting.Tag.Old), russian);
        }
    }

    [Fact]
    public void EnglishIsEnglishFirstAsBefore()
    {
        var lists = new[]
        {
            new[] { "af_bella", "jf_alpha", "bm_george" }, new[] { "flux-kit-en", "flux-x-de" }, new[] { "Puck", "Kore" },
            new[] { "tara", "leah", "jess", "leo", "dan", "mia", "zac", "zoe", "pierre" },
        };
        foreach (var voices in lists) Assert.Equal(Voices.EnglishFirst(voices), Voices.InLanguage(voices, Language.English));
    }

    [Fact]
    public void RussianVoicesAreKeptWhenTheNamesSayWhichTheyAre()
    {
        var mixed = new[] { "af_bella", "ru_dmitri", "ru-RU-SvetlanaNeural", "Russian_Girl", "en_paul_happy", "voice-ru", "pierre" };
        Assert.Equal(new[] { "ru_dmitri", "ru-RU-SvetlanaNeural", "Russian_Girl", "voice-ru" }, Voices.InLanguage(mixed, Language.Russian));
        // No Russian marks: every voice is kept, as unmarked voices speak every language.
        Assert.Equal(new[] { "alloy", "echo", "nova" }, Voices.InLanguage(new[] { "alloy", "echo", "nova" }, Language.Russian));
        Assert.Equal(new[] { "af_bella", "bm_george" }, Voices.InLanguage(new[] { "af_bella", "bm_george" }, Language.Russian));
        Assert.Empty(Voices.InLanguage(Array.Empty<string>(), Language.Russian));
    }

    [Fact]
    public void LanguageFirstFollowsTheCurrentLanguage()
    {
        var voices = new[] { "en_paul", "ru_olga" };
        Assert.Equal(new[] { "ru_olga" }, Ru_(() => Voices.LanguageFirst(voices)));
        Assert.Equal(new[] { "en_paul" }, En(() => Voices.LanguageFirst(voices)));
    }

    [Fact]
    public void AVoiceOfAnotherLanguageDoesNotSpeakIt()
    {
        var voices = new[] { "en_paul", "ru_olga", "ru_ivan" };
        Assert.False(Voices.Speaks("en_paul", Language.Russian, voices));
        Assert.True(Voices.Speaks("ru_olga", Language.Russian, voices));
        Assert.True(Voices.Speaks("ru_olga(2)+ru_ivan(1)", Language.Russian, voices), "a blend of Russian voices");
        Assert.False(Voices.Speaks("ru_olga+en_paul", Language.Russian, voices));
        // Nothing marked, or nothing known: any voice will do.
        Assert.True(Voices.Speaks("alloy", Language.Russian, new[] { "alloy", "echo" }));
        Assert.True(Voices.Speaks("anything", Language.Russian, Array.Empty<string>()));
        Assert.True(Voices.Speaks("en_paul", Language.English, voices));
    }

    [Fact]
    public void CyrillicIsSaidAsWritten()
    {
        Assert.Equal("Ну ладно. Бери потолок.", Voices.Speakable("*вздыхает* Ну ладно. 🌸 Бери **потолок**."));
        Assert.Equal("Ёжик, привет — это 5:00!", Voices.Speakable("Ёжик, привет — это 5:00!"));
    }

    // MARK: Costs, sprites

    [Fact]
    public void EveryFeatureHasARussianTitleOnTheCostsTab()
    {
        foreach (var purpose in Enum.GetValues<Spend.Purpose>())
        {
            var russian = Ru_(() => purpose.Title());
            Assert.True(russian != En(() => purpose.Title()) && Cyrillic(russian), purpose.ToString());
        }
        Assert.True(Cyrillic(Ru_(() => Spend.UnlabelledPurpose)));
        Assert.Equal("Earlier, unlabelled", En(() => Spend.UnlabelledPurpose));
    }

    [Fact]
    public void TheSpritePromptKeepsTheFormat()
    {
        var english = En(() => SpriteText.Prompt(new[] { "..o." }));
        var russian = Ru_(() => SpriteText.Prompt(new[] { "..o." }));
        Assert.NotEqual(english, russian);
        foreach (var key in new[] { "name:", "kind:", "colour:", "character:", "pose: idle", "pose: walk-0", ". o b l s k x" }) Assert.Contains(key, russian);
        Assert.Contains(string.Join(", ", SpriteText.Poses), russian);
        Assert.Contains(Ru_(() => SpriteText.DescribePlaceholder), russian);
        Assert.True(Cyrillic(Ru_(() => SpriteText.DescribePlaceholder)));
    }

    [Fact]
    public void SpriteErrorsReadInRussian()
    {
        var e = Assert.Throws<SpriteText.ParseException>(() => Ru_(() => SpriteText.Parse("pose: idle")));
        Assert.True(Cyrillic(e.Message), e.Message);
    }

    [Fact]
    public void TheLineMemoryNoteIsInTheLanguage()
    {
        var note = Ru_(() => LineMemory.Note(new[] { "Привет." }));
        Assert.True(Cyrillic(note.Split('\n')[0]) && note.EndsWith("- Привет."), note);
    }
}
